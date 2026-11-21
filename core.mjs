// Champions ダメージ計算コア
// Championsの実数値は @smogon/calc (gen9) で IV31 / Lv50 / EV = SP x 8 と置くと完全一致する (検証済み)
import { Generations, Pokemon, Move, Field, calculate, calcStat } from '@smogon/calc';

export const gen = Generations.get(9);
const IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };
export const STAT_KEYS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];

// 実数値 (ステータス画面の6つの能力値) から SP振りと性格を逆算する。
// Champions は Lv50・IV31 固定で HP = 種族値+75+SP、他 = floor((種族値+20+SP) × 性格補正)。
// 候補を列挙し、SP合計の大きい順に返す (通常は1件に定まる)。
const NATURE_MODS = {
  Lonely: ['atk', 'def'], Brave: ['atk', 'spe'], Adamant: ['atk', 'spa'], Naughty: ['atk', 'spd'],
  Bold: ['def', 'atk'], Relaxed: ['def', 'spe'], Impish: ['def', 'spa'], Lax: ['def', 'spd'],
  Timid: ['spe', 'atk'], Hasty: ['spe', 'def'], Jolly: ['spe', 'spa'], Naive: ['spe', 'spd'],
  Modest: ['spa', 'atk'], Mild: ['spa', 'def'], Quiet: ['spa', 'spe'], Rash: ['spa', 'spd'],
  Calm: ['spd', 'atk'], Gentle: ['spd', 'def'], Sassy: ['spd', 'spe'], Careful: ['spd', 'spa'],
};
const ALL_NATURES = ['Hardy', 'Lonely', 'Brave', 'Adamant', 'Naughty', 'Bold', 'Docile', 'Relaxed', 'Impish', 'Lax',
  'Timid', 'Hasty', 'Serious', 'Jolly', 'Naive', 'Modest', 'Mild', 'Quiet', 'Bashful', 'Rash',
  'Calm', 'Gentle', 'Sassy', 'Careful', 'Quirky'];
export function deriveBuild(speciesName, actual) {
  const s = gen.species.get(speciesName.toLowerCase().replace(/[^a-z0-9]/g, ''));
  if (!s || !actual) return [];
  const base = s.baseStats;
  const solutions = [];
  for (const nature of ALL_NATURES) {
    const [up, down] = NATURE_MODS[nature] || [null, null];
    const mod = k => (k === up ? 1.1 : k === down ? 0.9 : 1.0);
    const hpSP = actual.hp - base.hp - 75;
    if (hpSP < 0 || hpSP > 32) continue;
    const cand = { hp: [hpSP] };
    let ok = true;
    for (const k of STAT_KEYS.slice(1)) {
      const list = [];
      for (let sp = 0; sp <= 32; sp++) {
        if (Math.floor((base[k] + 20 + sp) * mod(k)) === actual[k]) list.push(sp);
      }
      if (!list.length) { ok = false; break; }
      cand[k] = list;
    }
    if (!ok) continue;
    const rec = (i, cur, total) => {
      if (total > 66) return;
      if (i === STAT_KEYS.length) { solutions.push({ nature, sp: { ...cur }, total }); return; }
      for (const v of cand[STAT_KEYS[i]]) { cur[STAT_KEYS[i]] = v; rec(i + 1, cur, total + v); }
    };
    rec(0, {}, 0);
  }
  solutions.sort((a, b) => b.total - a.total);
  return solutions;
}

export function spToEvs(sp = {}) {
  const evs = {};
  for (const k of STAT_KEYS) evs[k] = (sp[k] || 0) * 8;
  return evs;
}

