// アイテム JA→EN 対応の恒常チェック (2026-11-23 のヨプのみ誤映射の再発防止)。
// 1) usage_sets の初期持ち物が、pokedb のトップ持ち物 (JA) を items_ja.json で
//    引いた EN と一致すること (全種族)。
// 2) 実 (ベリー) の対応が PokéAPI で検証した正本と一致すること
//    (実効マップ = fetch_usage.mjs の ITEM_JA2EN に items_ja.json を重ねたもの。
//    mapItem の優先順位と同じ)。
import { readFileSync } from 'node:fs';

let failures = 0;
const check = (label, ok) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${label}`); if (!ok) failures++; };

const itemsJa = JSON.parse(readFileSync(new URL('../data/items_ja.json', import.meta.url), 'utf8'));
const parsed = JSON.parse(readFileSync(new URL('../data/pokedb_parsed.json', import.meta.url), 'utf8'));
const usage = JSON.parse(readFileSync(new URL('../data/usage_sets.json', import.meta.url), 'utf8'));
const src = readFileSync(new URL('../fetch_usage.mjs', import.meta.url), 'utf8');

// --- 1) 初期持ち物の整合 ---
const byCode = {};
for (const [k, v] of Object.entries(usage.sets || {})) byCode[v.code] = [k, v];
let checked = 0;
const bad = [];
for (const [code, e] of Object.entries(parsed)) {
  const ent = byCode[code];
  if (!ent || !e.items || !e.items.length) continue;
  const topJa = e.items[0].name;
  const expect = itemsJa[topJa];
  if (!expect) continue;
  checked++;
  if (ent[1].item !== expect) bad.push(`${ent[1].species}: built=${ent[1].item} expect=${expect} (top ${topJa})`);
}
check(`itemmap: usage_sets items match pokedb top items via items_ja (${checked} species)`, bad.length === 0);
for (const b of bad.slice(0, 10)) console.log('  ' + b);

// --- 2) 実の正本 (PokéAPI 検証済み、2026-11-23) ---
const BERRY_TRUTH = {
  'アッキのみ': 'Kee Berry', 'イアのみ': 'Iapapa Berry', 'イトケのみ': 'Passho Berry', 'イバンのみ': 'Custap Berry',
  'ウイのみ': 'Wiki Berry', 'ウタンのみ': 'Payapa Berry', 'オッカのみ': 'Occa Berry', 'オボンのみ': 'Sitrus Berry',
  'オレンのみ': 'Oran Berry', 'カゴのみ': 'Chesto Berry', 'カシブのみ': 'Kasib Berry', 'カムラのみ': 'Salac Berry',
  'キーのみ': 'Persim Berry', 'クラボのみ': 'Cheri Berry', 'サンのみ': 'Lansat Berry', 'シュカのみ': 'Shuca Berry',
  'ジャポのみ': 'Jaboca Berry', 'スターのみ': 'Starf Berry', 'ズアのみ': 'Apicot Berry', 'ソクノのみ': 'Wacan Berry',
  'タラプのみ': 'Maranga Berry', 'タンガのみ': 'Tanga Berry', 'チイラのみ': 'Liechi Berry', 'チーゴのみ': 'Rawst Berry',
  'ナゾのみ': 'Enigma Berry', 'ナナシのみ': 'Aspear Berry', 'ナモのみ': 'Colbur Berry', 'ハバンのみ': 'Haban Berry',
  'バコウのみ': 'Coba Berry', 'バンジのみ': 'Aguav Berry', 'ヒメリのみ': 'Leppa Berry', 'ビアーのみ': 'Kebia Berry',
  'フィラのみ': 'Figy Berry', 'ホズのみ': 'Chilan Berry', 'マゴのみ': 'Mago Berry', 'ミクルのみ': 'Micle Berry',
  'モモンのみ': 'Pecha Berry', 'ヤタピのみ': 'Petaya Berry', 'ヤチェのみ': 'Yache Berry', 'ヨプのみ': 'Chople Berry',
  'ヨロギのみ': 'Charti Berry', 'ラムのみ': 'Lum Berry', 'リュガのみ': 'Ganlon Berry', 'リリバのみ': 'Babiri Berry',
  'リンドのみ': 'Rindo Berry', 'レンブのみ': 'Rowap Berry', 'ロゼルのみ': 'Roseli Berry',
};
const tableSrc = (src.match(/const ITEM_JA2EN = \{([\s\S]*?)\n\};/) || [])[1] || '';
const table = {};
for (const m of tableSrc.matchAll(/'([^']+)':\s*'([^']+)'/g)) table[m[1]] = m[2];
const badBerry = [];
for (const [ja, en] of Object.entries(BERRY_TRUTH)) {
  const eff = itemsJa[ja] || table[ja];
  if (eff !== en) badBerry.push(`${ja}: effective=${eff} truth=${en}`);
  if (table[ja] && itemsJa[ja] && table[ja] !== itemsJa[ja]) badBerry.push(`${ja}: table=${table[ja]} items_ja=${itemsJa[ja]} (disagree)`);
}
check('itemmap: berry mappings match the verified truth', badBerry.length === 0);
for (const b of badBerry.slice(0, 10)) console.log('  ' + b);

console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
