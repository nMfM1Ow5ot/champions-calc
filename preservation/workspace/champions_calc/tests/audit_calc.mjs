// ダメージ計算の全体点検 (2026-11-21 総合チャットの点検指示)。
// core.mjs の計算を、素の @smogon/calc (calc.pokemonshowdown.com のエンジン)
// で独立に組んだ複製、および Champions のステータス公式と幅広く照合する。
// 実行: node tests/audit_calc.mjs
// 出力: セクションごとの件数と、不一致ケースの詳細。最後に SUMMARY を出す。
import { readFileSync } from 'node:fs';
import { Pokemon, Move, Field, calculate } from '@smogon/calc';
import { gen, calcMatchup, damageRolls, statTable, withCurHP, STAT_KEYS } from '../core.mjs';

const IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };
let total = 0, mismatches = [];
function cmp(section, name, coreVal, refVal) {
  total++;
  if (JSON.stringify(coreVal) !== JSON.stringify(refVal)) {
    mismatches.push({ section, name, core: coreVal, ref: refVal });
  }
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/* ============ Part 1: ステータス導出 ============ */
// 1a. statTable (calcStat) が Champions 公式と一致するか、全種族で確認
//     公式: HP = 種族値+75+SP (種族値1は1)、他 = floor((種族値+20+SP) × 性格補正)
const dex = JSON.parse(readFileSync(new URL('../data/champions_dex.json', import.meta.url), 'utf8'));
const speciesNames = dex.species || dex.pokemon || Object.keys(dex);
const NATURE_MOD = {
  Lonely: ['atk', 'def'], Brave: ['atk', 'spe'], Adamant: ['atk', 'spa'], Naughty: ['atk', 'spd'],
  Bold: ['def', 'atk'], Relaxed: ['def', 'spe'], Impish: ['def', 'spa'], Lax: ['def', 'spd'],
  Timid: ['spe', 'atk'], Hasty: ['spe', 'def'], Jolly: ['spe', 'spa'], Naive: ['spe', 'spd'],
  Modest: ['spa', 'atk'], Mild: ['spa', 'def'], Quiet: ['spa', 'spe'], Rash: ['spa', 'spd'],
  Calm: ['spd', 'atk'], Gentle: ['spd', 'def'], Sassy: ['spd', 'spe'], Careful: ['spd', 'spa'],
};
function championsFormula(base, stat, sp, nature) {
  if (stat === 'hp') return base === 1 ? 1 : base + 75 + sp;
  const mod = NATURE_MOD[nature];
  const mult = !mod ? 1 : mod[0] === stat ? 1.1 : mod[1] === stat ? 0.9 : 1;
  return Math.floor((base + 20 + sp) * mult);
}
let statCount = 0, statBad = [];
{
  const sampleNatures = ['Hardy', 'Adamant', 'Modest', 'Bold', 'Timid', 'Careful'];
  const sampleSps = [0, 1, 16, 32];
  for (const name of speciesNames) {
    const s = gen.species.get(String(name).toLowerCase().replace(/[^a-z0-9]/g, ''));
    if (!s) { statBad.push(`${name}: gen9 データに無い`); continue; }
    const table = statTable(name);
    if (!table) { statBad.push(`${name}: statTable が null`); continue; }
    for (const stat of STAT_KEYS) {
      for (const nature of sampleNatures) {
        for (const sp of sampleSps) {
          const row = table[stat].find(r => r.nature === nature && r.sp === sp);
          const expected = championsFormula(s.baseStats[stat], stat, sp, nature);
          statCount++;
          if (!row || row.value !== expected) {
            if (statBad.length < 15) statBad.push(`${name} ${stat} ${nature} SP${sp}: core=${row && row.value} 公式=${expected}`);
          }
        }
      }
    }
  }
}
console.log(`Part 1a statTable vs Champions公式: ${statCount} 件, 不一致 ${statBad.length} 件`);
for (const b of statBad) console.log('  ', b);

// 1b. calcMatchup の stats (toPokemon 経由) が素の Pokemon 構築と一致するか
function mirrorPokemon(spec) {
  const name = spec.mega && spec.megaSpecies ? spec.megaSpecies : spec.species;
  const ability = spec.mega && spec.megaAbility ? spec.megaAbility : spec.ability;
  return new Pokemon(gen, name, {
    level: 50, nature: spec.nature, ability, item: spec.itemLost ? '' : spec.item,
    ivs: IVS, evs: Object.fromEntries(STAT_KEYS.map(k => [k, (spec.sp?.[k] || 0) * 8])),
    boosts: spec.boosts || undefined, status: spec.status || '', curHP: spec.curHP,
    abilityOn: ability === 'Unburden' && spec.unburden ? true : undefined,
  });
}
const STAT_SAMPLES = [
  { species: 'Garchomp', nature: 'Jolly', ability: 'Rough Skin', item: 'Yache Berry', sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Earthquake'] },
  { species: 'Blastoise', nature: 'Modest', ability: 'Rain Dish', item: 'Blastoisinite', megaSpecies: 'Blastoise-Mega', megaAbility: 'Mega Launcher', mega: true, sp: { hp: 32, spa: 32, spe: 2 }, moves: ['Water Pulse'] },
  { species: 'Shedinja', nature: 'Adamant', ability: 'Wonder Guard', item: '', sp: { atk: 32 }, moves: ['X-Scissor'] },
  { species: 'Indeedee-F', nature: 'Relaxed', ability: 'Psychic Surge', item: 'Rocky Helmet', sp: { hp: 32, def: 32, spd: 2 }, moves: ['Psychic'] },
  { species: 'Weavile', nature: 'Adamant', ability: 'Pressure', item: 'Focus Sash', sp: { atk: 32, spe: 32, hp: 2 }, boosts: { atk: 2 }, moves: ['Ice Shard'] },
];
for (const s of STAT_SAMPLES) {
  const dummy = { species: 'Gengar', nature: 'Hardy', ability: 'Cursed Body', item: '', sp: {}, moves: [] };
  const out = calcMatchup({ mine: [s], opps: [dummy], field: {} }, null);
  cmp('stats', `${s.species}${s.mega ? ' (mega)' : ''}`, out.stats.mine[0], mirrorPokemon(s).stats);
}
console.log(`Part 1b calcMatchup stats: ${STAT_SAMPLES.length} 件照合`);

/* ============ Part 2: ダメージ計算マトリクス ============ */
// core の calcMatchup (1vs1 に絞った state) と、素の calculate() を比較する。
function coreDamage(atkSpec, defSpec, moveName, fieldOpts = {}) {
  const state = {
    mine: [{ ...atkSpec, moves: [moveName] }],
    opps: [{ ...defSpec, moves: [] }],
    field: {
      weather: fieldOpts.weather, terrain: fieldOpts.terrain,
      attackerSide: fieldOpts.atkSide || {}, defenderSide: fieldOpts.defSide || {},
      oppAttackerSide: {}, oppDefenderSide: {},
    },
    crit: fieldOpts.crit ? { mine: [true] } : undefined,
    singleMoves: fieldOpts.single ? { mine: [moveName] } : undefined,
  };
  const out = calcMatchup(state, null);
  return out.results[0].moveResults[0].vs[0];
}
function refDamage(atkSpec, defSpec, moveName, fieldOpts = {}) {
  const atk = mirrorPokemon(atkSpec);
  const def = mirrorPokemon(defSpec);
  const moveObj = new Move(gen, moveName);
  if (fieldOpts.crit) moveObj.isCrit = true;
  if (fieldOpts.moveOpts) Object.assign(moveObj, fieldOpts.moveOpts);
  const field = new Field({
    gameType: fieldOpts.single ? 'Singles' : 'Doubles',
    weather: fieldOpts.weather || undefined,
    terrain: fieldOpts.terrain || undefined,
    attackerSide: fieldOpts.atkSide || {},
    defenderSide: fieldOpts.defSide || {},
  });
  if (moveObj.category === 'Status') return { status: true };
  try {
    const r = calculate(gen, atk, def, moveObj, field);
    const range = r.range();
    return { min: range[0], max: range[1] };
  } catch (e) {
    return { error: e.message };
  }
}
// core 側の行を参照形に丸める (無効は min/max 0、ステータスは status)
function coreShape(row) {
  if (!row) return { error: 'row なし' };
  if (row.status) return { status: true };
  if (row.error) return { error: row.error };
  return { min: row.min, max: row.max };
}
function D(section, name, atk, def, mv, fieldOpts) {
  cmp(section, name, coreShape(coreDamage(atk, def, mv, fieldOpts)), refDamage(atk, def, mv, fieldOpts));
}

const P = (species, extra = {}) => ({ species, nature: 'Hardy', ability: '', item: '', sp: { atk: 32, spa: 32, spe: 32, hp: 2 }, moves: [], ...extra });
const GARCHOMP = P('Garchomp', { ability: 'Rough Skin', sp: { hp: 32, def: 32, spd: 32, spe: 2 } });
const SNORLAX = P('Snorlax', { ability: 'Thick Fat', sp: { hp: 32, def: 32, spd: 32 } });
const GENGAR = P('Gengar', { ability: 'Cursed Body', sp: { hp: 32, def: 32, spd: 32 } });
const WEAVILE = P('Weavile', { ability: 'Pressure' });
const CHARIZARD = P('Charizard', { ability: 'Blaze' });
const VENUSAUR = P('Venusaur', { ability: 'Overgrow' });
const BLASTOISE = P('Blastoise', { ability: 'Torrent' });
const TYRANITAR = P('Tyranitar', { ability: 'Sand Stream', sp: { hp: 32, def: 32, spd: 32 } });
const ABOMASNOW = P('Abomasnow', { ability: 'Snow Warning', sp: { hp: 32, def: 32, spd: 32 } });

// 基本・相性・STAB
D('基本', 'STAB物理 (地震→ガブ)', GARCHOMP, SNORLAX, 'Earthquake');
D('基本', 'STAB特殊 (ラスターカノン)', P('Magnezone', { ability: 'Sturdy' }), SNORLAX, 'Flash Cannon');
D('基本', '非STAB', WEAVILE, SNORLAX, 'Surf');
D('基本', '4倍弱点 (こおり→ガブ)', WEAVILE, GARCHOMP, 'Ice Shard');
D('基本', '0.25倍 (くさ→ガブ)', P('Rillaboom', { ability: 'Grassy Surge' }), GARCHOMP, 'Bullet Seed');
D('基本', 'タイプ無効 (ノーマル→ゴースト)', P('Ursaring', { ability: 'Guts' }), GENGAR, 'Body Slam');
D('基本', 'タイプ無効 (じめん→ひこう)', GARCHOMP, CHARIZARD, 'Earthquake');
// 天候
D('天候', '晴れ+ほのお 1.5', CHARIZARD, VENUSAUR, 'Flamethrower', { weather: 'Sun' });
D('天候', '晴れ+みず 0.5', BLASTOISE, VENUSAUR, 'Surf', { weather: 'Sun' });
D('天候', '雨+みず 1.5', BLASTOISE, CHARIZARD, 'Surf', { weather: 'Rain' });
D('天候', '雨+ほのお 0.5', CHARIZARD, BLASTOISE, 'Flamethrower', { weather: 'Rain' });
D('天候', '砂嵐+いわ特防1.5 (特殊→サイドン)', P('Alakazam', { ability: 'Magic Guard' }), P('Rhyperior', { ability: 'Solid Rock', sp: { hp: 32, def: 32, spd: 32 } }), 'Psychic', { weather: 'Sand' });
D('天候', '雪+こおり防御1.5 (物理→ユキノオー)', WEAVILE, ABOMASNOW, 'Ice Shard', { weather: 'Snow' });
// フィールド
D('フィールド', 'エレキ+でんき 1.3', P('Magnezone', { ability: 'Sturdy' }), SNORLAX, 'Thunderbolt', { terrain: 'Electric' });
D('フィールド', 'グラス+くさ 1.3', P('Rillaboom', { ability: 'Grassy Surge' }), SNORLAX, 'Wood Hammer', { terrain: 'Grassy' });
D('フィールド', 'グラス+地震 半減', GARCHOMP, SNORLAX, 'Earthquake', { terrain: 'Grassy' });
D('フィールド', 'サイコ+エスパー 1.3', P('Alakazam', { ability: 'Magic Guard' }), SNORLAX, 'Psychic', { terrain: 'Psychic' });
D('フィールド', 'ミスト+ドラゴン 半減', GARCHOMP, SNORLAX, 'Dragon Claw', { terrain: 'Misty' });
// 壁 (ダブルス 2/3、シングルス 1/2)
D('壁', 'リフレクター (ダブルス)', WEAVILE, SNORLAX, 'Ice Punch', { defSide: { isReflect: true } });
D('壁', 'ひかりのかべ (ダブルス)', P('Alakazam', { ability: 'Magic Guard' }), SNORLAX, 'Psychic', { defSide: { isLightScreen: true } });
D('壁', 'オーロラベール (ダブルス物理)', WEAVILE, SNORLAX, 'Ice Punch', { defSide: { isAuroraVeil: true } });
D('壁', 'オーロラベール (ダブルス特殊)', P('Alakazam', { ability: 'Magic Guard' }), SNORLAX, 'Psychic', { defSide: { isAuroraVeil: true } });
D('壁', 'リフレクター (シングルス)', WEAVILE, SNORLAX, 'Ice Punch', { defSide: { isReflect: true }, single: true });
// ランク補正・急所・やけど
D('ランク', '攻撃+2', { ...WEAVILE, boosts: { atk: 2 } }, SNORLAX, 'Ice Punch');
D('ランク', '防御+2される側', WEAVILE, { ...SNORLAX, boosts: { def: 2 } }, 'Ice Punch');
D('ランク', '攻撃-1', { ...WEAVILE, boosts: { atk: -1 } }, SNORLAX, 'Ice Punch');
D('急所', '急所 (通常)', WEAVILE, SNORLAX, 'Ice Punch', { crit: true });
D('急所', '急所は防御+2を無視', WEAVILE, { ...SNORLAX, boosts: { def: 2 } }, 'Ice Punch', { crit: true });
D('急所', '急所は攻撃-1を無視', { ...WEAVILE, boosts: { atk: -1 } }, SNORLAX, 'Ice Punch', { crit: true });
D('やけど', 'やけど物理 半減', { ...WEAVILE, status: 'brn' }, SNORLAX, 'Ice Punch');
D('やけど', 'からげんき (やけど時2倍+半減なし)', { ...P('Ursaring', { ability: 'Quick Feet' }), status: 'brn' }, SNORLAX, 'Facade');
D('やけど', 'こんじょう+やけど (半減なし+攻撃1.5)', { ...P('Ursaring', { ability: 'Guts' }), status: 'brn' }, SNORLAX, 'Body Slam');
// 特性
D('特性', 'ちからもち (アズマリル)', P('Azumarill', { ability: 'Huge Power' }), SNORLAX, 'Aqua Tail');
D('特性', 'テクニシャン (威力60以下1.5)', P('Scizor', { ability: 'Technician' }), SNORLAX, 'Bullet Punch');
D('特性', 'てきおうりょく (STAB2倍)', P('Porygon-Z', { ability: 'Adaptability' }), SNORLAX, 'Tri Attack');
D('特性', 'フェアリースキン (ハイパーボイス→ゲンガー)', P('Sylveon', { ability: 'Pixilate' }), GENGAR, 'Hyper Voice');
D('特性', 'ふゆう (じめん無効)', GARCHOMP, P('Bronzong', { ability: 'Levitate', sp: { hp: 32, def: 32, spd: 32 } }), 'Earthquake');
D('特性', 'かたやぶり→ふゆう (無効化)', { ...GARCHOMP, ability: 'Mold Breaker' }, P('Bronzong', { ability: 'Levitate', sp: { hp: 32, def: 32, spd: 32 } }), 'Earthquake');
D('特性', 'もらいび (ほのお無効)', CHARIZARD, P('Arcanine', { ability: 'Flash Fire' }), 'Flamethrower');
D('特性', 'あついしぼう (ほのお半減)', CHARIZARD, SNORLAX, 'Flamethrower');
D('特性', 'ふしぎなうろこ (状態異常時防御1.5)', WEAVILE, { ...P('Milotic', { ability: 'Marvel Scale', sp: { hp: 32, def: 32, spd: 32 } }), status: 'brn' }, 'Ice Punch');
D('特性', 'てんねん (相手の攻撃+2を無視)', { ...WEAVILE, boosts: { atk: 2 } }, P('Clefable', { ability: 'Unaware', sp: { hp: 32, def: 32, spd: 32 } }), 'Ice Punch');
// 持ち物
D('持ち物', 'いのちのたま 1.3', { ...WEAVILE, item: 'Life Orb' }, SNORLAX, 'Ice Punch');
D('持ち物', 'こだわりハチマキ 1.5', { ...WEAVILE, item: 'Choice Band' }, SNORLAX, 'Ice Punch');
D('持ち物', 'こだわりメガネ 1.5', { ...P('Alakazam', { ability: 'Magic Guard' }), item: 'Choice Specs' }, SNORLAX, 'Psychic');
D('持ち物', 'たつじんのおび (効果抜群1.2)', { ...WEAVILE, item: 'Expert Belt' }, GARCHOMP, 'Ice Shard');
D('持ち物', 'もくたん (ほのお1.2)', { ...CHARIZARD, item: 'Charcoal' }, VENUSAUR, 'Flamethrower');
D('持ち物', 'とつげきチョッキ (特防1.5)', P('Alakazam', { ability: 'Magic Guard' }), { ...SNORLAX, item: 'Assault Vest' }, 'Psychic');
D('持ち物', 'しんかのきせき', WEAVILE, P('Porygon2', { ability: 'Trace', item: 'Eviolite', sp: { hp: 32, def: 32, spd: 32 } }), 'Ice Punch');
D('持ち物', 'ふといホネ (ガラガラ攻撃2倍)', P('Marowak', { ability: 'Rock Head', item: 'Thick Club' }), SNORLAX, 'Bonemerang');
// ダブルス固有
D('ダブルス', '範囲技 0.75 (なみのり)', BLASTOISE, SNORLAX, 'Surf');
D('ダブルス', '範囲技 0.75 (じしん)', GARCHOMP, SNORLAX, 'Earthquake');
D('ダブルス', 'フレンドガード 0.75', WEAVILE, SNORLAX, 'Ice Punch', { defSide: { isFriendGuard: true } });
D('ダブルス', 'てだすけ 1.5', WEAVILE, SNORLAX, 'Ice Punch', { atkSide: { isHelpingHand: true } });
D('ダブルス', 'シングルス扱いでは範囲技 1.0', BLASTOISE, SNORLAX, 'Surf', { single: true });
// メガシンカ
D('メガ', 'メガサーナイト+フェアリースキン', { species: 'Gardevoir', nature: 'Hardy', ability: 'Synchronize', item: 'Gardevoirite', megaSpecies: 'Gardevoir-Mega', megaAbility: 'Pixilate', mega: true, sp: { spa: 32, spe: 32, hp: 2 } }, GENGAR, 'Hyper Voice');
D('メガ', 'メガカメックス+メガランチャー (波動技1.5)', { species: 'Blastoise', nature: 'Hardy', ability: 'Torrent', item: 'Blastoisinite', megaSpecies: 'Blastoise-Mega', megaAbility: 'Mega Launcher', mega: true, sp: { spa: 32, spe: 32, hp: 2 } }, SNORLAX, 'Water Pulse');
// 状態・その他
D('その他', 'へクス (状態異常時2倍)', { ...GENGAR }, { ...SNORLAX, status: 'psn' }, 'Hex');
D('その他', 'ちきゅうなげ (固定ダメージ)', P('Machamp', { ability: 'Guts' }), SNORLAX, 'Seismic Toss');
D('その他', 'ヘビースラム (体重差)', P('Aggron', { ability: 'Sturdy', sp: { atk: 32, hp: 32 } }), P('Joltik', { ability: 'Compound Eyes', sp: {} }), 'Heavy Slam');
D('その他', 'イカサマ (相手の攻撃+ランクで計算)', P('Liepard', { ability: 'Prankster' }), { ...GARCHOMP, boosts: { atk: 2 } }, 'Foul Play');
D('その他', 'ボディプレス (防御で攻撃)', { ...P('Aggron', { ability: 'Sturdy', sp: { def: 32, hp: 32 } }), boosts: { def: 2 } }, SNORLAX, 'Body Press');
D('その他', 'サイコショック (特殊→物理防御)', P('Alakazam', { ability: 'Magic Guard' }), { ...SNORLAX, boosts: { def: 2, spd: 6 } }, 'Psyshock');
D('その他', '変化技', WEAVILE, SNORLAX, 'Swords Dance');
D('その他', '連続技デフォルト (タネマシンガン)', P('Rillaboom', { ability: 'Grassy Surge' }), SNORLAX, 'Bullet Seed');
D('その他', 'トリプルアクセル デフォルト', WEAVILE, GARCHOMP, 'Triple Axel');

/* ============ Part 3: damageRolls (推定エンジン経路) ============ */
function refRolls(atkSpec, defSpec, moveName, opts = {}) {
  const moveObj = new Move(gen, moveName);
  if (opts.crit) moveObj.isCrit = true;
  const field = new Field({
    gameType: opts.gameType || 'Doubles',
    weather: opts.weather || undefined, terrain: opts.terrain || undefined,
    attackerSide: opts.atkSide || {}, defenderSide: opts.defSide || {},
  });
  const r = calculate(gen, mirrorPokemon(atkSpec), mirrorPokemon(defSpec), moveObj, field);
  return Array.isArray(r.damage) ? r.damage : [r.damage];
}
const ROLLCASES = [
  ['通常', WEAVILE, GARCHOMP, 'Ice Shard', {}],
  ['急所', WEAVILE, GARCHOMP, 'Ice Shard', { crit: true }],
  ['晴れ', CHARIZARD, VENUSAUR, 'Flamethrower', { weather: 'Sun' }],
  ['サイコフィールド', P('Alakazam', { ability: 'Magic Guard' }), SNORLAX, 'Psychic', { terrain: 'Psychic' }],
  ['壁あり', WEAVILE, SNORLAX, 'Ice Punch', { defSide: { isReflect: true } }],
  ['シングルス', BLASTOISE, SNORLAX, 'Surf', { gameType: 'Singles' }],
];
for (const [name, a, d, mv, opts] of ROLLCASES) {
  const got = damageRolls(a, d, mv, opts);
  cmp('damageRolls', name, got.rolls, refRolls(a, d, mv, opts));
}

/* ============ Part 4: 素早さ (calcMatchup speeds) ============ */
function coreSpeed(spec, fieldOpts = {}) {
  const dummy = { species: 'Gengar', nature: 'Hardy', ability: 'Cursed Body', item: '', sp: {}, moves: [] };
  const out = calcMatchup({ mine: [spec], opps: [dummy], field: { tailwindMine: !!fieldOpts.tailwind } }, null);
  return out.speeds.mine[0];
}
function refSpeed(spec, fieldOpts = {}) {
  const p = mirrorPokemon(spec);
  let v = p.stats.spe;
  const b = (spec.boosts && spec.boosts.spe) || 0;
  v = b >= 0 ? Math.floor(v * (2 + b) / 2) : Math.floor(v * 2 / (2 - b));
  if (spec.ability === 'Unburden' && spec.unburden) v *= 2;
  if (fieldOpts.tailwind) v *= 2;
  if (spec.status === 'par') v = Math.floor(v / 2);
  return v;
}
const SPEEDCASES = [
  ['素の素早さ', { ...WEAVILE }, {}],
  ['+1ランク', { ...WEAVILE, boosts: { spe: 1 } }, {}],
  ['-1ランク', { ...WEAVILE, boosts: { spe: -1 } }, {}],
  ['おいかぜ', { ...WEAVILE }, { tailwind: true }],
  ['まひ半減', { ...WEAVILE, status: 'par' }, {}],
  ['かるわざ発動', { species: 'Sneasler', nature: 'Hardy', ability: 'Unburden', item: '', sp: { spe: 32 }, unburden: true, moves: [] }, {}],
];
for (const [name, spec, fo] of SPEEDCASES) cmp('speeds', name, coreSpeed(spec, fo), refSpeed(spec, fo));

/* ============ Part 5: curHP (withCurHP + KO率) ============ */
{
  const full = damageRolls(WEAVILE, GARCHOMP, 'Ice Shard');
  const halfSpec = withCurHP({ ...GARCHOMP, curHPPercent: 50 });
  const half = damageRolls(WEAVILE, halfSpec, 'Ice Shard');
  cmp('curHP', 'ダメージロール自体は curHP で変わらない', half.rolls, full.rolls);
  const refP = mirrorPokemon({ ...GARCHOMP, curHP: halfSpec.curHP });
  cmp('curHP', 'withCurHP の実数変換', halfSpec.curHP, Math.max(1, Math.floor(refP.stats.hp * 0.5)));
}

/* ============ 結果 ============ */
console.log(`\nPart 2-5 照合件数 (Part 1b 含む): ${total} 件, 不一致 ${mismatches.length} 件`);
for (const m of mismatches) {
  console.log(`MISMATCH [${m.section}] ${m.name}\n  core: ${JSON.stringify(m.core)}\n  ref : ${JSON.stringify(m.ref)}`);
}
console.log(`SUMMARY total=${total + statCount} statMismatches=${statBad.length} damageMismatches=${mismatches.length}`);
process.exit(mismatches.length || statBad.length ? 1 : 0);
