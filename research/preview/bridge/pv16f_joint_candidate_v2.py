"""PV16-F provisional research ranking core; NOT production or calibrated acceptance.

Inputs: canonical 823x540 BGR image and caller-supplied, privately held validated
reference features/type metadata, prototype bank and local 18-type patches.
No private images, labels, features or automatic asset acquisition included.
"""
import math
import cv2
import numpy as np

N = 'Bug Dark Dragon Electric Fairy Fighting Fire Flying Ghost Grass Ground Ice Normal Poison Psychic Rock Steel Water'.split()
YS = (97, 151, 204, 258, 312, 366)

def corr(q,g):
 q=q-q.mean();g=g-g.mean(axis=1,keepdims=True);den=np.linalg.norm(q)*np.linalg.norm(g,axis=1);return np.divide(g@q,den,out=np.zeros(len(g)),where=den>0)

def feature(im,y,offset):
 x,w,h=667,128,48;s=int(.38*h);xx=x+int([.64,.81][offset]*w);yy=y+int(.12*h)
 rgb=im[yy:yy+s,xx:xx+s,::-1].astype(float);g=rgb@np.array([.299,.587,.114]);px=rgb.reshape(-1,3);p=px[px.mean(1)<210];p=p if len(p) else px
 return float(g.std()),np.median(p,axis=0),np.floor(cv2.resize(g,(12,12),interpolation=cv2.INTER_AREA)+.5).ravel()

