#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
MANIFEST="${1:-$ROOT/PRIVATE-seven-reference-map-v1.json}"
if [ ! -f "$MANIFEST" ]; then echo "STOP: local verified mapping manifest unavailable"; exit 2; fi
D="$(mktemp -d "$ROOT/pv16-seven-reference-eval.XXXXXX")"
REPORT="$D/anonymous-seven-reference-eval-v1.json"
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
"$PY" -B - "$ROOT" "$MANIFEST" "$REPORT" 2>analysis.log <<'PY'
import sys,os,json,hashlib,time,re,stat
from pathlib import Path
from collections import Counter
import cv2
import numpy as np
import pv16_shadow_worker as worker
import pv16_pv11_hybrid_v1 as frozen
cv2.setNumThreads(1)
root,manifest,report=map(Path,sys.argv[1:])
TARGETS={"I0058":"B009","I0085":"B011","I0190":"B018","I0209":"B019","I0227":"B020","I0242":"B021","I0270":"B023"}
def need(ok,code):
    if not ok:raise ValueError(code)
def sha(b):return hashlib.sha256(b).hexdigest()
def local_file(p):
    p=Path(p).expanduser()
    need(p.is_absolute() and p.is_file() and not p.is_symlink(),"invalid_local_file")
    p=p.resolve()
    need(p.is_relative_to(Path.home().resolve()),"outside_local_home")
    return p
def load_json(p,limit=1024*1024):
    need(p.stat().st_size<=limit,"manifest_too_large")
    return json.loads(p.read_text())
m=load_json(local_file(manifest))
need(m.get("schema")=="pv16-seven-reference-map-v1","manifest_schema")
rows=m.get("rows",[])
need(isinstance(rows,list) and len(rows)<=7,"manifest_rows")
ids=[x.get("asset_id") for x in rows]
need(len(set(ids))==len(ids) and set(ids)<=set(TARGETS),"manifest_ids")
# Local frozen calibration from the previously successful validation run.
p=root/"pv16-pv11-hybrid-validation.tTb2IN"
v=load_json(p/"anonymous-pv11-hybrid-validation-v1.json")
need(v.get("schema")=="pv16-pv11-hybrid-validation-v1" and v.get("regression_pass") is True and v.get("frozen_calibration_local_only") is True,"previous_calibration_record")
cal=p/"private-calibration.npy"
cal_bytes=cal.read_bytes()
need(len(cal_bytes)<100000,"calibration_size")
import io
H=frozen.Hybrid(np.load(io.BytesIO(cal_bytes),allow_pickle=False))
def find_zip(pattern,expected):
    for folder in (Path.home()/"Downloads",Path.home()/"Desktop",Path.home()/"Documents",Path.home()):
        for p in sorted(folder.glob(pattern)):
            if p.is_file() and not p.is_symlink() and sha(p.read_bytes())==expected:return p
    raise ValueError("verified_reference_zip_unavailable")
bundle=find_zip("PV16-F-R4*.zip",worker.BUNDLE)
archive=find_zip("preview_images_all*.zip",worker.ARCHIVE)
R,T,G,dev=worker.load_assets(bundle,archive)
local,gb=worker.banks(T,G)
dev_hashes={s["original_sha256"] for s,_ in dev}
dev_pixels={sha(im.tobytes()) for _,im in dev}
valid=set(R.ids)
bases={worker.base(i) for i in valid}
# Exact form and species-level scoring kept separate. No inference-derived labels.
def validate_row(row):
    i=row["asset_id"]
    need(row.get("battle_id")==TARGETS[i],"battle_id_mismatch")
    need(row.get("mapping_status")=="verified_local_source","mapping_not_verified")
    need(row.get("scene")=="preview" and row.get("scene_evidence") in ("visual","battle_record"),"scene_not_verified")
    need(row.get("label_evidence") in ("visual","battle_record","mixed"),"label_evidence_missing")
    need(row.get("label_source_independent_of_recognizer") is True,"label_source_not_independent")
    need(row.get("rights")=="user_approved_local_reference","rights_scope")
    labs=row.get("slots")
    need(isinstance(labs,list) and len(labs)==6,"six_slot_manifest_required")
    for q in labs:
        if q is None:continue
        need(isinstance(q,dict) and q.get("level") in ("base","exact"),"label_level")
        k=q.get("id")
        need(isinstance(k,str) and k in (valid if q["level"]=="exact" else bases),"unknown_label_id")
    h=row.get("image_sha256")
    need(isinstance(h,str) and re.fullmatch(r"[a-f0-9]{64}",h) is not None,"expected_image_digest_missing")
    f=local_file(row.get("image_path",""))
    need(f.suffix.lower() in (".png",".jpg",".jpeg",".webp") and f.stat().st_size<=worker.MAX_IMAGE,"image_type_or_size")
    b=f.read_bytes()
    need(sha(b)==h,"image_digest_mismatch")
    return b,labs,h
