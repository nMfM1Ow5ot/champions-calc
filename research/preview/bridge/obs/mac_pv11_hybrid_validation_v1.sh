#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
D="$(mktemp -d "$ROOT/pv16-pv11-hybrid-validation.XXXXXX")"
REPORT="$D/anonymous-pv11-hybrid-validation-v1.json"
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
pv16_shadow_worker.py 71506eb4f9dde3697d782579ed8c075467d4174c
pv16f_joint_candidate_v2.py 573be1ef1e422c285c680906ed56413dc649cee5
pv16f_coverage_v2.py be0ff17d08ca8b52dace5fb004da210e9fd41ee2
pv16f_temporal_fusion_v1.py aa40601d4c0ac6475bebbe3383beabf18a50cf40
pv16f_residual_v1.py eeddf54c86ecd9938e4b2f713e69e17639241468
pv16f_integrated_v2.py cb63e9347b82163c4aefa56c25230abe902ff407
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
gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/research/preview/bridge/obs/pv16_pv11_hybrid_v1.py?ref=4708ca9c368f041fe91272f557e3accbe4b965ee" > pv16_pv11_hybrid_v1.py
test "$(git hash-object --no-filters pv16_pv11_hybrid_v1.py)" = d31584b12f688c7cf97ae5e1c059222f2e665d0e
echo "PINNED SOURCES: PASS"
cat > reproduce.py <<'PY'
import os,sys,json,hashlib,math,time,zipfile,itertools
from pathlib import Path
from collections import Counter,defaultdict
import cv2
import numpy as np
import legacy_geometry as legacy
import pv16f_scene_gate_v2 as gate
import champions_preview_features_pv01 as pv01
import pv11_scene_dedup_v1 as pv11
import pv16_shadow_worker as worker
import pv16_pv11_hybrid_v1 as frozen
from unittest.mock import patch
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

# Require both recordings and a usable prior calibration; never silently substitute.
if set(chosen)!={1,4} or template is None:
    raise SystemExit("STOP: prior recordings or calibration not uniquely located")
def find_zip(pattern,expected):
    for folder in (home/"Downloads",home/"Desktop",home/"Documents",home):
        for p in sorted(folder.glob(pattern)):
            if p.is_file() and sha(p).hex()==expected:return p
    raise RuntimeError("verified reference ZIP unavailable")
