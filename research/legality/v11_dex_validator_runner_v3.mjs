// Research CLI: node v11_dex_validator_runner_v3.mjs SHOWDOWN_ROOT NEW_OUTPUT
// The immutable sibling v2 CLI performs the original extraction and its 17 controls.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const commit = '7f7b03182d1df61c88ad360cf1d1639451b97b42';
const originalHash = '8ff79c8c8f30b88c65157b00a0a2d8855a2d88ccd9edaa58b6ab56b8cbeb8111';
const formatID = 'gen9championsvgc2026regmc';
const sha = data => createHash('sha256').update(data).digest('hex');
const json = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const write = (dir, name, data) => fs.writeFileSync(path.join(dir, name), JSON.stringify(data, null, 2) + '\n', {flag:'wx', mode:0o600});
const id = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');
const histogram = list => Object.fromEntries([...new Set(list)].sort().map(key => [key, list.filter(x => x === key).length]));

export function moveKeys(rows, data, dexMoves) {
  const byName = new Map(rows.map(row => [row.name, row]));
  assert.equal(byName.size, rows.length, 'ambiguous exported move name');
  const mapped = [];
  for (const [key, entry] of Object.entries(data)) {
    const move = dexMoves.getByID(key);
    if (!move.exists) continue;
    const row = byName.get(move.name);
    assert.ok(row && row.id === move.id && row.type === move.type, 'Dex move/export mismatch: ' + key);
    byName.delete(move.name);
    if (key !== move.id) assert.equal(id(entry.placeholderFor || ''), move.id, 'unexplained ID collision: ' + key);
    mapped.push({...row, id:key, simulatorId:move.id, placeholderFor:entry.placeholderFor ?? null});
  }
  assert.equal(byName.size, 0, 'unmapped v2 move');
  return mapped;
}

export function classifyReference(issue, owner) {
  if (issue.kind === 'ability' && issue.name === '' && owner?.id === 'missingno' &&
      owner.isNonstandard === 'Custom' && owner.componentRuleProblem) return 'excludedEmptyAbility';
  return 'unresolved';
}

function distManifest(root) {
  const rows = [];
  function walk(rel) {
    for (const e of fs.readdirSync(path.join(root, rel), {withFileTypes:true}).sort((a,b) => a.name.localeCompare(b.name, 'en'))) {
      const file = path.join(rel, e.name);
      if (e.isDirectory()) walk(file);
      else {
        assert.ok(e.isFile(), 'unsupported dist entry: ' + file);
        rows.push([file, sha(fs.readFileSync(path.join(root, file)))]);
      }
    }
  }
  walk('dist');
  return rows;
}

function explicitModFields(root, require) {
  // Capture before Dex.loadData merges and deletes inheritance markers in these modules.
  const out = {};
  const dir = path.join(root, 'dist/data/mods/champions');
  for (const file of fs.readdirSync(dir).filter(name => name.endsWith('.js')).sort()) {
    for (const [table, entries] of Object.entries(require(path.join(dir, file)))) {
      out[table] = Object.fromEntries(Object.entries(entries).map(([key, row]) => [key,
        row === null ? {mode:'remove'} : {mode:row.inherit ? 'merge' : 'define', keys:Object.keys(row).sort()}]));
    }
  }
  return out;
}

