// 種族ごとの全特性リスト (隠れ特性含む) を PokeAPI から取得し、
// data/species_abilities.json を生成する。
// 対象は names_index.json の全種族 (フォルム違い・リージョン違い・性別違いを含む)。
// リーダーのフォルム判別 (特性で絞り込む) と UI の特性プルダウン候補に使う。
// PokeAPI で引けない種族は @smogon/calc の特性データで補う。
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'node:fs';

const gen = Generations.get(9);
const idOf = s => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');

// calc の特性名 (EN) を id で引けるようにする
const abilityById = {};
for (const a of gen.abilities) abilityById[idOf(a.name)] = a.name;

// calc 側の全特性 (フォールバック用): EN名 -> [特性EN]
const calcAbilities = {};
for (const sp of gen.species) {
  const abs = Object.values(sp.abilities || {}).filter(Boolean);
  if (abs.length) calcAbilities[sp.name] = [...new Set(abs)];
}

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
let ok = 0, fallback = 0, missing = 0;
const queue = [...names];
async function worker() {
  while (queue.length) {
    const en = queue.shift();
    const slug = pokeSlug(en);
    try {
      const r = await fetch(`https://pokeapi.co/api/v2/pokemon/${slug}`);
      if (!r.ok) throw new Error(String(r.status));
      const j = await r.json();
      const abs = [];
      for (const a of j.abilities || []) {
        const name = abilityById[idOf(a.ability.name)];
        if (name && !abs.includes(name)) abs.push(name);
      }
      if (abs.length) { out[en] = abs; ok++; continue; }
      throw new Error('no abilities');
    } catch (e) {
      if (calcAbilities[en]) { out[en] = calcAbilities[en]; fallback++; }
      else { missing++; console.log(`  取得失敗: ${en} (${slug})`); }
    }
  }
}
await Promise.all(Array.from({ length: 8 }, worker));
console.log(`species abilities: ${ok} ok, ${fallback} calc fallback, ${missing} missing / ${names.length}`);
writeFileSync(new URL('./data/species_abilities.json', import.meta.url), JSON.stringify(out, null, 1));
for (const k of ['Ninetales-Alola', 'Indeedee-F', 'Marowak-Alola', 'Raichu-Alola', 'Rotom-Heat', 'Incineroar']) {
  console.log(`sample ${k}:`, out[k]);
}
