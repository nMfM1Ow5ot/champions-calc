#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
ROOT="$HOME/champions-vision-research"
PY="$ROOT/.venv/bin/python"
test -x "$PY"
D="$(mktemp -d "$ROOT/pv16-holdout-evidence.XXXXXX")"
REPORT="$D/anonymous-holdout-evidence-v1.1.json"
trap 'rc=$?; echo "RESULT_DIRECTORY=$D"; if [ -f "$REPORT" ]; then open -R "$REPORT"; elif [ -f "$D/analysis.log" ]; then open -R "$D/analysis.log"; else open "$D"; fi; exit "$rc"' EXIT
cd "$D"
export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
unset PYTHONPATH PYTHONHOME
"$PY" -B - "$ROOT" "$D" 2>analysis.log <<'PY'
import os,sys,re,json,hashlib,zipfile,stat
from pathlib import Path
from collections import Counter,defaultdict
root,out=map(Path,sys.argv[1:])
home=Path.home()
TARGETS={"I0058":"B009","I0085":"B011","I0190":"B018","I0209":"B019","I0227":"B020","I0242":"B021","I0270":"B023"}
PAIRS=[("I0042","I0199"),("I0047","I0085"),("I0209","I0296")]
IDS=set(TARGETS)|{i for pair in PAIRS for i in pair}
ID_RE=re.compile(r"\b(?:"+"|".join(sorted(IDS))+r")\b")
ZIP_NAME="vision_asset_review_v1.2.zip"
ZIP_SHA="cf353300491b137f45ce4b249b21fa9d235c84ed4ec7884e7b7b80501ad413d1"
MEMBERS={
 "Vision-Asset-Anonymous-Catalog-v1.2.json":("f524c4df5ec3308727435830b0a5ddea6e258360888599625e77448980ac79c6",344716),
 "Vision-Asset-Independent-Review-Handoff-v1.2.md":("f1c599b383e784203fb0930e4006c3a81228d5e1971d9d329766cdd5fb87a103",7097)}
def digest(b):return hashlib.sha256(b).hexdigest()
def sha(p):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(1048576),b""):h.update(b)
    return h.hexdigest()
def emit(name,obj):
    (out/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2,allow_nan=False)+"\n")
# Limited local traversal. Do not follow symlinks, enter application data,
# inspect unrelated documents, download archives or touch production files.
roots=[root,home/"Downloads",home/"Desktop",home/"Documents",home/"Movies",
       home/"workspace",home/"champions-calc",home/"champions_calc",home/"Muse",home/"muse"]
skip={".git","node_modules","venv",".venv","Library","__pycache__","dist","build","target"}
meta_name=re.compile(r"(vision[-_ ].*(asset|review|catalog|holdout|label|manifest)|asset[-_ ].*(catalog|review|mapping|provenance|index)|holdout|preview[-_ ].*(label|manifest|index|provenance|review)|label[-_ ].*evidence|(?:pv|ocr)[-_ ].*(usage|history|provenance|manifest|evidence)|(?:vision|asset|preview)[-_ ].*rights)",re.I)
meta_ext={".json",".jsonl",".md",".txt",".csv",".tsv"}
image_ext={".png",".jpg",".jpeg",".webp",".heic"}
files=[];zips=[];named_images=defaultdict(list);seen=set();visited=0;walk_errors=0;bounded=False
def onerror(_):
    global walk_errors
    walk_errors+=1
for base in roots:
    if not base.is_dir() or base.is_symlink() or bounded:continue
    for dp,dns,fs in os.walk(base,followlinks=False,onerror=onerror):
        dns[:]=[n for n in dns if not n.startswith(".") and n not in skip and not Path(dp,n).is_symlink() and not n.startswith("pv16-holdout-evidence.")]
        for n in fs:
            visited+=1
            if visited>120000:bounded=True;break
            p=Path(dp,n);suffix=p.suffix.lower()
            if p.is_symlink():continue
            if not (n==ZIP_NAME or (suffix in meta_ext and meta_name.search(n)) or (suffix in image_ext and ID_RE.search(n))):continue
            try:
                st=p.stat()
                if not stat.S_ISREG(st.st_mode):continue
                key=(st.st_dev,st.st_ino)
                if key in seen:continue
                seen.add(key)
                if n==ZIP_NAME:zips.append(p)
                elif suffix in image_ext:
                    for i in set(ID_RE.findall(n)):named_images[i].append(str(p))
                elif st.st_size<=8*1024*1024:files.append((p,st.st_size))
            except OSError:walk_errors+=1
        if bounded:break
