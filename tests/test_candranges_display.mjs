// MH-001-R1-E: candRanges の完全性契約の検証。信用集合 (cover) 内の
// 候補のうち1件でも分布が計算不能なら、その技エントリは部分集計値では
// なく { unavailable: true } で返ること。有効な分布での真の KO 確率0や
// 無効 (immune) は計算不能と区別され、通常の集計値が返ること。cover 外
// の候補は完全性に影響しないこと。candRanges が推定状態を変更しない
// ことを、実経路 (R1-C2 のシームで計算不能を構成) で確認する。
// 実行: node tests/test_candranges_display.mjs (最後に ALL PASS と出す)
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const eng = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
const { gen, damageRolls, withCurHP } = core;

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
const makeEst = fakeFn => eng.createEstimator(fakeFn ? { effSpecies, getData, damageDistribution: fakeFn } : { effSpecies, getData });

function makeFake(rule) {
  const calls = [];
  const fn = (atkSpec, defSpec, moveName, opts) => {
    const verdict = rule ? rule(atkSpec, defSpec, moveName, opts) : null;
    if (verdict === 'fail') { calls.push({ atk: atkSpec && atkSpec.species, def: defSpec && defSpec.species, defItem: defSpec && defSpec.item, move: moveName, result: 'fail' }); return { error: 'injected' }; }
    const r = core.damageDistribution(atkSpec, defSpec, moveName, opts);
    calls.push({ atk: atkSpec && atkSpec.species, def: defSpec && defSpec.species, defItem: defSpec && defSpec.item, move: moveName, result: r && r.error ? 'error' : 'ok' });
    return r;
  };
  return { fn, calls };
}

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'] });
const oppChomp = spec('Garchomp', 'Adamant', {}, { ability: 'Sand Veil', moves: ['Rock Slide', 'Earthquake'] });
const baseChomp = spec('Garchomp', 'Adamant', {});
const side0 = { hand: false, light: false, reflect: false, veil: false, guard: false, rock: false, spikes: 0 };
const crArgs = (mine, opp) => ({ mine, opp, field: { weather: '', terrain: '' }, side: { mine: { ...side0 }, opp: { ...side0 } }, critMine: false, critOpps: false, isSingleMine: () => false, isSingleOpps: () => false });

// candRanges は証拠が1件以上適用された後に cover を返す (エンジンの
// 既存仕様)。各場面ではまず正常な単発証拠を1件適用してから呼ぶ
const truthChompEv = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide'] });
const amtRockEv = damageRolls(withCurHP(truthChompEv), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];
function applyEvidence(est) {
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRockEv, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  est.takeInferenceLog();
}
const isUnavailable = e => !!e && e.unavailable === true && Object.keys(e).length === 1;
const isNumeric = e => !!e && typeof e.lo === 'number' && typeof e.hi === 'number' && typeof e.exp === 'number' && typeof e.ko === 'number' && !e.unavailable;

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

