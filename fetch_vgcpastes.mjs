// VGCPastes Repository (公開 Google スプレッドシート) から、現行
// レギュレーションのタブ (Champions M-C 等) に載るチームのうち
// EVs 列が Yes のものを収集し、各チームの PokéPaste から完全な型を
// 取得して data/vgc_pastes.json (型コーパス + チーム出所)、
// data/vgc_pastes_stats.json (種族ごとの集計)、data/vgcpastes_sets.json
// (UI 用の種族別インデックス) を生成する。
//
// 取得方針:
//   - シートは認証なしの gviz JSON で取得する。タブ名は
//     regulation.json の regulation から組み立てる (M-C -> Champions M-C)
//   - ペーストは raw テキスト (URL + /raw) を取得し、data/vgc_cache/ に
//     ペースト ID 単位でキャッシュする。日次更新では新規・URL 変更分
//     だけを取得する (差分判定は Team ID / PokéPaste URL)
//   - 取得は直列で、リクエスト間に間隔を空ける (既定 1200ms)
//   - 型の解釈と検証は fetch_meta_sets.mjs と同じ (Champions の
//     ペーストは EVs 欄に SP がそのまま書かれる。検証は dex 照合、
//     特性の正当性、各 SP 32 以下・合計 66 以下)
//   - sets[] のレコード形式は meta_sets.json と互換 (sps は実数で埋まる)
//
// 実行: node fetch_vgcpastes.mjs [--limit N] [--delay MS] [--no-fetch]
// 結果サマリは VGCPASTES|... の 1 行で標準出力に出る。
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const args = process.argv.slice(2);
const LIMIT = args.includes('--limit') ? +args[args.indexOf('--limit') + 1] : 0;
const DELAY = args.includes('--delay') ? +args[args.indexOf('--delay') + 1] : 1200;
const NO_FETCH = args.includes('--no-fetch');

const SHEET_ID = '1axlwmzPA49rYkqXh7zHvAtSP-TKbM0ijGYBPRflLSWw';
const ROOT = new URL('.', import.meta.url).pathname;
const CACHE = ROOT + 'data/vgc_cache/';
mkdirSync(CACHE, { recursive: true });

const regulation = JSON.parse(readFileSync(ROOT + 'data/regulation.json', 'utf-8'));
const REG = regulation.regulation || 'M-C';
const TAB = `Champions ${REG}`;

function curl(url, maxTime = 40) {
  return execFileSync('curl', ['-sL', '--retry', '2', '--max-time', String(maxTime),
    '-A', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    url], { maxBuffer: 64 * 1024 * 1024 }).toString('utf-8');
}
const sleep = ms => execFileSync('sleep', [String(ms / 1000)]);
const todayJST = () => new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));

/* ---------------- 検証リスト (fetch_meta_sets.mjs と同じ) ---------------- */
const dex = JSON.parse(readFileSync(ROOT + 'data/champions_dex.json', 'utf-8'));
const DEX_SPECIES = new Set(dex.species);
const DEX_ITEMS = new Set(dex.items);
const DEX_MOVES = new Set(dex.moves);
const speciesAbilities = JSON.parse(readFileSync(ROOT + 'data/species_abilities.json', 'utf-8'));
const NATURES = new Set(['Hardy', 'Lonely', 'Brave', 'Adamant', 'Naughty', 'Bold',
  'Docile', 'Relaxed', 'Impish', 'Lax', 'Timid', 'Hasty', 'Serious', 'Jolly',
  'Naive', 'Modest', 'Mild', 'Quiet', 'Bashful', 'Rash', 'Calm', 'Gentle',
  'Sassy', 'Careful', 'Quirky']);

/* ---------------- シートの取得と解析 ---------------- */
function fetchSheet() {
  const url = `https://docs.google.com/spreadsheets/d/${SHEET_ID}/gviz/tq?tqx=out:json&sheet=${encodeURIComponent(TAB)}`;
  const raw = curl(url, 60);
  const start = raw.indexOf('setResponse(') + 'setResponse('.length;
  const end = raw.trimEnd().replace(/;$/, '').lastIndexOf(')');
  const doc = JSON.parse(raw.slice(start, end));
  if (doc.status !== 'ok') throw new Error('gviz status: ' + doc.status);
  return doc.table;
}

