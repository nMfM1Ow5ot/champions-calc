#!/usr/bin/env python3
"""Offline evidence replay, standard library only; no OCR or state updates."""
import argparse
import hashlib
import json
import re
import statistics
import unicodedata
import zipfile
from pathlib import Path


def norm(text):
    return ''.join(unicodedata.normalize('NFKC', text).split())


def center(box):
    x0, y0, x1, y1 = box['xyxy']
    return (x0+x1)/2, (y0+y1)/2


def height(box):
    return box['xyxy'][3]-box['xyxy'][1]


def ruby_candidates(boxes):
    if not boxes:
        return [], []
    hs = sorted(height(b) for b in boxes)
    med = hs[len(hs)//2]
    keep, removed = [], []
    for b in boxes:
        x0,y0,x1,y1 = b['xyxy']
        ruby = med > 0 and height(b) < .62*med and any(
            height(o) >= .8*med and o['xyxy'][0] < x1 and x0 < o['xyxy'][2]
            and (abs(o['xyxy'][1]-y1) <= .02 or
                 (y0 >= o['xyxy'][1]-.005 and y1 <= o['xyxy'][1]+.55*height(o)))
            for o in boxes)
        (removed if ruby else keep).append(b)
    return keep, removed


def join_rows(boxes):
    # Group by vertical center, then sort each row horizontally. All existing
    # members must agree, preventing a chain of bridges merging separate lines.
    rows = []
    for b in sorted(boxes, key=lambda b:(center(b)[1], b['xyxy'][0])):
        def compatible(row):
            return all(abs(center(b)[1]-center(o)[1]) <= .45*min(height(b),height(o)) for o in row)
        eligible = [row for row in rows if compatible(row)]
        if eligible:
            min(eligible, key=lambda r:abs(center(b)[1]-statistics.median(center(o)[1] for o in r))).append(b)
        else:
            rows.append([b])
    rows.sort(key=lambda r:statistics.median(center(o)[1] for o in r))
    return [' '.join(b['text'] for b in sorted(row,key=lambda b:b['xyxy'][0])) for row in rows]


def screen_evidence(boxes):
    # Labels must co-occur in their observed UI zones. UNKNOWN is not battle.
    def hits(label, rect):
        return any(label in norm(b['text']) and rect[0]<=center(b)[0]<=rect[2]
                   and rect[1]<=center(b)[1]<=rect[3] for b in boxes)
    command = hits('COMMAND',(.68,.16,.98,.34))
    inspect = hits('様子を見る',(.68,.30,.98,.47))
    movehelp = hits('技の説明',(.68,.40,.98,.55))
    status = hits('能力',(.30,.10,.74,.22)) and hits('ステータス',(.30,.10,.74,.22))
    cmd = command and (inspect or movehelp)
    label = 'UNKNOWN' if cmd == status else ('COMMAND_MENU' if cmd else 'STATUS_MENU')
    return {'candidate':label,'markers':{'command':command,'inspect':inspect,'movehelp':movehelp,'status_tabs':status},'event_emission':'DISABLED'}


def hp_candidates(text):
    s = norm(text)
    # Only propose slash substitutions; do not infer a missing digit, apply a
    # game-state update, or assume a unique legal HP maximum.
    if re.fullmatch(r'[0-9]{1,3}/[0-9]{1,3}',s):
        parts = [s]
    elif re.fullmatch(r'[0-9]{3,7}',s):
        parts = [s[:i]+'/'+s[i+1:] for i,c in enumerate(s) if c=='7' and 1<=i<=3 and 1<=len(s)-i-1<=3]
    else:
        parts = []
    return sorted(set(p for p in parts if 0<=int(p.split('/')[0])<=int(p.split('/')[1]) and int(p.split('/')[1])>0))


def replay(report):
    results=[]
    for r in report['results']:
        if r['status']!='EXECUTED_UNSCORED':
            continue
        boxes=r['boxes_original_normalized']
        msg=[b for b in boxes if 375/1920<=center(b)[0]<1200/1920 and 785/1080<=center(b)[1]<915/1080]
        keep, removed=ruby_candidates(msg)
        results.append({'case':r['case'],'method':r['method'],'rows':join_rows(keep),
            'ruby_candidates':[b['text'] for b in removed], 'screen':screen_evidence(boxes) if r['method']=='full_frame' else {'candidate':'NOT_APPLICABLE'},
            'hp_candidates':[{'raw':b['text'],'candidates':hp_candidates(b['text'])} for b in boxes if hp_candidates(b['text'])], 'event_emission':'DISABLED'})
    return results


def self_test():
    def b(t,x,y,w=.1,h=.03):return {'text':t,'xyxy':[x,y,x+w,y+h]}
    cases=[
        ('row jitter',join_rows([b('右',.4,.79),b('左',.2,.80)])==['左 右']),
        ('separate rows',join_rows([b('上',.4,.74),b('下',.2,.80)])==['上','下']),
        ('no transitive bridge',len(join_rows([b('a',.2,.70,h=.04),b('b',.4,.717,h=.04),b('c',.6,.734,h=.04)]))==2),
        ('empty',join_rows([])==[]),
        ('ruby evidence',len(ruby_candidates([b('反応',.4,.8),b('本文',.2,.75),b('はんのう',.4,.79,h=.01)])[1])==1),
        ('small unaligned retained',len(ruby_candidates([b('本文',.2,.75),b('本文',.4,.8),b('7',.8,.79,h=.01)])[1])==0),
        ('command positive',screen_evidence([b('COMMAND',.75,.26),b('様子を見る',.75,.39)])['candidate']=='COMMAND_MENU'),
        ('command lone',screen_evidence([b('COMMAND',.75,.26)])['candidate']=='UNKNOWN'),
        ('command wrong zone',screen_evidence([b('COMMAND',.2,.26),b('様子を見る',.2,.39)])['candidate']=='UNKNOWN'),
        ('status positive',screen_evidence([b('能力 ステータス',.4,.14)])['candidate']=='STATUS_MENU'),
        ('conflict',screen_evidence([b('能力 ステータス',.4,.14),b('COMMAND',.75,.26),b('様子を見る',.75,.39)])['candidate']=='UNKNOWN'),
        ('hp slash',hp_candidates('157/157')==['157/157']),
        ('hp possible separator',hp_candidates('1537153')==['153/153']),
        ('hp invalid',hp_candidates('200/100')==[]),
        ('hp zero max',hp_candidates('0/0')==[]),
        ('not hp',hp_candidates('06:55')==[]),
        ('no event',screen_evidence([])['event_emission']=='DISABLED'),
    ]
    return {'checks':[{ 'name':n,'pass':p} for n,p in cases], 'pass':sum(p for _,p in cases),'total':len(cases)}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive',type=Path,nargs='?');p.add_argument('--out',type=Path)
    a=p.parse_args(); result={'schema':'ocr-replay-v6','self_test':self_test()}
    if a.archive:
        with zipfile.ZipFile(a.archive) as z:
            d=json.loads(z.read('report.json'))
            if d['schema']!='ocr-diagnostic-pilot-v5':raise ValueError('unexpected report schema')
            for f in d['frames']:
                if hashlib.sha256(z.read(f['image'])).hexdigest()!=f['sha256']:raise ValueError('frame SHA mismatch')
            result['verified_frames']=len(d['frames'])
            result['replayed']=replay(d)
    s=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if a.out:
        with a.out.open('x',encoding='utf8') as f:f.write(s)
    print(s,end='')
    return int(result['self_test']['pass']!=result['self_test']['total'])

if __name__=='__main__':raise SystemExit(main())
