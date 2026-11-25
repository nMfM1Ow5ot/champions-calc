// PV-08 research-only, no production writes. Node.js >=18, no dependencies.
// Usage: node research/preview/pv08-hard-negatives-v1.mjs <directory containing three frozen JSON files>
// Frozen commit f43460ad3d93ac4591a8e1e8bb924b6050c7f5a4; exact Git blob hashes verified.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
const dir=process.argv[2]||'data';
const load=(name,sha)=>{const b=fs.readFileSync(path.join(dir,name));const actual=crypto.createHash('sha1').update('blob '+b.length+'\0').update(b).digest('hex');if(actual!==sha)throw Error(name+' blob mismatch '+actual);return JSON.parse(b);};
const F=load('preview_features.json','16052f6a51447db3fc41fe2e2debdf1a795bd01c');
const T=load('species_types.json','bfeba203f6cd0d891d56ae60a5ec4f761209cb6b');
const R=load('regulation.json','cf4df343979e930a47e3a71e083a3943e013895f');
const names=[...new Set(R.species)].filter(n=>F[n]&&!/-Mega(?:-[XYZ])?$/.test(n)&&!['Greninja-Bond','Palafin-Hero','Mimikyu-Busted','Morpeko-Hangry'].includes(n));
const norm=h=>{const s=h.reduce((a,b)=>a+b,0);return h.map(v=>v/s)};
const prep=f=>({...f,hb:BigInt('0x'+f.hash),p:norm(f.hue)});
const bank=Object.fromEntries(names.map(n=>[n,[prep(F[n]),...(F[n].templates??[]).filter(x=>x.tag!=='shiny').map(prep)]]));
const queries=names.flatMap(n=>bank[n].slice(1).filter(x=>x.src).map(q=>({n,q})));
const pop=x=>{let z=0;while(x){x&=x-1n;z++}return z};
const types=n=>(T[n]?.types??[]).slice().sort().join('/');
const dist=(a,b)=>{const h=pop(a.hb^b.hb)/256+.15*Math.abs(Math.log(a.aspect/b.aspect))+.25*Math.abs(a.density-b.density);let aa=0,bb=0,ab=0,bc=0;for(let i=0;i<24;i++){const x=a.p[i]-1/24,y=b.p[i]-1/24;aa+=x*x;bb+=y*y;ab+=x*y;bc+=Math.sqrt(a.p[i]*b.p[i]);}return [h-.35*(aa*bb?ab/Math.sqrt(aa*bb):0),h+.7*Math.sqrt(Math.max(0,1-bc))]};
const modes=['legacy','hellinger'], rows=[];
for(const {n,q} of queries){const rank=[[],[]];for(const k of names){let ds=[Infinity,Infinity];for(const b of bank[k]){if(b.src===q.src)continue;const d=dist(q,b);ds=ds.map((v,i)=>Math.min(v,d[i]));}ds.forEach((d,i)=>rank[i].push({k,d}));}
const row={n,src:q.src,otherRefs:bank[n].filter(b=>b.src&&b.src!==q.src).length};for(let i=0;i<2;i++){const r=rank[i].sort((a,b)=>a.d-b.d||a.k.localeCompare(b.k));const same=r.filter(x=>types(x.k)===types(n));const score=r.find(x=>x.k===n).d;const sr=same.find(x=>x.k===n).d;const rankOf=(ar,s)=>ar.filter(x=>x.d<=s+1e-12).length;row[modes[i]]={rank:rankOf(r,score),sameRank:rankOf(same,sr),winner:r[0].k,sameWinner:same[0].k,margin:r[1].d-r[0].d};}rows.push(row);}
const summar=(a,m)=>({n:a.length,top1:a.filter(x=>x[m].rank===1).length,top3:a.filter(x=>x[m].rank<=3).length,sameTop1:a.filter(x=>x[m].sameRank===1).length,sameTop3:a.filter(x=>x[m].sameRank<=3).length});
const report={candidates:names.length,queries:rows.length,sources:new Set(rows.map(x=>x.src)).size,labels:new Set(rows.map(x=>x.n)).size,summary:Object.fromEntries(modes.map(m=>[m,summar(rows,m)])),byOtherRefs:Object.fromEntries([0,1,2].map(i=>[i===2?'2+':String(i),Object.fromEntries(modes.map(m=>[m,summar(rows.filter(x=>i===2?x.otherRefs>=2:x.otherRefs===i),m)]))])),paired:Object.fromEntries(['rank','sameRank'].map(k=>[k,{improved:rows.filter(x=>x.legacy[k]!==1&&x.hellinger[k]===1).length,worsened:rows.filter(x=>x.legacy[k]===1&&x.hellinger[k]!==1).length}])),sameTypeConfusions:Object.fromEntries(modes.map(m=>{const counts={};for(const x of rows.filter(x=>x[m].sameRank!==1)){const k=x.n+' -> '+x[m].sameWinner;counts[k]=(counts[k]??0)+1;}return [m,Object.entries(counts).sort((a,b)=>b[1]-a[1])]})),selective:Object.fromEntries(modes.map(m=>[m,[0,.025,.05,.1,.15].map(t=>{const a=rows.filter(x=>x[m].margin>t+1e-12);return {margin:t,accepted:a.length,wrong:a.filter(x=>x[m].rank!==1).length}})]))};
console.log(JSON.stringify(report,null,2));