function enrich(master, dex, validator) {
  master.moves = moveKeys(master.moves, dex.data.Moves, dex.moves);
  const methods = {moves:'checkMove', items:'checkItem', abilities:'checkAbility', natures:'checkNature'};
  for (const [table, method] of Object.entries(methods)) {
    for (const row of master[table]) {
      const obj = dex[table].get(row.id);
      row.componentRuleProblem = validator[method]({name:'Probe'}, obj, {}) ?? null;
    }
  }
  const species = new Map(master.species.map(s => [s.id, s]));
  const moveIds = new Set(master.moves.map(row => row.id));
  const itemIds = new Set(master.items.map(row => row.id));
  const abilityIds = new Set(master.abilities.map(row => row.id));
  const problems = [];
  let sourceEntries = 0;
  let inheritedChains = 0;
  const stones = [];
  for (const s of master.species) {
    const live = dex.species.get(s.id);
    s.componentRuleProblem = validator.checkSpecies({name:s.name, species:s.name}, live, live, {}) ?? null;
    if (!s.fullLearnset) { problems.push({species:s.id, kind:'unavailableLearnset'}); continue; }
    s.learnsetStatus = s.fullLearnset.length ? 'PRESENT' : 'RETURNED_EMPTY';
    if (s.fullLearnset.some(link => link.speciesId !== s.id)) inheritedChains++;
    for (const link of s.fullLearnset) {
      if (!species.has(link.speciesId)) problems.push({species:s.id, kind:'learnsetParent', id:link.speciesId});
      for (const [move, sources] of Object.entries(link.learnset)) {
        sourceEntries++;
        if (!moveIds.has(move) || !Array.isArray(sources) || !sources.length || !sources.every(v => typeof v === 'string' && v.trim())) {
          problems.push({species:s.id, kind:'moveOrSource', move});
        }
      }
    }
    if (s.requiredMove && !moveIds.has(id(s.requiredMove))) problems.push({species:s.id, kind:'requiredMove'});
    if (s.requiredAbility && !abilityIds.has(id(s.requiredAbility))) problems.push({species:s.id, kind:'requiredAbility'});
    for (const name of new Set([s.requiredItem, ...(s.requiredItems ?? [])].filter(Boolean))) {
      if (!itemIds.has(id(name))) problems.push({species:s.id, kind:'requiredItem', name});
    }
    for (const name of [s.battleOnly ?? []].flat()) {
      if (!species.has(id(name))) problems.push({species:s.id, kind:'battleOnly', name});
    }
  }
  for (const item of master.items) {
    for (const [base, form] of Object.entries(item.megaStone ?? {})) {
      const target = species.get(id(form));
      stones.push({item:item.id, from:id(base), to:id(form)});
      if (!species.has(id(base)) || !target?.isMega || !target.requiredItems?.includes(item.name)) {
        problems.push({kind:'megaStone', item:item.id, base, form});
      }
    }
  }
  const references = master.referenceIssues.map(issue => ({...issue, classification:classifyReference(issue, species.get(issue.species))}));
  // A collision is explained only when the actual retained placeholder records account for every v2 error.
  const collisions = master.moves.filter(r => r.id !== r.simulatorId);
  const expectedDiagnostics = collisions.map(r => ({stage:'invalid_or_duplicate_id', kind:'moves', id:r.simulatorId}));
  assert.deepEqual(master.errors, expectedDiagnostics, 'unexpected v2 extraction diagnostic');
  master.v2Diagnostics = {errors:master.errors, references};
  master.errors = problems;
  master.referenceIssues = references.filter(r => r.classification === 'unresolved');
  master.megaStoneLinks = stones;
  master.coverage = ['species','moves','items','abilities','natures'].map(kind => {
    const rows = master[kind];
    const unique = new Set(rows.map(r => r.id)).size;
    assert.ok(rows.length && unique === rows.length && rows.every(r => r.id), kind + ' primary keys');
    return {kind, count:rows.length, unique, componentCheckClear:rows.filter(r => !r.componentRuleProblem).length,
      nonstandard:histogram(rows.map(r => r.isNonstandard ?? 'standard'))};
  });
  const ruleCallbacks = {};
  for (const [key] of master.resolvedRules) {
    if ('+-*!'.includes(key[0])) continue;
    const rule = dex.formats.get(key);
    const names = Object.keys(rule).filter(k => typeof rule[k] === 'function');
    if (names.length) ruleCallbacks[key] = names;
  }
  const rows = master.species;
  return {coverage:master.coverage, collisions:collisions.length, references, problems, ruleCallbacks,
    sourceEntries, inheritedChains, directWithoutMoveMap:rows.filter(s => s.directLearnset?.learnset == null).length,
    fullLearnsets:histogram(rows.map(s => s.learnsetStatus)), battleOnly:rows.filter(s => s.battleOnly).length,
    screenedOutOfBattle:rows.filter(s => !s.battleOnly && !s.componentRuleProblem).length,
    megaStones:master.items.filter(i => i.megaStone).length, megaStoneLinks:stones.length,
    complexBans:master.complexBans.length, complexTeamBans:master.complexTeamBans.length};
}

function main() {
  const root = fs.realpathSync(process.argv[2]);
  const dest = path.join(fs.realpathSync(path.dirname(path.resolve(process.argv[3]))), path.basename(process.argv[3]));
  const rel = path.relative(root, dest);
  assert.ok(rel === '..' || rel.startsWith('..' + path.sep), 'output must be outside source');
  const git = (...args) => execFileSync('git', ['-C', root, ...args], {encoding:'utf8'}).trim();
  function checkSource() {
    assert.equal(git('rev-parse', 'HEAD'), commit);
    assert.equal(git('status', '--porcelain', '--untracked-files=no'), '');
  }
  checkSource();
  const runner = fileURLToPath(new URL('./v11_dex_validator_runner_v2.mjs', import.meta.url));
  assert.equal(sha(fs.readFileSync(runner)), originalHash, 'unexpected v2 bytes');
  fs.mkdirSync(dest, {mode:0o700});
  const original = path.join(dest, 'original-v2');
  const before = distManifest(root);
  const run = spawnSync(process.execPath, [runner, root, original], {encoding:'utf8'});
  if (run.error || ![0,1].includes(run.status) || run.stderr) throw Error('v2 failed: ' + (run.error ?? run.stderr ?? run.status));
  const summary = json(path.join(original, 'v11-effective-master-summary-v2.json'));
  assert.equal(summary.validationStatus, 'PASS_LIMITED_SIMULATOR_REGRESSION');
  assert.deepEqual(json(path.join(original,'v11-dist-manifest-v2.json')), before);
  const raw = fs.readFileSync(path.join(original, 'v11-effective-master-v2.json'));
  assert.equal(sha(raw), summary.masterSha256);
  const master = JSON.parse(raw);
  const require = createRequire(path.join(root, 'package.json'));
  master.explicitModFields = explicitModFields(root, require);
  const {Dex, TeamValidator} = require(path.join(root, 'dist/sim'));
  const dex = Dex.forFormat(formatID);
  assert.equal(dex.currentMod, 'champions');
  const audit = enrich(master, dex, new TeamValidator(formatID));
  master.ruleCallbacks = audit.ruleCallbacks;
  master.schema = 'v11-dex-export-v3';
  const accepted = !master.errors.length && !master.referenceIssues.length;
  checkSource();
  assert.deepEqual(distManifest(root), before);
  write(dest, 'v11-effective-master-v3.json', master);
  write(dest, 'v11-dist-manifest-v3.json', before);
  write(dest, 'v11-effective-master-summary-v3.json', {schema:master.schema, commit, format:formatID, originalV2Exit:run.status,
    originalMasterSha256:summary.masterSha256, masterSha256:sha(fs.readFileSync(path.join(dest, 'v11-effective-master-v3.json'))),
    distManifestFileSha256:summary.manifestFileSha256, original17:summary.validationStatus, ...audit, integrityPassed:accepted});
  process.exitCode = accepted ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
