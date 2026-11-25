#!/usr/bin/env python3
"""Offline pilot: associate saved OCR boxes without confirming game state."""
import argparse
import hashlib
import json
import math
import re
import zipfile
from pathlib import Path
import champions_ocr_replay_v6 as v6

SCHEMA = 'ocr-association-v8'
ROWS = (.56, .66, .765, .865)


def validate_boxes(boxes):
    for b in boxes:
        x0,y0,x1,y1 = b['xyxy']
        if not (all(math.isfinite(v) for v in (x0,y0,x1,y1)) and 0<=x0<x1<=1 and 0<=y0<y1<=1):
            raise ValueError('invalid box geometry')
        if not isinstance(b['text'],str): raise ValueError('invalid box text')


def unique_matching(edges):
    # Only accept mutual singleton associations. Ambiguity is not a tie-break.
    return [(a, bs[0]) for a,bs in edges.items() if len(bs)==1 and sum(bs[0] in other for other in edges.values())==1]


def command(boxes, move_evidence, species):
    species = set(species)
    move_by_raw = {e['raw']:e for e in move_evidence}
    moves, pp, opponent = [], [], []
    for row,y in enumerate(ROWS,1):
        ids = [i for i,b in enumerate(boxes) if .73<=v6.center(b)[0]<=.83 and abs(v6.center(b)[1]-y)<=.022]
        # PP current and maximum can be distinct OCR boxes; never infer a missing maximum.
        left = [i for i,b in enumerate(boxes) if .86<=v6.center(b)[0]<=.92 and abs(v6.center(b)[1]-(y-.015))<=.018 and re.fullmatch(r'[0-9]{1,2}',v6.norm(b['text']))]
        right = [i for i,b in enumerate(boxes) if .86<=v6.center(b)[0]<=.94 and abs(v6.center(b)[1]-(y+.017))<=.018 and re.fullmatch(r'/[0-9]{1,2}',v6.norm(b['text']))]
        values=[]
        for i,j in unique_matching({i:[j for j in right if 0<v6.center(boxes[j])[1]-v6.center(boxes[i])[1]<=.05] for i in left}):
            cur=int(v6.norm(boxes[i]['text'])); mx=int(v6.norm(boxes[j]['text'])[1:])
            if 0<=cur<=mx and mx>0: values.append({'current':cur,'maximum':mx,'box_ids':[i,j]})
        moves.append({'row':row,'box_ids':ids,'names':[move_by_raw.get(boxes[i]['text'],{'raw':boxes[i]['text'],'status':'UNKNOWN'}) for i in ids],'confirmed':False})
        pp.append({'row':row,'pairs':values,'unpaired_current_box_ids':[i for i in left if not any(i in v['box_ids'] for v in values)],'confirmed':False})
    names=[i for i,b in enumerate(boxes) if .55<=v6.center(b)[0]<=.95 and .025<=v6.center(b)[1]<=.085 and v6.norm(b['text']) in species]
    hp=[i for i,b in enumerate(boxes) if .55<=v6.center(b)[0]<=.95 and .085<=v6.center(b)[1]<=.145 and re.fullmatch(r'[0-9]{1,3}%',v6.norm(b['text'])) and int(v6.norm(b['text'])[:-1])<=100]
    edges={i:[j for j in hp if abs(v6.center(boxes[j])[0]-v6.center(boxes[i])[0])<=.085 and 0<v6.center(boxes[j])[1]-v6.center(boxes[i])[1]<=.09] for i in names}
    for i,j in unique_matching(edges):
        opponent.append({'name':boxes[i]['text'],'displayed_percent':int(v6.norm(boxes[j]['text'])[:-1]),'box_ids':[i,j],'confirmed':False})
    return {'moves':moves,'pp':pp,'opponent_hp':opponent,'confirmed':False}


