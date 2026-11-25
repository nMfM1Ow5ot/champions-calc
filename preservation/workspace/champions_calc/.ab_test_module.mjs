
import { Generations, TEAM_PRESETS, assumedSet, usageSpec, calcMatchup, withCurHP, deriveBuild, damageRolls, statTable, moveData } from './bundle.mjs';

const gen = Generations.get(9);const STATJ = [['hp','HP'],['atk','ATK'],['def','DEF'],['spa','SPA'],['spd','SPD'],['spe','SPE']];
const TYPE_JA = {Normal:'ノーマル',Fire:'ほのお',Water:'みず',Electric:'でんき',Grass:'くさ',Ice:'こおり',Fighting:'かくとう',Poison:'どく',Ground:'じめん',Flying:'ひこう',Psychic:'エスパー',Bug:'むし',Rock:'いわ',Ghost:'ゴースト',Dragon:'ドラゴン',Dark:'あく',Steel:'はがね',Fairy:'フェアリー'};
const TYPE_SHORT = {Normal:'NRML',Fire:'FIRE',Water:'WATR',Electric:'ELEC',Grass:'GRASS',Ice:'ICE',Fighting:'FIGHT',Poison:'POISON',Ground:'GROUND',Flying:'FLYING',Psychic:'PSYC',Bug:'BUG',Rock:'ROCK',Ghost:'GHOST',Dragon:'DRAGON',Dark:'DARK',Steel:'STEEL',Fairy:'FARY'};
const TYPE_COLOR = {Normal:'#8a8a6a',Fire:'#d96f26',Water:'#4f7de0',Electric:'#d9b62a',Grass:'#67b83c',Ice:'#7fc9c6',Fighting:'#b02a24',Poison:'#923a92',Ground:'#c9a94f',Flying:'#8f7fe8',Psychic:'#e84f7f',Bug:'#93a51a',Rock:'#a08f2f',Ghost:'#5f4a8a',Dragon:'#5f2ef0',Dark:'#5f4a3d',Steel:'#9a9ab5',Fairy:'#d685ad'};
const NATURES = ['Hardy','Lonely','Brave','Adamant','Naughty','Bold','Docile','Relaxed','Impish','Lax','Timid','Hasty','Serious','Jolly','Naive','Modest','Mild','Quiet','Bashful','Rash','Calm','Gentle','Sassy','Careful','Quirky'];
const NAT_JA = {Hardy:'がんばりや',Lonely:'さみしがり',Brave:'ゆうかん',Adamant:'いじっぱり',Naughty:'やんちゃ',Bold:'ずぶとい',Docile:'すなお',Relaxed:'のんき',Impish:'わんぱく',Lax:'のうてんき',Timid:'おくびょう',Hasty:'せっかち',Serious:'まじめ',Jolly:'ようき',Naive:'むじゃき',Modest:'ひかえめ',Mild:'おっとり',Quiet:'れいせい',Bashful:'てれや',Rash:'うっかりや',Calm:'おだやか',Gentle:'おとなしい',Sassy:'なまいき',Careful:'しんちょう',Quirky:'きまぐれ'};
const NAT_UPDOWN = {Lonely:['atk','def'],Brave:['atk','spe'],Adamant:['atk','spa'],Naughty:['atk','spd'],Bold:['def','atk'],Relaxed:['def','spe'],Impish:['def','spa'],Lax:['def','spd'],Timid:['spe','atk'],Hasty:['spe','def'],Jolly:['spe','spa'],Naive:['spe','spd'],Modest:['spa','atk'],Mild:['spa','def'],Quiet:['spa','spe'],Rash:['spa','spd'],Calm:['spd','atk'],Gentle:['spd','def'],Sassy:['spd','spe'],Careful:['spd','spa']};
const itemLabel = en => en ? ((typeof NAMES !== 'undefined' && NAMES._itemEn2ja && NAMES._itemEn2ja[en]) || en) : 'なし';

let NAMES = { species: {}, moves: {}, abilities: {} };
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
const ja = (table, en) => (NAMES[table] && NAMES[table][idOf(en)]) || en;

const $ = id => document.getElementById(id);
const state = {
  field: { weather: '', terrain: '' },
  side: {
    mine: { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false },
    opp: { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false },
  },
  mine: [], opps: [],
  oppTeam: ['Garchomp', 'Rillaboom'],
  sel: { mine: 0, opps: 0 },
  active: { mine: [0, 1], opps: [0, 1] },
};
let lastCalc = null;
// ひんし (HP0) になったポケモンは、対戦中に state.json の誤読で HP が戻らないようロックする (種族名)
const faintLock = { mine: new Set(), opps: new Set() };
// さいきのいのり (Revival Blessing) の使用回数 (側ごと)。使われた直後の復活 (HP約50%) だけロックを解除する
const revivalPending = { mine: 0, opps: 0 };
let lastStateJson = '';
const ui = { importing: {}, crit: { mine: false, opps: false }, formePop: null, spreadSel: { mine: {}, opps: {} } };

function blankBoosts() { return { atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }; }
let PRESETS = TEAM_PRESETS; // my_team.json があれば読み取り登録した自チームに差し替わる
function presetSpec(i) {
  const p = PRESETS[i];
  return { preset: i, species: p.species, megaSpecies: p.megaSpecies, mega: !!p.megaSpecies && i === 1, item: p.item,
    ability: p.ability, megaAbility: p.megaAbility, nature: p.nature, sp: { ...p.sp }, moves: [...p.moves], origMoves: [...p.moves],
    curHPPercent: 100, boosts: blankBoosts(), status: '' };
}
// 表示名 (括弧書きのフォルム表記を除いた日本語名) が同じフォルム違いの候補。
// 例: イエッサン -> [Indeedee, Indeedee-F]、キュウコン -> [Ninetales, Ninetales-Alola]
function speciesVariants(en) {
  const idx = NAMES._indexSpecies || [];
  const disp = jaName => (jaName || '').replace(/（[^）]*）/g, '').replace(/\([^)]*\)/g, '');
  const mine = idx.find(e => e.en === en);
  if (!mine) return [en];
  const d = disp(mine.ja);
  const out = [];
  for (const e of idx) if (disp(e.ja) === d && !out.includes(e.en)) out.push(e.en);
  return out.length ? out : [en];
}
// my_team.json の1体分 (reader の --team モードが書く) をプリセット形式に変換する。
// stats があれば SP・性格を逆算し、item がメガストーンならメガ形態も導く。
function myTeamPreset(e) {
  let species = resolveSpecies(e.species) || e.species;
  let sd = gen.species.get(idOf(species));
  if (!sd) return null;
  let nature, sp, ambiguous = false;
  let sols = e.stats ? deriveBuild(species, e.stats) : [];
  if (e.stats && !sols.length) {
    // 登録名のフォルムでは実数値を再現できない場合、同名のフォルム違い
    // (性別・リージョン等) で再現できるものを採用する
    for (const cand of speciesVariants(species)) {
      if (cand === species) continue;
      const s = deriveBuild(cand, e.stats);
      if (s.length) { sols = s; species = cand; sd = gen.species.get(idOf(cand)); break; }
    }
  }
  if (sols.length) {
    let pick = sols[0];
    if (e.spHint) {
      const keys = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
      const m = sols.find(s => keys.every(k => (s.sp[k] || 0) === (e.spHint[k] || 0)));
      if (m) pick = m;
    }
    nature = pick.nature; sp = pick.sp; ambiguous = sols.length > 1;
  }
  else { const a = assumedSet(species, 'attacker'); nature = a.nature; sp = a.sp; }
  const item = e.item ? (resolveItem(e.item) || '') : '';
  let megaSpecies, megaAbility;
  if (item) {
    const it = gen.items.get(idOf(item));
    if (it && it.megaStone) megaSpecies = Object.values(it.megaStone)[0];
  }
  if (!megaSpecies && e.item && /ナイト/.test(e.item)) {
    const m = String(e.item).replace(/[Ａ-Ｚ]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0)).match(/ナイト([XYZ])?$/);
    const cand = gen.species.get(idOf(species + '-Mega' + (m && m[1] ? '-' + m[1] : '')));
    if (cand) megaSpecies = cand.name;
  }
  if (megaSpecies) {
    const msd = gen.species.get(idOf(megaSpecies));
    if (msd) megaAbility = Object.values(msd.abilities || {})[0];
  }
  const ability = (e.ability && resolveAbility(e.ability)) || Object.values(sd.abilities || {})[0] || '';
  let moves = Array.isArray(e.moves) ? e.moves.map(mv => resolveMove(mv) || mv).filter(Boolean) : [];
  if (!moves.length) { const u = usageSpec(species, USAGE_SETS); if (u) moves = [...u.moves]; }
  return { label: ja('species', species), species, megaSpecies, megaAbility, item, ability, nature, sp,
    moves: moves.slice(0, 4), derivedAmbiguous: ambiguous, derivedFailed: !sols.length };
}
// my_team.json を読み直して自チームプリセットに反映する (撮影取り込み後にも使う)
async function loadMyTeam() {
  try {
    const rt = await fetch('./my_team.json', { cache: 'no-store' });
    if (!rt.ok) return false;
    const mt = await rt.json();
    const list = (Array.isArray(mt) ? mt : []).map(myTeamPreset).filter(Boolean);
    if (!list.length) return false;
    PRESETS = list;
    state.mine = list.map((_, i) => presetSpec(i));
    state.sel.mine = 0;
    state.active.mine = [0, Math.min(1, list.length - 1)];
    faintLock.mine.clear();
    return true;
  } catch (e) { return false; }
}
// 撮影ボタン: リーダー (localhost:8899) に QuickTime 画面の撮影と解析を頼む
async function captureTeam(tab) {
  const st = $('capStatusText');
  const say = (msg, cls) => { if (st) { st.textContent = msg; st.className = cls || ''; } };
  say('撮影中…', '');
  try {
    const r = await fetch('http://localhost:8899/capture?tab=' + tab);
    const j = await r.json();
    if (j.ok) {
      await loadMyTeam();
      calcAll();
      say('撮影成功： ' + (j.message || '取り込みました'), 'ok');
    } else {
      say('撮影失敗： ' + (j.error || '画面を確認してください'), 'ng');
    }
  } catch (e) {
    say('撮影失敗： リーダーに接続できません（run_reader.sh を起動してください）', 'ng');
  }
}
let CHAMP = null; // data/champions_dex.json (チャンピオンズ実装済みリスト)
let CHAMP_MOVES_JA = null;
function champMoveList() { return CHAMP_MOVES_JA || Object.keys(NAMES._moveJa2en || {}); }
let USAGE_SETS = null; // data/usage_sets.json の sets (pokedb 使用率トップ型)
let POKEDB_PARSED = null; // data/pokedb_parsed.json (pokedb の使用率分布一式。ベイズ推定の候補生成用)
let oppTrainerName = ''; // state.json から受け取る相手トレーナー名
let USAGE_SEASON = '';
// 使用率型の解決: フォルム名 (イルカマン(ヒーロー)等) には使用率データが
// 無いため、ベース種族の型を流用し種族名だけ差し替える
// (これが無いとフォルム表示のパネルは技が全部「（技なし）」になる)
function usageFor(speciesEn) {
  const direct = usageSpec(speciesEn, USAGE_SETS);
  if (direct) return direct;
  const base = gen.species.get(idOf(speciesEn))?.baseSpecies;
  if (base && base !== speciesEn) {
    const bu = usageSpec(base, USAGE_SETS);
    if (bu) return { ...bu, species: speciesEn };
  }
  return null;
}
function oppSpec(speciesEn, kind) {
  if (kind === 'usage') {
    const u = usageFor(speciesEn);
    if (u) return { ...u, kind, moves: [...u.moves], origMoves: [...u.moves], knownMoves: [],
      curHPPercent: 100, boosts: blankBoosts(), status: '', corrected: [] };
  }
  const a = assumedSet(speciesEn, kind === 'usage' ? 'attacker' : kind);
  const u = usageFor(speciesEn);
  const moves = u ? [...u.moves] : [];
  return { species: speciesEn, kind, sp: { ...a.sp }, nature: a.nature, ability: a.ability, item: '',
    moves, origMoves: [...moves], knownMoves: [], curHPPercent: 100, boosts: blankBoosts(), status: '', note: a.note, corrected: [],
    noUsage: kind === 'usage' && !USAGE_SETS ? true : undefined };
}
// 対戦画面で判明した情報 (技・持ち物・特性) を想定型の上に部分的に上書きする
function applyRevealed(spec, rev) {
  if (!rev) return spec;
  const corr = new Set(spec.corrected || []);
  if (rev.ability) {
    const ab = resolveAbility(rev.ability) || rev.ability;
    if (spec.mega && spec.megaSpecies) {
      const ms = gen.species.get(idOf(spec.megaSpecies));
      const mabs = ms ? (Array.isArray(ms.abilities) ? ms.abilities : Object.values(ms.abilities || {})) : [];
      if (mabs.includes(ab)) spec.megaAbility = ab; else spec.ability = ab;
    } else spec.ability = ab;
    corr.add('特性');
  }
  if (rev.item != null) {
    spec.item = rev.item === 'none' || rev.item === '' ? '' : (resolveItem(rev.item) || rev.item);
    corr.add('持ち物');
    if (spec.item) {
      const io = gen.items.get(idOf(spec.item));
      const ms = io && io.megaStone ? Object.values(io.megaStone)[0] : null;
      if (ms) {
        // 持ち物がメガストーンと分かっただけではメガシンカ済みにしない
        // (実際のメガシンカは state.json の mega 通知で applyMegaFlag が立てる)
        spec.megaSpecies = ms;
        const msd = gen.species.get(idOf(ms));
        if (msd) spec.megaAbility = Array.isArray(msd.abilities) ? msd.abilities[0] : Object.values(msd.abilities || {})[0];
      }
    }
  }
  if (Array.isArray(rev.moves) && rev.moves.length) {
    const rms = rev.moves.map(m => resolveMove(m) || m).filter(Boolean);
    spec.moves = [...new Set([...rms, ...(spec.moves || [])])].slice(0, 4);
    if (!Array.isArray(spec.knownMoves)) spec.knownMoves = [];
    for (const m of rms) if (!spec.knownMoves.includes(m)) spec.knownMoves.push(m);
    corr.add('技');
  }
  spec.corrected = [...corr];
  return spec;
}
const z2h = s => String(s).replace(/[Ａ-Ｚａ-ｚ０-９]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));
function resolveItem(name) {
  const t = z2h(String(name).trim());
  if (NAMES._itemJa2en && NAMES._itemJa2en[t]) return NAMES._itemJa2en[t];
  const it = gen.items.get(idOf(t));
  return it ? it.name : null;
}
function setEv(side, k, raw, refocus) {
  const spec = state[side][state.sel[side]];
  spec.sp[k] = Math.min(32, Math.max(0, parseInt(raw) || 0));
  if (side === 'opps') markCorrected(spec, 'EV');
  calcAll();
  if (refocus) { const el = document.querySelector(`[data-ev="${side}:${k}"]`); if (el) { el.focus(); el.select(); } }
}
function markCorrected(spec, label) {
  if (!spec.corrected) spec.corrected = [];
  if (!spec.corrected.includes(label)) spec.corrected.push(label);
}
state.mine = PRESETS.map((_, i) => presetSpec(i));
state.sel.mine = 1;
state.active.mine = [1, 5];
state.opps = state.oppTeam.map(sp => oppSpec(sp, 'usage'));

