// MH-001-R1-F (エンジン側): 統合検収の補足検証。
// §1 processRecoilBayes の依存関係 (複数ヒット観測から独立か)
// §2 てだすけ消費の意味論の実証 (ゲート保留・計算不能保留・別個体・
//    後続技・急所再生)
// §3 candRanges の cover 条件付けの実証
// 本番コードは変更しない。実行: node tests/test_r1f_verification.mjs
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
const makeEst = fakeFn => eng.createEstimator(fakeFn ? { effSpecies, getData, damageDistribution: fakeFn } : { effSpecies, getData });
function makeFake(rule) {
  const calls = [];
  const fn = (atkSpec, defSpec, moveName, opts) => {
    const verdict = rule ? rule(atkSpec, defSpec, moveName, opts) : null;
    if (verdict === 'fail') { calls.push({ move: moveName, result: 'fail' }); return { error: 'injected' }; }
    if (verdict === 'extreme') { calls.push({ move: moveName, result: 'extreme' }); return { dist: { values: [999999], counts: [1], total: 1 }, min: 999999, max: 999999, hits: 1, multi: false }; }
    const r = core.damageDistribution(atkSpec, defSpec, moveName, opts);
    calls.push({ move: moveName, result: r && r.error ? 'error' : 'ok' });
    return r;
  };
  return { fn, calls };
}

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });
const truthRilla = spec('Rillaboom', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Grassy Surge', moves: ['Wood Hammer', 'Bullet Seed'] });
const baseRilla = spec('Rillaboom', 'Adamant', {});
const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide'] });
const baseChomp = spec('Garchomp', 'Adamant', {});
const bogusBase = spec('Bogusmon', 'Adamant', {});

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
function distMode(atk, def, move) {
  const dd = damageDistribution(withCurHP(atk), withCurHP(def), move, { gameType: 'Singles' });
  let best = null, bc = -1;
  dd.dist.values.forEach((v, i) => { if (dd.dist.counts[i] > bc) { bc = dd.dist.counts[i]; best = v; } });
  return best;
}
const amtSeed = distMode(truthRilla, myVenusaur, 'Bullet Seed');
const amtHammer = distMode(truthRilla, myVenusaur, 'Wood Hammer');

// ================= §1 processRecoilBayes の依存関係 =================
function recoilRun(pre, pct, fakeFn) {
  const est = makeEst(fakeFn || null);
  est.reset();
  est.entry('Rillaboom');
  const initial = fingerprint(est, 'Rillaboom');
  for (const fn of pre) fn(est);
  est.takeInferenceLog();
  const ev = { turn: 2, atk: 'p2: Rillaboom', def: 'p2: Rillaboom', pct };
  est.processDamageInf(ev, {});
  est.processDamageBayes(ev, {});
  const log = est.takeInferenceLog();
  return { est, initial, fp: fingerprint(est, 'Rillaboom'), log };
}
const dmgEv = (move, amt) => est => {
  const ev = { turn: 1, atk: 'p2: Rillaboom', def: 'p1: Venusaur', move, amt, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseRilla], baseAtk: baseRilla };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
};
{
  const Z = recoilRun([], 10);
  check('§1 前提: 反動観測のみで事後が動く', Z.fp !== Z.initial);
  check('§1 前提: recoil の適用記録が残る', Z.log.some(r => r.trigger && r.trigger.kind === 'recoil' && r.trigger.applied === true), JSON.stringify(Z.log.map(r => r.trigger)));
  const X = recoilRun([dmgEv('Wood Hammer', amtHammer)], 10);
  const Y = recoilRun([dmgEv('Bullet Seed', amtSeed)], 10);
  check('§1(a): 複数ヒット技+反動の結果が反動のみの結果と一致する', Y.fp === Z.fp);
  check('§1(a): 単発技+反動ではダメージ側の更新も加わる', X.fp !== Z.fp);
  check('§1(a): 複数ヒットが保留されても反動処理は発火する', Y.log.some(r => r.trigger && r.trigger.kind === 'recoil' && r.trigger.applied === true));
  // (b) ダメージ量・ヒット数を変えても反動側の更新は変わらない
  const Y2 = recoilRun([dmgEv('Bullet Seed', 9999)], 10);
  const Y3 = recoilRun([dmgEv('Bullet Seed', 1)], 10);
  check('§1(b): 複数ヒット技のダメージ量を変えても反動の更新は同一', Y2.fp === Z.fp && Y3.fp === Z.fp);
  const P9 = recoilRun([], 9), P11 = recoilRun([], 11);
  check('§1(b): 反動 pct が帯域内なら更新は同一 (pct の大きさ自体は使わない)', P9.fp === Z.fp && P11.fp === Z.fp);
  const P7 = recoilRun([], 7), P12 = recoilRun([], 12);
  check('§1(b): 反動 pct が帯域外なら更新されない', P7.fp === P7.initial && P12.fp === P12.initial);
  // (c) 分布計算を失敗させても反動経路に影響しない
  const fakeFail = makeFake(() => 'fail');
  const W = recoilRun([dmgEv('Wood Hammer', amtHammer)], 10, fakeFail.fn);
  check('§1(c): 分布が全て失敗しても反動の更新は同一', W.fp === Z.fp);
  check('§1(c): 到達証拠: ダメージ側では分布計算が試行されている', fakeFail.calls.length > 0, 'calls=' + fakeFail.calls.length);
}

