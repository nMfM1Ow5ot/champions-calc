#!/usr/bin/env python3
"""Research-only 18-type prototype bank and frozen development rerun; no holdout access."""
import argparse,hashlib,json,math,zipfile
from pathlib import Path
import cv2,numpy as np
NAMES='Bug Dark Dragon Electric Fairy Fighting Fire Flying Ghost Grass Ground Ice Normal Poison Psychic Rock Steel Water'.split()
SOURCE='c4ca6c06022f70e6bbf9edc168e7f86b0d6b06a0'
COMMIT='59edac6d38caf3c9aa209aa5f43c350fd2c77294'
FNV_EXPECTED=0x923d7f84

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def fnv(raw):
 h=2166136261
 for x in raw:h=((h^x)*16777619)&0xffffffff
 return h

def build(raw):
 if len(raw)!=2646 or fnv(raw)!=FNV_EXPECTED:raise ValueError('compact bank transfer mismatch')
 a=np.frombuffer(raw,dtype=np.uint8).reshape(18,147)
 return {'schema':'PV16-E-type-prototype-bank-v1','source_commit':COMMIT,'source_blob':SOURCE,'transfer_fnv32':f'{fnv(raw):08x}','transfer_sha256':hashlib.sha256(raw).hexdigest(),'provenance':'rounded legacy RGB and 12x12 grayscale mean glyph; not raw game icon PNG; original sample lineage not verified','classes':{k:{'rgb':r[:3].tolist(),'glyph':r[3:].tolist()} for k,r in zip(NAMES,a)}}
def corr(q,g):
 q=q-q.mean();g=g-g.mean(axis=1,keepdims=True);den=np.linalg.norm(q)*np.linalg.norm(g,axis=1);return np.divide(g@q,den,out=np.zeros(len(g)),where=den>0)
def feature(im,y,offset):
 x,w,h=667,128,48;s=int(.38*h);xx=x+int([.64,.81][offset]*w);yy=y+int(.12*h)
 rgb=im[yy:yy+s,xx:xx+s,::-1].astype(float);g=rgb@np.array([.299,.587,.114]);px=rgb.reshape(-1,3);p=px[px.mean(1)<210];p=p if len(p) else px
 return float(g.std()),np.median(p,axis=0),np.floor(cv2.resize(g,(12,12),interpolation=cv2.INTER_AREA)+.5).ravel()
def classify(f,bank,mode):
 std,rgb,g=f;col=np.linalg.norm(bank[:,:3]-rgb,axis=1)/441.7;glyph=(1-corr(g,bank[:,3:]))/2
 d=col if mode=='rgb' else .7*glyph+.3*col
 ii=np.argsort(d,kind='stable');i=int(ii[0]);gap=float(d[ii[1]]-d[i]);best=float(d[i]);label=NAMES[i]
 if std<=30:label='NONE'
 elif (mode=='rgb' and best>=.25) or (mode!='rgb' and best>=.42):label='UNKNOWN'
 elif mode=='guard' and gap<.025:label='UNKNOWN'
 return label,best,gap