const MONTHS = { Jan: 1, Feb: 2, Mar: 3, Apr: 4, May: 5, Jun: 6,
  Jul: 7, Aug: 8, Sep: 9, Oct: 10, Nov: 11, Dec: 12 };
function cellVal(row, i) {
  const c = (row.c || [])[i];
  if (!c) return null;
  return c.v !== undefined && c.v !== null ? c.v : (c.f ?? null);
}
function cellText(row, i) {
  const c = (row.c || [])[i];
  if (!c) return null;
  const v = c.f !== undefined && c.f !== null ? c.f : c.v;
  return v === undefined || v === null ? null : String(v).trim();
}
function parseSheetDate(row, i) {
  const v = cellVal(row, i);
  if (typeof v === 'string') {
    const m = v.match(/^Date\((\d+),(\d+),(\d+)/);
    if (m) return `${m[1]}-${String(+m[2] + 1).padStart(2, '0')}-${String(m[3]).padStart(2, '0')}`;
  }
  const t = cellText(row, i);
  const m = t && t.match(/^(\d{1,2}) (\w{3}) (\d{4})$/);
  if (m && MONTHS[m[2]]) return `${m[3]}-${String(MONTHS[m[2]]).padStart(2, '0')}-${String(+m[1]).padStart(2, '0')}`;
  return null;
}
const cleanOpt = s => (s && s !== '-' && s !== 'None') ? s : null;

function parseSheet(table) {
  const dateCol = table.cols.findIndex(c => c.type === 'date');
  let headerIdx = -1;
  let col = {};
  for (let r = 0; r < table.rows.length; r++) {
    if (cellText(table.rows[r], 0) === 'Team ID') {
      headerIdx = r;
      const labels = table.rows[r].c.map(c => (c && (c.f ?? c.v)) ? String(c.f ?? c.v).trim() : '');
      const find = name => labels.indexOf(name);
      // レンタルコードの列見出しは "Replica Code\n(Click text for
      // image)" と改行・注記付きのため、前方一致で探す
      const findPrefix = prefix => labels.findIndex(l => l.startsWith(prefix));
      col = {
        id: find('Team ID'), desc: find('Team Description'), creator: find('Full Name'),
        paste: find('Pokepaste'), evs: find('EVs'), event: find('Tournament / Event'),
        rank: find('Rank'), source: find('Link to Source'), owner: find('Owner'),
        code: findPrefix('Replica Code'),
        date: dateCol,
      };
      break;
    }
  }
  if (headerIdx < 0) throw new Error('header row not found');
  for (const k of ['id', 'desc', 'paste', 'evs']) {
    if (col[k] < 0) throw new Error('column not found: ' + k);
  }
  const teams = [];
  for (let r = headerIdx + 1; r < table.rows.length; r++) {
    const row = table.rows[r];
    const teamId = cellText(row, col.id);
    if (!teamId) continue;
    if (cellText(row, col.evs) !== 'Yes') continue;
    const pasteUrl = cellText(row, col.paste);
    if (!pasteUrl || !pasteUrl.includes('pokepast.es/')) continue;
    teams.push({
      teamId,
      description: cellText(row, col.desc) || '',
      creator: col.creator >= 0 ? cellText(row, col.creator) : null,
      owner: col.owner >= 0 ? cellText(row, col.owner) : null,
      pasteUrl: pasteUrl.replace(/\/$/, ''),
      date: col.date >= 0 ? parseSheetDate(row, col.date) : null,
      event: col.event >= 0 ? cleanOpt(cellText(row, col.event)) : null,
      rank: col.rank >= 0 ? cleanOpt(cellText(row, col.rank)) : null,
      sourceUrl: col.source >= 0 ? cleanOpt(cellText(row, col.source)) : null,
      rentalCode: col.code >= 0 ? cleanOpt(cellText(row, col.code)) : null,
    });
  }
  return teams;
}

/* ---------------- ペーストの解析 (fetch_meta_sets.mjs と同じ解釈) ---------------- */
function parseShowdownText(text) {
  const sets = [];
  for (const block of text.split(/\r?\n\s*\r?\n/)) {
    const lines = block.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    if (!lines.length) continue;
    let head = lines[0].replace(/\s{2,}$/, '');
    let item = null;
    const atIdx = head.lastIndexOf(' @ ');
    if (atIdx >= 0) { item = head.slice(atIdx + 3).trim(); head = head.slice(0, atIdx).trim(); }
    head = head.replace(/\s*\((M|F)\)\s*$/, '');
    let species = head;
    const paren = head.match(/\(([^)]+)\)\s*$/);
    if (paren) species = paren[1];
    const set = { species, item, ability: null, nature: null, moves: [],
      evs: null, level: null, teraType: null };
    for (const line of lines.slice(1)) {
      if (line.startsWith('Ability:')) set.ability = line.slice(8).trim();
      else if (line.startsWith('- ')) set.moves.push(line.slice(2).trim());
      else if (/Nature$/.test(line)) set.nature = line.replace(/\s*Nature$/, '').trim();
      else if (line.startsWith('Level:')) {
        const lv = parseInt(line.slice(6).trim(), 10);
        if (Number.isInteger(lv)) set.level = lv;
      }
      else if (line.startsWith('Tera Type:')) set.teraType = line.slice(10).trim();
      else if (line.startsWith('EVs:')) {
        // 生の値をそのまま保持する (換算・丸めは取り込み側の判断。
        // 型推定エンジンチャットの要件 2026-11-22)
        const ev = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
        const key = { HP: 'hp', Atk: 'atk', Def: 'def', SpA: 'spa', SpD: 'spd', Spe: 'spe' };
        let ok = true;
        for (const part of line.slice(4).split('/')) {
          const mm = part.trim().match(/^(\d+) (HP|Atk|Def|SpA|SpD|Spe)$/);
          if (!mm) { ok = false; break; }
          ev[key[mm[2]]] = +mm[1];
        }
        if (ok) set.evs = ev;
      }
    }
    if (set.moves.length) sets.push(set);
  }
  return sets;
}