// ================= §2 てだすけ消費の検証 =================
// てだすけでしか届かないダメージ量を観測値に使うことで、inf の適用
// 可否から「その技がてだすけ込みで評価されたか」を読み取る
// ※ MH-001-R1-G1 (G-F01) で方針変更: てだすけ観測ターンの同サイド
// 攻撃証拠は、消費の仕組みによらず一律に保留される
// (理由 helping-hand-observed)。§2 の各場面の期待値はこの方針に
// 合わせて変更した (変更理由は各チェックの注記を参照)
function hhOnlyAmt(truth, move) {
  const noHH = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles' });
  const hh = damageDistribution(withCurHP(truth), withCurHP(myVenusaur), move, { gameType: 'Doubles', atkSide: { isHelpingHand: true } });
  let amt = null;
  hh.dist.values.forEach((v, i) => { if (v > noHH.max && hh.dist.counts[i] > 0) amt = v; });
  return { amt, noHHMax: noHH.max };
}
const hhChomp = hhOnlyAmt(truthChomp, 'Rock Slide');
const hhRilla = hhOnlyAmt(truthRilla, 'Wood Hammer');
check('§2 前提: てだすけでしか届かない観測値が存在する', hhChomp.amt !== null && hhRilla.amt !== null, JSON.stringify([hhChomp, hhRilla]));

function hhScene() {
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  est.entry('Rillaboom');
  return est;
}
const hhEvent = (est, label) => est.processMoveInf({ turn: 1, label, move: 'Helping Hand' }, { my: {}, opp: {}, field: { weather: '', terrain: '' } });
function dmgStep(est, atkSp, move, amt, ctx) {
  const ev = { turn: 1, atk: 'p2: ' + atkSp, def: 'p1: Venusaur', move, amt, crit: false, w: '', t: '', defAlive: 2 };
  est.processDamageInf(ev, ctx);
  est.processDamageBayes(ev, ctx);
  return est.takeInferenceLog();
}
const infApplied = log => { const r = log.find(r => r.trigger && r.trigger.kind === 'inf'); return r ? r.trigger.applied : null; };
const infReason = log => { const r = log.find(r => r.trigger && r.trigger.kind === 'inf'); return r ? (r.trigger.reason || null) : null; };
const ioChomp = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
const ioRilla = { myDef: myVenusaur, basesAtk: [baseRilla], baseAtk: baseRilla };

