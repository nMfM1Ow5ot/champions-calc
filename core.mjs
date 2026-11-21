// Champions ダメージ計算コア
// Championsの実数値は @smogon/calc (gen9) で IV31 / Lv50 / EV = SP x 8 と置くと完全一致する (検証済み)
import { Generations, Pokemon, Move, Field, calculate, calcStat } from '@smogon/calc';

export const gen = Generations.get(9);

// ---- 仕様差分レイヤー (バランス調整への対応) ----
// data/spec_patches.json のバージョンを @smogon/calc の gen データへ直接
// 上書きする。calc のデータオブジェクトは凍結されておらず、上書きは
// calculate() / statTable / damageRolls / 型推定エンジン (同じ gen を参照)
// のすべてに反映される。差分が無い (未適用) 状態では一切触らないため、
// 計算結果は従来と完全に同一になる。対象はデータで表せるもの (種族値・
// タイプ・技の威力/命中/タイプ/分類/優先度・タイプ相性) に限る。特性や
// 道具の効果そのものの変更は calc 内部のコード依存のため対象外。
let specPatchData = null;
let activeSpecPatchVer = null;
const specPristine = new Map(); // key -> { obj, prop, value } (復元用)
const patchIdOf = name => String(name).toLowerCase().replace(/[^a-z0-9]/g, '');
function patchAssign(obj, prop, value, key) {
  if (!specPristine.has(key)) specPristine.set(key, { obj, prop, value: obj[prop] });
  obj[prop] = value;
}
export function setSpecPatchData(data) {
  specPatchData = data && Array.isArray(data.versions) ? data : { versions: [] };
}
export function specPatchVersions() { return specPatchData ? specPatchData.versions : []; }
export function activeSpecPatch() { return activeSpecPatchVer; }
// id のバージョンを適用する。null/空は全て復元して現行仕様に戻す
export function applySpecPatch(id) {
  for (const { obj, prop, value } of specPristine.values()) obj[prop] = value;
  specPristine.clear();
  activeSpecPatchVer = null;
  // statTable のキャッシュは gen データから作られているため、切り替え時は破棄する
  for (const k of Object.keys(_statTables)) delete _statTables[k];
  if (!id || !specPatchData) return null;
  const v = specPatchData.versions.find(x => x.id === id);
  if (!v) return null;
  for (const [name, patch] of Object.entries(v.species || {})) {
    const sp = gen.species.get(patchIdOf(name));
    if (!sp) continue;
    for (const [prop, val] of Object.entries(patch)) {
      if (prop === 'baseStats' && val && typeof val === 'object') {
        for (const [k, bv] of Object.entries(val)) patchAssign(sp.baseStats, k, bv, `sp:${sp.id}:bs:${k}`);
      } else patchAssign(sp, prop, val, `sp:${sp.id}:${prop}`);
    }
  }
  for (const [name, patch] of Object.entries(v.moves || {})) {
    const mv = gen.moves.get(patchIdOf(name));
    if (!mv) continue;
    for (const [prop, val] of Object.entries(patch)) patchAssign(mv, prop, val, `mv:${mv.id}:${prop}`);
  }
  for (const [atkType, defs] of Object.entries(v.types || {})) {
    const t = gen.types.get(patchIdOf(atkType));
    if (!t || !t.effectiveness) continue;
    for (const [defType, mult] of Object.entries(defs)) patchAssign(t.effectiveness, defType, mult, `ty:${t.name}:${defType}`);
  }
  activeSpecPatchVer = v;
  return v;
}

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
  if (!s || !s.baseStats || !actual) return [];
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
  // calc データに無い種族名でもパネル構築が落ちないようにする (防御的措置。
  // 通常はユニバースの範囲内なので到達しない)
  if (!s || !s.baseStats) return { sp: {}, nature: 'Serious', ability: '', item: undefined, note: '想定データなし' };
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
    // テラスタル中のみテラスタイプを渡す (エンジンが STAB・タイプ変化を処理する)
    teraType: spec.terastallized && spec.teraType ? spec.teraType : undefined,
    // ダイマックス中は HP が倍化する (エンジンが maxHP・現在 HP に反映する)
    isDynamaxed: spec.dynamax ? true : undefined,
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