// ---- 正常な単発技: 従来どおりの集計値 (シーム無し＝本番経路) ----
let baselineMine0 = null;
{
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const out = est.candRanges(crArgs(myVenusaur, oppChomp));
  baselineMine0 = out.mine[0];
  check('正常単発: 集計値が返る', isNumeric(out.mine[0]), JSON.stringify(out.mine[0]));
  check('正常単発: 相手方向も集計値が返る', isNumeric(out.opps[0]) && isNumeric(out.opps[1]), JSON.stringify(out.opps));
  check('正常単発: acc が信用集合の累積質量を返す', typeof out.acc === 'number' && out.acc > 0.8, String(out.acc));
}
// ---- 正常な複数ヒット技 (計算可能な場合): 分布ベースの集計が維持される ----
{
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const myGreninja = spec('Greninja', 'Timid', { spa: 32, spe: 32 }, { ability: 'Torrent', moves: ['Water Shuriken'] });
  const out = est.candRanges(crArgs(myGreninja, oppChomp));
  check('正常複数ヒット: 集計値が返り幅を持つ', isNumeric(out.mine[0]) && out.mine[0].hi > out.mine[0].lo, JSON.stringify(out.mine[0]));
}
// ---- 一部候補が計算不能: 当該技は表示保留、部分集計値は返らない ----
{
  const fake = makeFake((atk, def) => (atk && atk.species === 'Venusaur' && def && def.nature === 'Adamant' && def.sp && def.sp.atk === 32) ? 'fail' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const out = est.candRanges(crArgs(myVenusaur, oppChomp));
  const mineCalls = fake.calls.filter(c => c.move === 'Earth Power');
  check('一部不能 到達証拠: cover 内で失敗と成功が混在した', mineCalls.some(c => c.result === 'fail') && mineCalls.some(c => c.result === 'ok'), JSON.stringify(mineCalls.map(c => c.result)));
  check('一部不能: 当該技エントリが { unavailable: true } のみになる', isUnavailable(out.mine[0]), JSON.stringify(out.mine[0]));
  check('一部不能: 影響のない相手方向は集計値のまま', isNumeric(out.opps[0]) && isNumeric(out.opps[1]), JSON.stringify(out.opps));
}
// ---- 全候補が計算不能: 表示保留になる ----
{
  let failAll = false;
  const fake = makeFake(() => failAll ? 'fail' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  failAll = true;
  const out = est.candRanges(crArgs(myVenusaur, oppChomp));
  check('全不能: 自分方向が表示保留になる', isUnavailable(out.mine[0]), JSON.stringify(out.mine[0]));
  check('全不能: 相手方向も表示保留になる', isUnavailable(out.opps[0]) && isUnavailable(out.opps[1]), JSON.stringify(out.opps));
}
// ---- 有効な分布で真の KO 確率0: unavailable にならず ko=0 で返る ----
{
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const weakVenusaur = spec('Venusaur', 'Hardy', {}, { ability: 'Overgrow', moves: ['Tackle'] });
  const out = est.candRanges(crArgs(weakVenusaur, oppChomp));
  check('真のKO0: 集計値が返り ko が 0', isNumeric(out.mine[0]) && out.mine[0].ko === 0 && out.mine[0].exp > 0, JSON.stringify(out.mine[0]));
}
// ---- 無効 (immune) の退化分布は有効: 集計値 (全て0) が返る ----
{
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const boltVenusaur = spec('Venusaur', 'Modest', { spa: 20 }, { ability: 'Overgrow', moves: ['Thunderbolt'] });
  const out = est.candRanges(crArgs(boltVenusaur, oppChomp));
  check('immune: 集計値が返り全て 0', isNumeric(out.mine[0]) && out.mine[0].lo === 0 && out.mine[0].hi === 0 && out.mine[0].exp === 0 && out.mine[0].ko === 0, JSON.stringify(out.mine[0]));
}
// ---- cover 外の候補の計算不能は完全性に影響しない ----
{
  const fake = makeFake(null);
  const est = makeEst(fake.fn);
  est.reset();
  const ent = est.entry('Garchomp');
  // 証拠を重ねて cover を絞る
  const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide'] });
  const amt = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];
  for (let t = 1; t <= 3; t++) {
    const ev = { turn: t, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt, crit: false, w: '', t: '' };
    est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
    est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  }
  est.takeInferenceLog();
  const cov = est.cover('Garchomp');
  const coveredIdx = new Set(cov.cover.map(c => ent.cands.indexOf(c)));
  check('cover外 前提: cover が全候補より小さい', cov.cover.length < ent.cands.length, `cover=${cov.cover.length} cands=${ent.cands.length}`);
  const outside = ent.cands.find((c, i) => !coveredIdx.has(i));
  // cover 外候補の署名 (性格+持ち物+SP) でのみ失敗させる
  const sig = c => c.nature + '|' + c.item + '|' + c.ability + '|' + JSON.stringify(c.sp);
  const fake2 = makeFake((atk, def) => (def && def.species === 'Garchomp' && sig({ nature: def.nature, item: def.item, ability: def.ability, sp: def.sp }) === sig(outside)) ? 'fail' : null);
  const est2 = eng.createEstimator({ effSpecies, getData, damageDistribution: fake2.fn });
  est2.reset();
  const ent2 = est2.entry('Garchomp');
  for (let t = 1; t <= 3; t++) {
    const ev = { turn: t, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt, crit: false, w: '', t: '' };
    est2.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
    est2.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  }
  est2.takeInferenceLog();
  const cov2 = est2.cover('Garchomp');
  const covered2 = new Set(cov2.cover.map(c => ent2.cands.indexOf(c)));
  const outside2 = ent2.cands.find((c, i) => !covered2.has(i));
  check('cover外 前提: 別インスタンスでも cover 外候補が存在する', !!outside2 && sig(outside2) === sig(outside));
  const out = est2.candRanges(crArgs(myVenusaur, oppChomp));
  check('cover外: 集計値が返り unavailable にならない', isNumeric(out.mine[0]), JSON.stringify(out.mine[0]));
  check('cover外 到達証拠: cover 外候補は計算自体されていない', !fake2.calls.some(c => c.result === 'fail'), JSON.stringify(fake2.calls.map(c => c.result)));
}
// ---- 状態不変性: 計算不能を含む呼出でも推定状態が変わらない ----
{
  const fake = makeFake((atk, def) => (def && def.nature === 'Adamant' && def.sp && def.sp.atk === 32) ? 'fail' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  applyEvidence(est);
  const before = fingerprint(est, 'Garchomp');
  const out = est.candRanges(crArgs(myVenusaur, oppChomp));
  check('状態不変性: 前提として表示保留が発生している', isUnavailable(out.mine[0]) || isUnavailable(out.opps[0]), JSON.stringify([out.mine[0], out.opps[0]]));
  check('状態不変性: 候補集合・事後・フラグ・inf が変わらない', fingerprint(est, 'Garchomp') === before);
  check('状態不変性: 推論ログにも記録が残らない', est.takeInferenceLog().length === 0);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
