#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test "$(uname -s)" = Darwin
test -x "$PY"
D="$(mktemp -d "$ROOT/pv16-scene-geometry-study.XXXXXX")"
REPORT="$D/anonymous-scene-geometry-v0.1.json"
trap 'rc=$?; echo "RESULT_DIRECTORY=$D"; if [ -f "$REPORT" ]; then open -R "$REPORT"; elif [ -f "$D/analysis.log" ]; then open -R "$D/analysis.log"; else open "$D"; fi; exit "$rc"' EXIT
cd "$D"
export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
# Reuse exact local sources; fetch code only if a verified copy is absent.
REF=5da26d5d49cd338e25b1085645f12ec771f96645
REPO=nMfM1Ow5ot/champions-calc
while read -r n sha; do
  for p in "$ROOT"/pv16-obs-live-shadow.*/"$n" "$ROOT"/pv16-native-compare-v11.*/"$n"; do
    if [ -f "$p" ] && [ "$(git hash-object --no-filters "$p")" = "$sha" ]; then cp "$p" "$n"; break; fi
  done
  if [ ! -f "$n" ]; then
    gh api -H 'Accept: application/vnd.github.raw+json' "repos/$REPO/contents/research/preview/bridge/$n?ref=$REF" > "$n"
  fi
  test "$(git hash-object --no-filters "$n")" = "$sha"
done <<'BLOBS'
pv16_shadow_worker.py 71506eb4f9dde3697d782579ed8c075467d4174c
pv16f_joint_candidate_v2.py 573be1ef1e422c285c680906ed56413dc649cee5
pv16f_coverage_v2.py be0ff17d08ca8b52dace5fb004da210e9fd41ee2
pv16f_temporal_fusion_v1.py aa40601d4c0ac6475bebbe3383beabf18a50cf40
pv16f_residual_v1.py eeddf54c86ecd9938e4b2f713e69e17639241468
pv16f_integrated_v2.py cb63e9347b82163c4aefa56c25230abe902ff407
pv16f_scene_gate_v1.py 66788a1dcf08eab0346adb6ffb6303850e95d15a
pv16f_scene_gate_v2.py 9fa3d8e85879bbc440c8a45e0a690279e7a69363
legacy_geometry.py 9698b891fa04f699b63f5adbe2f578a2b2cc0b00
BLOBS
echo "PINNED SOURCES: PASS"
cat > geometry_study.py <<'PY'
"""Exploratory offline ablation: existing images only; no candidate IDs exported."""
import json,hashlib,sys,zipfile,time,re
from pathlib import Path
from collections import Counter,defaultdict
import numpy as np
import cv2
import pv16_shadow_worker as worker
import pv16f_scene_gate_v1 as v1
import pv16f_scene_gate_v2 as v2
import legacy_geometry as legacy

cv2.setNumThreads(1)
ROOT=Path(sys.argv[1])
W,H=v1.W,v1.H
YS=np.array(v1.YS,dtype=float)
YREF=YS+np.array([2,2,2,2,1,1])
METHODS=("current","strict_full","relaxed_full","affine_full","guarded_legacy_crop")
def digest(p):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for c in iter(lambda:f.read(1048576),b""):h.update(c)
    return h.hexdigest()
def find_zip(pattern,expected):
    h=Path.home()
    for folder in (h/"Downloads",h/"Desktop",h/"Documents",h):
        for p in sorted(folder.glob(pattern)):
            if p.is_file() and digest(p)==expected:return p
    raise RuntimeError("verified asset ZIP absent")
def decode(raw):
    return cv2.imdecode(np.frombuffer(raw,np.uint8),cv2.IMREAD_COLOR)
def read_img(p):
    im=decode(p.read_bytes())
    if im is None:raise ValueError("existing PNG decode failed")
    return im
def read_json(p):return json.loads(p.read_text())
def relaxed(a):
    # Fixed, predeclared exploratory thresholds, not optimized on this corpus.
    d,_=v1.inspect(a)
    if "left" not in d:return False
    color=d["color_ok"] # retain original bilateral color requirement
    row=sum(e>=30 and abs(o-t)<=3 for e,o,t in zip(d["row_edges"],d["row_offsets"],[2,2,2,2,1,1]))>=5
    col=(all(abs(o)<=3 for o in d["column_offsets"][:2]) and abs(d["column_offsets"][2])<=4
         and min(d["column_edges"][:2])>=25 and d["column_edges"][2]>=8)
    slots,center=v2.visibility(a)
    return bool(color and row and col and all(slots) and center)
