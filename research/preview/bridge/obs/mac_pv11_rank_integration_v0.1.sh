#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
D="$(mktemp -d "$ROOT/pv16-pv11-rank-integration.XXXXXX")"
REPORT="$D/anonymous-pv11-rank-integration-v0.1.json"
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
ARMS=("current","strict_full","pv11_guard_legacy","pv11_fixed","pv11_fixed_visible","hybrid_fixed_visible")
YS=(97,151,204,258,312,366)
def fixed_canvas(im,panels):
    # PV11 fixes panel origins, not species identity. All source bounds checked.
    if len(panels)!=6:return None
    dst=np.zeros((540,823,3),np.uint8)
    h0,w0=im.shape[:2]
    for y,(x,yy,w,h) in zip(YS,panels):
        if min(x,yy)<0 or min(w,h)<=0 or x+w>w0 or yy+h>h0:return None
        dst[y:y+48,667:795]=cv2.resize(im[yy:yy+h,x:x+w],(128,48),interpolation=cv2.INTER_AREA)
    return dst
def sprite_visibility(canvas):
    # Use v2's sprite subwindows, not its center (which is blank on row canvas).
    return all(gate.visibility(canvas)[0])
def alternatives(im):
    g,full=gate.inspect(im)
    rows=legacy.detect(im) if im.shape==(1080,1920,3) else []
    assert rows==(pv01.detect(im) if im.shape==(1080,1920,3) else [])
    old=legacy.canonical(im,rows) if rows else None
    current=full if full is not None else (old if not g["layout_candidate"] else None)
    hit,_=pv11.scene(im,template)
    panels=hit[2] if hit is not None else None
    # Never override explicit v2 layout-present but flat-patch rejection in proposed hybrid.
    blocked=g["layout_candidate"] and full is None
    fixed=fixed_canvas(im,panels) if panels is not None else None
    visible=fixed is not None and sprite_visibility(fixed)
    arms={"current":current,"strict_full":full,
        "pv11_guard_legacy":old if hit is not None and not blocked else None,
        "pv11_fixed":fixed if not blocked else None,
        "pv11_fixed_visible":fixed if visible and not blocked else None,
        "hybrid_fixed_visible":full if full is not None else (fixed if visible and not blocked else None)}
    return arms,{"layout":None if hit is None else int(hit[1]),"legacy":bool(rows),
        "reason":g["reason"],"route":"full" if full is not None else "legacy" if current is not None else "held",
        "blocked":bool(blocked),"fixed_visible":bool(visible),"fixed_panels":panels,"old_panels":rows}
def check_contract():
    # Numerical-only geometry checks; no new game captures.
    x=np.zeros((1080,1920,3),np.uint8)
    panels=[(1472,194+round(j*107.2),252,98) for j in range(6)]
    for j,(px,py,w,h) in enumerate(panels):x[py:py+h,px:px+w]=j+1
    y=fixed_canvas(x,panels)
    assert y.shape==(540,823,3)
    assert all(np.all(y[a:a+48,667:795]==j+1) for j,a in enumerate(YS))
    assert fixed_canvas(x,panels[:-1]) is None
    assert fixed_canvas(x,[(1919,0,10,10)]+panels[1:]) is None
    assert not sprite_visibility(y)
    return 4
tests=check_contract()
def ranked(canvas,bank=local,gal=gb):
    rr,types,recovered=worker.rank_unconfirmed(R,canvas,bank,gal)
    assert len(rr)==len(types)==len(recovered)==6
    return {"slots":[[n for n,_ in (r or [])[:5]] for r in rr],"types":types}
def top(row,j):
    a=row["slots"][j]
    return worker.base(a[0]) if a else None
def pair(a,b):
    c=Counter()
    for j in range(6):
        x,y=top(a,j),top(b,j)
        if x is not None and y is not None:
            c["comparable"]+=1
            c["base_top1_agree"]+=x==y
            c["exact_top1_agree"]+=a["slots"][j][0]==b["slots"][j][0]
            c["a_top1_in_b_top5"]+=x in [worker.base(n) for n in b["slots"][j]]
    c["paired_frames"]+=1
    c["both_six"]+=c["comparable"]==6
    c["all_six_base_agree"]+=c["base_top1_agree"]==6
    return c
