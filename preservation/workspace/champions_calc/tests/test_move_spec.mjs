// 技ごとの指定値 (連続技のヒット数・ふんどのこぶし・おはかまいり) の検証。
// 期待値は @smogon/calc の Move/Pokemon を直接組んだ複製と、ダメージ公式の
// 手計算 (修飾なしの素の対面) の両方で照合する。
// 実行: node tests/test_move_spec.mjs (最後に ALL PASS と出す)
import { Pokemon, Move, Field, calculate } from '@smogon/calc';
import { gen, damageRolls, calcMatchup, moveData, spToEvs } from '../core.mjs';

let failures = 0;
function check(name, cond, detail = '') {
  console.log((cond ? 'PASS ' : 'FAIL ') + name + (!cond && detail ? ` (${detail})` : ''));
  if (!cond) failures++;
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };

const WEAVILE = { species: 'Weavile', nature: 'Hardy', ability: 'Pressure', item: '', sp: { atk: 32 } };
const ANNIHILAPE = { species: 'Annihilape', nature: 'Hardy', ability: 'Vital Spirit', item: '', sp: { atk: 32 } };
const RILLABOOM = { species: 'Rillaboom', nature: 'Hardy', ability: 'Grassy Surge', item: '', sp: { atk: 32 } };
const GARCHOMP = { species: 'Garchomp', nature: 'Hardy', ability: 'Rough Skin', item: '', sp: { hp: 32, def: 32 } };

function mirrorPokemon(spec) {
  return new Pokemon(gen, spec.species, {
    level: 50, nature: spec.nature, ability: spec.ability, item: spec.item,
    ivs: IVS, evs: spToEvs(spec.sp),
  });
}

// ダメージ公式の手計算 (Lv50、修飾は STAB とタイプ相性のみの素の対面用)
// base = floor(floor(floor(2*Lv/5+2) * 威力 * A / D) / 50) + 2
// roll_i = floor(pokeRound(floor(base * (85+i) / 100) * stab) * eff)
// pokeRound は 0.5 を切り捨てる四捨五入
function pokeRound(x) {
  const f = x - Math.floor(x);
  return f > 0.5 ? Math.ceil(x) : Math.floor(x);
}
function handRolls(bp, atk, def, stab, eff) {
  const base = Math.floor(Math.floor(Math.floor(2 * 50 / 5 + 2) * bp * atk / def) / 50) + 2;
  const rolls = [];
  for (let i = 0; i < 16; i++) {
    let d = Math.floor(base * (85 + i) / 100);
    if (stab !== 1) d = pokeRound(d * stab);
    d = Math.floor(d * eff);
    rolls.push(Math.max(1, d));
  }
  return rolls;
}
// MH-001 以降、複数ヒットの期待値は「要素ごとの合計」ではなく合計の分布。
// 参照分布は全列挙で独立に求める (畳み込み実装とは別の経路で照合する)
function bruteForceDist(lists) {
  let combos = [0];
  for (const l of lists) {
    const next = [];
    for (const c of combos) for (const v of l) next.push(c + v);
    combos = next;
  }
  const freq = new Map();
  for (const c of combos) freq.set(c, (freq.get(c) || 0) + 1);
  const values = [...freq.keys()].sort((a, b) => a - b);
  return { values, counts: values.map(v => freq.get(v)), total: combos.length };
}
const distEq = (a, b) => !!a && !!b && eq(a.values, b.values) && eq(a.counts, b.counts) && a.total === b.total;

// --- A. メタ情報 (moveData().spec) ---
check('Bullet Seed の spec', eq(moveData('Bullet Seed').spec, { kind: 'hits', min: 2, max: 5, def: 3 }), JSON.stringify(moveData('Bullet Seed').spec));
check('Triple Axel の spec', eq(moveData('Triple Axel').spec, { kind: 'hits', min: 1, max: 3, def: 3 }));
check('Population Bomb の spec', eq(moveData('Population Bomb').spec, { kind: 'hits', min: 1, max: 10, def: 10 }));
check('Rage Fist の spec', eq(moveData('Rage Fist').spec, { kind: 'rageFist', min: 0, max: 6, def: 0 }));
check('Last Respects の spec', eq(moveData('Last Respects').spec, { kind: 'lastRespects', min: 0, max: 5, def: 0 }));
check('Double Kick は指定なし (固定2ヒット)', moveData('Double Kick').spec === null);
check('通常技は指定なし', moveData('Tackle').spec === null);