bundle=find_zip("PV16-F-R4*.zip",worker.BUNDLE)
archive=find_zip("preview_images_all*.zip",worker.ARCHIVE)
R,templates,gallery,data=worker.load_assets(bundle,archive)
local,gb=worker.banks(templates,gallery)
# Freeze the calibration in the private result directory before evaluating
# any other corpus. Reopening the 15s development frame is not independent.
H=frozen.Hybrid(template)
np.save("private-calibration.npy",H.template,allow_pickle=False)
calibration_digest=sha(Path("private-calibration.npy"))
assert not H.template.flags.writeable
def contract():
    tests={}
    x=np.zeros((1080,1920,3),np.uint8)
    panel=[(1472,194+round(j*107.2),252,98) for j in range(6)]
    for j,(px,py,w,h) in enumerate(panel):x[py:py+h,px:px+w]=j+1
    a=frozen.fixed_canvas(x,panel)
    tests["coordinate_mapping"]=a.shape==(540,823,3) and all(np.all(a[y:y+48,667:795]==j+1) for j,y in enumerate(frozen.YS))
    tests["bounds"]=frozen.fixed_canvas(x,[(1919,0,10,10)]+panel[1:]) is None
    tests["six_slots_required"]=frozen.fixed_canvas(x,panel[:-1]) is None
    tests["invalid_input"]=H.geometry(None)==("held",None,"invalid_input")
    try:frozen.Hybrid(np.zeros((32,350),np.float32));tests["reject_empty_calibration"]=False
    except ValueError:tests["reject_empty_calibration"]=True
    full=np.zeros((540,823,3),np.uint8)
    with patch.object(gate,"inspect",return_value=({"layout_candidate":True},full)),patch.object(pv11,"scene",side_effect=AssertionError("fallback on full")):
        route,img,reason=H.geometry(x)
        tests["preserve_full"]=route=="full" and img is full
    with patch.object(gate,"inspect",return_value=({"layout_candidate":True},None)),patch.object(pv11,"scene",side_effect=AssertionError("fallback on explicit reject")):
        tests["explicit_flat_reject"]=H.geometry(x)==("held",None,"explicit_visibility_rejection")
    with patch.object(gate,"inspect",return_value=({"layout_candidate":False},None)),patch.object(pv11,"scene",return_value=(None,[])):
        tests["no_unguarded_fallback"]=H.geometry(x)==("held",None,"pv11_no_unique_layout")
    with patch.object(gate,"inspect",return_value=({"layout_candidate":False},None)),patch.object(pv11,"scene",return_value=((.9,0,panel),[])),patch.object(gate,"visibility",return_value=([True]*5+[False],False)):
        tests["fallback_visibility"]=H.geometry(x)==("held",None,"sprite_flat_patch")
    with patch.object(gate,"inspect",return_value=({"layout_candidate":False},None)),patch.object(pv11,"scene",return_value=((.9,0,panel),[])),patch.object(gate,"visibility",return_value=([True]*6,False)):
        route,img,_=H.geometry(x)
        tests["fallback_fixed_canvas"]=route=="pv11_fixed_visible" and np.array_equal(img,a)
        with patch.object(worker,"rank_unconfirmed",return_value=([None]*6,[None]*6,[False]*6)):
            result=H.analyze(x,R,local,gb)
            tests["candidate_only_contract"]=result["status"]=="ranked" and result["accepted"] is False and result["scene_authenticated"] is False and result["slots"]==[None]*6
    assert all(tests.values())
    return tests
tests=contract()
print("F CONTRACT TESTS: PASS",len(tests),flush=True)

def old_f(im):
    # Reproduce the accepted development ablation independently of the module.
    g,full=gate.inspect(im)
    if full is not None:return full
    if g["layout_candidate"]:return None
    hit,_=pv11.scene(im,template)
    if hit is None:return None
    dst=np.zeros((540,823,3),np.uint8)
    for y,(x,yy,w,h) in zip((97,151,204,258,312,366),hit[2]):
        dst[y:y+48,667:795]=cv2.resize(im[yy:yy+h,x:x+w],(128,48),interpolation=cv2.INTER_AREA)
    return dst if all(gate.visibility(dst)[0]) else None

def check_frame(im,stats,run_rank=False):
    t0=time.perf_counter()
    route,a,reason=H.geometry(im)
    stats["geometry_ms"].append((time.perf_counter()-t0)*1000)
    prev=old_f(im)
    same=(a is None and prev is None) or (a is not None and prev is not None and np.array_equal(a,prev))
    stats["frames"]+=1;stats["pixel_equivalent"]+=bool(same)
    stats["routes"][route]+=1;stats["reasons"][reason]+=1
    if run_rank:
        answer=H.analyze(im,R,local,gb)
        assert answer["accepted"] is False and answer["scene_authenticated"] is False
        assert answer["route"]==route and len(answer["slots"])==6
        stats["rank_calls"]+=1
        stats["six_nonempty"]+=all(bool(x) for x in answer["slots"])
        if a is not None:
            rr,tt,rec=worker.rank_unconfirmed(R,prev,local,gb)
            expected=[row[:5] if row else None for row in rr]
            stats["rank_equivalent"]+=answer["slots"]==expected and answer["types"]==tt and answer["recovered"]==rec
        else:stats["rank_equivalent"]+=answer["slots"]==[None]*6
    return route
