import test from 'node:test';
import assert from 'node:assert/strict';
import {moveKeys, classifyReference} from './v11_dex_validator_runner_v3.mjs';

const rows = [{id:'hiddenpower', name:'Hidden Power', type:'Normal'}, {id:'hiddenpower', name:'Hidden Power Fire', type:'Fire'}];
const data = {hiddenpower:{}, hiddenpowerfire:{placeholderFor:'Hidden Power'}};
const dex = {getByID(key) { return {...rows[key === 'hiddenpower' ? 0 : 1], exists:true}; }};
test('typed variant and canonical move survive as distinct rows with the actual simulator ID', () => {
  assert.deepEqual(moveKeys(rows, data, dex).map(r => [r.id,r.simulatorId,r.type]), [
    ['hiddenpower','hiddenpower','Normal'], ['hiddenpowerfire','hiddenpower','Fire'],
  ]);
});
test('unexplained collision and missing row block extraction', () => {
  assert.throws(() => moveKeys(rows, {...data, hiddenpowerfire:{}}, dex));
  assert.throws(() => moveKeys(rows, {hiddenpower:{}}, dex));
});
test('empty slots require both the known Custom owner and its format exclusion', () => {
  const issue = {kind:'ability',name:''};
  const owner = {id:'missingno',isNonstandard:'Custom',componentRuleProblem:'banned'};
  assert.equal(classifyReference(issue, owner), 'excludedEmptyAbility');
  for (const changed of [{id:'other'}, {isNonstandard:null}, {componentRuleProblem:null}]) {
    assert.equal(classifyReference(issue, {...owner,...changed}), 'unresolved');
  }
  assert.equal(classifyReference({...issue,name:'unknown'}, owner), 'unresolved');
});