// デフォルトチーム: 「やなぎ_グロチャレ２」(Regulation M-C)。
// my_team.json が読めない場合のフォールバックとして、登録チームと同内容を
// 保持する (2026-11-20 ユーザー指示で旧 M-C 構築から差し替え)
export const TEAM_PRESETS = [
  {
    label: 'カメックス (メガ)', species: 'Blastoise', megaSpecies: 'Blastoise-Mega',
    item: 'Blastoisinite', ability: 'Rain Dish', megaAbility: 'Mega Launcher', nature: 'Modest',
    sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Water Spout', 'Terrain Pulse', 'Aura Sphere', 'Dark Pulse'],
  },
  {
    label: 'サーナイト (メガ)', species: 'Gardevoir', megaSpecies: 'Gardevoir-Mega',
    item: 'Gardevoirite', ability: 'Synchronize', megaAbility: 'Pixilate', nature: 'Timid',
    sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Hyper Voice', 'Expanding Force', 'Thunderbolt', 'Protect'],
  },
  {
    label: 'オオニューラ', species: 'Sneasler',
    item: 'Psychic Seed', ability: 'Unburden', nature: 'Adamant',
    sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Close Combat', 'Dire Claw', 'Rock Tomb', 'Protect'],
  },
  {
    label: 'イエッサン♀', species: 'Indeedee-F',
    item: 'Rocky Helmet', ability: 'Psychic Surge', nature: 'Relaxed',
    sp: { hp: 32, def: 32, spd: 2 }, moves: ['Psychic', 'Follow Me', 'Helping Hand', 'Protect'],
  },
  {
    label: 'グレンアルマ', species: 'Armarouge',
    item: 'Focus Sash', ability: 'Weak Armor', nature: 'Modest',
    sp: { hp: 1, def: 1, spa: 32, spe: 32 }, moves: ['Expanding Force', 'Armor Cannon', 'Wide Guard', 'Protect'],
  },
  {
    label: 'エルフーン', species: 'Whimsicott',
    item: 'Babiri Berry', ability: 'Prankster', nature: 'Modest',
    sp: { hp: 32, def: 2, spa: 25, spd: 7 }, moves: ['Grass Knot', 'Tailwind', 'Sunny Day', 'Encore'],
  },
];

// 相手の想定型 (画面から見えない相手の振り方はこれで仮定する)
export function assumedSet(speciesName, kind = 'attacker') {
  const s = gen.species.get(speciesName.toLowerCase().replace(/[^a-z0-9]/g, ''));
  const bs = s.baseStats;
  const physical = bs.atk >= bs.spa;
  const offKey = physical ? 'atk' : 'spa';
  if (kind === 'none') return { sp: {}, nature: 'Serious', ability: s.abilities[0], item: undefined, note: '無振り想定' };
  if (kind === 'bulky') {
    const defKey = bs.def <= bs.spd ? 'def' : 'spd';
    return {
      sp: { hp: 32, [defKey]: 32, spe: 2 }, nature: defKey === 'def' ? 'Impish' : 'Careful',
      ability: s.abilities[0], item: undefined, note: '耐久想定 (H32+' + (defKey === 'def' ? 'B' : 'D') + '32)',
    };
  }
  // attacker: 攻撃32 + 素早さ32 + HP2
  const fast = bs.spe >= 100;
  return {
    sp: { [offKey]: 32, spe: 32, hp: 2 },
    nature: fast ? (physical ? 'Jolly' : 'Timid') : (physical ? 'Adamant' : 'Modest'),
    ability: s.abilities[0], item: undefined, note: (physical ? '物理' : '特殊') + 'アタッカー想定 (32-32)',
  };
}

function toPokemon(spec) {
  const name = spec.mega && spec.megaSpecies ? spec.megaSpecies : spec.species;
  const ability = spec.mega && spec.megaAbility ? spec.megaAbility : spec.ability;
  const p = new Pokemon(gen, name, {
    level: 50, nature: spec.nature, ability, item: spec.itemLost ? '' : spec.item,
    ivs: IVS, evs: spToEvs(spec.sp),
    boosts: spec.boosts || undefined,
    status: spec.status || '',
    curHP: spec.curHP, // 実数 (undefined = 満タン)
    // かるわざ発動中 (持ち物を失った) のときだけ素早さ2倍がかかる。
    // abilityOn は他の特性にも効くフラグのため、かるわざ以外では渡さない
    abilityOn: ability === 'Unburden' && spec.unburden ? true : undefined,
  });
  return p;
}

