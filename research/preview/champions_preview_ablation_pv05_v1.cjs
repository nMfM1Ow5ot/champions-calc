// Research-only source-group-held-out descriptor ablation. Node.js, no dependencies.
// Usage: node champions_preview_ablation_pv05_v1.cjs preview_features.json species_types.json
function analyze(d,types){
 const ns=Object.keys(d).filter(n=>!/-Mega(?:-[XYZ])?$/.test(n)&&!["Greninja-Bond","Palafin-Hero","Mimikyu-Busted","Morpeko-Hangry"].includes(n)).sort();
 const valid=v=>typeof v.hash==="string"&&/^[a-f0-9]{64}$/i.test(v.hash)&&v.hue?.length===24&&v.hue.every(Number.isFinite)&&Number.isFinite(v.aspect)&&v.aspect>0&&Number.isFinite(v.density);
 const bit=[0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4];
 function prep(v){if(!valid(v))throw Error("invalid descriptor");const a=v.hue,mean=a.reduce((s,x)=>s+x,0)/24,x=a.map(x=>x-mean),norm=Math.hypot(...x);return {...v,h:Array.from(v.hash,x=>parseInt(x,16)),u:x.map(x=>norm?x/norm:0),la:Math.log(v.aspect)}}
 const base=ns.map(n=>({...prep(d[n]),n,source:null}));const tpl=ns.flatMap(n=>(d[n].templates||[]).filter(v=>v.tag!=="shiny"&&typeof v.src==="string"&&v.src.length).map(v=>({...prep(v),n,source:v.src})));
 function components(a,b){let hd=0,hc=0;for(let i=0;i<64;i++)hd+=bit[a.h[i]^b.h[i]];for(let i=0;i<24;i++)hc+=a.u[i]*b.u[i];return [hd/256,-.35*hc,.15*Math.abs(a.la-b.la),.25*Math.abs(a.density-b.density)]}
 function mismatch(a,b){if(!a||!b)return 0;return Math.max(a.filter(t=>!b.includes(t)).length,b.filter(t=>!a.includes(t)).length)}
 const ws={full:[1,1,1,1],no_hash:[0,1,1,1],no_hue:[1,0,1,1],no_geometry:[1,1,0,0],hash_only:[1,0,0,0],hue_only:[0,1,0,0]};
 const configs=Object.entries(ws).flatMap(([name,w])=>[false,true].map(aug=>({name,w,aug})));
 const totals=Object.fromEntries(configs.map(c=>[`${c.name}_${c.aug?"aug":"base"}`,{top1:0,top3:0,rankSum:0,bySpecies:{},ties:0,appearanceTop1:0}]));
 const paired={corrected:0,broken:0,unchangedCorrect:0,unchangedNotCorrect:0};
 const strata={otherSource:{n:0,baseTop1:0,augTop1:0},noOtherSource:{n:0,baseTop1:0,augTop1:0}};
 for(const a of tpl){const pool=[...base,...tpl.filter(b=>b.source!==a.source)];const str=pool.some(b=>b.source&&b.n===a.n)?strata.otherSource:strata.noOtherSource;str.n++;const result={};const matrix=pool.map(b=>({b,c:components(a,b),p:.25*mismatch(types[a.n]?.types,types[b.n]?.types)}));
  for(const cfg of configs){const key=`${cfg.name}_${cfg.aug?"aug":"base"}`,best=new Map(),bestA=new Map();
   for(const {b,c,p} of matrix){if(!cfg.aug&&b.source)continue;const s=c.reduce((sum,x,i)=>sum+x*cfg.w[i],0);if(!best.has(b.n)||best.get(b.n)>s+p)best.set(b.n,s+p);if(!bestA.has(b.n)||bestA.get(b.n)>s)bestA.set(b.n,s)}
   const target=best.get(a.n),rank=1+[...best.values()].filter(s=>s<target-1e-12).length,tie=[...best.values()].filter(s=>Math.abs(s-target)<=1e-12).length;const ar=bestA.get(a.n);const aTop=[...bestA.values()].filter(s=>s<=ar+1e-12).length===1;
   const m=totals[key],ok=rank===1&&tie===1;m.top1+=+ok;m.top3+=+(rank+tie-1<=3);m.ties+=+(tie>1);m.appearanceTop1+=+aTop;m.rankSum+=rank;m.bySpecies[a.n]??=[0,0];m.bySpecies[a.n][0]+=+ok;m.bySpecies[a.n][1]++;result[key]=ok;
  }
  const x=result.full_base,y=result.full_aug;paired[x?(y?"unchangedCorrect":"broken"):(y?"corrected":"unchangedNotCorrect")]++;str.baseTop1+=+x;str.augTop1+=+y;
 }
 const key=v=>JSON.stringify([v.hash,v.hue,v.aspect,v.density]);const groups=new Map();for(const a of tpl){const k=key(a);if(!groups.has(k))groups.set(k,[]);groups.get(k).push(a)}const dup=[...groups.values()].filter(v=>new Set(v.map(t=>t.source)).size>1);
 const bg=new Map();for(const a of base){const k=key(a);if(!bg.has(k))bg.set(k,[]);bg.get(k).push(a)}const bd=[...bg.values()].filter(v=>v.length>1);
 return {schema:"preview-cause-ablation-pv05-v1",eligibleEntries:ns.length,queries:tpl.length,sourceGroups:new Set(tpl.map(v=>v.source)).size,queryLabels:new Set(tpl.map(v=>v.n)).size,baseWithoutSourceMetadata:base.filter(v=>!v.src).length,crossSourceExactDuplicateGroups:dup.length,baseExactDuplicateGroups:bd.length,baseExactDuplicateEntries:bd.reduce((s,x)=>s+x.length,0),paired,strata,results:Object.fromEntries(Object.entries(totals).map(([k,m])=>[k,{top1:m.top1,top3:m.top3,meanRank:m.rankSum/tpl.length,appearanceTop1:m.appearanceTop1,ties:m.ties,macroTop1:Object.values(m.bySpecies).reduce((s,[a,b])=>s+a/b,0)/Object.keys(m.bySpecies).length}]))};
}
if (require.main === module) {
 const fs=require('node:fs');
 if(process.argv.length!==4) throw Error('expected two JSON paths');
 console.log(JSON.stringify(analyze(JSON.parse(fs.readFileSync(process.argv[2],'utf8')),JSON.parse(fs.readFileSync(process.argv[3],'utf8'))),null,2));
}
module.exports={analyze};
