// MH-001-R1-C2: テスト専用シーム (deps.damageDistribution) を使った故障
// 注入テスト。R1-C では構成できなかった「ベイズの一部候補だけ計算不能」
// 「仮説の再計算だけ失敗」「急所再推論の途中失敗」「バックストップ単独
// の保留」を、差し替え関数の呼出記録 (到達証拠) と推論ログで検証する。
// あわせて巻き戻し方式の監査項目 (キー同一性・巻き戻し後の整合性・
// ログの見え方・例外時の防御) を確認する。各場面に対照実験 (注入なし
// では同じ証拠が通常どおり適用される) を含む。
// 実行: node tests/test_fault_injection.mjs (最後に ALL PASS と出す)
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

// 差し替え関数の工場: rule(atkSpec, defSpec, moveName, opts, callIndex) が
// 'fail' (計算不能を返す) / 'multi' (multi=true を強制) / 'malformed'
// (壊れた分布を返す) / null (実関数へ委譲) を返す。全呼出を記録する
function makeFake(rule) {
  const calls = [];
  const fn = (atkSpec, defSpec, moveName, opts) => {
    const verdict = rule ? rule(atkSpec, defSpec, moveName, opts, calls.length) : null;
    if (verdict === 'fail') { calls.push({ item: atkSpec && atkSpec.item, nature: atkSpec && atkSpec.nature, crit: !!(opts && opts.crit), result: 'fail' }); return { error: 'injected' }; }
    if (verdict === 'malformed') { calls.push({ item: atkSpec && atkSpec.item, nature: atkSpec && atkSpec.nature, crit: !!(opts && opts.crit), result: 'malformed' }); return { dist: { values: null, counts: null, total: 1 }, min: 0, max: 0, hits: 1, multi: false }; }
    const r = core.damageDistribution(atkSpec, defSpec, moveName, opts);
    if (verdict === 'multi' && r && r.dist) { calls.push({ item: atkSpec && atkSpec.item, nature: atkSpec && atkSpec.nature, crit: !!(opts && opts.crit), result: 'multi' }); return { ...r, multi: true, hits: Math.max(2, r.hits || 1) }; }
    calls.push({ item: atkSpec && atkSpec.item, nature: atkSpec && atkSpec.nature, crit: !!(opts && opts.crit), result: r && r.error ? 'error' : 'ok' });
    return r;
  };
  return { fn, calls };
}

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });
const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide', 'Earthquake'] });
const baseChomp = spec('Garchomp', 'Adamant', {});
const bogusBase = spec('Bogusmon', 'Adamant', {});
const amtRock = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];
const amtQuake = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Earthquake', { gameType: 'Singles' }).rolls[8];

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
const hasRec = (log, kind, reason) => log.some(r => r.trigger && r.trigger.kind === kind && r.trigger.reason === reason);

