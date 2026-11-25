"""Research-only preview geometry and feature extraction. No state writes."""
import cv2,numpy as np

def runs(a,gap):
 return [r for r in np.split(a,np.where(np.diff(a)>gap)[0]+1) if len(r)]
def detect(a):
 H,W=a.shape[:2];b,g,r=a.astype(np.int16).transpose(2,0,1);m=(r>90)&(r-g>45)&(r-b>15)
 if (H,W)!=(1080,1920):return []
 col=m[160:880].sum(0);c=np.where((col>400)&(np.arange(W)>1056))[0];groups=[g for g in runs(c,8) if len(g)>=5]
 if not groups:return []
 # persistent left border; don't use background outside panel for row segmentation
 x0=int(groups[0][0]);x1=int(groups[-1][-1])+1; width=x1-x0
 if not 180<=width<=320:return []
 row=m[:,x0:x0+max(12,int(.10*width))].mean(1);ys=np.where(row>.7)[0];gr=[k for k in runs(ys,5) if 65<=k[-1]-k[0]+1<=120]
 if len(gr)!=6:return []
 starts=np.array([k[0] for k in gr]);hs=np.array([k[-1]-k[0]+1 for k in gr]);ds=np.diff(starts)
 if np.max(abs(ds-np.median(ds)))>8 or np.max(abs(hs-np.median(hs)))>12:return []
 return [(x0,int(k[0]),width,int(k[-1]-k[0]+1)) for k in gr]

def feature(a,p):
 x,y,w,h=p;cw=int(.52*w);patch=a[y:y+h,x:x+cw];rgb=patch[:,:,::-1];bg=a[y+4,x+int(.55*w),::-1].astype(int)
 def calc(bg):
  mask=(np.abs(rgb.astype(int)-bg).sum(2)>90).astype(np.uint8)
  n,lab,st,_=cv2.connectedComponentsWithStats(mask,8)
  if n<2:return None
  i=1+np.argmax(st[1:,4]);u,v,sw,sh,area=map(int,st[i]);
  if area<20:return None
  selected=lab[v:v+sh,u:u+sw]==i;colors=rgb[v:v+sh,u:u+sw][selected];gray=np.full((sh,sw),128.,np.float64);gray[selected]=colors@np.array([.299,.587,.114]);small=cv2.resize(gray,(17,16),interpolation=cv2.INTER_LINEAR);hash_=np.packbits((small[:,1:]>small[:,:-1]).flatten()).tobytes().hex();hue=cv2.cvtColor(colors.reshape(-1,1,3).astype(np.float32)/255,cv2.COLOR_RGB2HSV)[:,0,0];hist=np.bincount(np.minimum(23,(hue/15).astype(int)),minlength=24)/len(colors)
  return [hash_,[round(float(v),5) for v in hist],round(sw/sh,5),round(area/(sw*sh),5),round(area/(cw*h),5),round(sw/cw,5)]
 first=calc(bg)
 if first and first[-1]<.98 and first[-2]<.60:return first
 bins=(rgb.astype(int)//32)@np.array([64,8,1]);mode=np.bincount(bins.flatten()).argmax();bg=rgb[bins==mode].astype(int).sum(0)//(bins==mode).sum();second=calc(bg)
 if second and second[-1]>=.98 and second[-2]>=.60:return None
 return second or first


def type_feature(a,p,offset,adjusted=False):
 x,y,w,h=p
 k=([.64,.81] if adjusted else [.620,.810])[offset]
 s=int((.38 if adjusted else .403)*h);xx=x+int(k*w);yy=y+int((.12 if adjusted else .05)*h)
 rgb=a[yy:yy+s,xx:xx+s,::-1].astype(float);px=rgb.reshape(-1,3);g=rgb@np.array([.299,.587,.114])
 src=px[px.mean(1)<210];src=src if len(src) else px
 grid=np.rint(cv2.resize(g,(12,12),interpolation=cv2.INTER_AREA)).astype('uint8')
 return {"std":round(g.std(),2),"rgb":np.median(src,axis=0).tolist(),"glyph":grid.flatten().tolist()}