// 生 EVs から Champions の SP 解釈を導く (各 32 以下・合計 66 以下なら
// そのまま SP、全て 8 の倍数なら古典 EV とみなして 1/8)。解釈できない
// 場合は null (生値は evs 側に残るため、情報は落ちない)
function interpretSP(evs) {
  if (!evs) return null;
  const vals = Object.values(evs);
  const total = vals.reduce((a, b) => a + b, 0);
  if (vals.every(v => v <= 32) && total <= 66) return { ...evs };
  if (vals.every(v => v % 8 === 0)) {
    const conv = Object.fromEntries(Object.entries(evs).map(([k, v]) => [k, v / 8]));
    if (Object.values(conv).every(v => v <= 32) && total / 8 <= 66) return conv;
  }
  return null;
}

// メガストーンからメガフォルムを引く (calc のアイテムデータが持つ
// megaStone {基本種族: メガフォルム} を正とする。ストーン名は
// Golisopite のように不規則なため、名前からの推定はしない)
const toID = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');
function megaFromStone(speciesName, item) {
  if (!item) return null;
  let it;
  try { it = gen.items.get(toID(item)); } catch { return null; }
  const ms = it && it.megaStone;
  if (!ms) return null;
  // ペーストがメガフォルム名そのもので書かれている場合 (例:
  // "Meowstic-F-Mega @ Meowsticite") は、その名前をそのまま採用する
  if (Object.values(ms).includes(speciesName)) return speciesName;
  if (ms[speciesName]) return ms[speciesName];
  // 性別フォルム表記などのずれ: 基本種族が一致するキーを採用する
  let ss;
  try { ss = gen.species.get(toID(speciesName)); } catch { return null; }
  if (!ss) return null;
  const myBase = ss.baseSpecies ?? ss.name;
  for (const [baseName, mega] of Object.entries(ms)) {
    let bs;
    try { bs = gen.species.get(toID(baseName)); } catch { continue; }
    if (bs && (bs.baseSpecies ?? bs.name) === myBase) return mega;
  }
  return null;
}

/* ---------------- 正規化と検証 (fetch_meta_sets.mjs の normalize と同じ) ---------------- */
// ペースト側の表記ゆれ (小文字の性格名、"U-Turn" のような大文字違い) は
// 正規スペルへ寄せてから検証する
const canonMap = set => {
  const m = new Map();
  for (const v of set) m.set(v.toLowerCase(), v);
  return m;
};
const NATURE_BY_LOWER = canonMap(NATURES);
const ITEM_BY_LOWER = canonMap(DEX_ITEMS);
const MOVE_BY_LOWER = canonMap(DEX_MOVES);

