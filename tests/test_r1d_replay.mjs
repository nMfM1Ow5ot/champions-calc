// MH-001-R1-D: 既存推定結果の撤回・再計算の検証。同一の観測イベント
// 履歴を3条件で再生して比較する。
//   A: 公開 rev 20261124_1101 の旧版エンジン (隔離環境 /tmp/r1d_old/。
//      R1D_OLD_DIR で変更可)。UI の guardEv と同様にイベント単位で
//      例外を捕捉して継続する
//   B: 修正版 (現行ローカル) の新規インスタンス
//   C: 移行の再現 — 旧版で履歴を処理した状態を初期化 (新規インスタンス
//      への切替 = UI の resetInference 相当) し、修正版で同じ履歴を再生
// 本番ファイルは変更しない。実行: node tests/test_r1d_replay.mjs
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const OLD_DIR = process.env.R1D_OLD_DIR || '/tmp/r1d_old';
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const engNew = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
if (!fs.existsSync(OLD_DIR + '/estimate_engine.mjs')) { console.log('FAIL 旧版エンジンが ' + OLD_DIR + ' にありません'); process.exit(1); }
const engOld = await import(pathToFileURL(OLD_DIR + '/estimate_engine.mjs').href);
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

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });
const bogusVenusaur = spec('Venusaur', 'BogusNature', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });
const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide'] });
const baseChomp = spec('Garchomp', 'Adamant', {});
const bogusBase = spec('Bogusmon', 'Adamant', {});
const truthRilla = spec('Rillaboom', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Grassy Surge', moves: ['Bullet Seed'] });
const baseRilla = spec('Rillaboom', 'Adamant', {});
const kangaExtra = { item: 'Kangaskhanite', ability: 'Parental Bond', mega: true, megaSpecies: 'Kangaskhan-Mega', megaAbility: 'Parental Bond' };
const truthKanga = spec('Kangaskhan', 'Adamant', { atk: 32, spe: 32 }, { ...kangaExtra, moves: ['Body Slam'] });
const baseKanga = spec('Kangaskhan', 'Adamant', {}, kangaExtra);

// 実分布から代表値を取る (複数ヒットは既定ヒット数の分布の最頻値)
function distMode(atk, def, move) {
  const dd = damageDistribution(withCurHP(atk), withCurHP(def), move, { gameType: 'Singles' });
  let best = null, bc = -1;
  dd.dist.values.forEach((v, i) => { if (dd.dist.counts[i] > bc) { bc = dd.dist.counts[i]; best = v; } });
  return best;
}
const amtSeed = distMode(truthRilla, myVenusaur, 'Bullet Seed');
const amtSlam = (() => { const dd = damageDistribution(withCurHP(truthKanga), withCurHP(myVenusaur), 'Body Slam', { gameType: 'Singles' }); return dd.max; })();
const amtRock = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];

const SPECIES = ['Rillaboom', 'Garchomp', 'Kangaskhan'];
function fingerprint(est) {
  const out = {};
  for (const sp of SPECIES) {
    const ent = est._debug().bayes.bySpecies[sp];
    const ie = est._debug().inference.bySpecies[sp];
    const ser = v => v instanceof Set ? [...v].sort() : v;
    out[sp] = {
      cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), c.post]) : null,
      dmgFlag: ent ? ent.dmgFlag || null : null, used: ent ? ent.used : null,
      inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
    };
  }
  return JSON.stringify(out);
}

