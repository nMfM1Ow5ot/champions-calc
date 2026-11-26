"""PV16-F-R2/R3 research integration; Python 3.9+. No confirmed observations.
Caller must verify private bank provenance, catalog, session and geometry.
This module binds declared metadata; it cannot authenticate the caller.
"""
from dataclasses import dataclass, asdict, replace
import hashlib
import json
import math
import re

import cv2
import numpy as np

import pv16f_joint_candidate_v2 as core
import pv16f_coverage_v2 as coverage
import pv16f_residual_v1 as residual
import pv16f_temporal_fusion_v1 as temporal

@dataclass(frozen=True)
class Contract:
    catalog_digest: str
    ranker_digest: str
    reference_digest: str
    typebank_digest: str
    gallery_digest: str
    geometry_digest: str
    sampling_digest: str
    score_kind: str = "joint25-dynamic-gallery-recovery-v2"
    aggregation: str = "single"
    schema_version: str = "pv16f-contract-v1"

    def __post_init__(self):
        for k,v in asdict(self).items():
            if k.endswith("_digest") and (not isinstance(v,str) or not re.fullmatch("[0-9a-f]{64}",v)):
                raise ValueError("invalid digest: "+k)
        if self.schema_version!="pv16f-contract-v1" or self.score_kind!="joint25-dynamic-gallery-recovery-v2" or self.aggregation not in ("single","mean_distance"):
            raise ValueError("unsupported score domain")

    @property
    def digest(self):
        return hashlib.sha256(json.dumps(asdict(self),sort_keys=True,separators=(",",":")).encode()).hexdigest()

def catalog_digest(ids):
    ids=tuple(ids)
    if len(ids)<10 or any(not isinstance(i,str) or not i for i in ids) or tuple(sorted(set(ids)))!=ids:
        raise ValueError("catalog must be sorted unique nonempty IDs")
    return hashlib.sha256(json.dumps(ids,separators=(",",":"),ensure_ascii=True).encode()).hexdigest()

def validate_contract(contract,ids,aggregation):
    if not isinstance(contract,Contract) or contract.catalog_digest!=catalog_digest(ids) or contract.aggregation!=aggregation:
        raise ValueError("incompatible contract or catalog")

# Experimental implementation of the reported supplemental descriptor.
# Not a byte-exact reconstruction of the private experiment.
HOG=cv2.HOGDescriptor((32,32),(16,16),(8,8),(8,8),9)

def descriptor(im,y):
    if im.shape!=(540,823,3) or im.dtype!=np.uint8 or y not in core.YS:
        raise ValueError("canonical image required")
    rgb=im[y:y+48,667:733]
    bg=im[y+4,737].astype(np.int16)
    mask=(np.abs(rgb.astype(np.int16)-bg).sum(2)>90).astype(np.uint8)
    n,labels,stats,_=cv2.connectedComponentsWithStats(mask,connectivity=8)
    if n<2:return None
    k=1+np.argmax(stats[1:,4]); sel=labels==k
    near=cv2.dilate(sel.astype(np.uint8),np.ones((9,9),np.uint8))>0
    for j in np.unique(labels[near]):
        if j and stats[j,4]>=5:sel|=labels==j
    yy,xx=np.where(sel)
    if len(xx)<20:return None
    x0,x1,y0,y1=xx.min(),xx.max()+1,yy.min(),yy.max()+1
    w,h=x1-x0,y1-y0
    if len(xx)/(66*48)>=.60 or w/66>=.98:return None
    crop=rgb[y0:y1,x0:x1].copy();m=sel[y0:y1,x0:x1]
    crop[~m]=128
    scale=32/max(w,h); nw=max(1,round(w*scale));nh=max(1,round(h*scale))
    canvas=np.full((32,32,3),128,np.uint8);occ=np.zeros((32,32),np.float32)
    x,y=(32-nw)//2,(32-nh)//2
    canvas[y:y+nh,x:x+nw]=cv2.resize(crop,(nw,nh),interpolation=cv2.INTER_AREA)
    occ[y:y+nh,x:x+nw]=cv2.resize(m.astype(np.float32),(nw,nh),interpolation=cv2.INTER_AREA)
    gray=cv2.cvtColor(canvas,cv2.COLOR_BGR2GRAY)
    hog=HOG.compute(gray).reshape(-1).astype(float)
    norm=np.linalg.norm(hog)
    if norm==0:return None
    lab=cv2.cvtColor(canvas,cv2.COLOR_BGR2LAB).astype(float)/255
    return hog/norm,cv2.resize(lab,(4,4),interpolation=cv2.INTER_AREA).ravel(),cv2.resize(occ,(4,4),interpolation=cv2.INTER_AREA).ravel()