const rejects = [];
function normalizeSet(raw, ctx) {
  // 素の "Aegislash" 表記は calc / dex に単独の項目が無く、交代時の
  // 姿である Aegislash-Shield として解決する
  const speciesName = raw.species === 'Aegislash' ? 'Aegislash-Shield' : raw.species;
  let spec;
  try { spec = gen.species.get(toID(speciesName)); } catch { spec = null; }
  if (!spec && /-(F|M)$/.test(speciesName)) {
    try { spec = gen.species.get(toID(speciesName.replace(/-(F|M)$/, ''))); } catch { spec = null; }
  }
  if (!spec) { rejects.push(`${ctx}: unknown species "${raw.species}"`); return null; }
  const base = spec.baseSpecies ?? spec.name;
  let forme = null;
  if (raw.megaSpecies) forme = raw.megaSpecies;
  else if (spec.name !== base) forme = spec.name;
  const formeKey = forme || base;
  if (!DEX_SPECIES.has(formeKey)) { rejects.push(`${ctx}: ${formeKey} not in champions_dex`); return null; }
  if (raw.item) {
    const canonItem = ITEM_BY_LOWER.get(raw.item.toLowerCase());
    if (canonItem) raw.item = canonItem;
    if (!DEX_ITEMS.has(raw.item)) { rejects.push(`${ctx}: item "${raw.item}" not in dex (${formeKey})`); return null; }
  }
  const natureText = raw.nature ? raw.nature.normalize('NFKD').replace(/[̀-ͯ]/g, '') : null;
  const nature = natureText ? NATURE_BY_LOWER.get(natureText.toLowerCase()) : null;
  if (!nature) { rejects.push(`${ctx}: bad nature "${raw.nature}" (${formeKey})`); return null; }
  raw.nature = nature;
  const legalAbilities = new Set([
    ...(speciesAbilities[formeKey] || []),
    ...(speciesAbilities[spec.name] || []),
    ...(speciesAbilities[base] || []),
    ...Object.values(spec.abilities || {}),
  ]);
  // メガの型の Ability 欄は進化前の特性が書かれる。性別フォルムの
  // メガ (Meowstic-F-Mega 等) は baseSpecies が無印側を指すため、
  // メガ接尾辞を外したフォルムの特性も合法に含める
  if (forme && /-Mega(-[A-Z])?$/.test(forme)) {
    const preMega = forme.replace(/-Mega(-[A-Z])?$/, '');
    for (const a of speciesAbilities[preMega] || []) legalAbilities.add(a);
    try {
      const pre = gen.species.get(toID(preMega));
      for (const a of Object.values(pre.abilities || {})) legalAbilities.add(a);
    } catch { /* 対応する項目が無い場合は無視する */ }
  }
  const legalByLower = canonMap(legalAbilities);
  const ability = raw.ability ? legalByLower.get(raw.ability.toLowerCase()) : null;
  if (!ability) {
    rejects.push(`${ctx}: ability "${raw.ability}" not legal for ${formeKey}`); return null;
  }
  raw.ability = ability;
  if (!raw.moves.length || raw.moves.length > 4) { rejects.push(`${ctx}: moves count ${raw.moves.length} (${formeKey})`); return null; }
  raw.moves = raw.moves.map(mv => MOVE_BY_LOWER.get(mv.toLowerCase()) || mv);
  for (const mv of raw.moves) {
    if (!DEX_MOVES.has(mv)) { rejects.push(`${ctx}: move "${mv}" not in dex (${formeKey})`); return null; }
  }
  // SP の範囲外は棄却しない (生 EVs を残し、解釈は取り込み側に委ねる)
  const out = { species: base, forme, nature, sps: interpretSP(raw.evs),
    evs: raw.evs, item: raw.item, ability: raw.ability, moves: raw.moves };
  if (raw.level !== null && raw.level !== 50) out.level = raw.level;
  if (raw.teraType) out.teraType = raw.teraType;
  return out;
}