def fresh():
    return {"frames":0,"pixel_equivalent":0,"routes":Counter(),"reasons":Counter(),"geometry_ms":[],"rank_calls":0,"rank_equivalent":0,"six_nonempty":0}
def finish(s):
    return dict(s,geometry_ms={"n":len(s["geometry_ms"]),"median":round(float(np.median(s["geometry_ms"])),3) if s["geometry_ms"] else None,"p95":round(float(np.percentile(s["geometry_ms"],95)),3) if s["geometry_ms"] else None})
def scan(p,k):
    z=open_video(p)
    if z is None:raise RuntimeError("recording metadata mismatch")
    c,fps,n=z;stride=max(1,round(fps/2));i=0;err=0
    before=sha(p);allstats=fresh();interval=Counter();targets={}
    try:
        while allstats["frames"]+err<300 and c.grab():
            j=i;i+=1
            if j%stride:continue
            ok,im=c.retrieve()
            if not ok or im.shape!=(1080,1920,3):err+=1;continue
            ts=j/fps
            route=check_frame(im,allstats,run_rank=True)
            interval[("preview" if k==1 and 15<=ts<=89 else "outside")+"__"+route]+=1
            if k==1 and ts in (112,122):targets[str(int(ts))]=route
            if allstats["frames"]%50==0:print("development segment",k,"samples",allstats["frames"],flush=True)
    finally:c.release()
    assert sha(p)==before
    return {"metrics":finish(allstats),"decode_errors":err,"interval_routes":dict(interval),"known_negative_targets":targets}
reg={}
with zipfile.ZipFile(archive) as z:
    groups={"canonical":fresh(),"original":fresh()}
    for s,im in data:
        raw=cv2.imdecode(np.frombuffer(z.read(s["entry"]),np.uint8),cv2.IMREAD_COLOR)
        assert raw is not None
        for name,img in (("canonical",im),("original",raw)):
            check_frame(img,groups[name],run_rank=True)
    reg={k:finish(v) for k,v in groups.items()}
segments={str(k):scan(chosen[k],k) for k in (1,4)}
# Additional prior OBS corpora, NOT independent (used in prior experiments).
cross={}
pairs={}
for d in root.glob("pv16-native-compare-v11.*"):
    a,b=d/"inputs/image-001.png",d/"inputs/image-002.png"
    if a.is_file() and b.is_file():pairs.setdefault((sha(a),sha(b)),(a,b))
if len(pairs)==1:
    for label,p in zip(("prior_visual_positive","prior_visual_negative"),next(iter(pairs.values()))):
        im=cv2.imdecode(np.frombuffer(p.read_bytes(),np.uint8),1)
        assert im is not None
        st=fresh();check_frame(im,st,run_rank=True);cross[label]=finish(st)
else:cross["prior_pair_status"]="missing_or_ambiguous"
runs=[]
for d in root.glob("pv16-obs-reconnect.*"):
    try:
        a=json.loads((d/"aggregate-result.json").read_text())
        if a["schema"]=="pv16-obs-reconnect-summary-v1" and [a[p]["frames"] for p in ("baseline","stopped","restarted")]==[3,14,20] and a["result"]=="NON_GAME_OUTPUT_AND_LAYOUT_RECOVERY_CANDIDATE":runs.append(d)
    except (OSError,ValueError,KeyError):continue
if len(runs)==1:
    import re
    d=runs[0];v=json.loads((d/"capture-result.json").read_text())
    assert len(v["samples"])==37
    groups=defaultdict(fresh)
    for row in v["samples"]:
        f=row["file"];phase=row["phase"]
        assert row["success"] and phase in ("baseline","stopped","restarted")
        assert re.fullmatch(r"frames/[0-9]{3}\.png",f)
        im=cv2.imdecode(np.frombuffer((d/f).read_bytes(),np.uint8),1)
        assert im is not None
        check_frame(im,groups[phase],run_rank=True)
    cross.update({"reconnect_"+k:finish(v) for k,v in groups.items()})