const effSpecies = spec => (spec.mega && spec.megaSpecies) ? spec.megaSpecies : spec.species;
function speciesData(spec) { return gen.species.get(idOf(effSpecies(spec))); }
let SPECIES_ABILITIES = {};
function abilitiesOf(spec) {
  const sd = speciesData(spec);
  let vals;
  if (spec.mega && spec.megaSpecies) {
    const msd = gen.species.get(idOf(spec.megaSpecies));
    vals = msd ? Object.values(msd.abilities || {}) : [];
  } else {
    const base = (sd && sd.baseSpecies) || spec.species;
    const full = SPECIES_ABILITIES[base];
    if (full && full.length) vals = [...full];
    else vals = Array.isArray(sd.abilities) ? sd.abilities : Object.values(sd.abilities || {});
  }
  if (spec.ability && !vals.includes(spec.ability)) vals.push(spec.ability);
  return [...new Set(vals)];
}
function formesOf(en) {
  const sd = gen.species.get(idOf(en));
  if (!sd) return [en];
  const base = sd.baseSpecies || en;
  const bsd = gen.species.get(idOf(base));
  const others = (bsd && bsd.otherFormes) || sd.otherFormes || [];
  return [base, ...others.filter(f => f !== base)];
}
function megaFormesOf(en) { return formesOf(en).filter(f => f.includes('-Mega')); }
function stoneForForme(forme) {
  const sd = gen.species.get(idOf(forme));
  const base = sd?.baseSpecies;
  if (!base) return null;
  for (const it of gen.items) {
    if (it.megaStone && it.megaStone[base] === forme) return it.name;
  }
  return null;
}
function spriteId(en) {
  if (en === 'Greninja-Bond') return 'greninja-ash';
  let s = String(en).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  s = s.replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
  s = s.replace(/-mega-([xyz])$/, '-mega$1').replace(/^mr-/, 'mr')
    .replace(/(jangmo|hakamo|kommo)-o$/, '$1o')
    .replace(/paldea-(blaze|combat|aqua)$/, 'paldea$1')
    .replace(/-low-key$/, '-lowkey');
  return s;
}
function spriteURL(speciesEn) { return `https://play.pokemonshowdown.com/sprites/gen5/${spriteId(speciesEn)}.png`; }
function spriteImg(en, baseEn, cls) {
  return `<img class="${cls}" src="${spriteURL(en)}" data-spr="0" data-sid="${spriteId(en)}" data-base="${spriteId(baseEn || en)}" alt="">`;
}
function typeChips(spec) {
  return speciesData(spec).types.map(t => `<span class="typechip" style="background:${TYPE_COLOR[t] || '#555'}">${TYPE_JA[t] || t}</span>`).join('');
}
function natureMark(spec, key) {
  const ud = NAT_UPDOWN[spec.nature];
  if (!ud || key === 'hp') return null;
  if (ud[0] === key) return 'up';
  if (ud[1] === key) return 'down';
  return null;
}
const fmtPct = v => (Math.round(v * 10) / 10) % 1 === 0 ? String(Math.round(v)) : (Math.round(v * 10) / 10).toFixed(1);
function koColor(n, guaranteed) { if (n === 1) return guaranteed ? 'g' : 'o'; if (n <= 3) return 'o'; return 'r'; }
function koFmt(t) {
  if (!t) return null;
  let m;
  if (t === 'guaranteed OHKO') return ['1HKO', 'g'];
  if ((m = t.match(/^([\d.]+)% chance to OHKO/))) return [`${fmtPct(+m[1])}% 1HKO`, 'g'];
  if ((m = t.match(/^guaranteed (\d+)HKO/))) return [`${m[1]}HKO`, koColor(+m[1], true)];
  if ((m = t.match(/^([\d.]+)% chance to (\d+)HKO/))) return [`${fmtPct(+m[1])}% ${m[2]}HKO`, koColor(+m[2], false)];
  if ((m = t.match(/^possible (\d+)HKO/))) return [`${m[1]}HKO`, koColor(+m[1], false)];
  return [t, 'n'];
}

/* ---------- import / export ---------- */
function exportText(spec) {
  const spParts = STATJ.filter(([k]) => (spec.sp[k] || 0) > 0)
    .map(([k, j]) => `${spec.sp[k]} ${{ hp: 'HP', atk: 'Atk', def: 'Def', spa: 'SpA', spd: 'SpD', spe: 'Spe' }[k]}`);
  const lines = [
    `${effSpecies(spec)}${spec.item ? ' @ ' + spec.item : ''}`,
    `Ability: ${spec.mega && spec.megaAbility ? spec.megaAbility : spec.ability}`,
    'Level: 50',
    `${spec.nature} Nature`,
  ];
  if (spParts.length) lines.push(`SPs: ${spParts.join(' / ')}`);
  for (const mv of spec.moves || []) if (mv) lines.push(`- ${mv}`);
  return lines.join('\n');
}
function resolveSpecies(name) {
  const t = z2h(name.trim());
  if (!t) return null;
  if (NAMES._ja2en && NAMES._ja2en[t]) return NAMES._ja2en[t];
  const s = gen.species.get(idOf(t));
  return s ? s.name : null;
}
function resolveMove(name) {
  const t = z2h(name.trim());
  if (NAMES._moveJa2en && NAMES._moveJa2en[t]) return NAMES._moveJa2en[t];
  const m = gen.moves.get(idOf(t));
  return m ? m.name : null;
}
function resolveAbility(name) {
  const t = z2h(name.trim());
  if (NAMES._abilityJa2en && NAMES._abilityJa2en[t]) return NAMES._abilityJa2en[t];
  const a = gen.abilities.get(idOf(t));
  return a ? a.name : null;
}
function parseSet(text) {
  const lines = text.split('\n').map(l => l.trim()).filter(l => l !== '');
  if (!lines.length) return null;
  const out = { moves: [], sp: {} };
  const head = lines[0].split('@');
  out.species = resolveSpecies(head[0]);
  if (!out.species) return null;
  if (head[1]) out.item = head[1].trim();
  const statMap = { HP: 'hp', Atk: 'atk', Def: 'def', SpA: 'spa', SpD: 'spd', Spe: 'spe' };
  for (const line of lines.slice(1)) {
    let m;
    if ((m = line.match(/^Ability:\s*(.+)$/i))) out.ability = resolveAbility(m[1]) || m[1].trim();
    else if ((m = line.match(/^(\w+)\s+Nature$/i))) out.nature = m[1];
    else if ((m = line.match(/^SPs:\s*(.+)$/i))) for (const part of m[1].split('/')) { const p = part.trim().match(/^(\d+)\s+(\w+)$/); if (p && statMap[p[2]]) out.sp[statMap[p[2]]] = Math.min(32, +p[1]); }
    else if ((m = line.match(/^EVs:\s*(.+)$/i))) for (const part of m[1].split('/')) { const p = part.trim().match(/^(\d+)\s+(\w+)$/); if (p && statMap[p[2]]) out.sp[statMap[p[2]]] = Math.min(32, Math.round(+p[1] / 8)); }
    else if (line.startsWith('-')) { const mv = resolveMove(line.slice(1)); if (mv) out.moves.push(mv); }
  }
  return out;
}

/* ---------- displayed spec ---------- */
const DS = side => state[side][state.sel[side]];
const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/* ---------- custom dropdown (Showdex react-select reproduction) ---------- */
const DDREG = {};
let openDDId = null;
let SPECIES_OPTIONS = [], MOVE_OPTIONS = [], ITEM_OPTIONS = [];
function regDD(id, cfg) { DDREG[id] = cfg; }
function ddHTML(id) {
  const d = DDREG[id];
  if (!d) return '';
  const opt = d.options.find(o => o.v === d.value);
  const label = d.valueLabel || (opt ? opt.l : '');
  return `<div class="sdd${d.highlight ? ' highlight' : ''}${d.bare ? ' bare' : ''}" data-sdd="${id}">
    <div class="sdd-control" data-ddctl="${id}">
      <div class="sdd-value${label ? '' : ' ph'}">${esc(label || d.placeholder || '')}</div>
      ${d.extra || ''}
      ${d.clearable && d.value ? '<span class="sdd-clear" data-ddclear="' + id + '">✕</span>' : ''}
      <span class="sdd-chev"><svg width="10" height="10" viewBox="0 0 10 10"><path d="M1.5 3.2 5 6.8 8.5 3.2" stroke="currentColor" fill="none" stroke-width="1.6" stroke-linecap="round"/></svg></span>
    </div></div>`;
}
function ddListHTML(d, query, focusIdx) {
  const q = z2h(query || '').toLowerCase();
  const list = d.options.filter(o => !q || z2h(o.l).toLowerCase().includes(q) || String(o.v).toLowerCase().includes(q));
  if (!list.length) return { html: '<div class="sdd-empty">該当なし</div>', list };
  const html = list.map((o, i) => `<div class="sdd-opt${o.v === d.value ? ' selected' : ''}${i === focusIdx ? ' focused' : ''}" data-ddopt="${esc(o.v)}" data-ddidx="${i}">${esc(o.l)}</div>`).join('');
  return { html, list };
}
function openDD(id) {
  closeDD();
  const d = DDREG[id];
  const host = document.querySelector(`[data-sdd="${CSS.escape(id)}"]`);
  if (!d || !host) return;
  openDDId = id;
  host.classList.add('open');
  const ctl = host.querySelector('.sdd-control');
  const cur = d.options.find(o => o.v === d.value);
  ctl.innerHTML = `<input class="sdd-input" data-ddinput="${id}" placeholder="${esc(cur ? cur.l : (d.placeholder || ''))}">
    ${d.extra || ''}
    ${d.clearable && d.value ? '<span class="sdd-clear" data-ddclear="' + id + '">✕</span>' : ''}
    <span class="sdd-chev"><svg width="10" height="10" viewBox="0 0 10 10"><path d="M1.5 3.2 5 6.8 8.5 3.2" stroke="currentColor" fill="none" stroke-width="1.6" stroke-linecap="round"/></svg></span>`;
  const menu = document.createElement('div');
  menu.className = 'sdd-menu';
  menu.innerHTML = '<div class="sdd-list"></div>';
  host.appendChild(menu);
  const input = ctl.querySelector('.sdd-input');
  let focusIdx = Math.max(0, d.options.findIndex(o => o.v === d.value));
  const paint = () => {
    const { html, list } = ddListHTML(d, input.value, focusIdx);
    menu.querySelector('.sdd-list').innerHTML = html;
    menu._list = list;
    const f = menu.querySelector('.sdd-opt.focused');
    if (f) f.scrollIntoView({ block: 'nearest' });
  };
  paint();
  input.focus();
  input.addEventListener('input', () => { focusIdx = 0; paint(); });
  input.addEventListener('keydown', e => {
    const list = menu._list || [];
    if (e.key === 'ArrowDown') { e.preventDefault(); focusIdx = Math.min(list.length - 1, focusIdx + 1); paint(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); focusIdx = Math.max(0, focusIdx - 1); paint(); }
    else if (e.key === 'Enter') { e.preventDefault(); const o = list[focusIdx] || list[0]; if (o) pickDD(id, o.v); }
    else if (e.key === 'Escape') { closeDD(); }
  });
}
function closeDD() {
  if (!openDDId) return;
  const id = openDDId;
  openDDId = null;
  const host = document.querySelector(`[data-sdd="${CSS.escape(id)}"]`);
  if (host) { host.classList.remove('open'); const m = host.querySelector('.sdd-menu'); if (m) m.remove(); }
}
function pickDD(id, v) {
  const d = DDREG[id];
  closeDD();
  if (d && d.onPick) d.onPick(v);
}

/* ---------- status popover ---------- */
const STATUS_LIST = [['', '正常', 'OK', 'ok'], ['brn', 'やけど', 'BRN', 'brn'], ['par', 'まひ', 'PAR', 'par'], ['psn', 'どく', 'PSN', 'psn'], ['tox', 'もうどく', 'TOX', 'tox'], ['slp', 'ねむり', 'SLP', 'slp'], ['frz', 'こおり', 'FRZ', 'frz']];
const STATUS_ABBR = { brn: 'BRN', par: 'PAR', psn: 'PSN', tox: 'TOX', slp: 'SLP', frz: 'FRZ' };
let stPopEl = null;
function closeStPop() { if (stPopEl) { stPopEl.remove(); stPopEl = null; } }
function openStPop(side, anchor) {
  closeStPop();
  const spec = DS(side);
  stPopEl = document.createElement('div');
  stPopEl.className = 'stpop';
  stPopEl.innerHTML = STATUS_LIST.map(([v, jaName, abbr, cls]) =>
    `<button data-statuspick="${side}:${v}"><span class="stbadge ${cls}">${abbr}</span>${jaName}</button>`).join('');
  document.body.appendChild(stPopEl);
  const r = anchor.getBoundingClientRect();
  stPopEl.style.left = (window.scrollX + r.left) + 'px';
  stPopEl.style.top = (window.scrollY + r.bottom + 4) + 'px';
}
function statusBadgeHTML(spec) {
  if ((spec.curHPPercent ?? 100) <= 0) return '<span class="stbadge fnt">RIP</span>';
  if (spec.status) return `<span class="stbadge ${spec.status}">${STATUS_ABBR[spec.status] || ''}</span>`;
  return '<span class="stbadge ok">OK</span>';
}


function dispStat(spec, key, raw, sideKey) {
  if (key === 'hp') return [raw.hp, ''];
  let v = raw[key];
  const b = spec.boosts[key] || 0;
  if (b > 0) v = Math.floor(v * (2 + b) / 2); else if (b < 0) v = Math.floor(v * 2 / (2 - b));
  // 特性・道具による補正: ゲーム式 (@smogon/calc の atMods/dfMods) に合わせ、
  // ランク補正後の値に補正を 4096 固定小数点で連鎖させ、最後に pokeRound
  // (.5 は切り下げ) で 1 回だけ丸める。特性→道具の順も calc と同じ
  const ab = (spec.mega && spec.megaAbility) ? spec.megaAbility : spec.ability;
  let modChain = 4096;
  const pushMod = m => { modChain = Math.floor((modChain * m + 2048) / 4096); };
  if (key === 'atk' && (ab === 'Huge Power' || ab === 'Pure Power')) pushMod(8192);
  else if (key === 'atk' && ab === 'Gorilla Tactics') pushMod(6144);
  if (key === 'def' && ab === 'Fur Coat') pushMod(8192);
  if (key === 'spd' && ab === 'Ice Scales') pushMod(8192);
  const itm = spec.itemLost ? '' : spec.item;
  if (key === 'atk' && itm === 'Choice Band') pushMod(6144);
  if (key === 'spa' && itm === 'Choice Specs') pushMod(6144);
  if (modChain !== 4096) { const x = v * modChain / 4096; v = (x % 1 > 0.5) ? Math.ceil(x) : Math.floor(x); }
  if (key === 'spe') {
    if (itm === 'Choice Scarf') v = Math.floor(v * 1.5);
    if (spec.unburden && ab === 'Unburden') v *= 2;
    if (state.side[sideKey].tailwind) v *= 2;
    if (spec.status === 'par') v = Math.floor(v / 2);
  }
  return [v, v > raw[key] ? 'green' : v < raw[key] ? 'red' : ''];
}

