// data/names_index.json の JA名グループ内で基本フォルムを先頭に並べ替える。
// 以前は重複を「解消」して基本フォルム以外を削除していたが、それだと
// イエッサン♀ (Indeedee-F) のような性別フォルムが索引から消えてしまい、
// 性別・フォルム違いを検出できなくなる (2026-11-20 の誤検出の原因)。
// 現在は削除せず、並び順だけを保証する: 同じJA名では基本フォルムが最初。
// matchSpecies の同点時先勝ちと、_ja2en 等の first-wins 変換が基本フォルムを指すため。
import { readFileSync, writeFileSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const path = new URL('./data/names_index.json', import.meta.url);
const idx = JSON.parse(readFileSync(path, 'utf-8'));
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');

function isBaseForme(en) {
  const s = gen.species.get(idOf(en));
  if (!s) return false;
  return s.baseSpecies === s.name && !s.forme;
}
const seen = new Map();
for (const e of idx.species) {
  if (!seen.has(e.ja)) seen.set(e.ja, []);
  seen.get(e.ja).push(e);
}
const out = [];
for (const list of seen.values()) {
  list.sort((a, b) => (isBaseForme(b.en) ? 1 : 0) - (isBaseForme(a.en) ? 1 : 0));
  out.push(...list);
}
idx.species = out;
writeFileSync(path, JSON.stringify(idx, null, 1));
console.log('entries:', out.length, '(all formes kept, base formes first per JA name)');
for (const probe of ['イエッサン', 'イダイトウ', 'ニャオニクス']) {
  console.log(probe, '->', out.filter(x => x.ja === probe).map(x => x.en).join(', ') || 'なし');
}
