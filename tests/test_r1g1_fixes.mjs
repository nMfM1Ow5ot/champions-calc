// MH-001-R1-G1: G-F01 (てだすけ証拠の保留) / G-F02 (複数ヒット遮断の
// 跨ぎ原子性) / G-F03 (急所再推論の原子性) の検証。
// 実行: node tests/test_r1g1_fixes.mjs (最後に ALL PASS と出す)
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
const makeEst = (fakeFn) => eng.createEstimator(fakeFn ? { effSpecies, getData, damageDistribution: fakeFn } : { effSpecies, getData });

// 故障注入用の偽 damageDistribution: rule が 'fail' | 'multi' | null を返す
function makeFake(rule) {
  const calls = [];
  const fake = (atkSpec, defSpec, moveName, opts) => {
    const verdict = rule(atkSpec, defSpec, moveName, opts, calls.length);
    calls.push({ item: atkSpec && atkSpec.item, nature: atkSpec && atkSpec.nature, crit: !!(opts && opts.crit), verdict: verdict || 'ok' });
    if (verdict === 'fail') return { error: 'injected' };
    const real = damageDistribution(atkSpec, defSpec, moveName, opts);
    if (verdict === 'multi' && real && real.dist) return { ...real, multi: true };
    return real;
  };
  fake.calls = calls;
  return fake;
}

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', boosts: { ...boosts0, def: 2 } });
const myBlastoise = spec('Blastoise', 'Modest', { spa: 20, spe: 20 }, { ability: 'Torrent' });
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
const amtRock = damageRolls(truthChomp, myVenusaur, 'Rock Slide', { gameType: 'Singles' }).rolls[10];
const amtRockDbl = distMode(truthChomp, myVenusaur, 'Rock Slide', 'Doubles');
const amtHHChomp = hhOnlyAmt(truthChomp, 'Rock Slide');
const amtHammer = distMode(truthRilla, myVenusaur, 'Wood Hammer');

function scene(fakeFn) { const e = makeEst(fakeFn); e.reset(); e.entry('Garchomp'); e.entry('Rillaboom'); e.takeInferenceLog(); return e; }
const hhEvent = (est, label, turn = 1) => est.processMoveInf({ turn, label, move: 'Helping Hand' }, { my: {}, opp: {}, field: { weather: '', terrain: '' } });
const ioChomp = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
const ioRilla = { myDef: myVenusaur, basesAtk: [baseRilla], baseAtk: baseRilla };
function dmgStep(est, atkSp, move, amt, ctx, turn = 1, defLabel = 'p1: Venusaur') {
  const ev = { turn, atk: 'p2: ' + atkSp, def: defLabel, move, amt, crit: false, w: '', t: '', defAlive: 2 };
  est.processDamageInf(ev, ctx);
  est.processDamageBayes(ev, ctx);
  return est.takeInferenceLog();
}
function fingerprint(est, species) {
  const ent = est._debug().bayes.bySpecies[species];
  const ie0 = est._debug().inference.bySpecies[species];
  const ser = v => v instanceof Set ? [...v].sort() : v;
  // 制約が一切無い inf エントリは「未生成」と等価として正規化する
  const ie = ie0 && (ie0.used || ie0.dropped || ie0.hpSps || Object.values(ie0.pairs).some(v => v)) ? ie0 : null;
  return JSON.stringify({
    // 事後は浮動小数の往復誤差を避けるため12桁で丸める (巻き戻しの逆演算用)
    cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), Number(c.post.toPrecision(12))]) : null,
    dmgFlag: ent ? ent.dmgFlag || null : null, speFlag: ent ? ent.speFlag || null : null, used: ent ? ent.used : null, hpLifted: ent ? !!ent.hpLifted : null,
    inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
  });
}
const hasRec = (log, kind, reason) => log.some(r => r.trigger && r.trigger.kind === kind && (!reason || r.trigger.reason === reason));