def gallery_bonus(q,gallery,ids):
    # gallery: tuple of (owner IDs, HOG matrix, Lab matrix, occupancy matrix).
    owner,h,l,o=gallery
    owner=tuple(owner);h,l,o=(np.asarray(a,dtype=float) for a in (h,l,o))
    if len(owner)==0 or not set(owner).issubset(ids) or h.shape!=(len(owner),HOG.getDescriptorSize()) or l.shape!=(len(owner),48) or o.shape!=(len(owner),16):
        raise ValueError("invalid gallery dimensions or owners")
    if not all(np.isfinite(a).all() for a in (h,l,o)) or not np.allclose(np.linalg.norm(h,axis=1),1,atol=1e-6) or np.any(h<0) or np.any((l<0)|(l>1)) or np.any((o<0)|(o>1)):
        raise ValueError("invalid gallery feature values")
    bonus={a:0.0 for a in ids}
    if q is None:return bonus
    qh,ql,qo=q
    d=.5*np.linalg.norm(h-qh,axis=1)+.3*np.abs(l-ql).mean(1)+.2*np.abs(o-qo).mean(1)
    for a,v in zip(owner,d):
        bonus[a]=max(bonus[a],.4*max(0.,1-float(v)/.30))
    return bonus

def rank_frame(r,im,bank,gallery,contract,session,frame_id,geometry_verified=False):
    validate_contract(contract,r.ids,"single")
    if geometry_verified is not True or not all(isinstance(x,str) and x for x in (session,frame_id)):
        raise ValueError("unverified geometry or identity")
    base=core.rank_screen(r,im,bank)
    slots=[];types=[];recovered=[]
    for y,b in zip(core.YS,base):
        types.append(b["types"])
        raw=b["rank"]
        used_recovery=not bool(raw)
        if used_recovery:
            raw=residual.rank_recovery(r,im,y,b["types"])
        recovered.append(used_recovery and bool(raw))
        if not raw:
            slots.append(None);continue
        bonus=gallery_bonus(descriptor(im,y),gallery,r.ids)
        # Common +.4 maintains nonnegative distances; new score domain.
        rank=sorted(((a,max(0.,d+.4-bonus[a])) for a,d in raw),key=lambda x:(x[1],x[0]))
        coverage.evidence(rank,r.ids)
        slots.append(rank)
    return {"contract":contract,"session":session,"frame_id":frame_id,
            "slots":slots,"types":types,"recovered":recovered,"accepted":False}

def fuse_frames(frames,ids,contract):
    ids=tuple(ids);validate_contract(contract,ids,"single")
    frames=tuple(frames)
    for f in frames:
        if f.get("contract")!=contract or f.get("accepted") is not False:
            raise ValueError("mixed contract or nonresearch frame")
    # Existing core rejects mixed sessions, conflicts, missing IDs and invalid distances.
    slots=temporal.fuse(frames,ids,method="mean_distance")
    return {"contract":replace(contract,aggregation="mean_distance"),
            "session":frames[0]["session"] if frames else None,
            "slots":slots,"accepted":False}

