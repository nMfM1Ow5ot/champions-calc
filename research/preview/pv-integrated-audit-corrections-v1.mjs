// Isolated audit prototypes, NOT integrated into production or existing PV gates.
// The v1 gate function is supplied from the pinned research source, not dynamically loaded.
export function closureGate(records,roster,baseGate){
 const result=baseGate(records,roster);
 const roots=records.map((_,i)=>i);const find=i=>roots[i]===i?i:(roots[i]=find(roots[i]));const join=(i,j)=>{roots[find(i)]=find(j)};
 const keys=new Map();for(const [i,r] of records.entries()){if(!r||typeof r!=="object")continue;for(const f of ["source_group_id","battle_id","image_sha256","crop_sha256"]){if(typeof r[f]!=="string"||!r[f].trim())continue;const k=f+":"+r[f];if(keys.has(k))join(i,keys.get(k));else keys.set(k,i);}}
 const comps=new Map();for(const [i,r] of records.entries()){if(!r||typeof r!=="object")continue;const k=find(i);if(!comps.has(k))comps.set(k,[]);comps.get(k).push(i);}
 const quarantined=new Set(result.quarantine),issues=new Map(result.issues.map(x=>[x.index,new Set(x.codes)]));
 for(const a of comps.values())if(new Set(a.map(i=>records[i].split)).size>1)for(const i of a){quarantined.add(i);if(!issues.has(i))issues.set(i,new Set());issues.get(i).add("TRANSITIVE_SPLIT_LEAKAGE");}
 return {accepted:result.accepted.filter(i=>!quarantined.has(i)),quarantine:[...quarantined].sort((a,b)=>a-b),issues:[...issues.entries()].sort((a,b)=>a[0]-b[0]).map(([index,codes])=>({index,codes:[...codes]}))};
}
export function normalizeIcon(r){
 if(!r||typeof r!=="object")return {type:null,status:"unknown"};
 if(r.status==="blank"&&r.type===null)return {type:null,status:"blank"};
 if(r.status==="read"&&typeof r.type==="string"&&r.type.trim().length>0)return {type:r.type,status:"read"};
 return {type:null,status:"unknown"};
}
export function completeTypes(cells){
 const cs=cells.map(normalizeIcon),ts=cs.filter(x=>x.status==="read").map(x=>x.type);
 return {types:ts,complete:cs.length===2&&cs.every(x=>x.status!=="unknown")&&ts.length>0&&new Set(ts).size===ts.length};
}
