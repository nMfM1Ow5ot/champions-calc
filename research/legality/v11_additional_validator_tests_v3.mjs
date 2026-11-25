// node v11_additional_validator_tests_v3.mjs SHOWDOWN_ROOT V2_OUTPUT NEW_RESULTS_JSON
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import {isDeepStrictEqual} from 'node:util';

const [rootArg, v2, output] = process.argv.slice(2);
const root = fs.realpathSync(rootArg);
const commit = '7f7b03182d1df61c88ad360cf1d1639451b97b42';
const format = 'gen9championsvgc2026regmc';
const git = (...args) => execFileSync('git',['-C',root,...args],{encoding:'utf8'}).trim();
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(git('rev-parse','HEAD'), commit);
assert.equal(git('status','--porcelain','--untracked-files=no'), '');
const destParent = fs.realpathSync(path.dirname(path.resolve(output)));
const rel = path.relative(root,path.join(destParent,path.basename(output)));
assert.ok(rel === '..' || rel.startsWith('..' + path.sep));
const summary = JSON.parse(fs.readFileSync(path.join(v2,'v11-effective-master-summary-v2.json')));
const bytes = fs.readFileSync(path.join(v2,'v11-effective-master-v2.json'));
assert.equal(summary.commit, commit);
assert.equal(summary.format.id, format);
assert.equal(digest(bytes), summary.masterSha256);
const original = JSON.parse(bytes).validation.cases;
assert.equal(original.length, 17);
assert.ok(original.every(c => c.match));
const {TeamValidator} = createRequire(path.join(root,'package.json'))(path.join(root,'dist/sim'));
const base = original.find(c => c.id === 'positive_control').normalized;
const cases = [];
const controls = new Map();
function changes(a, b, at = '') {
  if (isDeepStrictEqual(a,b)) return [];
  if (a && b && typeof a === 'object' && typeof b === 'object' && Array.isArray(a) === Array.isArray(b)) {
    return [...new Set([...Object.keys(a),...Object.keys(b)])].flatMap(k => changes(a[k],b[k],at + '/' + k));
  }
  return [{path:at, ...(a === undefined ? {} : {before:a}), ...(b === undefined ? {} : {after:b})}];
}

