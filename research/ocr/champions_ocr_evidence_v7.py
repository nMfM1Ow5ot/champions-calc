#!/usr/bin/env python3
"""Research-only structured OCR evidence. No confirmed events or state updates."""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path
import champions_ocr_replay_v6 as v6


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1]+1, row[j]+1, row[j-1]+(x != y)))
        row = nxt
    return row[-1]


def name_evidence(raw, words):
    s = v6.norm(raw)
    limit = 0 if len(s) < 3 else 1 if len(s) < 6 else 2
    ranked = sorted((distance(s, w), w) for w in set(map(v6.norm, words)) if w and abs(len(s)-len(w)) <= limit)
    ranked = [r for r in ranked if r[0] <= limit]
    best = ranked[0][0] if ranked else None
    ties = [w for d, w in ranked if d == best]
    return {'raw': raw, 'best_distance': best, 'best_candidates': ties, 'candidate_count': len(ranked),
            'status': 'UNKNOWN' if best is None else 'EXACT_TEXT' if best == 0 else 'AMBIGUOUS' if len(ties)>1 else 'SUGGESTED', 'confirmed': False}


def analyze(boxes, species, moves, method):
    screen = v6.screen_evidence(boxes) if method == 'full_frame' else {'candidate':'NOT_APPLICABLE'}
    msg = [b for b in boxes if 375/1920 <= v6.center(b)[0] < 1200/1920 and 785/1080 <= v6.center(b)[1] < 915/1080]
    keep, ruby = v6.ruby_candidates(msg)
    rows = v6.join_rows(keep)
    text = v6.norm(''.join(rows))
    matches, hp, move = [], [], []
    if screen['candidate'] == 'COMMAND_MENU':
        names = [(b, name_evidence(b['text'], species)) for b in boxes if .08 <= v6.center(b)[0] <= .48 and .86 <= v6.center(b)[1] <= .93]
        names = [(b, n) for b,n in names if n['status']=='EXACT_TEXT']
        for b in boxes:
            x,y = v6.center(b)
            if not (.08<=x<=.48 and .92<=y<=.99): continue
            vals = v6.hp_candidates(b['text'])
            if not vals: continue
            parents = [n['raw'] for p,n in names if abs(x-v6.center(p)[0])<=.075 and 0<y-v6.center(p)[1]<=.085]
            if len(parents)==1:
                hp.append({'raw':b['text'],'candidates':vals,'nearby_name':parents[0],'confirmed':False})
        for b in boxes:
            x,y = v6.center(b)
            if .73<=x<=.83 and any(abs(y-r)<=.035 for r in (.56,.66,.765,.865)):
                move.append(name_evidence(b['text'], moves))
    elif screen['candidate'] == 'UNKNOWN':
        m = re.fullmatch(r'(.+?)は(.+?)と(.+?)を繰り出した[!！]?',text)
        if m:
            matches.append({'kind':'SEND_OUT_CANDIDATE','names':[name_evidence(m[2],species),name_evidence(m[3],species)],'confirmed':False})
    return {'screen':screen,'raw_boxes':boxes,'rows':rows,'ruby_candidates':ruby,'message_candidates':matches,
            'hp_candidates':hp,'move_candidates':move,'event_emission':'DISABLED'}


def self_test():
    def b(t,x,y,w=.05,h=.02): return {'text':t,'xyxy':[x,y,x+w,y+h]}
    sp=['フラエッテ','ガオガエン','リザードン','フシギバナ']; mv=['ウェザーボール','シャドーボール']
    menu=[b('COMMAND',.78,.27),b('様子を見る',.83,.40)]
    send=[b('Aはプラエッテと',.21,.75,.2),b('ガオガエンを繰り出した！',.21,.80,.25)]
    def run(boxes,method='full_frame'):return analyze(boxes,sp,mv,method)
    test={
      'distance':distance('プラエッテ','フラエッテ')==1,
      'name_candidate':name_evidence('プラエッテ',sp)['best_candidates']==['フラエッテ'],
      'tie':name_evidence('アカイ',['アカウ','アカエ'])['status']=='AMBIGUOUS',
      'unmatched':name_evidence('不明',sp)['status']=='UNKNOWN',
      'exact_not_confirmed':not name_evidence('ガオガエン',sp)['confirmed'],
      'send_candidate':len(run(send)['message_candidates'])==1,
      'menu_blocks_send':not run(send+menu)['message_candidates'],
      'crop_not_screen':not run(send,'direct_crop')['message_candidates'],
      'unrelated_number':not run(menu+[b('1537153',.85,.94)])['hp_candidates'],
      'no_name_no_hp':not run(menu+[b('1537153',.18,.94)])['hp_candidates'],
      'nearby_hp':run(menu+[b('リザードン',.15,.89),b('1537153',.18,.94)])['hp_candidates'][0]['candidates']==['153/153'],
      'two_names_ambiguous':not run(menu+[b('リザードン',.14,.89),b('フシギバナ',.22,.89),b('1537153',.18,.94)])['hp_candidates'],
      'move_candidate':run(menu+[b('ウエザーポール',.75,.65)])['move_candidates'][0]['best_candidates']==['ウェザーボール'],
      'no_state_update':run(send)['event_emission']=='DISABLED',
    }
    return test


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('archive',type=Path,nargs='?');p.add_argument('--dict-dir',type=Path);a=p.parse_args()
    checks=self_test();out={'schema':'ocr-evidence-v7','tests':checks,'pass':sum(checks.values()),'total':len(checks)}
    if a.archive:
        if not a.dict_dir: p.error('--dict-dir is required for replay')
        path=a.dict_dir/'names_ja.json';raw=path.read_bytes();d=json.loads(raw)
        out['dictionary_sha256']=hashlib.sha256(raw).hexdigest()
        with zipfile.ZipFile(a.archive) as z:
            r=json.loads(z.read('report.json'))
            if r['schema']!='ocr-diagnostic-pilot-v5':raise ValueError('unexpected schema')
            for f in r['frames']:
                if hashlib.sha256(z.read(f['image'])).hexdigest()!=f['sha256']:raise ValueError('image mismatch')
            out['results']=[{'case':x['case'],'method':x['method'],**analyze(x['boxes_original_normalized'],d['species'].values(),d['moves'].values(),x['method'])} for x in r['results'] if x['status']=='EXECUTED_UNSCORED']
    print(json.dumps(out,ensure_ascii=False,indent=2));return int(not all(checks.values()))

if __name__=='__main__':raise SystemExit(main())
