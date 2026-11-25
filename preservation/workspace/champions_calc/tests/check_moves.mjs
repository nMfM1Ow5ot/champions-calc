// 相手パネルの「（技なし）」表示バグの恒常チェック。
// 使用率トップ型 (data/usage_sets.json) の全種族について、UI が実際に
// 構築する手順 (core.mjs の usageSpec → ui.html の MOVE_OPTIONS) で
// 技が解決できるかを全数検証する。1 件でも解決できない技があれば
// その種族のパネルで「（技なし）」と表示されてしまう。
// 使い方: node tests/check_moves.mjs (問題があれば exit 1)
import { usageSpec, Generations } from '../bundle.mjs';
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.dirname(url.fileURLToPath(import.meta.url)) + '/..';
const usage = JSON.parse(fs.readFileSync(ROOT + '/data/usage_sets.json', 'utf8'));
const names = JSON.parse(fs.readFileSync(ROOT + '/data/names_ja.json', 'utf8'));
const champ = JSON.parse(fs.readFileSync(ROOT + '/data/champions_dex.json', 'utf8'));

const champMoves = new Set(champ.moves || []);
const champSpecies = new Set(champ.species || []);
// ui.html の _moveJa2en / MOVE_OPTIONS 構築をそのまま再現する
// (names_ja.json の moves は calc の技 ID がキー。gen の技と突合して英名を得る)
const gen = Generations.get(9);
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
const z2h = s => String(s).replace(/[Ａ-Ｚａ-ｚ０-９]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));
const moveJa2en = {};
for (const [id, jaName] of Object.entries(names.moves || {})) {
  const mv = [...gen.moves].find(m => idOf(m.name) === id);
  if (mv) moveJa2en[z2h(jaName)] = mv.name;
}
// MOVE_OPTIONS は技 ID キーで構築される (同名の日本語名で潰れない)
const moveById = new Map([...gen.moves].map(m => [idOf(m.name), m]));
const isMech = en => { const mv = gen.moves.get(idOf(en)); return !!(mv && (mv.isZ || mv.isMax)); };
const optionValues = new Set(
  Object.keys(names.moves || {}).map(id => moveById.get(id)).filter(Boolean).map(mv => mv.name)
    .filter(en => (!champMoves.size || champMoves.has(en)) && !isMech(en)));

let failures = 0;
const fail = msg => { failures++; console.log('FAIL ' + msg); };

const sets = usage.sets || usage;
let moveCount = 0;
for (const key of Object.keys(sets)) {
  const u = usageSpec(key, sets);
  if (!u) { fail(`usageSpec returned nothing: ${key}`); continue; }
  // champions_dex との不整合はデータ源同士の食い違い (表示は壊れない) ので警告に留める
  if (champSpecies.size && !champSpecies.has(u.species)) console.log(`WARN usage species not in champions_dex (data source mismatch): ${u.species}`);
  if (!u.moves || u.moves.length === 0) { fail(`usageSpec has no moves: ${u.species}`); continue; }
  u.moves.forEach((m, i) => {
    moveCount++;
    if (!m) fail(`${u.species} move slot ${i + 1} is empty`);
    else if (!optionValues.has(m)) fail(`${u.species} move slot ${i + 1} unresolved (shows as 技なし): ${JSON.stringify(m)}`);
  });
}
console.log(`checked ${Object.keys(sets).length} species / ${moveCount} moves`);
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