def timing(xs):
    return {"n":len(xs),"median":round(float(np.median(xs)),3) if xs else None,
            "p95":round(float(np.percentile(xs,95)),3) if xs else None}
def summarize_rank(ranked_rows,reference):
    c=Counter()
    for row in ranked_rows:
        c["ranked_frames"]+=1
        c["nonempty_slots"]+=sum(bool(x) for x in row["slots"])
        c["six_nonempty_frames"]+=all(bool(x) for x in row["slots"])
        if reference is not None:
            for j,target in enumerate(reference):
                if target is None:continue
                c["pseudo_reference_slots"]+=1
                xs=[worker.base(n) for n in row["slots"][j]]
                c["pseudo_top1"]+=bool(xs and xs[0]==target)
                c["pseudo_top3"]+=target in xs[:3]
                c["pseudo_top5"]+=target in xs
    return dict(c)
def make_reference(rows):
    # Pseudo-reference only, from strict-full candidates in the historical
    # preview interval. Exclude every contributing frame from its evaluation.
    a=[x["rank"]["strict_full"] for x in rows if x["positive_interval"] and "strict_full" in x["rank"]]
    result=[]
    for j in range(6):
        ct=Counter(top(r,j) for r in a if top(r,j) is not None)
        target,n=ct.most_common(1)[0] if ct else (None,0)
        result.append(target if len(a)>=3 and n>=.8*len(a) else None)
    return result,len(a)
def scan(p,k):
    z=open_video(p)
    if z is None:raise RuntimeError("recording metadata mismatch")
    c,fps,n=z;stride=max(1,round(fps/2));i=0;rows=[];errors=0
    before=sha(p);elapsed=[];crop_delta=defaultdict(list)
    try:
        while len(rows)+errors<300 and c.grab():
            j=i;i+=1
            if j%stride:continue
            ok,im=c.retrieve()
            if not ok or im.shape!=(1080,1920,3):errors+=1;continue
            ts=j/fps
            start=time.perf_counter()
            arms,diag=alternatives(im)
            elapsed.append((time.perf_counter()-start)*1000)
            local_cache={};ranks={};times={}
            for name,canvas in arms.items():
                if canvas is None:continue
                key=hashlib.sha256(canvas.tobytes()).digest()
                if key not in local_cache:
                    t0=time.perf_counter()
                    ans=ranked(canvas)
                    local_cache[key]=(ans,(time.perf_counter()-t0)*1000)
                ranks[name],times[name]=local_cache[key]
            if diag["fixed_panels"] and diag["old_panels"]:
                for f,o in zip(diag["fixed_panels"],diag["old_panels"]):
                    crop_delta[str(diag["layout"])].append([abs(a-b) for a,b in zip(f,o)])
            rows.append({"t":ts,"positive_interval":k==1 and 15<=ts<=89,
                "route":diag["route"],"layout":diag["layout"],"legacy":diag["legacy"],
                "blocked":diag["blocked"],"visible":diag["fixed_visible"],"reason":diag["reason"],
                "rank":ranks,"times":times})
            if len(rows)%50==0:print("segment",k,"samples",len(rows),flush=True)
    finally:c.release()
    if sha(p)!=before:raise RuntimeError("recording changed")
    ref,anchors=make_reference(rows) if k==1 else ([None]*6,0)
    out={}
    for group,selected in (("historical_preview_interval",[r for r in rows if r["positive_interval"]]),
                           ("outside_historical_preview_interval",[r for r in rows if not r["positive_interval"]]),
                           ("pv11_layout_0",[r for r in rows if r["layout"]==0]),
                           ("pv11_layout_1",[r for r in rows if r["layout"]==1])):
        arm_stats={};pairs={}
        for arm in ARMS:
            arr=[r["rank"][arm] for r in selected if arm in r["rank"]]
            eval_rows=[r for r in selected if r["positive_interval"] and "strict_full" not in r["rank"]]
            eval_rank=[r["rank"][arm] for r in eval_rows if arm in r["rank"]]
            arm_stats[arm]={"candidates":len(arr),"rank_output":summarize_rank(arr,None),
                "rank_kernel_ms":timing([r["times"][arm] for r in selected if arm in r["times"]]),
                "pseudo_reference_excluding_anchors":summarize_rank(eval_rank,ref),
                "pseudo_common_denominator":len(eval_rows)*sum(x is not None for x in ref)}
        for a,b in (("strict_full","pv11_fixed"),("pv11_guard_legacy","pv11_fixed"),
                    ("current","hybrid_fixed_visible"),("pv11_fixed","pv11_fixed_visible")):
            total=Counter()
            for r in selected:
                if a in r["rank"] and b in r["rank"]:total.update(pair(r["rank"][a],r["rank"][b]))
            pairs[a+"__"+b]=dict(total)
        out[group]={"samples":len(selected),"arms":arm_stats,"paired_rank_comparison":pairs}
    targets=[]
    if k==1:
        for ts in (112,122):
            rr=[r for r in rows if abs(r["t"]-ts)<=.3]
            targets.append({"nominal_s":ts,"samples":[{"t":round(r["t"],3),"route":r["route"],"layout":r["layout"],
                 "candidate_arms":list(r["rank"])} for r in rr]})
    return {"samples":len(rows),"decode_errors":errors,"current_routes":dict(Counter(r["route"] for r in rows)),
        "pv11_positive":sum(r["layout"] is not None for r in rows),
        "historical_pv11_count_match":len(rows)==281 and sum(r["layout"] is not None for r in rows)=={1:149,4:0}[k],
        "layout_counts":dict(Counter(str(r["layout"]) for r in rows if r["layout"] is not None)),
        "explicit_flat_rejects":sum(r["blocked"] for r in rows),
        "pseudo_reference_anchor_frames":anchors,"pseudo_reference_consensus_slots":sum(x is not None for x in ref),
        "geometry_all_arms_ms":timing(elapsed),"groups":out,"historical_false_scene_targets":targets,
        "legacy_vs_fixed_abs_panel_delta_px":{k:{"panels":len(v),"median_xywh":[round(float(t),3) for t in np.median(v,axis=0)],
           "max_xywh":[int(t) for t in np.max(v,axis=0)]} for k,v in crop_delta.items()}}
