"""PV-10 synthetic regression only; does not test game recognition."""
import tempfile, pathlib, cv2, numpy as np
import pv10_collect_v1 as p
with tempfile.TemporaryDirectory() as d:
    d=pathlib.Path(d)
    blank=np.zeros((1080,1920,3),np.uint8)+30
    pos=blank.copy()
    for i in range(6):
        y=175+110*i
        cv2.rectangle(pos,(1200,y),(1439,y+89),(60,50,180),-1)
        cv2.ellipse(pos,(1255,y+45),(24,30),0,0,360,(200,190,30),-1)
    def video(name,frames,size):
        path=d/name
        w=cv2.VideoWriter(str(path),cv2.VideoWriter_fourcc(*'MJPG'),4,size)
        assert w.isOpened()
        for a in frames:w.write(a)
        w.release()
        return path
    v=video('synthetic.avi',[blank]*4+[pos]*12+[blank]*4+[pos]*12+[blank]*4,(1920,1080))
    r=p.collect(v,d/'out',2,300)
    assert len(r['runs'])==2 and len(r['records'])==12 and r['registered']==0
    assert all(x['label'] is None and x['status']=='QUARANTINE' for x in r['records'])
    assert all(p.file_sha(d/'out'/x['crop_file'])==x['crop_sha256'] for x in r['records'])
    assert all(p.file_sha(d/'out'/x['file'])==x['image_sha256'] for x in r['runs'])
    r2=p.collect(v,d/'budget',2,3)
    assert r2['samples']==3 and r2['stop']=='sample_budget'
    try:
        p.collect(v,d/'out')
        raise AssertionError('overwrote')
    except FileExistsError:pass
    small=np.zeros((360,640,3),np.uint8)
    v2=video('small.avi',[small]*8,(640,360))
    r3=p.collect(v2,d/'small',2,300)
    assert r3['unsupported_samples']==4 and len(r3['records'])==0
    v3=video('single.avi',[blank]*4+[pos]*2+[blank]*4,(1920,1080))
    r4=p.collect(v3,d/'single')
    assert len(r4['records'])==0
    print('PASS: two runs, 12 crops, quarantine, crop/frame hashes, sample budget, no overwrite, unsupported resolution, isolated detection rejected')