// 場面4 (対照の基礎): R1-G1 方針では観測ターンの証拠は一律に保留される
{
  const est = hhScene();
  hhEvent(est, 'p2: Rillaboom');
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  // R1-G1 で期待値を変更: 従来は「未消費なら適用される」だったが、
  // G-F01 の方針 (観測ターンの同サイド攻撃証拠は保留) により、
  // 最初の証拠から保留される
  check('§2-4 (R1-G1 方針変更): てだすけ観測ターンの最初の証拠も保留される', infApplied(log1) === false && infReason(log1) === 'helping-hand-observed', JSON.stringify(log1.map(r => r.trigger)));
  const log2 = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  check('§2-4: 同一ターンの後続の証拠も保留される (消費に依存しない)', infApplied(log2) === false && infReason(log2) === 'helping-hand-observed', JSON.stringify(log2.map(r => r.trigger)));
  const est2 = hhScene();
  const log3 = dmgStep(est2, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  check('§2-4 対照: てだすけ観測が無ければ適用されない', infApplied(log3) === false, JSON.stringify(log3.map(r => r.trigger)));
}
// 場面1: ゲート保留された複数ヒット技の後
{
  const est = hhScene();
  hhEvent(est, 'p2: Rillaboom');
  const logS = dmgStep(est, 'Rillaboom', 'Bullet Seed', amtSeed, ioRilla);
  // R1-G1 で期待値を変更: てだすけ保留が複数ヒットゲートより手前で
  // 効くため、この場面の理由は helping-hand-observed になる
  check('§2-1 前提 (R1-G1 変更): てだすけ観測ターンの複数ヒット技は てだすけ保留になる', logS.some(r => r.trigger && r.trigger.reason === 'helping-hand-observed'), JSON.stringify(logS.map(r => r.trigger)));
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  // R1-F1 で消費の漏出は解消したが、R1-G1 (G-F01) で方針自体が
  // 「観測ターンの証拠は保留」へ変わったため、後続技も保留される
  check('§2-1 実測 (R1-G1 方針変更): 後続技も てだすけ保留になる', infApplied(log1) === false && infReason(log1) === 'helping-hand-observed', JSON.stringify(log1.map(r => r.trigger)));
}
// 場面2: 計算不能で保留された技の後
{
  const est = hhScene();
  hhEvent(est, 'p2: Rillaboom');
  const ioBogus = { myDef: myVenusaur, basesAtk: [baseChomp, bogusBase], baseAtk: baseChomp };
  const logS = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioBogus);
  // R1-G1 で期待値を変更: てだすけ保留が分布計算より手前で効くため、
  // 計算不能には到達せず理由は helping-hand-observed になる
  check('§2-2 前提 (R1-G1 変更): てだすけ保留が計算不能より優先される', logS.some(r => r.trigger && r.trigger.reason === 'helping-hand-observed'), JSON.stringify(logS.map(r => r.trigger)));
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  check('§2-2 実測 (R1-G1 方針変更): 後続技も てだすけ保留になる', infApplied(log1) === false && infReason(log1) === 'helping-hand-observed', JSON.stringify(log1.map(r => r.trigger)));
}
// 場面3: 同一サイドの別個体が先に攻撃した場合
{
  const est = hhScene();
  hhEvent(est, 'p2: Rillaboom');
  const log1 = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
  // R1-G1 で期待値を変更: 帰属を問わず観測ターンの証拠は保留される
  check('§2-3 実測 (R1-G1 方針変更): 先に処理された別個体の技も保留される', infApplied(log1) === false && infReason(log1) === 'helping-hand-observed', JSON.stringify(log1.map(r => r.trigger)));
  const log2 = dmgStep(est, 'Rillaboom', 'Wood Hammer', hhRilla.amt, ioRilla);
  check('§2-3 実測 (R1-G1 方針変更): その後の技 (使用者側) も保留される', infApplied(log2) === false && infReason(log2) === 'helping-hand-observed', JSON.stringify(log2.map(r => r.trigger)));
}
// 場面5: 急所の後付け再推論と再生での一致
{
  const script = est => {
    hhEvent(est, 'p2: Rillaboom');
    dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
    const critEv = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
    est.processCritInf(critEv, ioChomp);
    est.processCritBayes(critEv, ioChomp);
    const log = est.takeInferenceLog();
    const after = dmgStep(est, 'Garchomp', 'Rock Slide', hhChomp.amt, ioChomp);
    return { fp: fingerprint(est, 'Garchomp'), log, after };
  };
  const r1 = script(hhScene());
  const patch = r1.log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  // R1-G1 で期待値を変更: 証拠自体が保留され記録が残らないため、
  // 急所是正の対象は存在しない (no-match)
  check('§2-5 (R1-G1 方針変更): 保留された証拠への急所是正は対象なし', !!patch && patch.trigger.applied === false && patch.trigger.reason === 'no-match', JSON.stringify(patch && patch.trigger));
  check('§2-5: その後の証拠も てだすけ保留のまま', infApplied(r1.after) === false && infReason(r1.after) === 'helping-hand-observed', JSON.stringify(r1.after.map(r => r.trigger)));
  const r2 = script(hhScene());
  check('§2-5: 初期化+再生で消費状態と最終状態が一致する (二重消費・復活なし)', r2.fp === r1.fp && JSON.stringify(r2.log.map(r => r.trigger)) === JSON.stringify(r1.log.map(r => r.trigger)));
}

