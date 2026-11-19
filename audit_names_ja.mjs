// names_ja.json のうち英語のまま残っている技・特性名を PokeAPI から補完する。
// (Z ワザなど、初期構築で日本語名が取れなかったもの)
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'node:fs';

const gen = Generations.get(9);
const idOf = s => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
const hasJa = v => /[぀-ヿ一-鿿]/.test(v);
const namesPath = new URL('./data/names_ja.json', import.meta.url);
const names = JSON.parse(readFileSync(namesPath));
const dex = JSON.parse(readFileSync(new URL('./data/champions_dex.json', import.meta.url)));

function pokeSlug(en) {
  let s = en.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  s = s.replace(/[''`.]/g, '');
  return s.trim().toLowerCase().replace(/[\s_]+/g, '-').replace(/-+/g, '-');
}

async function jaName(kind, en) {
  const slug = pokeSlug(en);
  // Z ワザは PokeAPI では <slug>--physical / --special に分かれている
  const tries = kind === 'move' ? [slug, slug + '--physical', slug + '--special'] : [slug];
  for (const t of tries) {
    const r = await fetch(`https://pokeapi.co/api/v2/${kind}/${t}`);
    if (!r.ok) continue;
    const j = await r.json();
    const ja = (j.names || []).find(n => n.language.name === 'ja')?.name;
    if (ja) return ja;
  }
  return null;
}

// moves
const moveById = {};
for (const m of gen.moves) moveById[idOf(m.name)] = m.name;
let fixedM = 0, stillM = [];
for (const [id, val] of Object.entries(names.moves)) {
  if (hasJa(val)) continue;
  const en = moveById[id];
  if (!en || !dex.moves.includes(en)) continue;
  const ja = await jaName('move', en).catch(() => null);
  if (ja) { names.moves[id] = ja; fixedM++; }
  else stillM.push(en);
}
console.log(`moves fixed: ${fixedM}, still EN: ${stillM.join(', ') || 'none'}`);

// abilities
const abById = {};
for (const a of gen.abilities) abById[idOf(a.name)] = a.name;
let fixedA = 0, stillA = [];
for (const [id, val] of Object.entries(names.abilities)) {
  if (hasJa(val)) continue;
  const en = abById[id];
  if (!en) continue;
  const ja = await jaName('ability', en).catch(() => null);
  if (ja) { names.abilities[id] = ja; fixedA++; }
  else stillA.push(en);
}
console.log(`abilities fixed: ${fixedA}, still EN: ${stillA.join(', ') || 'none'}`);

writeFileSync(namesPath, JSON.stringify(names, null, 1));
console.log('names_ja.json updated');
