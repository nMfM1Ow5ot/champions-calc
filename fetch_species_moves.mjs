// 種族ごとの習得技リスト (全習得方法) を PokeAPI から取得し、
// data/species_moves.json を生成する。
// 対象は names_index.json の全種族 (フォルム違い・リージョン違い・性別違いを含む)。
// リーダーのフォルム判別 (フォルム専用技で絞り込む) に使う。
// PokeAPI で引けない種族は空リストにせず、対象外として記録だけする。
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'node:fs';

const gen = Generations.get(9);
const idOf = s => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');

// calc の技名 (EN) を id で引けるようにする
const moveById = {};
for (const m of gen.moves) moveById[idOf(m.name)] = m.name;

// PokeAPI のスラッグが一般規則と異なる種族
const SLUG_SPECIAL = {
  'Indeedee': 'indeedee-male', 'Indeedee-F': 'indeedee-female',
  'Meowstic': 'meowstic-male', 'Meowstic-F': 'meowstic-female',
  'Basculegion': 'basculegion-male', 'Basculegion-F': 'basculegion-female',
  'Oinkologne-F': 'oinkologne-female',
  'Tauros-Paldea-Combat': 'tauros-paldea-combat-breed',
  'Tauros-Paldea-Blaze': 'tauros-paldea-blaze-breed',
  'Tauros-Paldea-Aqua': 'tauros-paldea-aqua-breed',
  'Urshifu': 'urshifu-single-strike',
  'Calyrex-Ice': 'calyrex-ice-rider', 'Calyrex-Shadow': 'calyrex-shadow-rider',
  'Basculin': 'basculin-red-striped',
  'Wormadam': 'wormadam-plant',
  'Sinistea': 'sinistea-phony', 'Polteageist': 'polteageist-phony',
  'Gourgeist': 'gourgeist-average', 'Pumpkaboo': 'pumpkaboo-average',
  'Maushold': 'maushold-family-of-three', 'Maushold-Four': 'maushold-family-of-four',
  'Tatsugiri': 'tatsugiri-curly',
  'Squawkabilly': 'squawkabilly-green-plumage',
  'Zygarde-10%': 'zygarde-10',
  'Morpeko': 'morpeko-full-belly',
  "Oricorio-Pa'u": 'oricorio-pau',
  'Mimikyu': 'mimikyu-disguised',
  'Eiscue': 'eiscue-ice-face',
  'Palafin': 'palafin-zero',
  'Gimmighoul': 'gimmighoul-chest',
  'Toxtricity': 'toxtricity-amped',
  'Minior': 'minior-red-meteor',
  'Wishiwashi': 'wishiwashi-solo',
};

function pokeSlug(en) {
  if (SLUG_SPECIAL[en]) return SLUG_SPECIAL[en];
  let s = en.normalize('NFD').replace(/[̀-ͯ]/g, '');
  s = s.replace(/[''’`.:]/g, '').replace(/♀/g, '-f').replace(/♂/g, '-m');
  s = s.trim().toLowerCase().replace(/[\s_]+/g, '-');
  s = s.replace(/-+/g, '-');
  return s;
}

const index = JSON.parse(readFileSync(new URL('./data/names_index.json', import.meta.url), 'utf8'));
const names = [...new Set((index.species || []).map(e => e.en))];
console.log(`対象: ${names.length} 種族`);

const out = {};
let ok = 0, missing = 0;
const queue = [...names];
async function worker() {
  while (queue.length) {
    const en = queue.shift();
    const slug = pokeSlug(en);
    try {
      const r = await fetch(`https://pokeapi.co/api/v2/pokemon/${slug}`);
      if (!r.ok) throw new Error(String(r.status));
      const j = await r.json();
      const mvs = [];
      for (const m of j.moves || []) {
        const name = moveById[idOf(m.move.name)];
        if (name && !mvs.includes(name)) mvs.push(name);
      }
      out[en] = mvs; ok++;
    } catch (e) {
      missing++; console.log(`  取得失敗: ${en} (${slug})`);
      out[en] = [];
    }
  }
}
await Promise.all(Array.from({ length: 8 }, worker));
console.log(`species moves: ${ok} ok, ${missing} missing / ${names.length}`);
writeFileSync(new URL('./data/species_moves.json', import.meta.url), JSON.stringify(out, null, 1));
for (const k of ['Rotom-Heat', 'Rotom-Wash', 'Rotom', 'Lilligant-Hisui', 'Zoroark-Hisui', 'Ninetales-Alola']) {
  console.log(`sample ${k}:`, (out[k] || []).length, 'moves');
}
