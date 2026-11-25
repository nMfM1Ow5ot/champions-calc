"""PV12 research only: rank existing PV10 frames, not a registration tool.
No network. Outputs local PNG crops and JSON; median is diagnostic, not a new reference.
"""
import argparse, hashlib, json
from pathlib import Path
import cv2
import numpy as np
import pv11_scene_dedup_v1 as pv

PV11_SHA='b817730ee5f5fb7320c7f1246ff7fb9aa30efee1b94526bfbbc06e8cf960a32a'

def digest(p):
    with p.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()

def verify(p,sha):
    if digest(p)!=sha: raise ValueError('input digest mismatch')

def measure(rows,old_right):
    a=np.stack([x[1] for x in rows]); med=np.median(a,axis=0).astype('uint8')
    b,g,r=med.astype('int16').transpose(2,0,1)
    mask=((r-g<45)|(r-b<15))&(np.max(med,axis=2)>45)
    mask[:3]=False;mask[-3:]=False
    n,lab,stats,_=cv2.connectedComponentsWithStats(mask.astype('uint8'))
    if n<2: return None
    j=1+np.argmax(stats[1:,4]); c=lab==j
    if not c.any() or c.all():return None
    x,y,w,h,area=map(int,stats[j]); metrics=[]
    for idx,pix in rows:
        diff=np.mean(np.abs(pix.astype('float32')-med.astype('float32')),axis=2)
        fg=float(diff[c].mean());bg=float(diff[~c].mean())
        lap=cv2.Laplacian(cv2.cvtColor(pix,cv2.COLOR_BGR2GRAY),cv2.CV_64F)
        metrics.append(dict(run=idx,foreground_deviation=fg,background_deviation=bg,laplacian_energy=float(np.mean(lap[c]**2)),score=fg+.25*bg))
    best=min(metrics,key=lambda v:(v['score'],v['run']))
    return dict(n=len(rows),bbox=[x,y,w,h],area=area,old_right=old_right,new_right=a.shape[2],old_mask_crosses_right=x+w>old_right,new_mask_crosses_right=x+w>=a.shape[2],chosen=best,metrics=metrics)

def run(source,out):
    verify(Path(pv.__file__),PV11_SHA)
    m=json.loads((source/'manifest.json').read_text());by_run={};checked=0
    if len({r['run'] for r in m['runs']})!=len(m['runs']):raise ValueError('duplicate run')
    for r in m['runs']:verify(source/r['file'],r['image_sha256']);by_run[r['run']]=r
    for r in m['records']:verify(source/r['crop_file'],r['crop_sha256']);checked+=1
    t=pv.template(cv2.imread(str(source/by_run[0]['file'])));groups={};geometry={};rejected=0
    for r in m['runs']:
        a=cv2.imread(str(source/r['file']));hit,_=pv.scene(a,t)
        if hit is None:rejected+=1;continue
        _,k,panels=hit
        for s,(x,y,w,h) in enumerate(panels,1):
            box=(x+4,y+3,int(.63*w)-4,h-6)
            xx,yy,ww,hh=box;patch=a[yy:yy+hh,xx:xx+ww]
            if patch.shape!=(hh,ww,3):raise ValueError('crop out of bounds')
            groups.setdefault((k,s),[]).append((r['run'],patch));geometry[(k,s)]=box
    out.mkdir(parents=True,exist_ok=False);results=[]
    for (k,s),rows in sorted(groups.items()):
        q=measure(rows,int(.52*pv.LAYOUTS[k][2])-4)
        if q is None:continue
        idx=q['chosen']['run'];pix=next(a for i,a in rows if i==idx);name=f'layout-{k}-slot-{s}.png';ok,b=cv2.imencode('.png',pix)
        if not ok:raise RuntimeError('encode failed')
        (out/name).write_bytes(b.tobytes());q.update(layout=k,slot=s,crop=list(geometry[(k,s)]),crop_file=name,crop_sha256=digest(out/name),frame_sha256=by_run[idx]['image_sha256'],frame_index=by_run[idx]['frame_index'],recording_sha256=m['recording_sha256'],label=None,label_status='unverified',rights_status='unknown',status='QUARANTINE')
        results.append(q)
    report=dict(schema='pv12-quality-selection-v1',frames_verified=len(by_run),old_crops_verified=checked,rejected_frames=rejected,eligible_frames=len(by_run)-rejected,expanded_candidates=sum(map(len,groups.values())),selected=len(results),registered=0,groups=results)
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n');return report

def self_test():
    a=np.zeros((30,40,3),np.uint8);a[:]=(50,20,160);a[8:23,20:34]=(40,170,40)
    b=a.copy();b[8:23,20:34]=(140,140,140)
    q=measure([(0,a),(1,a),(2,b)],28)
    assert q['old_mask_crosses_right'] and not q['new_mask_crosses_right']
    assert q['chosen']['run']==0 and q['n']==3
    red=np.zeros((30,40,3),np.uint8);red[:]=(50,20,160)
    assert measure([(0,red)],28) is None
    return {'detect_right_crossing':True,'select_stable_original':True,'reject_empty_proxy':True}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--self-test',action='store_true');p.add_argument('--source',type=Path);p.add_argument('--out',type=Path);a=p.parse_args()
    if a.self_test:print(json.dumps(self_test()));raise SystemExit(0)
    if not a.source or not a.out:p.error('source and out required')
    r=run(a.source,a.out);print(json.dumps({k:v for k,v in r.items() if k!='groups'}));print('old right proxy',sum(g['old_mask_crosses_right'] for g in r['groups']),'new right proxy',sum(g['new_mask_crosses_right'] for g in r['groups']))
