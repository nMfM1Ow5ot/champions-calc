#!/usr/bin/env python3
"""Score frozen v12 candidates against image-only references; no OCR or state writes.
Reference format: mapping frame ID -> category -> mapping slot -> value.
Use null for an unscorable category; [] is not valid. Values are JSON arrays/scalars.
Prediction format is the same except null is forbidden. Missing slot = abstention.
Categories: hp (species label + displayed HP), move (Japanese name),
pp (current + maximum), message_kind (class only), screen (class).
"""
import argparse
import json
from collections import Counter
from pathlib import Path

CATEGORIES=('hp','move','pp','message_kind','screen')

def score(reference,prediction):
    if set(reference)!=set(prediction): raise ValueError('frame coverage mismatch')
    result={}
    for cat in CATEGORIES:
        counts=Counter({k:0 for k in ('correct','wrong','missing','spurious','unscorable_frames','unscorable_predictions','scored_frames')})
        for frame,r in reference.items():
            if set(r)!=set(CATEGORIES) or set(prediction[frame])!=set(CATEGORIES): raise ValueError('category coverage mismatch')
            a,b=r[cat],prediction[frame][cat]
            if not isinstance(b,dict) or any(v is None for v in b.values()): raise ValueError('invalid prediction mapping')
            if a is None:
                counts['unscorable_frames']+=1;counts['unscorable_predictions']+=len(b);continue
            if not isinstance(a,dict) or any(v is None for v in a.values()): raise ValueError('invalid reference mapping')
            counts['scored_frames']+=1
            for k,v in a.items(): counts['missing' if k not in b else 'correct' if b[k]==v else 'wrong']+=1
            counts['spurious']+=len(set(b)-set(a))
        c,w,m,s=(counts[k] for k in ('correct','wrong','missing','spurious'))
        total_ref=c+w+m; total_pred=c+w+s
        result[cat]={**counts,'reference_count':total_ref,'prediction_count':total_pred,'precision':c/total_pred if total_pred else None,'recall':c/total_ref if total_ref else None}
    return result


def predictions_from_v12(records):
    """Project one unambiguous candidate per field; keep v12 raw records separately."""
    out={}
    def unique_name(n):
        c=n.get('best_candidates',[])
        return c[0] if len(c)==1 and n.get('status') in ('EXACT_TEXT','SUGGESTED') else None
    for case,r in records.items():
        q={k:{} for k in CATEGORIES}; out[case]=q
        p,m,c=r['plate'],r['message'],r['command']
        for h in p['hp_candidates']:
            n=unique_name(h['name'])
            if n is not None:
                if h['slot'] in q['hp']:raise ValueError('duplicate HP slot')
                q['hp'][h['slot']]=[n,h['hp_candidate']]
        screen=p['screen_candidate']
        if screen not in ('UNKNOWN','CONFLICT'):q['screen']['scene']=screen
        if m['candidate'] is not None:q['message_kind']['message']=m['candidate']['kind']
        if c:
            for row in c['moves']:
                if len(row['names'])==1 and (n:=unique_name(row['names'][0])) is not None:q['move'][str(row['row'])]=n
            for row in c['pp']:
                if len(row['pairs'])==1:
                    pair=row['pairs'][0];q['pp'][str(row['row'])]=[pair['current'],pair['maximum']]
    return out


def self_test():
    def run(a,b):
        r={k:{} for k in CATEGORIES};p=r.copy();r['hp']=a;p['hp']=b
        return score({'f':r},{'f':p})['hp']
    a=run({'left':['A','100%']},{'left':['A','100%']})
    b=run({'left':['A','100%']},{'left':['A','90%']})
    c=run({'left':['A','100%']},{})
    d=run({}, {'left':['A','100%']})
    e=run(None,{'left':['A','100%']})
    f=run({}, {})
    g=run({'left':['A','100%']},{'right':['A','100%']})
    tests={'correct':a['correct']==1 and a['precision']==a['recall']==1,
       'wrong':b['wrong']==1 and b['precision']==b['recall']==0,
       'missing':c['missing']==1 and c['precision'] is None and c['recall']==0,
       'spurious':d['spurious']==1 and d['precision']==0 and d['recall'] is None,
       'unscorable':e['unscorable_predictions']==1 and e['precision'] is None,
       'no_coverage':f['precision'] is None and f['recall'] is None,
       'slot_mismatch':g['missing']==g['spurious']==1}
    try: score({'f':{}},{})
    except ValueError: tests['frame_coverage']=True
    else: tests['frame_coverage']=False
    try: run({'left':None},{})
    except ValueError: tests['null_value_rejected']=True
    else: tests['null_value_rejected']=False
    n={'status':'EXACT_TEXT','best_candidates':['A']}
    frame={'plate':{'screen_candidate':'UNKNOWN','hp_candidates':[{'name':n,'slot':'own_left','hp_candidate':'1/2'}]},'message':{'candidate':None},'command':None}
    q=predictions_from_v12({'f':frame})['f']
    tests['adapter_hp']=q['hp']=={'own_left':['A','1/2']}
    tests['adapter_unknown_screen']=q['screen']=={}
    tests['adapter_empty_message']=q['message_kind']=={}
    return tests

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference',type=Path);p.add_argument('--prediction',type=Path);a=p.parse_args()
    t=self_test();out={'tests':t,'pass':sum(t.values()),'total':len(t)}
    if bool(a.reference)!=bool(a.prediction):p.error('both files required')
    if a.reference:out['score']=score(json.loads(a.reference.read_text()),json.loads(a.prediction.read_text()))
    print(json.dumps(out,ensure_ascii=False,indent=2));raise SystemExit(int(not all(t.values())))
