#!/usr/bin/env python3
"""PV16-D v1.1: pinned, local-only reference bank. Python 3.9+; stdlib only."""
import argparse, concurrent.futures, hashlib, json, math, os, re, struct, tempfile, time, urllib.request, zlib
from pathlib import Path

MANIFEST_URL = 'https://raw.githubusercontent.com/nMfM1Ow5ot/champions-calc/11a4d4e2d8c6cea4af67e311b7f027574f17f047/research/preview/PV16-D-reference-manifest-v0.1.json'
MANIFEST_BLOB = '57f3db7022dffcc5511e298945d2af1b3eb5c3ed'
SPRITES = 'c0542f7c51215d9672439012838c99f520596cbd'
BASE = 'sprites/pokemon/versions/generation-ix/champions/icons'
PILOT = {'687.png','shiny/687.png','10061.png','10011.png','10257.png','925.png','10248.png','666-archipelago.png','869-caramel-swirl-star-sweet.png','668-female.png'}
SCHEMA = 'pv16d-alpha-component-dhash256-hue24-v1'

def blob(b):
    return hashlib.sha1(f'blob {len(b)}\0'.encode()+b).hexdigest()

def get(url, limit):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'PV16-D-research/1'}), timeout=15) as response:
                b=response.read(limit+1)
            if len(b)>limit: raise ValueError('oversize response')
            return b
        except (OSError, ValueError):
            if attempt==2: raise
            time.sleep(2**attempt)

def atomic(path,b):
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix=path.name+'.',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f: f.write(b)
        os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)

