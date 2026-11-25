"""Research-only PV-02/03 candidate ranking. Requires existing PV-01 and OpenCV/NumPy."""
import json
import math
import statistics
from pathlib import Path
import cv2
import numpy as np
import champions_preview_features_pv01 as pv

BATTLE_ONLY = {'Greninja-Bond','Palafin-Hero','Mimikyu-Busted','Morpeko-Hangry'}


def type_rank(image, panel, offset, palette):
    x,y,w,h=panel
    s=round(.145*w); xx=x+round((.65 if offset==0 else .82)*w); yy=y+round(.13*h)
    rgb=image[yy:yy+s,xx:xx+s,::-1].astype(float)
    if rgb.shape!=(s,s,3) or s<4: raise ValueError('invalid icon crop')
    g=rgb@np.array([.299,.587,.114]); px=rgb.reshape(-1,3)
    Y,X=np.mgrid[:s,:s]
    ring=(np.minimum.reduce([X,Y,s-1-X,s-1-Y])<s*.23).ravel()
    selected=px[ring & (px.mean(1)<225)]
    if not len(selected): return {'status':'UNKNOWN','ranks':[]}
    med=np.median(selected,axis=0); std=float(g.std())
    ranks=[]
    for name,ref in palette.items():
        v=np.asarray(ref,dtype=float)
        if v.shape!=(3,) or not np.isfinite(v).all(): raise ValueError('invalid palette')
        delta=med-v
        score=float(np.sqrt(np.sum((delta-delta.mean())**2)+.5*(delta.mean()-20)**2))
        ranks.append((name,score))
    ranks.sort(key=lambda p:(p[1],p[0]))
    return {'status':'EMPTY_CANDIDATE' if std<=18 else 'RANKED','ranks':ranks,'std':std,'rgb':med.tolist()}


def pear(a,b):
    x=np.asarray(a,dtype=float);y=np.asarray(b,dtype=float)
    x=x-x.mean();y=y-y.mean();d=float(np.linalg.norm(x)*np.linalg.norm(y))
    return float(x@y/d) if d else 0.0


def appearance(f,ref):
    if len(f[0])!=64 or len(ref['hash'])!=64 or len(ref['hue'])!=24 or ref['aspect']<=0: raise ValueError('invalid feature')
    hd=(int(f[0],16)^int(ref['hash'],16)).bit_count()/256
    return hd-.35*pear(f[1],ref['hue'])+.15*abs(math.log(f[2]/ref['aspect']))+.25*abs(f[3]-ref['density'])


def type_mismatch(observed, expected):
    if observed is None or expected is None: return 0
    a=set(observed);b=set(expected)
    return max(len(a-b),len(b-a))


def stable_types(frames):
    # Do not treat disagreement or missing observations as proof of absence.
    result=[]
    for j in range(2):
        q=[f[j] for f in frames]
        if any(x['status']=='UNKNOWN' for x in q):return None
        labels=[None if x['status']=='EMPTY_CANDIDATE' else x['ranks'][0][0] for x in q]
        if len(set(labels))!=1:return None
        if labels[0] is not None:result.append(labels[0])
    return result if result and len(set(result))==len(result) else None


def rank_slot(features, observed, dictionary, types, penalty=.25):
    if not features or penalty<0:raise ValueError('invalid ranking input')
    ranks=[]
    for name,ref in dictionary.items():
        if name.endswith(('-Mega','-Mega-X','-Mega-Y','-Mega-Z')) or name in BATTLE_ONLY:continue
        refs=[ref]+[r for r in ref.get('templates',[]) if r.get('tag')!='shiny']
        score=statistics.median(min(appearance(f,r) for r in refs) for f in features)
        mismatch=type_mismatch(observed,types.get(name,{}).get('types'))
        ranks.append({'name':name,'appearance':score,'type_mismatch':mismatch,'score':score+penalty*mismatch})
    ranks.sort(key=lambda r:(r['score'],r['name']))
    return ranks


def inspect(images,dictionary,types,icon_dict):
    # Caller must establish same battle and stable slot ordering. No state updates.
    if not images:raise ValueError('empty image sequence')
    palette={k:v['rgb'] for k,v in icon_dict.items()}
    all_panels=[pv.detect(a) for a in images]
    if any(len(p)!=6 for p in all_panels):raise ValueError('six panels required in all frames')
    out=[]
    for i in range(6):
        fs=[];ts=[]
        for a,panels in zip(images,all_panels):
            f=pv.feature(a,panels[i])
            if f is not None:fs.append(f[:4])
            ts.append([type_rank(a,panels[i],j,palette) for j in range(2)])
        observed=stable_types(ts)
        out.append({'slot':i+1,'type_candidate':observed,'type_evidence':ts,'ranked':rank_slot(fs,observed,dictionary,types) if fs else [],'confirmed':False})
    return {'schema':'preview-pv02-v1','slots':out,'unrepresented_species':'UNKNOWN','confirmed_events':0}


def self_test():
    f=['00'*32,[1]+[0]*23,1,.5];r={'hash':f[0],'hue':f[1],'aspect':1,'density':.5}
    same={'status':'RANKED','ranks':[('Fire',1)]};empty={'status':'EMPTY_CANDIDATE','ranks':[]};other={'status':'RANKED','ranks':[('Water',1)]}
    ranks=rank_slot([f],['Fire'],{'A':r,'B':r,'A-Mega':r},{'A':{'types':['Fire']},'B':{'types':['Water']}})
    return {'identical_appearance':abs(appearance(f,r)+.35)<1e-9,'mismatch_permutation':type_mismatch(['Fire','Water'],['Water','Fire'])==0,'unknown_neutral':type_mismatch(None,['Fire'])==0,'same_types':stable_types([[empty,same],[empty,same]])==['Fire'],'disagreement_neutral':stable_types([[empty,same],[empty,other]]) is None,'mismatch_not_exclusion':len(ranks)==2 and ranks[1]['name']=='B','penalty_order':ranks[0]['name']=='A','battle_only_filter':all(x['name']!='A-Mega' for x in ranks)}


if __name__=='__main__':
    tests=self_test();print(json.dumps(tests,indent=2));raise SystemExit(not all(tests.values()))
