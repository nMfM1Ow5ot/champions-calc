// 実数値から SP振りと性格を逆算する
// 使い方: node derive_build.mjs <Species英語名> <HP> <攻撃> <防御> <特攻> <特防> <素早さ>
import { Generations } from '@smogon/calc';
const gen = Generations.get(9);

const NATURES = {
  Hardy: 'がんばりや', Lonely: 'さみしがり', Brave: 'ゆうかん', Adamant: 'いじっぱり', Naughty: 'やんちゃ',
  Bold: 'ずぶとい', Docile: 'すなお', Relaxed: 'のんき', Impish: 'わんぱく', Lax: 'のうてんき',
  Timid: 'おくびょう', Hasty: 'せっかち', Serious: 'まじめ', Jolly: 'ようき', Naive: 'むじゃき',
  Modest: 'ひかえめ', Mild: 'おっとり', Quiet: 'れいせい', Bashful: 'てれや', Rash: 'うっかりや',
  Calm: 'おだやか', Gentle: 'おとなしい', Sassy: 'なまいき', Careful: 'しんちょう', Quirky: 'きまぐれ',
};
// [上げる, 下げる] (null = 補正なし)
const MODS = {
  Lonely: ['atk', 'def'], Brave: ['atk', 'spe'], Adamant: ['atk', 'spa'], Naughty: ['atk', 'spd'],
  Bold: ['def', 'atk'], Relaxed: ['def', 'spe'], Impish: ['def', 'spa'], Lax: ['def', 'spd'],
  Timid: ['spe', 'atk'], Hasty: ['spe', 'def'], Jolly: ['spe', 'spa'], Naive: ['spe', 'spd'],
  Modest: ['spa', 'atk'], Mild: ['spa', 'def'], Quiet: ['spa', 'spe'], Rash: ['spa', 'spd'],
  Calm: ['spd', 'atk'], Gentle: ['spd', 'def'], Sassy: ['spd', 'spe'], Careful: ['spd', 'spa'],
};
const KEYS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];

export function deriveBuild(speciesName, actual) {
  const s = gen.species.get(speciesName.toLowerCase().replace(/[^a-z0-9]/g, ''));
  if (!s) throw new Error('species not found: ' + speciesName);
  const base = s.baseStats;
  const solutions = [];
  for (const nature of Object.keys(NATURES)) {
    const [up, down] = MODS[nature] || [null, null];
    const mod = (k) => k === up ? 1.1 : k === down ? 0.9 : 1.0;
    // HP は一意
    const hpSP = actual.hp - base.hp - 75;
    if (hpSP < 0 || hpSP > 32) continue;
    // 各ステータスの SP 候補
    const cand = { hp: [hpSP] };
    let ok = true;
    for (const k of KEYS.slice(1)) {
      const list = [];
      for (let sp = 0; sp <= 32; sp++) {
        if (Math.floor((base[k] + 20 + sp) * mod(k)) === actual[k]) list.push(sp);
      }
      if (!list.length) { ok = false; break; }
      cand[k] = list;
    }
    if (!ok) continue;
    // 組み合わせ (合計66以下) を列挙
    const combos = [];
    const rec = (i, cur, total) => {
      if (total > 66) return;
      if (i === KEYS.length) { combos.push({ sp: { ...cur }, total }); return; }
      for (const v of cand[KEYS[i]]) { cur[KEYS[i]] = v; rec(i + 1, cur, total + v); }
    };
    rec(0, {}, 0);
    for (const c of combos) solutions.push({ nature, natureJa: NATURES[nature], ...c });
  }
  // 合計66 (=全振り) を優先し、候補が多ければ余りの少ない順
  solutions.sort((a, b) => b.total - a.total);
  return solutions;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [name, ...vals] = process.argv.slice(2);
  const actual = Object.fromEntries(KEYS.map((k, i) => [k, parseInt(vals[i])]));
  const sols = deriveBuild(name, actual);
  console.log(`${name} 実数値 ${JSON.stringify(actual)} -> 候補 ${sols.length} 件`);
  for (const s of sols.slice(0, 8)) console.log(`  ${s.natureJa} (${s.nature}) SP ${JSON.stringify(s.sp)} 合計${s.total}`);
}