// Accepted children use their parent's input so a one-field edit can exercise a normalizing form.
function check(id, parent, edit, reasons = [], normalize = () => {}, api = 'validateTeam') {
  if (parent && !controls.has(parent)) {
    cases.push({id,parent,status:'NOT_RUN_CONTROL',match:false});
    return;
  }
  const input = structuredClone(parent ? controls.get(parent) : base);
  edit(input);
  const actual = structuredClone(input);
  const record = {id, parent, api, expected:reasons.length ? 'REJECTED' : 'ACCEPTED', expectedReasons:reasons,
    inputChangesFromBase:changes(base,input)};
  try {
    const validator = new TeamValidator(format);
    const raw = api === 'validateSet' ? validator.validateSet(actual[0], {}) : validator.validateTeam(actual);
    assert.ok(raw === null || (Array.isArray(raw) && raw.length && raw.every(s => typeof s === 'string' && s.trim())));
    const expectedAfter = structuredClone(input);
    normalize(expectedAfter);
    const normalizedAsExpected = raw === null ? isDeepStrictEqual(actual,expectedAfter) : null;
    const reasonMatches = reasons.map(reason => raw?.some(problem => problem.includes(reason)) ?? false);
    record.decision = raw === null ? 'ACCEPTED' : 'REJECTED';
    Object.assign(record,{problems:raw ?? [], reasonMatches, normalizedAsExpected, mutations:changes(input,actual)});
    record.match = record.decision === record.expected && (raw === null ? normalizedAsExpected : reasonMatches.every(Boolean));
    if (raw === null && !normalizedAsExpected) record.unexpected = changes(expectedAfter,actual);
    if (raw === null && record.match) controls.set(id,input);
  } catch (err) {
    Object.assign(record,{decision:'ERROR', error:String(err), match:false});
  }
  cases.push(record);
}
const noop = () => {};
const baseline = 'six_itemless';
check(baseline, null, noop);
check('gardevoir_stone',baseline,t => {t[4].item = 'Gardevoirite';});
check('two_distinct_mega_stones','gardevoir_stone',t => {t[5].item = 'Gengarite';});
check('stone_on_other_species',baseline,t => {t[0].item = 'Gardevoirite';});
check('mega_ability_without_stone',baseline,t => {t[4].ability = 'Pixilate';}, ["can't have Pixilate"]);
check('mega_ability_with_stone','gardevoir_stone',t => {t[4].ability = 'Pixilate';}, [], t => {t[4].ability = 'Synchronize';});
check('mega_input_with_stone','gardevoir_stone',t => {t[4].species = 'Gardevoir-Mega';}, [], t => {t[4].species = 'Gardevoir';});
check('mega_input_and_ability','mega_input_with_stone',t => {t[4].ability = 'Pixilate';}, [], t => {
  t[4].species = 'Gardevoir'; t[4].ability = 'Synchronize';
});
check('mega_input_wrong_stone','mega_input_with_stone',t => {t[4].item = 'Gengarite';}, ['transforms in-battle with Gardevoirite']);
function appliance(set,species) {
  return {...set,name:'Rotom',species,ability:'Levitate',gender:'N',moves:['Protect']};
}
check('wash_control',baseline,t => {t[2] = appliance(t[2],'Rotom-Wash');});
check('heat_control',baseline,t => {t[3] = appliance(t[3],'Rotom-Heat');});
check('wash_and_heat','wash_control',t => {t[3] = appliance(t[3],'Rotom-Heat');}, ['by Species Clause']);
check('negative_sp',baseline,t => {t[0].evs.hp = -1;}, ['less than 0 Awakening Values in HP']);
check('fractional_sp',baseline,t => {t[0].evs.hp = 1.5;});
check('missing_sp_axis',baseline,t => {delete t[0].evs.hp;});
check('missing_sp_object',baseline,t => {delete t[0].evs;}, [], t => {t[0].evs = {hp:0,atk:0,def:0,spa:0,spd:0,spe:0};});
check('one_protect',baseline,t => {t[0].moves = ['Protect'];});
check('one_fake_out',baseline,t => {t[0].moves = ['Fake Out'];});
check('joint_moves','one_protect',t => {t[0].moves.push('Fake Out');});
check('repeat_move','one_protect',t => {t[0].moves.push('Protect');}, ['multiple copies of Protect']);
check('invalid_gender',baseline,t => {t[0].gender = 'X';}, [], t => {t[0].gender = '';});
check('fixed_gender','wash_control',t => {t[2].gender = 'F';}, [], t => {t[2].gender = 'N';});
check('level_51',baseline,t => {t[0].level = 51;}, [], t => {t[0].level = 50;});
check('unnamed',baseline,t => {delete t[0].name;}, [], t => {t[0].name = 'Incineroar';});
check('two_reasons',baseline,t => {t[0].ability = 'Drizzle'; t[0].moves[1] = 'Spore';}, ["can't have Drizzle","can't learn Spore"]);
check('independent_set',baseline,noop,[],noop,'validateSet');
check('illegal_set','independent_set',t => {t[0].ability = 'Drizzle';}, ["can't have Drizzle"],noop,'validateSet');

assert.equal(git('status','--porcelain','--untracked-files=no'), '');
fs.writeFileSync(output, JSON.stringify({commit,format,base,original:original.map(c => ({
  id:c.id, expected:c.expected, expectedReason:c.expectedReason, decision:c.decision, problems:c.problems, match:c.match,
  reasonMatched:c.reasonMatched, selectedCoreMutation:c.materialMutation, mutations:changes(c.input,c.normalized),
  inputChangesFromBase:changes(base,c.input),
})),cases},null,2)+'\n', {flag:'wx',mode:0o600});
process.exitCode = cases.every(c => c.match) ? 0 : 1;