/* ---------- panel parts (1 vs 1, Showdex PlayerCalc structure) ---------- */
function playerBar(side) {
  const isOpp = side === 'opps';
  const specs = state[side];
  const rack = specs.map((spec, i) => {
    const cls = ['picon', i === state.sel[side] ? 'sel' : '', state.active[side].includes(i) ? 'active' : '', (spec.curHPPercent ?? 100) <= 0 ? 'fnt' : ''].filter(Boolean).join(' ');
    const eff = effSpecies(spec);
    return `<button class="${cls}" data-icon="${side}:${i}" title="${esc(ja('species', eff))}">${spriteImg(eff, gen.species.get(idOf(eff))?.baseSpecies || eff, '')}</button>`;
  }).join('');
  return `<div class="playerbar">
    <div class="playerinfo">
      <div class="username">${isOpp ? '相手' : '自分'}</div>
      <div class="playeractions"><button class="tgl on" data-noop="1">AUTO</button></div>
    </div>
    <div class="rack">${rack}</div>
  </div>`;
}
function presetBox(side) {
  const spec = DS(side);
  let dd = '';
  if (side === 'mine') {
    regDD('preset:mine', {
      options: PRESETS.map((p, i) => ({ v: String(i), l: p.label })),
      value: String(state.sel.mine),
      onPick: v => { state.sel.mine = +v; calcAll(); },
    });
    dd = ddHTML('preset:mine');
  } else {
    regDD('preset:opps', {
      options: [
        { v: 'usage', l: '使用率トップ型（pokedb）' },
        { v: 'attacker', l: '火力特化型' },
        { v: 'bulky', l: '耐久型' },
        { v: 'none', l: '素の種族値' },
        { v: 'custom', l: 'カスタム' },
      ],
      value: spec.kind || 'usage',
      valueLabel: (spec.corrected && spec.corrected.length && oppTrainerName) ? oppTrainerName : '',
      onPick: v => {
        const keep = DS('opps');
        const ns = oppSpec(keep.species, v);
        ns.curHPPercent = keep.curHPPercent; ns.boosts = keep.boosts; ns.status = keep.status;
        state.opps[state.sel.opps] = ns;
        calcAll();
      },
    });
    dd = ddHTML('preset:opps');
  }
  const imp = ui.importing[side];
  return `<div class="presetbox">
    <div class="presethead">
      <div class="part"><span class="ddlabel" style="margin:0">SET</span><button class="tgl on" data-noop="1">AUTO</button></div>
      <div class="part">
        <button class="tgl" data-act="${side}:import">読み込み</button>
        <button class="tgl" data-act="${side}:export">書き出し</button>
        <button class="tgl" data-act="${side}:all">すべて書き出し</button>
      </div>
    </div>
    ${dd}
    ${imp ? `<textarea class="importbox" data-importbox="${side}" placeholder="Showdown形式のセットを貼り付け">${esc(imp === true ? '' : imp)}</textarea>
      <button class="tgl applybtn" data-applyimport="${side}">この内容で読み込む</button>` : ''}
  </div>`;
}
function pokeInfo(side) {
  const spec = DS(side);
  const eff = effSpecies(spec);
  const sd = speciesData(spec);
  let nameHTML;
  if (side === 'opps') {
    regDD('species:opps', {
      options: SPECIES_OPTIONS, value: spec.species, bare: true,
      valueLabel: ja('species', eff),
      onPick: v => {
        if (!v || v === spec.species) return;
        const keep = DS('opps');
        const ns = oppSpec(v, keep.kind || 'usage');
        ns.curHPPercent = keep.curHPPercent; ns.boosts = keep.boosts; ns.status = keep.status;
        state.opps[state.sel.opps] = ns;
        state.oppTeam[state.sel.opps] = v;
        calcAll();
      },
    });
    nameHTML = ddHTML('species:opps');
  } else {
    nameHTML = `<span class="speciesname">${esc(ja('species', eff))}</span>`;
  }
  const hp = Math.max(0, Math.min(100, Math.round(spec.curHPPercent ?? 100)));
  return `<div class="pokeinfo">
    <div class="piconbox"><span class="spritewrap" data-forme="${side}" title="フォルム選択">${spriteImg(eff, sd?.baseSpecies || spec.species, '')}${ui.formePop === side ? formePopHTML(side) : ''}</span></div>
    <div class="infomain">
      <div class="firstline">${nameHTML}<span class="level">L50</span><span class="typesfield">${typeChips(spec)}</span></div>
      <div class="secondline">
        <div class="hpbar"><i style="width:${hp}%"></i></div>
        <span class="hpct"><input data-hpnum="${side}" type="number" min="0" max="100" value="${hp}">%</span>
        <button class="statusbtn" data-statusbtn="${side}">${statusBadgeHTML(spec)}</button>
      </div>
    </div>
    ${presetBox(side)}
  </div>`;
}
function metaRow(side) {
  const spec = DS(side);
  const corr = f => side === 'opps' && (spec.corrected || []).includes(f);
  const abs = abilitiesOf(spec);
  if (spec.ability && !abs.includes(spec.ability)) abs.push(spec.ability);
  if (spec.mega && spec.megaAbility && !abs.includes(spec.megaAbility)) abs.push(spec.megaAbility);
  regDD(`ability:${side}`, {
    options: abs.map(a => ({ v: a, l: ja('abilities', a) })),
    value: (spec.mega && spec.megaAbility) ? spec.megaAbility : spec.ability, highlight: corr('特性'),
    onPick: v => { if (spec.mega && spec.megaAbility) spec.megaAbility = v; else spec.ability = v; if (side === 'opps') markCorrected(spec, '特性'); calcAll(); },
  });
  regDD(`nature:${side}`, {
    options: NATURES.map(n => ({ v: n, l: NAT_JA[n] || n })),
    value: spec.nature, highlight: corr('性格'),
    onPick: v => { spec.nature = v; if (side === 'opps') { markCorrected(spec, '性格'); (spec.estManual ||= {}).nature = true; } calcAll(); },
  });
  regDD(`item:${side}`, {
    options: ITEM_OPTIONS, value: spec.itemLost ? '' : (spec.item || ''), clearable: true, placeholder: 'なし',
    valueLabel: !spec.itemLost && spec.item ? ((NAMES._itemEn2ja || {})[idOf(spec.item)] || spec.item) : '',
    highlight: corr('持ち物'),
    onPick: v => { spec.item = v || ''; spec.itemLost = false; if (side === 'opps') markCorrected(spec, '持ち物'); calcAll(); },
  });
  return `<div class="metarow">
    <div class="col"><div class="ddlabel">特性</div>${ddHTML(`ability:${side}`)}</div>
    <div class="col"><div class="ddlabel">性格</div>${ddHTML(`nature:${side}`)}</div>
    <div class="col"><div class="ddlabel">持ち物</div>${ddHTML(`item:${side}`)}</div>
  </div>`;
}
function oppInfoLine() {
  const spec = DS('opps');
  const rates = spec.usageRates || spec.rates;
  if (spec.kind !== 'usage' || !rates) return '';
  const corr = spec.corrected || [];
  const parts = [];
  if (rates.ability && !corr.includes('特性')) parts.push(`特性 ${ja('abilities', spec.ability)} ${rates.ability}%`);
  else if (rates.ability) parts.push(`特性 ${ja('abilities', spec.ability)}`);
  if (rates.item && !corr.includes('持ち物')) parts.push(`持ち物 ${spec.item ? ((NAMES._itemEn2ja || {})[idOf(spec.item)] || spec.item) : 'なし'} ${rates.item}%`);
  else if (rates.item) parts.push(`持ち物 ${spec.item ? ((NAMES._itemEn2ja || {})[idOf(spec.item)] || spec.item) : 'なし'}`);
  if (rates.patternLabel && !corr.includes('EV')) parts.push(`EV型 ${rates.patternLabel} ${rates.pattern || ''}%`);
  const head = `pokedb 使用率トップ型${USAGE_SEASON ? `（${USAGE_SEASON}）` : ''}: `;
  const corrLine = corr.length ? `<br><span class="corrected">判明情報で訂正済み: ${corr.join('・')}</span>` : '';
  return `<div class="oppinfo">${head}${parts.join(' / ')}${corrLine}</div>`;
}
function megaFormeOf(speciesEn) {
  for (const suf of ['-Mega', '-Mega-X', '-Mega-Y', '-Mega-Z']) {
    const c = gen.species.get(idOf(speciesEn + suf));
    if (c) return c.name;
  }
  return null;
}
// その技が現在のフィールドで範囲技になるか (ワイドフォースはサイコフィールド+接地時のみ)
function spreadCapable(side, moveName) {
  if (!moveName) return false;
  const md = moveData(moveName);
  if (!md || md.category === 'Status') return false;
  if (md.name === 'Expanding Force') {
    if (state.field.terrain !== 'Psychic') return false;
    const spec = DS(side);
    const sd = gen.species.get(idOf(effSpecies(spec)));
    if (!sd) return false;
    if ((sd.types || []).includes('Flying')) return false;
    const ab = (spec.mega && spec.megaAbility) ? spec.megaAbility : spec.ability;
    if (ab === 'Levitate' || (spec.itemLost ? '' : spec.item) === 'Air Balloon') return false;
    return true;
  }
  return md.target === 'allAdjacentFoes' || md.target === 'allAdjacent';
}
// 単体/全体の現在モード: 手動選択があればそれ、なければ相手の場の残数で決める
function spreadMode(side, moveName) {
  const sel = ui.spreadSel[side][moveName];
  if (sel) return sel;
  const foeSide = side === 'mine' ? 'opps' : 'mine';
  const alive = (state.active[foeSide] || []).filter(i => (state[foeSide][i]?.curHPPercent ?? 100) > 0).length;
  return alive >= 2 ? 'spread' : 'single';
}
function movesBox(side, res) {
  const spec = DS(side);
  const canMega = spec.megaSpecies || megaFormeOf(spec.species);
  const megaSuffix = spec.mega && spec.megaSpecies ? (spec.megaSpecies.match(/-(X|Y|Z)$/)?.[1] || '') : '';
  const head = `<div class="mvhead">技${canMega ? ` <button class="tgl${spec.mega ? ' on' : ''}" data-mega="${side}">メガ${megaSuffix}</button>` : ''}</div>
    <div class="mvhead mid">ダメージ <button class="tgl${ui.crit[side] ? ' on' : ''}" data-crit="${side}">CRIT</button></div>
    <div class="mvhead mid">KO %</div>`;
  const rows = [0, 1, 2, 3].map(mi => {
    regDD(`move:${side}:${mi}`, {
      options: MOVE_OPTIONS, value: spec.moves[mi] || '', clearable: true, placeholder: '（技なし）',
      extra: (() => {
        const mv0 = spec.moves[mi];
        if (!spreadCapable(side, mv0)) return '';
        const mode = spreadMode(side, mv0);
        return `<span class="spreadtgl"><button data-spread="${side}:${mi}:single" class="${mode === 'single' ? 'on' : ''}">単体</button><button data-spread="${side}:${mi}:spread" class="${mode === 'spread' ? 'on' : ''}">全体</button></span>`;
      })(),
      highlight: side === 'opps' && !!spec.moves[mi] && (spec.knownMoves || []).includes(spec.moves[mi]),
      onPick: v => { const old = spec.moves[mi]; spec.moves[mi] = v || ''; if (side === 'opps') { markCorrected(spec, '技'); if (!Array.isArray(spec.knownMoves)) spec.knownMoves = []; if (v && !spec.knownMoves.includes(v)) spec.knownMoves.push(v); if (old && old !== v && !spec.moves.includes(old)) spec.knownMoves = spec.knownMoves.filter(m => m !== old); } calcAll(); },
    });
    const mr = res && res.moveResults ? res.moveResults[mi] : null;
    const r = mr && mr.vs ? mr.vs[0] : null;
    let dmg = '—', cls = '', ko = '', koStyle = '';
    if (r) {
      if (r.status) { dmg = 'N/A'; }
      else if (r.immune) { dmg = 'IMMUNE'; cls = 'immune'; }
      else if (r.error) { dmg = '—'; }
      else {
        dmg = `${fmtPct(r.minPct)} – ${fmtPct(r.maxPct)}%`;
        const kf = koFmt(r.ko);
        if (kf) { ko = kf[0]; const c = { g: '#4CAF50', o: '#FF9800', r: '#F44336' }[kf[1]]; if (c) koStyle = ` style="color:${c}"`; }
      }
    }
    const foe = DS(side === 'mine' ? 'opps' : 'mine');
    const mvName = spec.moves[mi];
    const copyText = (r && !r.status && !r.immune && mvName) ? `${ja('species', effSpecies(spec))} ${ja('moves', mvName)} vs ${ja('species', effSpecies(foe))}: ${dmg} ${ko}` : '';
    // ベイズ候補 (事後90%) を通じたダメージ幅。MAP 型の通常範囲より広い時だけ出す
    let sub = '';
    const cr = lastCalc && lastCalc.candRanges ? lastCalc.candRanges[side][mi] : null;
    if (r && cr && !r.status && !r.immune && !r.error && (cr.lo < r.minPct - 0.05 || cr.hi > r.maxPct + 0.05)) {
      sub = `<span class="candsub" title="相手の型候補（事後確率 ${Math.round((lastCalc.candRanges.acc || 0) * 100)}% 分）を通じたダメージ範囲">候補 ${fmtPct(cr.lo)}–${fmtPct(cr.hi)}%</span>`;
    }
    return `${ddHTML(`move:${side}:${mi}`)}
      <button class="dmgbtn ${cls}" ${copyText ? `data-copy="${esc(copyText)}"` : ''}>${dmg}${sub}</button>
      <span class="ko"${koStyle}>${ko}</span>`;
  }).join('');
  return `<div class="movesbox"><div class="movesgrid">${head}${rows}</div></div>`;
}
function statsGrid(side, statArr) {
  const spec = DS(side);
  const heads = STATJ.map(([k, en]) => {
    const m = natureMark(spec, k);
    return `<div class="sghead ${m || ''}">${m === 'up' ? '+' : m === 'down' ? '-' : ''}${en}</div>`;
  }).join('');
  const total = STATJ.reduce((s, [k]) => s + (spec.sp[k] || 0), 0);
  const over = total > 66;
  const delta = total < 66 ? `<span class="delta">${66 - total}↓</span>` : over ? `<span class="delta over">${total - 66}↑</span>` : '';
  const evRow = STATJ.map(([k]) => {
    const est = side === 'opps' ? spec.estSp?.[k] : null;
    if (est) {
      const txt = est[0] === est[1] ? String(est[0]) : `${est[0]}-${est[1]}`;
      return `<div class="evwrap"><input data-evest="${side}:${k}" class="estval estin" type="text" inputmode="numeric" style="${rangeFont(txt, 1, 3.6)}" title="推定 ${txt}（数値を入力して上書きできます）${spec.estMapProb != null ? `・最有力候補の確率 ${Math.round(spec.estMapProb * 100)}%` : ''}" value="${txt}"></div>`;
    }
    return `<div class="evwrap"><span class="evfield"><input data-ev="${side}:${k}" type="number" min="0" max="32" value="${spec.sp[k] || 0}" class="${(spec.sp[k] || 0) > 0 ? 'has' : ''}"></span></div>`;
  }).join('');
  const finals = STATJ.map(([k]) => {
    if (!statArr) return '<div class="finalstat">—</div>';
    const est = side === 'opps' ? spec.estStat?.[k] : null;
    if (est) {
      const txt = est[0] === est[1] ? String(est[0]) : `${est[1]}*`;
      return `<input data-statest="${side}:${k}" class="finalstat estval estin" type="text" inputmode="numeric" style="${rangeFont(txt, 1.1, 3.3)}" title="推定 ${est[0]}-${est[1]}（数値を入力すると努力値を逆算して上書きします）${spec.estMapProb != null ? `・最有力候補の確率 ${Math.round(spec.estMapProb * 100)}%` : ''}" value="${txt}">`;
    }
    const [v, cn] = dispStat(spec, k, statArr, side === 'mine' ? 'mine' : 'opp');
    return `<div class="finalstat ${cn === 'green' ? 'pos' : cn === 'red' ? 'neg' : ''}">${v}</div>`;
  }).join('');
  const boosts = STATJ.map(([k]) => {
    if (k === 'hp') return '<div></div>';
    const b = spec.boosts[k] || 0;
    return `<div class="boostcell"><button class="bstbtn" data-boost="${side}:${k}:-1">−</button><span class="bstval ${b > 0 ? 'pos' : b < 0 ? 'neg' : ''}">${b > 0 ? '+' + b : b}</span><button class="bstbtn" data-boost="${side}:${k}:1">+</button></div>`;
  }).join('');
  return `<div class="statswrap"><div class="statsgrid">
    <div></div>${heads}
    <div class="sglabel ${over ? 'warn' : ''}">努力値${delta}</div>${evRow}
    <div></div>${finals}
    <div class="sglabel">ランク</div>${boosts}
  </div></div>`;
}
function formePopHTML(side) {
  const spec = DS(side);
  const eff = effSpecies(spec);
  const formes = formesOf(spec.species);
  if (formes.length < 2) return '';
  const base = formes[0];
  const opts = formes.map(f => {
    const label = f === base ? 'BASE' : f.replace(base + '-', '').toUpperCase();
    return `<button class="formeopt ${f === eff ? 'sel' : ''}" data-formepick="${side}:${f}">${spriteImg(f, base, '')}<span>${esc(label)}</span></button>`;
  }).join('');
  return `<span class="formepop">${opts}</span>`;
}
function renderPanel(side) {
  if (!DS(side)) {
    return `<div class="playercalc">${playerBar(side)}<div class="oppinfo" style="margin-top:1.2rem">相手のチームはリセットされました。対戦が始まると自動で読み取ります。</div></div>`;
  }
  const res = !lastCalc ? null : side === 'mine' ? lastCalc.results[0] : lastCalc.oppResults[0];
  const statArr = !lastCalc ? null : side === 'mine' ? lastCalc.stats.mine[0] : lastCalc.stats.opps[0];
  return `<div class="playercalc">
    ${playerBar(side)}
    ${pokeInfo(side)}
    ${metaRow(side)}
    ${side === 'opps' ? oppInfoLine() : ''}
    <div class="tables">${movesBox(side, res)}${statsGrid(side, statArr)}</div>
  </div>`;
}

