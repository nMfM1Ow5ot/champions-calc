// てだすけ保留と消費ブックキーピングの関係 (MH-001-R1-G1 / G-F01)。
// R1-F1 までは「消費」の意味論 (ゲート経路でも消費する等) を検証する
// テストだったが、G-F01 で方針が「てだすけ観測ターンの同サイド攻撃
// 証拠は一律に保留する (判定は消費と独立した観測記録に基づく)」へ
// 変わったため、本ファイルは「保留が消費の順序・回数・経路に依存
// しないこと」と「てだすけと無関係な経路 (複数ヒット保留・反動) が
// 従来どおりであること」を検証する回帰テストへ変更した。
// 実行: node tests/test_hh_consumption.mjs (最後に ALL PASS と出す)
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const eng = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
const { gen, damageRolls, damageDistribution, withCurHP } = core;

let failures = 0;
function check(name, cond, detail = '') {
  console.log((cond ? 'PASS ' : 'FAIL ') + name + (!cond && detail ? ` (${detail})` : ''));
  if (!cond) failures++;
}

const J = f => JSON.parse(fs.readFileSync(ROOT + '/data/' + f, 'utf8'));
const POKEDB_PARSED = J('pokedb_parsed.json');
const USAGE_SETS = J('usage_sets.json');
const META_SETS = J('meta_sets.json');
const VGC_SETS = J('vgc_pastes.json');
const SPECIES_MOVES = J('species_moves.json');
const namesJa = J('names_ja.json');
const itemsJa = J('items_ja.json');
const moveJa2en = {};
for (const [id, ja] of Object.entries(namesJa.moves || {})) { const m = gen.moves.get(id); if (m) moveJa2en[ja] = m.name; }
const abilityJa2en = {};
for (const [id, ja] of Object.entries(namesJa.abilities || {})) { const a = gen.abilities.get(id); if (a) abilityJa2en[ja] = a.name; }
const NAMES = { ...namesJa, _itemJa2en: { ...itemsJa }, _moveJa2en: moveJa2en, _abilityJa2en: abilityJa2en };
const effSpecies = spec => (spec && spec.mega && spec.megaSpecies) ? spec.megaSpecies : spec.species;
const getData = () => ({ POKEDB_PARSED, USAGE_SETS, META_SETS, META_SETS_LOADED: true, NAMES, VGC_SETS, SPECIES_MOVES });
const makeEst = () => eng.createEstimator({ effSpecies, getData });

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', boosts: { ...boosts0, def: 2 } });
const truthRilla = spec('Rillaboom', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Grassy Surge' });
const baseRilla = spec('Rillaboom', 'Adamant', {});
const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil' });
const baseChomp = spec('Garchomp', 'Adamant', {});
const bogusBase = spec('Bogusmon', 'Adamant', {});

function hhOnlyAmt(truth, move) {
  const noHH = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles' });
  const hh = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles', atkSide: { isHelpingHand: true } });
  let amt = null;
  hh.dist.values.forEach((v, i) => { if (v > noHH.max && hh.dist.counts[i] > 0) amt = v; });
  return amt;
}
const amtRock = damageRolls(truthChomp, myVenusaur, 'Rock Slide', { gameType: 'Singles' }).rolls[10];
const amtHHChomp = hhOnlyAmt(truthChomp, 'Rock Slide');
check('前提: てだすけでしか届かない観測値が存在する', amtHHChomp !== null);

function scene() { const e = makeEst(); e.reset(); e.entry('Garchomp'); e.entry('Rillaboom'); e.takeInferenceLog(); return e; }
const hhEvent = (est, label) => est.processMoveInf({ turn: 1, label, move: 'Helping Hand' }, { my: {}, opp: {}, field: { weather: '', terrain: '' } });
const ioChomp = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
const ioRilla = { myDef: myVenusaur, basesAtk: [baseRilla], baseAtk: baseRilla };
function dmgStep(est, atkSp, move, amt, ctx) {
  const ev = { turn: 1, atk: 'p2: ' + atkSp, def: 'p1: Venusaur', move, amt, crit: false, w: '', t: '', defAlive: 2 };
  est.processDamageInf(ev, ctx);
  est.processDamageBayes(ev, ctx);
  return est.takeInferenceLog();
}
function fingerprint(est, species) {
  const ent = est._debug().bayes.bySpecies[species];
  const ie0 = est._debug().inference.bySpecies[species];
  const ser = v => v instanceof Set ? [...v].sort() : v;
  const ie = ie0 && (ie0.used || ie0.dropped || ie0.hpSps || Object.values(ie0.pairs).some(v => v)) ? ie0 : null;
  return JSON.stringify({
    cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), Number(c.post.toPrecision(12))]) : null,
    dmgFlag: ent ? ent.dmgFlag || null : null, used: ent ? ent.used : null,
    inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
  });
}
const suspended = log => log.some(r => r.trigger && r.trigger.kind === 'inf' && r.trigger.applied === false && r.trigger.reason === 'helping-hand-observed');