function boostedSpe(p, tailwind) {
  let v = p.stats.spe;
  const b = (p.boosts && p.boosts.spe) || 0;
  v = b >= 0 ? Math.floor(v * (2 + b) / 2) : Math.floor(v * 2 / (2 - b));
  if (p.ability === 'Unburden' && p.abilityOn) v *= 2;
  if (tailwind) v *= 2;
  if (p.status === 'par') v = Math.floor(v / 2);
  return v;
}

// pokedb の使用率データ (usage_sets.json の sets) から「最も使用されている型」の spec を作る
export function usageSpec(speciesName, usageSets) {
  if (!usageSets) return null;
  const key = String(speciesName).toLowerCase().replace(/[^a-z0-9]/g, '');
  const u = usageSets[key];
  if (!u) return null;
  let megaAbility;
  if (u.megaSpecies) {
    const ms = gen.species.get(u.megaSpecies.toLowerCase().replace(/[^a-z0-9]/g, ''));
    if (ms) megaAbility = Array.isArray(ms.abilities) ? ms.abilities[0] : Object.values(ms.abilities || {})[0];
  }
  return {
    species: u.species, megaSpecies: u.megaSpecies || undefined, mega: false,
    ability: u.ability, megaAbility, nature: u.nature, item: u.item || '',
    sp: { ...(u.sp || {}) }, moves: [...(u.moves || [])],
    usageRates: u.rates || null, usageJa: u.ja || '',
  };
}

// @smogon/calc は無効 (ダメージ0) の相性で例外を投げるため、無効判定を先に行う
const TYPE_IMMUNE = { Normal: ['Ghost'], Electric: ['Ground'], Fighting: ['Ghost'], Poison: ['Steel'], Ground: ['Flying'], Psychic: ['Dark'], Ghost: ['Normal'], Dragon: ['Fairy'] };
const ABILITY_IMMUNE = [
  [['Levitate', 'Earth Eater'], 'Ground'], [['Flash Fire', 'Well-Baked Body'], 'Fire'],
  [['Water Absorb', 'Dry Skin', 'Storm Drain'], 'Water'], [['Volt Absorb', 'Lightning Rod', 'Motor Drive'], 'Electric'],
  [['Sap Sipper'], 'Grass'],
];
// 攻撃側の特性で技タイプが変わる場合の実効タイプ
// (@smogon/calc 本体は変換後のタイプで計算するが、事前の無効判定は
// 変換前のタイプで見ていたため、フェアリースキンのハイパーボイスが
// ゴーストに「無効」と誤判定された。2026-11-20 ユーザー報告)
function effectiveMoveType(atkP, moveObj) {
  let t = moveObj.type;
  const ab = atkP.ability;
  if (ab === 'Normalize') t = 'Normal';
  else if (t === 'Normal') {
    if (ab === 'Pixilate') t = 'Fairy';
    else if (ab === 'Aerilate') t = 'Flying';
    else if (ab === 'Refrigerate') t = 'Ice';
    else if (ab === 'Galvanize') t = 'Electric';
  }
  if (ab === 'Liquid Voice' && (moveObj.flags || {}).sound) t = 'Water';
  return t;
}
function isImmune(atkP, defP, moveObj) {
  const effType = effectiveMoveType(atkP, moveObj);
  if (TYPE_IMMUNE[effType] && defP.types.some(t => TYPE_IMMUNE[effType].includes(t))) return true;
  const breaker = ['Mold Breaker', 'Teravolt', 'Turboblaze'].includes(atkP.ability);
  if (!breaker) {
    for (const [abilities, type] of ABILITY_IMMUNE) if (effType === type && abilities.includes(defP.ability)) return true;
    const fl = moveObj.flags || {};
    if (defP.ability === 'Soundproof' && fl.sound) return true;
    if (defP.ability === 'Bulletproof' && fl.bullet) return true;
    if (defP.ability === 'Wind Rider' && fl.wind) return true;
  }
  return false;
}