// ---- 回復を考慮した KO テキスト (きのみ / ねをはる) ----
// @smogon/calc の kochance は たべのこし / グラスフィールド / やどりぎのタネ
// (Side.isSeeded) 等のターン終了時効果は織り込むが、オボンのみ・オレンのみ
// (被弾で HP が半分以下になった時点で発動する回復) と ねをはる は扱わない。
// それらが関係する局面だけ、ライブラリと同じ前提 (ハザード + ターン終了時
// 効果) でダメージ乱数を回して KO テキストを作り直す。それ以外は従来どおり
// ライブラリのテキストを使う。
function koSerializeTexts(texts) {
  if (!texts.length) return '';
  if (texts.length === 1) return texts[0];
  if (texts.length === 2) return texts[0] + ' and ' + texts[1];
  return texts.slice(0, -1).join(', ') + ', and ' + texts[texts.length - 1];
}
// ライブラリ getHazards の移植 (gen9 前提)
function koHazards(defender, side) {
  let damage = 0; const texts = [];
  if (!side) return { damage, texts };
  if (side.isSR && !defender.hasAbility('Magic Guard', 'Mountaineer')) {
    const rockType = gen.types.get('rock');
    const eff = defender.teraType && defender.teraType !== 'Stellar'
      ? rockType.effectiveness[defender.teraType]
      : rockType.effectiveness[defender.types[0]] * (defender.types[1] ? rockType.effectiveness[defender.types[1]] : 1);
    damage += Math.max(Math.floor((eff * defender.maxHP()) / 8), 1);
    texts.push('Stealth Rock');
  }
  if (!defender.hasType('Flying') && !defender.hasAbility('Magic Guard', 'Levitate', 'Eelevate') && !defender.hasItem('Air Balloon')) {
    if (side.spikes === 1) { damage += Math.floor(defender.maxHP() / 8); texts.push('1 layer of Spikes'); }
    else if (side.spikes === 2) { damage += Math.floor(defender.maxHP() / 6); texts.push('2 layers of Spikes'); }
    else if (side.spikes === 3) { damage += Math.floor(defender.maxHP() / 4); texts.push('3 layers of Spikes'); }
  }
  return { damage: isNaN(damage) ? 0 : damage, texts };
}
// ライブラリ getEndOfTurn の移植 (gen9 前提) + ねをはる / アクアリング。damage は正が回復。
function koEndOfTurn(attacker, defender, move, field, ingrain, aquaring) {
  let damage = 0; const texts = [];
  const loseItem = move.named('Knock Off') && !defender.hasAbility('Sticky Hold');
  const healBlock = move.named('Psychic Noise') &&
    !(attacker.hasAbility('Sheer Force') || defender.hasItem('Covert Cloak') || defender.hasAbility('Shield Dust', 'Aroma Veil'));
  const maxHP = defender.maxHP();
  if (field.hasWeather('Sun', 'Harsh Sunshine')) {
    if (defender.hasAbility('Dry Skin', 'Solar Power')) { damage -= Math.floor(maxHP / 8); texts.push(defender.ability + ' damage'); }
  } else if (field.hasWeather('Rain', 'Heavy Rain') && !healBlock) {
    if (defender.hasAbility('Dry Skin')) { damage += Math.floor(maxHP / 8); texts.push('Dry Skin recovery'); }
    else if (defender.hasAbility('Rain Dish')) { damage += Math.floor(maxHP / 16); texts.push('Rain Dish recovery'); }
  } else if (field.hasWeather('Sand')) {
    if (!defender.hasType('Rock', 'Ground', 'Steel') && !defender.hasAbility('Magic Guard', 'Overcoat', 'Sand Force', 'Sand Rush', 'Sand Veil') && !defender.hasItem('Safety Goggles')) {
      damage -= Math.floor(maxHP / 16); texts.push('sandstorm damage');
    }
  } else if (field.hasWeather('Hail', 'Snow')) {
    if (defender.hasAbility('Ice Body') && !healBlock) { damage += Math.floor(maxHP / 16); texts.push('Ice Body recovery'); }
    else if (!defender.hasType('Ice') && !defender.hasAbility('Magic Guard', 'Overcoat', 'Snow Cloak') && !defender.hasItem('Safety Goggles') && field.hasWeather('Hail')) {
      damage -= Math.floor(maxHP / 16); texts.push('hail damage');
    }
  }
  if (defender.hasItem('Leftovers') && !loseItem && !healBlock) { damage += Math.floor(maxHP / 16); texts.push('Leftovers recovery'); }
  else if (defender.hasItem('Black Sludge') && !loseItem) {
    if (defender.hasType('Poison')) { if (!healBlock) { damage += Math.floor(maxHP / 16); texts.push('Black Sludge recovery'); } }
    else if (!defender.hasAbility('Magic Guard', 'Klutz')) { damage -= Math.floor(maxHP / 8); texts.push('Black Sludge damage'); }
  } else if (defender.hasItem('Sticky Barb') && !loseItem && !defender.hasAbility('Magic Guard', 'Klutz')) {
    damage -= Math.floor(maxHP / 8); texts.push('Sticky Barb damage');
  }
  if (field.defenderSide && field.defenderSide.isSeeded && !defender.hasAbility('Magic Guard')) {
    damage -= Math.floor(maxHP / 8); texts.push('Leech Seed damage');
  }
  if (field.attackerSide && field.attackerSide.isSeeded && !attacker.hasAbility('Magic Guard')) {
    let recovery = Math.floor(attacker.maxHP() / 8);
    if (defender.hasItem('Big Root')) recovery = Math.trunc(recovery * 5324 / 4096);
    if (attacker.hasAbility('Liquid Ooze')) { damage -= recovery; texts.push('Liquid Ooze damage'); }
    else if (!healBlock) { damage += recovery; texts.push('Leech Seed recovery'); }
  }
  if (field.hasTerrain('Grassy')) {
    const grounded = !defender.hasType('Flying') && !defender.hasAbility('Levitate') && !defender.hasItem('Air Balloon');
    if (grounded && !healBlock) { damage += Math.floor(maxHP / 16); texts.push('Grassy Terrain recovery'); }
  }
  if (ingrain && !healBlock) { damage += Math.floor(maxHP / 16); texts.push('Ingrain recovery'); }
  if (aquaring && !healBlock) { damage += Math.floor(maxHP / 16); texts.push('Aqua Ring recovery'); }
  if (defender.hasStatus('psn')) {
    if (defender.hasAbility('Poison Heal')) { if (!healBlock) { damage += Math.floor(maxHP / 8); texts.push('Poison Heal'); } }
    else if (!defender.hasAbility('Magic Guard')) { damage -= Math.floor(maxHP / 8); texts.push('poison damage'); }
  } else if (defender.hasStatus('tox')) {
    if (defender.hasAbility('Poison Heal')) { if (!healBlock) { damage += Math.floor(maxHP / 8); texts.push('Poison Heal'); } }
    else if (!defender.hasAbility('Magic Guard')) { texts.push('toxic damage'); }
  } else if (defender.hasStatus('brn')) {
    if (defender.hasAbility('Heatproof')) { damage -= Math.floor(maxHP / 32); texts.push('reduced burn damage'); }
    else if (!defender.hasAbility('Magic Guard')) { damage -= Math.floor(maxHP / 16); texts.push('burn damage'); }
  } else if ((defender.hasStatus('slp') || defender.hasAbility('Comatose')) && attacker.hasAbility('Bad Dreams') && !defender.hasAbility('Magic Guard')) {
    damage -= Math.floor(maxHP / 8); texts.push('Bad Dreams');
  }
  return { damage, texts };
}
// ライブラリ computeKOChance の移植 + きのみの発動 (残り HP が半分以下で回復し、消費する)
function koChanceRec(damage, hp, eot, toxicCounter, maxHP, berryHeal, hits) {
  let toxicDamage = 0, tc = toxicCounter;
  if (tc > 0) { toxicDamage = Math.floor(tc * maxHP / 16); tc++; }
  const n = damage.length;
  if (hits === 1) {
    let e = eot, t = toxicDamage;
    if (e - t > 0) { e = 0; t = 0; }
    for (let i = 0; i < n; i++) {
      if (damage[n - 1] - e + t < hp) return 0;
      if (damage[i] - e + t >= hp) return (n - i) / n;
    }
    return 0;
  }
  let sum = 0;
  const cache = new Map();
  for (let i = 0; i < n; i++) {
    const afterHit = hp - damage[i];
    let c;
    if (afterHit <= 0) c = 1;
    else {
      let nh = afterHit, nb = berryHeal;
      if (nb > 0 && nh <= maxHP / 2) { nh += nb; nb = 0; }
      nh += eot - toxicDamage;
      if (nh <= 0) c = 1;
      else {
        const key = nh + '|' + nb;
        if (cache.has(key)) c = cache.get(key);
        else { c = koChanceRec(damage, nh, eot, tc, maxHP, nb, hits - 1); cache.set(key, c); }
      }
    }
    if (c === 1) { sum += n - i; break; }
    sum += c;
  }
  return sum / n;
}
// きのみ / ねをはる が関係する局面の KO テキスト。関係しなければ null (ライブラリのテキストを使う)
// ライブラリは 9HKO までしか KO テキストを返さないため、それを超える低ダメージ
// では最大ロール基準の必要発数を補う (possible nHKO)。ターン終了時の回復が
// 最大ダメージ以上なら、繰り返しても倒せないため補わない (null)
export function fallbackKoText(attacker, defender, move, field, maxDmg, ingrain, aquaring) {
  try {
    const eot = koEndOfTurn(attacker, defender, move, field, !!ingrain, !!aquaring);
    const per = maxDmg - eot.damage;
    if (per <= 0) return null;
    const n = Math.ceil((defender.curHP() - eot.damage) / per);
    return n > 1 ? `possible ${n}HKO` : null;
  } catch (e) { return null; }
}