// ---- (a) ベイズの一部候補だけが計算不能 ----
{
  const fake = makeFake(atk => atk && atk.item === 'Life Orb' ? 'fail' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint(est, 'Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  const bayesStart = fake.calls.length;
  est.processDamageBayes(ev, io);
  const bayesCalls = fake.calls.slice(bayesStart);
  const log = est.takeInferenceLog();
  check('(a) 到達証拠: ベイズ計算で一部候補が失敗し他は成功した', bayesCalls.some(c => c.result === 'fail') && bayesCalls.some(c => c.result === 'ok'), JSON.stringify(bayesCalls.map(c => c.result)));
  check('(a) 証拠全体が保留され状態が不変', fingerprint(est, 'Garchomp') === before);
  check('(a) dist-unavailable が推論ログに残る', hasRec(log, 'damage', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
  // 対照実験: 注入なしでは同じ証拠が適用される
  const est2 = makeEst(makeFake(null).fn);
  est2.reset();
  const ent2 = est2.entry('Garchomp');
  est2.processDamageInf(ev, io);
  est2.processDamageBayes(ev, io);
  const log2 = est2.takeInferenceLog();
  check('(a) 対照: 注入なしでは適用される', log2.some(r => r.trigger && r.trigger.kind === 'damage' && r.trigger.applied === true) && ent2.used === 1);
}

// ---- (b) 仮説の再計算だけが失敗 ----
{
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: 9999, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  // ベイズ側の呼出窓: 初回計算 (候補数ぶん) の直後が再計算。再計算側の
  // Choice Band 持ち spec でのみ失敗させる
  const win = { from: Infinity, to: -Infinity };
  const fake2 = makeFake((atk, def, mv, opts, idx) => (idx >= win.from && idx <= win.to && atk && atk.item === 'Choice Band') ? 'fail' : null);
  const estB = makeEst(fake2.fn);
  estB.reset();
  const entB = estB.entry('Garchomp');
  const beforeB = fingerprint(estB, 'Garchomp');
  estB.processDamageInf(ev, io);
  const startB = fake2.calls.length;
  win.from = startB + entB.cands.length;
  win.to = startB + 2 * entB.cands.length - 1;
  estB.processDamageBayes(ev, io);
  const bc = fake2.calls.slice(startB);
  const pass1 = bc.slice(0, entB.cands.length), recomp = bc.slice(entB.cands.length);
  const logB = estB.takeInferenceLog();
  check('(b) 到達証拠: 初回計算は全件成功した', pass1.length === entB.cands.length && pass1.every(c => c.result === 'ok'), JSON.stringify(pass1.map(c => c.result)));
  check('(b) 到達証拠: 再計算の呼出が発生し Band 持ちで失敗した', recomp.some(c => c.result === 'fail' && c.item === 'Choice Band'), JSON.stringify(recomp.map(c => [c.item, c.result])));
  check('(b) フラグが残らず証拠全体が保留され状態が不変', !entB.dmgFlag && fingerprint(estB, 'Garchomp') === beforeB);
  check('(b) dist-unavailable が推論ログに残る', hasRec(logB, 'damage', 'dist-unavailable'), JSON.stringify(logB.map(r => r.trigger)));
  // 対照実験: 注入なしでは仮説が実際に立つ
  const est2 = makeEst(makeFake(null).fn);
  est2.reset();
  const ent2 = est2.entry('Garchomp');
  est2.processDamageInf(ev, io);
  est2.processDamageBayes(ev, io);
  est2.takeInferenceLog();
  check('(b) 対照: 注入なしでは Choice Band の仮説が立つ', ent2.dmgFlag === 'Choice Band', String(ent2.dmgFlag));
}

// ---- (c) 急所再推論の途中で失敗 ----
{
  const fake = makeFake((atk, def, mv, opts) => (opts && opts.crit === true && atk && atk.item === 'Life Orb') ? 'fail' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
  est.takeInferenceLog();
  const applied = fingerprint(est, 'Garchomp');
  const critStart = fake.calls.length;
  const critEv = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  est.processCritInf(critEv, io);
  const bayesCritStart = fake.calls.length;
  est.processCritBayes(critEv, io);
  const critCalls = fake.calls.slice(critStart);
  const captureCalls = fake.calls.slice(bayesCritStart);
  const log = est.takeInferenceLog();
  check('(c) 到達証拠: inf 再生は成功し capture で一部候補が失敗した', critCalls.slice(0, bayesCritStart - critStart).every(c => c.result !== 'fail') && captureCalls.some(c => c.result === 'fail') && captureCalls.some(c => c.result === 'ok'), JSON.stringify(captureCalls.map(c => c.result)));
  check('(c) 是正が中断され適用済みの状態が完全に維持される', fingerprint(est, 'Garchomp') === applied);
  const patch = log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('(c) critPatch は dist-unavailable で未適用と記録される', !!patch && patch.trigger.applied === false && patch.trigger.reason === 'dist-unavailable', JSON.stringify(patch && patch.trigger));
  // 対照実験: 注入なしでは是正が適用される
  const est2 = makeEst(makeFake(null).fn);
  est2.reset();
  const ent2 = est2.entry('Garchomp');
  est2.processDamageInf(ev, io);
  est2.processDamageBayes(ev, io);
  est2.takeInferenceLog();
  const postsBefore2 = ent2.cands.map(c => c.post);
  est2.processCritInf(critEv, io);
  est2.processCritBayes(critEv, io);
  const log2 = est2.takeInferenceLog();
  const patch2 = log2.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('(c) 対照: 注入なしでは是正が適用される', !!patch2 && patch2.trigger.applied === true && ent2.cands.some((c, i) => c.post !== postsBefore2[i]));
}

// ---- (d) バックストップ単独の保留 ----
{
  const fake = makeFake(() => 'multi');
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint(est, 'Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
  const log = est.takeInferenceLog();
  check('(d) 到達証拠: 事前判定を通過し分布関数が実際に呼ばれた', fake.calls.length > 0, 'calls=' + fake.calls.length);
  check('(d) multi 分布で multihit-suspended として保留される', hasRec(log, 'inf', 'multihit-suspended'), JSON.stringify(log.map(r => r.trigger)));
  check('(d) 推定状態が変わらない', fingerprint(est, 'Garchomp') === before);
  // 対比: 事前判定で止まる技では分布呼出が0件 (ゲートはシームに依存しない)
  est.reset();
  est.entry('Rillaboom');
  const callsBefore = fake.calls.length;
  const evB = { turn: 1, atk: 'p2: Rillaboom', def: 'p1: Venusaur', move: 'Bullet Seed', amt: 50, crit: false, w: '', t: '' };
  const baseRilla = spec('Rillaboom', 'Adamant', {});
  est.processDamageInf(evB, { myDef: myVenusaur, basesAtk: [baseRilla] });
  check('(d) 対比: ゲート対象技では分布呼出が0件', fake.calls.length === callsBefore, 'calls=' + (fake.calls.length - callsBefore));
  // 対照実験: multi 強制なしでは同じ証拠が適用される
  const est2 = makeEst(makeFake(null).fn);
  est2.reset();
  const ent2 = est2.entry('Garchomp');
  est2.processDamageInf(ev, io);
  est2.processDamageBayes(ev, io);
  const log2 = est2.takeInferenceLog();
  check('(d) 対照: 注入なしでは適用される', log2.some(r => r.trigger && r.trigger.kind === 'damage' && r.trigger.applied === true) && ent2.used === 1);
}

// ---- 監査 (e): キー不一致では巻き戻しが発動しない ----
{
  const est = makeEst(null);
  est.reset();
  est.entry('Garchomp');
  const evA = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const evB = { turn: 2, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Earthquake', amt: amtQuake, crit: false, w: '', t: '' };
  est.processDamageInf(evA, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageInf(evB, { myDef: myVenusaur, basesAtk: [baseChomp] });
  const afterInfAB = fingerprint(est, 'Garchomp');
  // A のベイズを、不能になる文脈と明示 opts で後から呼ぶ (UI の実際の
  // 呼出順序では発生しない割り込みパターン)
  est.processDamageBayes(evA, { myDef: myVenusaur, baseAtk: bogusBase }, { gameType: 'Singles' });
  const log = est.takeInferenceLog();
  check('(e) キー不一致: A の inf は巻き戻されない', fingerprint(est, 'Garchomp') === afterInfAB);
  check('(e) キー不一致: 相殺エントリは記録されない', !hasRec(log, 'inf', 'dist-unavailable-rollback'), JSON.stringify(log.map(r => r.trigger)));
  check('(e) A のベイズ保留自体は記録される', hasRec(log, 'damage', 'dist-unavailable'));
}

// ---- 監査 (f)(g): 巻き戻し後の整合性とログの見え方 ----
{
  const est = makeEst(null);
  est.reset();
  const ent = est.entry('Garchomp');
  const before = fingerprint(est, 'Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: bogusBase });
  const log = est.takeInferenceLog();
  check('(f) 巻き戻し後: used を含む推定状態が処理前に戻る', fingerprint(est, 'Garchomp') === before);
  const infAppliedIdx = log.findIndex(r => r.trigger && r.trigger.kind === 'inf' && r.trigger.applied === true);
  const rollbackIdx = log.findIndex(r => r.trigger && r.trigger.kind === 'inf' && r.trigger.reason === 'dist-unavailable-rollback');
  check('(g) ログ: inf 適用の後に相殺エントリが続き、適用済みのまま残らない', infAppliedIdx >= 0 && rollbackIdx > infAppliedIdx, JSON.stringify(log.map(r => r.trigger)));
  check('(g) ログ: damage の適用済み記録は無い', !log.some(r => r.trigger && r.trigger.kind === 'damage' && r.trigger.applied === true));
  // pendingOpts が下りていること: 同じ証拠のベイズ再呼出は無動作
  const postsNow = ent.cands.map(c => c.post);
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  check('(f) 巻き戻し後: pendingOpts が下りてベイズ再呼出が無動作', ent.cands.every((c, i) => c.post === postsNow[i]) && ent.used === 0);
  est.takeInferenceLog();
  // dmgRecord が無いこと: 急所イベントは no-match
  est.processCritInf({ turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' }, { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp });
  const log2 = est.takeInferenceLog();
  check('(f) 巻き戻し後: dmgRecord が無く critPatch は no-match', hasRec(log2, 'critPatch', 'no-match'), JSON.stringify(log2.map(r => r.trigger)));
  // 後続の正常な証拠とその急所是正が通常どおり効くこと (記録連鎖の健全性)
  const ev2 = { turn: 2, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Earthquake', amt: amtQuake, crit: false, w: '', t: '' };
  const io2 = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev2, io2);
  est.processDamageBayes(ev2, io2);
  est.processCritInf({ turn: 2, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Earthquake' }, io2);
  est.processCritBayes({ turn: 2, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Earthquake' }, io2);
  const log3 = est.takeInferenceLog();
  const patch3 = log3.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('(f) 巻き戻し後: 後続の証拠と急所是正が通常どおり効く', !!patch3 && patch3.trigger.applied === true && ent.used >= 1, JSON.stringify(patch3 && patch3.trigger));
}

// ---- 監査 (h): dmgDist 以外の例外でも部分状態が残らない ----
{
  // inf 側: 壊れた分布で distMass が例外を投げる
  const fakeBad = makeFake(() => 'malformed');
  const est = makeEst(fakeBad.fn);
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint(est, 'Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  let threw = false;
  try { est.processDamageInf(ev, io); } catch (e) { threw = true; }
  check('(h) inf 例外: 例外は伝播する', threw);
  check('(h) inf 例外: 推定状態が変わらない', fingerprint(est, 'Garchomp') === before);
  const ent = est._debug().bayes.bySpecies['Garchomp'];
  const postsNow = ent.cands.map(c => c.post);
  est.processDamageBayes(ev, io);
  check('(h) inf 例外: pendingOpts が掃除されベイズは無動作', ent.cands.every((c, i) => c.post === postsNow[i]));
  est.takeInferenceLog();
  // bayes 側: inf は正常、ベイズ計算の途中で例外
  let malformed = false;
  const fakeSw = makeFake(() => malformed ? 'malformed' : null);
  const est2 = makeEst(fakeSw.fn);
  est2.reset();
  est2.entry('Garchomp');
  const before2 = fingerprint(est2, 'Garchomp');
  est2.processDamageInf(ev, io);
  malformed = true;
  let threw2 = false;
  try { est2.processDamageBayes(ev, io); } catch (e) { threw2 = true; }
  const logB = est2.takeInferenceLog();
  check('(h) bayes 例外: 例外は伝播する', threw2);
  check('(h) bayes 例外: inf まで巻き戻り状態が戻る', fingerprint(est2, 'Garchomp') === before2);
  check('(h) bayes 例外: 相殺エントリが記録される', hasRec(logB, 'inf', 'dist-unavailable-rollback'), JSON.stringify(logB.map(r => r.trigger)));
  malformed = false;
  const ent2 = est2._debug().bayes.bySpecies['Garchomp'];
  est2.processDamageInf(ev, io);
  est2.processDamageBayes(ev, io);
  check('(h) bayes 例外: その後も通常どおり推定できる', ent2.used === 1);
}

// ---- 監査 (i): 急所再推論の capture 中の例外でも適用済みの状態が保たれる ----
{
  const fake = makeFake((atk, def, mv, opts) => (opts && opts.crit === true && atk && atk.item === 'Life Orb') ? 'malformed' : null);
  const est = makeEst(fake.fn);
  est.reset();
  est.entry('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
  est.takeInferenceLog();
  const applied = fingerprint(est, 'Garchomp');
  const critEv = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  est.processCritInf(critEv, io);
  let threw = false;
  try { est.processCritBayes(critEv, io); } catch (e) { threw = true; }
  check('(i) crit 例外: 例外は伝播する', threw);
  check('(i) crit 例外: 適用済みの状態 (事後・inf 履歴) が完全に維持される', fingerprint(est, 'Garchomp') === applied);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
