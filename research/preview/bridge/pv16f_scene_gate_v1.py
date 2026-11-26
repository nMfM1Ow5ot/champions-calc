"""Research-only static layout gate. Not an authenticated scene/viewport detector."""
import cv2
import numpy as np

YS=(97,151,204,258,312,366)
W,H=823,540

def normalize(im):
    if not isinstance(im,np.ndarray) or im.dtype!=np.uint8 or im.ndim!=3 or im.shape[2]!=3:
        return None
    h,w=im.shape[:2]
    if h<H or w<W or abs((w/h)/(W/H)-1)>.005:
        return None
    return cv2.resize(im,(W,H),interpolation=cv2.INTER_AREA) if (w,h)!=(W,H) else im.copy()

def inspect(im):
    """Accept candidate layout only; do not authorize a confirmed observation."""
    a=normalize(im)
    if a is None:return dict(layout_candidate=False,reason='unsupported_input_or_aspect',accepted=False),None
    left=[];right=[];edges=[];offsets=[];xs=[];strength=[]
    for y in YS:
        b,g,r=a[y+8:y+40,45:60].astype(np.int16).transpose(2,0,1)
        left.append(float(((b-r>18)&(b-g>12)).mean()))
        b,g,r=a[y+8:y+40,670:686].astype(np.int16).transpose(2,0,1)
        right.append(float(((r-g>22)&(r-b>10)).mean()))
        d=np.abs(np.diff(a[y-8:y+9,55:185].astype(np.int16),axis=0)).mean((1,2))
        edges.append(float(d.max()));offsets.append(int(d.argmax()-7))
    for x in (36,257,667):
        d=np.median([np.abs(np.diff(a[y+10:y+38,x-8:x+9].astype(np.int16),axis=1)).mean((0,2)) for y in YS],axis=0)
        xs.append(int(d.argmax()-7));strength.append(float(d.max()))
    color_ok=sum(v>=.65 for v in left)>=5 and all(v>=.65 for v in right)
    row_ok=all(v>=40 for v in edges) and all(abs(v-e)<=1 for v,e in zip(offsets,(2,2,2,2,1,1)))
    column_ok=all(abs(v)<=1 for v in xs[:2]) and abs(xs[2])<=2 and min(strength[:2])>=35 and strength[2]>=10
    ok=color_ok and row_ok and column_ok
    return dict(layout_candidate=ok,accepted=False,color_ok=color_ok,row_ok=row_ok,column_ok=column_ok,reason='candidate_only' if ok else 'layout_mismatch',left=left,right=right,row_edges=edges,row_offsets=offsets,column_offsets=xs,column_edges=strength),a if ok else None
