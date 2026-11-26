"""Research-only temporal rank fusion. Caller must establish scene/session/slot identity.
Distances are not probabilities; never emits accepted observations.
"""
import math
from statistics import median
from collections import Counter

METHODS=('mean_distance','median_distance','borda','plurality')

def fuse(frames, ids, method='mean_distance'):
    """frames: iterable of {session, frame_id, slots:[six full rank lists]}.
    Deduplicates identical frame IDs, rejects conflicting repeats, mixed sessions,
    missing candidates, malformed/negative/nonfinite scores. None = missing slot.
    A source must provide stable frame IDs (e.g. canonical content SHA256).
    """
    ids=tuple(ids)
    if len(ids)<2 or len(set(ids))!=len(ids) or method not in METHODS:
        raise ValueError('invalid ids or method')
    seen={}; session=None
    for fr in frames:
        s,k=fr['session'],fr['frame_id']
        if not isinstance(s,str) or not s or not isinstance(k,str) or not k:raise ValueError('invalid identity')
        if session is None:session=s
        if s!=session:raise ValueError('mixed session')
        if len(fr['slots'])!=6:raise ValueError('expected six slots')
        slots=[]
        for row in fr['slots']:
            if row is None or len(row)==0:slots.append(None);continue
            if len(row)!=len(ids) or {x[0] for x in row}!=set(ids):raise ValueError('incomplete or duplicate candidates')
            if any(not math.isfinite(v) or v<0 for _,v in row):raise ValueError('invalid score')
            slots.append(tuple(sorted((a,float(v)) for a,v in row)))
        slots=tuple(slots)
        if k in seen and seen[k]!=slots:raise ValueError('conflicting duplicate')
        seen[k]=slots
    out=[]
    for j in range(6):
        rows=[dict(seen[k][j]) for k in sorted(seen) if seen[k][j] is not None]
        if not rows:out.append({'rank':[],'support':0,'accepted':False});continue
        # Ties share average rank, plurality votes split equally; deterministic final ID ordering is not a certainty decision.
        ranks=[];votes=Counter()
        for d in rows:
            order=sorted(ids,key=lambda a:(d[a],a)); rank={};i=0
            while i<len(order):
                k=i+1
                while k<len(order) and d[order[k]]==d[order[i]]:k+=1
                for a in order[i:k]:rank[a]=(i+1+k)/2
                if i==0:
                    for a in order[i:k]:votes[a]+=1/(k-i)
                i=k
            ranks.append(rank)
        borda={a:math.fsum(d[a] for d in ranks)/len(rows) for a in ids}
        if method=='mean_distance':score={a:math.fsum(d[a] for d in rows)/len(rows) for a in ids}
        elif method=='median_distance':score={a:median(d[a] for d in rows) for a in ids}
        elif method=='borda':score=borda
        else:score={a:-votes[a]/len(rows) for a in ids}
        order=sorted(ids,key=lambda a:(score[a],borda[a] if method=='plurality' else 0,a))
        out.append({'rank':[[a,score[a]] for a in order],'support':len(rows),'accepted':False})
    return out