def dump(path,obj):
    atomic(path,(json.dumps(obj,sort_keys=True,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode())

def png(b):
    if not b.startswith(b'\x89PNG\r\n\x1a\n'): raise ValueError('PNG signature')
    i=8; header=None; compressed=[]; end=False
    while i+12<=len(b):
        n=struct.unpack_from('>I',b,i)[0]; tag=b[i+4:i+8]; j=i+8+n
        if j+4>len(b): raise ValueError('chunk length')
        data=b[i+8:j]
        if zlib.crc32(tag+data)&0xffffffff!=struct.unpack_from('>I',b,j)[0]: raise ValueError('PNG CRC')
        i=j+4
        if tag==b'IHDR':
            if header is not None or n!=13 or i!=33: raise ValueError('IHDR')
            header=struct.unpack('>IIBBBBB',data)
        elif tag==b'IDAT': compressed.append(data)
        elif tag==b'IEND':
            if n!=0: raise ValueError('IEND')
            end=True; break
    if header is None or not end or i!=len(b) or not compressed: raise ValueError('incomplete PNG')
    w,h,bit,typ,comp,filt,inter=header
    if not (1<=w<=1024 and 1<=h<=1024 and (bit,typ,comp,filt,inter)==(8,6,0,0,0)): raise ValueError(f'unsupported PNG {header}')
    stride=4*w; length=h*(stride+1); dec=zlib.decompressobj(); raw=dec.decompress(b''.join(compressed),length+1)
    if len(raw)!=length or not dec.eof or dec.unused_data or dec.unconsumed_tail: raise ValueError('bad raster size or zlib stream')
    out=bytearray(w*h*4)
    for y in range(h):
        f=raw[y*(stride+1)]
        if f>4: raise ValueError('PNG filter')
        for x in range(stride):
            k=y*stride+x; a=out[k-4] if x>=4 else 0; c=out[k-stride-4] if y and x>=4 else 0; d=out[k-stride] if y else 0
            if f==4:
                p=a+d-c; pa,pb,pc=abs(p-a),abs(p-d),abs(p-c)
                v=a if pa<=pb and pa<=pc else d if pb<=pc else c
            else: v=(0,a,d,(a+d)//2)[f]
            out[k]=(raw[y*(stride+1)+x+1]+v)&255
    return w,h,out

def feature(b):
    w,h,p=png(b); seen=bytearray(w*h); best=[]
    for j in range(w*h):
        if seen[j] or p[4*j+3]<128: continue
        q=[j]; seen[j]=1
        for k in q:
            x,y=k%w,k//w
            for Y in range(max(0,y-1),min(h,y+2)):
                for X in range(max(0,x-1),min(w,x+2)):
                    t=Y*w+X
                    if not seen[t] and p[4*t+3]>=128: seen[t]=1; q.append(t)
        if len(q)>len(best): best=q
    if not best: raise ValueError('empty foreground')
    xs=[j%w for j in best]; ys=[j//w for j in best]; x0,y0=min(xs),min(ys); sw,sh=max(xs)-x0+1,max(ys)-y0+1
    g=[128.0]*(sw*sh); hist=[0]*24
    for j in best:
        r,G,b=p[4*j:4*j+3]; g[(j//w-y0)*sw+j%w-x0]=.299*r+.587*G+.114*b
        mx,mn=max(r,G,b),min(r,G,b); d=mx-mn
        H=0 if d==0 else (60*((G-b)/d+6))%360 if mx==r else 60*((b-r)/d+2) if mx==G else 60*((r-G)/d+4)
        hist[min(23,int(H/15))]+=1
    def val(x,y):
        x=max(0,min(sw-1,x)); y=max(0,min(sh-1,y)); a,b=int(x),int(y); c,d=min(a+1,sw-1),min(b+1,sh-1); fx,fy=x-a,y-b
        return (g[b*sw+a]*(1-fx)+g[b*sw+c]*fx)*(1-fy)+(g[d*sw+a]*(1-fx)+g[d*sw+c]*fx)*fy
    bits=0
    for y in range(16):
        for x in range(16):
            Y=(y+.5)*sh/16-.5; bits=(bits<<1)|int(val((x+1.5)*sw/17-.5,Y)>val((x+.5)*sw/17-.5,Y))
    return {'hash':f'{bits:064x}','hue':hist,'aspect':sw/sh,'density':len(best)/(sw*sh),'bbox':[x0,y0,sw,sh],'foreground':len(best),'dimensions':[w,h]}

def validate(m):
    if m['schema']!='PV16-D-reference-manifest-v0.1' or m['sources']['sprites']['commit']!=SPRITES or m['sources']['sprites']['base_path']!=BASE: raise ValueError('wrong manifest source')
    a=m['assets']; c=m['candidates']; ids=[x['id'] for x in c]; paths=[x['path'] for x in a]; index={x['path']:x for x in a}
    if len(ids)!=293 or len(set(ids))!=293 or len(paths)!=712 or len(set(paths))!=712: raise ValueError('manifest cardinality')
    if sum(x['bytes'] for x in a)!=9656827: raise ValueError('manifest byte total')
    owned=[]
    for x in c:
        if not x['assets']: raise ValueError('empty candidate')
        for p in x['assets']:
            if index[p]['id']!=x['id']: raise ValueError('owner mismatch')
            owned.append(p)
    if sorted(owned)!=sorted(paths): raise ValueError('asset ownership')
    for x in a:
        p=x['path']; normal=p.removeprefix('shiny/'); expected='shiny' if p.startswith('shiny/') else 'normal'
        if not re.fullmatch(r'(?:shiny/)?[0-9]+(?:-[a-z0-9]+)*\.png',p) or x['variant']!=expected or not re.fullmatch(r'[0-9a-f]{40}',x['git_blob_sha1']) or not 0<x['bytes']<=1000000: raise ValueError('unsafe asset metadata')
        if index[normal]['id']!=x['id'] or index['shiny/'+normal]['id']!=x['id']: raise ValueError('normal/shiny pair')
    return sorted(a,key=lambda x:x['path'])

def process(a,cache,offline):
    sha=a['git_blob_sha1']; p=cache/(sha+'.png')
    def checked(b):
        if len(b)!=a['bytes'] or blob(b)!=sha: raise ValueError('image size/blob mismatch')
        return b
    if p.exists(): b=checked(p.read_bytes())
    else:
        if offline: raise FileNotFoundError(str(p))
        b=checked(get(f'https://raw.githubusercontent.com/PokeAPI/sprites/{SPRITES}/{BASE}/{a["path"]}',a['bytes']))
        atomic(p,b)
    return {**a,'sha256':hashlib.sha256(b).hexdigest(),'feature':feature(b)}

def selftest():
    def chunk(t,b): return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
    def image(w,h,pix): return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes(pix[y*w*4:(y+1)*w*4]) for y in range(h))))+chunk(b'IEND',b'')
    a=image(3,2,[255,0,0,255]*6); b=image(2,3,[0,255,0,255]*6); c=image(2,2,[0,0,0,0]*4)
    f=feature(a); g=feature(b)
    assert f['dimensions']==[3,2] and f['foreground']==6 and f['hue'][0]==6 and f['aspect']==1.5
    assert g['dimensions']==[2,3] and g['hue'][8]==6 and g['density']==1
    assert feature(a)==f and len(f['hash'])==64 and sum(f['hue'])==6
    for bad in [c,a[:-1],a[:40]+bytes([a[40]^1])+a[41:]]:
        try: feature(bad)
        except ValueError: pass
        else: raise AssertionError('invalid image accepted')
    print('selftest PASS: variable dimensions, hue, deterministic descriptor, empty/truncated/corrupt PNG rejection')

def main():
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,default=Path.home()/'pv16d-reference-v1'); p.add_argument('--manifest',type=Path); p.add_argument('--pilot',action='store_true'); p.add_argument('--offline',action='store_true'); p.add_argument('--workers',type=int,default=4); p.add_argument('--selftest',action='store_true'); args=p.parse_args()
    if args.selftest: selftest(); return
    if not 1<=args.workers<=4: p.error('workers must be 1..4')
    out=args.output.expanduser().resolve(); mp=out/'manifest.json'
    # Raw assets and extracted features are local research outputs, not public repo material.
    if any((d/'.git').exists() for d in [out,*out.parents]): p.error('choose output outside any Git working tree')
    out.mkdir(parents=True,exist_ok=True)
    if args.manifest: raw=args.manifest.read_bytes()
    elif mp.exists(): raw=mp.read_bytes()
    elif args.offline: p.error('manifest absent in offline mode')
    else: raw=get(MANIFEST_URL,1000000)
    if blob(raw)!=MANIFEST_BLOB: raise ValueError('pinned manifest blob mismatch')
    m=json.loads(raw); assets=validate(m); atomic(mp,raw)
    if args.pilot: assets=[a for a in assets if a['path'] in PILOT]; assert len(assets)==10
    rows=[]; errors=[]; label='pilot' if args.pilot else 'full'
    groups={}
    for a in assets: groups.setdefault(a['git_blob_sha1'],[]).append(a)
    if any(len({a['bytes'] for a in group})!=1 for group in groups.values()): raise ValueError('blob size conflict')
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures={pool.submit(process,group[0],out/'images',args.offline):group for group in groups.values()}
        for i,f in enumerate(concurrent.futures.as_completed(futures),1):
            group=futures[f]
            try:
                result=f.result()
                rows.extend({**a,'sha256':result['sha256'],'feature':result['feature']} for a in group)
            except Exception as e:
                errors.extend({'path':a['path'],'error':type(e).__name__+': '+str(e)} for a in group)
            if i%50==0: print(f'{i}/{len(groups)} unique blobs',flush=True)
    rows.sort(key=lambda a:a['path']); errors.sort(key=lambda a:a['path'])
    report={'schema':SCHEMA,'scope':label,'manifest_blob':MANIFEST_BLOB,'manifest_sha256':hashlib.sha256(raw).hexdigest(),'target':len(assets),'success':len(rows),'errors':errors,'candidate_count':len({a['id'] for a in rows}),'distinct_blobs':len({a['git_blob_sha1'] for a in rows}),'complete':not errors,'target_distinct_blobs':len(groups),'cross_candidate_identical_blobs':[{'blob':sha,'candidate_ids':sorted({a['id'] for a in group})} for sha,group in sorted(groups.items()) if len({a['id'] for a in group})>1],'status':'PROVISIONAL_MAPPING_NOT_INDEPENDENT_ACCEPTANCE'}
    dest=out/f'features-{label}.json'
    if not errors: dump(dest,{'schema':SCHEMA,'manifest_blob':MANIFEST_BLOB,'references':rows})
    elif dest.exists(): raise RuntimeError('existing complete feature file left unchanged; new run failed: '+str(errors[:3]))
    dump(out/f'validation-{label}.json',report); print(json.dumps(report,ensure_ascii=False)); raise SystemExit(1 if errors else 0)

if __name__=='__main__': main()