/* ---------- field ---------- */
function sideChips(which) {
  const s = state.side[which];
  const defs = [['light', 'ひかりのかべ'], ['reflect', 'リフレクター'], ['veil', 'オーロラベール'], ['tailwind', 'おいかぜ'], ['hand', 'てだすけ'], ['guard', 'フレンドガード']];
  return defs.map(([k, label]) => `<button class="tgl primary${s[k] ? ' on' : ''}" data-sidechip="${which}:${k}">${label}</button>`).join('');
}
function renderField() {
  regDD('weather', {
    options: [{ v: '', l: 'なし' }, { v: 'Sun', l: 'はれ' }, { v: 'Rain', l: 'あめ' }, { v: 'Sand', l: 'すなあらし' }, { v: 'Snow', l: 'ゆき' }, { v: 'Harsh Sunshine', l: 'つよいひざし' }, { v: 'Heavy Rain', l: 'つよいあめ' }, { v: 'Strong Winds', l: 'らんきりゅう' }],
    value: state.field.weather || '',
    onPick: v => { state.field.weather = v; calcAll(); },
  });
  regDD('terrain', {
    options: [{ v: '', l: 'なし' }, { v: 'Electric', l: 'エレキフィールド' }, { v: 'Grassy', l: 'グラスフィールド' }, { v: 'Psychic', l: 'サイコフィールド' }, { v: 'Misty', l: 'ミストフィールド' }],
    value: state.field.terrain || '',
    onPick: v => { state.field.terrain = v; calcAll(); },
  });
  return `
    <div class="frow"><div class="flabel">天候</div><div class="fcontrol">${ddHTML('weather')}</div></div>
    <div class="frow"><div class="flabel">フィールド</div><div class="fcontrol">${ddHTML('terrain')}</div></div>
    <div class="frow"><div class="flabel">↑ 自分の場</div><div class="fchips">${sideChips('mine')}</div></div>
    <div class="frow"><div class="flabel">↓ 相手の場</div><div class="fchips">${sideChips('opp')}</div></div>`;
}

/* ---------- calc ---------- */
function renderAll() {
  if (document.activeElement && document.activeElement !== document.body && document.activeElement.blur) {
    try { document.activeElement.blur(); } catch (e) { /* noop */ }
  }
  openDDId = null;
  closeStPop();
  document.getElementById('playerMine').innerHTML = renderPanel('mine');
  document.getElementById('fieldbar').innerHTML = renderField();
  document.getElementById('playerOpp').innerHTML = renderPanel('opps');
}
// 第2段: 選択中マッチアップについて、相手の事後上位候補 (累積90%) を通じた
// ダメージの最小〜最大を出す。MAP 型だけの通常表示に対する「型が違った場合の幅」
function computeCandRanges() {
  const out = { mine: [null, null, null, null], opps: [null, null, null, null], acc: 0 };
  const opp = DS('opps'), mine = DS('mine');
  if (!opp || !mine) return out;
  const cov = bayesCover(opp.species);
  if (!cov) return out;
  out.acc = cov.acc;
  const F = { weather: state.field.weather, terrain: state.field.terrain };
  const sideFor = (atkKey, defKey) => ({
    atkSide: { isHelpingHand: !!state.side[atkKey === 'mine' ? 'mine' : 'opp'].hand },
    defSide: { isLightScreen: !!state.side[defKey === 'mine' ? 'mine' : 'opp'].light, isReflect: !!state.side[defKey === 'mine' ? 'mine' : 'opp'].reflect, isAuroraVeil: !!state.side[defKey === 'mine' ? 'mine' : 'opp'].veil, isFriendGuard: !!state.side[defKey === 'mine' ? 'mine' : 'opp'].guard },
  });
  const run = (atkSpec, defSpec, defHp, moves, crit, atkKey, defKey, singleFn, dst) => {
    const sc = sideFor(atkKey, defKey);
    (moves || []).forEach((mv, mi) => {
      if (!mv || !defHp) return;
      const { rolls } = damageRolls(withCurHP(atkSpec), withCurHP(defSpec), mv,
        { ...F, gameType: singleFn(mv) ? 'Singles' : 'Doubles', crit: !!crit, atkSide: sc.atkSide, defSide: sc.defSide });
      if (!rolls || !rolls.length) return;
      const lo = Math.min(...rolls) / defHp * 100, hi = Math.max(...rolls) / defHp * 100;
      const cur = dst[mi];
      dst[mi] = cur ? { lo: Math.min(cur.lo, lo), hi: Math.max(cur.hi, hi) } : { lo, hi };
    });
  };
  for (const c of cov.cover) {
    const candSpec = bayesCandSpec(opp, c);
    // 自分の技 → 相手候補 (防御側が変動)
    run(mine, candSpec, c.values.hp, mine.moves, ui.crit.mine, 'mine', 'opps',
      mv => spreadCapable('mine', mv) && spreadMode('mine', mv) === 'single', out.mine);
    // 相手候補の技 → 自分 (攻撃側が変動)
    const myTable = statTable(effSpecies(mine));
    const myHp = myTable ? (myTable.hp.find(r => r.sp === (mine.sp.hp || 0)) || {}).value : null;
    run(candSpec, mine, myHp, opp.moves, ui.crit.opps, 'opps', 'mine',
      mv => spreadCapable('opps', mv) && spreadMode('opps', mv) === 'single', out.opps);
  }
  return out;
}
function calcAll() {
  ui.formePop = null;
  if (!DS('mine') || !DS('opps')) { lastCalc = null; renderAll(); return; }
  const atkSide = { isHelpingHand: !!state.side.mine.hand };
  const defSide = { isLightScreen: !!state.side.opp.light, isReflect: !!state.side.opp.reflect, isAuroraVeil: !!state.side.opp.veil, isFriendGuard: !!state.side.opp.guard };
  const oppAtkSide = { isHelpingHand: !!state.side.opp.hand };
  const oppDefSide = { isLightScreen: !!state.side.mine.light, isReflect: !!state.side.mine.reflect, isAuroraVeil: !!state.side.mine.veil, isFriendGuard: !!state.side.mine.guard };
  const singleMoves = { mine: [], opps: [] };
  for (const sd of ['mine', 'opps']) {
    for (const mv of DS(sd).moves || []) {
      if (mv && spreadCapable(sd, mv) && spreadMode(sd, mv) === 'single') singleMoves[sd].push(mv);
    }
  }
  lastCalc = calcMatchup({
    mine: [DS('mine')], opps: [DS('opps')],
    field: { weather: state.field.weather, terrain: state.field.terrain, attackerSide: atkSide, defenderSide: defSide, oppAttackerSide: oppAtkSide, oppDefenderSide: oppDefSide, tailwindMine: !!state.side.mine.tailwind, tailwindOpp: !!state.side.opp.tailwind },
    crit: { mine: [ui.crit.mine], opps: [ui.crit.opps] },
    singleMoves,
  });
  lastCalc.candRanges = computeCandRanges();
  renderAll();
}

/* ---------- import (adapted to displayed spec) ---------- */
function applyImport(side, parsed) {
  if (!parsed.species) return;
  const idx = state.sel[side];
  const keep = state[side][idx];
  const megaSpecies = megaFromItem(parsed.item) || parsed.megaSpecies || null;
  const megaAbility = megaSpecies ? (gen.species.get(megaSpecies)?.abilities?.[0] || null) : null;
  state[side][idx] = {
    species: parsed.species, kind: 'custom',
    sp: { ...parsed.sp }, nature: parsed.nature || keep.nature,
    ability: parsed.ability || keep.ability, item: parsed.item || '',
    moves: parsed.moves.slice(0, 4), origMoves: parsed.moves.slice(0, 4),
    curHPPercent: keep.curHPPercent, boosts: keep.boosts, status: keep.status,
    megaSpecies, megaAbility, mega: !!megaSpecies && keep.mega,
    knownMoves: side === 'opps' ? parsed.moves.slice(0, 4) : [],
    note: 'Imported set', corrected: ['読み込み'],
  };
  if (side === 'opps') state.oppTeam[idx] = parsed.species;
}
function megaFromItem(itemEn) {
  if (!itemEn) return null;
  const it = gen.items.get(itemEn);
  if (it && it.megaStone) return Object.values(it.megaStone)[0];
  return null;
}

