// Research only. Fixed source runtime, output outside repository; no implicit legality from Dex membership.
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';import {execFileSync} from 'node:child_process';import {createRequire} from 'node:module';
function verdict(raw,expected,reason,before,after){
 if(raw!==null&&(!Array.isArray(raw)||raw.length===0||!raw.every(x=>typeof x==="string"&&x.trim())))throw Error("unexpected validator result");
 const decision=raw===null?"ACCEPTED":"REJECTED";
 const canonical=x=>JSON.stringify(x.map(s=>({species:s.species,ability:s.ability,item:s.item,moves:s.moves,nature:s.nature,evs:s.evs,ivs:s.ivs})));
 const materialMutation=canonical(before)!==canonical(after);
 const reasonMatched=decision==="REJECTED"&&typeof reason==="string"&&raw.some(x=>x.includes(reason));
 return {decision,reasonMatched,materialMutation,match:decision===expected&&(expected==="ACCEPTED"?!materialMutation:reasonMatched)};
}
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
 const run=(id,team,expect,reason=null)=>{try{const before=clone(team),after=clone(team),raw=new TeamValidator(format).validateTeam(after);return {id,expected:expect,expectedReason:reason,...verdict(raw,expect,reason,before,after),problems:raw??[],input:before,normalized:after};}catch(e){return {id,expected:expect,decision:"ERROR",match:false,error:String(e)}}};
 const positive=run("positive_control",base,"ACCEPTED");if(!positive.match)return {status:"BLOCKED_POSITIVE_CONTROL",cases:[positive]};
 const cases=[positive];
 const add=(id,expect,mut,reason=null)=>{const t=clone(base);mut(t);cases.push(run(id,t,expect,reason));};
 add("duplicate_species","REJECTED",t=>{t[1]=clone(t[0]);},"by Species Clause");
 add("five_members","REJECTED",t=>{t.pop();},"You must bring at least 6");
 add("seven_members","REJECTED",t=>{t.push(clone(t[0]));},"You may only bring up to 6");
 add("wrong_ability","REJECTED",t=>{t[0].ability="Drizzle";},"can\'t have Drizzle");
 add("wrong_move","REJECTED",t=>{t[0].moves[1]="Spore";},"can\'t learn Spore");
 add("five_moves","REJECTED",t=>{t[0].moves.push("U-turn");},"more than the limit of 4");
 add("sp_axis_33_total_66","REJECTED",t=>{t[0].evs.atk=33;t[0].evs.hp=1;},"more than 32 Stat Points");
 add("sp_total_67","REJECTED",t=>{t[0].evs.hp=3;},"limit of 66");
 add("sp_total_65","ACCEPTED",t=>{t[0].evs.hp=1;});
 add("iv_30","REJECTED",t=>{t[0].ivs.spe=30;},"requires all IVs to be 31");
 add("zero_sp_hardy","ACCEPTED",t=>{t[0].evs={hp:0,atk:0,def:0,spa:0,spd:0,spe:0};});
 add("zero_sp_serious","REJECTED",t=>{t[0].evs={hp:0,atk:0,def:0,spa:0,spd:0,spe:0};t[0].nature="Serious";},"has exactly 0 Stat Points");
 const item=clone(base);item[0].item="Sitrus Berry";const itemControl=run("single_item_control",item,"ACCEPTED");cases.push(itemControl);if(itemControl.match){item[1].item="Sitrus Berry";cases.push(run("duplicate_item",item,"REJECTED","by Item Clause"));}
 add("one_move","ACCEPTED",t=>{t[0].moves=["Protect"];});
 add("zero_moves","REJECTED",t=>{t[0].moves=[];},"has no moves");
 return {status:cases.every(c=>c.match)&&cases.length===17?"PASS_LIMITED_SIMULATOR_REGRESSION":"BLOCKED_OR_DISCREPANCY",cases};
}

