// MH-001-R1-B: 複数ヒット証拠の推定利用停止 (保留ゲート) の検証。
// 候補集合・事後分布・仮説フラグが保留対象の証拠で変わらないこと、
// 保留理由が推論ログに残ること、単発技の挙動が従来と一致することを見る。
// 実行: node tests/test_multihit_gate.mjs (最後に ALL PASS と出す)
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const eng = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
const { gen, statTable, damageRolls, damageDistribution, withCurHP } = core;

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
const est = eng.createEstimator({ effSpecies, getData: () => ({ POKEDB_PARSED, USAGE_SETS, META_SETS, META_SETS_LOADED: true, NAMES, VGC_SETS, SPECIES_MOVES }) });

const blank = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
const boosts0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
const spec = (species, nature, sp, extra = {}) => ({ species, nature, sp: { ...blank, ...sp }, item: '', ability: '', moves: [], boosts: { ...boosts0 }, status: '', curHPPercent: 100, mega: false, ...extra });

// 推定状態の指紋: 候補集合 (同定情報)・事後分布・仮説フラグ・使用回数と、
// inf 側の交差状態 (feasible 集合) をまとめて比較可能にする
function fingerprint(species) {
  const ent = est._debug().bayes.bySpecies[species];
  const ie = est._debug().inference.bySpecies[species];
  const ser = v => v instanceof Set ? [...v].sort() : v;
  return JSON.stringify({
    cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), c.post]) : null,
    dmgFlag: ent ? ent.dmgFlag : null, speFlag: ent ? ent.speFlag : null, used: ent ? ent.used : null,
    inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
  });
}
const suspendedRec = log => log.find(r => r.trigger && r.trigger.reason === 'multihit-suspended');

const myBlastoise = spec('Blastoise', 'Modest', { hp: 2, spa: 32, spe: 32 }, { item: 'Blastoisinite', ability: 'Rain Dish' });
const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });

// ---- 1. 可変ヒット技 (相手の Bullet Seed, 実数観測) で状態が変わらない ----
{
  est.reset();
  const base = spec('Rillaboom', 'Adamant', {});
  est.entry('Rillaboom');
  const before = fingerprint('Rillaboom');
  const ev = { turn: 1, atk: 'p2: Rillaboom', def: 'p1: Blastoise', move: 'Bullet Seed', amt: 100, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myBlastoise, basesAtk: [base] });
  est.processDamageBayes(ev, { myDef: myBlastoise, baseAtk: base });
  const log = est.takeInferenceLog();
  check('1: Bullet Seed で推定状態が変わらない', fingerprint('Rillaboom') === before);
  check('1: 保留理由が推論ログに残る', !!suspendedRec(log), JSON.stringify(log.map(r => r.trigger)));
  // ---- 3. 急所イベント経由でも遮断が維持される (dmgRecord 自体が無い) ----
  est.processCritInf({ turn: 1, atk: 'p2: Rillaboom', def: 'p1: Blastoise', move: 'Bullet Seed' }, {});
  est.processCritBayes({ turn: 1, atk: 'p2: Rillaboom', def: 'p1: Blastoise', move: 'Bullet Seed' }, {});
  const log2 = est.takeInferenceLog();
  check('3: crit 経由でも推定状態が変わらない', fingerprint('Rillaboom') === before);
  check('3: critPatch は no-match で終わる (記録が存在しない)', log2.some(r => r.trigger.kind === 'critPatch' && r.trigger.applied === false && r.trigger.reason === 'no-match'), JSON.stringify(log2.map(r => r.trigger)));
  // ---- 4. 全候補の最大超過の複数ヒット観測でも dmgFlag が発生しない ----
  const evBig = { turn: 2, atk: 'p2: Rillaboom', def: 'p1: Blastoise', move: 'Bullet Seed', amt: 9999, crit: false, w: '', t: '' };
  est.processDamageInf(evBig, { myDef: myBlastoise, basesAtk: [base] });
  est.processDamageBayes(evBig, { myDef: myBlastoise, baseAtk: base });
  const ent = est._debug().bayes.bySpecies['Rillaboom'];
  check('4: 最大超過の複数ヒット観測でも dmgFlag が発生しない', !ent.dmgFlag && fingerprint('Rillaboom') === before);
}

// ---- 2a. 固定ヒット技 (Double Kick) でも保留される ----
{
  est.reset();
  const base = spec('Hitmonlee', 'Adamant', {});
  est.entry('Hitmonlee');
  const before = fingerprint('Hitmonlee');
  const ev = { turn: 1, atk: 'p2: Hitmonlee', def: 'p1: Blastoise', move: 'Double Kick', amt: 60, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myBlastoise, basesAtk: [base] });
  est.processDamageBayes(ev, { myDef: myBlastoise, baseAtk: base });
  check('2a: Double Kick で推定状態が変わらない', fingerprint('Hitmonlee') === before);
  check('2a: 保留理由が推論ログに残る', !!suspendedRec(est.takeInferenceLog()));
}

