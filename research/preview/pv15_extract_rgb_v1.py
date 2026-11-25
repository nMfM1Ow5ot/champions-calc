"""PV15 local diagnostic. Produce private feature/type rows for paired integration test."""
import argparse, hashlib, json, sys
from pathlib import Path
import cv2

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def extract(cache,selection,modules,output):
    for name,d in [('champions_preview_features_pv01.py','25f5489c117ed05a921e3e76dd871aa0ae4be1332d68fd521af735b9b9d62076'),('pv11_scene_dedup_v1.py','b817730ee5f5fb7320c7f1246ff7fb9aa30efee1b94526bfbbc06e8cf960a32a')]:
        if sha(modules/name)!=d: raise ValueError('module digest mismatch')
    sys.path.insert(0,str(modules));import champions_preview_features_pv01 as pv;import pv11_scene_dedup_v1 as sc
    m=json.loads((cache/'manifest.json').read_text());s=json.loads((selection/'manifest.json').read_text());by={r['run']:r for r in m['runs']};p=cache/by[0]['file'];assert sha(p)==by[0]['image_sha256'];t=sc.template(cv2.imread(str(p)));rows=[]
    for g in s['groups']:
        r=by[g['chosen']['run']];p=cache/r['file'];assert sha(p)==r['image_sha256'];assert sha(selection/g['crop_file'])==g['crop_sha256'];a=cv2.imread(str(p));hit,_=sc.scene(a,t);assert hit is not None and hit[1]==g['layout'];p=hit[2][g['slot']-1];f=pv.feature(a,p);assert f is not None;icons=[]
        for i in range(2):
            q=pv.type_feature(a,p,i,True);icons.append(f"{float(q['std']):.2f},"+','.join(f'{float(x):g}' for x in q['rgb']))
        rows.append(f"{g['layout']} {g['slot']} {f[0]}|"+','.join(str(round(x*100000)) for x in f[1])+f'|{f[2]}|{f[3]}|'+ '|'.join(icons))
    raw='\n'.join(rows);b=raw.encode('ascii');fnv=2166136261
    for x in b:fnv=((fnv^x)*16777619)&0xffffffff
    with output.open('x') as f:f.write(raw)
    print('rows',len(rows),'bytes',len(b),'SHA256',hashlib.sha256(b).hexdigest(),'FNV32',format(fnv,'08x'));print(raw)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('cache',type=Path);p.add_argument('selection',type=Path);p.add_argument('modules',type=Path);p.add_argument('output',type=Path);a=p.parse_args();extract(a.cache,a.selection,a.modules,a.output)