function clampBoost(v) { return Math.max(-6, Math.min(6, v)); }
function boostsWith(base, deltas) {
  const b = { ...(base || {}) };
  for (const k of ['atk', 'def', 'spa', 'spd', 'spe', 'acc', 'eva']) if (deltas[k]) b[k] = clampBoost((b[k] || 0) + deltas[k]);
  return b;
}
function convolveDist(a, b) {
  const out = new Map();
  for (const [d1, p1] of a) for (const [d2, p2] of b) out.set(d1 + d2, (out.get(d1 + d2) || 0) + p1 * p2);
  return out;
}
// result.damage (単発=16本 / 連続技=ヒットごとの入れ子) をダメージ分布 Map にする
function damageDist(raw) {
  if (typeof raw === 'number') return new Map([[raw, 1]]);
  if (!Array.isArray(raw) || !raw.length) return null;
  if (typeof raw[0] === 'number') {
    const m = new Map();
    for (const d of raw) m.set(d, (m.get(d) || 0) + 1 / raw.length);
    return m;
  }
  let acc = new Map([[0, 1]]);
  for (const sub of raw) {
    const sd = damageDist(sub);
    if (!sd) return null;
    acc = convolveDist(acc, sd);
  }
  return acc;
}
// ターンごとにダメージ分布が変わる場合の KO 確率 (koChanceRec の一般化)
function koChanceDyn(dists, hp, eotDamage, toxicCounter, maxHP, berryHeal, turns) {
  const memo = new Map();
  const rec = (ti, h, berry, tc, left) => {
    if (left === 0) return 0;
    const key = ti + '|' + h + '|' + berry + '|' + tc + '|' + left;
    if (memo.has(key)) return memo.get(key);
    const dist = dists[Math.min(ti, dists.length - 1)];
    let sum = 0;
    for (const [d, p] of dist) {
      const afterHit = h - d;
      if (afterHit <= 0) { sum += p; continue; }
      let nh = afterHit, nb = berry;
      if (nb > 0 && nh <= maxHP / 2) { nh += nb; nb = 0; }
      const td = tc > 0 ? Math.floor(tc * maxHP / 16) : 0;
      nh += eotDamage - td;
      if (nh <= 0) { sum += p; continue; }
      sum += p * rec(ti + 1, nh, nb, tc > 0 ? tc + 1 : 0, left - 1);
    }
    memo.set(key, sum);
    return sum;
  };
  return rec(0, hp, berryHeal, toxicCounter, turns);
}

function recoveryKoText(attacker, defender, move, field, result, koCtx, defIdx, atkSpec, defSpec) {
  const raw = result.damage;
  const damage = Array.isArray(raw) ? (raw.every(x => typeof x === 'number') ? raw : null) : (typeof raw === 'number' ? [raw] : null);
  const baseDist = damageDist(raw);
  if (!baseDist || !baseDist.size) return null;
  if (Math.max(...baseDist.keys()) === 0) return null;
  const maxHP = defender.maxHP();
  const ingrain = !!(koCtx && koCtx.defIngrain && koCtx.defIngrain[defIdx]);
  const aquaring = !!(koCtx && koCtx.defAquaRing && koCtx.defAquaRing[defIdx]);
  const octolock = !!(koCtx && koCtx.defOctolock && koCtx.defOctolock[defIdx]);
  // 毎ターン変動する要素: 受ける側のヒットごとのランク変化 (じきゅうりょく /
  // よわきのよろい / せいぎのこころ)、使う側の技の自己ランク変化 (りゅうせいぐん
  // 等。あまのじゃくで反転)、たこがためのターン終了ごとの低下 (あまのじゃくで上昇)
  const defPerHit = {};
  const defCat = move.defensiveCategory || move.category;
  if (defender.hasAbility('Stamina') && defCat === 'Physical') defPerHit.def = (defPerHit.def || 0) + 1;
  if (defender.hasAbility('Weak Armor') && move.category === 'Physical') defPerHit.def = (defPerHit.def || 0) - 1;
  if (defender.hasAbility('Justified') && move.type === 'Dark') defPerHit.atk = (defPerHit.atk || 0) + 1;
  let atkPerUse = 0, atkPerUseStat = null;
  const rawMoveData = gen.moves.get(String(move.name).toLowerCase().replace(/[^a-z0-9]/g, ''));
  const selfB = rawMoveData && rawMoveData.self && rawMoveData.self.boosts;
  if (selfB) {
    const stat = move.category === 'Physical' ? 'atk' : (move.category === 'Special' ? 'spa' : null);
    if (stat && selfB[stat]) { atkPerUseStat = stat; atkPerUse = attacker.hasAbility('Contrary') ? -selfB[stat] : selfB[stat]; }
  }
  const dyn = !!(Object.keys(defPerHit).length || atkPerUse || octolock);
  if (!dyn && (!damage || !damage.length)) return null;
  const loseItem = move.named('Knock Off') && !defender.hasAbility('Sticky Hold');
  const healBlock = move.named('Psychic Noise') &&
    !(attacker.hasAbility('Sheer Force') || defender.hasItem('Covert Cloak') || defender.hasAbility('Shield Dust', 'Aroma Veil'));
  let berryHeal = 0, berryName = '';
  if (!(koCtx && koCtx.unnerve) && !loseItem && !healBlock && !defender.hasAbility('Klutz')) {
    const ripen = defender.hasAbility('Ripen') ? 2 : 1;
    if (defender.hasItem('Sitrus Berry')) { berryHeal = Math.floor(maxHP / 4) * ripen; berryName = 'Sitrus Berry'; }
    else if (defender.hasItem('Oran Berry')) { berryHeal = 10 * ripen; berryName = 'Oran Berry'; }
  }
  if (!berryHeal && !ingrain && !aquaring && !dyn) return null;
  const hazards = koHazards(defender, field.defenderSide);
  let hp = defender.curHP() - hazards.damage;
  if (hp <= 0) return null;
  const eot = koEndOfTurn(attacker, defender, move, field, ingrain, aquaring);
  const toxicCounter = defender.hasStatus('tox') && !defender.hasAbility('Magic Guard', 'Poison Heal') ? (defender.toxicCounter || 0) : 0;
  let berry = berryHeal;
  if (berry > 0 && hp <= maxHP / 2) { hp += berry; berry = 0; }
  const texts = [];
  if (berryHeal) texts.push(berryName + ' recovery');
  for (const t of hazards.texts) texts.push(t);
  for (const t of eot.texts) texts.push(t);
  const after = texts.length ? ' after ' + koSerializeTexts(texts) : '';
  const roundChance = c => Math.max(Math.min(Math.round(c * 1000), 999), 1) / 10;
  if (dyn) {
    const hitsPerUse = Array.isArray(raw) && raw.length && Array.isArray(raw[0]) ? raw.length : (move.hits || 1);
    const dynText = dynamicKoText({ attacker, defender, move, field, atkSpec, defSpec, baseDist, hitsPerUse, defPerHit, atkPerUse, atkPerUseStat, octolock, hp, berry, eotDamage: eot.damage, toxicCounter, maxHP, after, roundChance, ingrain, aquaring });
    if (dynText !== null) return dynText;
  }
  const c1 = koChanceRec(damage, hp, eot.damage, toxicCounter, maxHP, berry, 1);
  if (c1 > 0) {
    if (c1 === 1) return 'guaranteed OHKO';
    return `${roundChance(c1)}% chance to OHKO${after}`;
  }
  for (let n = 2; n <= 4; n++) {
    const c = koChanceRec(damage, hp, eot.damage, toxicCounter, maxHP, berry, n);
    if (c > 0) {
      if (c === 1) return `guaranteed ${n}HKO${after}`;
      return `${roundChance(c)}% chance to ${n}HKO${after}`;
    }
  }
  const predict = (roll, n) => {
    let h = hp, b = berry;
    for (let k = 0; k < n; k++) {
      h -= roll;
      if (h <= 0) return true;
      if (b > 0 && h <= maxHP / 2) { h += b; b = 0; }
      if (k < n - 1) {
        const td = toxicCounter > 0 ? Math.floor((toxicCounter + k) * maxHP / 16) : 0;
        h += eot.damage - td;
        if (h <= 0) return true;
      }
    }
    return false;
  };
  for (let n = 5; n <= 9; n++) {
    if (predict(damage[0], n)) return `guaranteed ${n}HKO${after}`;
    if (predict(damage[damage.length - 1], n)) return `possible ${n}HKO${after}`;
  }
  return null;
}

