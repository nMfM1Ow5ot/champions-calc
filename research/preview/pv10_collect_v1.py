"""Offline PV-10 pilot. Unlabelled candidates only; no network or production writes."""
import argparse, hashlib, json, math
from pathlib import Path
import cv2
import champions_preview_features_pv01 as pv

EXPECTED='25f5489c117ed05a921e3e76dd871aa0ae4be1332d68fd521af735b9b9d62076'

def sha(b): return hashlib.sha256(b).hexdigest()
def file_sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()
def png(a):
    ok,b=cv2.imencode('.png',a)
    if not ok: raise RuntimeError('PNG encode failed')
    return b.tobytes()

def collect(video,out,hz=2.0,max_samples=300):
    if file_sha(Path(pv.__file__))!=EXPECTED: raise ValueError('PV-01 digest mismatch')
    if not math.isfinite(hz) or hz<=0 or max_samples<1: raise ValueError('invalid budget')
    cap=cv2.VideoCapture(str(video)); fps=cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not math.isfinite(fps) or fps<=0:
        cap.release(); raise ValueError('invalid video or fps')
    out.mkdir(parents=True,exist_ok=False)
    source=file_sha(video); stride=max(1,round(fps/hz)); runs=[]; records=[]
    samples=positive=unsupported=0; frame_index=0; pending=None; active=False; stop='decode_end_or_error'
    try:
        while samples<max_samples:
            if not cap.grab(): break
            i=frame_index; frame_index+=1
            if i%stride: continue
            ok,a=cap.retrieve(); samples+=1
            if not ok: pending=None; active=False; continue
            if a.shape[:2]!=(1080,1920): unsupported+=1; pending=None; active=False; continue
            panels=pv.detect(a)
            if len(panels)!=6: pending=None; active=False; continue
            positive+=1
            if active: continue
            if pending is None: pending=(i,a,panels); continue
            # Consecutive sampled detections, not proof of same battle or real preview.
            j,b,ps=pending; pending=None; active=True
            run=len(runs); fb=png(b); fd=sha(fb); fp=f'frame-{run:04}.png'; (out/fp).write_bytes(fb)
            runs.append({'run':run,'frame_index':j,'nominal_seconds':j/fps,'image_sha256':fd,'file':fp,'confirmation_frame_index':i})
            for slot,p in enumerate(ps,1):
                x,y,w,h=map(int,p); cw=int(.52*w); crop=png(b[y:y+h,x:x+cw]); cd=sha(crop)
                cp=f'crop-{run:04}-{slot}.png'; (out/cp).write_bytes(crop)
                f=pv.feature(b,p)
                records.append({'id':f'{source}:{j}:{slot}','source_kind':'game_frame','source_group_id':source,'recording_sha256':source,'battle_id':None,'label':None,'label_evidence_id':None,'label_status':'unverified','rights_status':'unknown','split':None,'image_sha256':fd,'crop_sha256':cd,'image_size':[1920,1080],'crop':[x,y,cw,h],'crop_file':cp,'extractor_version':EXPECTED,'feature':None if f is None else dict(zip(['hash','hue','aspect','density','occupancy','width_ratio'],f)),'status':'QUARANTINE'})
        if samples>=max_samples: stop='sample_budget'
    finally: cap.release()
    if file_sha(video)!=source: raise RuntimeError('recording changed during scan; discard output')
    report={'schema':'pv10-collection-pilot-v1','recording_sha256':source,'fps_nominal':fps,'stride':stride,'samples':samples,'positive_samples':positive,'unsupported_samples':unsupported,'stop':stop,'runs':runs,'records':records,'registered':0,'opencv':cv2.__version__}
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('video',type=Path); p.add_argument('out',type=Path); p.add_argument('--hz',type=float,default=2); p.add_argument('--max-samples',type=int,default=300); a=p.parse_args()
    r=collect(a.video,a.out,a.hz,a.max_samples)
    print(json.dumps({k:v for k,v in r.items() if k not in ('records','runs')}|{'candidate_runs':len(r['runs']),'candidate_crops':len(r['records']),'features':sum(x['feature'] is not None for x in r['records'])},indent=2))