// 1: ゲート経路 (消費が起きる経路) を経ても保留は維持され、直接の場面と一致する
{
  const viaGate = scene();
  const f0 = fingerprint(viaGate, 'Garchomp');
  hhEvent(viaGate, 'p2: Rillaboom');
  dmgStep(viaGate, 'Rillaboom', 'Bullet Seed', 30, ioRilla); // ゲート保留 (R1-F1 の消費経路)
  const logR = dmgStep(viaGate, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('1: ゲート経路の後でも後続技は保留される', suspended(logR));
  const direct = scene();
  hhEvent(direct, 'p2: Rillaboom');
  dmgStep(direct, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('1: ゲート経由と直接で最終状態が一致する (消費に依存しない)', fingerprint(viaGate, 'Garchomp') === fingerprint(direct, 'Garchomp') && fingerprint(viaGate, 'Garchomp') === f0);
}
// 2: 計算不能になる証拠でも、てだすけ保留が優先される
{
  const est = scene();
  const f0 = fingerprint(est, 'Garchomp');
  hhEvent(est, 'p2: Rillaboom');
  const ioBogus = { myDef: myVenusaur, basesAtk: [baseChomp, bogusBase], baseAtk: baseChomp };
  const logS = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioBogus);
  check('2: 計算不能な証拠でも理由は helping-hand-observed で状態不変', suspended(logS) && fingerprint(est, 'Garchomp') === f0);
}
// 3: 先行する単発技も保留される (「最初の1件だけ適用」は起きない)
{
  const est = scene();
  const f0C = fingerprint(est, 'Garchomp'), f0R = fingerprint(est, 'Rillaboom');
  hhEvent(est, 'p2: Rillaboom');
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', amtRock, ioChomp);
  const log2 = dmgStep(est, 'Rillaboom', 'Wood Hammer', 16, ioRilla);
  check('3: 先行する単発技も後続の技も保留される', suspended(log1) && suspended(log2) && fingerprint(est, 'Garchomp') === f0C && fingerprint(est, 'Rillaboom') === f0R);
}
// 4: てだすけ観測が無ければ従来どおり適用される / 別ターンでは適用される
{
  const est = scene();
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', amtRock, ioChomp);
  check('4: 観測が無ければ同じ証拠は適用される', log1.some(r => r.trigger && r.trigger.kind === 'damage' && r.trigger.applied === true));
  const est2 = scene();
  hhEvent(est2, 'p2: Rillaboom');
  const ev2 = { turn: 2, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '', defAlive: 2 };
  est2.processDamageInf(ev2, ioChomp);
  est2.processDamageBayes(ev2, ioChomp);
  const log2 = est2.takeInferenceLog();
  check('4: 別ターンの証拠は保留されず適用される', log2.some(r => r.trigger && r.trigger.kind === 'damage' && r.trigger.applied === true) && !suspended(log2));
}
// 5: 同一イベントの重複処理でも保留は1回分と等価
{
  const est = scene();
  hhEvent(est, 'p2: Rillaboom');
  dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  const once = scene();
  hhEvent(once, 'p2: Rillaboom');
  dmgStep(once, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('5: 重複処理でも状態は単回処理と一致する', fingerprint(est, 'Garchomp') === fingerprint(once, 'Garchomp'));
}
// 6: 保留された証拠への急所イベントは対象なし / 再生一致
{
  const script = () => {
    const e = scene();
    hhEvent(e, 'p2: Rillaboom');
    dmgStep(e, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
    const evC = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
    e.processCritInf(evC, ioChomp);
    e.processCritBayes(evC, ioChomp);
    const log = e.takeInferenceLog();
    return { e, log };
  };
  const a = script(), b = script();
  const patch = a.log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('6: 保留された証拠への急所イベントは no-match', !!patch && patch.trigger.applied === false && patch.trigger.reason === 'no-match', JSON.stringify(patch && patch.trigger));
  check('6: 再生で最終状態が一致する', fingerprint(a.e, 'Garchomp') === fingerprint(b.e, 'Garchomp'));
}
// 7: 複数ヒット保留の不変条件 (てだすけと無関係な経路は従来どおり)
{
  const est = scene();
  const before = fingerprint(est, 'Rillaboom');
  const log = dmgStep(est, 'Rillaboom', 'Bullet Seed', 9999, ioRilla);
  const ent = est._debug().bayes.bySpecies['Rillaboom'];
  check('7: 過大な複数ヒット証拠でも候補・事後・フラグは不変', fingerprint(est, 'Rillaboom') === before && log.some(r => r.trigger && r.trigger.reason === 'multihit-suspended'));
  check('7: dmgFlag が誤発動しない', !ent.dmgFlag);
}
// 8: 反動経路の回帰 (反動証拠は従来どおり処理される)
{
  const recoilRun = () => {
    const e = makeEst();
    e.reset();
    e.entry('Rillaboom');
    e.takeInferenceLog();
    const rec = { turn: 1, atk: 'p2: Rillaboom', def: 'p2: Rillaboom', move: 'Wood Hammer', pct: 10, crit: false, w: '', t: '' };
    e.processDamageInf(rec, ioRilla);
    e.processDamageBayes(rec, ioRilla);
    e.takeInferenceLog();
    return fingerprint(e, 'Rillaboom');
  };
  const z1 = recoilRun(), z2 = recoilRun();
  check('8: 反動のみの結果が再現可能 (従来どおり)', z1 === z2 && JSON.parse(z1).used > 0);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