/* ---------------- weight (meta_sets の日付減衰に順位の基準値を対応付け) ---------------- */
function rankBase(rank) {
  if (!rank) return 0.3;
  const r = rank.toLowerCase();
  if (/champion|winner/.test(r)) return 1.0;
  if (/runner|finalist/.test(r)) return 0.85;
  if (/top\s*4|semifinal/.test(r)) return 0.7;
  if (/top\s*8|quarter/.test(r)) return 0.55;
  if (/top\s*16/.test(r)) return 0.4;
  if (/top\s*32/.test(r)) return 0.3;
  if (/top\s*64/.test(r)) return 0.2;
  return 0.3;
}
function weightFor(dateStr, rank, today) {
  if (!dateStr) return rankBase(rank);
  const days = Math.max(0, Math.floor((today - new Date(dateStr + 'T00:00:00Z')) / 86400000));
  return Math.round(rankBase(rank) * Math.pow(0.5, days / 365) * 1000) / 1000;
}

/* ---------------- 本体 ---------------- */
function pasteIdOf(url) {
  const m = url.match(/pokepast\.es\/([0-9a-f]+)/i);
  return m ? m[1] : null;
}

function main() {
  const today = todayJST();
  const todayStr = today.toISOString().slice(0, 10);
  const table = fetchSheet();
  let teams = parseSheet(table);
  if (LIMIT > 0) teams = teams.slice(0, LIMIT);
  console.log(`sheet: tab "${TAB}", EVs=Yes teams: ${teams.length}`);

  let fetched = 0, cachedCount = 0, missing = 0;
  const teamOut = [];
  const allSets = [];
  for (const t of teams) {
    const pid = pasteIdOf(t.pasteUrl);
    if (!pid) { missing++; continue; }
    const cachePath = CACHE + pid + '.txt';
    const missPath = CACHE + pid + '.missing';
    let text = null;
    if (existsSync(cachePath)) { text = readFileSync(cachePath, 'utf-8'); cachedCount++; }
    else if (existsSync(missPath)) {
      // 取得失敗の記録が 7 日以上前のものは、一時的な失敗として
      // 再取得を試す (恒常的な失敗はまた記録され、毎日は叩かない)
      const marked = readFileSync(missPath, 'utf-8').trim();
      const ageDays = (today - new Date(marked + 'T00:00:00Z')) / 86400000;
      if (!(ageDays >= 7)) { missing++; continue; }
    }
    else {
      if (NO_FETCH) { missing++; continue; }
      try {
        text = curl(t.pasteUrl + '/raw', 30);
        if (!text || text.length < 20) throw new Error('empty paste');
        writeFileSync(cachePath, text);
      } catch (e) {
        writeFileSync(missPath, todayStr);
        missing++;
        continue;
      }
      fetched++;
      if (fetched % 25 === 0) console.log(`  fetched ${fetched} pastes...`);
      if (DELAY > 0) sleep(DELAY);
    }
    const rawSets = parseShowdownText(text);
    const members = [];
    for (const raw of rawSets) {
      raw.megaSpecies = megaFromStone(raw.species, raw.item);
      const norm = normalizeSet(raw, t.teamId);
      if (!norm) continue;
      members.push(norm);
      allSets.push({ ...norm, megaSpecies: raw.megaSpecies || null, team: t });
    }
    teamOut.push({
      teamId: t.teamId, description: t.description, creator: t.creator,
      owner: t.owner, pasteUrl: t.pasteUrl, date: t.date, event: t.event,
      rank: t.rank, sourceUrl: t.sourceUrl, rentalCode: t.rentalCode, members,
    });
  }

  // sets[]: 同一型でも統合せず、全インスタンスを 1 件ずつ残す
  // (出現頻度そのものが事前確率の材料になるため。型推定エンジン
  // チャットの要件 2026-11-22)
  const spKey = sp => sp ? [sp.hp, sp.atk, sp.def, sp.spa, sp.spd, sp.spe].join(',') : 'null';
  const setsOut = allSets.map(s => {
    const rec = {
      species: s.species, forme: s.forme, nature: s.nature, sps: s.sps,
      evs: s.evs, item: s.item, ability: s.ability, moves: s.moves,
      source: 'vgcpastes', sourceLabel: s.team.description,
      player: s.team.creator || s.team.owner || null,
      date: s.team.date, weight: weightFor(s.team.date, s.team.rank, today),
      teamId: s.team.teamId, pasteUrl: s.team.pasteUrl,
      event: s.team.event, rank: s.team.rank, regulation: REG,
    };
    if (s.level) rec.level = s.level;
    if (s.teraType) rec.teraType = s.teraType;
    return rec;
  }).sort((a, b) =>
    b.weight - a.weight || (a.forme || a.species).localeCompare(b.forme || b.species));

  // stats: 全インスタンスをフォルム単位で集計する
  const dist = arr => {
    const m = new Map();
    for (const v of arr) if (v) m.set(v, (m.get(v) || 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  };
  const statsMap = new Map();
  for (const s of allSets) {
    const key = s.forme || s.species;
    if (!statsMap.has(key)) statsMap.set(key, { species: s.species, forme: s.forme,
      sets: [], teamIds: new Set() });
    const e = statsMap.get(key);
    e.sets.push(s);
    e.teamIds.add(s.team.teamId);
  }
  const statsOut = {};
  for (const key of [...statsMap.keys()].sort()) {
    const e = statsMap.get(key);
    const patterns = new Map();
    for (const s of e.sets) {
      if (!s.sps) continue;
      const k = spKey(s.sps);
      if (!patterns.has(k)) patterns.set(k, { sp: s.sps, count: 0 });
      patterns.get(k).count++;
    }
    statsOut[key] = {
      species: e.species, forme: e.forme, count: e.sets.length,
      teams: e.teamIds.size,
      items: dist(e.sets.map(s => s.item)),
      natures: dist(e.sets.map(s => s.nature)),
      abilities: dist(e.sets.map(s => s.ability)),
      moves: dist(e.sets.flatMap(s => s.moves)),
      spPatterns: [...patterns.values()].sort((a, b) => b.count - a.count).slice(0, 12),
    };
  }

  // UI 用の種族別インデックス (ダメージ計算チャットの要望形式):
  // フォルム名をキーに、その種族の収集型を label (Team Description
  // そのまま) 付きで並べる。同一型でもチームが違えば別エントリ。
  const uiSpecies = {};
  for (const s of allSets) {
    const key = s.forme || s.species;
    const entry = {
      label: s.team.description, ability: s.ability, item: s.item,
      nature: s.nature, sp: s.sps, moves: s.moves,
      teamId: s.team.teamId, date: s.team.date,
    };
    if (s.megaSpecies) entry.megaSpecies = s.megaSpecies;
    (uiSpecies[key] = uiSpecies[key] || []).push(entry);
  }
  const uiIndex = { version: 1, updated: todayStr, regulation: REG, species: uiSpecies };

  const corpus = { version: 1, updated: todayStr, regulation: REG,
    source: 'VGCPastes Repository', teams: teamOut, sets: setsOut };
  const stats = { version: 1, updated: todayStr, regulation: REG, species: statsOut };

  const writeIfChanged = (path, obj) => {
    const body = JSON.stringify(obj, null, 1) + '\n';
    if (existsSync(path)) {
      const old = JSON.parse(readFileSync(path, 'utf-8'));
      // weight は日付減衰で毎日わずかに動くため、変更判定からは外す
      // (実データが変わったときに書き直され、その際に再計算される。
      // 取り込み側も date と rank から再計算できる)
      const strip = o => {
        const c = { ...o };
        delete c.updated;
        if (Array.isArray(c.sets)) c.sets = c.sets.map(s => ({ ...s, weight: 0 }));
        return JSON.stringify(c);
      };
      if (strip(old) === strip(obj)) return false;
    }
    writeFileSync(path, body);
    return true;
  };
  const changed = [
    writeIfChanged(ROOT + 'data/vgc_pastes.json', corpus),
    writeIfChanged(ROOT + 'data/vgc_pastes_stats.json', stats),
    writeIfChanged(ROOT + 'data/vgcpastes_sets.json', uiIndex),
  ].some(Boolean);

  for (const r of rejects.slice(0, 20)) console.log('reject: ' + r);
  console.log(`VGCPASTES|teams=${teamOut.length}|instances=${allSets.length}` +
    `|sets=${setsOut.length}|species=${Object.keys(statsOut).length}` +
    `|fetched=${fetched}|cached=${cachedCount}|missing=${missing}` +
    `|rejects=${rejects.length}|changed=${changed ? 1 : 0}`);
}

main();
