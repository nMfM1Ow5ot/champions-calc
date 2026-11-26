"""Exploratory monotone reject rules. Scores are not probabilities.
The public API never confirms observations. Caller validates scene and catalog.
"""
import math
from statistics import median

FEATURES=('distance','negative_margin','ratio2','ratio5','ratio10','ratio_median')
FAMILIES={
 'distance_exact':('distance',), 'margin_exact':('negative_margin',),
 'ratio2':('ratio2',),'ratio5':('ratio5',),'ratio10':('ratio10',),'ratio_median':('ratio_median',),
 'distance_margin':('distance','negative_margin'),
 'distance_ratio2':('distance','ratio2'),
 'distance_ratio5':('distance','ratio5'),
 'distance_ratio10':('distance','ratio10'),
 'distance_ratio_median':('distance','ratio_median'),
 'distance_margin_ratio5':('distance','negative_margin','ratio5'),
}

def evidence(rank,ids):
    ids=tuple(ids)
    if len(ids)<10 or len(set(ids))!=len(ids) or len(rank)!=len(ids) or {a for a,d in rank}!=set(ids):raise ValueError('invalid catalog')
    if any(not isinstance(d,(int,float)) or isinstance(d,bool) or not math.isfinite(d) or d<0 for a,d in rank):raise ValueError('invalid distance')
    a=sorted(rank,key=lambda x:(x[1],x[0]));ds=[d for _,d in a];d=ds[0];m=ds[1]-d
    def ratio(v):return d/v if v>0 else 1.0
    return dict(top=a[0][0],unique=m>0, distance=d,negative_margin=-m,ratio2=ratio(ds[1]),ratio5=ratio(ds[4]),ratio10=ratio(ds[9]),ratio_median=ratio(median(ds)))

def dominates(a,b):return all(x<=y for x,y in zip(a,b))

def vector(e,features):return tuple(e[k] for k in features)

def fit_bad(bad,features):
    if not features or len(set(features))!=len(features) or any(k not in FEATURES for k in features):raise ValueError('invalid features')
    points=sorted(set(vector(e,features) for e in bad if e['unique']))
    if any(not math.isfinite(v) for p in points for v in p):raise ValueError('invalid boundary')
    # Only minimal bad points are needed. Empty training negatives => no rule.
    return tuple(p for i,p in enumerate(points) if not any(dominates(q,p) for j,q in enumerate(points) if j!=i))

def eligible(e,features,boundary):
    v=vector(e,features)
    return bool(boundary) and e['unique'] is True and all(math.isfinite(x) for x in v) and not any(dominates(b,v) for b in boundary)

def propose(rank,ids,features,boundary,context_valid=False):
    e=evidence(rank,ids)
    if not features or len(set(features))!=len(features) or any(k not in FEATURES for k in features):raise ValueError('invalid features')
    boundary=tuple(tuple(p) for p in boundary)
    if any(len(p)!=len(features) or any(not math.isfinite(x) for x in p) for p in boundary):raise ValueError('invalid boundary')
    return dict(e,would_accept=context_valid is True and eligible(e,features,boundary),accepted=False)
