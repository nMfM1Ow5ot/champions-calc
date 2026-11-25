#!/usr/bin/env python3
"""Research-only replay: verify raw OCR and recompute, never trust prior candidates."""
import argparse
import hashlib
import json
import math
import zipfile
from pathlib import Path
import champions_ocr_replay_v6 as v6
import champions_ocr_evidence_v7 as v7
import champions_ocr_association_v8 as v8


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def normalized(obs, rect):
    x, y, w, h = obs['box_xywh_bottom_left']
    x0, y0, x1, y1 = rect
    W, H = x1-x0, y1-y0
    c = obs['confidence']
    require(all(math.isfinite(q) for q in (x,y,w,h,c)) and 0<=x and 0<=y and w>0 and h>0
            and x+w<=1+1e-9 and y+h<=1+1e-9 and 0<=c<=1, 'invalid raw observation')
    return {'text':obs['text'], 'confidence':c,
            'xyxy':[(x0+x*W)/1920,(y0+(1-y-h)*H)/1080,(x0+(x+w)*W)/1920,(y0+(1-y)*H)/1080]}


def analyze(boxes, species, moves, method):
    v8.validate_boxes(boxes)
    species = set(map(v6.norm,species))
    result = v7.analyze(boxes, species, moves, method)
    screen = result['screen']
    m = screen.get('markers',{})
    conflict = m.get('status_tabs') and m.get('command') and (m.get('inspect') or m.get('movehelp'))
    if conflict:
        screen['candidate'] = 'CONFLICT'
        result['message_candidates'] = []
    # Rebuild own HP associations as a mutual-singleton graph over box IDs.
    result['hp_candidates'] = []
    if screen['candidate'] == 'COMMAND_MENU':
        names = [i for i,b in enumerate(boxes) if .08<=v6.center(b)[0]<=.48 and .86<=v6.center(b)[1]<=.93 and v6.norm(b['text']) in species]
        hp = [i for i,b in enumerate(boxes) if .08<=v6.center(b)[0]<=.48 and .92<=v6.center(b)[1]<=.99 and v6.hp_candidates(b['text'])]
        edges = {i:[j for j in hp if abs(v6.center(boxes[j])[0]-v6.center(boxes[i])[0])<=.075 and 0<v6.center(boxes[j])[1]-v6.center(boxes[i])[1]<=.085] for i in names}
        result['hp_candidates'] = [{'nearby_name':boxes[i]['text'],'raw':boxes[j]['text'],'candidates':v6.hp_candidates(boxes[j]['text']),'box_ids':[i,j],'confirmed':False} for i,j in v8.unique_matching(edges)]
        result['command'] = v8.command(boxes,result['move_candidates'],species)
    return result


def replay(report, species, moves):
    require(report['schema']=='ocr-diagnostic-pilot-v5','unsupported report schema')
    frames = {f['case']:f for f in report['frames']}
    require(len(frames)==len(report['frames'])==len({f['frame_index'] for f in frames.values()}),'duplicate frame identity')
    groups = {}
    seen = set()
    for r in report['results']:
        if r['status']!='EXECUTED_UNSCORED':
            continue
        key = (r['case'],r['method'])
        require(key not in seen,'duplicate OCR pass')
        seen.add(key)
        f = frames[r['case']]
        rect = r['rect']
        x0,y0,x1,y1 = rect
        require(0<=x0<x1<=1920 and 0<=y0<y1<=1080,'invalid rect')
        require(r['method'] in ('full_frame','direct_crop'),'unknown method')
        if r['method']=='full_frame':
            require(rect==[0,0,1920,1080] and r['image']==f['image'],'full-frame source mismatch')
        boxes = [normalized(o,rect) for o in r['observations']]
        require(boxes==r['boxes_original_normalized'],'stored normalized boxes differ from raw observations')
        g = groups.setdefault(str(f['frame_index']),{'frame_sha256':f['sha256'],'passes':[]})
        g['passes'].append({'method':r['method'],**analyze(boxes,species,moves,r['method'])})
    return {'schema':'ocr-guard-v9','video_sha256':report['video_sha256'],'source_groups':groups,'confirmed_events':0}


def load_archive(path, expected):
    require(sha(path.read_bytes())==expected,'archive SHA mismatch')
    with zipfile.ZipFile(path) as z:
        require(len(z.namelist())==len(set(z.namelist())),'duplicate ZIP member')
        r=json.loads(z.read('report.json'))
        for f in r['frames']:
            require(sha(z.read(f['image']))==f['sha256'],'frame SHA mismatch')
        for p in r['results']:
            if p['status']=='EXECUTED_UNSCORED':
                require(bool(z.read(p['image'])),'empty OCR input image')
    return r


def self_test():
    def b(t,x,y): return {'text':t,'xyxy':[x-.01,y-.01,x+.01,y+.01]}
    menu=[b('COMMAND',.8,.27),b('様子を見る',.83,.4)]
    names=['リザードン','フラエッテ','ガオガエン']
    run=lambda boxes:analyze(boxes,names,[],'full_frame')
    a=b('リザードン',.2,.90); h=b('153/153',.2,.95); h2=b('100/153',.23,.96)
    send=[b('Aはフラエッテと',.30,.76),b('ガオガエンを繰り出した！',.30,.81)]
    conflict=run(menu+[b('能力 ステータス',.4,.14)]+send)
    tests={
        'one_name_two_hp_rejected':not run(menu+[a,h,h2])['hp_candidates'],
        'valid_hp_preserved':len(run(menu+[a,h])['hp_candidates'])==1,
        'one_hp_two_names_rejected':not run(menu+[a,b('ガオガエン',.23,.90),h])['hp_candidates'],
        'conflict_explicit':conflict['screen']['candidate']=='CONFLICT',
        'conflict_blocks_message':not conflict['message_candidates'],
        'send_candidate_preserved':len(run(send)['message_candidates'])==1,
        'no_state_emission':run(send)['event_emission']=='DISABLED',
    }
    return tests


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path);p.add_argument('--expected-sha256');p.add_argument('--dictionary',type=Path);p.add_argument('--out',type=Path)
    a=p.parse_args(); checks=self_test(); out={'tests':checks,'pass':sum(checks.values()),'total':len(checks)}
    if a.archive:
        if not a.expected_sha256 or not a.dictionary:p.error('archive requires SHA-256 and dictionary')
        raw=a.dictionary.read_bytes();d=json.loads(raw)
        out.update(replay(load_archive(a.archive,a.expected_sha256),d['species'].values(),d['moves'].values()))
        out['dictionary_sha256']=sha(raw)
    s=json.dumps(out,ensure_ascii=False,indent=2)+'\n'
    if a.out:
        with a.out.open('x',encoding='utf8') as f:f.write(s)
    else:print(s,end='')
    return int(not all(checks.values()))

if __name__=='__main__':raise SystemExit(main())
