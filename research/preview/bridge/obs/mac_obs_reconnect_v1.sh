#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
die() { echo "STOP: $*" >&2; exit 1; }
test "$(uname -s)" = Darwin || die "macOS required"
test -x "$PY" || die "Existing Python environment missing"
for cmd in gh git swiftc codesign plutil open; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
D="$(mktemp -d "$ROOT/pv16-obs-reconnect.XXXXXX")"
trap 'rc=$?; echo "RESULT_DIRECTORY=$D"; open "$D" || true; exit "$rc"' EXIT
trap 'echo "STOP: line=$LINENO exit=$?" >&2' ERR
cd "$D"
mkdir -p frames tmp
export TMPDIR="$D/tmp/" PYTHONDONTWRITEBYTECODE=1
REPO=nMfM1Ow5ot/champions-calc
REF=85528d89a6b4631147e1a89011864dd113939b8b
fetch() {
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/$1?ref=$REF" > "$2"
  test "$(git hash-object --no-filters "$2")" = "$3" || die "Source mismatch: $1"
  echo "VERIFIED: $2"
}
echo "=== 1. PINNED SOURCE ==="
while read -r name blob; do
  fetch "research/preview/bridge/obs/$name" "$name" "$blob"
done <<'BLOBS'
CaptureInputPolicy.swift e5d6e571498f0b6425d026aa3549857160189b4c
OBSFrameSource.swift 3f0331f3b3e459702d9b572ef5a198cc31b1b271
OBSInfo.plist 6fc92ed007144c29b7efcfd775a9d97c8c3d0eaf
BLOBS
while read -r name blob; do
  fetch "research/preview/bridge/$name" "$name" "$blob"
done <<'BLOBS'
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
BLOBS
cp OBSFrameSource.swift OBSFrameSourceDiagnostic.swift
cat >> OBSFrameSourceDiagnostic.swift <<'SWIFT'

// Read-only diagnostics; original capture methods remain byte-identical.
extension OBSFrameSource {
    func diagnosticSnapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let t = now()
        let age: Any = latest.map { (t - $0.0.uptime) * 1000 } as Any? ?? NSNull()
        return ["generation": generation, "sequence": sequence,
                "consumed": consumed, "latest_age_ms": age,
                "pending": pending, "active": active != nil,
                "status": status]
    }
}
SWIFT
cat > main.swift <<'SWIFT'
import Foundation
import AppKit

