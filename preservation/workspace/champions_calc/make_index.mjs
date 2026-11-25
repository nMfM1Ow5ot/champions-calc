// Swift読み取りプログラム用の索引 (日本語名 -> 英語名/ID) を作る
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'fs';
const names = JSON.parse(readFileSync(new URL('./data/names_ja.json', import.meta.url), 'utf8'));
const gen = Generations.get(9);
// Aegislash-Both は @smogon/calc 内部の合成エントリ (実在しないフォルム) のため索引に入れない。
const EXCLUDE_IDS = new Set(['aegislashboth']);
const species = [];
for (const s of gen.species) {
  const ja = names.species[s.id];
  if (ja && ja !== s.name && !EXCLUDE_IDS.has(s.id)) species.push({ ja, en: s.name, id: s.id });
}
writeFileSync(new URL('./data/names_index.json', import.meta.url), JSON.stringify({ species }, null, 0));
console.log('entries:', species.length);
for (const probe of ['ウインディ', 'セグレイブ', 'フシギバナ', 'ガブリアス', 'メガガブリアスZ', 'メガライチュウY', 'サーフゴー'])
  console.log(probe, '->', (species.find(s => s.ja === probe) || {}).en);
