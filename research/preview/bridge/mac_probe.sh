#!/usr/bin/env bash
set -euo pipefail
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

D="$(mktemp -d "$ROOT/pv16-reader-shadow.XXXXXX")"
chmod 700 "$D"
cd "$D"
REF=5da26d5d49cd338e25b1085645f12ec771f96645
REPO=nMfM1Ow5ot/champions-calc
fetch() {
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/$1?ref=$REF" > "$2"
  test "$(git hash-object "$2")" = "$3"
}
fetch reader.swift reader.swift fa8152abd137d8ccaeb32f12fac8cb65b319ff43
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
test_pv16f_integrated_v2.py adf93c73405cffd80740e7fda724e4316597acb7
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
test_shadow.py 75b7a3cb87c14c43fdc9cc81a9ba8d9f8ca265f6
BLOBS
export PV16_SHADOW_WORKER="$D/pv16_shadow_worker.py"
echo '=== VERIFIED SOURCE / PYTHON CONTRACTS ==='
"$PY" -B -m unittest -v test_pv16f_integrated_v2
"$PY" -B test_shadow.py
echo '=== PREPARE PRIVATE IMAGE PROBE ==='
"$PY" -B - <<'PY'
import json,os
from pathlib import Path
import cv2
import pv16_shadow_worker as w
cv2.setNumThreads(1)
r,t,g,data=w.load_assets(Path(os.environ['PV16_SHADOW_BUNDLE']),Path(os.environ['PV16_SHADOW_ARCHIVE']))
local,gb=w.banks(t,g)
im=data[0][1]
assert cv2.imwrite('probe.png',im)
expected=w.analyze(im,r,local,gb)
assert expected['status']=='ranked'
Path('expected.json').write_text(json.dumps(expected))
PY
echo '=== COMPILE ISOLATED READER (MAC) ==='
swiftc -swift-version 5 reader.swift -o reader-shadow
echo '=== OFFLINE SWIFT TO PYTHON PROBE ==='
./reader-shadow --preview-shadow-image "$D/probe.png" > "$D/probe-result.json"
"$PY" -B - <<'PY'
import json,math
from pathlib import Path
a=json.loads(Path('expected.json').read_text())
b=json.loads(Path('probe-result.json').read_text())
assert b['accepted'] is False and b['scene_authenticated'] is False
assert b['status']=='ranked' and b['route']==a['route']
assert b['types']==a['types'] and b['recovered']==a['recovered']
assert len(a['slots'])==len(b['slots'])==6
for x,y in zip(a['slots'],b['slots']):
    if x is None or y is None:assert x is y;continue
    assert len(x)==len(y)
    for (i,d),(j,e) in zip(x,y):assert i==j and math.isclose(d,e,rel_tol=1e-8,abs_tol=1e-8)
for name in ('state.json','battle.log','battle_protocol.log','my_team.json'):
    assert not Path(name).exists(), 'unexpected state file: '+name
print('MAC_OFFLINE_BRIDGE_PASS: six slots, matching top-five candidates and scores, no state files')
PY
echo "LOCAL_OUTPUT=$D"
echo '=== COMPLETE: NO LIVE LOOP OR PRODUCTION CHANGE ==='