/* ---------- events ---------- */
document.addEventListener('mousedown', e => {
  const spb = e.target.closest('[data-spread]');
  if (spb) {
    e.preventDefault(); e.stopPropagation();
    ui.spreadGuard = Date.now();
    const [sd, mi, mode] = spb.dataset.spread.split(':');
    const spec = DS(sd);
    const mv = spec && spec.moves[+mi];
    if (mv) ui.spreadSel[sd][mv] = mode;
    calcAll();
    return;
  }
  const clear = e.target.closest('[data-ddclear]');
  if (clear) { e.preventDefault(); e.stopPropagation(); pickDD(clear.dataset.ddclear, ''); return; }
  const opt = e.target.closest('[data-ddopt]');
  if (opt) { e.preventDefault(); const host = opt.closest('[data-sdd]'); if (host) pickDD(host.dataset.sdd, opt.dataset.ddopt); return; }
  const ctl = e.target.closest('[data-ddctl]');
  if (ctl) {
    const id = ctl.dataset.ddctl;
    if (openDDId === id) { /* already open: keep open (input focus) */ const inp = ctl.querySelector('.sdd-input'); if (inp && e.target !== inp) { e.preventDefault(); inp.focus(); } }
    else openDD(id);
    return;
  }
  if (!e.target.closest('.sdd')) closeDD();
  if (!e.target.closest('.stpop') && !e.target.closest('[data-statusbtn]')) closeStPop();
  if (ui.formePop && !e.target.closest('[data-forme]') && !e.target.closest('.formepop')) { ui.formePop = null; renderAll(); }
});
document.addEventListener('click', e => {
  const t = e.target;
  const icon = t.closest('[data-icon]');
  if (icon) { const [side, i] = icon.dataset.icon.split(':'); state.sel[side] = +i; calcAll(); return; }
  const cap = t.closest('[data-capture]');
  if (cap) { captureTeam(cap.dataset.capture); return; }
  const act = t.closest('[data-act]');
  if (act) {
    const [side, what] = act.dataset.act.split(':');
    if (what === 'import') { ui.importing[side] = ui.importing[side] ? false : true; renderAll(); const ta = document.querySelector(`[data-importbox="${side}"]`); if (ta) ta.focus(); }
    if (what === 'export') {
      if (navigator.clipboard) navigator.clipboard.writeText(exportText(DS(side))).catch(() => {});
      const old = act.textContent;
      act.textContent = 'コピー済み';
      setTimeout(() => { act.textContent = old; }, 1600);
    }
    if (what === 'all') {
      const team = side === 'mine' ? state.mine : state.opps;
      if (navigator.clipboard) navigator.clipboard.writeText(team.map(exportText).join('\n\n')).catch(() => {});
      const old = act.textContent;
      act.textContent = 'コピー済み';
      setTimeout(() => { act.textContent = old; }, 1600);
    }
    return;
  }
  const ai = t.closest('[data-applyimport]');
  if (ai) {
    const side = ai.dataset.applyimport;
    const ta = document.querySelector(`[data-importbox="${side}"]`);
    const parsed = parseSet(ta ? ta.value : '');
    ui.importing[side] = false;
    applyImport(side, parsed);
    calcAll();
    return;
  }
  const fp = t.closest('[data-formepick]');
  if (fp) {
    const [side, forme] = fp.dataset.formepick.split(':');
    const spec = DS(side);
    const base = gen.species.get(idOf(spec.species))?.baseSpecies || spec.species;
    if (forme === base) {
      spec.mega = false;
      if (spec.species !== base) {
        // フォルム違い (イルカマン等) は種族自体をベースに戻す
        spec.species = base;
        spec.megaSpecies = undefined;
        const list = abilitiesOf(spec);
        if (list.length && !list.includes(spec.ability)) spec.ability = list[0];
      }
    }
    else if (forme.includes('-Mega')) {
      spec.megaSpecies = forme;
      spec.mega = true;
      const sd = gen.species.get(idOf(forme));
      if (sd) spec.megaAbility = Object.values(sd.abilities)[0];
      const stone = stoneForForme(forme);
      if (stone) spec.item = stone;
    } else {
      spec.species = forme;
      spec.mega = false;
      spec.megaSpecies = undefined;
      const list = abilitiesOf(spec);
      if (list.length && !list.includes(spec.ability)) spec.ability = list[0];
    }
    ui.formePop = null;
    calcAll();
    return;
  }
  const fo = t.closest('[data-forme]');
  if (fo) { const side = fo.dataset.forme; ui.formePop = ui.formePop === side ? null : side; renderAll(); return; }
  const mg = t.closest('[data-mega]');
  if (mg) {
    const spec = DS(mg.dataset.mega);
    const formes = megaFormesOf(spec.species);
    if (formes.length) {
      if (!spec.mega) { spec.mega = true; spec.megaSpecies = formes[0]; }
      else {
        const i = formes.indexOf(spec.megaSpecies);
        if (i >= 0 && i < formes.length - 1) spec.megaSpecies = formes[i + 1];
        else spec.mega = false;
      }
      if (spec.mega) {
        const sd = gen.species.get(idOf(spec.megaSpecies));
        if (sd) spec.megaAbility = Object.values(sd.abilities)[0];
        const stone = stoneForForme(spec.megaSpecies);
        if (stone) spec.item = stone;
      }
    }
    calcAll();
    return;
  }
  const cr = t.closest('[data-crit]');
  if (cr) { const side = cr.dataset.crit; ui.crit[side] = !ui.crit[side]; calcAll(); return; }
  const spb = t.closest('[data-spread]');
  if (spb) {
    if (Date.now() - (ui.spreadGuard || 0) < 1000) return;
    const [sd, mi, mode] = spb.dataset.spread.split(':');
    const spec = DS(sd);
    const mv = spec && spec.moves[+mi];
    if (mv) ui.spreadSel[sd][mv] = mode;
    calcAll();
    return;
  }
  const bs = t.closest('[data-boost]');
  if (bs) {
    const [side, k, d] = bs.dataset.boost.split(':');
    const spec = DS(side);
    spec.boosts[k] = Math.max(-6, Math.min(6, (spec.boosts[k] || 0) + (+d)));
    calcAll();
    return;
  }
  const chip = t.closest('[data-sidechip]');
  if (chip) {
    const [which, k] = chip.dataset.sidechip.split(':');
    state.side[which][k] = !state.side[which][k];
    calcAll();
    return;
  }
  const sb = t.closest('[data-statusbtn]');
  if (sb) { openStPop(sb.dataset.statusbtn, sb); return; }
  const sp = t.closest('[data-statuspick]');
  if (sp) {
    const [side, v] = sp.dataset.statuspick.split(':');
    DS(side).status = v;
    closeStPop();
    calcAll();
    return;
  }
  const cp = t.closest('[data-copy]');
  if (cp) {
    if (navigator.clipboard) navigator.clipboard.writeText(cp.dataset.copy);
    cp.classList.add('copied');
    setTimeout(() => cp.classList.remove('copied'), 700);
    return;
  }
});
document.addEventListener('change', e => {
  const t = e.target;
  if (t.matches('[data-hpnum]')) {
    const spec = DS(t.dataset.hpnum);
    spec.curHPPercent = Math.max(0, Math.min(100, Math.round(+t.value || 0)));
    if (spec.curHPPercent > 0) faintLock[t.dataset.hpnum].delete(spec.species);
    calcAll();
    return;
  }
  if (t.matches('[data-ev]')) {
    const [side, k] = t.dataset.ev.split(':');
    const prevSide = state.sel[side];
    setEv(side, k, t.value, false);
    return;
  }
  if (t.matches('[data-evest]')) {
    const [side, k] = t.dataset.evest.split(':');
    commitEstEv(side, k, t.value);
    return;
  }
  if (t.matches('[data-statest]')) {
    const [side, k] = t.dataset.statest.split(':');
    commitEstStat(side, k, t.value);
    return;
  }
});
document.addEventListener('keydown', e => {
  const t = e.target;
  if (t.matches && t.matches('[data-ev]') && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
    e.preventDefault();
    const [side, k] = t.dataset.ev.split(':');
    const spec = DS(side);
    const step = (e.shiftKey ? 4 : 1) * (e.key === 'ArrowUp' ? 1 : -1);
    setEv(side, k, (spec.sp[k] || 0) + step, true);
  }
  if (t.matches && t.matches('[data-hpnum]') && e.key === 'Enter') t.blur();
  if (t.matches && t.matches('[data-evest]') && e.key === 'Enter') { const [side, k] = t.dataset.evest.split(':'); commitEstEv(side, k, t.value); }
  if (t.matches && t.matches('[data-statest]') && e.key === 'Enter') { const [side, k] = t.dataset.statest.split(':'); commitEstStat(side, k, t.value); }
});
document.addEventListener('focusin', e => {
  if (e.target.matches && (e.target.matches('[data-ev]') || e.target.matches('[data-evest]') || e.target.matches('[data-statest]'))) e.target.select();
});
$('applyjson').addEventListener('click', () => {
  try { applyState(JSON.parse($('jsonin').value)); } catch (err) { /* ignore */ }
});

/* ---------- state.json 連携 ---------- */
const lastActiveKey = { mine: '', opps: '' };
function applyRevealedPreserving(spec, rev) {
  let fresh = oppSpec(spec.species, 'usage');
  // フォルム違い (イルカマン(ヒーロー)等) には使用率データが無いため、
  // ベース種族の使用率型を流用し種族だけ差し替える (想定型が毎回変わらないように)
  if (!usageSpec(spec.species, USAGE_SETS)) {
    const base = gen.species.get(idOf(spec.species))?.baseSpecies;
    if (base && base !== spec.species && usageSpec(base, USAGE_SETS)) {
      fresh = oppSpec(base, 'usage');
      fresh.species = spec.species;
    }
  }
  applyRevealed(fresh, rev);
  for (const f of spec.corrected || []) {
    if (f === '特性') fresh.ability = spec.ability;
    if (f === '性格') fresh.nature = spec.nature;
    if (f === '持ち物') { fresh.item = spec.item; fresh.megaSpecies = spec.megaSpecies; fresh.megaAbility = spec.megaAbility; fresh.mega = spec.mega; }
    if (f === '技') fresh.moves = [...spec.moves];
    if (f === 'EV') fresh.sp = { ...spec.sp };
    if (!fresh.corrected.includes(f)) fresh.corrected.push(f);
  }
  // 手動で切り替えたメガシンカ状態は再構築で消さない
  if (spec.mega && !fresh.mega) { fresh.mega = true; fresh.megaSpecies = spec.megaSpecies; fresh.megaAbility = spec.megaAbility; }
  if (!fresh.megaSpecies && spec.megaSpecies) fresh.megaSpecies = spec.megaSpecies;
  fresh.knownMoves = [...new Set([...(fresh.knownMoves || []), ...(spec.knownMoves || [])])];
  fresh.curHPPercent = spec.curHPPercent; fresh.boosts = spec.boosts; fresh.status = spec.status;
  if (spec.estManual) fresh.estManual = { ...spec.estManual };
  if (spec.itemLost) fresh.itemLost = true;
  if (spec.unburden) fresh.unburden = true;
  return fresh;
}
// リーダーがメガシンカを検出したら、その枠をメガ種族として計算する
function applyMegaFlag(spec, en) {
  if (!en.mega || spec.mega) return;
  spec.mega = true;
  if (en.megaSpecies) spec.megaSpecies = en.megaSpecies;
  if (!spec.megaSpecies) spec.megaSpecies = megaFormeOf(spec.species);
  if (spec.megaSpecies) {
    const msd = gen.species.get(idOf(spec.megaSpecies));
    if (msd) spec.megaAbility = Array.isArray(msd.abilities) ? msd.abilities[0] : Object.values(msd.abilities || {})[0];
  }
}
/* ---------- 相手の型推定エンジン ---------- */
// reader が state.json に流すイベント (技の使用順と、ダメージ+その時の状況) を
// 自チームの正確な数値と照らし合わせ、相手の実数値・努力値・性格の範囲を絞り込む。
// モデル化できない要素 (未判明の持ち物・特性など) を含むイベントは、候補が
// 空になった時点で矛盾として捨てるため、推定が壊れることはない。
const INF_BLACKLIST = new Set(['Foul Play', 'Gyro Ball', 'Electro Ball', 'Endeavor', 'Final Gambit', 'Seismic Toss', 'Night Shade', 'Dragon Rage', 'Sonic Boom', 'Super Fang', "Nature's Madness", 'Fissure', 'Horn Drill', 'Guillotine', 'Sheer Cold', 'Counter', 'Mirror Coat', 'Metal Burst', 'Comeuppance', 'Pain Split']);
let inference, infCtx, infLastMove, infDirty;
let autoSideTurn;
let bayes = null, lastSpeCtx = null;
function resetInference() {
  inference = { seen: 0, bySpecies: {} };
  infCtx = { tailwindTurn: { p1: -99, p2: -99 }, screenTurn: { p1: {}, p2: {} }, trickRoomTurn: -99, hhTurn: { p1: -99, p2: -99 }, abBatches: {}, abPairs: new Set() };
  infLastMove = null;
  infDirty = false;
  bayesReset();
  lastSpeCtx = null;
  // 対戦イベントから自動反映したサイドコンディション (おいかぜ・壁・てだすけ) の
  // セットされたターン。新しい対戦では場の状態ごとリセットする
  autoSideTurn = { mine: { tailwind: -99, light: -99, reflect: -99, veil: -99, hand: -99 }, opp: { tailwind: -99, light: -99, reflect: -99, veil: -99, hand: -99 } };
  state.side = { mine: { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false }, opp: { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false } };
}
// 技の使用イベントからサイドコンディションをチップ状態へ反映する
function setAutoSide(sideP, key, turn) {
  const sk = sideP === 'p1' ? 'mine' : 'opp';
  if (!state.side[sk][key]) { state.side[sk][key] = true; infDirty = true; }
  autoSideTurn[sk][key] = turn;
}
// 効果ターンが切れた自動コンディションを落とす (おいかぜ4ターン / 壁5ターン / てだすけ当ターンのみ)。
// 手動で付けたチップは autoSideTurn が -99 のままなので、ここでは落ちない
function expireAutoSide(turn) {
  const dur = { tailwind: 4, light: 5, reflect: 5, veil: 5, hand: 1 };
  for (const sk of ['mine', 'opp']) for (const k of Object.keys(dur)) {
    const s = autoSideTurn[sk][k];
    if (s >= 0 && turn - s >= dur[k]) {
      autoSideTurn[sk][k] = -99;
      if (state.side[sk][k]) { state.side[sk][k] = false; infDirty = true; }
    }
  }
}
resetInference();
function infEntry(species) {
  if (!inference.bySpecies[species]) inference.bySpecies[species] = { pairs: { atk: null, spa: null, def: null, spd: null, spe: null }, hpSps: null, used: 0, dropped: 0 };
  return inference.bySpecies[species];
}
const labelSide = label => (label.startsWith('p1') ? 'p1' : 'p2');
const labelSpecies = label => { const i = label.indexOf(':'); return i >= 0 ? label.slice(i + 1).trim() : ''; };
// 推定レンジ表示のはみ出し防止: 基準フォントで budget 文字分まで、超えたら比例縮小
function rangeFont(txt, base, budget) {
  const l = String(txt).length;
  return l <= budget ? '' : `font-size:${(base * budget / l).toFixed(2)}rem;`;
}
function infMySpec(species, ev, isAtk) {
  const spec = state.mine.find(x => x.species === species);
  if (!spec) return null;
  const mega = isAtk ? ev.atkMega : ev.defMega;
  return { ...spec, mega: !!mega || !!spec.mega, megaSpecies: mega || spec.megaSpecies,
    boosts: { ...(isAtk ? ev.atkB : ev.defB) }, status: (isAtk ? ev.atkS : ev.defS) || '',
    curHPPercent: isAtk ? ev.atkHp : ev.defHp };
}
function infOppBase(species, ev, isAtk) {
  const pi = state.oppTeam.indexOf(species);
  const spec = pi >= 0 ? state.opps[pi] : oppSpec(species, 'usage');
  if (!spec) return null;
  const mega = isAtk ? ev.atkMega : ev.defMega;
  return { ...spec, mega: !!mega, megaSpecies: mega || undefined,
    boosts: { ...(isAtk ? ev.atkB : ev.defB) }, status: (isAtk ? ev.atkS : ev.defS) || '',
    curHPPercent: isAtk ? ev.atkHp : ev.defHp, estSp: undefined, estStat: undefined, estNature: undefined };
}
// 推定に使う相手 spec の候補: 持ち物が未判明なら「持ち物なし」も併せて候補にする
// (こだわり系・いのちのたま・とつげきチョッキ等の未判明補正で推定が外れるのを防ぐ)
function infBases(species, ev, isAtk) {
  const base = infOppBase(species, ev, isAtk);
  if (!base) return [];
  const pi = state.oppTeam.indexOf(species);
  const panel = pi >= 0 ? state.opps[pi] : null;
  const itemKnown = !!panel && (panel.corrected || []).includes('持ち物');
  const out = [base];
  if (!itemKnown && base.item) out.push({ ...base, item: '' });
  return out;
}
function infSideConds(ev) {
  const t = ev.turn;
  const active = (setTurn, dur) => typeof setTurn === 'number' && t - setTurn >= 0 && t - setTurn < dur;
  const ds = infCtx.screenTurn[labelSide(ev.def)] || {};
  const atkSideKey = labelSide(ev.atk);
  const hh = infCtx.hhTurn[atkSideKey] === t;
  if (hh) infCtx.hhTurn[atkSideKey] = -99;
  return {
    atkSide: { isHelpingHand: hh },
    defSide: { isReflect: active(ds.reflect, 5), isLightScreen: active(ds.light, 5), isAuroraVeil: active(ds.veil, 5) },
  };
}
// 候補集合への交差適用 (空になるイベントは矛盾として捨てる)
function infIntersect(species, statKey, feasible, hpSps) {
  const e = infEntry(species);
  if (!feasible || !feasible.size) { e.dropped++; return; }
  const next = e.pairs[statKey] ? new Set([...e.pairs[statKey]].filter(x => feasible.has(x))) : feasible;
  if (!next.size) { e.dropped++; return; }
  let nh = null;
  if (hpSps) {
    nh = e.hpSps ? new Set([...e.hpSps].filter(x => hpSps.has(x))) : hpSps;
    if (!nh.size) { e.dropped++; return; }
  }
  e.pairs[statKey] = next;
  if (hpSps) e.hpSps = nh;
  e.used++;
  infDirty = true;
}
function infProcessDamage(ev) {
  const md = moveData(ev.move);
  if (!md || md.category === 'Status' || !md.basePower || md.multihit || md.fixedDamage || INF_BLACKLIST.has(md.name)) return;
  const atkSpecies = labelSpecies(ev.atk), defSpecies = labelSpecies(ev.def);
  const oppIsAtk = labelSide(ev.atk) === 'p2';
  let target = md.target;
  if (md.name === 'Expanding Force' && ev.t === 'Psychic') target = 'allAdjacentFoes';
  let targets = 1;
  if (target === 'allAdjacentFoes') targets = ev.defAlive || 1;
  else if (target === 'allAdjacent') targets = (ev.defAlive || 1) + Math.max(0, (ev.atkAlive || 1) - 1);
  const gameType = targets >= 2 ? 'Doubles' : 'Singles';
  const conds = infSideConds(ev);
  const opts = { weather: ev.w, terrain: ev.t, gameType, crit: ev.crit, atkSide: conds.atkSide, defSide: conds.defSide };
  ev._bayesOpts = opts; // ベイズ側も同じ場の条件で評価する (てだすけ消費などの副作用を共有するため)
  if (oppIsAtk) {
    // 相手の攻撃 -> 自分の正確な被ダメ量から相手の攻撃 (or Body Press は防御) を絞る
    if (typeof ev.amt !== 'number' || ev.amt <= 0) return;
    const statKey = md.name === 'Body Press' ? 'def' : (md.category === 'Physical' ? 'atk' : 'spa');
    const defSpec = infMySpec(defSpecies, ev, false);
    const bases = infBases(atkSpecies, ev, true);
    const table = statTable(atkSpecies);
    if (!defSpec || !bases.length || !table) return;
    const byValue = new Map();
    for (const row of table[statKey]) { if (!byValue.has(row.value)) byValue.set(row.value, []); byValue.get(row.value).push(row); }
    const feasible = new Set();
    for (const base of bases) {
      for (const rows of byValue.values()) {
        const rep = rows[0];
        const atkSpec = { ...base, nature: rep.nature, sp: { ...base.sp, [statKey]: rep.sp } };
        const { rolls } = damageRolls(withCurHP(atkSpec), withCurHP(defSpec), md.name, opts);
        if (rolls.includes(ev.amt)) for (const r of rows) feasible.add(r.nature + '|' + r.sp);
      }
    }
    infIntersect(atkSpecies, statKey, feasible, null);
  } else {
    // 自分の攻撃 -> 相手の HP% の減少から相手の HP と防御 (or 特防) を共同で絞る
    if (typeof ev.pct !== 'number' || ev.pct <= 0) return;
    const defKey = md.category === 'Physical' ? 'def' : 'spd';
    const atkSpec = infMySpec(atkSpecies, ev, true);
    const bases = infBases(defSpecies, ev, false);
    const table = statTable(defSpecies);
    if (!atkSpec || !bases.length || !table) return;
    const hpBySp = new Map();
    for (const row of table.hp) if (!hpBySp.has(row.sp)) hpBySp.set(row.sp, row.value);
    const byValue = new Map();
    for (const row of table[defKey]) { if (!byValue.has(row.value)) byValue.set(row.value, []); byValue.get(row.value).push(row); }
    const feasPairs = new Set(), feasHp = new Set();
    for (const base of bases) {
      for (const rows of byValue.values()) {
        const rep = rows[0];
        const defSpec = { ...base, nature: rep.nature, sp: { ...base.sp, [defKey]: rep.sp } };
        const { rolls } = damageRolls(withCurHP(atkSpec), withCurHP(defSpec), md.name, opts);
        if (!rolls.length) continue;
        for (const [spHp, hpVal] of hpBySp) {
          if (rolls.some(r => r > 0 && (Math.round(r / hpVal * 100) === ev.pct || Math.floor(r / hpVal * 100) === ev.pct))) {
            for (const r of rows) feasPairs.add(r.nature + '|' + r.sp);
            feasHp.add(spHp);
          }
        }
      }
    }
    infIntersect(defSpecies, defKey, feasPairs, feasHp);
  }
}
const WEATHER_SPE = { Chlorophyll: 'Sun', 'Swift Swim': 'Rain', 'Sand Rush': 'Sand', 'Slush Rush': 'Snow' };
function infEffSpe(statVal, boosts, item, status, tailwind, ability, weather, terrain, unburden) {
  let v = statVal;
  const b = boosts?.spe || 0;
  v = b >= 0 ? Math.floor(v * (2 + b) / 2) : Math.floor(v * 2 / (2 - b));
  if (item === 'Choice Scarf') v = Math.floor(v * 1.5);
  if (ability && WEATHER_SPE[ability] === weather) v *= 2;
  if (ability === 'Surge Surfer' && terrain === 'Electric') v *= 2;
  if (unburden) v *= 2;
  if (tailwind) v *= 2;
  if (status === 'par') v = Math.floor(v / 2);
  return v;
}
function infProcessMove(ev) {
  const side = labelSide(ev.label);
  if (ev.move === 'Tailwind') { infCtx.tailwindTurn[side] = ev.turn; setAutoSide(side, 'tailwind', ev.turn); }
  else if (ev.move === 'Trick Room') infCtx.trickRoomTurn = ev.turn;
  else if (ev.move === 'Reflect') { infCtx.screenTurn[side].reflect = ev.turn; setAutoSide(side, 'reflect', ev.turn); }
  else if (ev.move === 'Light Screen') { infCtx.screenTurn[side].light = ev.turn; setAutoSide(side, 'light', ev.turn); }
  else if (ev.move === 'Aurora Veil') { infCtx.screenTurn[side].veil = ev.turn; setAutoSide(side, 'veil', ev.turn); }
  else if (ev.move === 'Helping Hand') { infCtx.hhTurn[side] = ev.turn; setAutoSide(side, 'hand', ev.turn); }
  const prev = infLastMove;
  infLastMove = { turn: ev.turn, side, species: labelSpecies(ev.label), move: ev.move };
  if (!prev || prev.turn !== ev.turn || prev.side === side) return;
  const mdA = moveData(prev.move), mdB = moveData(ev.move);
  if (!mdA || !mdB || mdA.priority !== mdB.priority) return;
  const firstIsOpp = prev.side === 'p2';
  const oppSpecies = firstIsOpp ? prev.species : labelSpecies(ev.label);
  const mySpecies = firstIsOpp ? labelSpecies(ev.label) : prev.species;
  const mySpec = state.mine.find(x => x.species === mySpecies);
  const pi = state.oppTeam.indexOf(oppSpecies);
  const oppSpec = pi >= 0 ? state.opps[pi] : null;
  const table = statTable(oppSpecies);
  if (!mySpec || !oppSpec || !table) return;
  const myTable = statTable(mySpecies);
  const myRow = myTable?.spe.find(r => r.nature === mySpec.nature && r.sp === (mySpec.sp.spe || 0));
  if (!myRow) return;
  const tw = s => ev.turn - infCtx.tailwindTurn[s] >= 0 && ev.turn - infCtx.tailwindTurn[s] < 4;
  const myEff = infEffSpe(myRow.value, mySpec.boosts, mySpec.itemLost ? '' : mySpec.item, mySpec.status, tw('p1'), mySpec.ability, state.field.weather, state.field.terrain, !!mySpec.unburden);
  const trick = ev.turn - infCtx.trickRoomTurn >= 0 && ev.turn - infCtx.trickRoomTurn < 5;
  const itemKnown = (oppSpec.corrected || []).includes('持ち物');
  const abKnown = (oppSpec.corrected || []).includes('特性');
  const feasible = new Set();
  for (const row of table.spe) {
    const eff = infEffSpe(row.value, oppSpec.boosts, itemKnown ? (oppSpec.itemLost ? '' : oppSpec.item) : '', oppSpec.status, tw('p2'), abKnown ? oppSpec.ability : '', state.field.weather, state.field.terrain, !!oppSpec.unburden);
    // 通常: 先に動いた方が速い (同速の両勝ちはありうる)。トリックルーム下では逆
    const ok = trick ? (firstIsOpp ? eff <= myEff : eff >= myEff) : (firstIsOpp ? eff >= myEff : eff <= myEff);
    if (ok) feasible.add(row.nature + '|' + row.sp);
  }
  lastSpeCtx = { species: oppSpecies, turn: ev.turn, myEff, trick, firstIsOpp, twP2: tw('p2') };
  infIntersect(oppSpecies, 'spe', feasible, null);
}
/* 特性の発動順からの素早さ推定: 同時入場 (対戦開始・両者同時交代・2 体同時
   補充など) では、入場時発動の特性は素早さ順に発動する (天候の奪い合いで
   遅い方の天候が残るのはこのため)。reader が同じ入場バッチで記録した
   'ab' イベント同士を比べ、先に発動した側を速い側として、技の行動順と
   同じ形で両エンジンに証拠を与える。トリックルームは特性の発動順には
   影響しないため反転しない。入場直後はランク変化 0・かるわざ未発動
   として実効素早さを計算する */