func run() -> Int32 {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard root.lastPathComponent.hasPrefix("pv16-obs-reconnect."),
          let opts = CaptureInputOptions.parse(["--capture", "obs"]),
          let attrs = try? FileManager.default.attributesOfItem(atPath: root.path),
          let mode = attrs[.posixPermissions] as? NSNumber,
          mode.intValue & 0o077 == 0 else { return 2 }
    let source = OBSFrameSource.shared
    var rows = [[String: Any]]()
    var completed = false
    var stopped = false
    var phase = "initial"
    func now() -> Double { ProcessInfo.processInfo.systemUptime }
    func report() {
        let absent = ["state.json","battle.log","battle_protocol.log","my_team.json","logs"].allSatisfy {
            !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let result: [String: Any] = ["schema":"pv16-obs-reconnect-v1",
            "completed":completed, "shutdown":stopped,
            "state_paths_absent":absent, "last_phase":phase, "samples":rows]
        do {
            let data = try JSONSerialization.data(withJSONObject:result, options:[.sortedKeys,.prettyPrinted])
            try data.write(to:root.appendingPathComponent("capture-result.json"),options:.atomic)
        } catch { fputs("REPORT_WRITE_FAILED\n",stderr) }
    }
    defer {
        stopped = source.shutdown()
        report()
        Swift.print("SHUTDOWN: \(stopped)")
        fflush(stdout)
    }
    func prompt(_ s:String) -> Bool {
        Swift.print(s)
        fflush(stdout)
        return readLine() != nil
    }
    @discardableResult
    func capture(_ phase:String,_ t0:Double,_ timeout:Double) -> Bool {
        let n=rows.count+1
        let name=String(format:"frames/%03d.png",n)
        let dst=root.appendingPathComponent(name)
        let before=source.diagnosticSnapshot()
        let start=now()
        let error=source.writePNG(dst.path,options:opts,timeout:timeout)
        let elapsed=(now()-start)*1000
        let after=source.diagnosticSnapshot()
        let exists=FileManager.default.fileExists(atPath:dst.path)
        let success=error == nil && exists
        let row:[String:Any]=["phase":phase,"sample":n,
            "phase_elapsed_ms":(start-t0)*1000,"capture_ms":elapsed,
            "success":success,"file_exists":exists,
            "file":success ? name : "",
            "error":error as Any? ?? NSNull(),
            "before":before,"after":after]
        rows.append(row); report()
        Swift.print("\(phase) #\(n): \(success ? "FRAME" : "NO_FRAME") \(Int(elapsed))ms")
        fflush(stdout)
        return success
    }
    func sampleWindow(_ name:String,_ seconds:Double) {
        let t0=now()
        var count=0
        while now()-t0 < seconds && count < 20 {
            capture(name,t0,1.25)
            count += 1
            Thread.sleep(forTimeInterval:0.8)
        }
    }

    guard prompt("OBS Virtual Camera ON, show a stable game selection screen. Ensure no production app uses OBS. Press Enter to begin; Ctrl-C to abort.") else { return 3 }
    phase="baseline"
    let t0=now()
    for i in 0..<3 {
        guard capture(phase,t0,i==0 ? 30 : 5) else { return 4 }
        Thread.sleep(forTimeInterval:0.5)
    }
    guard prompt("Stop ONLY OBS Virtual Camera in OBS. After it stops, return here and press Enter. Do not quit OBS or stop production processes.") else { return 3 }
    phase="stopped"
    sampleWindow(phase,12)
    guard prompt("Start OBS Virtual Camera again; restore the same game selection screen. Press Enter after clicking Start.") else { return 3 }
    phase="restarted"
    sampleWindow(phase,18)
    completed=true
    phase="complete"
    return 0
}
exit(run())
SWIFT

echo "=== 2. BUILD CAMERA-ONLY PROBE ==="
APP="$D/ChampionsOBSResearch.app"
mkdir -p "$APP/Contents/MacOS"
cp OBSInfo.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
"$PY" -B - "$APP/Contents/MacOS/reader-obs" <<'PY'
import os, signal, subprocess, sys, time
with open("build.log","w") as log:
    p=subprocess.Popen(["swiftc","-swift-version","5","CaptureInputPolicy.swift","OBSFrameSourceDiagnostic.swift","main.swift","-o",sys.argv[1]], stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    start=time.monotonic()
    try:
        while p.poll() is None:
            if time.monotonic()-start>120:
                raise TimeoutError("Swift build timeout")
            print("BUILD RUNNING",round(time.monotonic()-start,1),"s",flush=True)
            time.sleep(3)
    except BaseException:
        try: os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()
        raise
    if p.returncode: raise SystemExit("Build failed; see build.log")
print("BUILD PASS")
PY
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "=== 3. INTERACTIVE OBS RECOVERY ==="
set +e
"$PY" -B - "$APP/Contents/MacOS/reader-obs" <<'PY'
import subprocess,sys
with open("/dev/tty") as tty:
    try:
        r=subprocess.run([sys.argv[1]],stdin=tty,timeout=300)
        sys.exit(r.returncode)
    except subprocess.TimeoutExpired:
        print("PROBE TIMEOUT; child terminated")
        sys.exit(124)
PY
probe_rc=$?
set -e
echo "PROBE EXIT: $probe_rc"

echo "=== 4. AGGREGATE REVIEW ==="
"$PY" -B - <<'PY'
import json, hashlib
from pathlib import Path
import cv2
import pv16f_scene_gate_v2 as scene

p=Path("capture-result.json")
if not p.is_file(): raise SystemExit("STOP: no capture result")
r=json.loads(p.read_text())
rows=r["samples"]
for x in rows:
    x["layout_visible_candidate"]=False
    x["consumption_advanced"]=int(x["after"]["consumed"])>int(x["before"]["consumed"])
    if x["success"]:
        path=Path(x["file"])
        im=cv2.imread(str(path))
        x["decoded"]=im is not None
        if im is not None:
            x["width"],x["height"]=im.shape[1],im.shape[0]
            g,a=scene.inspect(im)
            x["layout_visible_candidate"]=a is not None
            x["pixel_sha256"]=hashlib.sha256(im.tobytes()).hexdigest()
    elif x["file_exists"]:
        x["unexpected_failed_output"]=True
def group(name):
    q=[x for x in rows if x["phase"]==name]
    good=[x for x in q if x["success"]]
    visible=[x for x in good if x["layout_visible_candidate"]]
    return {"attempts":len(q),"frames":len(good),"no_frame":len(q)-len(good),
            "visible_candidates":len(visible),
            "unique_decoded_pixel_hashes":len({x["pixel_sha256"] for x in good if "pixel_sha256" in x}),
            "first_frame_ms":round(good[0]["phase_elapsed_ms"]+good[0]["capture_ms"],3) if good else None,
            "first_visible_ms":round(visible[0]["phase_elapsed_ms"]+visible[0]["capture_ms"],3) if visible else None,
            "generation_start":q[0]["before"]["generation"] if q else None,
            "generation_end":q[-1]["after"]["generation"] if q else None,
            "sequence_start":q[0]["before"]["sequence"] if q else None,
            "sequence_end":q[-1]["after"]["sequence"] if q else None,
            "callback_sequence_advance":int(q[-1]["after"]["sequence"])-int(q[0]["before"]["sequence"]) if q else None,
            "error_counts":{e:sum(x.get("error")==e for x in q) for e in sorted({x["error"] for x in q if isinstance(x.get("error"),str)})}}
b,o,n=(group(s) for s in ("baseline","stopped","restarted"))
contract=bool(rows) and all((not x["success"] and not x["file_exists"]) or (x["success"] and x["consumption_advanced"] and x.get("decoded")) for x in rows)
base_hashes={x.get("pixel_sha256") for x in rows if x["phase"]=="baseline" and x["success"]}
new_visible=[x for x in rows if x["phase"]=="restarted" and x["layout_visible_candidate"]]
changed_visible=any(x.get("pixel_sha256") not in base_hashes for x in new_visible)
if not r["completed"] or not r["shutdown"] or not r["state_paths_absent"] or not contract:
    result="INCOMPLETE_OR_CONTRACT_FAILURE"
elif b["visible_candidates"]!=3 or n["visible_candidates"]<3:
    result="GAME_LAYOUT_RECOVERY_NOT_ESTABLISHED"
elif o["frames"]==0 and o["attempts"]>=2:
    result=("CALLBACK_GAP_AND_LAYOUT_RECOVERY_CANDIDATE" if o["callback_sequence_advance"]==0
            else "NO_FRAME_WITH_CALLBACK_ACTIVITY_AND_LAYOUT_RECOVERY_CANDIDATE")
elif o["visible_candidates"]==0 and o["frames"]>0:
    result="NON_GAME_OUTPUT_AND_LAYOUT_RECOVERY_CANDIDATE"
else:
    result="STOP_EFFECT_INCONCLUSIVE"
summary={"schema":"pv16-obs-reconnect-summary-v1","baseline":b,"stopped":o,"restarted":n,
         "result":result,"fresh_consumption_contract":contract,"shutdown":r["shutdown"],
         "state_paths_absent":r["state_paths_absent"],"completed":r["completed"],
         "restarted_visible_pixels_differ_from_baseline":changed_visible,
         "scene_authenticated":False,"accepted":False}
Path("review-local.json").write_text(json.dumps(rows,indent=2))
Path("aggregate-result.json").write_text(json.dumps(summary,indent=2))
print(json.dumps(summary,indent=2))
print("REVIEW: share aggregate-result.json or terminal summary only; raw frames remain private")
PY
test "$probe_rc" -eq 0 || die "Probe did not complete normally"
echo "=== FINISHED: NO PRODUCTION READER OR CODEX ==="
