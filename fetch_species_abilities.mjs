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

// PokeAPI のスラッグが一般規則と異なる種族。
// 性別差でデフォルト個体が -male になる種族 (Pyroar 等) や、デフォルト
// フォルムに接尾辞が付く種族 (incarnate / altered 等) がここに要る。
// 間違ったスラッグは 404 になり、無言で calc フォールバック (第1特性のみ)
// に落ちるため、新規追加時は pokemon-species の varieties で実名を確認する
// こと (2026-11-20 の Pyroar 欠落の教訓)。
const SLUG_SPECIAL = {
  'Pyroar': 'pyroar-male',
  'Frillish': 'frillish-male', 'Jellicent': 'jellicent-male',
  'Indeedee': 'indeedee-male', 'Indeedee-F': 'indeedee-female',
  'Meowstic': 'meowstic-male', 'Meowstic-F': 'meowstic-female',
  'Basculegion': 'basculegion-male', 'Basculegion-F': 'basculegion-female',
  'Oinkologne': 'oinkologne-male', 'Oinkologne-F': 'oinkologne-female',
  'Tauros-Paldea-Combat': 'tauros-paldea-combat-breed',
  'Tauros-Paldea-Blaze': 'tauros-paldea-blaze-breed',
  'Tauros-Paldea-Aqua': 'tauros-paldea-aqua-breed',
  'Urshifu': 'urshifu-single-strike',
  'Calyrex-Ice': 'calyrex-ice', 'Calyrex-Shadow': 'calyrex-shadow',
  'Basculin': 'basculin-red-striped',
  'Wormadam': 'wormadam-plant',
  'Gourgeist': 'gourgeist-average', 'Pumpkaboo': 'pumpkaboo-average',
  'Maushold': 'maushold-family-of-three', 'Maushold-Four': 'maushold-family-of-four',
  'Tatsugiri': 'tatsugiri-curly',
  'Squawkabilly': 'squawkabilly-green-plumage',
  'Squawkabilly-Blue': 'squawkabilly-blue-plumage',
  'Squawkabilly-White': 'squawkabilly-white-plumage',
  'Squawkabilly-Yellow': 'squawkabilly-yellow-plumage',
  'Zygarde': 'zygarde-50', 'Zygarde-10%': 'zygarde-10',
  'Morpeko': 'morpeko-full-belly',
  "Oricorio-Pa'u": 'oricorio-pau',
  'Mimikyu': 'mimikyu-disguised',
  'Eiscue': 'eiscue-ice',
  'Palafin': 'palafin-zero',
  'Gimmighoul': 'gimmighoul-chest',
  'Toxtricity': 'toxtricity-amped',
  'Minior': 'minior-red-meteor',
  'Wishiwashi': 'wishiwashi-solo',
  'Lycanroc': 'lycanroc-midday',
  'Giratina': 'giratina-altered',
  'Shaymin': 'shaymin-land',
  'Darmanitan': 'darmanitan-standard', 'Darmanitan-Galar': 'darmanitan-galar-standard',
  'Keldeo': 'keldeo-ordinary',
  'Landorus': 'landorus-incarnate', 'Thundurus': 'thundurus-incarnate',
  'Tornadus': 'tornadus-incarnate',
  'Meloetta': 'meloetta-aria',
  'Enamorus': 'enamorus-incarnate',
  'Dudunsparce': 'dudunsparce-two-segment',
  'Necrozma-Dusk-Mane': 'necrozma-dusk', 'Necrozma-Dawn-Wings': 'necrozma-dawn',
  'Pikachu-Original': 'pikachu-original-cap', 'Pikachu-Hoenn': 'pikachu-hoenn-cap',
  'Pikachu-Sinnoh': 'pikachu-sinnoh-cap', 'Pikachu-Unova': 'pikachu-unova-cap',
  'Pikachu-Kalos': 'pikachu-kalos-cap', 'Pikachu-Alola': 'pikachu-alola-cap',
  'Pikachu-Partner': 'pikachu-partner-cap', 'Pikachu-World': 'pikachu-world-cap',
};

// PokeAPI に pokemon エントリが無い見た目フォルム (模様・真贋等)。
// 特性は基本フォルムと同一なので、フォールバック前に基本フォルムの
// PokeAPI 取得結果を引き継ぐ (calc フォールバックの第1特性のみ化を防ぐ)
const INHERIT_ABILITIES = {
  'Vivillon-Pokeball': 'Vivillon', 'Vivillon-Fancy': 'Vivillon',
  'Polteageist-Antique': 'Polteageist', 'Sinistea-Antique': 'Sinistea',
  'Sinistcha-Masterpiece': 'Sinistcha', 'Poltchageist-Artisan': 'Poltchageist',
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
const fallbackNames = [];
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
      if (calcAbilities[en]) { out[en] = calcAbilities[en]; fallback++; fallbackNames.push(en); }
      else { missing++; console.log(`  取得失敗: ${en} (${slug})`); }
    }
  }
}
await Promise.all(Array.from({ length: 8 }, worker));
// 見た目フォルムは基本フォルムの PokeAPI 取得結果を引き継ぐ
let inherited = 0;
for (const [forme, base] of Object.entries(INHERIT_ABILITIES)) {
  if (out[base] && fallbackNames.includes(forme)) {
    out[forme] = out[base];
    fallback--; inherited++;
    fallbackNames.splice(fallbackNames.indexOf(forme), 1);
  }
}
console.log(`species abilities: ${ok} ok, ${inherited} inherited, ${fallback} calc fallback, ${missing} missing / ${names.length}`);
if (fallbackNames.length) console.log(`calc fallback のままの種族: ${fallbackNames.join(', ')}`);
writeFileSync(new URL('./data/species_abilities.json', import.meta.url), JSON.stringify(out, null, 1));
for (const k of ['Ninetales-Alola', 'Indeedee-F', 'Marowak-Alola', 'Raichu-Alola', 'Rotom-Heat', 'Incineroar']) {
  console.log(`sample ${k}:`, out[k]);
}