// 毎ターン変動 (ランク変化) を織り込んだ KO テキスト。ターンごとに、その時点の
// ランクで再計算したダメージ分布を使う。連続技はヒットごとにランクが進む。
// 戻り値: 文字列 = KO テキスト / '' = 繰り返しても倒せない / null = 計算不能
function dynamicKoText(ctx) {
  const { attacker, defender, move, field, atkSpec, defSpec, baseDist, hitsPerUse, defPerHit, atkPerUse, atkPerUseStat, octolock, hp, berry, eotDamage, toxicCounter, maxHP, after, roundChance, ingrain, aquaring } = ctx;
  if (!atkSpec || !defSpec) return null;
  const rawD = baseDist;
  const TURNS = 10;
  let oneHitMove = move;
  if (hitsPerUse > 1) {
    try { oneHitMove = new Move(gen, move.name, { hits: 1 }); if (move.isCrit) oneHitMove.isCrit = true; }
    catch (e) { return null; }
  }
  const octoSign = defender.hasAbility('Contrary') ? 1 : -1;
  const dists = [rawD];
  try {
    for (let t = 1; t < TURNS; t++) {
      const aBoosts = atkPerUse ? boostsWith(atkSpec.boosts, { [atkPerUseStat]: atkPerUse * t }) : atkSpec.boosts;
      const dStart = {};
      for (const k in defPerHit) dStart[k] = defPerHit[k] * hitsPerUse * t;
      if (octolock) { dStart.def = (dStart.def || 0) + octoSign * t; dStart.spd = (dStart.spd || 0) + octoSign * t; }
      const atkP = toPokemon({ ...atkSpec, boosts: aBoosts });
      let dist = null;
      if (hitsPerUse === 1) {
        const rr = calculate(gen, atkP, toPokemon({ ...defSpec, boosts: boostsWith(defSpec.boosts, dStart) }), move, field);
        dist = damageDist(rr.damage);
      } else {
        let acc = new Map([[0, 1]]);
        for (let k = 0; k < hitsPerUse; k++) {
          const dk = { ...dStart };
          for (const key in defPerHit) dk[key] = (dk[key] || 0) + defPerHit[key] * k;
          const rr = calculate(gen, atkP, toPokemon({ ...defSpec, boosts: boostsWith(defSpec.boosts, dk) }), oneHitMove, field);
          const hd = damageDist(rr.damage);
          if (!hd) { acc = null; break; }
          acc = convolveDist(acc, hd);
        }
        dist = acc;
      }
      if (!dist) return null;
      dists.push(dist);
    }
  } catch (e) { return null; }
  const c1 = koChanceDyn(dists, hp, eotDamage, toxicCounter, maxHP, berry, 1);
  if (c1 > 0) {
    if (c1 === 1) return 'guaranteed OHKO';
    return `${roundChance(c1)}% chance to OHKO${after}`;
  }
  for (let n = 2; n <= 4; n++) {
    const c = koChanceDyn(dists, hp, eotDamage, toxicCounter, maxHP, berry, n);
    if (c > 0) {
      if (c === 1) return `guaranteed ${n}HKO${after}`;
      return `${roundChance(c)}% chance to ${n}HKO${after}`;
    }
  }
  const distMin = dists.map(d => Math.min(...d.keys()));
  const distMax = dists.map(d => Math.max(...d.keys()));
  const predictDyn = (arr, n) => {
    let h = hp, b = berry;
    for (let k = 0; k < n; k++) {
      h -= arr[Math.min(k, arr.length - 1)];
      if (h <= 0) return true;
      if (b > 0 && h <= maxHP / 2) { h += b; b = 0; }
      if (k < n - 1) {
        const td = toxicCounter > 0 ? Math.floor((toxicCounter + k) * maxHP / 16) : 0;
        h += eotDamage - td;
        if (h <= 0) return true;
      }
    }
    return false;
  };
  for (let n = 5; n <= 9; n++) {
    if (predictDyn(distMin, n)) return `guaranteed ${n}HKO${after}`;
    if (predictDyn(distMax, n)) return `possible ${n}HKO${after}`;
  }
  // 10 ターンでも倒し切れない場合: 飽和した最終ターンの最大ダメージで推定する
  const fb = fallbackKoText(attacker, defender, move, field, distMax[distMax.length - 1], ingrain, aquaring);
  const fm = fb && fb.match(/possible (\d+)HKO/);
  return fm && +fm[1] > 9 ? fb : '';
}

