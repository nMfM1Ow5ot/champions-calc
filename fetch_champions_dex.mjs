// 内部データの土台を生成する。
// - data/champions_dex.json: 全ポケモンのユニバース (実在する全種族・フォルムと
//   gen9 の全アイテム・全技)。将来のレギュレーション変更に備え、実装範囲では
//   絞らない。種族は names_index.json の集合 (= 日本語名データのある実在ポケモン。
//   CAP や Aegislash-Both のような calc 内部の合成エントリを含まない) を正とする。
// - data/regulation.json: 現行レギュレーションの実装範囲 (スコープ) を保持する。
//   species / items / moves のスコープリストを、Serebii (Pokémon Champions) と
//   pokedb 使用率データから生成して書き込む。regulation / rule / season の
//   フィールドは既存の値を保持する (rule の変更は regulation.json を直接編集)。
// 使い方: node fetch_champions_dex.mjs
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const curl = url => execFileSync('curl', ['-sL', '--max-time', '60', url], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
const norm = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');

// --- ユニバース (全ポケモン) ---
const index = JSON.parse(readFileSync(new URL('./data/names_index.json', import.meta.url), 'utf8'));
const universeSpecies = [...new Set((index.species || []).map(e => e.en))];
const universeItems = [...gen.items].map(i => i.name);
const universeMoves = [...gen.moves].map(m => m.name);

// --- 現行レギュレーションの実装範囲 (Champions 実装済み) ---
let usage = { sets: {} };
try { usage = JSON.parse(readFileSync(new URL('./data/usage_sets.json', import.meta.url), 'utf8')); } catch (e) { /* 使用率なしでも続行 */ }

// ポケモン (pokedex-champions のスラッグ = 基本種族)
const pokeHtml = curl('https://www.serebii.net/pokemonchampions/pokemon.shtml');
const slugSet = new Set([...pokeHtml.matchAll(/pokedex-champions\/([a-z0-9-]+)\//g)].map(m => norm(m[1])));
const usageSpecies = new Set(Object.values(usage.sets || {}).map(s => s.species).filter(Boolean));
// Aegislash-Both は @smogon/calc 内部の合成エントリ (両フォルムの高い能力を併せた計算用) で、
// 実在するフォルムではないため収録しない。
const EXCLUDE_SPECIES = new Set(['Aegislash-Both']);
const scopeSpecies = [];
for (const sp of gen.species) {
  if (EXCLUDE_SPECIES.has(sp.name)) continue;
  const base = sp.baseSpecies || sp.name;
  let slugHit = slugSet.has(norm(base));
  if (!slugHit) {
    // baseSpecies が兄弟フォルムを指す種族 (Aegislash-Shield の baseSpecies は Aegislash-Blade) は
    // スラッグ 'aegislash' と一致せず落ちるため、名前を '-' で切り詰めた候補でも照合する。
    let n = sp.name;
    while (n.includes('-')) {
      n = n.slice(0, n.lastIndexOf('-'));
      if (slugSet.has(norm(n))) { slugHit = true; break; }
    }
  }
  if (slugHit || usageSpecies.has(sp.name)) scopeSpecies.push(sp.name);
}

// アイテム (チャンピオンズのアイテムページに載る itemdex スラッグ)
const itemHtml = curl('https://www.serebii.net/pokemonchampions/items.shtml');
const itemSlugs = new Set([...itemHtml.matchAll(/itemdex\/([a-z0-9]+)\.shtml/g)].map(m => norm(m[1])));
const usageItems = new Set();
for (const s of Object.values(usage.sets || {})) if (s.item) usageItems.add(s.item);
const scopeItems = [];
for (const it of gen.items) if (itemSlugs.has(norm(it.id || it.name)) || usageItems.has(it.name)) scopeItems.push(it.name);

// 技 (attackdex-champions のスラッグ + 使用率データの技)
const moveHtml = curl('https://www.serebii.net/attackdex-champions/');
const moveSlugs = new Set([...moveHtml.matchAll(/attackdex-champions\/([a-z0-9]+)\.shtml/g)].map(m => norm(m[1])));
const usageMoves = new Set();
for (const s of Object.values(usage.sets || {})) for (const m of s.moves || []) usageMoves.add(m);
const scopeMoves = [];
for (const mv of gen.moves) if (moveSlugs.has(norm(mv.id || mv.name)) || usageMoves.has(mv.name)) scopeMoves.push(mv.name);

// スコープはユニバースの部分集合でなければならない (利用側はこの前提で絞り込む)
const uSet = new Set(universeSpecies);
const outside = scopeSpecies.filter(s => !uSet.has(s));
if (outside.length) {
  console.error(`実装範囲の種族がユニバースにありません: ${outside.join(', ')}`);
  process.exit(1);
}

const today = new Date().toISOString().slice(0, 10);
writeFileSync(new URL('./data/champions_dex.json', import.meta.url), JSON.stringify({
  source: 'all Pokémon (names_index.json) + @smogon/calc gen9 items/moves',
  generated: today,
  species: universeSpecies, items: universeItems, moves: universeMoves,
}, null, 1));
console.log(`champions_dex (universe): species ${universeSpecies.length} / items ${universeItems.length} / moves ${universeMoves.length}`);

const regPath = new URL('./data/regulation.json', import.meta.url);
const reg = JSON.parse(readFileSync(regPath, 'utf8'));
reg.species = scopeSpecies;
reg.items = scopeItems;
reg.moves = scopeMoves;
reg.updated = today;
writeFileSync(regPath, JSON.stringify(reg, null, 1) + '\n');
console.log(`regulation scope: species ${scopeSpecies.length} / items ${scopeItems.length} / moves ${scopeMoves.length}`);
