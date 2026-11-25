#!/usr/bin/env python3
"""Collect six preselected frames from a user-selected new battle recording.
Uses existing OpenCV and macOS Vision only; no downloads, installs or state updates.
"""
import argparse
import hashlib
import json
import math
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

OLD_SHA='952fe95358842e2af367b13fef06c15cf98202ed44ce0c4ca804c64a1de0a581'
FRACTIONS=(.08,.28,.48,.65,.82,.95)
SWIFT=r'''
import Foundation
import Vision
import ImageIO
var rows = [[String: Any]]()
for path in CommandLine.arguments.dropFirst() {
    let start = Date()
    var row: [String: Any] = ["path": path]
    do {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        let supported = try req.supportedRecognitionLanguages()
        guard supported.contains("ja-JP") else { throw NSError(domain: "Japanese unavailable", code: 1) }
        req.recognitionLanguages = supported.contains("en-US") ? ["ja-JP", "en-US"] : ["ja-JP"]
        req.usesLanguageCorrection = false
        try VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:]).perform([req])
        row["observations"] = (req.results ?? []).compactMap { obs -> [String: Any]? in
            guard let cand = obs.topCandidates(1).first else { return nil }
            let b = obs.boundingBox
            return ["text":cand.string,"confidence":Double(cand.confidence),"box_xywh_bottom_left":[Double(b.minX),Double(b.minY),Double(b.width),Double(b.height)]]
        }
        row["revision"] = req.revision
        row["status"] = "EXECUTED_UNSCORED"
    } catch { row["status"] = "ERROR"; row["error"] = String(describing: error) }
    row["seconds"] = Date().timeIntervalSince(start)
    rows.append(row)
}
print(String(data: try JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!)
'''


