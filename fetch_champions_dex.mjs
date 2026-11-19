// チャンピオンズに実装されている ポケモン/アイテム/技 の一覧を Serebii (Pokémon Champions セクション)
// から取得し、data/champions_dex.json を生成する。UI の選択肢フィルタに使う。
// 種族・技は pokedb 使用率データ (usage_sets.json) との和集合にする (ランクで使われているものは確実に実装済み)。
// 使い方: node fetch_champions_dex.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const curl = url => execFileSync('curl', ['-sL', '--max-time', '60', url], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const norm = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');

// --- ポケモン (pokedex-champions のスラッグ = 基本種族) ---
const pokeHtml = curl('https://www.serebii.net/pokemonchampions/pokemon.shtml');
const slugSet = new Set([...pokeHtml.matchAll(/pokedex-champions\/([a-z0-9-]+)\//g)].map(m => norm(m[1])));
let usage = { sets: {} };
try { usage = JSON.parse(readFileSync(new URL('./data/usage_sets.json', import.meta.url), 'utf8')); } catch (e) { /* 使用率なしでも続行 */ }
const usageSpecies = new Set(Object.values(usage.sets || {}).map(s => s.species).filter(Boolean));
const species = [];
for (const sp of gen.species) {
  const base = sp.baseSpecies || sp.name;
  if (slugSet.has(norm(base)) || usageSpecies.has(sp.name)) species.push(sp.name);
}

// --- アイテム (チャンピオンズのアイテムページに載る itemdex スラッグ) ---
const itemHtml = curl('https://www.serebii.net/pokemonchampions/items.shtml');
const itemSlugs = new Set([...itemHtml.matchAll(/itemdex\/([a-z0-9]+)\.shtml/g)].map(m => norm(m[1])));
const usageItems = new Set();
for (const s of Object.values(usage.sets || {})) if (s.item) usageItems.add(s.item);
const items = [];
for (const it of gen.items) if (itemSlugs.has(norm(it.id || it.name)) || usageItems.has(it.name)) items.push(it.name);

// --- 技 (attackdex-champions のスラッグ + 使用率データの技) ---
const moveHtml = curl('https://www.serebii.net/attackdex-champions/');
const moveSlugs = new Set([...moveHtml.matchAll(/attackdex-champions\/([a-z0-9]+)\.shtml/g)].map(m => norm(m[1])));
const usageMoves = new Set();
for (const s of Object.values(usage.sets || {})) for (const m of s.moves || []) usageMoves.add(m);
const moves = [];
for (const mv of gen.moves) if (moveSlugs.has(norm(mv.id || mv.name)) || usageMoves.has(mv.name)) moves.push(mv.name);

const out = {
  source: 'serebii.net Pokémon Champions (pokemon / items / attackdex) + champs.pokedb.tokyo usage',
  generated: new Date().toISOString().slice(0, 10),
  species, items, moves,
};
writeFileSync(new URL('./data/champions_dex.json', import.meta.url), JSON.stringify(out, null, 1));
console.log(`species ${species.length} / items ${items.length} / moves ${moves.length}`);