def robust_line(xs,ys,min_sep,tol,min_inliers):
    # Deterministic two-point consensus; refine only inliers. No model training.
    x=np.asarray(xs,float);y=np.asarray(ys,float)
    if len(x)<min_inliers:return None
    best=None
    for i in range(len(x)):
        for j in range(i+1,len(x)):
            if abs(x[j]-x[i])<min_sep:continue
            a=(y[j]-y[i])/(x[j]-x[i]);b=y[i]-a*x[i]
            residual=np.abs(y-(a*x+b))
            m=residual<=tol
            score=(int(m.sum()),-float(residual[m].sum()))
            if best is None or score>best[0]:best=(score,m)
    if best is None or best[0][0]<min_inliers:return None
    m=best[1];a,b=np.linalg.lstsq(np.column_stack([x[m],np.ones(m.sum())]),y[m],rcond=None)[0]
    m=np.abs(y-(a*x+b))<=tol
    if m.sum()<min_inliers:return None
    return float(a),float(b),m
def affine_candidate(a):
    # Estimate independent horizontal/vertical scale and offset from BOTH panels.
    # No shear, rotation or unbounded crop. Check structure again after alignment.
    q=a.astype(np.int16);L=18
    ys=[];obs=[];side=[]
    for y in YREF.astype(int):
        for k,(x0,x1) in enumerate(((55,185),(670,685))):
            p=np.abs(np.diff(q[y-L-1:y+L+1,x0:x1],axis=0)).mean((1,2))
            i=int(p.argmax())
            if p[i]>=(30 if k==0 else 18):
                ys.append(y);obs.append(y+i-L);side.append(k)
    yf=robust_line(ys,obs,100,3,10)
    if yf is None:return None,"vertical_consensus"
    sy,dy,m=yf
    if any(sum(bool(z) and k==side[i] for i,z in enumerate(m))<5 for k in (0,1)):return None,"bilateral_consensus"
    if not .96<=sy<=1.04 or abs((sy-1)*H/2+dy)>20:return None,"vertical_bounds"
    xs=[];xo=[]
    for x in (36,257,667):
        ps=[]
        for y in YS:
            y0=int(round(sy*(y+10)+dy));y1=int(round(sy*(y+38)+dy))
            if y0<0 or y1>H or y1<=y0:return None,"window_bounds"
            ps.append(np.abs(np.diff(q[y0:y1,x-L-1:x+L+1],axis=1)).mean((0,2)))
        p=np.median(ps,axis=0);i=int(p.argmax())
        if p[i]<(25 if x!=667 else 8):return None,"horizontal_contrast"
        xs.append(x);xo.append(x+i-L)
    xf=robust_line(xs,xo,100,3,3)
    if xf is None:return None,"horizontal_consensus"
    sx,dx,_=xf
    if not .96<=sx<=1.04 or abs((sx-1)*W/2+dx)>20:return None,"horizontal_bounds"
    M=np.float32([[1/sx,0,-dx/sx],[0,1/sy,-dy/sy]])
    aligned=cv2.warpAffine(a,M,(W,H),flags=cv2.INTER_LINEAR)
    if not relaxed(aligned):return None,"post_alignment_structure_or_visibility"
    return aligned,"candidate"
def variants(im):
    t=time.perf_counter()
    g,strict=v2.inspect(im)
    native,kind=v2.viewport(im)
    oldrows=legacy.detect(im) if im.shape==(1080,1920,3) else []
    oldcrop=legacy.canonical(im,oldrows) if oldrows else None
    # Match existing worker's fallback condition exactly.
    current=strict if strict is not None else (oldcrop if not g["layout_candidate"] else None)
    current_route=("full" if strict is not None else "legacy" if current is not None else "held")
    rel=strict
    aff=strict
    reason="strict_pass" if strict is not None else "not_attempted"
    d={}
    if native is not None:
        d,_=v1.inspect(native)
        # Never bypass v2's explicit flat-patch rejection.
        if strict is None and not g["layout_candidate"]:
            if relaxed(native):rel=native
            aff=rel
            if aff is None:aff,reason=affine_candidate(native)
            else:reason="relaxed_pass"
    guarded=oldcrop if aff is not None and oldcrop is not None else None
    return {"current":current,"strict_full":strict,"relaxed_full":rel,
            "affine_full":aff,"guarded_legacy_crop":guarded},{
        "v2_reason":g["reason"],"viewport":kind or "unsupported",
        "current_route":current_route,"affine_reason":reason,
        "legacy_rows":bool(oldrows),
        "fixed_color_ok":d.get("color_ok"),"fixed_row_ok":d.get("row_ok"),
        "fixed_column_ok":d.get("column_ok"),
        "geometry_ms":(time.perf_counter()-t)*1000}