function exportDex(Dex,TeamValidator){
 const format=Dex.formats.get("gen9championsvgc2026regmc");
 if(!format.exists||format.mod!=="champions"||format.gameType!=="doubles")throw Error("format mismatch");
 const dex=Dex.forFormat(format),rt=dex.formats.getRuleTable(format);
 if(dex.currentMod!=="champions"||rt.evLimit!==66||rt.pickedTeamSize!==4||rt.minTeamSize!==6||rt.maxTeamSize!==6||rt.maxMoveCount!==4||rt.adjustLevel!==50||!rt.has("speciesclause")||Number(rt.valueRules.get("itemclause"))!==1)throw Error("rule mismatch");
 const errors=[];const coverage=[];const plain=(x,fields)=>Object.fromEntries(fields.map(k=>[k,x[k]??null]));
 const species=dex.species.all().filter(x=>x.exists).map(s=>{const row=plain(s,["id","name","num","baseSpecies","forme","types","baseStats","abilities","gender","genderRatio","isNonstandard","battleOnly","requiredItem","requiredItems","requiredAbility","requiredMove","isMega","changesFrom","prevo","tags","isCosmeticForme","unreleasedHidden","maleOnlyHidden","otherFormes","cosmeticFormes","baseForme","formeOrder","canGigantamax"]);try{const d=dex.species.getLearnsetData(s.id);row.directLearnset=plain(d,["exists","learnset","eventData","eventOnly","encounters"]);row.fullLearnset=dex.species.getFullLearnset(s.id).map(x=>({speciesId:x.species.id,learnset:x.learnset,eventData:x.eventData??null,eventOnly:x.eventOnly??null,encounters:x.encounters??null}));row.learnsetStatus=row.fullLearnset.length?"PRESENT":"EMPTY_OR_NOT_APPLICABLE";}catch(e){row.fullLearnset=null;row.learnsetStatus="ERROR";errors.push({id:s.id,stage:"learnset",error:String(e)});}return row;});
 const maps={moves:dex.moves.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard","type","category","basePower","accuracy","priority","pp","target"])),items:dex.items.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard","megaStone","megaEvolves","itemUser","forcedForme","requiredItem","isPokeball"])),abilities:dex.abilities.all().filter(x=>x.exists).map(x=>plain(x,["id","name","isNonstandard"])),natures:dex.natures.all().filter(x=>x.exists).map(x=>plain(x,["id","name","plus","minus"]))};
 for(const [kind,rows] of Object.entries({species,...maps})){const ids=new Set();if(!rows.length)errors.push({stage:"empty_table",kind});for(const row of rows){if(typeof row.id!=="string"||!row.id||ids.has(row.id))errors.push({stage:"invalid_or_duplicate_id",kind,id:row.id});ids.add(row.id);}coverage.push({kind,count:rows.length,unique:ids.size});}
 const asMap=rows=>new Set(rows.map(x=>x.id));const id=x=>String(x??"").toLowerCase().replace(/[^a-z0-9]/g,"");const moveIds=asMap(maps.moves),abilityIds=asMap(maps.abilities),speciesIds=asMap(species),itemIds=asMap(maps.items);const referenceIssues=[];
 for(const s of species){for(const name of Object.values(s.abilities??{}))if(!abilityIds.has(id(name)))referenceIssues.push({species:s.id,kind:"ability",name});for(const l of s.fullLearnset??[]){if(!speciesIds.has(l.speciesId))referenceIssues.push({species:s.id,kind:"learnset_parent",name:l.speciesId});for(const m of Object.keys(l.learnset??{}))if(!moveIds.has(m))referenceIssues.push({species:s.id,kind:"move",name:m});}for(const name of s.requiredItems??[])if(!itemIds.has(id(name)))referenceIssues.push({species:s.id,kind:"required_item",name});}
 const encode=(x)=>JSON.parse(JSON.stringify(x,(_,v)=>v===Infinity?{$number:"Infinity"}:v===-Infinity?{$number:"-Infinity"}:v));
 return {scope:"DEX_UNIVERSE_NOT_REGISTRATION_ROSTER",coverage,referenceIssues,format:plain(format,["id","name","mod","gameType","ruleset","banlist","unbanlist"]),rules:plain(rt,["minTeamSize","maxTeamSize","pickedTeamSize","adjustLevel","maxLevel","evLimit","maxMoveCount"]),resolvedRules:[...rt.entries()],valueRules:[...rt.valueRules.entries()],complexBans:encode([...rt.complexBans.entries()]),complexTeamBans:encode([...rt.complexTeamBans.entries()]),ruleCallbacksRetainedInPinnedSource:true,species,...maps,errors,validation:runCases(TeamValidator,format)};
}