// ================= §3 candRanges の cover 条件付け =================
const side0 = { hand: false, light: false, reflect: false, veil: false, guard: false, rock: false, spikes: 0 };
const crArgs = (mine, opp) => ({ mine, opp, field: { weather: '', terrain: '' }, side: { mine: { ...side0 }, opp: { ...side0 } }, critMine: false, critOpps: false, isSingleMine: () => false, isSingleOpps: () => false });
const oppChomp = spec('Garchomp', 'Adamant', {}, { ability: 'Sand Veil', moves: ['Rock Slide', 'Earthquake'] });
{
  const amtA = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];
  const amtB = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[0];
  const feed = (est, amt, turn) => {
    const ev = { turn, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt, crit: false, w: '', t: '' };
    est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
    est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
    est.takeInferenceLog();
  };
  const est = makeEst(null);
  est.reset();
  const ent = est.entry('Garchomp');
  for (let t = 1; t <= 3; t++) feed(est, amtA, t);
  const cov1 = est.cover('Garchomp');
  const baseline = JSON.stringify(est.candRanges(crArgs(myVenusaur, oppChomp)));
  // cover 外候補の署名でのみ極端な分布を返す差し替え (別インスタンスで再現)
  const coveredIdx = new Set(cov1.cover.map(c => ent.cands.indexOf(c)));
  const outside = ent.cands.find((c, i) => !coveredIdx.has(i));
  const sig = c => c.nature + '|' + c.item + '|' + c.ability + '|' + JSON.stringify(c.sp);
  let armed = false;
  const fake = makeFake((atk, def) => (armed && def && def.species === 'Garchomp' && sig({ nature: def.nature, item: def.item, ability: def.ability, sp: def.sp }) === sig(outside)) ? 'extreme' : null);
  const est2 = makeEst(fake.fn);
  est2.reset();
  est2.entry('Garchomp');
  for (let t = 1; t <= 3; t++) feed(est2, amtA, t);
  armed = true;
  const out2 = JSON.stringify(est2.candRanges(crArgs(myVenusaur, oppChomp)));
  check('§3: cover 外候補に極端な値を持たせても表示範囲は広がらない', out2 === baseline);
  check('§3 到達証拠: cover 外候補は計算自体されていない', !fake.calls.some(c => c.result === 'extreme'), JSON.stringify(fake.calls.map(c => c.result)));
  // 証拠で cover が狭まると範囲が変わり得る
  for (let t = 4; t <= 5; t++) feed(est, amtB, t);
  const cov2 = est.cover('Garchomp');
  const after = JSON.stringify(est.candRanges(crArgs(myVenusaur, oppChomp)));
  check('§3: 証拠で cover が狭まると集計が変わり得る', cov2.cover.length <= cov1.cover.length && after !== baseline, `cover ${cov1.cover.length} -> ${cov2.cover.length}`);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