// ---- 2b. moveSpec 明示の呼び出しでも保留される ----
{
  est.reset();
  const base = spec('Rillaboom', 'Adamant', {});
  est.entry('Rillaboom');
  const before = fingerprint('Rillaboom');
  const ev = { turn: 1, atk: 'p2: Rillaboom', def: 'p1: Blastoise', move: 'Bullet Seed', amt: 100, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myBlastoise, basesAtk: [base] }, { moveSpec: 5, gameType: 'Singles' });
  est.processDamageBayes(ev, { myDef: myBlastoise, baseAtk: base }, { moveSpec: 5, gameType: 'Singles' });
  const log = est.takeInferenceLog();
  check('2b: moveSpec 明示でも推定状態が変わらない', fingerprint('Rillaboom') === before);
  check('2b: ベイズ側でも保留が記録される', log.some(r => r.trigger.kind === 'damage' && r.trigger.reason === 'multihit-suspended'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- 2c. Parental Bond の攻撃側では単発技 (Body Slam) でも保留される ----
{
  // 前提確認: メガカンガルーの Body Slam は分布が multi=true になる
  const megaK = spec('Kangaskhan', 'Adamant', { atk: 32 }, { ability: 'Parental Bond', mega: true, megaSpecies: 'Kangaskhan-Mega' });
  const dd = damageDistribution(withCurHP(megaK), withCurHP(myBlastoise), 'Body Slam', { gameType: 'Singles' });
  check('2c 前提: Parental Bond の単発技は分布が multi=true', dd.multi === true && dd.hits === 2, JSON.stringify({ multi: dd.multi, hits: dd.hits }));
  est.reset();
  const base = spec('Kangaskhan', 'Adamant', {}, { ability: 'Parental Bond', mega: true, megaSpecies: 'Kangaskhan-Mega' });
  est.entry('Kangaskhan');
  const before = fingerprint('Kangaskhan');
  const ev = { turn: 1, atk: 'p2: Kangaskhan', def: 'p1: Blastoise', move: 'Body Slam', amt: 50, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myBlastoise, basesAtk: [base] });
  est.processDamageBayes(ev, { myDef: myBlastoise, baseAtk: base });
  check('2c: Parental Bond の Body Slam で推定状態が変わらない', fingerprint('Kangaskhan') === before);
  check('2c: 保留理由が推論ログに残る', !!suspendedRec(est.takeInferenceLog()));
}

// ---- 1b. 自分方向の複数ヒット技 (Triple Axel) でも保留される ----
{
  est.reset();
  const myWeavile = spec('Weavile', 'Adamant', { atk: 32 }, { ability: 'Pressure', moves: ['Triple Axel'] });
  const base = spec('Garchomp', 'Hardy', {});
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p1: Weavile', def: 'p2: Garchomp', move: 'Triple Axel', pct: 40, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myAtk: myWeavile, basesDef: [base] });
  est.processDamageBayes(ev, { myAtk: myWeavile, baseDef: base });
  check('1b: 自分方向の Triple Axel で推定状態が変わらない', fingerprint('Garchomp') === before);
  check('1b: 保留理由が推論ログに残る', !!suspendedRec(est.takeInferenceLog()));
}

// ---- 5. 単発技の回帰: 固定場面ハッシュが MH-001 検収時と一致する ----
{
  est.reset();
  const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide', 'Earthquake'] });
  const baseChomp = spec('Garchomp', 'Adamant', {});
  const ent = est.entry('Garchomp');
  const rolls1 = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls;
  const amt = rolls1[10];
  const ev1 = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt, crit: false };
  est.processDamageInf(ev1, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev1, { myDef: myVenusaur, baseAtk: baseChomp });
  const truthHp = statTable('Garchomp').hp.find(r => r.nature === 'Adamant' && r.sp === 0).value;
  const rolls2 = damageRolls(withCurHP(myVenusaur), withCurHP(truthChomp), 'Earth Power', { gameType: 'Singles' }).rolls;
  const pct = Math.round(rolls2[7] / truthHp * 100);
  const ev2 = { turn: 1, atk: 'p1: Venusaur', def: 'p2: Garchomp', move: 'Earth Power', pct, crit: false };
  est.processDamageInf(ev2, { myAtk: myVenusaur, basesDef: [baseChomp] });
  est.processDamageBayes(ev2, { myAtk: myVenusaur, baseDef: baseChomp });
  const canon = JSON.stringify({ posts: ent.cands.map(c => c.post), log: est.takeInferenceLog().map(r => r.trigger) });
  const hash = createHash('sha256').update(canon).digest('hex');
  check('5: 単発固定場面のハッシュが一致', hash === '688c01d9a1bfc2d9a58b564c046756b02a96e7c2e3ebd6b2638f998232e8c4f0', hash);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