def empty():
    return {"frames":0,"unique_pixels":set(),"shapes":Counter(),"routes":Counter(),
        "v2_reasons":Counter(),"affine_reasons":Counter(),"viewports":Counter(),
        "fixed_failures":Counter(),"outputs":Counter(),"geometry_ms":[],
        "rank":{m:Counter() for m in METHODS},"crop_pair":Counter(),
        "labeled_slots_total":0,"eligible_labeled_slots":0,"gate_cross":Counter(),"fixed_failures_by_route":Counter()}
def mark_rank(stats,rr,truths,s):
    # Development labels only. Exact forms in first5; elsewhere existing base normalization.
    counts=Counter()
    for row,q in zip(rr,s["slots"]):
        truth=q["truth"]
        if truth=="?":continue
        counts["labeled"]+=1
        names=[name for name,_ in (row or [])[:5]]
        if s["cohort"]!="first5":names=[worker.base(n) for n in names]
        counts["top1"]+=bool(names and names[0]==truth)
        counts["top3"]+=truth in names[:3]
        counts["top5"]+=truth in names
    stats.update(counts)
    return counts
def study(stats,im,s=None,banks=None):
    stats["frames"]+=1
    stats["unique_pixels"].add(hashlib.sha256(im.tobytes()).digest())
    stats["shapes"][str(im.shape[1])+"x"+str(im.shape[0])]+=1
    outputs,d=variants(im)
    stats["routes"][d["current_route"]]+=1
    stats["v2_reasons"][d["v2_reason"]]+=1
    stats["affine_reasons"][d["affine_reason"]]+=1
    stats["viewports"][d["viewport"]]+=1
    stats["geometry_ms"].append(d["geometry_ms"])
    for key in ("fixed_color_ok","fixed_row_ok","fixed_column_ok"):
        if d[key] is False:stats["fixed_failures"][key]+=1
    if s is not None:
        count=sum(q["truth"]!="?" for q in s["slots"])
        stats["labeled_slots_total"]+=count
        if banks is not None:stats["eligible_labeled_slots"]+=count
    for key in ("fixed_color_ok","fixed_row_ok","fixed_column_ok"):
        if d[key] is False:stats["fixed_failures_by_route"][d["current_route"]+"__"+key]+=1
    stats["gate_cross"][d["current_route"]+"__"+("affine_candidate" if outputs["affine_full"] is not None else "affine_held")]+=1
    local_rank={}
    for method,image in outputs.items():
        if image is None:continue
        stats["outputs"][method]+=1
        if s is not None and banks is not None:
            local,gb=banks
            rr,_,_=worker.rank_unconfirmed(R,image,local,gb)
            local_rank[method]=mark_rank(stats["rank"][method],rr,None,s)
    if "affine_full" in local_rank and "guarded_legacy_crop" in local_rank:
        x,y=local_rank["affine_full"],local_rank["guarded_legacy_crop"]
        stats["crop_pair"]["frames"]+=1
        stats["crop_pair"]["labeled"]+=x["labeled"]
        for k in ("top1","top3","top5"):
            stats["crop_pair"]["full_"+k]+=x[k]
            stats["crop_pair"]["legacy_"+k]+=y[k]
def finish(s):
    return {"frames":s["frames"],"unique_decoded_pixels":len(s["unique_pixels"]),
        "shapes":dict(s["shapes"]),"current_routes":dict(s["routes"]),
        "v2_reasons":dict(s["v2_reasons"]),"affine_reasons":dict(s["affine_reasons"]),
        "viewports":dict(s["viewports"]),"fixed_failure_counts":dict(s["fixed_failures"]),
        "fixed_failures_by_current_route":dict(s["fixed_failures_by_route"]),"gate_cross":dict(s["gate_cross"]),
        "labeled_slots_total":s["labeled_slots_total"],"eligible_labeled_slots":s["eligible_labeled_slots"],
        "rank_counts_including_held_as_misses":{m:{"denominator":s["eligible_labeled_slots"],**{k:s["rank"][m][k] for k in ("top1","top3","top5")}} for m in METHODS},
        "candidate_counts":{m:s["outputs"][m] for m in METHODS},
        "rank_on_output_only":{m:dict(s["rank"][m]) for m in METHODS},
        "paired_crop_comparison":dict(s["crop_pair"]),
        "all_variant_geometry_ms_median":round(float(np.median(s["geometry_ms"])),3) if s["frames"] else None}