function infProcessAbility(ev) {
  if (typeof ev.batch !== 'number') return;
  const list = infCtx.abBatches[ev.batch] || (infCtx.abBatches[ev.batch] = []);
  const me = { side: labelSide(ev.label), species: labelSpecies(ev.label) };
  for (const other of list) {
    if (other.side === me.side) continue;
    const firstIsOpp = other.side === 'p2';
    const oppSpecies = firstIsOpp ? other.species : me.species;
    const mySpecies = firstIsOpp ? me.species : other.species;
    const pairKey = ev.batch + '|' + oppSpecies + '|' + mySpecies;
    if (infCtx.abPairs.has(pairKey)) continue;
    infCtx.abPairs.add(pairKey);
    applyAbilityOrderEvidence(oppSpecies, mySpecies, firstIsOpp, ev.turn);
  }
  list.push(me);
}
function applyAbilityOrderEvidence(oppSpecies, mySpecies, firstIsOpp, turn) {
  const mySpec = state.mine.find(x => x.species === mySpecies);
  const pi = state.oppTeam.indexOf(oppSpecies);
  const oppSpec = pi >= 0 ? state.opps[pi] : null;
  const table = statTable(oppSpecies);
  if (!mySpec || !oppSpec || !table) return;
  const myTable = statTable(mySpecies);
  const myRow = myTable?.spe.find(r => r.nature === mySpec.nature && r.sp === (mySpec.sp.spe || 0));
  if (!myRow) return;
  const tw = s => turn - infCtx.tailwindTurn[s] >= 0 && turn - infCtx.tailwindTurn[s] < 4;
  const myEff = infEffSpe(myRow.value, {}, mySpec.itemLost ? '' : mySpec.item, mySpec.status, tw('p1'), mySpec.ability, state.field.weather, state.field.terrain, false);
  // 制約交差エンジン: 入場時の実効素早さで実現可能な (性格, SP) 行を残す
  const itemKnown = (oppSpec.corrected || []).includes('持ち物');
  const abKnown = (oppSpec.corrected || []).includes('特性');
  const feasible = new Set();
  for (const row of table.spe) {
    const eff = infEffSpe(row.value, {}, itemKnown ? (oppSpec.itemLost ? '' : oppSpec.item) : '', oppSpec.status, tw('p2'), abKnown ? oppSpec.ability : '', state.field.weather, state.field.terrain, false);
    if (firstIsOpp ? eff >= myEff : eff <= myEff) feasible.add(row.nature + '|' + row.sp);
  }
  infIntersect(oppSpecies, 'spe', feasible, null);
  // ベイズエンジン: 技の行動順と同じ尤度 (一致 16 / 同速 8 / 矛盾 0→下限)
  const ent = bayesEntry(oppSpecies);
  if (ent) {
    const counts = ent.cands.map(c => {
      if (c.values.spe == null) return 0;
      const eff = infEffSpe(c.values.spe, {}, oppSpec.itemLost ? '' : c.item, oppSpec.status, tw('p2'), c.ability, state.field.weather, state.field.terrain, false);
      if (eff === myEff) return 8;
      return (firstIsOpp ? eff > myEff : eff < myEff) ? 16 : 0;
    });
    bayesApply(ent, counts);
  }
}
/* ---------- 候補型×ベイズ更新エンジン (主推定) ----------
   使用率データに実在する型を候補とし、使用率を事前確率として、
   ダメージ・行動順・判明情報の証拠で事後確率を更新する。
   候補が無い種族や証拠が無い間は、従来の制約交差エンジン (estView) に
   フォールバックする (attachEstimate 参照) */
