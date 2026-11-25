// PV15 v2 research gate. Checks declarations; does not certify provenance, labels, policy signature, or independence. Separate one-sided 95% bounds; not a simultaneous confidence statement. No production writes.
import fs from 'node:fs';
function gateV2(e,p){
 const issues=[];const check=(ok,id)=>{if(!ok)issues.push(id);return !!ok};
 const obj=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
 const str=x=>typeof x==="string"&&x.trim().length>0;
 const sha=x=>typeof x==="string"&&/^[a-f0-9]{64}$/.test(x);
 const rate=x=>Number.isFinite(x)&&x>0&&x<1;
 const count=x=>Number.isSafeInteger(x)&&x>0;
 const bound=(n,k)=>n>0&&k===0?-Math.expm1(Math.log(.05)/n):null;
 const po=obj(p)&&p.approved===true&&str(p.id)&&sha(p.frozenConfigSha256)&&count(p.minBattles)&&count(p.minUnknownGroups)&&count(p.minNegativeGroups)&&rate(p.maxBattleErrorUpper)&&rate(p.maxUnknownErrorUpper)&&rate(p.maxNegativeErrorUpper)&&Number.isFinite(p.minFullCorrectCoverage)&&p.minFullCorrectCoverage>0&&p.minFullCorrectCoverage<=1;
 check(po,"POLICY_NOT_APPROVED_OR_INVALID");
 if(!obj(e))return {decision:"BLOCKED",issues:[...issues,"EVIDENCE_INVALID"]};
 for(const flag of ["frozenBeforeEvaluation","provenanceAudit","rosterAudit","labelAudit","productionEquivalent","realUnknownChallenge","sceneNegativeChallenge"])check(e[flag]===true,flag.toUpperCase()+"_REQUIRED");
 check(po&&e.frozenConfigSha256===p.frozenConfigSha256,"CONFIG_BINDING_MISMATCH");
 const collect=(arr,kind,validOutcome)=>{
  let ids=new Set(),groups=new Set(),hashes=new Set(),n=0,wrong=0,full=0,valid=Array.isArray(arr);
  for(const r of Array.isArray(arr)?arr:[]){
   if(!obj(r)||!str(r.id)||!str(r.group)||!sha(r.imageSha256)||r.independent!==true||r.labelVerified!==true||ids.has(r.id)||groups.has(r.group)||hashes.has(r.imageSha256)||!validOutcome(r)){valid=false;continue;}
   ids.add(r.id);groups.add(r.group);hashes.add(r.imageSha256);n++;
   if(kind==="battle"){if(r.slots.some(s=>s.outcome==="wrong"))wrong++;if(r.slots.every(s=>s.outcome==="correct"))full++;}
   else if(r.outcome==="false_accept")wrong++;
  }
  check(valid,kind.toUpperCase()+"_INVALID_OR_DUPLICATE");
  return {n,wrong,...(kind==="battle"?{full,coverage:n?full/n:null}:{}),zeroErrorUpper95:bound(n,wrong)};
 };
 const battle=collect(e.battles,"battle",r=>Array.isArray(r.slots)&&r.slots.length===6&&new Set(r.slots.map(s=>s?.index)).size===6&&r.slots.every(s=>obj(s)&&Number.isInteger(s.index)&&s.index>=1&&s.index<=6&&s.labelVerified===true&&["correct","wrong","abstain"].includes(s.outcome)));
 const unknown=collect(e.unknownGroups,"unknown",r=>["reject","false_accept"].includes(r.outcome));
 const negative=collect(e.negativeGroups,"negative",r=>["reject","false_accept"].includes(r.outcome));
 for(const [k,x,min,max] of [["BATTLE",battle,p?.minBattles,p?.maxBattleErrorUpper],["UNKNOWN",unknown,p?.minUnknownGroups,p?.maxUnknownErrorUpper],["NEGATIVE",negative,p?.minNegativeGroups,p?.maxNegativeErrorUpper]]){
  check(x.n>0,k+"_NO_ELIGIBLE_GROUPS");check(x.wrong===0,k+"_FALSE_ACCEPT");
  if(po){check(x.n>=min,k+"_INSUFFICIENT_N");check(x.zeroErrorUpper95!==null&&x.zeroErrorUpper95<=max,k+"_ERROR_BOUND_NOT_MET");}
 }
 if(po)check(battle.coverage!==null&&battle.coverage>=p.minFullCorrectCoverage,"COVERAGE_INSUFFICIENT");
 return {decision:issues.length?"BLOCKED":"ELIGIBLE_FOR_HUMAN_REVIEW",issues,battle,unknown,negative};
}
function selfTest(gate){
 const hash=n=>n.toString(16).padStart(64,"0");const p={approved:true,id:"synthetic-only",frozenConfigSha256:hash(999),minBattles:2,minUnknownGroups:2,minNegativeGroups:2,maxBattleErrorUpper:.8,maxUnknownErrorUpper:.8,maxNegativeErrorUpper:.8,minFullCorrectCoverage:.5};
 const base=(i)=>({id:"id"+i,group:"g"+i,imageSha256:hash(i),independent:true,labelVerified:true});
 const b=i=>({...base(i),slots:Array.from({length:6},(_,j)=>({index:j+1,labelVerified:true,outcome:"correct"}))});
 const c=i=>({...base(i),outcome:"reject"});
 const e={frozenBeforeEvaluation:true,provenanceAudit:true,rosterAudit:true,labelAudit:true,productionEquivalent:true,realUnknownChallenge:true,sceneNegativeChallenge:true,frozenConfigSha256:p.frozenConfigSha256,battles:[b(1),b(2)],unknownGroups:[c(3),c(4)],negativeGroups:[c(5),c(6)]};
 const cases=[
 ["positive_control",e,p,true],["no_policy",e,null,false],["no_battles",{...e,battles:[]},p,false],["one_unknown",{...e,unknownGroups:[c(3)]},p,false],["one_negative",{...e,negativeGroups:[c(5)]},p,false],
 ["same_unknown_group",{...e,unknownGroups:[c(3),{...c(4),group:"g3"}]},p,false],["same_negative_hash",{...e,negativeGroups:[c(5),{...c(6),imageSha256:hash(5)}]},p,false],["unknown_false_accept",{...e,unknownGroups:[c(3),{...c(4),outcome:"false_accept"}]},p,false],["negative_false_accept",{...e,negativeGroups:[c(5),{...c(6),outcome:"false_accept"}]},p,false],
 ["unknown_rate_bound",e,{...p,maxUnknownErrorUpper:.1},false],["negative_rate_bound",e,{...p,maxNegativeErrorUpper:.1},false],["battle_rate_bound",e,{...p,maxBattleErrorUpper:.1},false],
 ["duplicate_battle",{...e,battles:[b(1),b(1)]},p,false],["duplicate_slots",{...e,battles:[b(1),{...b(2),slots:b(2).slots.map(s=>({...s,index:1}))}]},p,false],
 ["wrong_slot",{...e,battles:[b(1),{...b(2),slots:b(2).slots.map((s,i)=>i===0?{...s,outcome:"wrong"}:s)}]},p,false],["all_abstain",{...e,battles:[1,2].map(i=>({...b(i),slots:b(i).slots.map(s=>({...s,outcome:"abstain"}))}))},p,false],
 ["config_mismatch",{...e,frozenConfigSha256:hash(998)},p,false],["unverified_unknown",{...e,unknownGroups:[c(3),{...c(4),labelVerified:false}]},p,false],["not_frozen",{...e,frozenBeforeEvaluation:false},p,false],["not_equivalent",{...e,productionEquivalent:false},p,false],["legacy_count_only",{...e,unknownGroups:undefined,negativeGroups:undefined,unknownTrials:1000,negativeSceneTrials:1000},p,false],["malformed",[],p,false]];
 return Object.fromEntries(cases.map(([n,e,p,ok])=>[n,gate(e,p).decision===(ok?"ELIGIBLE_FOR_HUMAN_REVIEW":"BLOCKED")]));
}
if(process.argv.includes('--self-test')){const t=selfTest(gateV2);console.log(JSON.stringify(t,null,2));process.exitCode=Object.values(t).every(Boolean)?0:1;}else{const r=gateV2(JSON.parse(fs.readFileSync(process.argv[2],'utf8')),JSON.parse(fs.readFileSync(process.argv[3],'utf8')));console.log(JSON.stringify(r,null,2));process.exitCode=r.decision==='BLOCKED'?1:0;}
