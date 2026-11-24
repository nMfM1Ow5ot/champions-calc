// MH-001-R1-C: 計算不能 (分布が得られない) と確率質量0 の分離・原子的
// 更新の検証。計算不能が一部でも混ざれば証拠全体が保留され、候補集合・
// 事後分布・仮説フラグ・inf 交差状態が更新前に戻ること、質量0 は従来の
// 推論規則どおり処理されることを、実際の推定経路で確認する。
// 実行: node tests/test_dist_unavailable.mjs (最後に ALL PASS と出す)
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const core = await import(pathToFileURL(ROOT + '/core.mjs').href);
const eng = await import(pathToFileURL(ROOT + '/estimate_engine.mjs').href);
const { gen, statTable, damageRolls, withCurHP } = core;

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

function fingerprint(species) {
  const ent = est._debug().bayes.bySpecies[species];
  const ie = est._debug().inference.bySpecies[species];
  const ser = v => v instanceof Set ? [...v].sort() : v;
  return JSON.stringify({
    cands: ent ? ent.cands.map(c => [c.nature, c.item, c.ability, JSON.stringify(c.sp), c.post]) : null,
    dmgFlag: ent ? ent.dmgFlag || null : null, speFlag: ent ? ent.speFlag || null : null, used: ent ? ent.used : null,
    inf: ie ? { pairs: Object.fromEntries(Object.entries(ie.pairs).map(([k, v]) => [k, ser(v)])), hpSps: ser(ie.hpSps), used: ie.used, dropped: ie.dropped } : null,
  });
}
const hasRec = (log, kind, reason) => log.some(r => r.trigger && r.trigger.kind === kind && r.trigger.reason === reason);

