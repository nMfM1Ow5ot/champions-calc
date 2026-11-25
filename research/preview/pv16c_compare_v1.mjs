// PV16-C: descriptor-level A/B/C comparison; research only. Node >=18.
// Input must be a local JSON with frozen candidates, equal reference counts per species, and paired queries.
// Feature format: PV13 hash/hue/aspect/density. IDs are exact form labels; color variants are separate templates, not species.
// Only aggregate output; do not commit input, raw images, lineup or labels. C has twice the templates; not a count-controlled substitution.
import fs from 'node:fs';
function compare(input) {
 const check=(b,m)=>{if(!b)throw Error(m)};
 const ids=input.candidates;check(Array.isArray(ids)&&ids.length>=2&&ids.every(x=>typeof x==="string"&&x.length)&&new Set(ids).size===ids.length,"invalid candidates");
 const allowed=new Set(ids), eps=1e-12;
 function prep(f){check(f&&typeof f.hash==="string"&&/^[0-9a-f]{64}$/i.test(f.hash),"bad hash");check(Array.isArray(f.hue)&&f.hue.length===24&&f.hue.every(x=>Number.isFinite(x)&&x>=0),"bad hue");const sum=f.hue.reduce((a,b)=>a+b,0);check(sum>0&&Number.isFinite(sum)&&Number.isFinite(f.aspect)&&f.aspect>0&&Number.isFinite(f.density)&&f.density>=0&&f.density<=1,"invalid descriptor");return {hash:BigInt("0x"+f.hash),p:f.hue.map(x=>x/sum),aspect:f.aspect,density:f.density};}
 function dist(a,b){let x=a.hash^b.hash,n=0;while(x){x&=x-1n;n++}let bc=a.p.reduce((s,v,i)=>s+Math.sqrt(v*b.p[i]),0);return n/256+.15*Math.abs(Math.log(a.aspect/b.aspect))+.25*Math.abs(a.density-b.density)+.7*Math.sqrt(Math.max(0,1-bc));}
 function bank(x){check(Array.isArray(x),"bad bank");const b=new Map(ids.map(id=>[id,[]]));for(const v of x){check(allowed.has(v.id),"out-of-scope reference");b.get(v.id).push(prep(v.feature));}for(const a of b.values())check(a.length>0,"missing candidate");return b;}
 const A=bank(input.old),B=bank(input.poke);
 for(const id of ids)check(A.get(id).length===B.get(id).length,"unmatched reference counts for "+id);
 const C=new Map(ids.map(id=>[id,[...A.get(id),...B.get(id)]]));
 check(Array.isArray(input.queries)&&input.queries.length>0,"no queries");
 const seen=new Set();for(const q of input.queries){check(typeof q.key==="string"&&q.key&&!seen.has(q.key)&&allowed.has(q.target),"invalid query key/target");seen.add(q.key);check(typeof q.group==="string"&&q.group.length>0,"missing recording group");}
 const out={candidateCount:ids.length,queryCount:input.queries.length,groupCount:new Set(input.queries.map(q=>q.group)).size,arms:{}};
 for(const [arm,b] of [["A",A],["B",B],["C",C]]){const rows=input.queries.map(q=>{const a=prep(q.feature);const s=ids.map(id=>({id,d:Math.min(...b.get(id).map(v=>dist(a,v)))}));const target=s.find(v=>v.id===q.target).d;const rank=s.filter(v=>v.d<=target+eps).length;return {rank,verified:q.verified===true,group:q.group};});
 const agg=z=>({n:z.length,top1:z.filter(r=>r.rank===1).length,top3:z.filter(r=>r.rank<=3).length,mrr:z.length?z.reduce((s,r)=>s+1/r.rank,0)/z.length:null});
 out.arms[arm]={all:agg(rows),verified:agg(rows.filter(r=>r.verified)),referenceCounts:ids.reduce((s,id)=>s+b.get(id).length,0)};}
 return out;
}
function selftest(){const d=i=>({hash:"0".repeat(64),hue:Array.from({length:24},(_,j)=>+(j===i)),aspect:1,density:.5});const z={candidates:["x","y"],old:[{id:"x",feature:d(1)},{id:"y",feature:d(0)}],poke:[{id:"x",feature:d(0)},{id:"y",feature:d(1)}],queries:[{key:"1",group:"same",target:"x",verified:true,feature:d(0)},{key:"2",group:"same",target:"y",verified:false,feature:d(1)}]};const t=compare(z),tests={correct_replacement:t.arms.B.all.top1===2,old_errors:t.arms.A.all.top1===0,worst_tie_rank:t.arms.C.all.top1===0&&t.arms.C.all.mrr===.5,verified_subset:t.arms.B.verified.n===1,group_count:t.groupCount===1,combined_count:t.arms.C.referenceCounts===4};for(const [k,mut] of [["missing_candidate",x=>x.poke.pop()],["unequal_templates",x=>x.old.push(x.old[0])],["duplicate_query",x=>x.queries.push(x.queries[0])],["zero_histogram",x=>x.queries[0].feature.hue.fill(0)]]){const x=JSON.parse(JSON.stringify(z));mut(x);try{compare(x);tests[k]=false}catch(e){tests[k]=true}}if(!Object.values(tests).every(Boolean))throw Error(JSON.stringify(tests));return tests;}
if(process.argv[2]==='--selftest') console.log(JSON.stringify(selftest(),null,2)); else {if(process.argv.length!==3)throw Error('usage: node pv16c_compare_v1.mjs input.json'); console.log(JSON.stringify(compare(JSON.parse(fs.readFileSync(process.argv[2],'utf8'))),null,2));}