matches=[p for p in zips if p.stat().st_size==17043 and sha(p)==ZIP_SHA]
if not matches:raise SystemExit("STOP: no exact verified v1.2 ZIP")
# Identical copies are interchangeable. Check archive bytes again before use.
p=matches[0];raw=p.read_bytes()
assert len(raw)==17043 and digest(raw)==ZIP_SHA
import io
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    infos=z.infolist()
    assert len(infos)==2 and {i.filename for i in infos}==set(MEMBERS)
    data={}
    for i in infos:
        expected,size=MEMBERS[i.filename]
        assert not i.is_dir() and i.file_size==size and not (i.flag_bits&1)
        b=z.read(i)
        assert len(b)==size and digest(b)==expected
        data[i.filename]=b
# No archive extraction; both members verified before decoding either.
catalog=json.loads(data["Vision-Asset-Anonymous-Catalog-v1.2.json"])
handoff=data["Vision-Asset-Independent-Review-Handoff-v1.2.md"].decode("utf-8")
def find_rows(x):
    if isinstance(x,list):
        if len(x)==376 and all(isinstance(v,dict) and "asset_id" in v for v in x):
            yield x
        else:
            for v in x:yield from find_rows(v)
    elif isinstance(x,dict):
        for v in x.values():yield from find_rows(v)
sets=list(find_rows(catalog))
assert len(sets)==1,"catalog row container ambiguous"
rows=sets[0];by={r["asset_id"]:r for r in rows}
assert len(by)==376 and IDS<=set(by)
# Recompute connectivity over metadata only. This does not authenticate lineage.
parent={}
def rt(x):
    parent.setdefault(x,x)
    if parent[x]!=x:parent[x]=rt(parent[x])
    return parent[x]
def join(x,y):parent[rt(x)]=rt(y)
for r in rows:
    i="i:"+r["asset_id"];rt(i)
    if r.get("battle_id"):join(i,"b:"+r["battle_id"])
    if r.get("source_group_id"):join(i,"g:"+r["source_group_id"])
    links=r.get("linked_group_ids",[])
    assert isinstance(links,list)
    for g in links:join(i,"g:"+g)
comps=defaultdict(list)
for r in rows:comps[rt("i:"+r["asset_id"])].append(r)
def component_state(r):
    group=comps[rt("i:"+r["asset_id"])]
    if any(q.get("prior_usage_pv")=="used" or q.get("prior_usage_reference_bank")=="used" for q in group):return "related_or_used"
    if any(q.get("prior_usage_pv")!="not_found" or q.get("prior_usage_reference_bank")!="not_found" or not q.get("battle_id") or not q.get("source_group_id") for q in group):return "unknown"
    return "candidate_declaration_only"
# Discover ORIGINAL evidence references without exporting content or paths.
# A hit is a location for local examination, not proof of rights or truth.
refs=defaultdict(list);examined=0;bytes_read=0;read_errors=0;scan_cap=False;reused=False
def kind(p):
    n=p.name.lower()
    if "rights" in n or "permission" in n:return "rights"
    if "label" in n or "truth" in n or "battle_record" in n:return "labels"
    if "usage" in n or "history" in n or "provenance" in n:return "usage"
    if "map" in n or "index" in n or "manifest" in n:return "mapping"
    if "duplicate" in n or "hash" in n:return "duplicates"
    return "review_or_catalog"
previous=root/"pv16-holdout-evidence.a8oOPs"/"PRIVATE-evidence-index-DO-NOT-UPLOAD.json"
# Only reuse reference locations, never treat prior index as authoritative evidence.
if previous.is_file() and not previous.is_symlink():
    try:
        old=json.loads(previous.read_text())
        if old["candidate_catalog_rows"]=={i:by[i] for i in sorted(IDS)}:
            restored={}
            allowed={"rights","labels","usage","mapping","duplicates","review_or_catalog"}
            for i,rr in old["local_metadata_references"].items():
                if i not in IDS or not isinstance(rr,list):raise ValueError("invalid private index")
                restored[i]=[x for x in rr if isinstance(x,dict) and x.get("category_hint") in allowed and isinstance(x.get("file"),str) and Path(x["file"]).is_file()]
            refs.update(restored)
            reused=True
    except (OSError,ValueError,KeyError,TypeError):
        refs.clear()
for p,n in ([] if reused else sorted(files,key=lambda q:(kind(q[0])=="review_or_catalog",q[1],str(q[0])))):
    if examined>=600 or bytes_read+n>64*1024*1024:scan_cap=True;break
    try:
        b=p.read_bytes();examined+=1;bytes_read+=len(b)
        # A verified copy of the handoff is not new original evidence.
        if digest(b) in {h for h,_ in MEMBERS.values()}:continue
        t=b.decode("utf-8",errors="strict")
    except (OSError,UnicodeError):read_errors+=1;continue
    hit=set(ID_RE.findall(t))
    if not hit:continue
    for i in hit:
        pattern=re.compile(r"\b"+i+r"\b")
        lines=[n for n,line in enumerate(t.splitlines(),1) if pattern.search(line)]
        refs[i].append({"file":str(p),"category_hint":kind(p),"line_numbers":lines[:20],"matching_lines":len(lines)})