function selfTest(){const b=[{species:"A",ability:"X",item:"",moves:["P"],nature:"Hardy",evs:{hp:1},ivs:{hp:31}}];const test=(r,e,s,a=b)=>verdict(r,e,s,b,a).match;const throws=f=>{try{f();return false}catch{return true}};return {accept:test(null,"ACCEPTED",null),unrelated:!test(["other"],"REJECTED","target"),expected:test(["target"],"REJECTED","target"),acceptMutation:!test(null,"ACCEPTED",null,[{...b[0],species:"B"}]),emptyResult:throws(()=>test([],"ACCEPTED",null)),malformed:throws(()=>test([""],"REJECTED","target")),rejectAll:runCases(class{validateTeam(){return ["other"]}},{}).status==="BLOCKED_POSITIVE_CONTROL",acceptAll:runCases(class{validateTeam(){return null}},{}).status==="BLOCKED_OR_DISCREPANCY",throwAll:runCases(class{validateTeam(){throw Error("test")}},{}).status==="BLOCKED_POSITIVE_CONTROL",count:runCases(class{validateTeam(){return null}},{}).cases.length===17};}
if(process.argv.includes('--self-test')){const t=selfTest();console.log(JSON.stringify(t,null,2));process.exitCode=Object.values(t).every(Boolean)?0:1;}else{
const root=fs.realpathSync(process.argv[2]),dest=path.resolve(process.argv[3]);const git=(...args)=>execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();const expected='7f7b03182d1df61c88ad360cf1d1639451b97b42';if(git('rev-parse','HEAD')!==expected)throw Error('unexpected commit');if(git('status','--porcelain','--untracked-files=no'))throw Error('tracked tree modified');if(fs.existsSync(dest))throw Error('output already exists');const parent=fs.realpathSync(path.dirname(dest));const rel=path.relative(root,path.join(parent,path.basename(dest)));if(!rel||(!rel.startsWith('..'+path.sep)&&rel!=='..'))throw Error('output must be outside source repo');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');function manifest(dir){const out=[];function walk(p){for(const e of fs.readdirSync(p,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name,'en'))){const f=path.join(p,e.name);if(e.isSymbolicLink())throw Error('symlink in compiled tree: '+path.relative(root,f));if(e.isDirectory())walk(f);else if(e.isFile())out.push([path.relative(root,f),sha(fs.readFileSync(f))]);else throw Error('unsupported entry');}}walk(dir);if(!out.length)throw Error('empty dist');return out;}
const dist=path.join(root,'dist');const before=manifest(dist);const require=createRequire(path.join(root,'package.json'));const sim=require(path.join(root,'dist/sim'));const out=exportDex(sim.Dex,sim.TeamValidator);const after=manifest(dist);if(JSON.stringify(before)!==JSON.stringify(after)||git('rev-parse','HEAD')!==expected||git('status','--porcelain','--untracked-files=no'))throw Error('source/runtime changed during run');
const summary={schema:'v11-dex-export-v2',commit:expected,node:process.version,compiledFiles:before.length,compiledManifestSha256:sha(Buffer.from(JSON.stringify(before))),buildProvenance:'UNVERIFIED_FRESHNESS; hash identifies observed dist, not proof of rebuild from source; require separate clean build record',format:out.format,rules:out.rules,counts:Object.fromEntries(['species','moves','items','abilities','natures'].map(k=>[k,out[k].length])),learnsetErrors:out.errors.length,referenceIssues:out.referenceIssues.length,validationStatus:out.validation.status,validation:out.validation.cases.map(({id,expected,expectedReason,decision,match,materialMutation,reasonMatched,problems,error})=>({id,expected,expectedReason,decision,match,materialMutation,reasonMatched,problems,error})),admission:'NOT_APPROVED'};fs.mkdirSync(dest,{mode:0o700});const write=(name,x)=>{const b=Buffer.from(JSON.stringify(x,null,2)+'\n');fs.writeFileSync(path.join(dest,name),b,{flag:'wx',mode:0o600});return sha(b);};summary.masterSha256=write('v11-effective-master-v2.json',out);summary.manifestFileSha256=write('v11-dist-manifest-v2.json',before);write('v11-effective-master-summary-v2.json',summary);console.log(JSON.stringify(summary,null,2));process.exitCode=out.errors.length||out.referenceIssues.length||out.validation.status!=='PASS_LIMITED_SIMULATOR_REGRESSION'?1:0;}
