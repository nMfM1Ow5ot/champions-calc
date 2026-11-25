// チャンピオンズ実装アイテム全種の日本語名を PokeAPI から補完し、
// data/items_ja.json (日本語名 -> 英語名) にマージする。
// 既存のエントリ (pokedb 由来) は優先して残す。
import { readFileSync, writeFileSync } from 'node:fs';

const dex = JSON.parse(readFileSync(new URL('./data/champions_dex.json', import.meta.url)));
const itemsJaPath = new URL('./data/items_ja.json', import.meta.url);
const itemsJa = JSON.parse(readFileSync(itemsJaPath));
const haveEn = new Set(Object.values(itemsJa));

function pokeSlug(en) {
  let s = en.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  s = s.replace(/[''`.]/g, '');
  s = s.trim().toLowerCase().replace(/[\s_]+/g, '-');
  return s.replace(/-+/g, '-');
}

let added = 0, missing = [];
for (const en of dex.items) {
  if (haveEn.has(en)) continue;
  const slug = pokeSlug(en);
  try {
    const r = await fetch(`https://pokeapi.co/api/v2/item/${slug}`);
    if (!r.ok) throw new Error(String(r.status));
    const j = await r.json();
    const jaName = (j.names || []).find(n => n.language.name === 'ja')?.name
      || (j.names || []).find(n => n.language.name === 'ja-hrkt')?.name;
    if (jaName && !itemsJa[jaName]) { itemsJa[jaName] = en; added++; }
    else missing.push(en);
  } catch (e) {
    missing.push(en);
  }
}
writeFileSync(itemsJaPath, JSON.stringify(itemsJa, null, 1));
console.log(`items_ja: added ${added}, total ${Object.keys(itemsJa).length}`);
console.log('still EN-only:', missing.join(', ') || 'none');