# Private index contains references only, never uploaded. No image bytes read.
private={"warning":"LOCAL ONLY. Do not submit. File references and catalog rows are not verified primary evidence.",
         "verified_zip":str(matches[0]),"candidate_catalog_rows":{i:by[i] for i in sorted(IDS)},
         "local_metadata_references":dict(refs),"filename_only_image_candidates":dict(named_images),
         "review_instructions":{
          "rights":"Check original acquisition and authority for local evaluation; unknown stays unknown. Do not infer from file possession.",
          "duplicate_pairs":"Resolve exact ID-to-source mapping and recording lineage first; inspect only authorized originals. Exact or perceptual distance alone cannot prove different battles.",
          "usage":"Verify all prior PV development, calibration and dictionary usage, including work after v1.2; component-level exclusion.",
          "labels":"Check independent battle record or nameplate/slot evidence, exact slot and form; do not use F outputs as labels."}}
emit("PRIVATE-evidence-index-DO-NOT-UPLOAD.json",private)
candidates=[]
for i,battle in TARGETS.items():
    r=by[i]
    # Historical target list is a hypothesis. Quarantine discrepancies instead of
    # aborting or rewriting authenticated source data. Only allowlisted values leave Mac.
    actual_battle=r.get("battle_id")
    actual_scene=r.get("scene_class")
    match_battle=actual_battle==battle
    match_scene=actual_scene=="preview"
    safe_battle=actual_battle if isinstance(actual_battle,str) and re.fullmatch(r"B[0-9]{3,6}",actual_battle) else None
    safe_scene=actual_scene if isinstance(actual_scene,str) and actual_scene in {"preview","battle_message","battle_command","hp_display","battle_result","other","unknown"} else "unrecognized_or_missing"
    candidates.append({"asset_id":i,"expected_battle_id":battle,"catalog_battle_id":safe_battle,
      "catalog_scene_class":safe_scene,"battle_id_matches":match_battle,"preview_class_matches":match_scene,
      "target_identity_consistent":match_battle and match_scene,
      "scene_declared_verified":r.get("scene_verification_status")=="verified",
      "six_slots_declared_verified":r.get("label_verification_status")=="verified" and r.get("verified_slot_count")==6,
      "rights_declared_approved":r.get("rights_status")=="approved_local_research",
      "component_usage":component_state(r),
      "metadata_reference_counts":dict(Counter(x["category_hint"] for x in refs[i])),
      "image_filename_match_count":len(named_images[i]),
      "original_rights_verified":False,"original_labels_verified":False,
      "complete_prior_usage_verified":False,"admitted":False})
pair_results=[]
for i,j in PAIRS:
    pair_results.append({"pair":[i,j],"same_declared_component":rt("i:"+i)==rt("i:"+j),
      "both_have_local_metadata_references":bool(refs[i] and refs[j]),
      "both_have_filename_image_candidates":bool(named_images[i] and named_images[j]),
      "original_mapping_verified":False,"raw_similarity_recomputed":False,"lineage_resolved":False})
summary={"schema":"pv16-holdout-evidence-inventory-v1.1","G0":{"zip_sha256_match":True,"both_inner_sha256_match":True,"archive_members_verified":2},
 "G1_G2":{"catalog_rows":len(rows),"requested_target_rows":len(candidates),"selected_preview_rows":sum(x["target_identity_consistent"] for x in candidates),"target_identity_discrepancies":sum(not x["target_identity_consistent"] for x in candidates),"prior_full_schema_and_counts_review_reused":True},
 "G3":{"declared_components":len(comps),"candidate_component_states":dict(Counter(x["component_usage"] for x in candidates)),
       "pairs":pair_results,"complete_usage_and_lineage_verified":False},
 "G4":{"candidate_rows":candidates,"catalog_rights_approved_count":sum(x["rights_declared_approved"] for x in candidates),
       "declared_six_slots_verified_count":sum(x["six_slots_declared_verified"] for x in candidates),
       "primary_label_and_rights_verification_complete":False},
 "G5":{"admitted":0,"status":"BLOCKED_TARGET_IDENTITY_AND_PRIMARY_EVIDENCE" if any(not x["target_identity_consistent"] for x in candidates) else "BLOCKED_PENDING_PRIMARY_EVIDENCE"},
 "search":{"prior_private_reference_index_reused":reused,"metadata_files_examined":examined,"metadata_bytes_read":bytes_read,"read_errors":read_errors,
           "walk_errors":walk_errors,"walk_limit_reached":bounded,"metadata_limit_reached":scan_cap,
           "target_ids_with_reference":sum(bool(refs[i]) for i in IDS)},
 "private_index_created":True,"image_bytes_read":False,"private_paths_or_labels_exported":False,
 "production_modified":False,"additional_matches":False}
emit("anonymous-holdout-evidence-v1.1.json",summary)
print(json.dumps(summary,ensure_ascii=False,indent=2))
print("COMPLETE: submit ONLY anonymous-holdout-evidence-v1.1.json")
PY