@dataclass(frozen=True)
class Boundary:
    contract_digest: str
    features: tuple
    points: tuple
    calibration_digest: str

    def __post_init__(self):
        for v in (self.contract_digest,self.calibration_digest):
            if not isinstance(v,str) or not re.fullmatch("[0-9a-f]{64}",v):
                raise ValueError("invalid boundary digest")
        f=tuple(self.features);p=tuple(tuple(x) for x in self.points)
        if not f or len(set(f))!=len(f) or any(k not in coverage.FEATURES for k in f):
            raise ValueError("invalid features")
        if any(len(x)!=len(f) or any(not isinstance(v,(int,float)) or isinstance(v,bool) or not math.isfinite(v) for v in x) for x in p):
            raise ValueError("invalid points")
        object.__setattr__(self,"features",f);object.__setattr__(self,"points",p)

def _propose(rank,ids,contract,boundary=None,context_valid=False):
    validate_contract(contract,ids,contract.aggregation)
    if boundary is None or not rank:return {"would_accept":False,"accepted":False,"reason":"missing calibration or rank"}
    if not isinstance(boundary,Boundary) or boundary.contract_digest!=contract.digest:
        raise ValueError("calibration contract mismatch")
    # Only a research proposal; context validity and label provenance external.
    return coverage.propose(rank,ids,boundary.features,boundary.points,context_valid=context_valid)

def propose_slot(result,ids,slot,boundary=None,context_valid=False):
    """Take scores and contract from the same result envelope; caller verifies provenance."""
    if result.get("accepted") is not False or type(slot) is not int or not 0<=slot<6 or len(result["slots"])!=6:
        raise ValueError("invalid result or slot")
    contract=result["contract"]
    validate_contract(contract,ids,contract.aggregation)
    row=result["slots"][slot]
    if contract.aggregation=="mean_distance":
        if not isinstance(row,dict) or row.get("accepted") is not False:
            raise ValueError("invalid fused slot")
        row=row["rank"]
    return _propose(row,ids,contract,boundary,context_valid)

def team_candidate(slots,ids,groups,rule_verified=False):
    """Minimize sum of original distances with at most one ID per verified group.
    No rank rewriting, acceptance, or inference of legal groups from name strings.
    Equal-cost ambiguity is conservatively reported; exact float equality only.
    """
    ids=tuple(ids);catalog_digest(ids)
    if rule_verified is not True:return {"team":None,"accepted":False,"reason":"rule unverified"}
    if set(groups)!=set(ids) or any(not isinstance(v,str) or not v for v in groups.values()):
        raise ValueError("invalid group map")
    if len(slots)!=6 or any(not s for s in slots):
        return {"team":None,"accepted":False,"reason":"missing slots"}
    for row in slots:coverage.evidence(row,ids)
    ds=[dict(s) for s in slots]
    by={}
    for a in ids:by.setdefault(groups[a],[]).append(a)
    # DP over 64 subsets, one candidate assigned per group.
    dp={0:(0.,(None,)*6,False)}
    for g in sorted(by):
        nxt=dict(dp)
        for mask,(cost,team,tie) in dp.items():
            for j in range(6):
                if mask&(1<<j):continue
                order=sorted(by[g],key=lambda a:(ds[j][a],a))
                a=order[0];newcost=cost+ds[j][a];newmask=mask|(1<<j)
                t=team[:j]+(a,)+team[j+1:]
                ambiguous=tie or (len(order)>1 and ds[j][order[1]]==ds[j][a])
                old=nxt.get(newmask)
                if old is None or newcost<old[0]:nxt[newmask]=(newcost,t,ambiguous)
                elif newcost==old[0]:nxt[newmask]=(old[0],min(old[1],t),True)
        dp=nxt
    if 63 not in dp:return {"team":None,"accepted":False,"reason":"infeasible"}
    cost,team,tie=dp[63]
    return {"team":team,"cost":cost,"tie":tie,"accepted":False}
