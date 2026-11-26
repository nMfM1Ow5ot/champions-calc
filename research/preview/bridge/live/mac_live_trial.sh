#!/usr/bin/env bash
set -euo pipefail
umask 077
export LC_ALL=C
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
command -v gh >/dev/null
command -v swiftc >/dev/null
command -v git >/dev/null

find_verified() {
  "$PY" - "$1" "$2" <<'PY'
import hashlib,sys
from pathlib import Path
home=Path.home()
for folder in (home/'Downloads',home/'Desktop',home/'Documents',home):
    for p in sorted(folder.glob(sys.argv[1])):
        if p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==sys.argv[2]:
            print(p);sys.exit(0)
sys.exit('STOP: verified archive not found: '+sys.argv[1])
PY
}
export PV16_SHADOW_BUNDLE="$(find_verified 'PV16-F-R4*.zip' 36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef)"
export PV16_SHADOW_ARCHIVE="$(find_verified 'preview_images_all*.zip' 570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7)"
export PV16_SHADOW_PYTHON="$PY"
echo 'VERIFIED: both private archives'
D="$(mktemp -d "$ROOT/pv16-live-trial.XXXXXX")"
chmod 700 "$D"
cd "$D"
mkdir data
REF=bc7464b02235a8bacb6bfc32e2007c2e6885a5a3
REPO=nMfM1Ow5ot/champions-calc
fetch() {
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/$1?ref=$REF" > "$2"
  test "$(git hash-object "$2")" = "$3"
}
fetch reader.swift reader.swift fa8152abd137d8ccaeb32f12fac8cb65b319ff43
while read -r name blob; do
  fetch "data/$name" "data/$name" "$blob"
done <<'BLOBS'
names_index.json 4b6f028a7cd29b3276f6ab5af84845bf034ea3ab
species_types.json bfeba203f6cd0d891d56ae60a5ec4f761209cb6b
preview_features.json 16052f6a51447db3fc41fe2e2debdf1a795bd01c
type_icons.json c4ca6c06022f70e6bbf9edc168e7f86b0d6b06a0
BLOBS
while read -r name blob; do
  fetch "research/preview/bridge/$name" "$name" "$blob"
done <<'BLOBS'
pv16_shadow_worker.py 71506eb4f9dde3697d782579ed8c075467d4174c
PreviewShadowBridge.swift 86c01a1648cd9abb7714709b95cd43bdab82a5db
pv16f_joint_candidate_v2.py 573be1ef1e422c285c680906ed56413dc649cee5
pv16f_coverage_v2.py be0ff17d08ca8b52dace5fb004da210e9fd41ee2
pv16f_temporal_fusion_v1.py aa40601d4c0ac6475bebbe3383beabf18a50cf40
pv16f_residual_v1.py eeddf54c86ecd9938e4b2f713e69e17639241468
pv16f_integrated_v2.py cb63e9347b82163c4aefa56c25230abe902ff407
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
BLOBS
while read -r name blob; do
  fetch "research/preview/bridge/live/$name" "$name" "$blob"
done <<'BLOBS'
LiveShadowSupport.swift 5dec4820412b43a2e70985b385d200bd71d561c8
LiveShadowDriver.swift 7119200b3f25ff794331d02a778dcb99060fd31c
build_trial.py 2af5269b3cd98366b2f7209073d2e147debce790
run_trial.py 2e71f71bd10eb79d85189ab20ed559904fa4fa6d
test_trial_aggregate.py cb53fb5a4c460db575e1690e0fc2aa00f797472f
test_support.swift 10ae1b4b2907a777e5f29d664be6e910ee3d3e78
BLOBS
export PV16_SHADOW_WORKER="$D/pv16_shadow_worker.py"
echo '=== VERIFIED: 21 SOURCE AND DICTIONARY BLOBS ==='
"$PY" -B -m unittest -v test_trial_aggregate
"$PY" -B - <<'PY'
from pathlib import Path
import os,cv2
import pv16_shadow_worker as w
r,t,g,data=w.load_assets(Path(os.environ['PV16_SHADOW_BUNDLE']),Path(os.environ['PV16_SHADOW_ARCHIVE']))
assert cv2.imwrite('probe.png',data[0][1])
PY
cat PreviewShadowBridge.swift LiveShadowSupport.swift test_support.swift > support_probe.swift
swiftc -swift-version 5 support_probe.swift -o support-probe
./support-probe "$D/probe.png"
rm -- "$D/probe.png"
"$PY" -B build_trial.py
swiftc -swift-version 5 reader_live_trial.swift -o reader-live-trial
echo '=== PREPARATION COMPLETE: NO PRODUCTION READER RESTART ==='
echo "ISOLATED_LOCAL_DIRECTORY=$D"
echo 'Start only when the normal reader is already capturing the intended QuickTime game window.'
echo 'During an allowed practice session, show both preview and non-preview screens.'
printf 'Press Enter to start the bounded read-only trial, or Ctrl-C to stop here: '
IFS= read -r _ </dev/tty
"$PY" -B run_trial.py
