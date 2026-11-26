#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
export LC_ALL=C PYTHONDONTWRITEBYTECODE=1
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
die() { echo "STOP: $*" >&2; exit 1; }
test "$(uname -s)" = Darwin || die "macOS required"
test -x "$PY" || die "Existing Python environment missing"
for cmd in gh git swiftc codesign plutil open; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
D="$(mktemp -d "$ROOT/pv16-obs-live-shadow.XXXXXX")"
trap 'rc=$?; echo "RESULT_DIRECTORY=$D"; open "$D" || true; exit "$rc"' EXIT
trap 'echo "STOP: line=$LINENO exit=$?" >&2' ERR
cd "$D"
mkdir -p data tmp
export TMPDIR="$D/tmp/"
export PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
REPO=nMfM1Ow5ot/champions-calc
OLD=8fe118aefba0867979cbf49a14d068fc8bf37205
NEW=5da26d5d49cd338e25b1085645f12ec771f96645
OBS=85528d89a6b4631147e1a89011864dd113939b8b
LIVE=bc7464b02235a8bacb6bfc32e2007c2e6885a5a3
fetch() {
  local path="$1" ref="$2" dst="$3" expected="$4" candidate
  for candidate in "$ROOT"/pv16-native-compare-v11.*/"$dst" "$ROOT"/pv16-obs-reconnect.*/"$dst"; do
    if [ -f "$candidate" ] && [ "$(git hash-object --no-filters "$candidate")" = "$expected" ]; then
      cp "$candidate" "$dst"
      break
    fi
  done
  if [ ! -f "$dst" ]; then
    gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/$path?ref=$ref" > "$dst"
  fi
  test "$(git hash-object --no-filters "$dst")" = "$expected" || die "Source mismatch: $path"
  echo "VERIFIED: $dst"
}
find_verified() {
  "$PY" -B - "$1" "$2" <<'PY'
import hashlib,sys
from pathlib import Path
home=Path.home()
for folder in (home/'Downloads',home/'Desktop',home/'Documents',home):
    for p in sorted(folder.glob(sys.argv[1])):
        if not p.is_file():continue
        h=hashlib.sha256()
        with p.open('rb') as f:
            for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
        if h.hexdigest()==sys.argv[2]:
            print(p);sys.exit(0)
sys.exit('STOP: verified archive not found: '+sys.argv[1])
PY
}
echo "=== 1. ASSET AND SOURCE INTEGRITY ==="
export PV16_SHADOW_BUNDLE="$(find_verified 'PV16-F-R4*.zip' 36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef)"
export PV16_SHADOW_ARCHIVE="$(find_verified 'preview_images_all*.zip' 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7)"
export PV16_SHADOW_PYTHON="$PY" PV16_SHADOW_WORKER="$D/pv16_shadow_worker.py"
fetch reader.swift "$OLD" reader-original.swift 038267041215f0f47e76156acf32ea7d0977a9fd
while read -r name blob; do fetch "data/$name" "$OLD" "data/$name" "$blob"; done <<'BLOBS'
names_index.json 4b6f028a7cd29b3276f6ab5af84845bf034ea3ab
preview_features.json 16052f6a51447db3fc41fe2e2debdf1a795bd01c
species_types.json bfeba203f6cd0d891d56ae60a5ec4f761209cb6b
type_icons.json c4ca6c06022f70e6bbf9edc168e7f86b0d6b06a0
BLOBS
while read -r name blob; do fetch "research/preview/bridge/obs/$name" "$OBS" "$name" "$blob"; done <<'BLOBS'
CaptureInputPolicy.swift e5d6e571498f0b6425d026aa3549857160189b4c
OBSFrameSource.swift 3f0331f3b3e459702d9b572ef5a198cc31b1b271
OBSInfo.plist 6fc92ed007144c29b7efcfd775a9d97c8c3d0eaf
BLOBS
while read -r name blob; do fetch "research/preview/bridge/$name" "$NEW" "$name" "$blob"; done <<'BLOBS'
pv16_shadow_worker.py 71506eb4f9dde3697d782579ed8c075467d4174c
pv16f_joint_candidate_v2.py 573be1ef1e422c285c680906ed56413dc649cee5
pv16f_coverage_v2.py be0ff17d08ca8b52dace5fb004da210e9fd41ee2
pv16f_temporal_fusion_v1.py aa40601d4c0ac6475bebbe3383beabf18a50cf40
pv16f_residual_v1.py eeddf54c86ecd9938e4b2f713e69e17639241468
pv16f_integrated_v2.py cb63e9347b82163c4aefa56c25230abe902ff407
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
PreviewShadowBridge.swift 86c01a1648cd9abb7714709b95cd43bdab82a5db
BLOBS
while read -r name blob; do fetch "research/preview/bridge/live/$name" "$LIVE" "$name" "$blob"; done <<'BLOBS'
LiveShadowSupport.swift 5dec4820412b43a2e70985b385d200bd71d561c8
run_trial.py 2e71f71bd10eb79d85189ab20ed559904fa4fa6d
test_trial_aggregate.py cb53fb5a4c460db575e1690e0fc2aa00f797472f
BLOBS