def encode(im,y):
 x,w,h=667,128,48;cw=int(.52*w);rgb=im[y:y+h,x:x+cw,::-1];bg=im[y+4,x+int(.55*w),::-1].astype(int)
 def enc(bg):
  m=(np.abs(rgb.astype(int)-bg).sum(2)>90).astype('uint8');n,l,st,_=cv2.connectedComponentsWithStats(m,connectivity=8)
  if n<2:return None
  i=1+np.argmax(st[1:,4]);u,v,sw,sh,area=map(int,st[i]);sel=l[v:v+sh,u:u+sw]==i;colors=rgb[v:v+sh,u:u+sw][sel];gray=np.full((sh,sw),128.,np.float64);gray[sel]=colors@np.array([.299,.587,.114]);small=cv2.resize(gray,(17,16),interpolation=cv2.INTER_LINEAR);hsh=np.packbits((small[:,1:]>small[:,:-1]).ravel()).tobytes().hex();hue=cv2.cvtColor(colors.reshape(-1,1,3).astype(np.float32)/255,cv2.COLOR_RGB2HSV)[:,0,0];hist=np.bincount(np.minimum(23,(hue/15).astype(int)),minlength=24)/len(colors);return [hsh,[round(float(v),5) for v in hist],round(sw/sh,5),round(area/(sw*sh),5),round(area/(cw*h),5),round(sw/cw,5)]
 f=enc(bg)
 if f is None or not(f[-1]<.98 and f[-2]<.60):
  bins=(rgb.astype(int)//32)@np.array([64,8,1]);mode=np.bincount(bins.flatten()).argmax();bg=rgb[bins==mode].astype(int).sum(0)//(bins==mode).sum();f=enc(bg)
 return f if f is not None and f[-1]<.98 and f[-2]<.60 else None

def ipatch(im,y,j):
 x=[759,780][j];p=cv2.resize(im[y+7:y+22,x-7:x+8].astype(float)/255.,(8,8),interpolation=cv2.INTER_AREA).ravel();std,rgb,g=feature(im,y,j);return p,std,rgb,g

def glyph(r,q):
 _,_,rgb,g=q;return .7*(1-corr(g,r.bank[:,3:]))/2+.3*np.linalg.norm(r.bank[:,:3]-rgb,axis=1)/441.7

def unified(r,q,j,bank,mode):
 p,std,_,_=q;xx,yy=bank;d=np.sqrt(((xx-p)**2).mean(1));blank=float(d[yy=='NONE'].min()) if np.any(yy=='NONE') else math.inf
 if j==0 and std<=10 and blank<=.18:return 'NONE'
 g=glyph(r,q)/.42;local=np.array([float(d[yy==k].min())/.18 if np.any(yy==k) else np.inf for k in N]);has=np.isfinite(local)
 # compare all 18; absent local class uses glyph. Scores heuristic normalized by prior scale, not probabilities.
 if mode=='local18':s=np.where(has,local,g)
 elif mode=='joint25':s=np.where(has,.75*local+.25*g,g)
 elif mode=='joint50':s=np.where(has,.5*local+.5*g,g)
 elif mode=='jointmin':s=np.minimum(local,g)
 elif mode=='jointguard':s=np.where(has,.75*local+.25*g,g)
 else:raise ValueError(mode)
 o=np.argsort(s,kind='stable');gap=s[o[1]]-s[o[0]]
 return N[o[0]] if s[o[0]]<=1 and (mode!='jointguard' or gap>=.12) else 'UNKNOWN'

def foreground(im,y,mode):
 if mode=='base':return encode(im,y)
 x,w,h=667,128,48;cw=66 if mode in ['union','rowbg'] else 72
 rgb=im[y:y+h,x:x+cw,::-1];bg=im[y+4,x+int(.55*w),::-1].astype(int)
 if mode=='rowbg':
  # horizontal color gradient proxy: left of type icons, right of sprite; per row median
  bg=np.median(im[y:y+h,x+68:x+75,::-1].astype(int),axis=1)[:,None,:]
 mask=(np.abs(rgb.astype(int)-bg).sum(2)>90).astype(np.uint8)
 if mode=='close':mask=cv2.morphologyEx(mask,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
 n,l,st,_=cv2.connectedComponentsWithStats(mask,connectivity=8)
 if n<2:return None
 i=1+np.argmax(st[1:,4]);sel=l==i
 if mode in ['union','wideunion','rowbg']:
  # Include nearby separated components, not arbitrary background islands; nonrecursive.
  near=cv2.dilate(sel.astype(np.uint8),np.ones((9,9),np.uint8))>0
  for k in np.unique(l[near]):
   if k and st[k,4]>=5:sel|=l==k
 yy,xx=np.where(sel);u,v=xx.min(),yy.min();sw,sh=xx.max()-u+1,yy.max()-v+1;area=len(xx)
 if area<20 or area/(cw*h)>=.60 or sw/cw>=.98:return None
 sel=sel[v:v+sh,u:u+sw];colors=rgb[v:v+sh,u:u+sw][sel];gray=np.full((sh,sw),128.,np.float64);gray[sel]=colors@np.array([.299,.587,.114]);small=cv2.resize(gray,(17,16),interpolation=cv2.INTER_LINEAR);hs=np.packbits((small[:,1:]>small[:,:-1]).ravel()).tobytes().hex();hue=cv2.cvtColor(colors.reshape(-1,1,3).astype(np.float32)/255,cv2.COLOR_RGB2HSV)[:,0,0];hist=np.bincount(np.minimum(23,(hue/15).astype(int)),minlength=24)/len(colors)
 return [hs,[round(float(v),5) for v in hist],round(sw/sh,5),round(area/(sw*sh),5),round(area/(cw*h),5),round(sw/cw,5)]

def app(r,f,aw=.15,hw=.35):
 if f is None:return np.full(len(r.ids),np.inf)
 h,p,ar,de=f[:4];p=np.array(p);p/=p.sum();a=np.array([bin(int(h,16)^b).count("1")/256 for b in r.rh])+aw*abs(np.log(ar/r.ra))+.25*abs(de-r.rd)+hw*np.sqrt(np.maximum(0,1-np.sqrt(p*r.rp).sum(1)));s=np.full(len(r.ids),np.inf);np.minimum.at(s,r.owner,a);return s

def pen(r,obs):
 known=set(obs)-{'NONE','UNKNOWN'};exact=bool(known) and 'UNKNOWN' not in obs and obs[1]!='NONE' and len(known)==(1 if obs[0]=='NONE' else 2)
 return np.array([.4*(len(known-r.types[i])+int(exact and known!=r.types[i])) for i in r.ids])


def rank_slot(r, im, y, bank):
    """Rank all candidate IDs; accepts a validated reference object (see README).

    A missing feature produces no ranks. No prediction is marked accepted.
    Local bank must cover every type. No fit or evaluation labels are consumed.
    """
    if im.shape != (540, 823, 3) or im.dtype != np.uint8 or y not in YS:
        raise ValueError('expected canonical uint8 BGR image and valid slot')
    xx, yy = bank
    if (xx.ndim != 2 or xx.shape[1] != 192 or yy.shape != (len(xx),)
            or not np.isfinite(xx).all() or np.any((xx < -1e-6) | (xx > 1+1e-6))
            or set(yy) - set(N) - {'NONE'} or not set(N).issubset(set(yy))):
        raise ValueError('invalid or incomplete local bank')
    f = foreground(im, y, 'base')
    types = [unified(r, ipatch(im, y, j), j, bank, 'joint25') for j in range(2)]
    if f is None:
        return {'types': types, 'rank': [], 'accepted': False}
    alts = [foreground(im, y, k) for k in ('union', 'wideunion', 'rowbg', 'close')]
    valid = [v for v in alts if v is not None]
    disp = max(abs(math.log(v[2]/f[2])) for v in valid) if valid else 1.
    reliability = min(1., f[4]/.10)*math.exp(-2*disp)
    scores = app(r, f, aw=.15*reliability) + pen(r, types)
    order = np.argsort(scores, kind='stable')
    return {'types': types, 'rank': [[r.ids[i], float(scores[i])] for i in order if np.isfinite(scores[i])],
            'aspect_weight': .15*reliability, 'accepted': False}


def rank_screen(r, im, bank):
    """Requires caller-validated scene and geometry, not a scene detector."""
    return [rank_slot(r, im, y, bank) for y in YS]
