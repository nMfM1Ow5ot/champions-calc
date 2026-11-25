// 網羅性チェック: 「データにあるのに UI で選べない・表示できない」を全数検出する。
// - チャンピオンズ実装技がすべて技ドロップダウン (MOVE_OPTIONS) に入っているか
// - チャンピオンズ実装アイテムがすべて持ち物ドロップダウンに入っているか
// - リーダーが出しうる技名 (log_names.json) がすべて計算データで解決できるか
// - 場の状態 (おいかぜ/壁/オーロラベール/てだすけ/トリックルーム) の
//   連携が UI 側に揃っているか
// 使い方: node tests/check_coverage.mjs (問題があれば exit 1)
import { Generations } from '../bundle.mjs';
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.dirname(url.fileURLToPath(import.meta.url)) + '/..';
const read = p => fs.readFileSync(ROOT + p, 'utf8');
const names = JSON.parse(read('/data/names_ja.json'));
const champ = JSON.parse(read('/data/champions_dex.json'));
const logNames = JSON.parse(read('/data/log_names.json'));
const itemsJa = JSON.parse(read('/data/items_ja.json'));
const uiHtml = read('/ui.html');
const engineSrc = read('/estimate_engine.mjs');

const gen = Generations.get(9);
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
const z2h = s => String(s).replace(/[Ａ-Ｚａ-ｚ０-９]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));

let failures = 0;
const fail = msg => { failures++; console.log('FAIL ' + msg); };

// ui.html と同じ手順で MOVE_OPTIONS の値を再現 (技 ID キーで構築する。
// 日本語名キーだと めざめるパワー のタイプ別バリアントが同名で潰れる)
const moveById = new Map([...gen.moves].map(m => [idOf(m.name), m]));
const champMoves = new Set(champ.moves || []);
// ui.html は Zワザ・ダイマックスわざ (仕組み側の技) を直接選択の候補から外す
// (名前で直接選ぶとダミー威力で計算されるため。Z / ダイマックスのトグルで使う)
const isMech = en => { const mv = gen.moves.get(idOf(en)); return !!(mv && (mv.isZ || mv.isMax)); };
const moveOptions = new Set(
  Object.keys(names.moves || {}).map(id => moveById.get(id)).filter(Boolean).map(mv => mv.name)
    .filter(en => (!champMoves.size || champMoves.has(en)) && !isMech(en)));
for (const m of champ.moves || []) {
  if (isMech(m)) continue;
  if (!moveOptions.has(m)) fail(`champions move not selectable in UI (revealed -> 技なし): ${m}`);
}

// 持ち物: ITEM_OPTIONS は gen.items ∩ champ.items (表示名は items_ja)
const champItems = new Set(champ.items || []);
for (const it of champ.items || []) {
  if (!gen.items.get(idOf(it))) fail(`champions item missing in calc data: ${it}`);
}

// リーダーが出す技名がすべて gen で解決できるか (解決できないと判明技が化ける)
const readerMoves = [...new Set(Object.values(logNames.moves || {}))];
let unres = 0;
for (const en of readerMoves) {
  if (!gen.moves.get(idOf(en))) { unres++; if (unres <= 10) fail(`reader move name unresolvable in calc: ${en}`); }
}
if (unres > 10) fail(`... and ${unres - 10} more unresolvable reader move names`);

// 場の状態の連携: 推定エンジン (estimate_engine.mjs の processMoveInf) に各技の分岐があるか
for (const mv of ['Tailwind', 'Reflect', 'Light Screen', 'Aurora Veil', 'Helping Hand', 'Trick Room']) {
  if (!(uiHtml + engineSrc).includes(`ev.move === '${mv}'`)) fail(`UI has no event branch for: ${mv}`);
  if (!readerMoves.includes(mv)) fail(`reader cannot emit move: ${mv}`);
}

console.log(`checked ${champMoves.size} champ moves / ${readerMoves.length} reader moves`);
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