echo "=== 2. REUSE AGGREGATE CONTRACT TESTS ==="
"$PY" -B -m unittest -v test_trial_aggregate

echo "=== 3. BUILD ISOLATED DIAGNOSTIC ==="
cat > driver.swift <<'SWIFT'
import CryptoKit

// New diagnostic accessor. Does not alter capture methods.
extension OBSFrameSource {
    func diagnosticConsumed() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return consumed
    }
}

let teamMode = false

// Same keyword predicate and Vision options as original legacy detector.
// Excludes original observation logging and trainer extraction.
func shadowProbeScene(_ image: CGImage) -> Bool? {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ja-JP", "en-US"]
    req.usesLanguageCorrection = false
    req.regionOfInterest = CGRect(x:0,y:0,width:1,height:1)
    do { try VNImageRequestHandler(cgImage:image,options:[:]).perform([req]) }
    catch { return nil }
    return (req.results ?? []).contains { $0.topCandidates(1).first?.string.contains("選出") ?? false }
}

func obsShadowTrial() -> Int32 {
    let root=scriptDir
    guard root.lastPathComponent.hasPrefix("pv16-obs-live-shadow."),
          let attrs=try? FileManager.default.attributesOfItem(atPath:root.path),
          let mode=attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0,
          let opts=CaptureInputOptions.parse(["--capture","obs"]) else { return 2 }
    loadDict(); loadPreviewData()
    guard pvDataLoaded, !speciesDict.isEmpty else { return 3 }
    let source=OBSFrameSource.shared, bridge=PreviewShadowBridge()
    let records=ShadowTrialRecords(), fm=FileManager.default
    let pngURL=root.appendingPathComponent("diagnostic-frame.png")
    let marker=root.appendingPathComponent("phase-active.txt")
    func now()->Double { ProcessInfo.processInfo.systemUptime }
    func prompt(_ s:String)->Bool {
        Swift.print(s); fflush(stdout); return readLine() != nil
    }
    var frames=0, scheduled=0, skipped=0, failed=0, decodeFailed=0, ocrFailed=0
    var phases=[[String:Any]](), completed=false
    var workerCleaned=false, captureShutdown=false
    let warmStart=now()
    let (ready,owned)=bridge.trialWarmup()
    let warmMS=(now()-warmStart)*1000
    let started=now()
    defer {
        try? fm.removeItem(at:marker)
        try? fm.removeItem(at:pngURL)
        workerCleaned=bridge.trialFinish(owned:owned)
        captureShutdown=source.shutdown()
        let absent=["state.json","battle.log","battle_protocol.log","my_team.json","logs","champions_frames"].allSatisfy {
            !fm.fileExists(atPath:root.appendingPathComponent($0).path)
        } && !fm.fileExists(atPath:root.appendingPathComponent("tmp/champions_frames").path)
        let report:[String:Any]=["schema":"pv16-live-trial-v1","scope":"isolated_obs_same_png",
            "accepted":false,"warmup_ms":warmMS,"sampling_elapsed_ms":phases.reduce(0.0){$0+($1["elapsed_ms"] as? Double ?? 0)},
            "polls":["scheduled":scheduled,"schedule_skipped":skipped,"capture_failed":failed,"decode_failed":decodeFailed,"ocr_failed":ocrFailed],
            "frames":records.all(),"worker_cleaned":workerCleaned,"state_paths_absent":absent,
            "capture_shutdown":captureShutdown,"completed":completed,"phases":phases,
            "total_after_warmup_ms":(now()-started)*1000]
        do {
            let data=try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys])
            try data.write(to:root.appendingPathComponent("private-pairs.json"),options:.atomic)
        } catch { fputs("REPORT_WRITE_FAILED\n",stderr) }
        Swift.print("CLEANUP worker=\(workerCleaned) camera=\(captureShutdown) local_state_absent=\(absent)")
        fflush(stdout)
    }
    guard ready else { return 4 }
    guard prompt("OBS Virtual Camera ON. No other app/production reader may use it. Show a practice/replay selection screen; press Enter. Ctrl-C aborts.") else { return 5 }
    guard source.writePNG(pngURL.path,options:opts,timeout:30)==nil else { return 6 }
    try? fm.removeItem(at:pngURL)
    func phase(_ name:String,_ n:Int) {
        let t0=now(), period=1.0
        let baseFrames=frames, baseSkipped=skipped, baseFailed=failed, baseDecode=decodeFailed
        try? name.write(to:marker,atomically:true,encoding:.utf8)
        defer { try? fm.removeItem(at:marker) }
        for i in 0..<n {
            scheduled+=1
            let planned=t0+Double(i)*period
            let delay=planned-now()
            if delay>0 { Thread.sleep(forTimeInterval:delay) }
            if now()-planned>=period { skipped+=1; continue }
            let begin=now(), before=source.diagnosticConsumed()
            try? fm.removeItem(at:pngURL)
            guard source.writePNG(pngURL.path,options:opts,timeout:1.25)==nil else { failed+=1; continue }
            let pngReady=now(), after=source.diagnosticConsumed()
            guard after>before, let raw=try? Data(contentsOf:pngURL), raw.count<=16*1024*1024,
                  let im=loadImage(path:pngURL.path) else { decodeFailed+=1; continue }
            try? fm.removeItem(at:pngURL)
            frames+=1
            let index=frames, digest=SHA256.hash(data:raw).map{String(format:"%02x",$0)}.joined()
            let offerMS=(now()-pngReady)*1000
            records.set(index,["frame":index,"frame_sha256":digest,"phase":name,
                "width":im.width,"height":im.height,"snapshot_age_ms":offerMS,
                "capture_ms":(pngReady-begin)*1000,"schedule_late_ms":(begin-planned)*1000,
                "consumed_advanced":true,"legacy_gate":false,"legacy_gate_ms":0.0,
                "legacy_rank_ms":0.0,"legacy_names":[] as [String],"new_status":"submitted","accepted":false])
            let offer=bridge.trialOffer(png:raw,frame:index,legacy:[]) { result,ms in
                var fields:[String:Any]=["new_exchange_ms":ms,"new_status":"bridge_failure"]
                if let q=result,q["frame_sha256"] as? String == digest,
                   q["accepted"] as? Bool == false,q["scene_authenticated"] as? Bool == false,
                   let status=q["status"] as? String {
                    fields["new_status"]=status; fields["new_result"]=q
                } else if result != nil { fields["new_status"]="integrity_failure" }
                records.set(index,fields)
            }
            if offer != "submitted" { records.set(index,["new_status":offer]) }
            let gateStart=now()
            let gate=shadowProbeScene(im)
            let gateMS=(now()-gateStart)*1000
            if gate==nil { ocrFailed+=1 }
            let rankStart=now()
            let old=gate==true ? identifyPreview(image:im) : nil
            let rankMS=(now()-rankStart)*1000
            records.set(index,["legacy_gate":gate==true,"legacy_gate_ms":gateMS,
                "legacy_rank_ms":rankMS,"legacy_names":(old?.team ?? []).map{$0 as Any? ?? NSNull()},
                "legacy_ocr_ok":gate != nil])
            Swift.print("\(name) \(i+1)/\(n) capture=\(Int((pngReady-begin)*1000))ms offer=\(offer)")
            fflush(stdout)
        }
        phases.append(["phase":name,"scheduled":n,"captured":frames-baseFrames,
                       "skipped":skipped-baseSkipped,"capture_failed":failed-baseFailed,
                       "decode_failed":decodeFailed-baseDecode,"elapsed_ms":(now()-t0)*1000])
    }
    phase("preview_a",12)
    guard prompt("Show a NON-selection screen (e.g. team list/menu). Keep it visible. Press Enter.") else { return 5 }
    phase("non_preview",10)
    guard prompt("Show the selection screen again. Keep it visible. Press Enter.") else { return 5 }
    phase("preview_b",12)
    completed=true
    return 0
}
exit(obsShadowTrial())
SWIFT