const myVenusaur = spec('Venusaur', 'Modest', { spa: 20, spe: 20 }, { ability: 'Overgrow', moves: ['Earth Power'], boosts: { ...boosts0, def: 2 } });
const myBlastoise = spec('Blastoise', 'Modest', { hp: 2, spa: 32, spe: 32 }, { item: 'Blastoisinite', ability: 'Rain Dish' });
const truthChomp = spec('Garchomp', 'Adamant', { atk: 32, spe: 32 }, { ability: 'Sand Veil', moves: ['Rock Slide', 'Earthquake'] });
const baseChomp = spec('Garchomp', 'Adamant', {});
const bogusBase = spec('Bogusmon', 'Adamant', {});
const amtRock = damageRolls(withCurHP(truthChomp), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' }).rolls[10];

// ---- R1-T03 (inf 相手方向): bases の一部が計算不能なら証拠全体を保留 ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp, bogusBase] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  const log = est.takeInferenceLog();
  check('T03 inf-opp: 一部不能で推定状態が変わらない', fingerprint('Garchomp') === before);
  check('T03 inf-opp: dist-unavailable が推論ログに残る', hasRec(log, 'inf', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T03 (inf 自分方向): basesDef の一部が計算不能なら保留 ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const truthHp = statTable('Garchomp').hp.find(r => r.nature === 'Adamant' && r.sp === 0).value;
  const pct = Math.round(damageRolls(withCurHP(myVenusaur), withCurHP(truthChomp), 'Earth Power', { gameType: 'Singles' }).rolls[7] / truthHp * 100);
  const ev = { turn: 1, atk: 'p1: Venusaur', def: 'p2: Garchomp', move: 'Earth Power', pct, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myAtk: myVenusaur, basesDef: [baseChomp, bogusBase] });
  est.processDamageBayes(ev, { myAtk: myVenusaur, baseDef: baseChomp });
  const log = est.takeInferenceLog();
  check('T03 inf-mine: 一部不能で推定状態が変わらない', fingerprint('Garchomp') === before);
  check('T03 inf-mine: dist-unavailable が推論ログに残る', hasRec(log, 'inf', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T03 (bayes 相手方向・跨ぎ原子性): inf は確定し得るが bayes 側の
// 計算不能で inf ごと巻き戻る ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  const mid = fingerprint('Garchomp');
  check('T03 bayes-opp 前提: inf 単独では交差状態が進む', mid !== before);
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: bogusBase });
  const log = est.takeInferenceLog();
  check('T03 bayes-opp: bayes 不能で inf まで巻き戻り状態が戻る', fingerprint('Garchomp') === before);
  check('T03 bayes-opp: dist-unavailable が推論ログに残る', hasRec(log, 'damage', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T03 (bayes 自分方向・跨ぎ原子性) ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const truthHp = statTable('Garchomp').hp.find(r => r.nature === 'Adamant' && r.sp === 0).value;
  const pct = Math.round(damageRolls(withCurHP(myVenusaur), withCurHP(truthChomp), 'Earth Power', { gameType: 'Singles' }).rolls[7] / truthHp * 100);
  const ev = { turn: 1, atk: 'p1: Venusaur', def: 'p2: Garchomp', move: 'Earth Power', pct, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myAtk: myVenusaur, basesDef: [baseChomp] });
  est.processDamageBayes(ev, { myAtk: myVenusaur, baseDef: bogusBase });
  const log = est.takeInferenceLog();
  check('T03 bayes-mine: bayes 不能で inf まで巻き戻り状態が戻る', fingerprint('Garchomp') === before);
  check('T03 bayes-mine: dist-unavailable が推論ログに残る', hasRec(log, 'damage', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T05: 全候補の計算不能 (防御側 spec が例外を投げる入力) ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const bogusDef = spec('Bogusmon', 'Modest', {});
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: bogusDef, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: bogusDef, baseAtk: baseChomp });
  const log = est.takeInferenceLog();
  const ent = est._debug().bayes.bySpecies['Garchomp'];
  check('T05: 全不能で候補集合・事後・フラグが維持される', fingerprint('Garchomp') === before && ent.cands.length > 0 && !ent.dmgFlag);
  check('T05: dist-unavailable が推論ログに残る', hasRec(log, 'inf', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T04a: 質量0 の候補と正の候補が混ざれば従来どおり適用される ----
{
  est.reset();
  const ent = est.entry('Garchomp');
  const postsBefore = ent.cands.map(c => c.post);
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  const log = est.takeInferenceLog();
  const dmg = log.find(r => r.trigger && r.trigger.kind === 'damage');
  check('T04a: 質量0 を含んでも証拠は適用される', !!dmg && dmg.trigger.applied === true && ent.used === 1, JSON.stringify(dmg && dmg.trigger));
  // 独立計算した質量ベースの期待事後と全候補で一致すること (質量0 の
  // 候補は床の係数で更新され、計算不能として保留・除外はされない)
  const { damageDistribution } = core;
  let tot = 0;
  const expected = ent.cands.map((c, i) => {
    const cs = { ...baseChomp, nature: c.nature, sp: { ...c.sp }, item: c.item, ability: c.ability, megaSpecies: c.megaSpecies };
    const dd = damageDistribution(withCurHP(cs), withCurHP(myVenusaur), 'Rock Slide', { gameType: 'Singles' });
    let mass = 0;
    if (dd.dist) { for (let j = 0; j < dd.dist.values.length; j++) if (dd.dist.values[j] === amtRock) mass += dd.dist.counts[j]; mass /= dd.dist.total; }
    const p = postsBefore[i] * Math.max(mass, 0.02);
    tot += p;
    return p;
  });
  const maxDiff = Math.max(...ent.cands.map((c, i) => Math.abs(c.post - expected[i] / tot)));
  check('T04a: 事後が質量ベースの期待値と一致 (質量0 と不能を区別)', maxDiff < 1e-9, 'maxDiff=' + maxDiff);
}

// ---- R1-T04b: 全候補で質量0 (計算は可能) なら no-match で保留され、
// dist-unavailable とは記録されない ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: 1, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  const log = est.takeInferenceLog();
  const dmg = log.find(r => r.trigger && r.trigger.kind === 'damage');
  check('T04b: 全候補質量0 は no-match で保留される', !!dmg && dmg.trigger.applied === false && dmg.trigger.reason === 'no-match', JSON.stringify(dmg && dmg.trigger));
  check('T04b: dist-unavailable とは記録されない', !hasRec(log, 'damage', 'dist-unavailable') && !hasRec(log, 'inf', 'dist-unavailable'));
}

// ---- R1-T06a: 仮説生成と再計算が計算可能な場合は従来どおりフラグが立つ ----
{
  est.reset();
  const ent = est.entry('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: 9999, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: baseChomp });
  est.takeInferenceLog();
  check('T06a: 最大超過では Choice Band の仮説が立つ', ent.dmgFlag === 'Choice Band', String(ent.dmgFlag));
}

// ---- R1-T06b: 仮説生成の経路で計算不能があれば、フラグだけが残らず
// 証拠全体が保留され、以前の状態 (inf の dropped 増加を含む) が維持される ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: 9999, crit: false, w: '', t: '' };
  est.processDamageInf(ev, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev, { myDef: myVenusaur, baseAtk: bogusBase });
  const log = est.takeInferenceLog();
  const ent = est._debug().bayes.bySpecies['Garchomp'];
  check('T06b: 不能時はフラグが発生せず状態が維持される', !ent.dmgFlag && fingerprint('Garchomp') === before);
  check('T06b: dist-unavailable が推論ログに残る', hasRec(log, 'damage', 'dist-unavailable'), JSON.stringify(log.map(r => r.trigger)));
}

// ---- crit: 通常の急所後付け是正は従来どおり効く ----
{
  est.reset();
  const ent = est.entry('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
  est.takeInferenceLog();
  const postsBefore = ent.cands.map(c => c.post);
  const critEv = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  est.processCritInf(critEv, io);
  est.processCritBayes(critEv, io);
  const log = est.takeInferenceLog();
  const patch = log.find(r => r.trigger && r.trigger.kind === 'critPatch');
  check('crit: 後付け是正が適用される', !!patch && patch.trigger.applied === true, JSON.stringify(patch && patch.trigger));
  check('crit: 是正で事後が動き、inf 状態も維持される', ent.cands.some((c, i) => c.post !== postsBefore[i]) && fingerprint('Garchomp').length > 0);
}

// ---- crit: 保留された証拠には記録が無く、急所イベントでも状態は変わらない ----
{
  est.reset();
  est.entry('Garchomp');
  const before = fingerprint('Garchomp');
  const ev = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false, w: '', t: '' };
  const io = { myDef: myVenusaur, basesAtk: [baseChomp, bogusBase], baseAtk: baseChomp };
  est.processDamageInf(ev, io);
  est.processDamageBayes(ev, io);
  est.takeInferenceLog();
  const critEv = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide' };
  est.processCritInf(critEv, io);
  est.processCritBayes(critEv, io);
  const log = est.takeInferenceLog();
  check('crit: 保留された証拠の critPatch は no-match で状態不変', hasRec(log, 'critPatch', 'no-match') && fingerprint('Garchomp') === before, JSON.stringify(log.map(r => r.trigger)));
}

// ---- R1-T08: 単発固定場面のハッシュが MH-001 検収時と一致する ----
{
  est.reset();
  const ent = est.entry('Garchomp');
  const ev1 = { turn: 1, atk: 'p2: Garchomp', def: 'p1: Venusaur', move: 'Rock Slide', amt: amtRock, crit: false };
  est.processDamageInf(ev1, { myDef: myVenusaur, basesAtk: [baseChomp] });
  est.processDamageBayes(ev1, { myDef: myVenusaur, baseAtk: baseChomp });
  const truthHp = statTable('Garchomp').hp.find(r => r.nature === 'Adamant' && r.sp === 0).value;
  const pct = Math.round(damageRolls(withCurHP(myVenusaur), withCurHP(truthChomp), 'Earth Power', { gameType: 'Singles' }).rolls[7] / truthHp * 100);
  const ev2 = { turn: 1, atk: 'p1: Venusaur', def: 'p2: Garchomp', move: 'Earth Power', pct, crit: false };
  est.processDamageInf(ev2, { myAtk: myVenusaur, basesDef: [baseChomp] });
  est.processDamageBayes(ev2, { myAtk: myVenusaur, baseDef: baseChomp });
  const canon = JSON.stringify({ posts: ent.cands.map(c => c.post), log: est.takeInferenceLog().map(r => r.trigger) });
  const hash = createHash('sha256').update(canon).digest('hex');
  check('T08: 単発固定場面のハッシュが一致', hash === '688c01d9a1bfc2d9a58b564c046756b02a96e7c2e3ebd6b2638f998232e8c4f0', hash);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