// --- B. 後方互換: 指定なしは従来の計算 (Move を素で組んだ複製) と完全一致 ---
// 単発技は従来どおり。複数ヒット技は MH-001 で分布契約に変更したため、
// そちらは直下の B2 で新しい期待値に照合する (旧期待値は要素ごと合計の
// 欠陥そのものを固定していた)。
for (const [atkSpec, mv] of [[WEAVILE, 'Ice Shard'], [ANNIHILAPE, 'Rage Fist'], [ANNIHILAPE, 'Last Respects']]) {
  const got = damageRolls(atkSpec, GARCHOMP, mv);
  const field = new Field({ gameType: 'Doubles' });
  const r = calculate(gen, mirrorPokemon(atkSpec), mirrorPokemon(GARCHOMP), new Move(gen, mv), field);
  const expected = Array.isArray(r.damage) ? r.damage : [r.damage];
  check(`指定なし ${mv} は従来どおり`, eq(got.rolls, expected));
}

// --- B2. 複数ヒット技の指定なし (MH-001 の分布契約で書き換え) ---
for (const [atkSpec, mv] of [[WEAVILE, 'Triple Axel'], [RILLABOOM, 'Bullet Seed'], [WEAVILE, 'Double Kick']]) {
  const got = damageRolls(atkSpec, GARCHOMP, mv);
  const field = new Field({ gameType: 'Doubles' });
  const r = calculate(gen, mirrorPokemon(atkSpec), mirrorPokemon(GARCHOMP), new Move(gen, mv), field);
  check(`指定なし ${mv} は分布で返す (MH-001)`,
    got.rolls === null && got.multi === true && got.hits === r.damage.length && distEq(got.dist, bruteForceDist(r.damage)),
    `got=${JSON.stringify(got).slice(0, 200)}`);
}

// --- C. トリプルアクセル: 段階威力 20/40/60 の合計 (手計算) ---
// MH-001 で書き換え: 2 ヒット以上は要素ごと合計ではなく、手計算の
// ヒットごとのロールを全列挙した分布と照合する。1 ヒットは単発として
// 従来どおりロール列で返す。
{
  const A = mirrorPokemon(WEAVILE).stats.atk;
  const D = mirrorPokemon(GARCHOMP).stats.def;
  const perHit = [1, 2, 3].map(h => handRolls(20 * h, A, D, 1.5, 4)); // 氷→地面・ドラゴンは 4 倍
  const got1 = damageRolls(WEAVILE, GARCHOMP, 'Triple Axel', { moveSpec: 1 });
  check('Triple Axel 1 ヒット', eq(got1.rolls, perHit[0]), `got=${JSON.stringify(got1.rolls)}`);
  for (const hits of [2, 3]) {
    const got = damageRolls(WEAVILE, GARCHOMP, 'Triple Axel', { moveSpec: hits });
    check(`Triple Axel ${hits} ヒットは分布 (MH-001)`,
      got.rolls === null && got.multi === true && got.hits === hits && distEq(got.dist, bruteForceDist(perHit.slice(0, hits))),
      `got=${JSON.stringify(got).slice(0, 200)}`);
  }
}

