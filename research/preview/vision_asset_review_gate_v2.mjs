// Research-only, normalized allowlisted projection; not direct Muse JSON parser or independent proof.
import fs from 'node:fs';import crypto from 'node:crypto';
function audit(rows) {
 const errors=[], blockers=[], idRe={asset:/^I[0-9]{4,}$/,battle:/^B[0-9]{3,}$/,group:/^G[0-9]{3,}$/};
 const scenes=["preview","battle_message","battle_command","hp_display","battle_result","other","unknown"];
 const usage=["used","not_found","unknown"], independence=["used","related","candidate","unknown"];
 const enums={scene_class:scenes,scene_verification_status:["verified","unverified","unknown"],prior_usage_pv:usage,prior_usage_ocr:usage,prior_usage_reference_bank:usage,independence_pv:independence,independence_ocr:independence,label_verification_status:["verified","unverified","unknown"],rights_status:["approved_local_research","unknown","denied"],proposed_split:["development","reference","candidate","quarantine","unknown"]};
 const fields=["asset_id","battle_id","source_group_id","linked_group_ids","github_entry_count","local_file_count","verified_slot_count",...Object.keys(enums)];
 if(!Array.isArray(rows)||!rows.length)return {status:"FAIL",errors:["EMPTY_OR_INVALID_ROWS"]};
 const ids=new Set(),groups=new Set(),battles=new Set();
 for(const [i,r] of rows.entries()){
  if(!r||typeof r!=="object"||Array.isArray(r)){errors.push(`ROW_${i}_TYPE`);continue;}
  if(Object.keys(r).length!==fields.length||fields.some(k=>!Object.hasOwn(r,k))||Object.keys(r).some(k=>!fields.includes(k)))errors.push(`ROW_${i}_SCHEMA`);
  if((typeof r.asset_id!=="string"||!idRe.asset.test(r.asset_id))||ids.has(r.asset_id))errors.push(`ROW_${i}_ASSET_ID`);ids.add(r.asset_id);
  if(r.battle_id!==null&&(typeof r.battle_id!=="string"||!idRe.battle.test(r.battle_id)))errors.push(`ROW_${i}_BATTLE_ID`);if(r.battle_id!==null)battles.add(r.battle_id);
  if(r.source_group_id!==null&&(typeof r.source_group_id!=="string"||!idRe.group.test(r.source_group_id)))errors.push(`ROW_${i}_GROUP_ID`);if(r.source_group_id!==null)groups.add(r.source_group_id);
  if(!Array.isArray(r.linked_group_ids)||r.linked_group_ids.some(x=>typeof x!=="string"||!idRe.group.test(x))||new Set(r.linked_group_ids).size!==r.linked_group_ids.length)errors.push(`ROW_${i}_LINKS`);
  for(const k of ["github_entry_count","local_file_count"])if(!Number.isSafeInteger(r[k])||r[k]<1)errors.push(`ROW_${i}_COUNT_${k}`);
  if(r.verified_slot_count!==null&&(!Number.isSafeInteger(r.verified_slot_count)||r.verified_slot_count<0||r.verified_slot_count>6))errors.push(`ROW_${i}_SLOTS`);
  for(const [k,v] of Object.entries(enums))if(!v.includes(r[k]))errors.push(`ROW_${i}_ENUM_${k}`);
  if(r.verified_slot_count===6&&r.label_verification_status!=="verified")errors.push(`ROW_${i}_LABEL_CONTRADICTION`);
 }
 if(errors.length)return {status:"FAIL",errors};
 const parent=rows.map((_,i)=>i), root=i=>{while(parent[i]!==i){parent[i]=parent[parent[i]];i=parent[i]}return i;},join=(i,j)=>{parent[root(i)]=root(j)};
 const keys=new Map(),unresolved=new Set();
 for(const [i,r] of rows.entries()){
  if(r.battle_id===null||r.source_group_id===null)unresolved.add(i);
  for(const g of r.linked_group_ids)if(!groups.has(g))unresolved.add(i);
  const ks=[...(r.battle_id?["b:"+r.battle_id]:[]),...(r.source_group_id?["g:"+r.source_group_id]:[]),...r.linked_group_ids.map(g=>"g:"+g)];
  for(const k of ks){if(keys.has(k))join(i,keys.get(k));else keys.set(k,i)}
 }
 const comps=new Map();for(const [i,r] of rows.entries()){const k=root(i);if(!comps.has(k))comps.set(k,[]);comps.get(k).push(i);}
 const results={};for(const s of ["pv","ocr"]){
  const states=Array(rows.length).fill("unknown");
  for(const ix of comps.values()){
   const used=ix.some(i=>rows[i]["prior_usage_"+s]==="used"||rows[i].prior_usage_reference_bank==="used");
   const unknown=ix.some(i=>unresolved.has(i)||rows[i]["prior_usage_"+s]==="unknown"||rows[i].prior_usage_reference_bank==="unknown");
   for(const i of ix){const r=rows[i];states[i]=r["prior_usage_"+s]==="used"||r.prior_usage_reference_bank==="used"?"used":used?"related":unknown?"unknown":"candidate";
    if(r["independence_"+s]==="candidate"&&states[i]!=="candidate")errors.push(`ROW_${i}_${s.toUpperCase()}_FALSE_CANDIDATE`);
    if(r["independence_"+s]!==states[i])blockers.push(`ROW_${i}_${s.toUpperCase()}_DECLARATION_DIFF`);
   }
  }
  const preview=rows.map((r,i)=>({r,i})).filter(({r})=>r.scene_class==="preview");
  const candidate=preview.filter(({i})=>states[i]==="candidate");
  const labelDeclared=candidate.filter(({r})=>r.label_verification_status==="verified"&&r.verified_slot_count===6);
  const verified=labelDeclared.filter(({r})=>r.scene_verification_status==="verified"&&r.rights_status==="approved_local_research");
  const distinct=x=>new Set(x.filter(({r})=>r.battle_id!==null).map(({r})=>r.battle_id)).size;
  const cross=Object.fromEntries(scenes.map(sc=>[sc,Object.fromEntries(independence.map(st=>[st,rows.filter((r,i)=>r.scene_class===sc&&states[i]===st).length]))]));
  const byBattle=Object.fromEntries([...battles].sort().map(b=>{const ix=rows.map((r,i)=>({r,i})).filter(({r})=>r.battle_id===b);return [b,{images:ix.length,preview:ix.filter(({r})=>r.scene_class==="preview").length,candidatePreview:ix.filter(({r,i})=>r.scene_class==="preview"&&states[i]==="candidate").length,verifiedCandidatePreview:verified.filter(({r})=>r.battle_id===b).length}]}));
  results[s]={cross,byBattle,A:distinct(preview),B:distinct(candidate),C:candidate.length,D:distinct(labelDeclared),D_screen_rights_declared:distinct(verified),E:preview.filter(({r})=>r.battle_id===null).length,candidateComponents:new Set(candidate.map(({i})=>root(i))).size};
 }
 return {status:errors.length?"FAIL":blockers.length?"REVIEW_REQUIRED":"STRUCTURAL_PASS_ONLY",errors,blockers,counts:{unique:rows.length,github:rows.reduce((a,r)=>a+r.github_entry_count,0),local:rows.reduce((a,r)=>a+r.local_file_count,0),battles:battles.size,scenes:Object.fromEntries(scenes.map(s=>[s,rows.filter(r=>r.scene_class===s).length])),labelVerified:rows.filter(r=>r.label_verification_status==="verified").length},results,warning:"Declarations and inferred connectivity only. No proof of provenance, label truth, rights, or actual independence. No holdout admission."};
}
const base={"asset_id":"I0001","battle_id":"B001","source_group_id":"G001","linked_group_ids":[],"github_entry_count":1,"local_file_count":1,"verified_slot_count":6,"scene_class":"preview","scene_verification_status":"verified","prior_usage_pv":"not_found","prior_usage_ocr":"not_found","prior_usage_reference_bank":"not_found","independence_pv":"candidate","independence_ocr":"candidate","label_verification_status":"verified","rights_status":"approved_local_research","proposed_split":"candidate"},b={"asset_id":"I0002","battle_id":"B002","source_group_id":"G002","linked_group_ids":[],"github_entry_count":1,"local_file_count":1,"verified_slot_count":6,"scene_class":"preview","scene_verification_status":"verified","prior_usage_pv":"not_found","prior_usage_ocr":"not_found","prior_usage_reference_bank":"not_found","independence_pv":"candidate","independence_ocr":"candidate","label_verification_status":"verified","rights_status":"approved_local_research","proposed_split":"candidate"},c={"asset_id":"I0003","battle_id":"B003","source_group_id":"G003","linked_group_ids":[],"github_entry_count":1,"local_file_count":1,"verified_slot_count":6,"scene_class":"preview","scene_verification_status":"verified","prior_usage_pv":"not_found","prior_usage_ocr":"not_found","prior_usage_reference_bank":"not_found","independence_pv":"candidate","independence_ocr":"candidate","label_verification_status":"verified","rights_status":"approved_local_research","proposed_split":"candidate"};
if(process.argv.includes('--self-test')){const t={positive:(audit([base,b]).status==="STRUCTURAL_PASS_ONLY"),duplicate:(audit([base,base]).status==="FAIL"),unknown_field:(audit([{...base,raw_image:"x"}]).status==="FAIL"),invalid_count:(audit([{...base,local_file_count:0}]).status==="FAIL"),invalid_slot:(audit([{...base,verified_slot_count:7}]).status==="FAIL"),label_contradiction:(audit([{...base,label_verification_status:"unverified"}]).status==="FAIL"),used_pv_not_ocr:(audit([{...base,prior_usage_pv:"used",independence_pv:"used"},b]).results.ocr.B===2),same_battle:(audit([{...base,prior_usage_pv:"used",independence_pv:"used"},{...b,battle_id:"B001"}]).status==="FAIL"),transitive:(audit([{...base,prior_usage_reference_bank:"used",independence_pv:"used",independence_ocr:"used"},{...b,linked_group_ids:["G001","G003"],independence_pv:"related",independence_ocr:"related"},c]).status==="FAIL"),dangling:(audit([{...base,linked_group_ids:["G999"]}]).status==="FAIL"),missing_battle:(audit([{...base,battle_id:null}]).status==="FAIL"),unknown_usage:(audit([{...base,prior_usage_pv:"unknown"}]).status==="FAIL"),unverified_labels:(audit([{...base,verified_slot_count:0,label_verification_status:"unverified"}]).results.pv.D===0),rights_unknown:(audit([{...base,rights_status:"unknown"}]).results.pv.D_screen_rights_declared===0),independent_groups:(audit([base,{...b,linked_group_ids:["G001"]}]).results.pv.candidateComponents===1)};Object.assign(t,{strict_asset_type:audit([{...base,asset_id:['I0001']}]).status==='FAIL',strict_link_type:audit([{...base,linked_group_ids:[['G001']]}]).status==='FAIL',D_distinct_from_rights:audit([{...base,rights_status:'unknown'}]).results.pv.D===1});console.log(JSON.stringify(t,null,2));process.exitCode=Object.values(t).every(Boolean)?0:1;}else{const expected=process.argv[3];if(!/^[a-f0-9]{64}$/.test(expected??""))throw Error("expected SHA-256 required");const b=fs.readFileSync(process.argv[2]);if(crypto.createHash("sha256").update(b).digest("hex")!==expected)throw Error("SHA-256 mismatch");const r=audit(JSON.parse(b.toString("utf8")));console.log(JSON.stringify(r,null,2));process.exitCode=r.status==="FAIL"?1:r.status==="REVIEW_REQUIRED"?2:0;}
