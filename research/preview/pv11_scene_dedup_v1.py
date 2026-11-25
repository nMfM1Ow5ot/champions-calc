"""Research-only PV11. Japanese ranked doubles, 1920x1080, two fitted layouts.
No species inference or confirmed events; no write to source recordings/dictionary.
Run with a local approved calibration frame (PV10 frame-0000) and videos.
"""
import argparse, json, math, hashlib, time
from pathlib import Path
import cv2
import numpy as np
import champions_preview_features_pv01 as pv

# Fitted on one previously inspected recording, not universal game geometry.
LAYOUTS=((1472,194,252,86),(1274,226,254,22))
TITLE_X=785
TITLE_W=350
TITLE_H=32
HEADER_THRESHOLD=.75
RED_THRESHOLD=.90
MAX_GAP_SECONDS=5.0
MAX_SLOT_DISTANCE=.30


def digest(p):
    with Path(p).open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()


def header_mask(a):
    # Bright glyphs: suppress the dark animated backdrop. No OCR or external model.
    return (cv2.cvtColor(a,cv2.COLOR_BGR2GRAY)>155).astype(np.float32)


def template(frame):
    if frame is None or frame.shape!=(1080,1920,3): raise ValueError('calibration resolution')
    t=header_mask(frame[86:86+TITLE_H,TITLE_X:TITLE_X+TITLE_W])
    if t.sum()<50 or t.sum()>t.size*.8: raise ValueError('invalid header calibration')
    return t


def scene(a,t):
    if a is None or a.shape!=(1080,1920,3): return None,[]
    candidates=[]; metrics=[]
    for k,(x,y,w,hy) in enumerate(LAYOUTS):
        roi=header_mask(a[hy-5:hy+TITLE_H+5,TITLE_X-5:TITLE_X+TITLE_W+5])
        h=float(cv2.matchTemplate(roi,t,cv2.TM_CCOEFF_NORMED).max())
        panels=[(x,y+round(j*107.2),w,98) for j in range(6)]
        red=[]
        for px,py,_,ph in panels:
            b,g,r=a[py+10:py+85,px+6:px+23].astype(np.int16).transpose(2,0,1)
            red.append(float(((r>90)&(r-g>45)&(r-b>15)).mean()))
        m=min(red);metrics.append((h,m))
        if h>=HEADER_THRESHOLD and m>=RED_THRESHOLD: candidates.append((h,k,panels))
    if len(candidates)!=1: return None,metrics
    return candidates[0],metrics


def signature(a,panels):
    # Compare slot-aligned RGB crops at normalized scale; no dictionary or labels.
    return np.stack([cv2.resize(a[y+5:y+h-5,x+23:x+int(w*.49)],(24,24),interpolation=cv2.INTER_AREA).astype(np.float32)/255 for x,y,w,h in panels])


def same(a,b):
    return bool(np.all(np.mean(np.abs(a-b),axis=(1,2,3))<=MAX_SLOT_DISTANCE))


class Episodes:
    def __init__(self): self.events=[];self.pending=None;self.active=None
    def update(self,i,t,sig,layout,score):
        # Two consecutive sampled positives required to start a provisional episode.
        if self.active is not None and t-self.active['last_seconds']>MAX_GAP_SECONDS:
            self.active=None
        if sig is None: self.pending=None;return
        if self.active is not None and same(self.active['anchor'],sig):
            self.active['last_seconds']=t;self.active['hits']+=1
            self.active['layouts'].add(layout);self.pending=None;return
        # A dissimilar positive must not silently bridge into the active episode.
        if self.active is not None:self.active=None
        if self.pending is not None and same(self.pending['anchor'],sig):
            p=self.pending; p['last_seconds']=t;p['hits']=2;p['layouts'].add(layout)
            self.events.append(p);self.active=p;self.pending=None
        else:
            self.pending={'first_frame':i,'first_seconds':t,'last_seconds':t,'hits':1,'layouts':{layout},'anchor':sig,'header_score':score}
    def report(self):
        return [{**{k:v for k,v in e.items() if k not in ('anchor','layouts')},'layouts':sorted(e['layouts'])} for e in self.events]


def scan(video,t,hz=2,max_samples=300):
    if not math.isfinite(hz) or hz<=0 or max_samples<1:raise ValueError('invalid budget')
    cap=cv2.VideoCapture(str(video));fps=cap.get(cv2.CAP_PROP_FPS)
    if not cap.isOpened() or not math.isfinite(fps) or fps<=0:cap.release();raise ValueError('video unavailable')
    stride=max(1,round(fps/hz));i=0;rows=[];episodes=Episodes();started=time.monotonic()
    # Save only local diagnostics, never raw frames in repository.
    try:
        while len(rows)<max_samples and cap.grab():
            j=i;i+=1
            if j%stride:continue
            ok,a=cap.retrieve();hit,metrics=scene(a if ok else None,t)
            if hit is None:episodes.update(j,j/fps,None,None,None)
            else:
                score,k,panels=hit;episodes.update(j,j/fps,signature(a,panels),k,score)
            rows.append({'frame':j,'t':j/fps,'valid_decode':bool(ok),'hit':None if hit is None else hit[1],'metrics':metrics})
    finally:cap.release()
    return {'samples':len(rows),'decoded':sum(r['valid_decode'] for r in rows),'positive':sum(r['hit'] is not None for r in rows),'episodes':episodes.report(),'nominal_fps':fps,'stride':stride,'elapsed':time.monotonic()-started,'rows':rows}


def self_test():
    a=np.zeros((6,24,24,3),np.float32);b=np.ones_like(a)
    e=Episodes();e.update(0,0,a,0,1);e.update(1,.5,a,0,1);e.update(2,1,None,None,None);e.update(3,1.5,a,1,1)
    assert len(e.events)==1 and e.events[0]['hits']==3
    e.update(4,2,b,0,1);e.update(5,2.5,b,0,1);assert len(e.events)==2
    e.update(6,9,b,0,1);e.update(7,9.5,b,0,1);assert len(e.events)==3
    e=Episodes();e.update(0,0,a,0,1);e.update(1,.5,None,None,None);e.update(2,1,a,0,1);assert not e.events
    return {'bridge_short_gap':True,'split_dissimilar':True,'split_long_gap':True,'reject_isolated':True}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--self-test',action='store_true');p.add_argument('--calibration',type=Path);p.add_argument('--video',type=Path,nargs='+');p.add_argument('--out',type=Path);a=p.parse_args()
    if a.self_test:print(json.dumps(self_test()));raise SystemExit(0)
    if not a.calibration or not a.video or not a.out:p.error('calibration, video, out required')
    t=template(cv2.imread(str(a.calibration)));report={'calibration_sha256':digest(a.calibration),'parameters':{'header':HEADER_THRESHOLD,'red':RED_THRESHOLD,'gap':MAX_GAP_SECONDS,'slot_distance':MAX_SLOT_DISTANCE},'videos':[],'tests':self_test()}
    for v in a.video:
        r=scan(v,t);r['source_sha256']=digest(v);report['videos'].append(r);print(json.dumps({k:x for k,x in r.items() if k!='rows'}),flush=True)
    with a.out.open('x') as f:json.dump(report,f,indent=2)
