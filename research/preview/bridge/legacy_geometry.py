import cv2,numpy as np
YS=[97,151,204,258,312,366]
def runs(a,gap):return [r for r in np.split(a,np.where(np.diff(a)>gap)[0]+1) if len(r)]

def detect(a):
 if a.shape[:2]!=(1080,1920):return []
 b,g,r=a.astype(np.int16).transpose(2,0,1);m=(r>90)&(r-g>45)&(r-b>15);col=m[160:880].sum(0);c=np.where((col>400)&(np.arange(1920)>1056))[0];groups=[g for g in runs(c,8) if len(g)>=5]
 if not groups:return []
 x0=int(groups[0][0]);x1=int(groups[-1][-1])+1;w=x1-x0
 if not 180<=w<=320:return []
 row=m[:,x0:x0+max(12,int(.10*w))].mean(1);ys=np.where(row>.7)[0];gr=[k for k in runs(ys,5) if 65<=k[-1]-k[0]+1<=120]
 if len(gr)!=6:return []
 starts=np.array([k[0] for k in gr]);hs=np.array([k[-1]-k[0]+1 for k in gr]);ds=np.diff(starts)
 if np.max(abs(ds-np.median(ds)))>8 or np.max(abs(hs-np.median(hs)))>12:return []
 return [(x0,int(k[0]),w,int(k[-1]-k[0]+1)) for k in gr]

def canonical(a,rows):
 im=np.zeros((540,823,3),np.uint8)
 for y,(x,yy,w,h) in zip(YS,rows):im[y:y+48,667:795]=cv2.resize(a[yy:yy+h,x:x+w],(128,48),interpolation=cv2.INTER_AREA)
 return im