function calcDirection(attackers, defenders, atkSpecs, defSpecs, field, critFlags, fieldSingle, singleMoves, moveSpecs, moveZ, koCtx) {
  const out = [];
  atkSpecs.forEach((spec, i) => {
    const entry = { attacker: i, species: spec.mega && spec.megaSpecies ? spec.megaSpecies : spec.species, moveResults: [] };
    for (const mv of spec.moves || []) {
      const row = { move: mv, vs: [] };
      if (!mv || !gen.moves.get(String(mv).toLowerCase().replace(/[^a-z0-9]/g, ''))) { for (let j = 0; j < defenders.length; j++) row.vs.push({ status: true }); entry.moveResults.push(row); continue; }
      const moveObj = buildMove(mv, moveSpecs && moveSpecs[i] ? moveSpecs[i][mv] : undefined, !!(critFlags && critFlags[i]), !!(moveZ && moveZ[i] && moveZ[i][mv]), spec);
      const useField = fieldSingle && singleMoves && singleMoves.includes(mv) ? fieldSingle : field;
      for (let j = 0; j < defenders.length; j++) {
        if (moveObj.category === 'Status') { row.vs.push({ status: true }); continue; }
        if (isImmune(attackers[i], defenders[j], moveObj)) { row.vs.push({ min: 0, max: 0, minPct: 0, maxPct: 0, ko: '', immune: true }); continue; }
        try {
          const r = calculate(gen, attackers[i], defenders[j], moveObj, useField);
          const range = r.range();
          const defMaxHP = defenders[j].maxHP();
          let koText = r.kochance().text;
          let descText = r.desc();
          const customKo = recoveryKoText(attackers[i], defenders[j], moveObj, useField, r, koCtx, j, atkSpecs[i], defSpecs[j]);
          if (customKo !== null) {
            koText = customKo;
            if (customKo) {
              const libKo = r.kochance().text;
              if (libKo && descText.endsWith(libKo)) descText = descText.slice(0, descText.length - libKo.length) + customKo;
              else if (!libKo) descText = descText + ' -- ' + customKo;
            }
          }
          if (!koText && customKo === null && range[1] > 0) {
            const fb = fallbackKoText(attackers[i], defenders[j], moveObj, useField, range[1],
              !!(koCtx && koCtx.defIngrain && koCtx.defIngrain[j]),
              !!(koCtx && koCtx.defAquaRing && koCtx.defAquaRing[j]));
            if (fb) { koText = fb; descText = descText + ' -- ' + fb; }
          }
          row.vs.push({
            min: range[0], max: range[1],
            minPct: Math.round(range[0] / defMaxHP * 1000) / 10,
            maxPct: Math.round(range[1] / defMaxHP * 1000) / 10,
            ko: koText,
            desc: descText,
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
//   moveZ (任意): { mine: [{技名: true}, ...], opps: [...] } Zワザ化する技 (スロットごと)
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
  // きのみの無効化 (きんちょうかん) は攻撃側の場全体で判定する。場の特性一覧は
  // calcAll が state.fieldAbilities で渡す (無い場合は選出中の1体だけを見る)
  const effAbilityOf = s => (s && s.mega && s.megaAbility) ? s.megaAbility : (s ? s.ability : '');
  const koCtxFor = (atkKey, defKey, defSpecs) => {
    const fa = state.fieldAbilities || {};
    const atkAb = fa[atkKey] && fa[atkKey].length ? fa[atkKey] : (state[atkKey] || []).map(effAbilityOf);
    const allAb = [...(fa.mine || []), ...(fa.opps || [])];
    const gas = allAb.includes('Neutralizing Gas');
    const unnerve = !gas && atkAb.some(a => a === 'Unnerve' || a === 'As One (Glastrier)' || a === 'As One (Spectrier)');
    return { unnerve, defIngrain: (defSpecs || []).map(s => !!s.ingrain), defAquaRing: (defSpecs || []).map(s => !!s.aquaring), defOctolock: (defSpecs || []).map(s => !!s.octolock) };
  };
  out.results = calcDirection(mine, opps, state.mine, state.opps, field, state.crit && state.crit.mine, fieldS, state.singleMoves && state.singleMoves.mine, state.moveSpecs && state.moveSpecs.mine, state.moveZ && state.moveZ.mine, koCtxFor('mine', 'opps', state.opps));
  out.oppResults = calcDirection(opps, mine, state.opps, state.mine, oppField, state.crit && state.crit.opps, oppFieldS, state.singleMoves && state.singleMoves.opps, state.moveSpecs && state.moveSpecs.opps, state.moveZ && state.moveZ.opps, koCtxFor('opps', 'mine', state.mine));
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
  return { ...spec, curHP: Math.max(1, Math.floor(p.maxHP() * spec.curHPPercent / 100)) };
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


/* ---------- Zワザ ---------- */
// 専用 Zワザ: [種族, ベース技, Zクリスタル, Zワザ名]。威力・タイプ・分類は
// calc の技データ側が持つ (専用 Z は実威力が入っている)。出典: Pokémon
// Showdown data/items.ts の zMoveFrom / itemUser (2026-11-21 抽出)
export const Z_EXCLUSIVE = [
  ['Raichu-Alola', 'Thunderbolt', 'Aloraichium Z', 'Stoked Sparksurfer'],
  ['Decidueye', 'Spirit Shackle', 'Decidium Z', 'Sinister Arrow Raid'],
  ['Eevee', 'Last Resort', 'Eevium Z', 'Extreme Evoboost'],
  ['Incineroar', 'Darkest Lariat', 'Incinium Z', 'Malicious Moonsault'],
  ['Kommo-o', 'Clanging Scales', 'Kommonium Z', 'Clangorous Soulblaze'],
  ['Kommo-o-Totem', 'Clanging Scales', 'Kommonium Z', 'Clangorous Soulblaze'],
  ['Lunala', 'Moongeist Beam', 'Lunalium Z', 'Menacing Moonraze Maelstrom'],
  ['Necrozma-Dawn-Wings', 'Moongeist Beam', 'Lunalium Z', 'Menacing Moonraze Maelstrom'],
  ['Lycanroc', 'Stone Edge', 'Lycanium Z', 'Splintered Stormshards'],
  ['Lycanroc-Midnight', 'Stone Edge', 'Lycanium Z', 'Splintered Stormshards'],
  ['Lycanroc-Dusk', 'Stone Edge', 'Lycanium Z', 'Splintered Stormshards'],
  ['Marshadow', 'Spectral Thief', 'Marshadium Z', 'Soul-Stealing 7-Star Strike'],
  ['Mew', 'Psychic', 'Mewnium Z', 'Genesis Supernova'],
  ['Mimikyu', 'Play Rough', 'Mimikium Z', "Let's Snuggle Forever"],
  ['Mimikyu-Busted', 'Play Rough', 'Mimikium Z', "Let's Snuggle Forever"],
  ['Pikachu', 'Volt Tackle', 'Pikanium Z', 'Catastropika'],
  ['Pikachu-Original', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Hoenn', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Sinnoh', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Unova', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Kalos', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Alola', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Pikachu-Partner', 'Thunderbolt', 'Pikashunium Z', '10,000,000 Volt Thunderbolt'],
  ['Primarina', 'Sparkling Aria', 'Primarium Z', 'Oceanic Operetta'],
  ['Snorlax', 'Giga Impact', 'Snorlium Z', 'Pulverizing Pancake'],
  ['Solgaleo', 'Sunsteel Strike', 'Solganium Z', 'Searing Sunraze Smash'],
  ['Necrozma-Dusk-Mane', 'Sunsteel Strike', 'Solganium Z', 'Searing Sunraze Smash'],
  ['Tapu Koko', "Nature's Madness", 'Tapunium Z', 'Guardian of Alola'],
  ['Tapu Lele', "Nature's Madness", 'Tapunium Z', 'Guardian of Alola'],
  ['Tapu Bulu', "Nature's Madness", 'Tapunium Z', 'Guardian of Alola'],
  ['Tapu Fini', "Nature's Madness", 'Tapunium Z', 'Guardian of Alola'],
  ['Necrozma-Ultra', 'Photon Geyser', 'Ultranecrozium Z', 'Light That Burns the Sky'],
];
// ベース技の汎用 Zワザ名 (エンジンに解決させる)
export function zMoveNameOf(moveName) {
  try { return new Move(gen, moveName, { useZ: true }).name; } catch (e) { return null; }
}
// 種族・持ち物・ベース技が専用 Z の組み合わせなら Zワザ名を返す
export function exclusiveZMove(species, item, moveName) {
  if (!species || !item || !moveName) return null;
  for (const [sp, mv, it, zm] of Z_EXCLUSIVE) {
    if (sp === species && mv === moveName && it === item) return zm;
  }
  return null;
}
// Z変化技の効果 (ダメージ計算には現れないため表示専用)。b = 能力上昇、
// e = 特殊効果。出典: Pokémon Showdown data/moves.ts の zMove (2026-11-21 抽出)
export const Z_STATUS = {
"Acid Armor":{e:'clearnegativeboost'},
"Acupressure":{e:'crit2'},
"After You":{b:{spe:1}},
"Agility":{e:'clearnegativeboost'},
"Ally Switch":{b:{spe:2}},
"Amnesia":{e:'clearnegativeboost'},
"Aqua Ring":{b:{def:1}},
"Aromatherapy":{e:'heal'},
"Aromatic Mist":{b:{spd:2}},
"Attract":{e:'clearnegativeboost'},
"Aurora Veil":{b:{spe:1}},
"Autotomize":{e:'clearnegativeboost'},
"Baby-Doll Eyes":{b:{def:1}},
"Baneful Bunker":{b:{def:1}},
"Barrier":{e:'clearnegativeboost'},
"Baton Pass":{e:'clearnegativeboost'},
"Belly Drum":{e:'heal'},
"Bestow":{b:{spe:2}},
"Block":{b:{def:1}},
"Bulk Up":{b:{atk:1}},
"Calm Mind":{e:'clearnegativeboost'},
"Camouflage":{b:{evasion:1}},
"Captivate":{b:{spd:2}},
"Celebrate":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Charge":{b:{spd:1}},
"Charm":{b:{def:1}},
"Coil":{e:'clearnegativeboost'},
"Confide":{b:{spd:1}},
"Confuse Ray":{b:{spa:1}},
"Conversion":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Conversion 2":{e:'heal'},
"Copycat":{b:{accuracy:1}},
"Cosmic Power":{b:{spd:1}},
"Cotton Guard":{e:'clearnegativeboost'},
"Cotton Spore":{e:'clearnegativeboost'},
"Crafty Shield":{b:{spd:1}},
"Curse":{e:'curse'},
"Dark Void":{e:'clearnegativeboost'},
"Defend Order":{b:{def:1}},
"Defense Curl":{b:{accuracy:1}},
"Defog":{b:{accuracy:1}},
"Destiny Bond":{e:'redirect'},
"Detect":{b:{evasion:1}},
"Disable":{e:'clearnegativeboost'},
"Double Team":{e:'clearnegativeboost'},
"Dragon Dance":{e:'clearnegativeboost'},
"Eerie Impulse":{b:{spd:1}},
"Electric Terrain":{b:{spe:1}},
"Electrify":{b:{spa:1}},
"Embargo":{b:{spa:1}},
"Encore":{b:{spe:1}},
"Endure":{e:'clearnegativeboost'},
"Entrainment":{b:{spd:1}},
"Fairy Lock":{b:{def:1}},
"Fake Tears":{b:{spa:1}},
"Feather Dance":{b:{def:1}},
"Flash":{b:{evasion:1}},
"Flatter":{b:{spd:1}},
"Floral Healing":{e:'clearnegativeboost'},
"Flower Shield":{b:{def:1}},
"Focus Energy":{b:{accuracy:1}},
"Follow Me":{e:'clearnegativeboost'},
"Foresight":{e:'crit2'},
"Forest's Curse":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Gastro Acid":{b:{spe:1}},
"Gear Up":{b:{spa:1}},
"Geomancy":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Glare":{b:{spd:1}},
"Grass Whistle":{b:{spe:1}},
"Grassy Terrain":{b:{def:1}},
"Gravity":{b:{spa:1}},
"Growl":{b:{def:1}},
"Growth":{b:{spa:1}},
"Grudge":{e:'redirect'},
"Guard Split":{b:{spe:1}},
"Guard Swap":{b:{spe:1}},
"Hail":{b:{spe:1}},
"Happy Hour":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Harden":{b:{def:1}},
"Haze":{e:'heal'},
"Heal Bell":{e:'heal'},
"Heal Block":{b:{spa:2}},
"Heal Order":{e:'clearnegativeboost'},
"Heal Pulse":{e:'clearnegativeboost'},
"Heart Swap":{e:'crit2'},
"Helping Hand":{e:'clearnegativeboost'},
"Hold Hands":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Hone Claws":{b:{atk:1}},
"Howl":{b:{atk:1}},
"Hypnosis":{b:{spe:1}},
"Imprison":{b:{spd:2}},
"Ingrain":{b:{spd:1}},
"Instruct":{b:{spa:1}},
"Ion Deluge":{b:{spa:1}},
"Iron Defense":{e:'clearnegativeboost'},
"Kinesis":{b:{evasion:1}},
"King's Shield":{e:'clearnegativeboost'},
"Laser Focus":{b:{atk:1}},
"Leech Seed":{e:'clearnegativeboost'},
"Leer":{b:{atk:1}},
"Light Screen":{b:{spd:1}},
"Lock-On":{b:{spe:1}},
"Lovely Kiss":{b:{spe:1}},
"Lucky Chant":{b:{evasion:1}},
"Magic Coat":{b:{spd:2}},
"Magic Room":{b:{spd:1}},
"Magnet Rise":{b:{evasion:1}},
"Magnetic Flux":{b:{spd:1}},
"Mat Block":{b:{def:1}},
"Me First":{b:{spe:2}},
"Mean Look":{b:{spd:1}},
"Meditate":{b:{atk:1}},
"Memento":{e:'healreplacement'},
"Metal Sound":{b:{spa:1}},
"Milk Drink":{e:'clearnegativeboost'},
"Mimic":{b:{accuracy:1}},
"Mind Reader":{b:{spa:1}},
"Minimize":{e:'clearnegativeboost'},
"Miracle Eye":{b:{spa:1}},
"Mirror Move":{b:{atk:2}},
"Mist":{e:'heal'},
"Misty Terrain":{b:{spd:1}},
"Moonlight":{e:'clearnegativeboost'},
"Morning Sun":{e:'clearnegativeboost'},
"Mud Sport":{b:{spd:1}},
"Nasty Plot":{e:'clearnegativeboost'},
"Nightmare":{b:{spa:1}},
"Noble Roar":{b:{def:1}},
"Odor Sleuth":{b:{atk:1}},
"Pain Split":{b:{def:1}},
"Parting Shot":{e:'healreplacement'},
"Perish Song":{e:'clearnegativeboost'},
"Play Nice":{b:{def:1}},
"Poison Gas":{b:{def:1}},
"Poison Powder":{b:{def:1}},
"Powder":{b:{spd:2}},
"Power Split":{b:{spe:1}},
"Power Swap":{b:{spe:1}},
"Power Trick":{b:{atk:1}},
"Protect":{e:'clearnegativeboost'},
"Psych Up":{e:'heal'},
"Psychic Terrain":{b:{spa:1}},
"Psycho Shift":{b:{spa:2}},
"Purify":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Quash":{b:{spe:1}},
"Quick Guard":{b:{def:1}},
"Quiver Dance":{e:'clearnegativeboost'},
"Rage Powder":{e:'clearnegativeboost'},
"Rain Dance":{b:{spe:1}},
"Recover":{e:'clearnegativeboost'},
"Recycle":{b:{spe:2}},
"Reflect":{b:{def:1}},
"Reflect Type":{b:{spa:1}},
"Refresh":{e:'heal'},
"Rest":{e:'clearnegativeboost'},
"Roar":{b:{def:1}},
"Rock Polish":{e:'clearnegativeboost'},
"Role Play":{b:{spe:1}},
"Roost":{e:'clearnegativeboost'},
"Rototiller":{b:{atk:1}},
"Safeguard":{b:{spe:1}},
"Sand Attack":{b:{evasion:1}},
"Sandstorm":{b:{spe:1}},
"Scary Face":{b:{spe:1}},
"Screech":{b:{atk:1}},
"Sharpen":{b:{atk:1}},
"Shed Tail":{e:'clearnegativeboost'},
"Shell Smash":{e:'clearnegativeboost'},
"Shift Gear":{e:'clearnegativeboost'},
"Shore Up":{e:'clearnegativeboost'},
"Simple Beam":{b:{spa:1}},
"Sing":{b:{spe:1}},
"Sketch":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Skill Swap":{b:{spe:1}},
"Slack Off":{e:'clearnegativeboost'},
"Sleep Powder":{b:{spe:1}},
"Sleep Talk":{e:'crit2'},
"Smokescreen":{b:{evasion:1}},
"Snatch":{b:{spe:2}},
"Soak":{b:{spa:1}},
"Soft-Boiled":{e:'clearnegativeboost'},
"Speed Swap":{b:{spe:1}},
"Spider Web":{b:{def:1}},
"Spikes":{b:{def:1}},
"Spiky Shield":{b:{def:1}},
"Spite":{e:'heal'},
"Splash":{b:{atk:3}},
"Spore":{e:'clearnegativeboost'},
"Spotlight":{b:{spd:1}},
"Stealth Rock":{b:{def:1}},
"Sticky Web":{b:{spe:1}},
"Stockpile":{e:'heal'},
"Strength Sap":{b:{def:1}},
"String Shot":{b:{spe:1}},
"Stun Spore":{b:{spd:1}},
"Substitute":{e:'clearnegativeboost'},
"Sunny Day":{b:{spe:1}},
"Supersonic":{b:{spe:1}},
"Swagger":{e:'clearnegativeboost'},
"Swallow":{e:'clearnegativeboost'},
"Sweet Kiss":{b:{spa:1}},
"Sweet Scent":{b:{accuracy:1}},
"Switcheroo":{b:{spe:2}},
"Swords Dance":{e:'clearnegativeboost'},
"Synthesis":{e:'clearnegativeboost'},
"Tail Glow":{e:'clearnegativeboost'},
"Tail Whip":{b:{atk:1}},
"Tailwind":{e:'crit2'},
"Taunt":{b:{atk:1}},
"Tearful Look":{b:{def:1}},
"Teeter Dance":{b:{spa:1}},
"Telekinesis":{b:{spa:1}},
"Teleport":{e:'heal'},
"Thunder Wave":{b:{spd:1}},
"Tickle":{b:{def:1}},
"Topsy-Turvy":{b:{atk:1}},
"Torment":{b:{def:1}},
"Toxic":{b:{def:1}},
"Toxic Spikes":{b:{def:1}},
"Toxic Thread":{b:{spe:1}},
"Transform":{e:'heal'},
"Trick":{b:{spe:2}},
"Trick Room":{b:{accuracy:1}},
"Trick-or-Treat":{b:{atk:1,def:1,spa:1,spd:1,spe:1}},
"Venom Drench":{b:{def:1}},
"Water Sport":{b:{spd:1}},
"Whirlwind":{b:{spd:1}},
"Wide Guard":{b:{def:1}},
"Will-O-Wisp":{b:{atk:1}},
"Wish":{b:{spd:1}},
"Withdraw":{b:{def:1}},
"Wonder Room":{b:{spd:1}},
"Work Up":{b:{atk:1}},
"Worry Seed":{b:{spe:1}},
"Yawn":{b:{spe:1}}
};

// 専用 Z のうち変化技扱いのものの効果 (ベース技は攻撃技なので Z_STATUS に無い)
export const Z_EXCLUSIVE_FX = {
  'Extreme Evoboost': { b: { atk: 2, def: 2, spa: 2, spd: 2, spe: 2 } },
};

/* ---------- ダイマックス ---------- */
// キョダイマックス技: 種族 → {name, type}。タイプが一致する攻撃技がこの技に
// 変わる。出典: Pokémon Showdown data/moves.ts の isMax (2026-11-21 抽出)
export const GMAX_MOVES = {
  'Butterfree': { name: 'G-Max Befuddle', type: 'Bug' },
  'Blastoise': { name: 'G-Max Cannonade', type: 'Water' },
  'Centiskorch': { name: 'G-Max Centiferno', type: 'Fire' },
  'Machamp': { name: 'G-Max Chi Strike', type: 'Fighting' },
  'Eevee': { name: 'G-Max Cuddle', type: 'Normal' },
  'Duraludon': { name: 'G-Max Depletion', type: 'Dragon' },
  'Rillaboom': { name: 'G-Max Drum Solo', type: 'Grass' },
  'Alcremie': { name: 'G-Max Finale', type: 'Fairy' },
  'Cinderace': { name: 'G-Max Fireball', type: 'Fire' },
  'Kingler': { name: 'G-Max Foam Burst', type: 'Water' },
  'Meowth': { name: 'G-Max Gold Rush', type: 'Normal' },
  'Orbeetle': { name: 'G-Max Gravitas', type: 'Psychic' },
  'Inteleon': { name: 'G-Max Hydrosnipe', type: 'Water' },
  'Garbodor': { name: 'G-Max Malodor', type: 'Poison' },
  'Melmetal': { name: 'G-Max Meltdown', type: 'Steel' },
  'Urshifu': { name: 'G-Max One Blow', type: 'Dark' },
  'Urshifu-Rapid-Strike': { name: 'G-Max Rapid Flow', type: 'Water' },
  'Snorlax': { name: 'G-Max Replenish', type: 'Normal' },
  'Lapras': { name: 'G-Max Resonance', type: 'Ice' },
  'Sandaconda': { name: 'G-Max Sandblast', type: 'Ground' },
  'Hatterene': { name: 'G-Max Smite', type: 'Fairy' },
  'Grimmsnarl': { name: 'G-Max Snooze', type: 'Dark' },
  'Copperajah': { name: 'G-Max Steelsurge', type: 'Steel' },
  'Drednaw': { name: 'G-Max Stonesurge', type: 'Water' },
  'Toxtricity': { name: 'G-Max Stun Shock', type: 'Electric' },
  'Appletun': { name: 'G-Max Sweetness', type: 'Grass' },
  'Flapple': { name: 'G-Max Tartness', type: 'Grass' },
  'Gengar': { name: 'G-Max Terror', type: 'Ghost' },
  'Venusaur': { name: 'G-Max Vine Lash', type: 'Grass' },
  'Coalossal': { name: 'G-Max Volcalith', type: 'Rock' },
  'Pikachu': { name: 'G-Max Volt Crash', type: 'Electric' },
  'Charizard': { name: 'G-Max Wildfire', type: 'Fire' },
  'Corviknight': { name: 'G-Max Wind Rage', type: 'Flying' },
};
// 種族 (基本フォルムへ寄せて照合) と技タイプからキョダイマックス技名を返す
export function gmaxMoveFor(species, moveType) {
  if (!species || !moveType) return null;
  let g = GMAX_MOVES[species];
  if (!g) {
    const sd = gen.species.get(String(species).toLowerCase().replace(/[^a-z0-9]/g, ''));
    if (sd && sd.baseSpecies && sd.baseSpecies !== species) g = GMAX_MOVES[sd.baseSpecies];
  }
  return g && g.type === moveType ? g.name : null;
}

// 指定値を反映した Move を作る。指定が無い・不正な場合は従来どおり
// (new Move(gen, name)) と完全に同じものになる。
// zMode が真なら Zワザ化する (専用 Z の組み合わせなら専用 Zワザ、
// それ以外はベース技からの汎用 Zワザ。エンジンが威力を解決する)
function buildMove(moveName, specValue, crit, zMode, atkSpec) {
  const effSp = atkSpec ? (atkSpec.mega && atkSpec.megaSpecies ? atkSpec.megaSpecies : atkSpec.species) : null;
  if (zMode) {
    const excl = atkSpec ? exclusiveZMove(effSp, atkSpec.itemLost ? '' : atkSpec.item, moveName) : null;
    const zObj = excl ? new Move(gen, excl) : new Move(gen, moveName, { useZ: true });
    if (crit) zObj.isCrit = true;
    return zObj;
  }
  if (atkSpec && atkSpec.dynamax) {
    // ダイマックス中は全ての技がダイマックスわざになる (変化技はダイマックスウォール)。
    // キョダイマックス技を持つ種族は、タイプが一致する攻撃技がキョダイマックス技に
    // 変わる (威力はベース技のダイマックスわざ威力を引き継ぐ)
    const raw = gen.moves.get(String(moveName).toLowerCase().replace(/[^a-z0-9]/g, ''));
    const gm = raw && raw.category !== 'Status' ? gmaxMoveFor(effSp, raw.type) : null;
    const maxObj = new Move(gen, moveName, gm ? { useMax: true, overrideMove: gm } : { useMax: true });
    if (crit) maxObj.isCrit = true;
    return maxObj;
  }
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
  if (!s || !s.baseStats) return null;
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
    isZ: !!m.isZ, isMax: !!m.isMax, zPower: (m.zMove && m.zMove.basePower) || null,
    spec: moveSpecInfo(name),
  };
}