def replay(report, prior, species):
    sources={f['case']:f for f in report['frames']}
    if len(sources)!=len(report['frames']): raise ValueError('duplicate frame case')
    old={(r['case'],r['method']):r for r in prior['results']}
    if len(old)!=len(prior['results']): raise ValueError('duplicate prior result')
    groups={}
    seen=set()
    for r in report['results']:
        if r['status']!='EXECUTED_UNSCORED': continue
        key=(r['case'],r['method'])
        if key in seen: raise ValueError('duplicate OCR pass')
        seen.add(key)
        f=sources[r['case']]; p=old[key]; boxes=r['boxes_original_normalized']
        validate_boxes(boxes)
        if p['raw_boxes']!=boxes: raise ValueError('prior evidence differs from report')
        # Same video frame is one correlated group, regardless of number of OCR passes.
        group_id=f"{report['video_sha256']}:{f['frame_index']}:{f['sha256']}"
        g=groups.setdefault(group_id,{'frame_index':f['frame_index'],'frame_sha256':f['sha256'],'passes':[],'independent_evidence_count':None})
        a={'method':r['method'],'raw_boxes':boxes,'screen':p['screen'],'message_candidates':p['message_candidates'],'own_hp_candidates':p['hp_candidates'],'event_emission':'DISABLED'}
        if p['screen']['candidate']=='COMMAND_MENU' and r['method']=='full_frame':
            a['command']=command(boxes,p['move_candidates'],species)
        g['passes'].append(a)
    if seen!=set(old): raise ValueError('prior/report coverage differs')
    return {'schema':SCHEMA,'source_groups':groups,'confirmed_events':0}


def self_test():
    def b(t,x,y): return {'text':t,'xyxy':[x-.01,y-.01,x+.01,y+.01]}
    bs=[b('技A',.78,.56),b('効果表示',.77,.598),b('12',.885,.545),b('/12',.896,.577),b('8',.89,.75),b('種族A',.64,.06),b('100%',.69,.115)]
    e=command(bs,[{'raw':'技A','status':'EXACT_TEXT'}],['種族A'])
    checks={
        'unique_pair':unique_matching({1:[2],3:[4]})==[(1,2),(3,4)],
        'shared_box_rejected':unique_matching({1:[2],3:[2]})==[],
        'multiple_candidates_rejected':unique_matching({1:[2,3]})==[],
        'effect_label_excluded':e['moves'][0]['box_ids']==[0],
        'split_pp':e['pp'][0]['pairs'][0]['current']==12 and e['pp'][0]['pairs'][0]['maximum']==12,
        'missing_max_not_inferred':not e['pp'][2]['pairs'],
        'opponent_hp':e['opponent_hp'][0]['displayed_percent']==100,
        'no_dictionary_no_hp':not command(bs,[],[])['opponent_hp'],
        'invalid_percentage':not command([b('種族A',.64,.06),b('101%',.69,.115)],[],['種族A'])['opponent_hp'],
        'ambiguous_name_rejected':not command(bs+[b('種族B',.68,.06)],[],['種族A','種族B'])['opponent_hp'],
        'no_confirmation':not e['confirmed'] and all(not x['confirmed'] for x in e['moves']+e['pp']+e['opponent_hp']),
    }
    try: validate_boxes([{'text':'x','xyxy':[0,0,float('nan'),1]}]); checks['nan_rejected']=False
    except ValueError: checks['nan_rejected']=True
    return checks


def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--archive',type=Path);p.add_argument('--expected-sha256');p.add_argument('--prior',type=Path);p.add_argument('--species',type=Path);p.add_argument('--out',type=Path);a=p.parse_args()
    tests=self_test(); out={'tests':tests,'pass':sum(tests.values()),'total':len(tests)}
    if a.archive:
        if not (a.expected_sha256 and a.prior and a.species):p.error('archive requires expected SHA-256, prior replay and species labels')
        if hashlib.sha256(a.archive.read_bytes()).hexdigest()!=a.expected_sha256:raise ValueError('archive SHA mismatch')
        with zipfile.ZipFile(a.archive) as z:
            report=json.loads(z.read('report.json'))
            if report['schema']!='ocr-diagnostic-pilot-v5':raise ValueError('unsupported report')
            for f in report['frames']:
                if hashlib.sha256(z.read(f['image'])).hexdigest()!=f['sha256']:raise ValueError('image SHA mismatch')
        labels=json.loads(a.species.read_text()); prior=json.loads(a.prior.read_text())
        out.update(replay(report,prior,labels));out['archive_sha256']=a.expected_sha256;out['prior_sha256']=hashlib.sha256(a.prior.read_bytes()).hexdigest();out['labels_sha256']=hashlib.sha256(a.species.read_bytes()).hexdigest()
    s=json.dumps(out,ensure_ascii=False,indent=2)+'\n'
    if a.out:
        with a.out.open('x',encoding='utf8') as f:f.write(s)
    else: print(s,end='')
    return int(not all(tests.values()))

if __name__=='__main__':raise SystemExit(main())
