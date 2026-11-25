// sets.mjs — 判断エンジン叩き台用の「想定セット」供給
// リプレイの showteam で判明している項目（種族・持ち物・特性・技・性格）はそのまま使い、
// 判明していない SP 配分は data/vgc_pastes_stats.json の最頻 SP パターンで補う。
// 種族自体が統計に無い場合は、種族値から作る汎用配分にフォールバックする。
import { readFileSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const toID = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
const stats = JSON.parse(readFileSync(new URL('../data/vgc_pastes_stats.json', import.meta.url), 'utf8'));
const bySpecies = stats.species || {};
const usage = JSON.parse(readFileSync(new URL('../data/usage_sets.json', import.meta.url), 'utf8'));
const usageSets = usage.sets || {};

export function spPatternFor(species) {
  const e = bySpecies[species];
  if (e && e.spPatterns && e.spPatterns.length) return e.spPatterns[0].sp;
  return null;
}

export function evsFromSp(sp) {
  if (!sp) return null;
  const g = (k) => (sp[k] || 0) * 8;
  return { hp: g('hp'), atk: g('atk'), def: g('def'), spa: g('spa'), spd: g('spd'), spe: g('spe') };
}

// 汎用フォールバック: HP と高い方の攻撃、残りを素早さへ
export function genericEvs(species) {
  const s = gen.species.get(toID(species));
  if (!s) return { hp: 252, atk: 0, def: 0, spa: 0, spd: 0, spe: 252 };
  const phys = s.baseStats.atk >= s.baseStats.spa;
  return phys
    ? { hp: 252, atk: 252, def: 0, spa: 0, spd: 4, spe: 0 }
    : { hp: 252, atk: 0, def: 0, spa: 252, spd: 4, spe: 0 };
}

export function genericNature(species) {
  const s = gen.species.get(toID(species));
  if (!s) return 'Serious';
  return s.baseStats.atk >= s.baseStats.spa ? 'Adamant' : 'Modest';
}

// 統計から最頻セットを組む（選出判断や、相手の未知セットの想定に使う）
// 優先順: VGCPastes 統計 → 使用率トップセット（usage_sets） → 汎用
export function assumedSet(species) {
  const e = bySpecies[species];
  if (!e) {
    const u = usageSets[toID(species)];
    if (u) {
      return { species: u.species || species, item: u.item, ability: u.ability, nature: u.nature, evs: evsFromSp(u.sp) || genericEvs(species), moves: u.moves || [] };
    }
    return { species, item: undefined, ability: undefined, nature: genericNature(species), evs: genericEvs(species), moves: [] };
  }
  const top = (arr) => (arr && arr.length ? arr[0][0] : undefined);
  return {
    species,
    item: top(e.items),
    ability: top(e.abilities),
    nature: top(e.natures) || genericNature(species),
    evs: evsFromSp(spPatternFor(species)) || genericEvs(species),
    moves: (e.moves || []).slice(0, 4).map((m) => m[0]),
  };
}

// 判明セット（showteam 由来）に SP 想定を足して完全なセットにする
export function completeSet(known) {
  const evs = evsFromSp(spPatternFor(known.species)) || genericEvs(known.species);
  return { ...known, evs };
}
