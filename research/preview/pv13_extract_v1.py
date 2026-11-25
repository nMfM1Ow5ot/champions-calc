"""PV13 local paired feature extraction, research only. No images or labels published."""
import argparse, hashlib, json, sys
from pathlib import Path
import cv2, numpy as np

PV01='25f5489c117ed05a921e3e76dd871aa0ae4be1332d68fd521af735b9b9d62076'
PV11='b817730ee5f5fb7320c7f1246ff7fb9aa30efee1b94526bfbbc06e8cf960a32a'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def encode(rgb,mask):
 n,lab,st,_=cv2.connectedComponentsWithStats(mask.astype('uint8'),8)
 if n<2:return None
 i=1+np.argmax(st[1:,4]);u,v,sw,sh,area=map(int,st[i]);
 if area<20:return None
 sel=lab[v:v+sh,u:u+sw]==i;colors=rgb[v:v+sh,u:u+sw][sel];gray=np.full((sh,sw),128.,np.float64);gray[sel]=colors@np.array([.299,.587,.114]);small=cv2.resize(gray,(17,16),interpolation=cv2.INTER_LINEAR);h=np.packbits((small[:,1:]>small[:,:-1]).flatten()).tobytes().hex();hue=cv2.cvtColor(colors.reshape(-1,1,3).astype(np.float32)/255,cv2.COLOR_RGB2HSV)[:,0,0];hist=np.bincount(np.minimum(23,(hue/15).astype(int)),minlength=24)/len(colors)
 return [h,[round(float(v),5) for v in hist],round(sw/sh,5),round(area/(sw*sh),5),round(area/(rgb.shape[0]*rgb.shape[1]),5),round(sw/rgb.shape[1],5)]
def extract(a,p,width,mode):
 x,y,w,h=p;cw=int(width*w);rgb=a[y:y+h,x:x+cw,::-1];bg=a[y+4,x+int(.55*w),::-1].astype(int)
 if mode=='nonred':
  rgb=rgb[3:-3,4:];r,g,b=rgb.astype('int16').transpose(2,0,1);mask=((r-g<45)|(r-b<15))&(np.max(rgb,axis=2)>45);mask[:3]=False;mask[-3:]=False
  return encode(rgb,mask)
 def calc(bg):return encode(rgb,np.abs(rgb.astype(int)-bg).sum(2)>90)
 first=calc(bg)
 if first and first[-1]<.98 and first[-2]<.60:return first
 bins=(rgb.astype(int)//32)@np.array([64,8,1]);mode=np.bincount(bins.flatten()).argmax();bg=rgb[bins==mode].astype(int).sum(0)//(bins==mode).sum();second=calc(bg)
 if second and second[-1]>=.98 and second[-2]>=.60:return None
 return second or first

def main(cache,selection,modules,out):
 for n,h in [('champions_preview_features_pv01.py',PV01),('pv11_scene_dedup_v1.py',PV11)]:
  if sha(modules/n)!=h:raise ValueError('module digest mismatch')
 sys.path.insert(0,str(modules));import champions_preview_features_pv01 as pv;import pv11_scene_dedup_v1 as scene
 m=json.loads((cache/'manifest.json').read_text());s=json.loads((selection/'manifest.json').read_text());e=json.loads((selection/'local-label-evidence-v1.json').read_text());by={r['run']:r for r in m['runs']}
 for ev in e['label_evidence']:
  if sha(selection/ev['file'])!=ev['nameplate_sha256']:raise ValueError('evidence digest mismatch')
 t=scene.template(cv2.imread(str(cache/by[0]['file'])));rows=[]
 for g in s['groups']:
  r=by[g['chosen']['run']];p=cache/r['file']
  if sha(p)!=r['image_sha256'] or sha(selection/g['crop_file'])!=g['crop_sha256']:raise ValueError('frame/crop mismatch')
  a=cv2.imread(str(p));hit,_=scene.scene(a,t);_,k,ps=hit;slot=g['slot'];panel=ps[slot-1];assert k==g['layout'];base=pv.feature(a,panel);old=extract(a,panel,.52,'legacy');assert old==base,(k,slot)
  for name,w,mode in [('old52',.52,'legacy'),('wide63',.63,'legacy'),('wide63_nonred',.63,'nonred')]:
   f=extract(a,panel,w,mode);rows.append({'layout':k,'slot':slot,'arm':name,'feature':f[:4] if f else None})
 with out.open('x') as f:json.dump(rows,f,indent=2)
 print('features',sum(r['feature'] is not None for r in rows),'/',len(rows),'paired baseline equality 12/12')
 for r in rows:
  f=r['feature'];print(r['layout'],r['slot'],r['arm'], 'NONE' if not f else f'{f[0]}|'+','.join(str(round(x*100000)) for x in f[1])+f'|{f[2]}|{f[3]}')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('cache',type=Path);p.add_argument('selection',type=Path);p.add_argument('modules',type=Path);p.add_argument('out',type=Path);a=p.parse_args();main(a.cache,a.selection,a.modules,a.out)