else:cross["reconnect_status"]="missing_or_ambiguous"

# Independent admission G0–G5. Known candidate rights were unknown.
# Inventory existing metadata only. Do not open unauthenticated archives or
# unknown-rights image data; do not treat past OCR review as PV independence.
def inventory(pattern,expected=None):
    matches=[]
    for folder in (home/"Downloads",home/"Desktop",home/"Documents",root):
        matches.extend(p for p in folder.glob(pattern) if p.is_file())
    verified=sum(sha(p).hex()==expected for p in matches) if expected else None
    return {"matching_files":len(matches),"expected_digest_matches":verified,"contents_read":False}
admission={
    "prior_anonymous_catalog":inventory("Vision-Asset-Anonymous-Catalog-v1.0.json","34f6e8b844d710d5c552269e058ebef1731d4f7204699f588881ecf7a6ca1f25"),
    "prior_review_v1_2":inventory("vision_asset_review_v1.2.zip","cf353300491b137f45ce4b249b21fa9d235c84ed4ec7884e7b7b80501ad413d1"),
    "prior_holdout_review_archives":inventory("vision-holdout-batch*-review.zip"),
    "prior_separate_recording_parts_present":sum((home/"Movies"/"2026-11-26 04-19-23_split"/("part"+str(i)+".mov")).is_file() for i in range(1,5)),
    "admitted_independent_preview_frames":0,"admitted_independent_negative_frames":0,
    "independent_rank_evaluated":0,"status":"BLOCKED_NO_VERIFIED_ADMISSION",
    "blockers":["latest approved rights and scene/slot evidence not available as verified per-image records",
        "complete development/reference provenance and component exclusion not established",
        "archive inner digest expectations unavailable; no candidate raw assets opened"],
    "no_holdout_tuning":True}
# The frozen module is verified against prior algorithm and actual outputs,
# not by reusing previous metrics as evidence of independence.
assert sha(Path("private-calibration.npy"))==calibration_digest
s1=segments["1"];s4=segments["4"]
all_checked=[*reg.values(),s1["metrics"],s4["metrics"],*[v for v in cross.values() if isinstance(v,dict)]]
checks={
 "all_canvas_equivalent":all(x["frames"]==x["pixel_equivalent"] for x in all_checked),
 "all_rank_equivalent":all(x["rank_calls"]==x["rank_equivalent"] for x in all_checked),
 "development_images_preserved":all(reg[k]["frames"]==29 and reg[k]["routes"].get("full")==29 for k in reg),
 "recording_regression":s1["metrics"]["frames"]==281 and s4["metrics"]["frames"]==281 and s1["decode_errors"]==s4["decode_errors"]==0 and s1["interval_routes"]=={"outside__held":132,"preview__full":13,"preview__pv11_fixed_visible":136} and s4["interval_routes"]=={"outside__held":281},
 "known_negative_regression":s1["known_negative_targets"]=={"112":"held","122":"held"},
 "calibration_unchanged":True}
summary={"schema":"pv16-pv11-hybrid-validation-v1","module_contract_tests":tests,
    "pinned_sources_assets_verified":True,"frozen_calibration_local_only":True,
    "recording_identity_not_authenticated":True,"development_regression":reg,
    "recordings":segments,"prior_obs_cross_corpus_not_independent":cross,
    "regression_checks":checks,"regression_pass":all(checks.values()),
    "independent_admission":admission,"independent_accuracy_measured":False,
    "independent_false_positive_rate_measured":False,"production_modified":False,
    "private_ids_images_paths_exported":False,"accepted":False,"scene_authenticated":False}
Path("anonymous-pv11-hybrid-validation-v1.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
print(json.dumps(summary,indent=2,allow_nan=False))
PY
"$PY" -B reproduce.py "$ROOT" 2>analysis.log
echo "=== COMPLETE: SHARE ONLY ANONYMOUS JSON ==="
