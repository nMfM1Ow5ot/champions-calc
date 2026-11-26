"""Local, candidate-only shadow worker. No state or network output."""
import argparse, hashlib, json, os, re, time, zipfile
from pathlib import Path
from types import SimpleNamespace
import cv2
import numpy as np
import pv16f_joint_candidate_v2 as core
import pv16f_integrated_v2 as model
import pv16f_residual_v1 as residual
import pv16f_coverage_v2 as coverage
import pv16f_scene_gate_v2 as scene
import legacy_geometry as legacy

BUNDLE='36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef'
ARCHIVE='570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7'
SCHEMA='pv16-shadow-v1'
MAX_IMAGE=16*1024*1024

def sha(b):return hashlib.sha256(b).hexdigest()
def check(ok):
    if not ok:raise ValueError('integrity or contract failure')
def base(v):
    for k in ['alcremie','vivillon','floette','basculegion','indeedee','meowstic','sinistcha','maushold','polteageist','gourgeist','lycanroc','rotom','squawkabilly','tauros','toxtricity']:
        if v.startswith(k):return k
    for s in ('hisui','alola','galar'):
        if v.endswith(s):return v[:-len(s)]
    return v

def load_assets(bundle,archive):
    check(sha(bundle.read_bytes())==BUNDLE and sha(archive.read_bytes())==ARCHIVE)
    with zipfile.ZipFile(bundle) as b,zipfile.ZipFile(archive) as z:
        for name,h in json.loads(b.read('members-sha256.json')).items():check(sha(b.read(name))==h)
        rows=json.loads(b.read('features-full.json'))['references'];ids=sorted({a['id'] for a in rows});ix={a:i for i,a in enumerate(ids)}
        check(len(ids)==293 and len(rows)==712)
        types={}
        for line in b.read('type-groups.txt').decode().splitlines():
            k,*vs=line.split()
            for v in vs:check(v not in types);types[v]=set(k.split('/'))
        check(set(types)==set(ids) and all(1<=len(v)<=2 and v.issubset(core.N) for v in types.values()))
        proto=json.loads(b.read('type-prototype-bank.json'))['classes'];bank=np.array([proto[k]['rgb']+proto[k]['glyph'] for k in core.N],float)
        rf=[a['feature'] for a in rows];rp=np.array([a['hue'] for a in rf],float);rp/=rp.sum(1,keepdims=True)
        r=SimpleNamespace(ids=ids,types=types,owner=np.array([ix[a['id']] for a in rows]),rh=[int(a['hash'],16) for a in rf],rp=rp,ra=np.array([a['aspect'] for a in rf]),rd=np.array([a['density'] for a in rf]),bank=bank)
        check(bank.shape==(18,147) and np.isfinite(bank).all() and np.isfinite(rp).all() and (r.ra>0).all())
        plan=json.loads(b.read('private-plan.json'));data=[];templates=[];gallery=[]
        for s in plan:
            raw=z.read(s['entry']);check(sha(raw)==s['original_sha256'])
            if 'working' in s:
                raw=b.read(s['working']);check(sha(raw)==s['working_sha256']);im=cv2.imdecode(np.frombuffer(raw,np.uint8),1)
            else:im=cv2.resize(cv2.imdecode(np.frombuffer(raw,np.uint8),1),(823,540),interpolation=cv2.INTER_AREA)
            check(im.shape==(540,823,3));data.append((s,im))
            for y,q in zip(core.YS,s['slots']):
                if q['pseudo_icons'] is not None:
                    for j,k in enumerate(q['pseudo_icons']):templates.append((s['group'],core.ipatch(im,y,j)[0],k))
                truth=q['truth'];matches=[p for p in ids if (p==truth if s['cohort']=='first5' else base(p)==truth)]
                if truth!='?' and len(matches)==1:
                    desc=model.descriptor(im,y)
                    if desc is not None:gallery.append((s['group'],matches[0],desc))
    check(len(data)==29 and len(templates)==328 and len(gallery)==130)
    return r,templates,gallery,data