const NATURE_JA2EN = { 'がんばりや': 'Hardy', 'さみしがり': 'Lonely', 'ゆうかん': 'Brave', 'いじっぱり': 'Adamant', 'やんちゃ': 'Naughty', 'ずぶとい': 'Bold', 'すなお': 'Docile', 'のんき': 'Relaxed', 'わんぱく': 'Impish', 'のんてんき': 'Lax', 'おくびょう': 'Timid', 'せっかち': 'Hasty', 'まじめ': 'Serious', 'ようき': 'Jolly', 'むじゃき': 'Naive', 'ひかえめ': 'Modest', 'おっとり': 'Mild', 'れいせい': 'Quiet', 'てれや': 'Bashful', 'うっかりや': 'Rash', 'おだやか': 'Calm', 'おとなしい': 'Gentle', 'なまいき': 'Sassy', 'しんちょう': 'Careful', 'きまぐれ': 'Quirky' };
const BAYES_FLOOR = 0.02;    // 尤度の下限 (候補を完全に消さない)
const BAYES_REV_KEEP = 0.05; // 判明情報と矛盾する候補の減衰率
function bayesReset() { bayes = { bySpecies: {}, skipped: 0 }; }
// 候補生成: pokedb の使用率分布 (SP配分×性格×持ち物×特性) から実在の型を作る。
// 事前確率は各要素の使用率の積 (独立近似) を正規化したもの
function bayesBuildCandidates(species) {
  if (!POKEDB_PARSED || !USAGE_SETS) return null;
  let u = USAGE_SETS[idOf(species)];
  if (!u) {
    const base = gen.species.get(idOf(species))?.baseSpecies;
    if (base && base !== species) u = USAGE_SETS[idOf(base)];
  }
  if (!u || !u.code) return null;
  const pd = POKEDB_PARSED[u.code];
  if (!pd) return null;
  const table = statTable(species);
  if (!table) return null;
  const patterns = (pd.patterns || []).slice(0, 5).map(p => ({ sp: p.sp || {}, rate: p.rate || 0 }));
  const natures = (pd.natures || []).map(n => ({ en: NATURE_JA2EN[n.name], rate: n.rate || 0 })).filter(n => n.en).slice(0, 5);
  const items = (pd.items || []).map(i => ({ en: (NAMES._itemJa2en || {})[i.name], rate: i.rate || 0 })).filter(i => i.en).slice(0, 4);
  const abilities = (pd.abilities || []).map(a => ({ en: (NAMES._abilityJa2en || {})[a.name], rate: a.rate || 0 })).filter(a => a.en).slice(0, 3);
  const movePool = (pd.moves || []).map(mv => (NAMES._moveJa2en || {})[mv.ja]).filter(Boolean).slice(0, 8);
  if (!patterns.length || !natures.length) return null;
  const topItem = items[0] || { en: '', rate: 0 };
  const topAbility = abilities[0] || { en: u.ability, rate: 0 };
  let megaAbility;
  if (u.megaSpecies) {
    const ms = gen.species.get(idOf(u.megaSpecies));
    if (ms) megaAbility = Array.isArray(ms.abilities) ? ms.abilities[0] : Object.values(ms.abilities || {})[0];
  }
  const combos = [];
  for (const p of patterns) for (const n of natures) combos.push({ p, n, w: (p.rate + 0.5) * (n.rate + 0.5) });
  combos.sort((a, b) => b.w - a.w);
  const mk = (combo, item, ability, wMul) => {
    const sp = {};
    for (const k of ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) sp[k] = combo.p.sp[k] || 0;
    const values = {};
    for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) {
      const row = table[k].find(r => r.nature === combo.n.en && r.sp === sp[k]);
      values[k] = row ? row.value : null;
    }
    const hpRow = table.hp.find(r => r.sp === sp.hp);
    values.hp = hpRow ? hpRow.value : null;
    return { nature: combo.n.en, sp, item: item.en, ability: ability.en, megaAbility, megaSpecies: u.megaSpecies || undefined,
      moves: movePool, values, post: 0, _w: combo.w * Math.max(item.rate, 0.3) * Math.max(ability.rate, 0.3) * wMul };
  };
  const raw = [];
  for (const c of combos.slice(0, 20)) raw.push(mk(c, topItem, topAbility, 1));
  for (const c of combos.slice(0, 4)) for (const it of items.slice(1, 3)) raw.push(mk(c, it, topAbility, 1));
  for (const c of combos.slice(0, 3)) for (const ab of abilities.slice(1, 2)) raw.push(mk(c, topItem, ab, 1));
  for (const c of combos.slice(0, 2)) raw.push(mk(c, { en: '', rate: 0 }, topAbility, 0.15));
  const seen = new Set(), out = [];
  for (const c of raw) {
    const key = c.nature + '|' + JSON.stringify(c.sp) + '|' + c.item + '|' + c.ability;
    if (seen.has(key)) continue;
    seen.add(key); out.push(c);
  }
  const tot = out.reduce((s, c) => s + c._w, 0) || 1;
  for (const c of out) { c.post = c._w / tot; delete c._w; }
  return out.slice(0, 64);
}
function bayesEntry(species) {
  if (!bayes) return null;
  if (!bayes.bySpecies[species]) {
    // 使用率データがまだ読み込めていない間は「候補なし」を確定させない
    if (!POKEDB_PARSED || !USAGE_SETS) return null;
    const cands = bayesBuildCandidates(species);
    if (!cands || !cands.length) { bayes.bySpecies[species] = null; return null; }
    bayes.bySpecies[species] = { cands, used: 0, revKey: '' };
  }
  return bayes.bySpecies[species];
}
// 候補をイベント評価用の spec にする (場の状態はイベントのスナップショット base から)
function bayesCandSpec(base, c) {
  return { ...base, nature: c.nature, sp: { ...c.sp }, item: base.itemLost ? '' : c.item,
    ability: base.mega && c.megaAbility ? c.megaAbility : c.ability,
    megaSpecies: base.megaSpecies || c.megaSpecies, estSp: undefined, estStat: undefined, estNature: undefined };
}
// 尤度の適用。counts は「16 ロール中いくつ両立したか」相当 (0..16)。
// 全候補が 0 のイベントは未モデル要素ありとみなして更新をスキップする
function bayesApply(ent, counts) {
  if (!counts.some(n => n > 0)) { bayes.skipped++; return; }
  let tot = 0;
  ent.cands.forEach((c, i) => { c.post *= Math.max(counts[i] / 16, BAYES_FLOOR); tot += c.post; });
  if (!(tot > 0)) return;
  for (const c of ent.cands) c.post /= tot;
  ent.used++;
  infDirty = true;
}
function bayesProcessDamage(ev) {
  const opts = ev._bayesOpts;
  if (!opts) return; // 旧エンジンが対象外にした技 (変化・固定ダメ等) は同じく対象外
  const md = moveData(ev.move);
  if (!md) return;
  const atkSpecies = labelSpecies(ev.atk), defSpecies = labelSpecies(ev.def);
  if (labelSide(ev.atk) === 'p2') {
    // 相手の攻撃: 自分の正確な被ダメ量と両立するロールの割合が尤度
    if (typeof ev.amt !== 'number' || ev.amt <= 0) return;
    const ent = bayesEntry(atkSpecies);
    const defSpec = infMySpec(defSpecies, ev, false);
    const base = infOppBase(atkSpecies, ev, true);
    if (!ent || !defSpec || !base) return;
    const counts = ent.cands.map(c => {
      const { rolls } = damageRolls(withCurHP(bayesCandSpec(base, c)), withCurHP(defSpec), md.name, opts);
      return rolls.filter(r => r === ev.amt).length;
    });
    bayesApply(ent, counts);
  } else {
    // 自分の攻撃: 相手の HP% 減少 (切り捨て/四捨五入の両対応) と両立するロールの割合
    if (typeof ev.pct !== 'number' || ev.pct <= 0) return;
    const ent = bayesEntry(defSpecies);
    const atkSpec = infMySpec(atkSpecies, ev, true);
    const base = infOppBase(defSpecies, ev, false);
    if (!ent || !atkSpec || !base) return;
    const counts = ent.cands.map(c => {
      const hpVal = c.values.hp;
      if (!hpVal) return 0;
      const { rolls } = damageRolls(withCurHP(atkSpec), withCurHP(bayesCandSpec(base, c)), md.name, opts);
      let n = 0;
      for (const r of rolls) if (r > 0 && (Math.round(r / hpVal * 100) === ev.pct || Math.floor(r / hpVal * 100) === ev.pct)) n++;
      return n;
    });
    bayesApply(ent, counts);
  }
}
function bayesProcessMove(ev) {
  const ctx = lastSpeCtx;
  if (!ctx || ctx.turn !== ev.turn) return;
  const ent = bayesEntry(ctx.species);
  if (!ent) return;
  const pi = state.oppTeam.indexOf(ctx.species);
  const panel = pi >= 0 ? state.opps[pi] : null;
  const counts = ent.cands.map(c => {
    if (c.values.spe == null) return 0;
    const eff = infEffSpe(c.values.spe, panel ? panel.boosts : {}, panel && panel.itemLost ? '' : c.item,
      panel ? panel.status : '', ctx.twP2, c.ability, state.field.weather, state.field.terrain, !!(panel && panel.unburden));
    if (eff === ctx.myEff) return 8; // 同速の可能性は中間
    const ok = ctx.trick ? (ctx.firstIsOpp ? eff < ctx.myEff : eff > ctx.myEff) : (ctx.firstIsOpp ? eff > ctx.myEff : eff < ctx.myEff);
    return ok ? 16 : 0;
  });
  bayesApply(ent, counts);
}
// 判明情報 (持ち物・特性・技) と矛盾する候補の減衰。同じ判明内容では再適用しない
function syncBayesRevealed() {
  if (!bayes) return;
  for (let pi = 0; pi < state.oppTeam.length; pi++) {
    const spec = state.opps[pi];
    const ent = bayes.bySpecies[state.oppTeam[pi]];
    if (!spec || !ent) continue;
    const corr = spec.corrected || [];
    const item = spec.itemLost ? '' : (corr.includes('持ち物') ? (spec.item || '') : null);
    const ability = corr.includes('特性') ? spec.ability : null;
    const moves = spec.knownMoves || [];
    const key = (item ?? '?') + '|' + (ability ?? '?') + '|' + [...moves].sort().join(',');
    if (key === ent.revKey) continue;
    ent.revKey = key;
    let changed = false;
    for (const c of ent.cands) {
      let f = 1;
      if (item !== null && c.item !== item) f *= BAYES_REV_KEEP;
      if (ability !== null && c.ability !== ability && !(spec.mega && c.megaAbility === ability)) f *= BAYES_REV_KEEP;
      for (const mv of moves) if (!c.moves.includes(mv)) f *= 0.2;
      if (f !== 1) { c.post *= f; changed = true; }
    }
    if (changed) {
      let tot = 0;
      for (const c of ent.cands) tot += c.post;
      if (tot > 0) for (const c of ent.cands) c.post /= tot;
      infDirty = true;
    }
  }
}
// 事後確率の上位候補 (累積 90% に達するまで。最大 16 件)
function bayesCover(species) {
  if (!bayes) return null;
  const ent = bayes.bySpecies[species];
  if (!ent || !ent.used) return null;
  const sorted = [...ent.cands].sort((a, b) => b.post - a.post);
  const cover = [];
  let acc = 0;
  for (const c of sorted) { cover.push(c); acc += c.post; if (acc >= 0.9 || cover.length >= 16) break; }
  return { cover, acc, map: sorted[0] };
}
// 事後分布のビュー: MAP 型 (パネル採用用) + 事後確率 90% を覆う推定レンジ
function bayesView(spec) {
  if (!bayes) return null;
  const ent = bayes.bySpecies[spec.species];
  if (!ent || !ent.used) return null;
  const sorted = [...ent.cands].sort((a, b) => b.post - a.post);
  const map = sorted[0];
  const view = { nature: null, sp: {}, stat: {}, rows: {}, bayes: true, mapProb: map.post, map: { nature: map.nature, sp: { ...map.sp } } };
  // レンジは能力ごとの周辺分布の 90% 区間 (5%〜95% 分位点)。
  // 候補集合の min-max だと低確率の裾の候補に引っ張られるため
  for (const k of ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) {
    const bySp = [...ent.cands].sort((a, b) => (a.sp[k] || 0) - (b.sp[k] || 0));
    let acc = 0, lo = null, hi = null;
    for (const c of bySp) {
      if (lo === null && acc >= 0.05) lo = c.sp[k] || 0;
      acc += c.post;
      if (acc >= 0.95) { hi = c.sp[k] || 0; break; }
    }
    view.sp[k] = [lo ?? (bySp[0].sp[k] || 0), hi ?? (bySp[bySp.length - 1].sp[k] || 0)];
    const byVal = ent.cands.filter(c => c.values[k] != null).sort((a, b) => a.values[k] - b.values[k]);
    if (byVal.length) {
      acc = 0; let vlo = null, vhi = null;
      for (const c of byVal) {
        if (vlo === null && acc >= 0.05) vlo = c.values[k];
        acc += c.post;
        if (acc >= 0.95) { vhi = c.values[k]; break; }
      }
      view.stat[k] = [vlo ?? byVal[0].values[k], vhi ?? byVal[byVal.length - 1].values[k]];
    }
  }
  const nProb = {};
  for (const c of ent.cands) nProb[c.nature] = (nProb[c.nature] || 0) + c.post;
  const bestN = Object.entries(nProb).sort((a, b) => b[1] - a[1])[0];
  if (bestN && bestN[1] >= 0.9) view.nature = bestN[0];
  return view;
}
// 推定結果のビュー (性格の交差 + 各能力の SP/実数値レンジ)
function estView(species) {
  const e = inference.bySpecies[species];
  if (!e) return null;
  const keys = ['atk', 'spa', 'def', 'spd', 'spe'].filter(k => e.pairs[k]);
  if (!keys.length && !e.hpSps) return null;
  const table = statTable(species);
  if (!table) return null;
  let natures = null;
  for (const k of keys) {
    const ns = new Set([...e.pairs[k]].map(x => x.split('|')[0]));
    natures = natures ? new Set([...natures].filter(n => ns.has(n))) : ns;
  }
  if (natures && !natures.size) natures = null;
  const view = { nature: natures && natures.size === 1 ? [...natures][0] : null, sp: {}, stat: {}, rows: {} };
  for (const k of keys) {
    const rows = table[k].filter(r => e.pairs[k].has(r.nature + '|' + r.sp) && (!natures || natures.has(r.nature)));
    if (!rows.length) continue;
    view.sp[k] = [Math.min(...rows.map(r => r.sp)), Math.max(...rows.map(r => r.sp))];
    view.stat[k] = [Math.min(...rows.map(r => r.value)), Math.max(...rows.map(r => r.value))];
    view.rows[k] = rows;
  }
  if (e.hpSps) {
    const rows = table.hp.filter(r => e.hpSps.has(r.sp));
    view.sp.hp = [Math.min(...e.hpSps), Math.max(...e.hpSps)];
    view.stat.hp = [Math.min(...rows.map(r => r.value)), Math.max(...rows.map(r => r.value))];
    view.rows.hp = rows;
  }
  return view;
}
// 推定を相手パネルの判明情報として反映する。
// 計算用 SP は、推定レンジの中で実数値が最大になる候補の SP を使う
// (相手を最も強い前提で計算する。性格が 1 つに定まっている場合はその
//  性格の候補の中で、定まっていない場合はパネルの現在の性格の候補の
//  中で最大になるものを選び、どちらの候補も無い能力は SP レンジの
//  上限を使う)
function attachEstimate(spec) {
  // 主推定はベイズ (候補型×事後確率)。候補が無い種族・証拠が無い間は
  // 従来の制約交差 (estView) にフォールバックする
  let view = bayesView(spec);
  if (!view) view = estView(spec.species);
  // ユーザーが入力で上書きした能力は、以降の推定で上書きしない
  if (view && spec.estManual) {
    for (const k of Object.keys(spec.estManual)) {
      if (spec.estManual[k]) { delete view.sp[k]; delete view.stat[k]; delete view.rows[k]; }
    }
  }
  spec.estSp = view ? view.sp : null;
  spec.estStat = view ? view.stat : null;
  spec.estNature = view ? view.nature : null;
  spec.estMapProb = view && view.bayes ? view.mapProb : null;
  if (!view) return;
  if (view.bayes) {
    // MAP 型をそのまま採用する (性格は手動で直された場合はそちらを優先)
    if (!spec.estManual || !spec.estManual.nature) { spec.nature = view.map.nature; markCorrected(spec, '性格'); }
    for (const k of Object.keys(view.sp)) spec.sp[k] = view.map.sp[k] || 0;
    markCorrected(spec, 'EV');
    return;
  }
  if (view.nature) { spec.nature = view.nature; markCorrected(spec, '性格'); }
  for (const k of Object.keys(view.sp)) {
    const rows = view.rows[k] || [];
    const byNature = rows.filter(r => r.nature === undefined || r.nature === spec.nature);
    const pool = byNature.length ? byNature : rows;
    let best = null;
    for (const r of pool) if (!best || r.value > best.value) best = r;
    spec.sp[k] = best ? best.sp : view.sp[k][1];
    markCorrected(spec, 'EV');
  }
}
// 推定セルの手動上書き: 努力値セルに数値を入れたら、その能力は推定の対象から外して固定する
function commitEstEv(side, k, raw) {
  const spec = state[side][state.sel[side]];
  const t = String(raw).trim();
  if (!/^\d+$/.test(t)) { calcAll(); return; }
  spec.sp[k] = Math.min(32, Math.max(0, parseInt(t, 10) || 0));
  (spec.estManual ||= {})[k] = true;
  markCorrected(spec, 'EV');
  // 推定表示はその場で外し、入力した値と計算後の実数値を通常表示で即時反映する
  if (spec.estSp) delete spec.estSp[k];
  if (spec.estStat) delete spec.estStat[k];
  calcAll();
}
// 推定セルの手動上書き: 実数値セルに数値を入れたら、その実数値になる (性格, SP) を逆算して固定する。
// 現在の性格で一致する SP があればそれを、無ければ一致する性格ごと切り替える。
// どの組み合わせでも一致しない場合は、現在の性格のまま最も近い実数値になる SP にする
function commitEstStat(side, k, raw) {
  const spec = state[side][state.sel[side]];
  const t = String(raw).trim().replace(/\*$/, '');
  if (!/^\d+$/.test(t)) { calcAll(); return; }
  const target = parseInt(t, 10);
  const table = statTable(effSpecies(spec));
  const rows = table ? table[k] : null;
  if (!rows || !rows.length) { calcAll(); return; }
  const cur = spec.sp[k] || 0;
  const pickClosestSp = list => list.reduce((a, b) => (Math.abs(b.sp - cur) < Math.abs(a.sp - cur) || (Math.abs(b.sp - cur) === Math.abs(a.sp - cur) && b.sp > a.sp) ? b : a));
  let chosen = null, newNature = null;
  const exactHere = rows.filter(r => r.value === target && r.nature === spec.nature);
  if (exactHere.length) chosen = pickClosestSp(exactHere);
  else {
    const exactAny = rows.filter(r => r.value === target);
    if (exactAny.length) { chosen = pickClosestSp(exactAny); newNature = chosen.nature; }
    else {
      const pool = rows.filter(r => r.nature === spec.nature);
      chosen = pool.reduce((a, b) => (Math.abs(b.value - target) < Math.abs(a.value - target) || (Math.abs(b.value - target) === Math.abs(a.value - target) && b.sp > a.sp) ? b : a));
    }
  }
  if (newNature && newNature !== spec.nature) { spec.nature = newNature; markCorrected(spec, '性格'); }
  spec.sp[k] = chosen.sp;
  (spec.estManual ||= {})[k] = true;
  markCorrected(spec, 'EV');
  if (spec.estSp) delete spec.estSp[k];
  if (spec.estStat) delete spec.estStat[k];
  calcAll();
}