def run(root,bank,outdir):
 d=json.loads((root/'PV16-E-exploratory-details-v1.0.json').read_text());r=json.loads((root/'PV16-D-retest-rankings-v1.0.json').read_text());ids=d['ids'];assert len(ids)==293 and len(r)==30
 assert sha(root/'PV16-D-Full-Evidence-20261126-085944.zip')=='69d16d949b3052ce8a841e90c61a21b0936cb27283a305f4aa2e9f567039c897'
 with zipfile.ZipFile(root/'PV16-C-five-screen-private-evidence-v1.0.zip') as z: rev=json.loads(z.read('review.json'))
 ims={}
 for s in rev['source_manifest']:
  p=root/f"pv16c_screen_{s['screen']}.jpg";assert sha(p)==s['working_sha256'];ims[s['screen']]=cv2.imread(str(p));assert ims[s['screen']].shape[:2]==(540,823)
 truth=np.array([ids.index(q['true_id']) for q in r]);screens=np.array([q['screen'] for q in r]);B=np.array(d['scores']['baseline']);types=[set(d['types'][i]) for i in ids]
 def metrics(S):
  ix=np.argsort(S,axis=1,kind='stable');t=(ix==truth[:,None]).argmax(1)+1;ok=t==1;return {'top1':int(ok.sum()),'top3':int((t<=3).sum()),'top5':int((t<=5).sum()),'mrr':float((1/t).mean()),'full':sum(bool(ok[screens==i].all()) for i in range(1,6)),'worst_rank':int(t.max()),'per_screen':[int(ok[screens==i].sum()) for i in range(1,6)]}
 assert metrics(B)['top1']==17
 tag=[q['true_icons'] for q in d['observed_types']];assert all((q['screen'],q['slot'])==(o['screen'],o['slot']) for q,o in zip(r,d['observed_types']))
 features=[[feature(ims[q['screen']],[97,151,204,258,312,366][q['slot']-1],j) for j in range(2)] for q in r]
 # Previous PV16-E 8x8 RGB templates, trained excluding evaluation screen.
 patch8=[]
 for q in r:
  im=ims[q['screen']];y=[97,151,204,258,312,366][q['slot']-1]
  patch8.append([cv2.resize(im[y+7:y+22,x-7:x+8].astype(float)/255.,(8,8),interpolation=cv2.INTER_AREA).ravel() for x in [759,780]])
 patch8=np.array(patch8); tags=np.array(tag)
 hybrid_bank={'schema':'PV16-E-development-hybrid-type-bank-v1','legacy_bank':'type-prototype-bank.json','observed_templates':[{'screen':q['screen'],'slot':q['slot'],'cells':[{'label':lab,'bgr8':p.tolist()} for lab,p in zip(tag[i],patch8[i])]} for i,q in enumerate(r)],'scope':'private development only; screen-excluded training during evaluation; full bank not independent'}
 dump(outdir/'hybrid-type-bank-private.json',hybrid_bank)
 results={};detail={}
 for mode in ['rgb','glyph','guard','hybrid','hybrid_guard']:
  records=[];S=B.copy()
  for i,ff in enumerate(features):
   if mode.startswith('hybrid'):
    tr=screens!=r[i]['screen'];xx=patch8[tr].reshape(-1,192);yy=tags[tr].reshape(-1);cc=[]
    for j,p in enumerate(patch8[i]):
     ds=np.sqrt(((xx-p)**2).mean(1));k=int(ds.argmin());dv=float(ds[k]);
     if dv<=.18:cc.append((str(yy[k]),dv,0.))
     else:cc.append(classify(ff[j],bank,'guard' if mode=='hybrid_guard' else 'glyph'))
   else:cc=[classify(f,bank,mode) for f in ff]
   pred=[c[0] for c in cc];known=set(pred)-{'NONE','UNKNOWN'};exact=bool(known) and 'UNKNOWN' not in pred and pred[1]!='NONE' and len(known)==(1 if pred[0]=='NONE' else 2)
   S[i]+=.4*np.array([len(known-t)+int(exact and known!=t) for t in types]);records.append({'screen':r[i]['screen'],'slot':r[i]['slot'],'truth':tag[i],'predicted':pred,'scores':[list(c[1:]) for c in cc],'std':[f[0] for f in ff],'species_truth':ids[truth[i]],'species_pred':ids[int(np.argmin(S[i]))]})
  results[mode]={'cell_correct':sum(a==b for o in records for a,b in zip(o['truth'],o['predicted'])),'pair_correct':sum(o['truth']==o['predicted'] for o in records),'unknown_cells':sum(o['predicted'].count('UNKNOWN') for o in records),'wrong_known_cells':sum(a!=b and b!='UNKNOWN' for o in records for a,b in zip(o['truth'],o['predicted'])),'species':metrics(S),'errors':[o for o in records if o['truth']!=o['predicted'] or o['species_truth']!=o['species_pred']]};detail[mode]=records
 # Structural synthetic test only: ideal prototype queries, uniform blank, both not empirical generalization.
 tests={'prototype_selfmatch':sum(classify((float(row[3:].std()),row[:3],row[3:]),bank,'glyph')[0]==name for name,row in zip(NAMES,bank)), 'prototype_identity_no_blank_gate':sum(classify((255.,row[:3],row[3:]),bank,'glyph')[0]==name for name,row in zip(NAMES,bank)), 'prototype_blank_gate_rejections':[name for name,row in zip(NAMES,bank) if row[3:].std()<=30],'blank':classify((0,np.array([150.,150.,150.]),np.full(144,150.)),bank,'guard')[0]}
 summary={'scope':'same five development screens; legacy prototype source lineage unknown; no independent performance','source_blob':SOURCE,'classes':NAMES,'observed_types':sorted(set(sum(tag,[]))-{'NONE'}),'unobserved_types':sorted(set(NAMES)-set(sum(tag,[]))),'baseline':metrics(B),'previous_type_fusion':metrics(np.array(d['scores']['observed_type_baseline'])),'results':results,'synthetic':tests,'versions':{'opencv':cv2.__version__,'numpy':np.__version__}}
 dump(outdir/'summary.json',summary);dump(outdir/'private-details.json',detail);print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('out',type=Path);g=p.add_mutually_exclusive_group(required=True);g.add_argument('--source',type=Path);g.add_argument('--compact',type=Path);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
 if a.source:
  b=a.source.read_bytes();assert hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()==SOURCE;d=json.loads(b);assert set(d)==set(NAMES);raw=bytes(math.floor(x+.5) for k in NAMES for x in d[k]['rgb']+d[k]['glyph'])
 else:raw=a.compact.read_bytes()
 D=build(raw);dump(a.out/'type-prototype-bank.json',D);run(a.root,np.frombuffer(raw,dtype=np.uint8).reshape(18,147).astype(float),a.out)