def banks(templates,gallery,exclude=None):
    t=[(p,k) for g,p,k in templates if g!=exclude];gg=[(a,v) for g,a,v in gallery if g!=exclude]
    local=(np.array([p for p,k in t]),np.array([k for p,k in t]));check(set(core.N).issubset(local[1]))
    return local,([a for a,v in gg],*[np.array([v[j] for a,v in gg]) for j in range(3)])

def rank_unconfirmed(r,im,local,gb):
    # Same rank kernel as integrated v2, deliberately no geometry_verified claim.
    slots=[];types=[];recovered=[]
    for y,b in zip(core.YS,core.rank_screen(r,im,local)):
        types.append(b['types']);raw=b['rank'];used=not bool(raw)
        if used:raw=residual.rank_recovery(r,im,y,b['types'])
        recovered.append(used and bool(raw))
        if not raw:slots.append(None);continue
        bonus=model.gallery_bonus(model.descriptor(im,y),gb,r.ids)
        rank=sorted(((a,max(0.,d+.4-bonus[a])) for a,d in raw),key=lambda x:(x[1],x[0]))
        coverage.evidence(rank,r.ids);slots.append(rank)
    return slots,types,recovered

def analyze(im,r,local,gb):
    g,a=scene.inspect(im);route='full_layout_candidate'
    if a is None and not g['layout_candidate'] and im.shape==(1080,1920,3):
        rows=legacy.detect(im)
        if rows:a=legacy.canonical(im,rows);route='legacy_geometry_candidate_visibility_unverified'
    if a is None:return {'status':'held','route':None,'slots':[None]*6,'types':None,'recovered':None}
    ranks,types,recovered=rank_unconfirmed(r,a,local,gb)
    return {'status':'ranked','route':route,'slots':[row[:5] if row else None for row in ranks],'types':types,'recovered':recovered}

def write_json(path,obj):
    tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(obj,allow_nan=False,separators=(',',':')));os.replace(tmp,path)
def alive(pid):
    try:os.kill(pid,0);return True
    except OSError:return False

def serve(args):
    cv2.setNumThreads(1);r,t,g,data=load_assets(args.bundle,args.archive);del data;local,gb=banks(t,g)
    root=args.spool;check(root.is_dir() and root.stat().st_mode&0o077==0)
    write_json(root/'ready.json',{'schema':SCHEMA,'accepted':False})
    while alive(args.parent):
        p=root/'request.json'
        if not p.exists():time.sleep(.02);continue
        rid=None;frame_digest=None
        try:
            check(p.stat().st_size<=4096);q=json.loads(p.read_text());p.unlink();rid=q.get('id')
            check(q.get('schema')==SCHEMA and isinstance(rid,str) and re.fullmatch('[a-f0-9-]{36}',rid))
            f=root/'frame.png';check(f.stat().st_size<=MAX_IMAGE);raw=f.read_bytes();f.unlink()
            frame_digest=sha(raw);check(frame_digest==q.get('sha256') if 'sha256' in q else True)
            check(raw[:8]==b'\x89PNG\r\n\x1a\n' and len(raw)>=24 and 1<=int.from_bytes(raw[16:20],'big')<=4096 and 1<=int.from_bytes(raw[20:24],'big')<=4096)
            im=cv2.imdecode(np.frombuffer(raw,np.uint8),1);check(im is not None)
            ans=analyze(im,r,local,gb)
        except Exception:
            p.unlink(missing_ok=True);(root/'frame.png').unlink(missing_ok=True)
            ans={'status':'error','route':None,'slots':[None]*6,'types':None,'recovered':None}
        write_json(root/'response.json',dict(ans,schema=SCHEMA,id=rid,accepted=False,bank_scope='all_historical_development',scene_authenticated=False,frame_sha256=frame_digest,asset_bundle_sha256=BUNDLE,image_archive_sha256=ARCHIVE,score_kind='joint25-dynamic-gallery-recovery-v2'))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--bundle',type=Path,required=True);ap.add_argument('--archive',type=Path,required=True);ap.add_argument('--spool',type=Path,required=True);ap.add_argument('--parent',type=int,required=True);serve(ap.parse_args())