"$PY" -B - <<'PY'
from pathlib import Path
src=Path('reader-original.swift').read_text()
marker='// MARK: - メイン'
assert src.count(marker)==1
prefix,old=src.split(marker)
assert all(x in old for x in ('loadDict()','startCaptureServer()','recognitionMainLoop()'))
bridge=Path('PreviewShadowBridge.swift').read_text()
a='URL(fileURLWithPath: "/tmp", isDirectory: true)'
assert bridge.count(a)==1
# Private spool stays inside this trial, not shared /tmp.
bridge=bridge.replace(a,'scriptDir.appendingPathComponent("tmp", isDirectory: true)')
parts=[prefix,Path('CaptureInputPolicy.swift').read_text(),Path('OBSFrameSource.swift').read_text(),bridge,
       Path('LiveShadowSupport.swift').read_text(),Path('driver.swift').read_text()]
Path('main.swift').write_text('\n\n'.join(parts))
print('ENTRYPOINT ISOLATED: production main excluded; original recognizers retained')
PY

APP="$D/ChampionsOBSResearch.app"
mkdir -p "$APP/Contents/MacOS"
cp OBSInfo.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
"$PY" -B - "$APP/Contents/MacOS/reader-obs" <<'PY'
import os,signal,subprocess,sys,time
with open('build.log','w') as log:
    p=subprocess.Popen(['swiftc','-swift-version','5','-O','main.swift','-o',sys.argv[1]],stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    t=time.monotonic()
    try:
        while p.poll() is None:
            if time.monotonic()-t>300:raise TimeoutError('Swift compilation exceeded 300s')
            print('BUILD RUNNING',round(time.monotonic()-t,1),'s',flush=True)
            time.sleep(4)
    except BaseException:
        if p.poll() is None:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
            p.wait()
        raise
    if p.returncode:raise SystemExit('Build failed: see build.log')
print('BUILD PASS')
PY
codesign --force --sign - "$APP"
codesign --verify "$APP"

echo "=== 4. BOUNDED LIVE SHADOW ==="
# Reuse previously tested supervisor and aggregate code.
"$PY" -B - <<'PY'
from pathlib import Path
s=Path('run_trial.py').read_text()
def replace(a,b):
    global s
    assert s.count(a)==1,a
    s=s.replace(a,b)
replace("root.name.startswith('pv16-live-trial.')","root.name.startswith('pv16-obs-live-shadow.')")
replace("p=subprocess.Popen([str(root/'reader-live-trial'),'--read-only-live-trial','90','60'],start_new_session=True)",
        "with open('/dev/tty') as tty:\n        p=subprocess.Popen([str(root/'ChampionsOBSResearch.app/Contents/MacOS/reader-obs')],stdin=tty,start_new_session=True)")
replace("deadline=time.monotonic()+140","deadline=time.monotonic()+300")
replace("if active:cpu.append(sum(x[1] for x in active));rss.append(sum(x[2] for x in active))",
        "if active and (root/'phase-active.txt').is_file():cpu.append(sum(x[1] for x in active));rss.append(sum(x[2] for x in active))")
replace("if child:child_cpu.append(sum(x[1] for x in child));child_rss.append(sum(x[2] for x in child))",
        "if child and (root/'phase-active.txt').is_file():child_cpu.append(sum(x[1] for x in child));child_rss.append(sum(x[2] for x in child))")
replace("if f.exists():out.update(summarize(json.loads(f.read_text())))",
"""if f.exists():
        v=json.loads(f.read_text());out.update(summarize(v))
        out['png_ready_to_offer_ms']=out.pop('snapshot_age_ms')
        out['capture_png_ms']=timing([r['capture_ms'] for r in v['frames']])
        out['schedule_late_ms']=timing([r['schedule_late_ms'] for r in v['frames']])
        out['capture_shutdown']=v['capture_shutdown'];out['completed']=v['completed']
        out['phases']=[]
        for p0 in v['phases']:
            rows=[r for r in v['frames'] if r['phase']==p0['phase']]
            out['phases'].append(dict(p0,new_status=dict(Counter(r['new_status'] for r in rows)),
                 legacy_gate_positive=sum(r['legacy_gate'] for r in rows),
                 full_layout_candidates=sum((r.get('new_result') or {}).get('route')=='full_layout_candidate' for r in rows),
                 legacy_ocr_errors=sum(not r['legacy_ocr_ok'] for r in rows)))
        out['limited_transport_pass']=bool(out['limited_transport_pass'] and v['completed'] and v['capture_shutdown']
             and v['polls']['decode_failed']==0 and v['polls']['ocr_failed']==0
             and all(r['consumed_advanced'] for r in v['frames']))
        phase={p['phase']:p for p in out['phases']}
        out['phase_evidence_sufficient']=bool(set(phase)=={'preview_a','non_preview','preview_b'}
             and all(phase[k]['full_layout_candidates']>=3 for k in ('preview_a','preview_b'))
             and phase['non_preview']['new_status'].get('held',0)>=3)
        out['negative_phase_ranked_candidates']=phase.get('non_preview',{}).get('new_status',{}).get('ranked',0)
        out['resource_samples_present']=bool(cpu and rss and child_cpu and child_rss)
        out['true_capture_drop_rate_measured']=False
        out['production_incremental_load_measured']=False
        out['phase_ground_truth_independently_verified']=False""")
Path('run_obs_trial.py').write_text(s)
print('SUPERVISOR ADAPTED: own process tree only; active-phase resource samples')
PY
"$PY" -B run_obs_trial.py
echo "=== COMPLETE: SEND AGGREGATE ONLY ==="