function applyState(j) {
  if (!j || typeof j !== 'object') return;
  let changed = false;
  // さいきのいのりの使用を先に拾う (同じ state.json で復活した HP が届いてもロック解除できるよう、HP 反映より前に数える)
  if (Array.isArray(j.events) && typeof inference !== 'undefined' && inference) {
    const from = j.events.length < inference.seen ? 0 : inference.seen;
    for (let i = from; i < j.events.length; i++) {
      const ev = j.events[i];
      if (ev && ev.k === 'mv' && ev.move === 'Revival Blessing' && typeof ev.label === 'string') {
        if (ev.label.startsWith('p1')) revivalPending.mine++;
        else if (ev.label.startsWith('p2')) revivalPending.opps++;
      }
    }
  }
  if (typeof j.oppTrainer === 'string' && j.oppTrainer && j.oppTrainer !== oppTrainerName) {
    oppTrainerName = j.oppTrainer;
    changed = true;
  }
  if (j.oppReset) {
    resetInference();
    oppTrainerName = '';
    state.oppTeam = [];
    state.opps = [];
    state.sel.opps = 0;
    state.active.opps = [];
    lastActiveKey.opps = '';
    faintLock.mine.clear();
    faintLock.opps.clear();
    for (const s of state.mine) if (s) s.itemLost = false;
    revivalPending.mine = 0;
    revivalPending.opps = 0;
    changed = true;
  }
  if (Array.isArray(j.mine)) {
    const idxs = [];
    for (const en of j.mine) {
      if (!en) continue;
      const spName = resolveSpecies(en.species) || en.species;
      const pi = state.mine.findIndex(s => s.species === spName);
      if (pi < 0) continue;
      if (typeof en.curHPPercent === 'number') {
        if (en.curHPPercent <= 0) { state.mine[pi].curHPPercent = 0; faintLock.mine.add(spName); }
        else if (!faintLock.mine.has(spName)) state.mine[pi].curHPPercent = en.curHPPercent;
        else if (revivalPending.mine > 0 && en.curHPPercent <= 55) { revivalPending.mine--; faintLock.mine.delete(spName); state.mine[pi].curHPPercent = en.curHPPercent; }
      }
      if (typeof en.status === 'string') state.mine[pi].status = en.status;
      // boosts キーが無い = 場に出ている以上ランクは 0 (reader は非0の時だけ送る)。
      // キーが無い時に旧値を残すと、交代でリセットされたはずのランクが
      // 再登場時に蘇ってしまうため、欠落は 0 として扱う
      state.mine[pi].boosts = Object.assign(blankBoosts(), (en.boosts && typeof en.boosts === 'object') ? en.boosts : {});
      state.mine[pi].unburden = !!en.unburden;
      // 持ち物の消費・喪失は対戦中ずっと有効 (交代しても戻らない) ため、一度立ったら維持する
      if (en.itemLost) state.mine[pi].itemLost = true;
      applyMegaFlag(state.mine[pi], en);
      idxs.push(pi); changed = true;
    }
    // 場に出ていないポケモンの かるわざ は解除されたものとして扱う (交代でリセットされるため)
    state.mine.forEach((s, i) => { if (!idxs.includes(i)) s.unburden = false; });
    if (idxs.length) {
      const key = idxs.join(',');
      if (key !== lastActiveKey.mine) { state.active.mine = idxs.slice(0, 2); state.sel.mine = idxs[0]; lastActiveKey.mine = key; }
    }
  }
  if (Array.isArray(j.oppTeam) && j.oppTeam.length) {
    const names = j.oppTeam.map(s => (s ? resolveSpecies(s) || s : null)).filter(Boolean).slice(0, 6);
    if (names.length && names.join() !== state.oppTeam.join()) {
      const old = {};
      state.oppTeam.forEach((sp, i) => { old[sp] = state.opps[i]; });
      state.oppTeam = names;
      state.opps = names.map(sp => old[sp] || oppSpec(sp, 'usage'));
      for (const sp of [...faintLock.opps]) if (!names.includes(sp)) faintLock.opps.delete(sp);
      if (state.sel.opps >= names.length) state.sel.opps = 0;
      state.active.opps = [0, Math.min(1, names.length - 1)];
      lastActiveKey.opps = '';
      changed = true;
    }
  }
  if (Array.isArray(j.opps)) {
    const idxs = [];
    for (const en of j.opps) {
      if (!en) continue;
      const spName = resolveSpecies(en.species) || en.species;
      let pi = state.oppTeam.indexOf(spName);
      if (pi < 0 && state.oppTeam.length < 6) {
        state.oppTeam.push(spName);
        state.opps.push(oppSpec(spName, 'usage'));
        pi = state.oppTeam.length - 1;
      }
      if (pi < 0) continue;
      let spec = state.opps[pi];
      if (en.revealed) { spec = applyRevealedPreserving(spec, en.revealed); state.opps[pi] = spec; }
      if (typeof en.curHPPercent === 'number') {
        if (en.curHPPercent <= 0) { spec.curHPPercent = 0; faintLock.opps.add(spName); }
        else if (!faintLock.opps.has(spName)) spec.curHPPercent = en.curHPPercent;
        else if (revivalPending.opps > 0 && en.curHPPercent <= 55) { revivalPending.opps--; faintLock.opps.delete(spName); spec.curHPPercent = en.curHPPercent; }
      }
      if (typeof en.status === 'string') spec.status = en.status;
      // mine 側と同様、boosts 欠落は 0 として扱う (交代リセットの反映漏れ防止)
      spec.boosts = Object.assign(blankBoosts(), (en.boosts && typeof en.boosts === 'object') ? en.boosts : {});
      spec.unburden = !!en.unburden;
      if (en.itemLost) spec.itemLost = true;
      applyMegaFlag(spec, en);
      idxs.push(pi); changed = true;
    }
    // 場に出ていないポケモンの かるわざ は解除されたものとして扱う (交代でリセットされるため)
    state.opps.forEach((s, i) => { if (!idxs.includes(i)) s.unburden = false; });
    if (idxs.length) {
      const key = idxs.join(',');
      if (key !== lastActiveKey.opps) { state.active.opps = idxs.slice(0, 2); state.sel.opps = idxs[0]; lastActiveKey.opps = key; }
    }
  }
  if (j.oppRevealed && typeof j.oppRevealed === 'object') {
    // 場に出ていない相手について判明した分も、その項目だけ随時反映する
    for (const [spRaw, rev] of Object.entries(j.oppRevealed)) {
      if (!rev) continue;
      const spName = resolveSpecies(spRaw) || spRaw;
      const pi = state.oppTeam.indexOf(spName);
      if (pi < 0) continue;
      state.opps[pi] = applyRevealedPreserving(state.opps[pi], rev);
      changed = true;
    }
  }
  if (j.field && typeof j.field === 'object') { Object.assign(state.field, j.field); changed = true; }
  syncBayesRevealed();
  if (Array.isArray(j.events)) {
    if (j.events.length < inference.seen) resetInference();
    for (let i = inference.seen; i < j.events.length; i++) {
      const ev = j.events[i];
      if (!ev || typeof ev !== 'object') continue;
      if (typeof ev.turn === 'number') expireAutoSide(ev.turn);
      if (ev.k === 'mv') { infProcessMove(ev); bayesProcessMove(ev); }
      else if (ev.k === 'dmg') { infProcessDamage(ev); bayesProcessDamage(ev); }
      else if (ev.k === 'ab') { infProcessAbility(ev); }
    }
    inference.seen = j.events.length;
    if (infDirty) { infDirty = false; changed = true; }
  }
  for (const spec of state.opps) if (spec) attachEstimate(spec);
  if (changed) calcAll();
}
let lastStateText = '';
let uiVersionSeen = null;
async function poll() {
  try {
    const rv = await fetch('./ui_version.txt', { cache: 'no-store' });
    if (rv.ok) {
      const v = (await rv.text()).trim();
      if (uiVersionSeen === null) uiVersionSeen = v;
      else if (v && v !== uiVersionSeen) { location.reload(); return; }
    }
  } catch (e) { /* ローカルコピーのみで動作 */ }
  try {
    const r = await fetch('./state.json', { cache: 'no-store' });
    if (r.ok) {
      const txt = await r.text();
      if (txt !== lastStateText) { lastStateText = txt; applyState(JSON.parse(txt)); }
    }
  } catch (e) { /* not running under a server */ }
}

/* ---------- init ---------- */
(async function init() {
  // state.json の取り込みはデータ読み込みの完了を待たずに即開始する
  // (選出画面・試合開始直後の反映を速くするため)
  poll();
  setInterval(poll, 200);
  // データファイル群は並列に読み込む (逐次読みだと全て揃うまで時間がかかるため)
  await Promise.all([
    (async () => { try {
      const r = await fetch('./data/names_ja.json');
      if (r.ok) {
        NAMES = await r.json();
        NAMES._ja2en = {};
        NAMES._indexSpecies = (await (await fetch('./data/names_index.json')).json()).species;
        // 同じJA名に複数のフォルムがある場合は先勝ち (索引は基本フォルムが先頭)
        for (const e of NAMES._indexSpecies) { const k = z2h(e.ja); if (!(k in NAMES._ja2en)) NAMES._ja2en[k] = e.en; }
        NAMES._moveJa2en = {};
        for (const [id, jaName] of Object.entries(NAMES.moves)) { const mv = [...gen.moves].find(m => idOf(m.name) === id); if (mv) NAMES._moveJa2en[z2h(jaName)] = mv.name; }
        NAMES._abilityJa2en = {};
        for (const [id, jaName] of Object.entries(NAMES.abilities)) { const ab = [...gen.abilities].find(a => idOf(a.name) === id); if (ab) NAMES._abilityJa2en[z2h(jaName)] = ab.name; }
        NAMES._itemEn2ja = {};
        try {
          const ij = await (await fetch('./data/items_ja.json')).json();
          NAMES._itemJa2en = ij;
          for (const [jaName, en] of Object.entries(ij)) (NAMES._itemEn2ja || {})[idOf(en)] = jaName;
        } catch (e) { /* items_ja optional */ }
      }
    } catch (e) { /* names are optional */ } })(),
    (async () => { try {
      const u = await (await fetch('./data/usage_sets.json')).json();
      USAGE_SETS = u.sets || {};
      USAGE_SEASON = u.season || '';
      // 読み込み前に仮の型で作られていた相手パネルは、使用率型で作り直す。
      // その際、既に反映済みの HP・状態・判明情報などは引き継ぐ
      state.opps = state.oppTeam.map((sp, i) => {
        const old = state.opps[i];
        if (!old || old.species !== sp) return oppSpec(sp, 'usage');
        if (!old.noUsage) return old;
        const fresh = oppSpec(sp, 'usage');
        fresh.curHPPercent = old.curHPPercent; fresh.boosts = old.boosts; fresh.status = old.status;
        fresh.knownMoves = old.knownMoves || [];
        if (old.estManual) fresh.estManual = old.estManual;
        for (const f of old.corrected || []) {
          if (f === '特性') fresh.ability = old.ability;
          if (f === '性格') fresh.nature = old.nature;
          if (f === '持ち物') { fresh.item = old.item; fresh.megaSpecies = old.megaSpecies; fresh.megaAbility = old.megaAbility; fresh.mega = old.mega; }
          if (f === '技') fresh.moves = [...old.moves];
          if (f === 'EV') fresh.sp = { ...old.sp };
          if (!fresh.corrected.includes(f)) fresh.corrected.push(f);
        }
        if (old.mega && !fresh.mega) { fresh.mega = true; fresh.megaSpecies = old.megaSpecies; fresh.megaAbility = old.megaAbility; }
        return fresh;
      });
    } catch (e) { /* usage sets optional */ } })(),
    (async () => { try {
      const sa = await (await fetch('./data/species_abilities.json')).json();
      SPECIES_ABILITIES = sa || {};
    } catch (e) { /* species abilities optional */ } })(),
    (async () => { try {
      POKEDB_PARSED = await (await fetch('./data/pokedb_parsed.json')).json();
    } catch (e) { /* pokedb distributions optional (bayes falls back) */ } })(),
    (async () => { try {
      const cd = await (await fetch('./data/champions_dex.json')).json();
      CHAMP = { species: new Set(cd.species || []), items: new Set(cd.items || []), moves: new Set(cd.moves || []) };
    } catch (e) { /* champions dex optional */ } })(),
    (async () => { try {
      const rg = await (await fetch('./data/regulation.json')).json();
      if (rg && rg.regulation) { const el = document.getElementById('regname'); if (el) el.textContent = 'レギュレーション' + rg.regulation; }
    } catch (e) { /* regulation optional */ } })(),
  ]);
  // dropdown option lists
  const seen = new Set();
  SPECIES_OPTIONS = Object.entries(NAMES._ja2en || {})
    .filter(([, en]) => !CHAMP.species.size || CHAMP.species.has(en))
    .filter(([, en]) => { if (seen.has(en)) return false; seen.add(en); return true; })
    .map(([jaName, en]) => ({ v: en, l: jaName }))
    .sort((a, b) => a.l.localeCompare(b.l, 'ja'));
  MOVE_OPTIONS = [{ v: '', l: '（技なし）' }].concat(
    Object.entries(NAMES._moveJa2en || {})
      .filter(([, en]) => !CHAMP.moves.size || CHAMP.moves.has(en))
      .map(([jaName, en]) => ({ v: en, l: jaName }))
      .sort((a, b) => a.l.localeCompare(b.l, 'ja')));
  ITEM_OPTIONS = [{ v: '', l: 'なし' }].concat(
    [...gen.items].map(it => it.name)
      .filter(en => !CHAMP.items.size || CHAMP.items.has(en))
      .map(en => ({ v: en, l: (NAMES._itemEn2ja || {})[idOf(en)] || en }))
      .sort((a, b) => a.l.localeCompare(b.l, 'ja')));
  await loadMyTeam();
  calcAll();
  // データが揃った状態で最新の state.json を反映し直す
  lastStateText = '';
  poll();
})();

;globalThis.__T = { get state(){ return state; }, applyState, bayesBuildCandidates, get bayes(){ return bayes; } };
