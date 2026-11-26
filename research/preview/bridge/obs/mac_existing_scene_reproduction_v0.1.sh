#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
D="$(mktemp -d "$ROOT/pv16-existing-scene-repro.XXXXXX")"
REPORT="$D/anonymous-existing-scene-reproduction-v0.1.json"
trap 'rc=$?; echo "RESULT_DIRECTORY=$D"; if [ -f "$REPORT" ]; then open -R "$REPORT"; elif [ -f "$D/analysis.log" ]; then open -R "$D/analysis.log"; else open "$D"; fi; exit "$rc"' EXIT
cd "$D"
export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
REPO=nMfM1Ow5ot/champions-calc
REF=5da26d5d49cd338e25b1085645f12ec771f96645
while read -r n sha; do
  for p in "$ROOT"/pv16-scene-geometry-study.*/"$n" "$ROOT"/pv16-obs-live-shadow.*/"$n"; do
    if [ -f "$p" ] && [ "$(git hash-object --no-filters "$p")" = "$sha" ]; then cp "$p" "$n"; break; fi
  done
  if [ ! -f "$n" ]; then
    gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/research/preview/bridge/$n?ref=$REF" > "$n"
  fi
  test "$(git hash-object --no-filters "$n")" = "$sha"
done <<'BLOBS'
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
BLOBS
# Reuse the actual prior PV01/PV11 implementation, fixed to the audited snapshot.
REF=cf01e65803d419dcb668ef70b995c5092aadbd20
while read -r n sha; do
  gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/research/preview/$n?ref=$REF" > "$n"
  test "$(git hash-object --no-filters "$n")" = "$sha"
done <<'BLOBS'
champions_preview_features_pv01.py 60a5c75d28d38d3c18a8de478af14bbc46bd90cf
pv11_scene_dedup_v1.py 1578a63c391d787dbb5601a835ee1c87fd0f6932
BLOBS
echo "PINNED SOURCES: PASS"
cat > reproduce.py <<'PY'
import os,sys,json,hashlib,math
from pathlib import Path
from collections import Counter
import cv2
import numpy as np
import legacy_geometry as legacy
import pv16f_scene_gate_v2 as gate
import champions_preview_features_pv01 as pv01
import pv11_scene_dedup_v1 as pv11
cv2.setNumThreads(1)
root=Path(sys.argv[1]);home=Path.home()
# Exact byte sizes from the prior private recording study, not content authentication.
expected={184554889:1,167826581:4}
ext={".mp4",".mov",".m4v",".mkv",".avi",".webm"}
roots=[root,home/"Downloads",home/"Desktop",home/"Documents",home/"Movies",home/"1126"]
matches={1:[],4:[]};errors=0;seen=set();visited=0;budget=100000;bounded=False
skip={".git","node_modules",".venv","venv","Library",".Trash","__pycache__"}
for base in roots:
    if not base.is_dir() or bounded:continue
    for dp,dns,fs in os.walk(base,followlinks=False,onerror=lambda _:None):
        dns[:]=[n for n in dns if not n.startswith(".") and n not in skip and not Path(dp,n).is_symlink()]
        for n in fs:
            visited+=1
            if visited>budget:bounded=True;break
            p=Path(dp,n)
            if p.suffix.lower() not in ext or p.is_symlink():continue
            try:
                s=p.stat()
                if s.st_size not in expected or not p.is_file():continue
                ident=(s.st_dev,s.st_ino)
                if ident in seen:continue
                seen.add(ident);matches[expected[s.st_size]].append(p)
            except OSError:errors+=1
        if bounded:break
def sha(p):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(1048576),b""):h.update(b)
    return h.digest()
def choose(ps):
    # Same content copies count once. Never print names or digests.
    if len(ps)>12:return None,"too_many_candidates"
    by={}
    for p in ps:by.setdefault(sha(p),p)
    return (next(iter(by.values())),"unique_size_candidate") if len(by)==1 else (None,"absent" if not by else "ambiguous")
chosen={};discovery={}
for k,ps in matches.items():
    try:p,why=choose(ps)
    except OSError:p,why=None,"read_error"
    discovery[str(k)]={"size_matches":len(ps),"selection":why}
    if p is not None:chosen[k]=p

def open_video(p):
    c=cv2.VideoCapture(str(p));fps=c.get(cv2.CAP_PROP_FPS)
    w,h=int(c.get(cv2.CAP_PROP_FRAME_WIDTH)),int(c.get(cv2.CAP_PROP_FRAME_HEIGHT))
    n=int(c.get(cv2.CAP_PROP_FRAME_COUNT))
    if not c.isOpened() or (w,h)!=(1920,1080) or not 59<=fps<=61 or not 8390<=n<=8430:
        c.release();return None
    return c,fps,n