function calcDirection(attackers, defenders, atkSpecs, field, critFlags, fieldSingle, singleMoves, moveSpecs) {
  const out = [];
  atkSpecs.forEach((spec, i) => {
    const entry = { attacker: i, species: spec.mega && spec.megaSpecies ? spec.megaSpecies : spec.species, moveResults: [] };
    for (const mv of spec.moves || []) {
      const row = { move: mv, vs: [] };
      if (!mv || !gen.moves.get(String(mv).toLowerCase().replace(/[^a-z0-9]/g, ''))) { for (let j = 0; j < defenders.length; j++) row.vs.push({ status: true }); entry.moveResults.push(row); continue; }
      const moveObj = buildMove(mv, moveSpecs && moveSpecs[i] ? moveSpecs[i][mv] : undefined, !!(critFlags && critFlags[i]));
      const useField = fieldSingle && singleMoves && singleMoves.includes(mv) ? fieldSingle : field;
      for (let j = 0; j < defenders.length; j++) {
        if (moveObj.category === 'Status') { row.vs.push({ status: true }); continue; }
        if (isImmune(attackers[i], defenders[j], moveObj)) { row.vs.push({ min: 0, max: 0, minPct: 0, maxPct: 0, ko: '', immune: true }); continue; }
        try {
          const r = calculate(gen, attackers[i], defenders[j], moveObj, useField);
          const range = r.range();
          const defMaxHP = defenders[j].stats.hp;
          row.vs.push({
            min: range[0], max: range[1],
            minPct: Math.round(range[0] / defMaxHP * 1000) / 10,
            maxPct: Math.round(range[1] / defMaxHP * 1000) / 10,
            ko: r.kochance().text,
            desc: r.desc(),
          });
        } catch (e) {
          row.vs.push({ error: e.message });
        }
      }
      entry.moveResults.push(row);
    }
    out.push(entry);
  });
  return out;
}

// state: { mine: [spec, spec], opps: [spec, spec], field: {weather, terrain, attackerSide, defenderSide, oppAttackerSide, oppDefenderSide, tailwindMine, tailwindOpp} }
//   moveSpecs (任意): { mine: [{技名: 指定値}, ...], opps: [...] } 攻撃側スロットごとの技指定値 (moveSpecInfo 参照)
//   attackerSide/defenderSide = 自分が攻撃する時 (自分の手助け / 相手の壁)
//   oppAttackerSide/oppDefenderSide = 相手が攻撃する時 (相手の手助け / 自分の壁)
// spec: {species, megaSpecies?, mega?, sp, nature, ability, megaAbility?, item, moves[], curHPPercent, boosts, status}
// 戻り値: { results: 自分の技→相手, oppResults: 相手の技→自分, speeds, stats }
export function calcMatchup(state, names) {
  const mine = state.mine.map(toPokemon);
  const opps = state.opps.map(toPokemon);
  const field = new Field({
    gameType: 'doubles',
    weather: state.field.weather || undefined,
    terrain: state.field.terrain || undefined,
    attackerSide: state.field.attackerSide || {},
    defenderSide: state.field.defenderSide || {},
  });
  const oppField = new Field({
    gameType: 'doubles',
    weather: state.field.weather || undefined,
    terrain: state.field.terrain || undefined,
    attackerSide: state.field.oppAttackerSide || {},
    defenderSide: state.field.oppDefenderSide || {},
  });
  const fieldS = new Field({
    gameType: 'Singles',
    weather: state.field.weather || undefined,
    terrain: state.field.terrain || undefined,
    attackerSide: state.field.attackerSide || {},
    defenderSide: state.field.defenderSide || {},
  });
  const oppFieldS = new Field({
    gameType: 'Singles',
    weather: state.field.weather || undefined,
    terrain: state.field.terrain || undefined,
    attackerSide: state.field.oppAttackerSide || {},
    defenderSide: state.field.oppDefenderSide || {},
  });
  const out = { results: [], oppResults: [], speeds: { mine: [], opps: [] } };
  out.results = calcDirection(mine, opps, state.mine, field, state.crit && state.crit.mine, fieldS, state.singleMoves && state.singleMoves.mine, state.moveSpecs && state.moveSpecs.mine);
  out.oppResults = calcDirection(opps, mine, state.opps, oppField, state.crit && state.crit.opps, oppFieldS, state.singleMoves && state.singleMoves.opps, state.moveSpecs && state.moveSpecs.opps);
  out.speeds.mine = mine.map(p => boostedSpe(p, state.field.tailwindMine));
  out.speeds.opps = opps.map(p => boostedSpe(p, state.field.tailwindOpp));
  out.stats = {
    mine: mine.map(p => ({ ...p.stats })),
    opps: opps.map(p => ({ ...p.stats })),
  };
  return out;
}