# Existing 29 canonical and original images: verify no changed pixel input on
# the strict-success path. Actual rank label validation remains prior study.
reg=Counter()
with zipfile.ZipFile(archive) as z:
    for s,im in data:
        raw=cv2.imdecode(np.frombuffer(z.read(s["entry"]),np.uint8),cv2.IMREAD_COLOR)
        for name,img in (("canonical",im),("original",raw)):
            if img is None:raise RuntimeError("archive decode failure")
            arms,_=alternatives(img)
            reg[name+"_tested"]+=1
            if arms["current"] is not None and arms["hybrid_fixed_visible"] is not None:
                reg[name+"_same_rank_input"]+=np.array_equal(arms["current"],arms["hybrid_fixed_visible"])
out={str(k):scan(chosen[k],k) for k in (1,4)}
summary={"schema":"pv16-pv11-rank-integration-v0.1","pinned_sources_and_assets_verified":True,
 "geometry_contract_checks":tests,"local_discovery":discovery,"recording_identity_not_authenticated":True,
 "calibration_and_evaluation_same_recording":True,"development_regression":dict(reg),
 "arms":{"current":"original full or unguarded legacy","strict_full":"original full only",
 "pv11_guard_legacy":"PV11 gate and old variable crop, explicit flat rejection respected",
 "pv11_fixed":"PV11 gate and fixed panel normalization, explicit flat rejection respected",
 "pv11_fixed_visible":"PV11 fixed panel normalization and sprite flat-patch check",
 "hybrid_fixed_visible":"original full first, otherwise PV11 fixed visible; no unguarded fallback"},
 "segments":out,"rank_bank_scope":"all_historical_development",
 "pseudo_reference_not_ground_truth":True,"pseudo_reference_anchor_frames_excluded":True,
 "historical_intervals_not_exhaustive_independent_labels":True,"rank_kernel_timing_excludes_capture_and_IPC":True,
 "independent_species_accuracy_measured":False,"independent_false_positive_rate_measured":False,
 "accepted":False,"scene_authenticated":False,"private_candidate_ids_exported":False,"production_modified":False}
Path("anonymous-pv11-rank-integration-v0.1.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
print(json.dumps(summary,indent=2,allow_nan=False))
PY
"$PY" -B reproduce.py "$ROOT" 2>analysis.log
echo "=== COMPLETE: SHARE ONLY ANONYMOUS JSON ==="
