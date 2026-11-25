// data/spec_patches.json の妥当性チェック。
// 使い方: node tests/check_spec_patches.mjs [対象ファイル (省略時 data/spec_patches.json)]
// 差分レイヤー (core.mjs の applySpecPatch) は、解決できない種族・技・
// タイプ名を黙って読み飛ばすため、登録ミスはここで落とす。
// ERROR があれば exit 1。WARN は落とさない (意図した差分かもしれないため)。
import { readFileSync, existsSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const target = process.argv[2] || new URL('../data/spec_patches.json', import.meta.url).pathname;
const gen = Generations.get(9);
const idOf = name => String(name).toLowerCase().replace(/[^a-z0-9]/g, '');
const STAT_KEYS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
const TYPE_NAMES = new Set([...gen.types].map(t => t.name));
const CATEGORIES = new Set(['Physical', 'Special', 'Status']);
const SPECIES_PROPS = new Set(['baseStats', 'types', 'abilities', 'weightkg', 'heightm', 'baseSpecies', 'forme', 'gen', 'prevo', 'evoLevel']);
const MOVE_PROPS = new Set(['basePower', 'accuracy', 'type', 'category', 'priority', 'target', 'pp', 'flags', 'secondary', 'secondaries', 'multihit', 'recoil', 'drain', 'heal', 'critRatio', 'zMove', 'maxMove', 'isZ', 'isMax']);
const MULTS = new Set([0, 0.5, 1, 2]);

let errors = 0, warnings = 0;
const err = m => { errors++; console.log('ERROR: ' + m); };
const warn = m => { warnings++; console.log('WARN: ' + m); };

let data;
try {
  data = JSON.parse(readFileSync(target, 'utf8'));
} catch (e) {
  console.log(`ERROR: ${target} を読めません: ${e.message}`);
  process.exit(1);
}
if (!data || typeof data !== 'object' || Array.isArray(data)) err('トップレベルはオブジェクトでなければなりません');
if (!Array.isArray(data?.versions)) err('versions は配列でなければなりません');

const versions = Array.isArray(data?.versions) ? data.versions : [];
const seenIds = new Set();
let entryCount = 0;
let prevEntries = null; // 前バージョンの登録キー集合 (完全スナップショットの欠落警告用)

for (const v of versions) {
  const tag = `version ${v?.id ?? '(id なし)'}`;
  if (!v || typeof v !== 'object') { err(`${tag}: バージョンはオブジェクトでなければなりません`); continue; }
  if (typeof v.id !== 'string' || !v.id) err(`${tag}: id がありません`);
  else {
    if (seenIds.has(v.id)) err(`${tag}: id が重複しています`);
    seenIds.add(v.id);
    if (!/^([a-z0-9]+-)?[0-9]{8}$/.test(v.id)) warn(`${tag}: id は '<yyyymmdd>' (適用開始日。シーズン接頭辞を付けてもよい) 形式が推奨です`);
  }
  if (typeof v.label !== 'string' || !v.label) warn(`${tag}: label がありません (選択 UI の表示名)`);
  if (typeof v.season !== 'string' || !v.season) warn(`${tag}: season がありません`);
  const keys = new Set();

  for (const [name, patch] of Object.entries(v.species || {})) {
    keys.add('sp:' + name); entryCount++;
    const sp = gen.species.get(idOf(name));
    if (!sp) { err(`${tag}: 種族 '${name}' は @smogon/calc に存在しません (読み飛ばされます)`); continue; }
    if (sp.name !== name) warn(`${tag}: 種族 '${name}' の正規名は '${sp.name}' です`);
    if (!patch || typeof patch !== 'object') { err(`${tag}: 種族 '${name}' の差分はオブジェクトでなければなりません`); continue; }
    for (const [prop, val] of Object.entries(patch)) {
      if (!SPECIES_PROPS.has(prop)) warn(`${tag}: 種族 '${name}' のプロパティ '${prop}' は想定外です (差分レイヤーはそのまま代入します)`);
      if (prop === 'baseStats') {
        if (!val || typeof val !== 'object') { err(`${tag}: 種族 '${name}' の baseStats はオブジェクトでなければなりません`); continue; }
        for (const [k, bv] of Object.entries(val)) {
          if (!STAT_KEYS.includes(k)) err(`${tag}: 種族 '${name}' の baseStats のキー '${k}' は無効です`);
          else if (!Number.isInteger(bv) || bv < 1 || bv > 255) err(`${tag}: 種族 '${name}' の baseStats.${k} = ${bv} は範囲外です (1-255 の整数)`);
        }
      }
      if (prop === 'types') {
        if (!Array.isArray(val) || val.length < 1 || val.length > 2) err(`${tag}: 種族 '${name}' の types は 1-2 個の配列でなければなりません`);
        else for (const t of val) if (!TYPE_NAMES.has(t)) err(`${tag}: 種族 '${name}' のタイプ '${t}' は存在しません`);
      }
    }
  }

  for (const [name, patch] of Object.entries(v.moves || {})) {
    keys.add('mv:' + name); entryCount++;
    const mv = gen.moves.get(idOf(name));
    if (!mv) { err(`${tag}: 技 '${name}' は @smogon/calc に存在しません (読み飛ばされます)`); continue; }
    if (mv.name !== name) warn(`${tag}: 技 '${name}' の正規名は '${mv.name}' です`);
    if (!patch || typeof patch !== 'object') { err(`${tag}: 技 '${name}' の差分はオブジェクトでなければなりません`); continue; }
    for (const [prop, val] of Object.entries(patch)) {
      if (!MOVE_PROPS.has(prop)) warn(`${tag}: 技 '${name}' のプロパティ '${prop}' は想定外です (差分レイヤーはそのまま代入します)`);
      if (prop === 'basePower' && (!Number.isInteger(val) || val < 0 || val > 300)) err(`${tag}: 技 '${name}' の basePower = ${val} は範囲外です (0-300 の整数)`);
      if (prop === 'accuracy' && !(val === true || (Number.isInteger(val) && val >= 1 && val <= 100))) err(`${tag}: 技 '${name}' の accuracy = ${val} は範囲外です (1-100 の整数または true)`);
      if (prop === 'type' && !TYPE_NAMES.has(val)) err(`${tag}: 技 '${name}' の type '${val}' は存在しません`);
      if (prop === 'category' && !CATEGORIES.has(val)) err(`${tag}: 技 '${name}' の category '${val}' は無効です`);
      if (prop === 'priority' && (!Number.isInteger(val) || val < -7 || val > 5)) err(`${tag}: 技 '${name}' の priority = ${val} は範囲外です (-7..5 の整数)`);
    }
  }

  for (const [atkType, defs] of Object.entries(v.types || {})) {
    keys.add('ty:' + atkType); entryCount++;
    if (!TYPE_NAMES.has(atkType)) { err(`${tag}: 攻撃タイプ '${atkType}' は存在しません (読み飛ばされます)`); continue; }
    if (!defs || typeof defs !== 'object') { err(`${tag}: タイプ '${atkType}' の差分はオブジェクトでなければなりません`); continue; }
    for (const [defType, mult] of Object.entries(defs)) {
      if (!TYPE_NAMES.has(defType)) err(`${tag}: 防御タイプ '${defType}' は存在しません`);
      else if (typeof mult !== 'number' || mult < 0 || mult > 4) err(`${tag}: 相性 ${atkType} -> ${defType} の倍率 ${mult} は範囲外です (0-4)`);
      else if (!MULTS.has(mult)) warn(`${tag}: 相性 ${atkType} -> ${defType} の倍率 ${mult} は通常値 (0/0.5/1/2) ではありません`);
    }
  }

  if (prevEntries) {
    for (const k of prevEntries) {
      if (!keys.has(k)) warn(`${tag}: 前バージョンにあった '${k}' がありません (各バージョンは差分の完全な集合です。意図した解除でなければ登録漏れです)`);
    }
  }
  prevEntries = keys;
}

// seasons の紐付け: 値は null か実在するバージョン id
if (data.seasons !== undefined) {
  if (!data.seasons || typeof data.seasons !== 'object' || Array.isArray(data.seasons)) err('seasons はオブジェクトでなければなりません');
  else for (const [season, id] of Object.entries(data.seasons)) {
    if (id !== null && !seenIds.has(id)) err(`seasons['${season}'] = '${id}' は存在しないバージョンです`);
  }
}

// regulation.json との整合: 現行シーズンの対応が一致していること
const regPath = new URL('../data/regulation.json', import.meta.url).pathname;
if (existsSync(regPath) && data.seasons && typeof data.seasons === 'object') {
  try {
    const reg = JSON.parse(readFileSync(regPath, 'utf8'));
    const expected = reg.season in data.seasons ? data.seasons[reg.season] : null;
    const actual = reg.specPatch ?? null;
    if (expected !== actual) err(`regulation.json の specPatch (${actual}) が seasons['${reg.season}'] (${expected}) と一致しません`);
  } catch { /* regulation が読めない場合はここでは扱わない */ }
}

console.log(`SPEC PATCH CHECK: ${errors === 0 ? 'OK' : 'FAILED'} (${versions.length} versions, ${entryCount} entries, ${warnings} warnings, ${errors} errors)`);
process.exit(errors === 0 ? 0 : 1);