# Mathematical unit checks (not additional game images).
fit=robust_line([0,100,200,300,400,500],[3,104,205,306,407,508],100,1,6)
assert fit is not None and abs(fit[0]-1.01)<1e-8 and abs(fit[1]-3)<1e-8
assert robust_line([0,100,200],[0,100,260],100,1,3) is None
# Verify and use existing archives; never export raw image hashes or identifiers.
bundle=find_zip("PV16-F-R4*.zip",worker.BUNDLE)
archive=find_zip("preview_images_all*.zip",worker.ARCHIVE)
R,templates,gallery,data=worker.load_assets(bundle,archive)
cohorts=defaultdict(empty)
excluded=Counter()
with zipfile.ZipFile(archive) as z:
    for s,im in data:
        try:bank=worker.banks(templates,gallery,exclude=s["group"])
        except (ValueError,IndexError):bank=None;excluded["group_exclusion_unavailable"]+=1
        study(cohorts["development_canonical"],im,s,bank)
        raw=decode(z.read(s["entry"]))
        if raw is None:excluded["archive_decode_failed"]+=1;continue
        study(cohorts["development_original"],raw,s,bank)
# The prior montage visually labeled native-comparison image-001 positive and
# image-002 negative. Deduplicate repeated runs locally, not new samples.
pairs={}
for d in ROOT.glob("pv16-native-compare-v11.*"):
    a,b=d/"inputs/image-001.png",d/"inputs/image-002.png"
    if a.is_file() and b.is_file():
        key=(digest(a),digest(b))
        pairs.setdefault(key,(a,b))
if len(pairs)==1:
    a,b=next(iter(pairs.values()))
    study(cohorts["prior_visual_positive"],read_img(a))
    study(cohorts["prior_visual_negative"],read_img(b))
else:excluded["prior_pair_missing_or_ambiguous"]+=1
# Reconnect protocol phases are NOT independent visual labels.
runs=[]
for d in ROOT.glob("pv16-obs-reconnect.*"):
    try:
        a=read_json(d/"aggregate-result.json")
        if (a["schema"]=="pv16-obs-reconnect-summary-v1"
            and [a[p]["frames"] for p in ("baseline","stopped","restarted")]==[3,14,20]
            and a["result"]=="NON_GAME_OUTPUT_AND_LAYOUT_RECOVERY_CANDIDATE"):
            runs.append(d)
    except (OSError,ValueError,KeyError):continue
if len(runs)==1:
    d=runs[0];v=read_json(d/"capture-result.json")
    assert len(v["samples"])==37
    for row in v["samples"]:
        f=row["file"];phase=row["phase"]
        assert row["success"] and phase in ("baseline","stopped","restarted")
        assert re.fullmatch(r"frames/[0-9]{3}\.png",f)
        study(cohorts["reconnect_"+phase],read_img(d/f))
else:excluded["reconnect_run_missing_or_ambiguous"]+=1
summary={"schema":"pv16-scene-geometry-study-v0.1",
    "pinned_assets_verified":True,"numeric_fit_unit_checks":2,
    "method_descriptions":{"current":"existing v2 + unguarded legacy fallback",
      "strict_full":"existing v2 only","relaxed_full":"strict or fixed bilateral relaxed edges and original visibility",
      "affine_full":"strict or relaxed or bounded bilateral axis-affine correction",
      "guarded_legacy_crop":"old row crop only when affine_full has a candidate; crop diagnostic, not standalone policy"},
    "cohorts":{k:finish(v) for k,v in sorted(cohorts.items())},
    "excluded":dict(excluded),"development_original_and_canonical_overlap":True,
    "development_labels_provisional":True,"group_excluded_banks_used_for_development_rank":True,
    "prior_pair_montage_link_not_cryptographically_verified":True,
    "reconnect_phase_labels_not_independent_truth":True,
    "whole_match_444_raw_frames_available":False,
    "rank_counts_conditional_on_output_not_accuracy_of_all_inputs":True,
    "rank_counts_including_held_use_common_eligible_denominator":True,
    "independent_accuracy_measured":False,"false_positive_rate_measured":False,
    "production_modified":False,"private_ids_exported":False}
print(json.dumps(summary,indent=2,allow_nan=False))
Path("anonymous-scene-geometry-v0.1.json").write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
PY
echo "=== OFFLINE STUDY: existing verified archives and saved PNGs ==="
"$PY" -B geometry_study.py "$ROOT" 2>analysis.log
echo "=== COMPLETE: SHARE ONLY anonymous-scene-geometry-v0.1.json ==="