def at(p,t):
    x=open_video(p)
    if x is None:return None
    c,fps,n=x
    try:
        c.set(cv2.CAP_PROP_POS_FRAMES,round(t*fps))
        ok,im=c.read()
        return im if ok and im.shape==(1080,1920,3) else None
    finally:c.release()

# Previously visually inspected preview at 15 s, used only as a development
# calibration hypothesis. Verify historical PV11 counts before interpreting it.
template=None
if 1 in chosen:
    im=at(chosen[1],15)
    if im is not None:
        try:template=pv11.template(im)
        except ValueError:pass

def evaluate(im):
    g,a=gate.inspect(im)
    rows=legacy.detect(im)
    old=pv01.detect(im)
    assert rows==old,"historical geometry mismatch"
    route="full" if a is not None else "legacy" if rows and not g["layout_candidate"] else "held"
    hit=None if template is None else pv11.scene(im,template)[0]
    return {"route":route,"legacy_geometry":bool(rows),"v2_reason":g["reason"],
            "pv11_header_geometry":None if template is None else hit is not None,
            "pv11_layout":None if hit is None else int(hit[1])}
def scan(p,k):
    x=open_video(p)
    if x is None:return {"status":"metadata_mismatch"}
    c,fps,n=x;stride=max(1,round(fps/2));i=0;rows=[];errors=0
    before=sha(p)
    try:
        while len(rows)+errors<300 and c.grab():
            j=i;i+=1
            if j%stride:continue
            ok,im=c.retrieve()
            if not ok or im.shape!=(1080,1920,3):errors+=1;continue
            d=evaluate(im);d["t"]=j/fps;rows.append(d)
    finally:c.release()
    if sha(p)!=before:raise RuntimeError("recording changed")
    counts=Counter(r["route"] for r in rows)
    cross=Counter(r["route"]+"__pv11_"+str(r["pv11_header_geometry"]) for r in rows)
    pcount=sum(r["legacy_geometry"] for r in rows)
    pv11count=None if template is None else sum(r["pv11_header_geometry"] is True for r in rows)
    targets=[]
    if k==1:
        for t in (112,122):
            found=[r for r in rows if abs(r["t"]-t)<=.3]
            targets.append({"historical_nominal_s":t,"matched_samples":[dict(r,t=round(r["t"],3)) for r in found]})
    # Reference intervals are retrospective historical annotations, not new labels.
    intervals={}
    if k==1:
        for label,group in (("historical_preview_interval",[r for r in rows if 15<=r["t"]<=89]),
                            ("outside_historical_preview_interval",[r for r in rows if not 15<=r["t"]<=89])):
            intervals[label]={"samples":len(group),"routes":dict(Counter(r["route"] for r in group))}
    return {"status":"scanned","samples":len(rows),"decode_errors":errors,
            "fps_nominal":round(fps,5),"nominal_frame_count":n,"routes":dict(counts),
            "pv01_legacy_geometry_positive":pcount,"pv11_positive":pv11count,
            "historical_pv01_count_match":pcount==({1:130,4:0}[k]) and len(rows)==281,
            "historical_pv11_count_match":None if pv11count is None else pv11count==({1:149,4:0}[k]) and len(rows)==281,
            "route_pv11_cross":dict(cross),"historical_false_scene_targets":targets,
            "historical_intervals":intervals}
out={}
for k,p in chosen.items():
    print("SCAN historical segment candidate",k,flush=True)
    out[str(k)]=scan(p,k)
summary={"schema":"pv16-existing-scene-reproduction-v0.1",
         "sources_verified":True,"local_discovery":discovery,"search_budget_reached":bounded,
         "search_stat_errors":errors,"calibration_from_existing_15s_frame":template is not None,
         "segments":out,"identity_by_prior_byte_size_and_metadata_only":True,
         "historical_target_labels_not_new_independent_review":True,
         "sampling_nominal_2hz":True,"whole_match_444_originals_unavailable":True,
         "independent_false_positive_rate_measured":False,"private_paths_or_pixels_exported":False,
         "production_modified":False}
Path("anonymous-existing-scene-reproduction-v0.1.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
print(json.dumps(summary,indent=2,allow_nan=False))
PY
"$PY" -B reproduce.py "$ROOT" 2>analysis.log
echo "=== COMPLETE: SHARE ONLY ANONYMOUS JSON ==="
