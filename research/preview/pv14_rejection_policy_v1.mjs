// PV14 post-hoc exploratory policy comparison, not independent validation.
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
function compare(F,R){
 const names=[...new Set(R.species)].filter(n=>F[n]&&!/-Mega(?:-[XYZ])?$/.test(n)&&!["Greninja-Bond","Palafin-Hero","Mimikyu-Busted","Morpeko-Hangry"].includes(n));
 const prep=f=>({...f,b:BigInt("0x"+f.hash),p:f.hue.map(x=>x/f.hue.reduce((s,y)=>s+y,0))});
 const bank=Object.fromEntries(names.map(n=>[n,[prep(F[n]),...(F[n].templates??[]).filter(t=>t.tag!=="shiny").map(prep)]]));
 const d=(a,b)=>{let v=a.b^b.b,k=0;while(v){v&=v-1n;k++}let aa=0,bb=0,ab=0,bc=0;for(let i=0;i<24;i++){let x=a.p[i]-1/24,y=b.p[i]-1/24;aa+=x*x;bb+=y*y;ab+=x*y;bc+=Math.sqrt(a.p[i]*b.p[i])}const h=k/256+.15*Math.abs(Math.log(a.aspect/b.aspect))+.25*Math.abs(a.density-b.density);return [h-.35*(aa*bb?ab/Math.sqrt(aa*bb):0),h+.7*Math.sqrt(Math.max(0,1-bc))]};
 const rows=[];for(const n of names)for(const q of bank[n].slice(1).filter(x=>x.src)){
 let ranks=[[],[]];for(const k of names){let v=[Infinity,Infinity];for(const b of bank[k])if(b.src!==q.src){const z=d(q,b);v=v.map((x,i)=>Math.min(x,z[i]))}for(let i=0;i<2;i++)ranks[i].push({k,d:v[i]})}
 ranks=ranks.map(r=>r.sort((a,b)=>a.d-b.d||a.k.localeCompare(b.k)));for(const unknown of [false,true]){
 const [a,b]=ranks.map(r=>unknown?r.filter(x=>x.k!==n):r);const lg=a[1].d-a[0].d,hg=b[1].d-b[0].d;
 rows.push({n,src:q.src,unknown,correct:b[0].k===n,legacyCorrect:a[0].k===n,legacy:lg>.15+1e-12,hellinger:hg>.1+1e-12,score:b[0].d,agree:a[0].k===b[0].k});}}
 const policies={legacy:r=>r.legacy,hellinger:r=>r.hellinger,hellinger_abs_050:r=>r.hellinger&&r.score<=.5,hellinger_abs_045:r=>r.hellinger&&r.score<=.45,hellinger_agree:r=>r.hellinger&&r.agree,dual_margin_agree:r=>r.hellinger&&r.legacy&&r.agree};
 return Object.fromEntries(Object.entries(policies).map(([n,p])=>{let k=rows.filter(r=>!r.unknown&&p(r)),u=rows.filter(r=>r.unknown&&p(r));return [n,{knownAccepted:k.length,knownWrong:k.filter(r=>!(n==="legacy"?r.legacyCorrect:r.correct)).length,unknownAccepted:u.length,knownSources:new Set(k.map(r=>r.src)).size,unknownSources:new Set(u.map(r=>r.src)).size}]}));
}
const dir=process.argv[2]||'data';const load=(n,h)=>{const b=fs.readFileSync(path.join(dir,n));if(crypto.createHash('sha1').update('blob '+b.length+'\0').update(b).digest('hex')!==h)throw Error('input blob mismatch');return JSON.parse(b);};
console.log(JSON.stringify(compare(load('preview_features.json','16052f6a51447db3fc41fe2e2debdf1a795bd01c'),load('regulation.json','cf4df343979e930a47e3a71e083a3943e013895f')),null,2));