def sha_file(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()


def indices(n):
    if n<12:raise ValueError('video too short')
    a=[round((n-1)*p) for p in FRACTIONS]
    if len(set(a))!=6:raise ValueError('duplicate sample frames')
    return a


def top_left(o):
    x,y,w,h=o['box_xywh_bottom_left']
    return {'text':o['text'],'confidence':o['confidence'],'xyxy':[x*1920/1920,(1-y-h)*1080/1080,(x+w)*1920/1920,(1-y)*1080/1080]}


def self_test():
    assert len(indices(8400))==6 and indices(8400)==sorted(indices(8400))
    assert 0<=indices(12)[0]<indices(12)[-1]<12
    assert top_left({'text':'x','confidence':1,'box_xywh_bottom_left':[0,0,1,1]})['xyxy']==[0,0,1,1]
    try:indices(5)
    except ValueError:pass
    else:raise AssertionError('short video accepted')
    print('Self-test PASS (4 checks)')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--video',type=Path);p.add_argument('--self-test',action='store_true');a=p.parse_args()
    if a.self_test:self_test();return 0
    if sys.platform!='darwin' or not shutil.which('swiftc'):raise SystemExit('既存macOS/Swift環境が必要です。')
    import cv2
    if a.video is None:
        pick=subprocess.run(['osascript','-e','POSIX path of (choose file with prompt "前回と異なる対戦の録画を選択してください")'],capture_output=True,text=True)
        if pick.returncode:raise SystemExit('動画選択を中止しました。')
        a.video=Path(pick.stdout.rstrip('\n'))
    video=a.video.expanduser().resolve(strict=True)
    if not video.is_file():raise SystemExit('動画ファイルではありません。')
    digest=sha_file(video)
    if digest==OLD_SHA:raise SystemExit('前回の動画と同一です。別の対戦動画を選んでください。')
    out=Path(tempfile.mkdtemp(prefix='vision-holdout-v9-',dir=Path.home()))
    (out/'frames').mkdir()
    start=time.monotonic()
    report={'schema':'ocr-diagnostic-pilot-v5','collector_version':'holdout-v9','video_sha256':digest,'video_bytes':video.stat().st_size,
            'sample_fractions':FRACTIONS,'selection_policy':'fixed fractions, no outcome-dependent frame selection','planned_ocr_max':6,
            'macos':platform.mac_ver()[0],'opencv':cv2.__version__,'frames':[],'results':[],
            'limits':['User selects a different battle. Different file hash alone does not establish independent battle.','Six samples cannot establish statistical accuracy or scene coverage.','1920x1080 only. No resize, no event emission.']}
    try:
        cap=cv2.VideoCapture(str(video))
        try:
            if not cap.isOpened():raise RuntimeError('video open failed')
            fps=cap.get(cv2.CAP_PROP_FPS);n=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            if not math.isfinite(fps) or fps<=0:raise RuntimeError('invalid FPS')
            report.update(fps=fps,frame_count=n)
            for idx in indices(n):
                if not cap.set(cv2.CAP_PROP_POS_FRAMES,idx):raise RuntimeError('seek failed')
                ok,frame=cap.read();pos=cap.get(cv2.CAP_PROP_POS_FRAMES)
                if not ok or frame.shape[:2]!=(1080,1920) or abs(pos-idx-1)>.5:raise RuntimeError('frame shape/seek mismatch; no automatic resizing')
                tag=f'f{idx:09d}';rel=f'frames/{tag}.png'
                if not cv2.imwrite(str(out/rel),frame):raise RuntimeError('image save failed')
                report['frames'].append({'case':tag,'frame_index':idx,'requested_seconds':idx/fps,'reported_next_frame':pos,'image':rel,'sha256':sha_file(out/rel)})
                report['results'].append({'case':tag,'method':'full_frame','image':rel,'rect':[0,0,1920,1080],'status':'PENDING'})
                print(f'静止画 {len(report["frames"])}/6: {idx/fps:.1f}秒',flush=True)
        finally:cap.release()
        src=out/'vision.swift';src.write_text(SWIFT,encoding='utf8');worker=out/'vision_worker'
        print('Apple Visionを一括実行（最大6枚）',flush=True)
        c=subprocess.run(['swiftc',str(src),'-o',str(worker)],capture_output=True,text=True,timeout=90)
        (out/'vision_compile.log').write_text(c.stdout+c.stderr,encoding='utf8')
        if c.returncode:raise RuntimeError('Swift compile failed')
        paths=[str(out/r['image']) for r in report['results']]
        v=subprocess.run([str(worker),*paths],capture_output=True,text=True,timeout=90)
        (out/'vision.log').write_text(v.stderr,encoding='utf8')
        if v.returncode:raise RuntimeError('Vision execution failed')
        returned=json.loads(v.stdout);mapped={r['path']:r for r in returned}
        if len(returned)!=6 or set(mapped)!=set(paths):raise RuntimeError('missing OCR outputs')
        for row,path in zip(report['results'],paths):
            row.update({k:v for k,v in mapped[path].items() if k!='path'})
            if row['status']=='EXECUTED_UNSCORED':row['boxes_original_normalized']=[top_left(o) for o in row['observations']]
    except Exception as e:
        report['error']=str(e)
        for row in report['results']:
            if row['status']=='PENDING':row.update(status='BLOCKED',error=str(e))
    report['counts']={s:sum(r['status']==s for r in report['results']) for s in ('EXECUTED_UNSCORED','ERROR','BLOCKED','PENDING')}
    report['elapsed_seconds']=round(time.monotonic()-start,3)
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    archive=out/(out.name+'-review.zip')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for f in sorted(out.rglob('*')):
            if f.is_file() and (f.suffix=='.png' or f.name in ('report.json','vision.log','vision_compile.log')):z.write(f,f.relative_to(out))
    print('結果:',report['counts'],'\n添付するファイル:',archive,flush=True)
    subprocess.run(['open','-R',str(archive)],check=False)
    return 0 if report['counts']['EXECUTED_UNSCORED']==6 else 2

if __name__=='__main__':raise SystemExit(main())