counts=Counter();individual=[];seen=set();seen_pixel=set()
for i in TARGETS:
    row=next((r for r in rows if r["asset_id"]==i),None)
    if row is None:
        counts["unmapped"]+=1
        individual.append({"asset_id":i,"status":"unmapped"});continue
    try:
        b,labs,h=validate_row(row)
        im=cv2.imdecode(np.frombuffer(b,np.uint8),cv2.IMREAD_COLOR)
        need(im is not None and max(im.shape[:2])<=4096,"invalid_image")
        pixel=sha(im.tobytes())
        need(h not in seen and pixel not in seen_pixel,"duplicate_candidate")
        seen.add(h);seen_pixel.add(pixel)
        route,canvas,_=H.geometry(im)
        known_dev=h in dev_hashes or (canvas is not None and sha(canvas.tobytes()) in dev_pixels)
        t=time.perf_counter()
        a=H.analyze(im,R,local,gb)
        elapsed=(time.perf_counter()-t)*1000
        need(a["accepted"] is False and a["scene_authenticated"] is False and len(a["slots"])==6,"output_contract")
        c=Counter()
        for q,ranks in zip(labs,a["slots"]):
            if q is None:continue
            k=q["id"];rr=[n for n,_ in (ranks or [])]
            base=worker.base(k) if q["level"]=="exact" else k
            br=[worker.base(n) for n in rr]
            c["base_labeled"]+=1
            for n in (1,3,5):c["base_top"+str(n)]+=base in br[:n]
            if q["level"]=="exact":
                c["exact_labeled"]+=1
                for n in (1,3,5):c["exact_top"+str(n)]+=k in rr[:n]
        c["six_base_labeled"]=c["base_labeled"]==6
        c["six_base_correct"]=c["base_labeled"]==6 and c["base_top1"]==6
        c["six_exact_labeled"]=c["exact_labeled"]==6
        c["six_exact_correct"]=c["exact_labeled"]==6 and c["exact_top1"]==6
        counts.update(c);counts["evaluated"]+=1;counts["ranked"]+=a["status"]=="ranked";counts["held"]+=a["status"]=="held";counts["known_development_overlap"]+=known_dev
        individual.append({"asset_id":i,"status":"evaluated","route":route,"held":a["status"]=="held","metrics":dict(c),"known_development_overlap":known_dev,"analysis_ms":round(elapsed,3)})
    except (ValueError,TypeError,KeyError,OSError,AttributeError,cv2.error):
        counts["blocked"]+=1
        # Never print paths, labels, exception text or private digests.
        individual.append({"asset_id":i,"status":"blocked_mapping_label_or_input_contract"})
need(sha(cal.read_bytes())==sha(cal_bytes),"calibration_changed")
summary={"schema":"pv16-seven-reference-eval-v1","requested":7,"counts":dict(counts),"rows":individual,
"scope":"reference_only_user_approved_local_use","independent_accuracy_measured":False,"formal_admission":0,
"bank_scope":"all_historical_development","calibration_source":"previous_successful_local_validation_path_not_independently_authenticated",
"ranker_and_assets_fixed":True,"held_labeled_slots_counted_as_misses":True,"unknown_labels_excluded":True,
"mapping_and_labels_local_reviewer_report_not_gpt_verified":True,"no_private_labels_or_paths_exported":True,
"production_modified":False,"additional_matches":False}
report.write_text(json.dumps(summary,indent=2,allow_nan=False)+"\n")
print(json.dumps(summary,indent=2,allow_nan=False))
PY
echo "COMPLETE: submit ONLY anonymous-seven-reference-eval-v1.json"
