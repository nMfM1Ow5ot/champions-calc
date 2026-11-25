// PokeAPIから日本語名を取得して data/names_raw.json に保存する
import { writeFileSync } from 'fs';

const BASE = 'https://pokeapi.co/api/v2';
const CONC = 12;

async function fetchJSON(url) {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(url);
      if (r.ok) return await r.json();
    } catch {}
    await new Promise(s => setTimeout(s, 500 * (i + 1)));
  }
  return null;
}

async function pool(items, fn) {
  const out = new Array(items.length);
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      out[i] = await fn(items[i]);
    }
  }
  await Promise.all(Array.from({ length: CONC }, worker));
  return out;
}

function jaName(obj) {
  if (!obj || !obj.names) return null;
  const n = obj.names.find(n => n.language.name === 'ja-Hrkt') || obj.names.find(n => n.language.name === 'ja');
  return n ? n.name : null;
}

async function collect(kind, limit) {
  const list = await fetchJSON(`${BASE}/${kind}?limit=${limit}`);
  const results = list.results;
  const names = {};
  await pool(results, async (r) => {
    const obj = await fetchJSON(r.url);
    const ja = jaName(obj);
    if (ja) names[r.name] = ja; // key = English slug (e.g. dragon-pulse, garchomp)
  });
  console.log(kind, Object.keys(names).length, '/', results.length);
  return names;
}

const species = await collect('pokemon-species', 1025);
const moves = await collect('move', 937);
const abilities = await collect('ability', 310);
writeFileSync(new URL('./data/names_raw.json', import.meta.url), JSON.stringify({ species, moves, abilities }, null, 1));
console.log('saved data/names_raw.json');
