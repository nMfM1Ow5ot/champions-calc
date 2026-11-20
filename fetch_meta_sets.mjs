// Victory Road の Pokémon Champions 大会チーム集 (Regulation M-C) と
// 大会結果アグリゲータ (Limitless) から、上位勢の実在の型を収集して
// data/meta_sets.json を生成する。
//
// 取得経路:
//   champions-replica 索引 (決勝進出 + トップカットの表)
//     -> 大会ページ (victoryroad.pro) の順位表にある vrpastes リンク
//        -> vrpastes バックエンド API (JSON) から型を取得
//     -> Limitless の大会ページは teamlist の Showdown テキストを解析
//
// 注意: オープン・チームシートには SP 配分が含まれないため、sps は null
// (不明) で収録する。性格・持ち物・特性・技の実在の組み合わせが本コーパス
// の中身であり、配分の次元は pokedb の分布と併用する前提である。
//
// 実行: node fetch_meta_sets.mjs [--no-fetch]
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const NO_FETCH = process.argv.includes('--no-fetch');
const CACHE = new URL('./data/meta_cache/', import.meta.url).pathname;
mkdirSync(CACHE, { recursive: true });

const INDEX_URL = 'https://victoryroad.pro/champions-replica/';
const VRPASTE_API = 'https://vrpaste-backend.vercel.app/api/paste/';

function curl(url) {
  return execFileSync('curl', ['-sL', '--retry', '3', '--max-time', '40',
    '-A', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    url], { maxBuffer: 64 * 1024 * 1024 }).toString('utf-8');
}
function cached(name, url) {
  const path = CACHE + name;
  if (existsSync(path)) return readFileSync(path, 'utf-8');
  if (NO_FETCH) throw new Error(`cache miss (no-fetch): ${name}`);
  const body = curl(url);
  writeFileSync(path, body);
  return body;
}
const stripTags = s => s.replace(/<[^>]+>/g, ' ').replace(/&amp;/g, '&')
  .replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