// --- D. ふんどのこぶし: 威力 50 + 50×被弾回数 (手計算) ---
{
  const A = mirrorPokemon(ANNIHILAPE).stats.atk;
  const D = mirrorPokemon(GARCHOMP).stats.def;
  const got0 = damageRolls(ANNIHILAPE, GARCHOMP, 'Rage Fist', { moveSpec: 0 });
  check('Rage Fist 被弾0回 (威力50)', eq(got0.rolls, handRolls(50, A, D, 1.5, 1)));
  const got3 = damageRolls(ANNIHILAPE, GARCHOMP, 'Rage Fist', { moveSpec: 3 });
  check('Rage Fist 被弾3回 (威力200)', eq(got3.rolls, handRolls(200, A, D, 1.5, 1)),
    `got=${JSON.stringify(got3.rolls)}`);
  const got6 = damageRolls(ANNIHILAPE, GARCHOMP, 'Rage Fist', { moveSpec: 99 });
  check('Rage Fist 上限クランプ (威力350)', eq(got6.rolls, handRolls(350, A, D, 1.5, 1)));
}

// --- E. おはかまいり: 威力 50 + 50×倒れた味方の数 (手計算) ---
{
  const A = mirrorPokemon(ANNIHILAPE).stats.atk;
  const D = mirrorPokemon(GARCHOMP).stats.def;
  const got0 = damageRolls(ANNIHILAPE, GARCHOMP, 'Last Respects', { moveSpec: 0 });
  check('Last Respects 味方0体 (威力50)', eq(got0.rolls, handRolls(50, A, D, 1.5, 1)));
  const got2 = damageRolls(ANNIHILAPE, GARCHOMP, 'Last Respects', { moveSpec: 2 });
  check('Last Respects 味方2体 (威力150)', eq(got2.rolls, handRolls(150, A, D, 1.5, 1)),
    `got=${JSON.stringify(got2.rolls)}`);
}

// --- F. 可変ヒット技の合計の分布 (手計算: 1ヒット分 × ヒット数) ---
// MH-001 で書き換え: 要素ごと合計ではなく、手計算の 1 ヒット分を
// 全列挙した分布と照合する。
{
  const A = mirrorPokemon(RILLABOOM).stats.atk;
  const D = mirrorPokemon(GARCHOMP).stats.def;
  const one = handRolls(25, A, D, 1.5, 1); // 草→地面2倍・ドラゴン0.5倍 = 等倍
  for (const hits of [2, 5]) {
    const got = damageRolls(RILLABOOM, GARCHOMP, 'Bullet Seed', { moveSpec: hits });
    check(`Bullet Seed ${hits} ヒットは分布 (MH-001)`,
      got.rolls === null && got.multi === true && got.hits === hits && distEq(got.dist, bruteForceDist(Array(hits).fill(one))),
      `got=${JSON.stringify(got).slice(0, 200)}`);
  }
}

// --- G. calcMatchup 経由 (state.moveSpecs) ---
{
  const base = {
    mine: [{ ...WEAVILE, moves: ['Triple Axel'] }],
    opps: [{ ...GARCHOMP, moves: [] }],
    field: {},
  };
  const r1 = calcMatchup({ ...base, moveSpecs: { mine: [{ 'Triple Axel': 1 }] } }, null);
  const d1 = damageRolls(WEAVILE, GARCHOMP, 'Triple Axel', { moveSpec: 1 }).rolls;
  const vs1 = r1.results[0].moveResults[0].vs[0];
  check('calcMatchup Triple Axel 1ヒット', vs1.min === Math.min(...d1) && vs1.max === Math.max(...d1),
    JSON.stringify(vs1));
  const r3 = calcMatchup({ ...base, moveSpecs: { mine: [{ 'Triple Axel': 3 }] } }, null);
  const rDef = calcMatchup(base, null);
  const vs3 = r3.results[0].moveResults[0].vs[0];
  const vsDef = rDef.results[0].moveResults[0].vs[0];
  check('calcMatchup 指定なし = 3ヒット (従来デフォルト)', vsDef.min === vs3.min && vsDef.max === vs3.max,
    `def=${JSON.stringify(vsDef)} spec3=${JSON.stringify(vs3)}`);
}

console.log(failures ? `${failures} FAILURES` : 'ALL PASS');
process.exit(failures ? 1 : 0);
