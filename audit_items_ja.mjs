// items_ja.json の JA->EN 対応を PokeAPI の正データで全件監査し、
// 誤対応を修正 + チャンピオンズ実装アイテムの欠けを補完する。
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'node:fs';

const gen = Generations.get(9);
const idOf = s => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
const itemsJaPath = new URL('./data/items_ja.json', import.meta.url);
const itemsJa = JSON.parse(readFileSync(itemsJaPath));
const dex = JSON.parse(readFileSync(new URL('./data/champions_dex.json', import.meta.url)));

const calcById = {};
for (const it of gen.items) calcById[idOf(it.name)] = it.name;

function pokeSlug(en) {
  let s = en.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  s = s.replace(/[''`.]/g, '');
  return s.trim().toLowerCase().replace(/[\s_]+/g, '-').replace(/-+/g, '-');
}

// PokeAPI から ja->en の正対応を作る (チャンピオンズ実装分 + 既存キーの検証分)
const targets = new Set(dex.items);
for (const en of Object.values(itemsJa)) targets.add(en);
const truth = {}; // ja -> en (calc item name)
let fetched = 0, noApi = [];
for (const en of targets) {
  const slug = pokeSlug(en);
  try {
    const r = await fetch(`https://pokeapi.co/api/v2/item/${slug}`);
    if (!r.ok) throw new Error(String(r.status));
    const j = await r.json();
    const jaName = (j.names || []).find(n => n.language.name === 'ja')?.name;
    const calcEn = calcById[idOf(j.name)] || en;
    if (jaName) { truth[jaName] = calcEn; fetched++; }
    else noApi.push(en);
  } catch (e) { noApi.push(en); }
}
console.log(`truth pairs: ${fetched}, no PokeAPI entry: ${noApi.length}`);

// 監査: 既存エントリのうち正対応と食い違うものを修正
const fixes = [];
for (const [jaName, en] of Object.entries(itemsJa)) {
  if (truth[jaName] && truth[jaName] !== en) {
    fixes.push(`${jaName}: ${en} -> ${truth[jaName]}`);
    itemsJa[jaName] = truth[jaName];
  }
}
// 補完: チャンピオンズ実装アイテムで JA 名が無いものを追加
let added = 0;
const haveEn = new Set(Object.values(itemsJa));
for (const [jaName, en] of Object.entries(truth)) {
  if (dex.items.includes(en) && !haveEn.has(en) && !itemsJa[jaName]) {
    itemsJa[jaName] = en; haveEn.add(en); added++;
  }
}
writeFileSync(itemsJaPath, JSON.stringify(itemsJa, null, 1));
console.log(`fixed ${fixes.length}:`);
for (const f of fixes) console.log('  ', f);
console.log(`added ${added}, total keys ${Object.keys(itemsJa).length}`);
const stillEn = dex.items.filter(en => !new Set(Object.values(itemsJa)).has(en));
console.log('Champions items still without JA:', stillEn.join(', ') || 'none');
