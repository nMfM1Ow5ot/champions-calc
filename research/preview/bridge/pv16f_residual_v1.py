"""Development-only segmentation recovery; no confirmed observations."""
import math
import cv2
import numpy as np
import pv16f_joint_candidate_v2 as core

def recover(im,y,mode='open3'):
    """Recover only when baseline rejects, using conservative foreground geometry."""
    if im.shape!=(540,823,3) or im.dtype!=np.uint8 or y not in core.YS:raise ValueError('canonical image required')
    rgb=im[y:y+48,667:733,::-1]
    bg=im[y+4,737,::-1].astype(int)
    mask=(np.abs(rgb.astype(int)-bg).sum(2)>90).astype(np.uint8)
    if mode=='rowopen':
        bg=np.median(im[y:y+48,735:742,::-1].astype(int),axis=1)[:,None,:]
        mask=(np.abs(rgb.astype(int)-bg).sum(2)>90).astype(np.uint8)
    k=5 if mode=='open5' else 3
    seed=cv2.morphologyEx(mask,cv2.MORPH_OPEN,np.ones((k,k),np.uint8))
    n,l,st,_=cv2.connectedComponentsWithStats(seed,connectivity=8)
    if n<2:return None
    i=1+np.argmax(st[1:,4]);sel=l==i
    if st[i,4]<20:return None
    # Limited restoration, not full component reconstruction (would reattach streaks).
    if mode!='open_only':sel=(cv2.dilate(sel.astype(np.uint8),np.ones((3,3),np.uint8))>0)&(mask>0)
    yy,xx=np.where(sel);u,v=xx.min(),yy.min();sw,sh=xx.max()-u+1,yy.max()-v+1;area=len(xx)
    if area<20 or area/(66*48)>=.60 or sw/66>=.98:return None
    # Avoid thin isolated decorations; require centroid in central sprite region.
    if not 13<=xx.mean()<=53 or not 7<=yy.mean()<=41 or sw<5 or sh<7:return None
    colors=rgb[sel];gray=np.full((sh,sw),128.,np.float64);gray[sel[v:v+sh,u:u+sw]]=colors@np.array([.299,.587,.114]);small=cv2.resize(gray,(17,16),interpolation=cv2.INTER_LINEAR);hsh=np.packbits((small[:,1:]>small[:,:-1]).ravel()).tobytes().hex();hue=cv2.cvtColor(colors.reshape(-1,1,3).astype(np.float32)/255,cv2.COLOR_RGB2HSV)[:,0,0];hist=np.bincount(np.minimum(23,(hue/15).astype(int)),minlength=24)/len(colors)
    return [hsh,[round(float(t),5) for t in hist],round(sw/sh,5),round(area/(sw*sh),5),round(area/(66*48),5),round(sw/66,5)]

def rank_recovery(r,im,y,types,mode='open3',type_weight=1.,aspect_weight=.05):
    f=recover(im,y,mode)
    if f is None:return []
    scores=core.app(r,f,aw=aspect_weight)+type_weight*core.pen(r,types)
    return [(r.ids[i],float(scores[i])) for i in np.argsort(scores,kind='stable') if np.isfinite(scores[i])]