// curHPPercent を持つ spec を curHP 実数に変換するヘルパー (UI/Mac側から使う)
export function withCurHP(spec) {
  if (spec.curHPPercent == null || spec.curHPPercent >= 100) return { ...spec, curHP: undefined };
  const p = toPokemon({ ...spec, curHP: undefined });
  return { ...spec, curHP: Math.max(1, Math.floor(p.stats.hp * spec.curHPPercent / 100)) };
}

/* ---------- 技ごとの指定値 (ヒット数・積み技カウンタ) ---------- */

// 技に「指定できる値」があるかを返す (UI が moveData().spec で引く)。
//   hits:        連続技のヒット数。2〜5 回の可変ヒット技 (multihit が配列) と、
//                命中判定がヒットごとの技 (multiaccuracy: トリプルアクセル等)
//   rageFist:    ふんどのこぶしの被弾回数 0〜6 (威力 50+50×回数、上限 350)
//   lastRespects: おはかまいりの倒れた味方の数 0〜5 (威力 50+50×数)
// 固定ヒット数の技 (ダブルキック等) は指定なし (spec: null) で現行どおり。
// def は指定がない場合の現行デフォルト (calc の Move 既定値と同じ)。
const _moveSpecCache = {};
export function moveSpecInfo(name) {
  if (name in _moveSpecCache) return _moveSpecCache[name];
  const m = gen.moves.get(String(name).toLowerCase().replace(/[^a-z0-9]/g, ''));
  let spec = null;
  if (m) {
    if (Array.isArray(m.multihit)) {
      spec = { kind: 'hits', min: m.multihit[0], max: m.multihit[1], def: m.multihit[0] + 1 };
    } else if (m.multiaccuracy && typeof m.multihit === 'number') {
      spec = { kind: 'hits', min: 1, max: m.multihit, def: m.multihit };
    } else if (m.name === 'Rage Fist') {
      spec = { kind: 'rageFist', min: 0, max: 6, def: 0 };
    } else if (m.name === 'Last Respects') {
      spec = { kind: 'lastRespects', min: 0, max: 5, def: 0 };
    }
  }
  _moveSpecCache[name] = spec;
  return spec;
}

// 指定値を反映した Move を作る。指定が無い・不正な場合は従来どおり
// (new Move(gen, name)) と完全に同じものになる。
function buildMove(moveName, specValue, crit) {
  const info = moveSpecInfo(moveName);
  let moveObj = null;
  if (info && specValue != null && Number.isFinite(+specValue)) {
    const v = Math.min(info.max, Math.max(info.min, Math.floor(+specValue)));
    if (info.kind === 'hits') {
      moveObj = new Move(gen, moveName, { hits: v });
    } else {
      // ふんどのこぶし / おはかまいり: 威力 = 50 + 50 × 指定値
      moveObj = new Move(gen, moveName, { overrides: { basePower: 50 + 50 * v } });
    }
  }
  if (!moveObj) moveObj = new Move(gen, moveName);
  if (crit) moveObj.isCrit = true;
  return moveObj;
}

