#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
for cmd in gh swiftc git codesign plutil; do command -v "$cmd" >/dev/null; done
D=$(mktemp -d "$ROOT/pv16-obs-probe.XXXXXX")
chmod 700 "$D"
cd "$D"
REPO=nMfM1Ow5ot/champions-calc
REF=85528d89a6b4631147e1a89011864dd113939b8b
fetch() {
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/$1?ref=$REF" > "$2"
  test "$(git hash-object "$2")" = "$3"
}
fetch reader.swift reader.swift 30dd105a551da0f96d10a527abd889cae88f7874
while read -r name blob; do
  fetch "research/preview/bridge/obs/$name" "$name" "$blob"
done <<'BLOBS'
CaptureInputPolicy.swift e5d6e571498f0b6425d026aa3549857160189b4c
test_capture_policy.swift e68c1c1722c6540e5e96d75198f68e045f7f64ea
OBSFrameSource.swift 3f0331f3b3e459702d9b572ef5a198cc31b1b271
OBSProbe.swift 14ec8f3a33f72a2888a053970270b600a5d125a3
OBSInfo.plist 6fc92ed007144c29b7efcfd775a9d97c8c3d0eaf
BLOBS
while read -r name blob; do
  fetch "research/preview/bridge/$name" "$name" "$blob"
done <<'BLOBS'
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
BLOBS
echo '=== SOURCE HASHES VERIFIED ==='
cat CaptureInputPolicy.swift test_capture_policy.swift > policy_main.swift
swiftc -swift-version 5 policy_main.swift -o policy-test
./policy-test
APP="$D/ChampionsOBSResearch.app"
mkdir -p "$APP/Contents/MacOS"
cp OBSInfo.plist "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
swiftc -swift-version 5 reader.swift -o "$APP/Contents/MacOS/reader-obs"
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo '=== OBS CAMERA PROBE READY ==='
echo 'Start OBS Virtual Camera and show the intended game preview screen. No overlays or stretching.'
printf 'Press Enter to capture six samples, or Ctrl-C to stop: '
IFS= read -r _ </dev/tty
"$APP/Contents/MacOS/reader-obs" --capture obs --obs-camera-probe | tee capture-result.json
"$PY" -B - <<'PY'
import json,cv2
from pathlib import Path
import pv16f_scene_gate_v2 as scene
import legacy_geometry as legacy
r=json.loads(Path('capture-result.json').read_text())
assert r['capture_pass'] is True and len(r['samples'])==6 and r['state_paths_absent'] is True and r['shutdown'] is True
im=cv2.imread('obs-probe.png');assert im is not None
assert [im.shape[1],im.shape[0]]==[r['samples'][-1]['width'],r['samples'][-1]['height']]
g,a=scene.inspect(im)
rows=legacy.detect(im) if im.shape==(1080,1920,3) else []
summary={'schema':'pv16-obs-geometry-probe-v1','width':im.shape[1],'height':im.shape[0],
         'layout_candidate':g['layout_candidate'],'visible_candidate':g['visible_candidate'],
         'full_route_available':a is not None,'legacy_panel_count':len(rows),
         'accepted':False,'scene_authenticated':False}
print('OBS_GEOMETRY_PROBE:',json.dumps(summary,allow_nan=False))
print('OBS_CAPTURE_PROBE_PASS: six fresh callbacks converted to PNG; geometry is candidate-only')
PY
echo "PRIVATE_OUTPUT_LOCAL_ONLY=$D"
echo '=== COMPLETE: NO LIVE READER LOOP OR PRODUCTION CHANGE ==='
