// Research only. No downloads, credentials, writes to source tree or production integration.
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';import {execFileSync} from 'node:child_process';import {createRequire} from 'node:module';
function runCases(TeamValidator,format){
 const base=[
 ["Incineroar","Intimidate",["Fake Out","Flare Blitz","Parting Shot","Protect"]],
 ["Rillaboom","Grassy Surge",["Fake Out","Wood Hammer","Grassy Glide","Protect"]],
 ["Garchomp","Rough Skin",["Earthquake","Dragon Claw","Rock Slide","Protect"]],
 ["Pelipper","Drizzle",["Hurricane","Weather Ball","Tailwind","Protect"]],
 ["Gardevoir","Trace",["Psychic","Moonblast","Trick Room","Protect"]],
 ["Gengar","Cursed Body",["Shadow Ball","Sludge Bomb","Taunt","Protect"]]
 ].map(([species,ability,moves])=>({name:species,species,ability,moves,item:"",nature:"Hardy",level:50,evs:{hp:2,atk:32,def:0,spa:0,spd:0,spe:32},ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31}}));
 const clone=x=>JSON.parse(JSON.stringify(x));
 const run=(id,team,expect)=>{try{const before=clone(team),after=clone(team),r=new TeamValidator(format).validateTeam(after);if(r!==null&&(!Array.isArray(r)||!r.every(x=>typeof x==="string")))throw Error("unexpected validator result");const decision=r===null||r.length===0?"ACCEPTED":"REJECTED";return {id,expected:expect,decision,match:decision===expect,problems:r??[],input:before,normalized:after,mutated:JSON.stringify(before)!==JSON.stringify(after)};}catch(e){return {id,expected:expect,decision:"ERROR",match:false,error:String(e)}}};
 const positive=run("positive_control",base,"ACCEPTED");if(!positive.match)return {status:"BLOCKED_POSITIVE_CONTROL",cases:[positive]};
 const cases=[positive];
 const add=(id,expect,mut)=>{const t=clone(base);mut(t);cases.push(run(id,t,expect));};
 add("duplicate_species","REJECTED",t=>{t[1]=clone(t[0]);});
 add("five_members","REJECTED",t=>{t.pop();});
 add("seven_members","REJECTED",t=>{t.push(clone(t[0]));});
 add("wrong_ability","REJECTED",t=>{t[0].ability="Drizzle";});
 add("wrong_move","REJECTED",t=>{t[0].moves[1]="Spore";});
 add("five_moves","REJECTED",t=>{t[0].moves.push("U-turn");});
 add("sp_axis_33_total_66","REJECTED",t=>{t[0].evs.atk=33;t[0].evs.hp=1;});
 add("sp_total_67","REJECTED",t=>{t[0].evs.hp=3;});
 add("sp_total_65","ACCEPTED",t=>{t[0].evs.hp=1;});
 add("iv_30","REJECTED",t=>{t[0].ivs.spe=30;});
 add("zero_sp_hardy","ACCEPTED",t=>{t[0].evs={hp:0,atk:0,def:0,spa:0,spd:0,spe:0};});
 add("zero_sp_serious","REJECTED",t=>{t[0].evs={hp:0,atk:0,def:0,spa:0,spd:0,spe:0};t[0].nature="Serious";});
 const item=clone(base);item[0].item="Sitrus Berry";const itemControl=run("single_item_control",item,"ACCEPTED");cases.push(itemControl);if(itemControl.match){item[1].item="Sitrus Berry";cases.push(run("duplicate_item",item,"REJECTED"));}
 return {status:cases.every(c=>c.match)&&cases.length===15?"PASS_LIMITED_SIMULATOR_REGRESSION":"BLOCKED_OR_DISCREPANCY",cases};
}
function exportDex(Dex,TeamValidator){
 const format=Dex.formats.get("gen9championsvgc2026regmc");
 if(!format.exists||format.mod!=="champions"||format.gameType!=="doubles")throw Error("format mismatch");
 const dex=Dex.forFormat(format),rt=dex.formats.getRuleTable(format);
 if(dex.currentMod!=="champions"||rt.evLimit!==66||rt.pickedTeamSize!==4)throw Error("rule mismatch");
 const errors=[];const plain=(x,fields)=>Object.fromEntries(fields.map(k=>[k,x[k]??null]));
 const species=dex.species.all().filter(x=>x.exists).map(s=>{const row=plain(s,["id","name","num","baseSpecies","forme","types","baseStats","abilities","gender","genderRatio","isNonstandard","battleOnly","requiredItem","requiredItems","requiredAbility","requiredMove","isMega","changesFrom","prevo","tags","isCosmeticForme"]);try{const d=dex.species.getLearnsetData(s.id);row.directLearnset=plain(d,["learnset","eventData","eventOnly","encounters"]);row.fullLearnset=dex.species.getFullLearnset(s.id).map(x=>({speciesId:x.species.id,learnset:x.learnset,eventData:x.eventData??null,eventOnly:x.eventOnly??null}));}catch(e){row.fullLearnset=null;errors.push({id:s.id,stage:"learnset",error:String(e)});}return row;});
 const maps={moves:dex.moves.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard","type","category","basePower","accuracy","priority","pp","target"])),items:dex.items.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard","megaStone","megaEvolves","itemUser","onTakeItem"] .filter(k=>k!=="onTakeItem"))),abilities:dex.abilities.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard"])),natures:dex.natures.all().filter(x=>x.exists).map(x=>plain(x,["id","name","plus","minus"]))};
 return {format:plain(format,["id","name","mod","gameType","ruleset","banlist","unbanlist"]),rules:plain(rt,["minTeamSize","maxTeamSize","pickedTeamSize","adjustLevel","maxLevel","evLimit","maxMoveCount"]),resolvedRules:[...rt.entries()],species,...maps,errors,validation:runCases(TeamValidator,format)};
}
const root=fs.realpathSync(process.argv[2]);const dest=path.resolve(process.argv[3]);const git=(...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();if(git('rev-parse','HEAD')!=='7f7b03182d1df61c88ad360cf1d1639451b97b42')throw Error('unexpected commit');if(git('status','--porcelain','--untracked-files=no'))throw Error('tracked tree modified');if(fs.existsSync(dest))throw Error('output already exists');const parent=fs.realpathSync(path.dirname(dest));const rel=path.relative(root,path.join(parent,path.basename(dest)));if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'))throw Error('output must be outside source repo');const require=createRequire(path.join(root,'package.json'));const sim=require(path.join(root,'dist/sim'));const out=exportDex(sim.Dex,sim.TeamValidator);const sha=b=>crypto.createHash('sha256').update(b).digest('hex');const summary={schema:'v11-dex-export-v1',commit:git('rev-parse','HEAD'),node:process.version,buildProvenance:'Caller must separately attest clean rebuild from pinned source; HEAD does not prove dist freshness',format:out.format,rules:out.rules,counts:Object.fromEntries(['species','moves','items','abilities','natures'].map(k=>[k,out[k].length])),learnsetErrors:out.errors.length,validationStatus:out.validation.status,validation:out.validation.cases.map(({id,expected,decision,match,mutated,problems,error})=>({id,expected,decision,match,mutated,problems,error}))};fs.mkdirSync(dest,{mode:0o700});const write=(name,x)=>{const b=Buffer.from(JSON.stringify(x,null,2)+'\n');fs.writeFileSync(path.join(dest,name),b,{flag:'wx',mode:0o600});return sha(b);};const fullSha=write('v11-effective-master-v1.json',out);summary.masterSha256=fullSha;write('v11-effective-master-summary-v1.json',summary);console.log(JSON.stringify(summary,null,2));process.exitCode=out.errors.length||out.validation.status!=='PASS_LIMITED_SIMULATOR_REGRESSION'?1:0;