// ============ G-F01-1: 対象帰属 (非対象の技が先行しても保留される) ============
{
  const est = scene();
  const f0C = fingerprint(est, 'Garchomp'), f0R = fingerprint(est, 'Rillaboom');
  hhEvent(est, 'p2: Rillaboom');
  const l1 = dmgStep(est, 'Rillaboom', 'Wood Hammer', amtHammer, ioRilla);
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('G-F01-1: 非対象の技も対象の技も保留される (理由 helping-hand-observed)', hasRec(l1, 'inf', 'helping-hand-observed') && hasRec(l2, 'inf', 'helping-hand-observed'));
  check('G-F01-1: 両種族とも推定状態は不変 (誤排除・誤更新・フラグなし)', fingerprint(est, 'Garchomp') === f0C && fingerprint(est, 'Rillaboom') === f0R);
}
// ============ G-F01-2: 早期除外技を挟んでも保留が維持される ============
{
  const est = scene();
  const f0 = fingerprint(est, 'Garchomp');
  hhEvent(est, 'p2: Rillaboom');
  dmgStep(est, 'Garchomp', 'Foul Play', distMode(truthChomp, myVenusaur, 'Foul Play'), ioChomp);
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('G-F01-2: イカサマを挟んでも後続の証拠は保留される', hasRec(l2, 'inf', 'helping-hand-observed') && fingerprint(est, 'Garchomp') === f0);
}
// ============ G-F01-3: 範囲技の対象別2イベントが両方保留される ============
{
  const est = scene();
  const f0 = fingerprint(est, 'Garchomp');
  hhEvent(est, 'p2: Rillaboom');
  const l1 = dmgStep(est, 'Garchomp', 'Rock Slide', amtRockDbl, ioChomp, 1, 'p1: Venusaur');
  const ioChompB = { myDef: myBlastoise, basesAtk: [baseChomp], baseAtk: baseChomp };
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', distMode(truthChomp, myBlastoise, 'Rock Slide', 'Doubles'), ioChompB, 1, 'p1: Blastoise');
  check('G-F01-3: 対象別2イベントが両方とも保留される', hasRec(l1, 'inf', 'helping-hand-observed') && hasRec(l2, 'inf', 'helping-hand-observed') && fingerprint(est, 'Garchomp') === f0);
}
// ============ G-F01: 消費に依存しない (ゲート消費・重複観測・別ターン・反対サイド) ============
{
  const est = scene();
  hhEvent(est, 'p2: Rillaboom');
  hhEvent(est, 'p2: Rillaboom'); // 重複観測
  dmgStep(est, 'Rillaboom', 'Bullet Seed', 30, ioRilla); // ゲート保留 (消費経路)
  const l = dmgStep(est, 'Garchomp', 'Rock Slide', amtHHChomp, ioChomp);
  check('G-F01: ゲート消費や重複観測の後でも保留は維持される', hasRec(l, 'inf', 'helping-hand-observed'));
  const l2 = dmgStep(est, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 2);
  check('G-F01: 別ターンの証拠は通常どおり処理される', !hasRec(l2, 'inf', 'helping-hand-observed') && est._debug().bayes.bySpecies['Garchomp'].used > 0);
  // 反対サイド (自軍の攻撃) は維持される: 自軍 Venusaur の攻撃で相手を推定
  const est2 = scene();
  hhEvent(est2, 'p2: Rillaboom');
  // 実分布から観測 pct を作る (真の型の HP に対する割合)
  const hpTruth = core.statTable('Garchomp').hp.find(r => r.nature === 'Adamant' && r.sp === 0).value;
  const pctMine = Math.round(distMode(myVenusaur, truthChomp, 'Sludge Bomb') / hpTruth * 100);
  const evMine = { turn: 1, atk: 'p1: Venusaur', def: 'p2: Garchomp', move: 'Sludge Bomb', pct: pctMine, crit: false, w: '', t: '' };
  const ioMine = { myAtk: myVenusaur, basesDef: [baseChomp], baseDef: baseChomp };
  est2.processDamageInf(evMine, ioMine);
  est2.processDamageBayes(evMine, ioMine);
  const lm = est2.takeInferenceLog();
  check('G-F01: てだすけ側を防御側とする証拠 (自軍の攻撃) は処理が維持される', !hasRec(lm, 'inf', 'helping-hand-observed') && est2._debug().bayes.bySpecies['Garchomp'].used > 0, JSON.stringify(lm.map(r => r.trigger)));
}
// ============ G-F01: 遅延観測 (適用済み証拠の巻き戻しと再生一致) ============
{
  const scriptHHFirst = () => {
    const e = scene();
    hhEvent(e, 'p2: Rillaboom');
    dmgStep(e, 'Garchomp', 'Rock Slide', amtRock, ioChomp);
    dmgStep(e, 'Rillaboom', 'Wood Hammer', amtHammer, ioRilla);
    e.takeInferenceLog();
    return e;
  };
  const scriptDelayed = () => {
    const e = scene();
    dmgStep(e, 'Garchomp', 'Rock Slide', amtRock, ioChomp);
    dmgStep(e, 'Rillaboom', 'Wood Hammer', amtHammer, ioRilla);
    hhEvent(e, 'p2: Rillaboom'); // 遅れて届く観測
    e.takeInferenceLog();
    return e;
  };
  const a = scriptHHFirst(), b = scriptDelayed();
  check('G-F01 遅延: 巻き戻し後の状態は先行観測の場合と一致する', fingerprint(b, 'Garchomp') === fingerprint(a, 'Garchomp') && fingerprint(b, 'Rillaboom') === fingerprint(a, 'Rillaboom'));
  // 巻き戻された証拠への crit は対象なし
  const evC = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  b.processCritInf(evC, ioChomp);
  b.processCritBayes(evC, ioChomp);
  const lc = b.takeInferenceLog();
  check('G-F01 遅延: 巻き戻された証拠への急所イベントは no-match', hasRec(lc, 'critPatch', 'no-match'));
  // 急所是正済みの証拠も巻き戻せる
  const scriptCritThenHH = () => {
    const e = scene();
    dmgStep(e, 'Garchomp', 'Rock Slide', amtRock, ioChomp);
    const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
    e.processCritInf(ev, ioChomp);
    e.processCritBayes(ev, ioChomp);
    hhEvent(e, 'p2: Rillaboom');
    e.takeInferenceLog();
    return e;
  };
  const c = scriptCritThenHH();
  check('G-F01 遅延: 急所是正済みの証拠も巻き戻され先行観測の場合と一致する', fingerprint(c, 'Garchomp') === fingerprint(a, 'Garchomp'));
}
// ============ G-F02-4: inf のみの multi 検出 (両経路の更新0) ============
{
  // inf 段階の呼び出し件数を数える
  const probe = makeFake(() => null);
  const pe = scene(probe);
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '', defAlive: 2 };
  pe.processDamageInf(ev, ioChomp);
  const infCalls = probe.calls.length;
  const fake = makeFake((a, d, m, o, idx) => idx < infCalls ? 'multi' : null);
  const est = scene(fake);
  const f0 = fingerprint(est, 'Garchomp');
  est.processDamageInf(ev, ioChomp);
  est.processDamageBayes(ev, ioChomp);
  const log = est.takeInferenceLog();
  check('G-F02-4: inf のみ multi の場合、両経路とも更新0', fingerprint(est, 'Garchomp') === f0 && hasRec(log, 'inf', 'multihit-suspended'), `infCalls=${infCalls}`);
  const evC = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  est.processCritInf(evC, ioChomp);
  est.processCritBayes(evC, ioChomp);
  check('G-F02-4: 保留された証拠の記録は残らず crit は no-match', hasRec(est.takeInferenceLog(), 'critPatch', 'no-match'));
}
// ============ G-F02-5: bayes のみの multi 検出 (inf 巻き戻し＋相殺ログ) ============
{
  const probe = makeFake(() => null);
  const pe = scene(probe);
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '', defAlive: 2 };
  pe.processDamageInf(ev, ioChomp);
  const infCalls = probe.calls.length;
  const fake = makeFake((a, d, m, o, idx) => idx >= infCalls ? 'multi' : null);
  const est = scene(fake);
  const f0 = fingerprint(est, 'Garchomp');
  est.processDamageInf(ev, ioChomp);
  est.processDamageBayes(ev, ioChomp);
  const log = est.takeInferenceLog();
  check('G-F02-5: bayes のみ multi の場合、両経路とも更新0 (到達証拠あり)', fake.calls.some(c => c.verdict === 'multi') && fingerprint(est, 'Garchomp') === f0);
  check('G-F02-5: 相殺ログが残る', hasRec(log, 'inf', 'multihit-suspended-rollback') && hasRec(log, 'damage', 'multihit-suspended'), JSON.stringify(log.map(r => r.trigger)));
}
// ============ G-F02-6: 仮説再計算のみの multi 検出 ============
{
  const probe = makeFake(() => null);
  const pe = scene(probe);
  const evOver = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: 9999, crit: false, w: '', t: '', defAlive: 2 };
  pe.processDamageInf(evOver, ioChomp);
  const infCalls = probe.calls.length;
  pe.processDamageBayes(evOver, ioChomp);
  const bayesPass1 = pe._debug().bayes.bySpecies['Garchomp'].cands.length;
  const fake = makeFake((a, d, m, o, idx) => (idx >= infCalls + bayesPass1 && a && a.item === 'Choice Band') ? 'multi' : null);
  const est = scene(fake);
  const f0 = fingerprint(est, 'Garchomp');
  est.processDamageInf(evOver, ioChomp);
  est.processDamageBayes(evOver, ioChomp);
  const ent = est._debug().bayes.bySpecies['Garchomp'];
  check('G-F02-6: 再計算のみ multi の場合、フラグは立たず状態不変', !ent.dmgFlag && fingerprint(est, 'Garchomp') === f0, `bayesPass1=${bayesPass1} inf=${infCalls} multi=${fake.calls.filter(c => c.verdict === 'multi').length}`);
}
// ============ G-F03-7: crit 再推論の inf 側のみ計算不能 ============
{
  // 正常な crit の collect 呼び出し件数を数える
  const probe = makeFake(() => null);
  const pe = scene(probe);
  dmgStep(pe, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 1);
  const before = probe.calls.length;
  const evC = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  pe.processCritInf(evC, ioChomp);
  const collectCalls = probe.calls.length - before;
  let failInf = true;
  let critSeen = 0;
  const fake = makeFake((a, d, m, o) => { if (failInf && o && o.crit) { critSeen++; if (critSeen <= collectCalls) return 'fail'; } return null; });
  const est = scene(fake);
  dmgStep(est, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 1);
  const fPre = fingerprint(est, 'Garchomp');
  est.processCritInf(evC, ioChomp);
  est.processCritBayes(evC, ioChomp);
  const log = est.takeInferenceLog();
  const cp = log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('G-F03-7: inf 側のみ失敗した場合、状態不変で critPatch は不成立', fingerprint(est, 'Garchomp') === fPre && !!cp && cp.trigger.applied === false, JSON.stringify(cp && cp.trigger));
  // 再試行 (失敗を止めると正しく適用できる)
  failInf = false;
  est.processCritInf(evC, ioChomp);
  est.processCritBayes(evC, ioChomp);
  const log2 = est.takeInferenceLog();
  const cp2 = log2.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('G-F03-9: 失敗後の再試行で正しく適用できる', !!cp2 && cp2.trigger.applied === true, JSON.stringify(cp2 && cp2.trigger));
}
// ============ G-F03-8: crit 再推論の bayes 側のみ計算不能 ============
{
  const probe = makeFake(() => null);
  const pe = scene(probe);
  dmgStep(pe, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 1);
  const before = probe.calls.length;
  const evC = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  pe.processCritInf(evC, ioChomp);
  const collectCalls = probe.calls.length - before;
  let critSeen = 0;
  let failBayes = true;
  const fake = makeFake((a, d, m, o) => { if (failBayes && o && o.crit) { critSeen++; if (critSeen > collectCalls) return 'fail'; } return null; });
  const est = scene(fake);
  dmgStep(est, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 1);
  const fPre = fingerprint(est, 'Garchomp');
  est.processCritInf(evC, ioChomp);
  est.processCritBayes(evC, ioChomp);
  const log = est.takeInferenceLog();
  const cp = log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('G-F03-8: bayes 側のみ失敗した場合、状態不変で critPatch は不成立', fingerprint(est, 'Garchomp') === fPre && !!cp && cp.trigger.applied === false && cp.trigger.bayes === false && cp.trigger.inf === false, JSON.stringify(cp && cp.trigger));
  // 再生一致: 同じ列を最初から再生すると最終状態が一致する
  const replay = () => {
    const e = scene();
    dmgStep(e, 'Garchomp', 'Rock Slide', amtRock, ioChomp, 1);
    e.processCritInf(evC, ioChomp);
    e.processCritBayes(evC, ioChomp);
    e.takeInferenceLog();
    return e;
  };
  const r1 = replay();
  failBayes = false;
  est.processCritInf(evC, ioChomp);
  est.processCritBayes(evC, ioChomp);
  est.takeInferenceLog();
  check('G-F03-9: 再試行後の状態は再生と一致する', fingerprint(est, 'Garchomp') === fingerprint(r1, 'Garchomp'));
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
