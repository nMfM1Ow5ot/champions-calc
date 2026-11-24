// てだすけの残存リスクの回帰テスト。
// MH-001-R1-G §3 では、対象帰属ができないことによる誤排除・誤更新
// (リスク1) と、早期除外経路による誤適用 (リスク2) を対照実験で
// 実証した (当時の版)。MH-001-R1-G1 (G-F01) で方針が
// 「てだすけ観測ターンの同サイド攻撃証拠は一律に保留する」へ
// 変わったため、本ファイルは欠陥の存在を期待するテストから、
// 修正後の安全性を要求する回帰テストへ変更した。
// 実行: node tests/test_hh_residual_risks.mjs (最後に ALL PASS と出す)
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const eng = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
const { gen, damageDistribution, withCurHP } = core;

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

function distMode(atk, def, move, gameType = 'Singles') {
  const dd = damageDistribution(withCurHP(atk), withCurHP(def), move, { gameType });
  let best = null, bc = -1;
  dd.dist.values.forEach((v, i) => { if (dd.dist.counts[i] > bc) { bc = dd.dist.counts[i]; best = v; } });
  return best;
}
function hhOnlyAmt(truth, move) {
  const noHH = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles' });
  const hh = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles', atkSide: { isHelpingHand: true } });
  let amt = null;
  hh.dist.values.forEach((v, i) => { if (v > noHH.max && hh.dist.counts[i] > 0) amt = v; });
  return amt;
}
const amtHammerPlain = distMode(truthRilla, myVenusaur, 'Wood Hammer');
const amtSlidePlain = distMode(truthChomp, myVenusaur, 'Rock Slide', 'Doubles');
const amtHHChomp = hhOnlyAmt(truthChomp, 'Rock Slide');
const amtFoul = distMode(truthChomp, myVenusaur, 'Foul Play');

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
  const ie = est._debug().inference.bySpecies[species];
  const ser = v => v instanceof Set ? [...v].sort() : v;
  return JSON.stringify({
    cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), c.post]) : null,
    dmgFlag: ent ? ent.dmgFlag || null : null, used: ent ? ent.used : null,
    inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
  });
}
const suspended = log => log.some(r => r.trigger && r.trigger.kind === 'inf' && r.trigger.applied === false && r.trigger.reason === 'helping-hand-observed');

// ================= リスク1: 帰属できない場合 (G-F01 で保留される) =================
{
  // R1-G §3 で誤排除・誤更新が実証された列: 非対象の技が先行し、
  // 本来の対象の てだすけ でしか届かない量の技が続く
  const est = scene();
  const f0C = fingerprint(est, 'Garchomp'), f0R = fingerprint(est, 'Rillaboom');
  hhEvent(est, 'p2: Rillaboom');
  const l1 = dmgStep(est, 'Rillaboom', 'Wood Hammer', amtHammerPlain, ioRilla);
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('リスク1: 非対象の技も本来の対象の技も保留される', suspended(l1) && suspended(l2));
  check('リスク1: 誤排除・誤更新・フラグ誤発動のいずれも生じない', fingerprint(est, 'Garchomp') === f0C && fingerprint(est, 'Rillaboom') === f0R && !est._debug().bayes.bySpecies['Garchomp'].dmgFlag);
  // 順序を入れ替えても結果は同じ (帰属・順序に依存しない)
  const est2 = scene();
  hhEvent(est2, 'p2: Rillaboom');
  dmgStep(est2, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  dmgStep(est2, 'Rillaboom', 'Wood Hammer', amtHammerPlain, ioRilla);
  check('リスク1: 処理順序を入れ替えても最終状態は一致する', fingerprint(est2, 'Garchomp') === f0C && fingerprint(est2, 'Rillaboom') === f0R);
  // 通常量の観測値でも保留される (方針は一律)
  const est3 = scene();
  hhEvent(est3, 'p2: Rillaboom');
  const b1 = dmgStep(est3, 'Garchomp', 'Rock Slide', amtSlidePlain, ioChomp);
  check('リスク1: 通常量の観測値でも保留される', suspended(b1) && fingerprint(est3, 'Garchomp') === f0C);
}

// ================= リスク2: 早期除外経路 (G-F01 で保留が維持される) =================
{
  const est = scene();
  const f0 = fingerprint(est, 'Garchomp');
  hhEvent(est, 'p2: Rillaboom');
  const l1 = dmgStep(est, 'Garchomp', 'Foul Play', amtFoul, ioChomp);
  // 状態変更は一切なし。記録は てだすけ保留の通知 (ベイズ側) のみが
  // 残り得る (R1-G1 でベイズ側も保留を明示するようになったため)
  check('リスク2: イカサマ自体は推定対象外 (状態変更なし・適用記録なし)', fingerprint(est, 'Garchomp') === f0 && l1.every(r => !r.trigger || r.trigger.applied !== true), `records=${JSON.stringify(l1.map(r => r.trigger))}`);
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('リスク2: 後続技は誤適用されず保留される', suspended(l2) && fingerprint(est, 'Garchomp') === f0);
  const l3 = dmgStep(est, 'Garchomp', 'Rock Slide', amtSlidePlain, ioChomp);
  check('リスク2: 通常量の後続証拠でも真の候補行は排除されない (保留のため不変)', suspended(l3) && fingerprint(est, 'Garchomp') === f0);
  // 対照: てだすけ観測が無ければ同じ観測値は通常どおり評価される
  const est2 = scene();
  const c1 = dmgStep(est2, 'Garchomp', 'Rock Slide', amtSlidePlain, ioChomp);
  const ie = est2._debug().inference.bySpecies['Garchomp'];
  check('リスク2 対照: てだすけ観測が無ければ通常量の証拠は適用され真の候補行を含む', c1.some(r => r.trigger && r.trigger.kind === 'inf' && r.trigger.applied === true) && !!ie && !!ie.pairs.atk && [...ie.pairs.atk].includes('Adamant|32'));
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