// 同一の観測イベント履歴。各ステップは呼出の列で、runner が guardEv
// 相当の捕捉をしながら実行し、ステップごとの状態控えと例外を記録する
function buildScript() {
  const dmg = (turn, atkSp, defSp, move, amt, ctx) => ([
    ['inf', est => est.processDamageInf({ turn, atk: 'p2: ' + atkSp, def: 'p1: ' + defSp, move, amt, crit: false, w: '', t: '' }, ctx)],
    ['bayes', est => est.processDamageBayes({ turn, atk: 'p2: ' + atkSp, def: 'p1: ' + defSp, move, amt, crit: false, w: '', t: '' }, ctx)],
  ]);
  const crit = (turn, atkSp, defSp, move, ctx) => ([
    ['critInf', est => est.processCritInf({ turn, atk: 'p2: ' + atkSp, def: 'p1: ' + defSp, move }, ctx)],
    ['critBayes', est => est.processCritBayes({ turn, atk: 'p2: ' + atkSp, def: 'p1: ' + defSp, move }, ctx)],
  ]);
  const ioRilla = { myDef: myVenusaur, basesAtk: [baseRilla], baseAtk: baseRilla };
  const ioKanga = { myDef: myVenusaur, basesAtk: [baseKanga], baseAtk: baseKanga };
  const ioChomp = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  const ioChompBogusBase = { myDef: myVenusaur, basesAtk: [baseChomp, bogusBase], baseAtk: baseChomp };
  const ioChompBogusDef = { myDef: bogusVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  return [
    { name: 's1-bullet-seed', calls: dmg(1, 'Rillaboom', 'Venusaur', 'Bullet Seed', amtSeed, ioRilla) },
    { name: 's2-bullet-seed-over', calls: dmg(2, 'Rillaboom', 'Venusaur', 'Bullet Seed', 9999, ioRilla) },
    { name: 's3-body-slam-pb', calls: dmg(3, 'Kangaskhan', 'Venusaur', 'Body Slam', amtSlam, ioKanga) },
    { name: 's4-unavailable-throw', calls: dmg(4, 'Garchomp', 'Venusaur', 'Rock Slide', amtRock, ioChompBogusBase) },
    { name: 's5-unavailable-error', calls: dmg(5, 'Garchomp', 'Venusaur', 'Rock Slide', amtRock, ioChompBogusDef) },
    { name: 's6-crit-multihit', calls: crit(1, 'Rillaboom', 'Venusaur', 'Bullet Seed', ioRilla) },
    { name: 's6b-crit-unavailable', calls: crit(4, 'Garchomp', 'Venusaur', 'Rock Slide', ioChompBogusBase) },
    { name: 's7-valid-after-invalid', calls: dmg(6, 'Garchomp', 'Venusaur', 'Rock Slide', amtRock, ioChomp) },
  ];
}

function runScript(eng, script) {
  const est = eng.createEstimator({ effSpecies, getData });
  est.reset();
  for (const sp of SPECIES) est.entry(sp);
  const initial = fingerprint(est);
  const steps = [];
  const throws = [];
  for (const step of script) {
    for (const [label, fn] of step.calls) {
      try { fn(est); } catch (e) { throws.push(step.name + '/' + label + ': ' + (e && e.message ? e.message.slice(0, 60) : String(e))); }
    }
    steps.push({ name: step.name, fp: fingerprint(est), log: est.takeInferenceLog() });
  }
  return { est, initial, steps, throws };
}
const trigSeq = steps => steps.flatMap(s => s.log.map(r => [r.species, r.trigger && r.trigger.kind, r.trigger && r.trigger.applied, r.trigger && r.trigger.reason, r.trigger && r.trigger.move]));
const stepLog = (run, name) => run.steps.find(s => s.name === name).log;
const fpAt = (run, name) => JSON.parse(run.steps.find(s => s.name === name).fp);
const hasRec = (log, kind, reason) => log.some(r => r.trigger && r.trigger.kind === kind && (reason === undefined || r.trigger.reason === reason));

const script = buildScript();
const runA = runScript(engOld, script);
const runB = runScript(engNew, script);
const runB2 = runScript(engNew, script);
// C: 旧版で処理した後に初期化 (インスタンス切替) して修正版で再生 ×2
runScript(engOld, script);
const runC = runScript(engNew, script);
runScript(engOld, script);
const runC2 = runScript(engNew, script);

const initB = JSON.parse(runB.initial);
const initA = JSON.parse(runA.initial);
check('前提: A と B の初期候補集合が一致する', JSON.stringify(initA) === JSON.stringify(initB));

// ---- 対象1・2: 複数ヒット技による不当な候補排除・事後更新 ----
{
  const a1 = fpAt(runA, 's1-bullet-seed'), b1 = fpAt(runB, 's1-bullet-seed');
  check('対象1: A では inf の交差が進む (ハード除外が発生)', !!(a1.Rillaboom.inf && a1.Rillaboom.inf.used > (initA.Rillaboom.inf ? initA.Rillaboom.inf.used : 0)), JSON.stringify(a1.Rillaboom.inf));
  check('対象1: B では inf が進まない', JSON.stringify(b1.Rillaboom.inf) === JSON.stringify(initB.Rillaboom.inf));
  check('対象2: A では事後が動く', JSON.stringify(a1.Rillaboom.cands) !== JSON.stringify(initA.Rillaboom.cands));
  check('対象2: B では事後が動かない', JSON.stringify(b1.Rillaboom.cands) === JSON.stringify(initB.Rillaboom.cands));
  check('対象2: B では multihit-suspended が記録される', hasRec(stepLog(runB, 's1-bullet-seed'), 'inf', 'multihit-suspended') || hasRec(stepLog(runB, 's1-bullet-seed'), 'damage', 'multihit-suspended'));
}
// ---- 対象3: 複数ヒット観測による dmgFlag の誤発生 ----
{
  const a2 = fpAt(runA, 's2-bullet-seed-over'), b2 = fpAt(runB, 's2-bullet-seed-over');
  check('対象3: A では dmgFlag が誤発生する', !!a2.Rillaboom.dmgFlag, String(a2.Rillaboom.dmgFlag));
  check('対象3: B では dmgFlag が発生しない', !b2.Rillaboom.dmgFlag);
}
// ---- 対象4: Parental Bond の追加ヒット ----
{
  const a3 = fpAt(runA, 's3-body-slam-pb'), b3 = fpAt(runB, 's3-body-slam-pb');
  check('対象4: A では2ヒット分布で事後が動く', JSON.stringify(a3.Kangaskhan.cands) !== JSON.stringify(initA.Kangaskhan.cands));
  check('対象4: B では保留され事後が動かない', JSON.stringify(b3.Kangaskhan.cands) === JSON.stringify(initB.Kangaskhan.cands));
  check('対象4: B では multihit-suspended が記録される', hasRec(stepLog(runB, 's3-body-slam-pb'), 'inf', 'multihit-suspended') || hasRec(stepLog(runB, 's3-body-slam-pb'), 'damage', 'multihit-suspended'));
}
// ---- 対象5: 計算不能を含むダメージ証拠 ----
{
  check('対象5: A では例外が発生する', runA.throws.some(t => t.startsWith('s4-unavailable-throw')), JSON.stringify(runA.throws));
  check('対象5: B では例外が発生しない', runB.throws.length === 0, JSON.stringify(runB.throws));
  const bPre = fpAt(runB, 's3-body-slam-pb'), b4 = fpAt(runB, 's4-unavailable-throw'), b5 = fpAt(runB, 's5-unavailable-error');
  check('対象5: B では証拠全体が保留され状態が保たれる (例外型)', JSON.stringify(b4.Garchomp) === JSON.stringify(bPre.Garchomp));
  check('対象5: B では証拠全体が保留され状態が保たれる (error 型)', JSON.stringify(b5.Garchomp) === JSON.stringify(b4.Garchomp));
  check('対象5: B では dist-unavailable が記録される', hasRec(stepLog(runB, 's4-unavailable-throw'), 'inf', 'dist-unavailable') && hasRec(stepLog(runB, 's5-unavailable-error'), 'inf', 'dist-unavailable') || hasRec(stepLog(runB, 's5-unavailable-error'), 'damage', 'dist-unavailable'));
  check('対象5: A には dist-unavailable の記録概念がない', !runA.steps.some(s => hasRec(s.log, 'inf', 'dist-unavailable') || hasRec(s.log, 'damage', 'dist-unavailable')));
}
// ---- 対象6: 急所イベントによる後付け再推論 ----
{
  const aLog = stepLog(runA, 's6-crit-multihit'), bLog = stepLog(runB, 's6-crit-multihit');
  const aPatch = aLog.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('対象6: A では複数ヒット証拠への critPatch が適用される', !!aPatch && aPatch.trigger.applied === true, JSON.stringify(aPatch && aPatch.trigger));
  check('対象6: B では critPatch は no-match で状態が変わらない', hasRec(bLog, 'critPatch', 'no-match') && JSON.stringify(fpAt(runB, 's6-crit-multihit')) === JSON.stringify(fpAt(runB, 's5-unavailable-error')));
  const bLog2 = stepLog(runB, 's6b-crit-unavailable');
  check('対象6: B では計算不能証拠への critPatch も no-match', hasRec(bLog2, 'critPatch', 'no-match'), JSON.stringify(bLog2.map(r => r.trigger)));
}
// ---- 対象7: 無効な証拠の後に有効な証拠が続く場合 ----
{
  const b7 = fpAt(runB, 's7-valid-after-invalid'), b6 = fpAt(runB, 's6b-crit-unavailable');
  check('対象7: B では後続の正常な単発証拠が通常どおり適用される', b7.Garchomp.used > b6.Garchomp.used && JSON.stringify(b7.Garchomp.cands) !== JSON.stringify(b6.Garchomp.cands), `used ${b6.Garchomp.used} -> ${b7.Garchomp.used}`);
  const dmg7 = stepLog(runB, 's7-valid-after-invalid').find(r => r.trigger && r.trigger.kind === 'damage');
  check('対象7: damage の適用記録が残る', !!dmg7 && dmg7.trigger.applied === true, JSON.stringify(dmg7 && dmg7.trigger));
}
// ---- 対象8: 再生の冪等性 (B・C の複数回繰り返し) ----
{
  const finalB = runB.steps[runB.steps.length - 1].fp;
  check('対象8: B の再再生が冪等に一致する', runB2.steps[runB2.steps.length - 1].fp === finalB);
  check('対象8: C (旧版処理→初期化→修正版再生) が B と一致する', runC.steps[runC.steps.length - 1].fp === finalB);
  check('対象8: C の繰り返しも B と一致する', runC2.steps[runC2.steps.length - 1].fp === finalB);
  check('対象8: 推論ログのエントリ列も B と C で一致する', JSON.stringify(trigSeq(runC.steps)) === JSON.stringify(trigSeq(runB.steps)) && JSON.stringify(trigSeq(runB2.steps)) === JSON.stringify(trigSeq(runB.steps)));
  check('対象8: A の最終状態は B と異なる (誤りが残存する)', runA.steps[runA.steps.length - 1].fp !== finalB);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
