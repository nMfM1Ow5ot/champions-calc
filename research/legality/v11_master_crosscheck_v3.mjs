// Read-only independent comparison of the local v3 projections with the pinned live Dex.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
const root = fs.realpathSync(process.argv[2]);
const output = process.argv[3];
const expectedCommit = '7f7b03182d1df61c88ad360cf1d1639451b97b42';
const git = (...args) => execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
assert.equal(git('rev-parse','HEAD'),expectedCommit);
assert.equal(git('status','--porcelain','--untracked-files=no'),'');
const bytes = fs.readFileSync(path.join(output,'v11-effective-master-v3.json'));
const master = JSON.parse(bytes);
const summary = JSON.parse(fs.readFileSync(path.join(output,'v11-effective-master-summary-v3.json')));
assert.equal(createHash('sha256').update(bytes).digest('hex'),summary.masterSha256);
const {Dex, TeamValidator} = createRequire(path.join(root,'package.json'))(path.join(root,'dist/sim'));
const validator = new TeamValidator('gen9championsvgc2026regmc');
const dex = Dex.forFormat(validator.format);
const direct = {absentTableKey:0, presentWithoutMap:0, presentEmptyMap:0, presentWithMoves:0};
const absentDespiteExists = [];
const keysWithoutMoveMap = [];
const inherited = [];
const empty = [];
const excludedTypeReferences = [];
const speciesIds = new Set(master.species.map(s => s.id));
const distinctPairs = new Set();
const stats = ['atk','def','hp','spa','spd','spe'];
function checkSpecies(name) {
  assert.ok(dex.species.get(name).exists && speciesIds.has(dex.species.get(name).id), name);
}
for (const s of master.species) {
  const live = dex.species.get(s.id);
  for (const field of ['types','baseStats','abilities','isNonstandard','battleOnly','requiredItems','changesFrom','requiredAbility','requiredMove']) {
    assert.deepEqual(s[field], live[field] ?? null);
  }
  assert.deepEqual(Object.keys(s.baseStats).sort(),stats);
  assert.ok(Object.values(s.baseStats).every(Number.isFinite));
  for (const type of s.types) {
    if (dex.types.get(type).exists) continue;
    const reason = validator.checkSpecies({name:s.name, species:s.name}, live, live, {});
    assert.ok(s.id === 'missingno' && s.isNonstandard === 'Custom' && type === 'Bird' && reason, s.id + '/' + type);
    excludedTypeReferences.push({species:s.id,type,category:s.isNonstandard,reason});
  }
  for (const name of [s.baseSpecies, s.prevo, s.changesFrom].filter(Boolean)) checkSpecies(name);
  const dl = dex.species.getLearnsetData(s.id);
  for (const key of Object.keys(s.directLearnset)) assert.deepEqual(s.directLearnset[key], dl[key] ?? null);
  if (!Object.hasOwn(dex.data.Learnsets,s.id)) {
    direct.absentTableKey++;
    if (dl.exists) absentDespiteExists.push(s.id);
  } else if (!dl.learnset) {
    direct.presentWithoutMap++;
    keysWithoutMoveMap.push(s.id);
  }
  else if (Object.keys(dl.learnset).length === 0) direct.presentEmptyMap++;
  else direct.presentWithMoves++;
  const chain = dex.species.getFullLearnset(s.id);
  assert.equal(s.fullLearnset.length,chain.length);
  if (!chain.length) empty.push({id:s.id,category:s.isNonstandard,reason:s.componentRuleProblem});
  if (chain.some(l => l.species.id !== s.id)) inherited.push(s.id);
  for (const [i, link] of chain.entries()) {
    const exported = s.fullLearnset[i];
    assert.equal(link.species.id,exported.speciesId);
    for (const field of ['learnset','eventData','eventOnly','encounters']) assert.deepEqual(exported[field],link[field] ?? null);
    for (const key of Object.keys(link.learnset)) distinctPairs.add(link.species.id + '/' + key);
  }
}
for (const item of master.items) {
  if (item.forcedForme) checkSpecies(item.forcedForme);
  for (const name of item.itemUser ?? []) checkSpecies(name);
}
const rt = validator.ruleTable;
assert.deepEqual([...rt.entries()],master.resolvedRules);
assert.deepEqual([...rt.valueRules],master.valueRules);
assert.deepEqual([...rt.complexBans.entries()],master.complexBans);
assert.deepEqual([...rt.complexTeamBans.entries()],master.complexTeamBans);
assert.ok(master.moves.filter(m => m.placeholderFor).every(m => m.componentRuleProblem));
assert.ok(empty.every(s => s.category && s.reason));
const sampleIDs = ['incineroar','rotomwash','gardevoirmega'];
console.log(JSON.stringify({commit:expectedCommit, direct, excludedTypeReferences, absentButGetterReportsExists:absentDespiteExists.length,
  absentKeysReturningExists:absentDespiteExists, keysWithoutMoveMap,
  uniqueLearnsetOwnerMovePairs:distinctPairs.size, inherited:inherited.length, empty,
  examples:Object.fromEntries(sampleIDs.map(id => [id,dex.species.getFullLearnset(id).map(l => l.species.id)])),
  directAndFullProjectedFieldsCompared:true, baseStatsTypesAndAbilitySlotsCompared:true,
  explicitTableKeyAndGetterCanDisagree:true, itemUsersAndForcedFormsResolved:true},null,2));