const normName = s => s.normalize('NFKD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();

/* ---------------- champions_dex による検証リスト ---------------- */
const dex = JSON.parse(readFileSync(new URL('./data/champions_dex.json', import.meta.url), 'utf-8'));
const DEX_SPECIES = new Set(dex.species);
const DEX_ITEMS = new Set(dex.items);
const DEX_MOVES = new Set(dex.moves);
const speciesAbilities = JSON.parse(readFileSync(new URL('./data/species_abilities.json', import.meta.url), 'utf-8'));
const NATURES = new Set(['Hardy', 'Lonely', 'Brave', 'Adamant', 'Naughty', 'Bold',
  'Docile', 'Relaxed', 'Impish', 'Lax', 'Timid', 'Hasty', 'Serious', 'Jolly',
  'Naive', 'Modest', 'Mild', 'Quiet', 'Bashful', 'Rash', 'Calm', 'Gentle',
  'Sassy', 'Careful', 'Quirky']);

/* ---------------- 索引 (champions-replica) の解析 ---------------- */
const MONTHS = { January: 1, February: 2, March: 3, April: 4, May: 5, June: 6,
  July: 7, August: 8, September: 9, October: 10, November: 11, December: 12 };
function parseDate(text) {
  const m = text.match(/\((\w+) (\d+)(?:st|nd|rd|th)\)/);
  if (!m) return null;
  const month = MONTHS[m[1]];
  const day = +m[2];
  const year = month >= 7 ? 2026 : 2027; // 2027 シーズンの大会は 2026 年後半開催
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
function parsePlacement(text) {
  // "Championships" に含まれる "Champion" と誤認しないよう、後続が英字でない場合のみ
  if (/(^|\s)Champion(?![A-Za-z])/.test(text)) return 'Champion';
  if (/(^|\s)Finalist(?![A-Za-z])/.test(text)) return 'Finalist';
  const m = text.match(/Top (\d+)/);
  return m ? `Top ${m[1]}` : null;
}
function parseIndex(html) {
  const entries = [];
  const sections = [
    ['Teams reaching finals of large tournaments', 'Other teams in top cuts of large tournaments'],
    ['Other teams in top cuts of large tournaments', 'Ranked Battles teams'],
  ];
  for (const [from, to] of sections) {
    const i1 = html.indexOf(from);
    const i2 = html.indexOf(to, i1 + 1);
    if (i1 < 0 || i2 < 0) continue;
    const seg = html.slice(i1, i2);
    for (const row of seg.match(/<tr[^>]*>[\s\S]*?<\/tr>/g) || []) {
      const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(x => x[1]);
      if (cells.length < 3) continue;
      const playerRaw = stripTags(cells[1]);
      const player = playerRaw.replace(/\s*\([\s\S]*$/, '').trim();
      const results = stripTags(cells[2]);
      const placement = parsePlacement(results);
      const date = parseDate(results);
      if (!player || !placement || !date) continue;
      const event = results
        .replace(/\s*\((?:January|February|March|April|May|June|July|August|September|October|November|December) \d+(?:st|nd|rd|th)\)\s*$/, '')
        .replace(new RegExp(`\\s*${placement === 'Champion' ? 'Champion' : placement === 'Finalist' ? 'Finalist' : 'Top \\d+'}\\s*$`), '')
        .trim();
      // 結果セルのリンクが大会ページとは限らない (paste 直リンクの行もある) ため、
      // 行内の全セルからリンクを拾い、種類で振り分ける
      const allLinks = cells.flatMap(c => [...c.matchAll(/href="([^"]+)"/g)].map(x => x[1]));
      const pasteLink = allLinks.find(u => /vrpastes\.com|pokepast\.es/.test(u)) || null;
      const link = pasteLink ||
        (cells[2].match(/href="([^"]+)"/) || [])[1] || null;
      const handle = (cells[1].match(/(?:twitter\.com|x\.com)\/([A-Za-z0-9_]+)/) || [])[1] || null;
      const alias = (playerRaw.match(/\(([^)]+)\)/) || [])[1]?.trim() || null;
      entries.push({ player, handle, alias, event, placement, date, eventUrl: link });
    }
  }
  // 同一 (選手, 大会) の重複を除く
  const seen = new Set();
  return entries.filter(e => {
    const k = normName(e.player) + '|' + e.event;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/* ---------------- 大会ページ (VR) -> 選手から paste ID ---------------- */
function parseVrEvent(html) {
  const byName = new Map();
  const byHandle = new Map();
  for (const row of html.match(/<tr[^>]*>[\s\S]*?<\/tr>/g) || []) {
    const pm = row.match(/(?:www\.)?vrpastes\.com\/([A-Za-z0-9]+)/);
    if (!pm) continue;
    const cells = [...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(x => x[1]);
    let name = null;
    let handle = null;
    for (const c of cells) {
      const hm = c.match(/(?:twitter\.com|x\.com)\/([A-Za-z0-9_]+)/);
      if (hm) {
        handle = hm[1];
        name = stripTags(c).replace(/\s*\([\s\S]*$/, '').trim();
        break;
      }
    }
    if (!name) continue;
    const key = normName(name);
    if (!byName.has(key)) byName.set(key, pm[1]); // 先勝ち (上位表が先に現れる)
    if (handle && !byHandle.has(handle.toLowerCase())) byHandle.set(handle.toLowerCase(), pm[1]);
  }
  return { byName, byHandle };
}

/* ---------------- Limitless: 順位表 -> teamlist テキスト ---------------- */
function parseLimitlessStandings(html, baseUrl) {
  const byName = new Map();
  for (const m of html.matchAll(/href="(\/tournament\/[^"]+\/player\/[^"]+\/teamlist)"/g)) {
    // teamlist リンク直前のプレイヤー表示名は表の構造依存のため、リンク周辺から拾う
    const idx = m.index;
    const around = html.slice(Math.max(0, idx - 1200), idx);
    const names = [...around.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map(x => stripTags(x[1]));
    const slug = decodeURIComponent(m[1].split('/player/')[1].split('/')[0]);
    byName.set(slug, baseUrl + m[1]);
    for (const n of names) {
      const k = normName(n.replace(/\s*\([\s\S]*$/, ''));
      if (k && !byName.has(k)) byName.set(k, baseUrl + m[1]);
    }
  }
  return byName;
}

/* ---------------- Showdown テキスト形式の解析 (Limitless / pokepast.es) ---------------- */
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
    const set = { species, item, ability: null, nature: null, moves: [], sps: null };
    for (const line of lines.slice(1)) {
      if (line.startsWith('Ability:')) set.ability = line.slice(8).trim();
      else if (line.startsWith('- ')) set.moves.push(line.slice(2).trim());
      else if (/Nature$/.test(line)) set.nature = line.replace(/\s*Nature$/, '').trim();
      else if (line.startsWith('EVs:')) {
        const sp = { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 };
        const key = { HP: 'hp', Atk: 'atk', Def: 'def', SpA: 'spa', SpD: 'spd', Spe: 'spe' };
        let ok = true;
        for (const part of line.slice(4).split('/')) {
          const mm = part.trim().match(/^(\d+) (HP|Atk|Def|SpA|SpD|Spe)$/);
          if (!mm) { ok = false; break; }
          sp[key[mm[2]]] = +mm[1];
        }
        if (ok) {
          const vals = Object.values(sp);
          const total = vals.reduce((a, b) => a + b, 0);
          if (vals.every(v => v <= 32) && total <= 66) set.sps = sp;
          else if (vals.every(v => v % 8 === 0)) {
            const conv = Object.fromEntries(Object.entries(sp).map(([k, v]) => [k, v / 8]));
            if (Object.values(conv).every(v => v <= 32) && total / 8 <= 66) set.sps = conv;
          }
        }
      }
    }
    if (set.moves.length) sets.push(set);
  }
  return sets;
}

/* ---------------- vrpastes API -> 型 ---------------- */
function setsFromVrPaste(json) {
  const sets = [];
  for (const t of json.teams || []) {
    sets.push({
      species: t.species,
      megaSpecies: t.megaEvolution ? t.megaEvolution.megaSpecies : null,
      item: t.item || null,
      ability: t.ability || null,
      nature: t.nature || null,
      moves: t.moves || [],
      sps: null, // OTS に配分は含まれない
    });
  }
  return sets;
}

/* ---------------- 正規化と検証 ---------------- */
const rejects = [];
const toID = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');
function normalizeSet(raw, ctx) {
  let spec;
  try { spec = gen.species.get(toID(raw.species)); } catch { spec = null; }
  if (!spec && /-(F|M)$/.test(raw.species)) {
    // 性別フォルム表記 (Pyroar-F 等): Champions のデータでは基本種族に統合される
    try { spec = gen.species.get(toID(raw.species.replace(/-(F|M)$/, ''))); } catch { spec = null; }
  }
  if (!spec) { rejects.push(`${ctx}: unknown species "${raw.species}"`); return null; }
  // この calc ビルドでは基本種族の baseSpecies が undefined になる
  const base = spec.baseSpecies ?? spec.name;
  let forme = null;
  if (raw.megaSpecies) forme = raw.megaSpecies;
  else if (spec.name !== base) forme = spec.name;
  const formeKey = forme || base;
  if (!DEX_SPECIES.has(formeKey)) { rejects.push(`${ctx}: ${formeKey} not in champions_dex`); return null; }
  if (raw.item && !DEX_ITEMS.has(raw.item)) { rejects.push(`${ctx}: item "${raw.item}" not in dex (${formeKey})`); return null; }
  // "Naïve" のようなダイアクリティカル付き表記を正規化する
  const nature = raw.nature ? raw.nature.normalize('NFKD').replace(/[̀-ͯ]/g, '') : null;
  if (!nature || !NATURES.has(nature)) { rejects.push(`${ctx}: bad nature "${raw.nature}" (${formeKey})`); return null; }
  raw.nature = nature;
  const legalAbilities = new Set([
    ...(speciesAbilities[formeKey] || []),
    ...(speciesAbilities[spec.name] || []),
    ...(speciesAbilities[base] || []),
    ...Object.values(spec.abilities || {}),
  ]);
  if (!raw.ability || !legalAbilities.has(raw.ability)) {
    rejects.push(`${ctx}: ability "${raw.ability}" not legal for ${formeKey}`);
    return null;
  }
  if (!raw.moves.length || raw.moves.length > 4) { rejects.push(`${ctx}: moves count ${raw.moves.length} (${formeKey})`); return null; }
  for (const mv of raw.moves) {
    if (!DEX_MOVES.has(mv)) { rejects.push(`${ctx}: move "${mv}" not in dex (${formeKey})`); return null; }
  }
  if (raw.sps) {
    const vals = Object.values(raw.sps);
    if (vals.some(v => v < 0 || v > 32) || vals.reduce((a, b) => a + b, 0) > 66) {
      rejects.push(`${ctx}: sps out of range (${formeKey})`);
      return null;
    }
  }
  return {
    species: base,
    forme,
    nature: raw.nature,
    sps: raw.sps,
    item: raw.item || null,
    ability: raw.ability,
    moves: raw.moves,
  };
}

/* ---------------- 重み付け ---------------- */
const PLACEMENT_BASE = { Champion: 1.0, Finalist: 0.85 };
function placementBase(p) {
  if (PLACEMENT_BASE[p]) return PLACEMENT_BASE[p];
  const n = +((p.match(/Top (\d+)/) || [])[1] || 0);
  if (n <= 4) return 0.7;
  if (n <= 8) return 0.55;
  if (n <= 16) return 0.4;
  if (n <= 32) return 0.3;
  if (n <= 64) return 0.2;
  return 0.15;
}
function weightFor(entry, today) {
  const days = Math.max(0, (today - new Date(entry.date + 'T00:00:00Z')) / 86400000);
  const w = placementBase(entry.placement) * Math.pow(0.5, days / 365);
  return Math.round(w * 1000) / 1000;
}

/* ---------------- 本体 ---------------- */
function main() {
  const today = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Tokyo' }));
  const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
  const indexHtml = cached('replica_index.html', INDEX_URL);
  const entries = parseIndex(indexHtml);
  console.log(`index entries: ${entries.length}`);

  const eventCache = new Map();
  const unresolved = [];
  const allSets = [];
  const sourceCounts = {};

  for (const entry of entries) {
    const ctx = `${entry.player} @ ${entry.event}`;
    try {
      let rawSets = null;
      let source = null;
      if (entry.eventUrl && entry.eventUrl.includes('vrpastes.com')) {
        // 索引の結果セルが paste 自体へ直接リンクしている行 (Alpensee Tour 等)
        const pasteId = entry.eventUrl.replace(/\/$/, '').split('/').pop();
        const pj = cached(`paste_${pasteId}.json`,
          `${VRPASTE_API}${pasteId}?lang=english`);
        rawSets = setsFromVrPaste(JSON.parse(pj));
        source = 'victoryroad';
      } else if (entry.eventUrl && entry.eventUrl.includes('pokepast.es')) {
        const pasteId = entry.eventUrl.replace(/\/$/, '').split('/').pop();
        const raw = cached(`pokepaste_${pasteId}.txt`,
          `https://pokepast.es/${pasteId}/raw`);
        rawSets = parseShowdownText(raw).map(s => ({ ...s, megaSpecies: null }));
        source = 'victoryroad';
      } else if (entry.eventUrl && entry.eventUrl.includes('victoryroad.pro')) {
        const slug = entry.eventUrl.replace(/\/$/, '').split('/').pop();
        if (!eventCache.has(slug)) {
          eventCache.set(slug, parseVrEvent(cached(`event_${slug}.html`, entry.eventUrl)));
        }
        const maps = eventCache.get(slug);
        const pasteId = maps.byName.get(normName(entry.player)) ||
          (entry.handle && maps.byHandle.get(entry.handle.toLowerCase()));
        if (!pasteId) { unresolved.push(`${ctx}: paste not found on event page`); continue; }
        const pj = cached(`paste_${pasteId}.json`,
          `${VRPASTE_API}${pasteId}?lang=english`);
        rawSets = setsFromVrPaste(JSON.parse(pj));
        source = 'victoryroad';
      } else if (entry.eventUrl && entry.eventUrl.includes('limitlesstcg.com')) {
        const base = 'https://play.limitlesstcg.com';
        const slug = entry.eventUrl.split('/tournament/')[1].split('/')[0];
        if (!eventCache.has('ll_' + slug)) {
          eventCache.set('ll_' + slug, parseLimitlessStandings(
            cached(`ll_standings_${slug}.html`, entry.eventUrl), base));
        }
        const maps = eventCache.get('ll_' + slug);
        const tlUrl = maps.get(normName(entry.player)) ||
          maps.get(entry.player.toLowerCase().replace(/\s+/g, '')) ||
          (entry.alias && maps.get(entry.alias.toLowerCase().replace(/\s+/g, '')));
        if (!tlUrl) { unresolved.push(`${ctx}: teamlist not found on standings`); continue; }
        const tlHtml = cached(`ll_team_${slug}_${tlUrl.split('/player/')[1].split('/')[0]}.html`, tlUrl);
        const m = tlHtml.match(/const teamlist = `([\s\S]*?)`;/);
        if (!m) { unresolved.push(`${ctx}: teamlist text not found`); continue; }
        rawSets = parseShowdownText(m[1]).map(s => ({ ...s, megaSpecies: null }));
        source = 'limitless';
      } else {
        unresolved.push(`${ctx}: unsupported event url ${entry.eventUrl}`);
        continue;
      }
      const w = weightFor(entry, today);
      for (const raw of rawSets) {
        const norm = normalizeSet(raw, ctx);
        if (!norm) continue;
        allSets.push({
          ...norm,
          source,
          sourceLabel: `${entry.event} ${entry.placement}`,
          player: entry.player,
          date: entry.date,
          weight: w,
        });
        sourceCounts[source] = (sourceCounts[source] || 0) + 1;
      }
    } catch (e) {
      unresolved.push(`${ctx}: ${e.message}`);
    }
  }

  // 同一の型 (種族/フォルム・性格・持ち物・特性・技構成) を統合し、最大の重みを残す
  const byKey = new Map();
  for (const s of allSets) {
    const k = [s.forme || s.species, s.nature, s.item, s.ability, [...s.moves].sort().join('/')].join('|');
    if (!byKey.has(k) || byKey.get(k).weight < s.weight) byKey.set(k, s);
  }
  const sets = [...byKey.values()].sort((a, b) =>
    b.weight - a.weight || (a.forme || a.species).localeCompare(b.forme || b.species));
  const out = { version: 1, updated: todayStr, sets };
  writeFileSync(new URL('./data/meta_sets.json', import.meta.url),
    JSON.stringify(out, null, 1) + '\n');

  const speciesCovered = new Set(sets.map(s => s.forme || s.species));
  console.log(`sets kept: ${sets.length} (raw ${allSets.length}, deduped ${allSets.length - sets.length})`);
  console.log(`species covered: ${speciesCovered.size}`);
  console.log(`by source (raw): ${JSON.stringify(sourceCounts)}`);
  console.log(`unresolved entries: ${unresolved.length}`);
  for (const u of unresolved) console.log(`  UNRESOLVED ${u}`);
  console.log(`rejects: ${rejects.length}`);
  for (const r of rejects) console.log(`  REJECT ${r}`);
}

main();
