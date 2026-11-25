// ダメージ計算の全体点検ハーネス (UI の配線と表示側)。
// 実際の ui.html の calcAll を駆動し、各ケースの結果 (ダメージ幅・KO%・説明文・
// ステータス・素早さ) を、素の @smogon/calc で独立に組み立てた参照計算と突き合わせる。
// 使い方: node tests/calc_audit.mjs (不一致があれば一覧表示し exit 1)
import fs from 'fs';
import path from 'path';
import url from 'url';
import { Generations, Pokemon, Move, Field, calculate } from '@smogon/calc';
import { fallbackKoText } from '../core.mjs';

const ROOT = path.dirname(url.fileURLToPath(import.meta.url)) + '/..';
const html = fs.readFileSync(ROOT + '/ui.html', 'utf8');
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) { console.log('FAIL module script not found'); process.exit(1); }

// ---- DOM スタブ (ui_harness と同じ形) ----
function makeEl() {
  const el = {
    children: [], style: {}, dataset: {}, value: '', textContent: '', innerHTML: '',
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    addEventListener() {}, removeEventListener() {}, appendChild(c) { this.children.push(c); return c; },
    setAttribute() {}, getAttribute: () => null, remove() {}, focus() {}, click() {},
    querySelector: () => null, querySelectorAll: () => [],
    closest: () => null, getBoundingClientRect: () => ({ width: 0, height: 0, top: 0, left: 0 }),
  };
  return el;
}
const els = new Map();
globalThis.document = {
  getElementById: id => { if (!els.has(id)) els.set(id, makeEl()); return els.get(id); },
  querySelector: () => null, querySelectorAll: () => [],
  createElement: () => makeEl(), addEventListener() {},
  body: makeEl(), documentElement: makeEl(), hidden: false,
};
globalThis.localStorage = { getItem: () => null, setItem() {}, removeItem() {} };
globalThis.location = { reload() {} };
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
if (!globalThis.navigator) globalThis.navigator = { clipboard: { writeText: async () => {} } };
globalThis.fetch = async (u) => {
  const p = String(u).split('?')[0];
  const resp = text => ({ ok: true, status: 200, text: async () => text, json: async () => JSON.parse(text) });
  if (p.endsWith('state.json')) return resp('{}');
  if (p.endsWith('ui_version.txt')) return resp('audit');
  const file = path.join(ROOT, p.replace(/^\.\//, ''));
  if (fs.existsSync(file)) return resp(fs.readFileSync(file, 'utf8'));
  return { ok: false, status: 404, text: async () => '', json: async () => { throw new Error('404'); } };
};

const hook = `\n;globalThis.__T = { get state(){ return state; }, get ui(){ return ui; }, calcAll, resetInference, koFmt, get lastCalc(){ return lastCalc; } };\n`;
const tmp = ROOT + '/.calc_audit_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);

// ---- 参照計算 (素の @smogon/calc で独立に構築) ----
const gen = Generations.get(9);
const IVS = { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 };
const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
function refPokemon(spec) {
  const name = spec.mega && spec.megaSpecies ? spec.megaSpecies : spec.species;
  const ability = spec.mega && spec.megaAbility ? spec.megaAbility : spec.ability;
  const evs = {};
  for (const k of STATS) evs[k] = (spec.sp?.[k] || 0) * 8;
  let curHP;
  if (spec.curHPPercent != null && spec.curHPPercent < 100) {
    const probe = new Pokemon(gen, name, { level: 50, nature: spec.nature, ability, ivs: IVS, evs });
    curHP = Math.max(1, Math.floor(probe.stats.hp * spec.curHPPercent / 100));
  }
  return new Pokemon(gen, name, {
    level: 50, nature: spec.nature, ability,
    item: spec.itemLost ? '' : (spec.item || undefined),
    ivs: IVS, evs, boosts: spec.boosts || undefined, status: spec.status || '', curHP,
    abilityOn: ability === 'Unburden' && spec.unburden ? true : undefined,
  });
}
function refField(c, gameType) {
  // c.dir: 'mine' = 自分の技→相手 (attackerSide は自分の場、defenderSide は相手の場)
  const atk = c.dir === 'mine' ? c.sideMine : c.sideOpp;
  const def = c.dir === 'mine' ? c.sideOpp : c.sideMine;
  return new Field({
    gameType,
    weather: c.weather || undefined,
    terrain: c.terrain || undefined,
    attackerSide: { isHelpingHand: !!atk.hand },
    defenderSide: {
      isLightScreen: !!def.light, isReflect: !!def.reflect, isAuroraVeil: !!def.veil,
      isFriendGuard: !!def.guard, isSR: !!def.rock, spikes: def.spikes || 0,
    },
  });
}
function refBoostedSpe(p, tailwind) {
  let v = p.stats.spe;
  const b = (p.boosts && p.boosts.spe) || 0;
  v = b >= 0 ? Math.floor(v * (2 + b) / 2) : Math.floor(v * 2 / (2 - b));
  if (p.ability === 'Unburden' && p.abilityOn) v *= 2;
  if (tailwind) v *= 2;
  if (p.status === 'par') v = Math.floor(v / 2);
  return v;
}

// ---- ケース定義 ----
// spec: パネルに設定する内容そのもの。move は対象の技 (mine 側の技なら dir:'mine')。
const B = (o) => ({ hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0, ...o });
function spec(o) {
  return {
    species: o.species, megaSpecies: o.megaSpecies, mega: !!o.mega,
    ability: o.ability, megaAbility: o.megaAbility, nature: o.nature || 'Serious',
    item: o.item || '', itemLost: !!o.itemLost, unburden: !!o.unburden,
    sp: o.sp || {}, moves: o.moves || [], curHPPercent: o.curHPPercent ?? 100,
    boosts: o.boosts || B({}), status: o.status || '', kind: 'custom', corrected: [],
  };
}
const CASES = [];
function C(name, mine, opp, opt = {}) {
  CASES.push({
    name, mine, opp,
    dir: opt.dir || 'mine', move: opt.move || (opt.dir === 'opps' ? opp.moves[0] : mine.moves[0]),
    weather: opt.weather || '', terrain: opt.terrain || '',
    sideMine: opt.sideMine || {}, sideOpp: opt.sideOpp || {},
    crit: !!opt.crit, single: !!opt.single, immune: !!opt.immune,
    moveSpecVal: opt.moveSpecVal,
  });
}

const GARCHOMP = { species: 'Garchomp', ability: 'Rough Skin', nature: 'Adamant', sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Earthquake'] };
const BLASTOISE = { species: 'Blastoise', ability: 'Rain Dish', nature: 'Modest', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Water Spout'] };
const GARDEVOIR = { species: 'Gardevoir', ability: 'Synchronize', nature: 'Timid', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Psychic'] };
const CHARIZARD = { species: 'Charizard', ability: 'Blaze', nature: 'Timid', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Flamethrower'] };
const TYRANITAR = { species: 'Tyranitar', ability: 'Sand Stream', nature: 'Adamant', sp: { hp: 32, atk: 32, def: 2 }, moves: ['Stone Edge'] };
const AVALUGG = { species: 'Avalugg', ability: 'Sturdy', nature: 'Impish', sp: { hp: 32, def: 32, atk: 2 }, moves: ['Body Press'] };
const SNORLAX = { species: 'Snorlax', ability: 'Thick Fat', nature: 'Adamant', sp: { hp: 32, atk: 32, spd: 2 }, moves: ['Body Slam'] };
const DRAGONITE = { species: 'Dragonite', ability: 'Multiscale', nature: 'Adamant', sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Dragon Claw'] };
const AZUMARILL = { species: 'Azumarill', ability: 'Huge Power', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Play Rough'] };
const SCIZOR = { species: 'Scizor', ability: 'Technician', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Bullet Punch'] };
const BRONZONG = { species: 'Bronzong', ability: 'Levitate', nature: 'Relaxed', sp: { hp: 32, def: 32, spd: 2 }, moves: ['Gyro Ball'] };
const HERACROSS = { species: 'Heracross', ability: 'Guts', nature: 'Adamant', sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Facade'] };
const NIDOKING = { species: 'Nidoking', ability: 'Sheer Force', nature: 'Modest', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Sludge Bomb'] };
const CRAWDAUNT = { species: 'Crawdaunt', ability: 'Adaptability', nature: 'Adamant', sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Crabhammer'] };
const CHANDELURE = { species: 'Chandelure', ability: 'Flash Fire', nature: 'Modest', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Shadow Ball'] };
const JOLTEON = { species: 'Jolteon', ability: 'Volt Absorb', nature: 'Timid', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Shadow Ball'] };
const UMBREON = { species: 'Umbreon', ability: 'Synchronize', nature: 'Careful', sp: { hp: 32, spd: 32, def: 2 }, moves: ['Foul Play'] };

// 基本
C('物理・等倍 (じしん)', spec(GARCHOMP), spec(BLASTOISE));
C('特殊・抜群 (しおふき満タン)', spec(BLASTOISE), spec(GARCHOMP));
C('特殊・等倍 (サイコキネシス)', spec(GARDEVOIR), spec(BLASTOISE));
C('逆方向 (相手の技→自分)', spec(BLASTOISE), spec(GARCHOMP), { dir: 'opps', move: 'Earthquake' });
// 無効 (タイプ・特性)
C('無効: じしん vs 飛行', spec(GARCHOMP), spec(CHARIZARD), { immune: true });
C('ほのお技 vs みず (半減)', spec(CHARIZARD), spec(BLASTOISE));
C('無効: サイコキネシス vs あく', spec(GARDEVOIR), spec(UMBREON), { immune: true });
C('無効: じしん vs ふゆう', spec(GARCHOMP), spec(BRONZONG), { immune: true });
C('無効: かえんほうしゃ vs もらいび', spec(CHARIZARD), spec(CHANDELURE), { immune: true });
C('無効: 10まんボルト vs ちくでん', spec({ ...JOLTEON, moves: ['Thunderbolt'] }), spec(JOLTEON), { immune: true });
// 天候
C('雨: みず技強化', spec(BLASTOISE), spec(GARCHOMP), { weather: 'Rain' });
C('雨: ほのお技弱化', spec(CHARIZARD), spec(BLASTOISE), { weather: 'Rain' });
C('晴: ほのお技強化', spec(CHARIZARD), spec(BLASTOISE), { weather: 'Sun' });
C('砂: いわ特防アップ (特殊で攻撃)', spec({ ...GARDEVOIR, moves: ['Moonblast'] }), spec(TYRANITAR), { weather: 'Sand', move: 'Moonblast' });
C('雪: こおり防アップ (物理で攻撃)', spec(GARCHOMP), spec(AVALUGG), { weather: 'Snow' });
// フィールド
C('エレキF: でんき技強化', spec({ ...JOLTEON, moves: ['Thunderbolt'] }), spec(BLASTOISE), { terrain: 'Electric' });
C('グラスF: くさ技強化', spec({ species: 'Rillaboom', ability: 'Grassy Surge', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Wood Hammer'] }), spec(BLASTOISE), { terrain: 'Grassy' });
C('ミストF: ドラゴン半減', spec(DRAGONITE), spec(BLASTOISE), { terrain: 'Misty' });
C('サイコF: エスパー強化', spec(GARDEVOIR), spec(BLASTOISE), { terrain: 'Psychic' });
// 壁・場の状態
C('リフレクター (物理)', spec(GARCHOMP), spec(BLASTOISE), { sideOpp: { reflect: true } });
C('ひかりのかべ (特殊)', spec(GARDEVOIR), spec(BLASTOISE), { sideOpp: { light: true } });
C('オーロラベール (物理)', spec(GARCHOMP), spec(BLASTOISE), { sideOpp: { veil: true }, weather: 'Snow' });
C('てだすけ', spec(GARCHOMP), spec(BLASTOISE), { sideMine: { hand: true } });
C('フレンドガード', spec(GARCHOMP), spec(BLASTOISE), { sideOpp: { guard: true } });
C('ステロ+まきびし (KO テキスト)', spec(GARCHOMP), spec({ ...BLASTOISE, sp: { hp: 32, spa: 32 } }), { sideOpp: { rock: true, spikes: 2 } });
// ランク・状態
C('攻撃+2', spec({ ...GARCHOMP, boosts: B({ atk: 2 }) }), spec(BLASTOISE));
C('相手防御-1', spec(GARCHOMP), spec({ ...BLASTOISE, boosts: B({ def: -1 }) }));
C('やけど (物理半減)', spec({ ...GARCHOMP, status: 'brn' }), spec(BLASTOISE));
C('やけど+こんじょう (からげんき)', spec({ ...HERACROSS, status: 'brn' }), spec(BLASTOISE));
C('まひ (素早さのみ・ダメージ不変)', spec({ ...GARDEVOIR, status: 'par' }), spec(BLASTOISE));
// 急所
C('急所', spec(GARCHOMP), spec(BLASTOISE), { crit: true });
// 持ち物
C('いのちのたま', spec({ ...GARDEVOIR, item: 'Life Orb' }), spec(BLASTOISE));
C('こだわりハチマキ', spec({ ...GARCHOMP, item: 'Choice Band' }), spec(BLASTOISE));
C('こだわりメガネ', spec({ ...GARDEVOIR, item: 'Choice Specs' }), spec(BLASTOISE));
C('たべのこし (KO テキスト)', spec(GARCHOMP), spec({ ...BLASTOISE, item: 'Leftovers' }));
C('もちものなし→itemLost', spec({ ...GARCHOMP, item: 'Choice Band', itemLost: true }), spec(BLASTOISE));
// 特性 (ダメージ系)
C('あついしぼう (ほのお半減)', spec(CHARIZARD), spec(SNORLAX));
C('マルチスケイル (満タン)', spec({ ...GARCHOMP, moves: ['Dragon Claw'] }), spec(DRAGONITE), { move: 'Dragon Claw' });
C('マルチスケイル (HP99%で不発)', spec({ ...GARCHOMP, moves: ['Dragon Claw'] }), spec({ ...DRAGONITE, curHPPercent: 99 }), { move: 'Dragon Claw' });
C('ちからもち', spec(AZUMARILL), spec(BLASTOISE));
C('テクニシャン (威力60以下)', spec(SCIZOR), spec(BLASTOISE));
C('ちからずく (追加効果技)', spec(NIDOKING), spec(BLASTOISE));
C('てきおうりょく (STAB)', spec(CRAWDAUNT), spec(BLASTOISE));
// メガシンカ
C('メガガルーラでなくメガサーナイト (ピクシレート)', spec({ species: 'Gardevoir', megaSpecies: 'Gardevoir-Mega', mega: true, ability: 'Synchronize', megaAbility: 'Pixilate', nature: 'Timid', sp: { hp: 2, spa: 32, spe: 32 }, moves: ['Hyper Voice'] }), spec(BLASTOISE), { move: 'Hyper Voice' });
// 現在 HP (KO% 前提・攻撃側 HP 依存技)
C('KO%現在HP: 相手50%', spec(GARCHOMP), spec({ ...BLASTOISE, curHPPercent: 50 }));
C('KO%現在HP: 相手25%', spec(GARCHOMP), spec({ ...BLASTOISE, curHPPercent: 25 }));
C('しおふき (攻撃側HP50%)', spec({ ...BLASTOISE, curHPPercent: 50 }), spec(GARCHOMP));
C('かるわざ発動 (素早さ2倍)', spec({ species: 'Sneasler', ability: 'Unburden', nature: 'Adamant', item: 'Psychic Seed', itemLost: true, unburden: true, sp: { hp: 2, atk: 32, spe: 32 }, moves: ['Close Combat'] }), spec(BLASTOISE), { move: 'Close Combat' });
// 範囲技 (全体/単体)
C('範囲技: なみのり 全体 (ダブル)', spec({ ...BLASTOISE, moves: ['Surf'] }), spec(GARCHOMP), { move: 'Surf' });
C('範囲技: なみのり 単体指定', spec({ ...BLASTOISE, moves: ['Surf'] }), spec(GARCHOMP), { move: 'Surf', single: true });
C('範囲技: じしん 全体', spec(GARCHOMP), spec(BLASTOISE));
C('範囲技: じしん 単体指定', spec(GARCHOMP), spec(BLASTOISE), { single: true });
// 連続技・積み技の指定 (moveSpecs 配線)。参照側はゲームのルールを素の Move で再現する
// (ヒット数 = Move の hits、ふんどのこぶし/おはかまいり = 威力 50 + 50 × 指定値)
C('連続技: タネマシンガン 5ヒット指定', spec({ species: 'Breloom', ability: 'Effect Spore', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Bullet Seed'] }), spec(BLASTOISE), { move: 'Bullet Seed', moveSpecVal: 5 });
C('連続技: タネマシンガン 未指定', spec({ species: 'Breloom', ability: 'Effect Spore', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Bullet Seed'] }), spec(BLASTOISE), { move: 'Bullet Seed' });
C('ふんどのこぶし 被弾3回指定', spec({ species: 'Annihilape', ability: 'Defiant', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Rage Fist'] }), spec(BLASTOISE), { move: 'Rage Fist', moveSpecVal: 3 });
C('おはかまいり 味方2体指定', spec({ species: 'Houndstone', ability: 'Sand Rush', nature: 'Adamant', sp: { hp: 32, atk: 32, spe: 2 }, moves: ['Last Respects'] }), spec(BLASTOISE), { move: 'Last Respects', moveSpecVal: 2 });

// ---- 実行 ----
let failures = 0, total = 0;
const rows = [];
const koTexts = new Set();
function cmp(caseName, field, uiVal, refVal) {
  total++;
  const ok = uiVal === refVal;
  if (!ok) { failures++; rows.push(`MISMATCH [${caseName}] ${field}: UI=${JSON.stringify(uiVal)} REF=${JSON.stringify(refVal)}`); }
}
try {
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  // 初期化 (データ読み込み) の完了待ち
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 100));
    try { T.calcAll(); if (T.lastCalc) break; } catch (e) { /* still loading */ }
  }
  for (const c of CASES) {
    if (process.env.AUDIT_VERBOSE) console.log('CASE', c.name);
    T.resetInference();
    const mine = structuredClone(c.mine);
    const opp = structuredClone(c.opp);
    if (c.moveSpecVal != null) {
      const atk = c.dir === 'mine' ? mine : opp;
      const mi = atk.moves.indexOf(c.move);
      atk.moveSpec = { [mi]: c.moveSpecVal };
    }
    T.state.mine = [mine];
    T.state.opps = [opp];
    T.state.sel.mine = 0; T.state.sel.opps = 0;
    // 相手の場に2体いる前提 (範囲技の既定モード = 全体 になる)
    T.state.active.mine = [0, 1]; T.state.active.opps = [0, 1];
    T.state.field.weather = c.weather; T.state.field.terrain = c.terrain;
    T.state.side.mine = { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false, rock: false, spikes: 0, ...c.sideMine };
    T.state.side.opp = { light: false, reflect: false, veil: false, hand: false, guard: false, tailwind: false, rock: false, spikes: 0, ...c.sideOpp };
    // てだすけは単体フラグ (攻撃側の個体) として UI へ渡す
    mine.hand = !!(c.sideMine && c.sideMine.hand);
    opp.hand = !!(c.sideOpp && c.sideOpp.hand);
    T.ui.crit.mine = c.dir === 'mine' && c.crit;
    T.ui.crit.opps = c.dir === 'opps' && c.crit;
    T.ui.spreadSel.mine = {}; T.ui.spreadSel.opps = {};
    if (c.single) {
      const sd = c.dir;
      T.ui.spreadSel[sd] = { [c.move]: 'single' };
    }
    T.calcAll();
    const res = c.dir === 'mine' ? T.lastCalc.results[0] : T.lastCalc.oppResults[0];
    const row = res.moveResults.find(r => r.move === c.move);
    const v = row?.vs?.[0];
    if (!v) { failures++; rows.push(`NO RESULT [${c.name}]`); continue; }
    // 参照
    const atkSpec = c.dir === 'mine' ? c.mine : c.opp;
    const defSpec = c.dir === 'mine' ? c.opp : c.mine;
    const atkP = refPokemon(atkSpec), defP = refPokemon(defSpec);
    let mv = new Move(gen, c.move);
    if (c.moveSpecVal != null) {
      // core の buildMove と同じゲームルールを素の Move で再現する
      const md = gen.moves.get(c.move.toLowerCase().replace(/[^a-z0-9]/g, ''));
      if (md && (md.multihit === true || Array.isArray(md.multihit))) mv = new Move(gen, c.move, { hits: c.moveSpecVal });
      else mv = new Move(gen, c.move, { overrides: { basePower: 50 + 50 * c.moveSpecVal } });
    }
    if (c.crit) mv.isCrit = true;
    // core は単体指定された範囲技だけ Singles フィールド、それ以外は doubles フィールド
    const field = refField(c, c.single ? 'Singles' : 'doubles');
    if (c.immune) {
      cmp(c.name, 'immune-flag', v.immune === true, true);
      cmp(c.name, 'immune-dmg', `${v.minPct}-${v.maxPct}`, '0-0');
      continue;
    }
    if (v.status || v.error) { failures++; rows.push(`UI STATUS/ERROR [${c.name}]: ${JSON.stringify(v)}`); continue; }
    let r;
    try {
      r = calculate(gen, atkP, defP, mv, field);
    } catch (e) {
      failures++; rows.push(`REF THREW [${c.name}]: ${e.message} (UI: ${JSON.stringify(v)})`);
      continue;
    }
    const range = r.range();
    const defMax = defP.stats.hp;
    cmp(c.name, 'minPct', v.minPct, Math.round(range[0] / defMax * 1000) / 10);
    cmp(c.name, 'maxPct', v.maxPct, Math.round(range[1] / defMax * 1000) / 10);
    let refKo;
    try { refKo = r.kochance().text; } catch (e) { refKo = `<kochance threw: ${e.message}>`; }
    let refDesc;
    try { refDesc = r.desc(); } catch (e) { refDesc = `<desc threw: ${e.message}>`; }
    // UI は 9HKO 超の低ダメージで KO テキストを補完する (core の fallbackKoText)
    if (!refKo && range[1] > 0) {
      const fb = fallbackKoText(atkP, defP, mv, field, range[1], false, false);
      if (fb) { refKo = fb; refDesc = refDesc + ' -- ' + fb; }
    }
    cmp(c.name, 'ko', v.ko, refKo);
    cmp(c.name, 'desc', v.desc, refDesc);
    // ステータスと素早さ (両サイド)
    const statsRef = { mine: refPokemon(c.mine).stats, opps: refPokemon(c.opp).stats };
    for (const sd of ['mine', 'opps']) {
      for (const k of STATS) cmp(c.name, `stats.${sd}.${k}`, T.lastCalc.stats[sd][0][k], statsRef[sd][k]);
    }
    cmp(c.name, 'speed.mine', T.lastCalc.speeds.mine[0], refBoostedSpe(refPokemon(c.mine), !!c.sideMine.tailwind));
    cmp(c.name, 'speed.opps', T.lastCalc.speeds.opps[0], refBoostedSpe(refPokemon(c.opp), !!c.sideOpp.tailwind));
    // おいかぜの素早さ (1ケースだけ追加で確認)
    if (c.name === '物理・等倍 (じしん)') {
      T.state.side.mine.tailwind = true;
      T.calcAll();
      cmp(c.name + '+おいかぜ', 'speed.mine', T.lastCalc.speeds.mine[0], refBoostedSpe(refPokemon(c.mine), true));
      T.state.side.mine.tailwind = false;
    }
    if (v.ko) koTexts.add(v.ko);
  }
  // KO テキストの表示整形 (koFmt) が全形状をラベル化できるか
  const SYNTH_KO = [
    'guaranteed OHKO after Stealth Rock',
    'guaranteed OHKO after hail damage',
    'possible OHKO',
    'approx. 50% chance to 2HKO',
    'guaranteed 2HKO after Stealth Rock',
    '12.5% chance to OHKO after Stealth Rock (guaranteed OHKO after Leftovers recovery)',
  ];
  for (const t of [...koTexts, ...SYNTH_KO]) {
    const f = T.koFmt(t);
    total++;
    if (!f || f[0] === t) { failures++; rows.push(`KOFMT FALLBACK: ${JSON.stringify(t)} -> ${JSON.stringify(f)}`); }
  }
} finally {
  try { fs.unlinkSync(tmp); } catch (e) {}
}
console.log(`cases: ${CASES.length}, comparisons: ${total}, mismatches: ${failures}`);
for (const r of rows) console.log(r);
console.log(failures === 0 ? 'AUDIT ALL MATCH' : 'AUDIT MISMATCHES FOUND');
process.exit(failures === 0 ? 0 : 1);
