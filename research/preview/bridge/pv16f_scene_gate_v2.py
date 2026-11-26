"""Research-only layout and visibility candidate. Never authenticates scenes.
Bounded global translation; centered 16:9 fit is an explicit viewport hypothesis.
No arbitrary crop, affine or projective correction. Flat patch rejection is heuristic.
"""
import cv2
import numpy as np
import pv16f_scene_gate_v1 as v1

W,H=v1.W,v1.H
YS=v1.YS

def viewport(im):
    if not isinstance(im,np.ndarray) or im.dtype!=np.uint8 or im.ndim!=3 or im.shape[2]!=3:return None,None
    h,w=im.shape[:2]
    if h<H or w<W:return None,None
    if abs((w/h)/(W/H)-1)<=.005:
        return v1.normalize(im),'native_aspect'
    if abs((w/h)/(16/9)-1)<=.005:
        width=round(h*W/H);x=(w-width)//2
        if x<0 or width<W:return None,None
        return v1.normalize(im[:,x:x+width]),'centered_16_9_hypothesis'
    return None,None

def estimate_shift(a,limit=24):
    # Search offsets by common edge peaks on left panel. Independent row/column
    # profiles exclude the sprite regions; require consensus and contrast.
    q=a.astype(np.int16)
    dy=[]; dx=[]
    for y,e in zip(YS,(2,2,2,2,1,1)):
        p=np.diff(q[y+e-limit-1:y+e+limit+1,85:155],axis=0).mean((1,2))
        k=int(np.argmax(p));dy.append(k-limit if p[k]>=40 else None)
    def consensus(xs,minimum):
        vals=[x for x in xs if x is not None]
        if len(vals)<minimum:return None
        m=int(round(float(np.median(vals))))
        return m if sum(abs(x-m)<=1 for x in vals)>=minimum else None
    yshift=consensus(dy,5)
    if yshift is None:return None,None
    for x,sign in ((36,1),(257,-1)):
        p=sign*np.median([np.diff(q[y+yshift+12:y+yshift+32,x-limit-1:x+limit+1],axis=1).mean((0,2)) for y in YS],axis=0)
        k=int(np.argmax(p));dx.append(k-limit if p[k]>=35 else None)
    return consensus(dx,2),yshift

def visibility(a):
    # Flat, large covering patches only. Texture-bearing overlays can escape.
    def flat(p):
        return float(cv2.meanStdDev(p)[1].mean())<2.
    slots=[]
    for y in YS:
        # Entire sprite region and subwindows; avoid known type-panel background.
        p=a[y+10:y+38,690:732]
        # Overlapping subwindows catch partial flat overlays; test only inside sprite region.
        windows=[p[i:i+12,j:j+24] for i in (0,4,8,12,16) for j in (0,9,18)]
        slots.append(not flat(p) and not any(flat(w) for w in windows))
    center=not flat(a[120:380,320:600])
    return slots,center

def inspect(im):
    a,kind=viewport(im)
    fail=lambda reason:({'layout_candidate':False,'visible_candidate':False,'accepted':False,'reason':reason},None)
    if a is None:return fail('unsupported_viewport')
    base,_=v1.inspect(a);shift=(0,0)
    if not base['layout_candidate']:
        dx,dy=estimate_shift(a)
        if dx is None or dy is None or (dx,dy)==(0,0):return fail('no_consensus')
        a=cv2.warpAffine(a,np.float32([[1,0,-dx],[0,1,-dy]]),(W,H),flags=cv2.INTER_NEAREST)
        base,_=v1.inspect(a);shift=(dx,dy)
        if not base['layout_candidate']:return fail('corrected_layout_mismatch')
    slots,center=visibility(a)
    return dict(layout_candidate=True,visible_candidate=all(slots) and center,slot_visible_candidate=slots,center_visible_candidate=center,shift=shift,viewport=kind,accepted=False,reason='candidate_only' if all(slots) and center else 'flat_patch'),a if all(slots) and center else None