/* ---------- 推定エンジン用ヘルパー ---------- */

// 1 回の攻撃のダメージロール (16 本) を返す
// atkSpec/defSpec は toPokemon が受ける spec 形式。opts: {weather, terrain, gameType, crit, atkSide, defSide, moveSpec}
// moveSpec は技ごとの指定値 (moveSpecInfo の kind に対応する数値)。
// ヒット数を指定した連続技では、ヒットごとのロールを合計した 16 本を返す。
// 指定がない場合の戻り値は従来と完全に同じ。
export function damageRolls(atkSpec, defSpec, moveName, opts = {}) {
  const atk = toPokemon(atkSpec);
  const def = toPokemon(defSpec);
  const moveObj = buildMove(moveName, opts.moveSpec, opts.crit);
  const field = new Field({
    gameType: opts.gameType || 'Doubles',
    weather: opts.weather || undefined,
    terrain: opts.terrain || undefined,
    attackerSide: opts.atkSide || {},
    defenderSide: opts.defSide || {},
  });
  if (moveObj.category === 'Status') return { rolls: [], status: true };
  if (isImmune(atk, def, moveObj)) return { rolls: [0], immune: true };
  try {
    const r = calculate(gen, atk, def, moveObj, field);
    const d = r.damage;
    const info = moveSpecInfo(moveName);
    if (opts.moveSpec != null && info && info.kind === 'hits' &&
        Array.isArray(d) && Array.isArray(d[0])) {
      // ヒットごとのロール (ヒット数 × 16) を要素ごとに合計し、
      // 合計ダメージの 16 本として返す
      const totals = new Array(16).fill(0);
      for (const hitRolls of d) {
        if (!Array.isArray(hitRolls)) continue;
        for (let i = 0; i < 16; i++) totals[i] += hitRolls[i] || 0;
      }
      return { rolls: totals };
    }
    return { rolls: Array.isArray(d) ? d : [d] };
  } catch (e) {
    return { rolls: [], error: e.message };
  }
}

export const NATURES = ['Adamant', 'Bashful', 'Bold', 'Brave', 'Calm', 'Careful', 'Docile', 'Gentle', 'Hardy', 'Hasty', 'Impish', 'Jolly', 'Lax', 'Lonely', 'Mild', 'Modest', 'Naive', 'Naughty', 'Quiet', 'Quirky', 'Rash', 'Relaxed', 'Sassy', 'Serious', 'Timid'];

// 種族の各能力について (性格, SP) -> 実数値 の対応表 (推定エンジン用, キャッシュ付き)
const _statTables = {};
export function statTable(speciesName) {
  if (_statTables[speciesName]) return _statTables[speciesName];
  const s = gen.species.get(String(speciesName).toLowerCase().replace(/[^a-z0-9]/g, ''));
  if (!s) return null;
  const table = {};
  for (const stat of STAT_KEYS) {
    const rows = [];
    for (const nature of NATURES) {
      for (let sp = 0; sp <= 32; sp++) {
        rows.push({ nature, sp, value: calcStat(gen, stat, s.baseStats[stat], 31, sp * 8, 50, nature) });
      }
    }
    table[stat] = rows;
  }
  _statTables[speciesName] = table;
  return table;
}

// 技の基本データ (推定エンジンと範囲技判定用)
// spec は技ごとの指定値のメタ情報 (moveSpecInfo と同じ形)。
// 指定できる技では {kind, min, max, def}、それ以外は null。
export function moveData(name) {
  const m = gen.moves.get(String(name).toLowerCase().replace(/[^a-z0-9]/g, ''));
  if (!m) return null;
  return {
    name: m.name, category: m.category, type: m.type, target: m.target,
    priority: m.priority || 0, multihit: m.multihit || null,
    fixedDamage: m.fixedDamage || null, basePower: m.basePower,
    spec: moveSpecInfo(name),
  };
}
