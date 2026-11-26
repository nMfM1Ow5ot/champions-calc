import json, hashlib, pathlib, time, tempfile, subprocess, os, sys
import cv2,numpy as np
import pv16_shadow_worker as w
import pv16f_integrated_v2 as m
P=pathlib.Path(__file__).resolve().parent
B=pathlib.Path(os.environ['PV16_SHADOW_BUNDLE']); A=pathlib.Path(os.environ['PV16_SHADOW_ARCHIVE'])
cv2.setNumThreads(1)
r,t,g,data=w.load_assets(B,A)
counts={'screens':0,'slots':0,'same_rank_vectors':0,'top1':0,'n':0,'complete':0,'complete_n':0,'through_gate':0,'gate_top1':0,'gate_n':0}
for s,im in data:
    loc,gb=w.banks(t,g,s['group']);c=m.Contract(m.catalog_digest(r.ids),*['0'*64]*6)
    old=m.rank_frame(r,im,loc,gb,c,s['key'],'test',geometry_verified=True)
    ranks,types,recovered=w.rank_unconfirmed(r,im,loc,gb)
    assert ranks==old['slots'] and types==old['types'] and recovered==old['recovered']
    counts['screens']+=1;counts['slots']+=6;counts['same_rank_vectors']+=6
    ans=w.analyze(im,r,loc,gb);counts['through_gate']+=ans['status']=='ranked';oks=[]
    for rank,ar,q in zip(ranks,ans['slots'],s['slots']):
        if q['truth']=='?':continue
        convert=lambda a:a if s['cohort']=='first5' else w.base(a)
        ok=bool(rank) and convert(rank[0][0])==q['truth'];oks.append(ok);counts['n']+=1;counts['top1']+=ok
        counts['gate_n']+=1;counts['gate_top1']+=bool(ar) and convert(ar[0][0])==q['truth']
    if len(oks)==6:counts['complete_n']+=1;counts['complete']+=all(oks)
assert counts['top1']==171 and counts['n']==173
print(json.dumps(counts))
with tempfile.TemporaryDirectory(prefix='pv16-test-') as root:
    root=pathlib.Path(root);p=subprocess.Popen([sys.executable,'-B',str(P/'pv16_shadow_worker.py'),'--bundle',str(B),'--archive',str(A),'--spool',str(root),'--parent',str(os.getpid())],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    def wait(name,timeout=15):
        f=root/name; deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            if f.exists():return json.loads(f.read_text())
            assert p.poll() is None;time.sleep(.02)
        raise RuntimeError(name)
    try:
        assert wait('ready.json')['accepted'] is False
        def request(im,id):
            cv2.imwrite(str(root/'frame.png'),im);w.write_json(root/'request.json',{'schema':w.SCHEMA,'id':id});ans=wait('response.json');(root/'response.json').unlink();assert ans['id']==id and ans['accepted'] is False and not ans['scene_authenticated'];return ans
        a=request(data[0][1],'a'*36);b=request(np.zeros((540,823,3),np.uint8),'b'*36);c=request(data[1][1],'c'*36)
        assert a['status']=='ranked' and b['status']=='held' and c['status']=='ranked' and p.poll() is None
        print('persistent worker: rank/hold/rank PASS')
    finally:p.terminate();p.wait(timeout=5)
