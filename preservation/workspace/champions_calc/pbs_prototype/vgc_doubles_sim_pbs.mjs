// 型推定エンジン (ベイズ) の M-C ダブル模擬対戦テスト。
// VGCPastes の実在チーム (6体) と自分の登録チームで、選出 (4体)・技選択
// (効果抜群を優先)・メガシンカ・交代を含むダブルバトルを再現し、相手の
// 出場個体ごとに推定の収束をターン単位で計測する。
// チームはシャッフル済みデッキから重複なく配り、偏った連続使用を避ける。
// 証拠の流し方は bayes_sim.mjs と同じ流儀 (ダメージ % / 実数照合 +
// 行動順のハード制約の複製)。反動・公表情報・技判明の経路は未再現。
//
// 使い方:
//   node tests/vgc_doubles_sim.mjs [--seed 1] [--battles 100] [--turns 12]
//                                  [--merge-vgc 1] [--out <path>]
import fs from 'fs';
import path from 'path';
import url from 'url';
import { buildPools, createPbs, spDist as pbsSpDist } from './estimators.mjs';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf('--' + name); return i >= 0 ? args[i + 1] : def; };
const SEED = parseInt(opt('seed', '1'), 10) || 1;
const BATTLES = Math.max(1, parseInt(opt('battles', '100'), 10) || 100);
const TURNS = Math.max(1, parseInt(opt('turns', '12'), 10) || 12);
const MERGE_VGC = opt('merge-vgc', '0') !== '0';
const MOVESEEN = opt('moveseen', '1') !== '0'; // 相手の技判明 (moveUpdate) を証拠として流すか
const REVEALED = opt('revealed', '1') !== '0'; // 判明情報 (特性・持ち物) を本番の applyRevealed 経路で流すか
// 登場時に表示される特性 (天候・フィールド・いかく等)。表示されない特性は流さない
const ENTRY_AB = new Set(['Intimidate', 'Drought', 'Drizzle', 'Sand Stream', 'Snow Warning', 'Electric Surge', 'Grassy Surge', 'Misty Surge', 'Psychic Surge', 'Download', 'Orichalcum Pulse', 'Hadron Engine', 'Dauntless Shield', 'Intrepid Sword', 'Slow Start', 'Screen Cleaner']); // 配線後は実経路 (VGC_SETS) が本体。META への統合は旧経路の再現用
const OUT = opt('out', path.join(ROOT, 'tests', 'sim_results', `vgc_doubles_seed${SEED}.json`));

let rngState = SEED >>> 0;
const rnd = () => { rngState = (rngState + 0x6D2B79F5) >>> 0; let t = rngState; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const rndInt = n => Math.floor(rnd() * n);
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = rndInt(i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };

// ---- UI モジュールの読み込み (bayes_sim と同じスタブ) ----
const html = fs.readFileSync(ROOT + '/ui.html', 'utf8');
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) { console.log('FAIL module script not found'); process.exit(1); }
function makeEl() {
  return {
    children: [], style: {}, dataset: {}, value: '', textContent: '', innerHTML: '',
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    addEventListener() {}, removeEventListener() {}, appendChild(c) { this.children.push(c); return c; },
    setAttribute() {}, getAttribute: () => null, remove() {}, focus() {}, click() {},
    querySelector: () => null, querySelectorAll: () => [],
    closest: () => null, getBoundingClientRect: () => ({ width: 0, height: 0, top: 0, left: 0 }),
  };
}
const els = new Map();
globalThis.document = {
  getElementById: id => { if (!els.has(id)) els.set(id, makeEl()); return els.get(id); },
  querySelector: () => null, querySelectorAll: () => [],
  createElement: () => makeEl(),
  addEventListener() {}, body: makeEl(), documentElement: makeEl(), hidden: false,
};
globalThis.localStorage = { getItem: () => null, setItem() {}, removeItem() {} };
globalThis.location = { reload() {} };
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
if (!globalThis.navigator) globalThis.navigator = { clipboard: { writeText: async () => {} } };
globalThis.fetch = async (u) => {
  const p = String(u).split('?')[0];
  const resp = text => ({ ok: true, status: 200, text: async () => text, json: async () => JSON.parse(text) });
  if (p.endsWith('state.json')) return resp('{}');
  if (p.endsWith('ui_version.txt')) return resp('harness');
  const file = path.join(ROOT, p.replace(/^\.\//, ''));
  if (fs.existsSync(file)) return resp(fs.readFileSync(file, 'utf8'));
  return { ok: false, status: 404, text: async () => '', json: async () => { throw new Error('404'); } };
};
const hook = `\n;globalThis.__T = { bayesEntry, bayesReset, bayesApply, bayesCandSpec, bayesView,
  applyState, get state() { return state; }, get estimator() { return estimator; },
  getMeta: () => META_SETS, getVgc: () => VGC_CORPUS,
  dataReady: () => !!(POKEDB_PARSED && USAGE_SETS && META_SETS_LOADED) };\n`;
const tmp = ROOT + '/.bayes_sim_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);

const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
const blankBoosts = () => ({ atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 });
const spDist = (a, b) => STATS.reduce((s, k) => s + Math.abs((a[k] || 0) - (b[k] || 0)), 0);
const hpFirst = sp => (sp.hp || 0) >= 32 || (!(sp.def > 0) && !(sp.spd > 0));
const archetype = sp => {
  const bulk = (sp.hp || 0) + (sp.def || 0) + (sp.spd || 0);
  const off = (sp.atk || 0) + (sp.spa || 0) + (sp.spe || 0);
  if (bulk >= 24 && !hpFirst(sp)) return 'nonHpFirstBulk';
  if (bulk >= 24) return 'hpFirstBulk';
  if (off >= 48) return 'offense';
  return 'balanced';
};

try {
  const bundle = await import(url.pathToFileURL(ROOT + '/bundle.mjs').href);
  const { damageRolls, withCurHP, statTable } = bundle;
  const gen9 = bundle.Generations.get(9);
  const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
  const movePrio = mv => { try { return gen9.moves.get(idOf(mv))?.priority || 0; } catch { return 0; } };
  const moveInfo = mv => { try { return gen9.moves.get(idOf(mv)) || null; } catch { return null; } };
  const typesOf = spName => { try { return gen9.species.get(idOf(spName))?.types || []; } catch { return []; } };
  const effVs = (moveType, defSpecies) => {
    let e = 1;
    for (const t of typesOf(defSpecies)) {
      const td = gen9.types.get(idOf(t));
      const v = td && td.effectiveness ? td.effectiveness[moveType] : undefined;
      e *= (typeof v === 'number' ? v : 1);
    }
    return e;
  };
  const statVal = (spName, nature, sp, stat) => {
    const table = statTable(spName); if (!table) return null;
    if (stat === 'hp') { const r = table.hp.find(r => r.sp === (sp.hp || 0)); return r ? r.value : null; }
    const r = table[stat].find(r => r.nature === nature && r.sp === (sp[stat] || 0));
    return r ? r.value : null;
  };
  const megaFormeOf = spName => {
    try { const sd = gen9.species.get(idOf(spName)); return (sd?.otherFormes || []).find(f => f.includes('Mega')) || null; } catch { return null; }
  };

  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !(T.dataReady() && T.state.mine?.length === 6)) await new Promise(r => setTimeout(r, 100));
  if (!T.dataReady() || T.state.mine?.length !== 6) { console.log('SKIP: データ読み込みが完了しませんでした'); process.exit(0); }

  // ---- 材料: VGC チーム (teamId 単位) と自分の登録チーム ----
  const vgc = JSON.parse(fs.readFileSync(ROOT + '/data/vgc_pastes.json', 'utf8'));
  const byTeam = new Map();
  for (const s of vgc.sets || []) {
    if (!s.teamId || !s.sps) continue;
    if (!byTeam.has(s.teamId)) byTeam.set(s.teamId, []);
    byTeam.get(s.teamId).push(s);
  }
  const teams = [...byTeam.values()].filter(t => t.length === 6);
  if (teams.length < BATTLES) { console.log(`SKIP: 完全なチームが ${teams.length} 件しかありません`); process.exit(0); }
  const teamDeck = shuffle([...teams]); // 偏った連続使用を避ける: 重複なく配る
  const meta = T.getMeta();
  const origMetaSets = (meta && Array.isArray(meta.sets)) ? [...meta.sets] : [];
  const vgcAllSets = vgc.sets || [];

  const mySpecs = T.state.mine.map(spec => ({ ...spec, sp: { ...spec.sp }, moves: [...(spec.moves || [])] }));

  // 個体の戦闘状態を作る
  function makeFighter(spec, truth) {
    const maxHp = statVal(spec.species, spec.nature, spec.sp, 'hp');
    return {
      spec: { ...spec, sp: { ...spec.sp }, boosts: blankBoosts(), status: '', curHPPercent: 100 },
      truth: truth || null, maxHp, hp: maxHp, alive: true, entered: false,
      megaDone: false, sitrusUsed: false, movedThisTurn: null, actedOrder: -1,
    };
  }
  const specOfSet = s => {
    const isMega = !!(s.forme && s.forme.includes('Mega'));
    const baseSpecies = s.species;
    return {
      species: baseSpecies, nature: s.nature,
      sp: Object.fromEntries(STATS.map(k => [k, (s.sps && s.sps[k]) || 0])),
      item: s.item || '', ability: s.ability || '', moves: [...(s.moves || [])],
      mega: false, megaSpecies: isMega ? s.forme : (megaFormeOf(baseSpecies) && (s.item || '').endsWith('ite') ? megaFormeOf(baseSpecies) : undefined),
      curHPPercent: 100, boosts: blankBoosts(), status: '',
    };
  };
  // 選出スコア: 相手チームへの最良の通り + 素早さ。ジッター付きでランダム性を持たせる
  function selectFour(specs, foeSpecs) {
    const scored = specs.map(spec => {
      let sc = 0;
      for (const foe of foeSpecs) {
        let best = 0;
        for (const mv of spec.moves || []) {
          const mi = moveInfo(mv);
          if (!mi || !mi.basePower) continue;
          best = Math.max(best, effVs(mi.type, foe.species) * Math.min(mi.basePower, 120));
        }
        sc += best;
      }
      sc += (statVal(spec.species, spec.nature, spec.sp, 'spe') || 0) * 0.3;
      if (spec.megaSpecies) sc += 15;
      return { spec, sc: sc * (0.85 + rnd() * 0.3) };
    }).sort((a, b) => b.sc - a.sc);
    return { leads: [scored[0].spec, scored[1].spec], bench: [scored[2].spec, scored[3].spec] };
  }
  const WEATHER_AB = { 'Drought': 'Sun', 'Drizzle': 'Rain', 'Sand Stream': 'Sand', 'Snow Warning': 'Snow', 'Orichalcum Pulse': 'Sun', 'Hadron Engine': 'Electric' };
  const TERRAIN_AB = { 'Electric Surge': 'Electric', 'Psychic Surge': 'Psychic', 'Grassy Surge': 'Grassy', 'Misty Surge': 'Misty', 'Hadron Engine': 'Electric' };

  function safeRolls(a, d, mv, field) {
    try { const r = damageRolls(withCurHP(a), withCurHP(d), mv, field); if (r && r.rolls && r.rolls.length >= 8) return r.rolls; } catch {}
    try { const r = damageRolls(withCurHP(a), withCurHP(d), mv, {}); if (r && r.rolls) return r.rolls; } catch {}
    return null;
  }

  function runBattle(teamSets, battleIdx) {
    const oppSpecsAll = teamSets.map(specOfSet);
    const mySel = selectFour(mySpecs, oppSpecsAll);
    const oppSel = selectFour(oppSpecsAll, mySpecs);
    if (MERGE_VGC && meta) meta.sets = [...origMetaSets, ...vgcAllSets.filter(s => s.teamId !== (teamSets[0] && teamSets[0].teamId))];
    // 実経路の VGC_SETS からも真値チームを除外する (leave-one-team-out)
    if (T.getVgc()) T.getVgc().sets = vgcAllSets.filter(s => s.teamId !== (teamSets[0] && teamSets[0].teamId));
    T.bayesReset();
    if (T.estimator?.setTeamContext) T.estimator.setTeamContext(oppSpecsAll.map(s => s.species));
    // --- PBS 並走: 同じ LOTO 条件で候補プールを作り、同じ証拠を流す ---
    const pbsPools = buildPools(vgcAllSets, { excludeTeamIds: new Set([teamSets[0] && teamSets[0].teamId]), cap: 60, keyFn: s => s.species });
    const pbs = createPbs(pbsPools, {});
    pbs.setPreview(oppSpecsAll.map(s => s.species));
    const pbsTracked = new Map(); // opp fighter -> { entryTurn, rows: [] }
    const toEstSpec = (spec, formeName) => ({ forme: formeName, species: spec.species, nature: spec.nature, sps: spec.sp, item: spec.item || null, ability: spec.ability || null, moves: spec.moves || [] });

    const mkSide = (sel, isOpp) => ({
      actives: sel.leads.map(sp => makeFighter(sp, isOpp ? sp : null)),
      bench: sel.bench.map(sp => makeFighter(sp, isOpp ? sp : null)),
      isOpp, megaUsed: false,
    });
    const mine = mkSide(mySel, false), opp = mkSide(oppSel, true);
    const field = {};
    const tracked = new Map(); // opp fighter -> { truth, ent, base, rows: [], entryTurn }
    const effName = f => (f.spec.mega && f.spec.megaSpecies) ? f.spec.megaSpecies : f.spec.species;
    const truthOf = f => f.truth;
    function onEnter(f, turn) {
      f.entered = true;
      const ab = f.spec.ability;
      if (WEATHER_AB[ab]) field.weather = WEATHER_AB[ab];
      if (TERRAIN_AB[ab]) field.terrain = TERRAIN_AB[ab];
      if (f.truth && !tracked.has(f)) {
        const ent = T.bayesEntry(f.spec.species);
        if (ent) tracked.set(f, { ent, rows: [], entryTurn: turn, exactIdx: -1, knownMoves: [] });
      }
      if (f.truth && !pbsTracked.has(f)) { try { pbs.entry(f.spec.species); } catch {} pbsTracked.set(f, { entryTurn: turn, rows: [] }); }
      // 登場時に表示される特性は判明情報として流す (本番の applyRevealed 経路)
      if (REVEALED && tracked.has(f) && ENTRY_AB.has(f.spec.ability)) feedReveal(f, null, f.spec.ability);
    }
    // 判明情報の投入: item / ability のどちらか (または両方) が観測で確定した時に呼ぶ
    function feedReveal(f, item, ability) {
      if (!REVEALED) return;
      const tr = tracked.get(f); if (!tr) return;
      const corrected = [];
      if (item) corrected.push('持ち物');
      if (ability) corrected.push('特性');
      if (!corrected.length) return;
      try {
        T.estimator.applyRevealed([{ species: f.spec.species, knownMoves: [...tr.knownMoves], itemLost: false,
          item: item || '', ability: ability || '', corrected, mega: !!f.spec.mega }]);
      } catch {}
      try { pbs.reveal(f.spec.species, { item: item || undefined, ability: ability || undefined }); } catch {}
    }
    for (const f of [...mine.actives, ...opp.actives]) onEnter(f, 0);

    const baseFor = f => ({ species: f.spec.species, nature: 'Serious', sp: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, item: '', ability: '', moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '', mega: !!f.spec.mega, megaSpecies: f.spec.megaSpecies });
    const tVals = f => {
      const name = effName(f), t = truthOf(f);
      const v = {};
      for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) v[k] = statVal(name, t.nature, t.sp, k);
      v.hp = statVal(f.spec.species, t.nature, t.sp, 'hp');
      return v;
    };
    function feedMyAttack(atkF, defF, mv, rollAbs) {
      const tr = tracked.get(defF); if (!tr) return;
      const tv = tVals(defF); if (!tv.hp) return;
      const pct = Math.round(rollAbs / tv.hp * 100);
      if (!(pct > 0)) return;
      const base = baseFor(defF);
      const counts = tr.ent.cands.map(c => {
        const hpVal = (defF.spec.mega && c.valuesMega) ? c.valuesMega.hp : c.values.hp; if (!hpVal) return 0;
        const r2 = safeRolls(atkF.spec, T.bayesCandSpec(base, c), mv, field); if (!r2) return 0;
        let n = 0; for (const r of r2) if (r > 0 && (Math.round(r / hpVal * 100) === pct || Math.floor(r / hpVal * 100) === pct)) n++;
        return n;
      });
      T.bayesApply(tr.ent, counts, true);
    }
    function feedOppAttack(atkF, defF, mv, amt) {
      const tr = tracked.get(atkF); if (!tr) return;
      const base = baseFor(atkF);
      const counts = tr.ent.cands.map(c => {
        const r2 = safeRolls(T.bayesCandSpec(base, c), defF.spec, mv, field); if (!r2) return 0;
        return r2.filter(r => r === amt).length;
      });
      T.bayesApply(tr.ent, counts, true);
    }
    function snapshot(f, turn) {
      const tr = tracked.get(f); if (!tr) return;
      const t = truthOf(f);
      if (tr.exactIdx === -2) return;
      if (tr.exactIdx === -1) tr.exactIdx = tr.ent.cands.findIndex(c => c.nature === t.nature && c.item === t.item && c.ability === t.ability && spDist(c.sp, t.sp) === 0);
      const sorted = [...tr.ent.cands].sort((a, b) => b.post - a.post);
      const map = sorted[0];
      let nearest = null, nearestRank = null;
      { let best = Infinity; for (const c of tr.ent.cands) { const d = spDist(c.sp, t.sp) + (c.nature === t.nature ? 0 : 0.5) + (c.item === t.item ? 0 : 0.25); if (d < best) { best = d; nearest = c; } } nearestRank = sorted.indexOf(nearest) + 1; }
      const view = T.bayesView({ species: f.spec.species, mega: !!f.spec.mega, megaSpecies: f.spec.megaSpecies, knownMoves: [] });
      let spCover = null, spWidth = null;
      if (view && view.sp) {
        let cs = 0, w = 0;
        for (const k of STATS) { const rs = view.sp[k]; if (Array.isArray(rs)) { if ((t.sp[k] || 0) >= rs[0] && (t.sp[k] || 0) <= rs[1]) cs++; w += rs[1] - rs[0]; } }
        spCover = cs / 6; spWidth = w / 6;
      }
      const natureHit = map.nature === t.nature, itemHit = map.item === t.item;
      const dist = spDist(map.sp, t.sp);
      tr.rows.push({
        turn: turn - tr.entryTurn, used: tr.ent.used,
        natureHit, itemHit, spDist: dist, mapNature: map.nature, mapItem: map.item,
        nearestRank, exactRank: tr.exactIdx >= 0 ? sorted.indexOf(tr.ent.cands[tr.exactIdx]) + 1 : null,
        spCover, spWidth: spWidth != null ? +spWidth.toFixed(2) : null,
        converged: natureHit && itemHit && dist <= 8,
      });
    }

    function snapshotPbs(f, turn) {
      const pt = pbsTracked.get(f); if (!pt) return;
      const t = truthOf(f);
      const view = pbs.view(f.spec.species);
      if (!view || !view.map) return;
      const map = view.map;
      const natureHit = map.nature === t.nature, itemHit = map.item === t.item;
      const dist = pbsSpDist(map.sps, t.sp);
      pt.rows.push({ turn: turn - pt.entryTurn, natureHit, itemHit, spDist: dist, converged: natureHit && itemHit && dist <= 8 });
    }

    const SPREAD = new Set(['allAdjacentFoes', 'allAdjacent', 'allFoes', 'all']);
    function chooseAction(f, foes, side) {
      // 交代: HP が低く、控えに相性の良い個体がいる場合
      if (f.hp / f.maxHp < 0.25) {
        const alive = side.bench.filter(b => b.alive);
        if (alive.length && rnd() < 0.7) {
          const threat = g => Math.max(0, ...foes.filter(x => x.alive).map(foe => Math.max(0, ...(foe.spec.moves || []).map(mv => { const mi = moveInfo(mv); return mi && mi.basePower ? effVs(mi.type, g.spec.species) : 0; }))));
          const cur = threat(f);
          const best = alive.sort((a, b) => threat(a) - threat(b))[0];
          if (threat(best) < cur) return { type: 'switch', to: best };
        }
      }
      // メガシンカ: そのチームのメガ枠が未使用で、この個体がメガ可能なら原則メガする
      let mega = false;
      if (!side.megaUsed && f.spec.megaSpecies && !f.spec.mega) mega = true;
      const myTypes = typesOf(f.spec.species);
      let bestAct = null;
      for (const mv of f.spec.moves || []) {
        const mi = moveInfo(mv); if (!mi) continue;
        if (!mi.basePower) {
          const sc = mi.target === 'self' ? 4 : 16;
          if (!bestAct || sc > bestAct.score) bestAct = { type: 'move', move: mv, target: null, score: sc, spread: false, mega };
          continue;
        }
        const spread = SPREAD.has(mi.target);
        const targets = spread ? foes.filter(x => x.alive) : foes.filter(x => x.alive);
        for (const tgt of (spread ? [targets[0]] : targets)) {
          if (!tgt) continue;
          const eff = effVs(mi.type, effName(tgt));
          if (eff <= 0) continue;
          let sc = eff * Math.min(mi.basePower, 130) * (myTypes.includes(mi.type) ? 1.4 : 1) + (mi.priority || 0) * 30;
          sc *= 0.9 + rnd() * 0.2;
          if (!bestAct || sc > bestAct.score) bestAct = { type: 'move', move: mv, target: tgt, score: sc, spread, mega };
        }
      }
      return bestAct || { type: 'move', move: (f.spec.moves || [])[0], target: foes.find(x => x.alive), score: 0, spread: false, mega };
    }

    for (const f of [...opp.actives]) { snapshot(f, 0); snapshotPbs(f, 0); }
    let winner = null;
    for (let turn = 1; turn <= TURNS; turn++) {
      const sides = [mine, opp];
      // 交代と行動の決定
      const actions = [];
      for (const side of sides) {
        const foes = (side === mine ? opp : mine).actives;
        side.actives.forEach((f, slot) => { if (f.alive) actions.push({ f, side, slot, act: chooseAction(f, foes, side) }); });
      }
      // 交代の解決
      for (const a of actions.filter(a => a.act.type === 'switch')) {
        const idx = a.side.bench.indexOf(a.act.to);
        if (idx < 0) continue;
        a.side.bench[idx] = a.f;
        a.side.actives[a.slot] = a.act.to;
        onEnter(a.act.to, turn);
        a.f = a.act.to; a.act = { type: 'wait' };
      }
      // メガシンカの適用
      for (const a of actions) {
        if (a.act.mega && a.f.spec.megaSpecies && !a.side.megaUsed) {
          a.f.spec = { ...a.f.spec, mega: true, ability: (gen9.species.get(idOf(a.f.spec.megaSpecies))?.abilities?.[0]) || a.f.spec.ability };
          a.side.megaUsed = true; a.f.megaDone = true;
          // メガシンカで特性が表示されるため判明情報として流す
          if (a.f.truth) feedReveal(a.f, null, a.f.spec.ability);
        }
      }
      // 行動順: 優先度 → 実効素早さ (スカーフのみ概算) → ランダム
      const effSpe = f => { const v = statVal(effName(f), f.spec.nature, f.spec.sp, 'spe') || 0; return f.spec.item === 'Choice Scarf' ? Math.floor(v * 1.5) : v; };
      const movers = actions.filter(a => a.act.type === 'move' && a.f.alive);
      movers.sort((x, y) => (movePrio(y.act.move) - movePrio(x.act.move)) || (effSpe(y.f) - effSpe(x.f)) || (rnd() - 0.5));
      movers.forEach((a, i) => { a.f.actedOrder = i; a.f.movedThisTurn = a.act.move; });
      // 技の実行
      for (const a of movers) {
        if (!a.f.alive) continue;
        // 技判明: 相手が技を使うたびに、判明済み技集合の差分更新を流す (本番の moveUpdate 経路)
        if (MOVESEEN && a.side === opp && a.f.truth) {
          const tr = tracked.get(a.f);
          if (tr && !tr.knownMoves.includes(a.act.move)) {
            tr.knownMoves.push(a.act.move);
            try { T.estimator.moveUpdate(tr.ent, a.f.spec.species, [...tr.knownMoves]); } catch {}
          }
        }
        // PBS: 行動による更新は技を使うたびに流す (設計どおり)
        if (a.side === opp && a.f.truth) {
          try { pbs.action(a.f.spec.species, a.act.move, a.act.target ? effName(a.act.target) : effName(mine.actives.find(x => x.alive) || mine.actives[0])); } catch {}
        }
        const foeSide = a.side === mine ? opp : mine;
        let targets = [];
        if (a.act.spread) targets = foeSide.actives.filter(x => x.alive);
        else if (a.act.target && a.act.target.alive) targets = [a.act.target];
        else targets = foeSide.actives.filter(x => x.alive).slice(0, 1);
        for (const tgt of targets) {
          const rolls = safeRolls(a.f.spec, tgt.spec, a.act.move, field);
          if (!rolls || !rolls.length || Math.max(...rolls) <= 0) continue;
          let roll = rolls[rndInt(rolls.length)];
          if (a.act.spread) roll = Math.floor(roll * 0.75);
          if (roll <= 0) continue;
          tgt.hp = Math.max(0, tgt.hp - roll);
          tgt.spec.curHPPercent = Math.round(tgt.hp / tgt.maxHp * 100);
          if (a.side === mine && tgt.truth) feedMyAttack(a.f, tgt, a.act.move, roll);
          if (a.side === opp && a.f.truth) feedOppAttack(a.f, tgt, a.act.move, roll);
          if (a.side === mine && tgt.truth) { const pct = Math.round(roll / tgt.maxHp * 100); if (pct > 0) try { pbs.damageToPct(tgt.spec.species, a.act.move, toEstSpec(a.f.spec, effName(a.f)), pct); } catch {} }
          if (a.side === opp && a.f.truth) { try { pbs.damageBy(a.f.spec.species, a.act.move, toEstSpec(tgt.spec, effName(tgt)), roll, Infinity); } catch {} }
          if (a.f.spec.item === 'Life Orb') { a.f.hp = Math.max(1, a.f.hp - Math.floor(a.f.maxHp / 10)); }
          if (tgt.spec.item === 'Sitrus Berry' && !tgt.sitrusUsed && tgt.hp > 0 && tgt.hp / tgt.maxHp <= 0.5) {
            tgt.hp = Math.min(tgt.maxHp, tgt.hp + Math.floor(tgt.maxHp / 4)); tgt.sitrusUsed = true;
            tgt.spec.curHPPercent = Math.round(tgt.hp / tgt.maxHp * 100);
            // きのみを食べた時点で持ち物が判明する
            if (tgt.truth) feedReveal(tgt, 'Sitrus Berry', null);
          }
          if (tgt.hp <= 0) tgt.alive = false;
        }
      }
      // 行動順の証拠 (同優先度の技同士、相手 vs 自分の各ペア)
      for (const of of opp.actives) {
        if (!of.truth || !of.movedThisTurn) continue;
        const tr = tracked.get(of); if (!tr) continue;
        for (const mf of mine.actives) {
          if (!mf.movedThisTurn || movePrio(mf.movedThisTurn) !== movePrio(of.movedThisTurn)) continue;
          const myEff = effSpe(mf), tEff = effSpe(of);
          if (myEff === tEff) continue;
          const firstIsOpp = of.actedOrder < mf.actedOrder;
          if ((tEff > myEff) !== firstIsOpp) continue; // 観測と実効値が矛盾する場合は乱数同速等として扱わない
          try { pbs.speed(of.spec.species, firstIsOpp, myEff, movePrio(of.movedThisTurn), movePrio(mf.movedThisTurn)); } catch {}
          const verdicts = tr.ent.cands.map(c => {
            const cs0 = (of.spec.mega && c.valuesMega) ? c.valuesMega.spe : c.values.spe;
            const cs = c.item === 'Choice Scarf' && cs0 != null ? Math.floor(cs0 * 1.5) : cs0;
            if (cs == null || cs === myEff) return null;
            return firstIsOpp ? cs > myEff : cs < myEff;
          });
          let survivorMass = 0, excluded = 0;
          tr.ent.cands.forEach((c, i) => { if (verdicts[i] === false) { if (c.post > 0) excluded++; } else survivorMass += c.post; });
          if (survivorMass > 0 && excluded) {
            tr.ent.cands.forEach((c, i) => { if (verdicts[i] === false) c.post = 0; });
            for (const c of tr.ent.cands) c.post /= survivorMass;
            tr.ent.used++;
          }
        }
      }
      for (const f of [...mine.actives, ...opp.actives]) f.movedThisTurn = null;
      // 倒れた個体の交代
      for (const side of sides) {
        side.actives.forEach((f, slot) => {
          if (f.alive) return;
          const cand = side.bench.filter(b => b.alive);
          if (!cand.length) return;
          const foes = (side === mine ? opp : mine).actives.filter(x => x.alive);
          const threat = g => Math.max(0, ...foes.map(foe => Math.max(0, ...(foe.spec.moves || []).map(mv => { const mi = moveInfo(mv); return mi && mi.basePower ? effVs(mi.type, g.spec.species) : 0; }))));
          const best = cand.sort((a, b) => threat(a) - threat(b))[0];
          side.bench.splice(side.bench.indexOf(best), 1);
          side.actives[slot] = best;
          onEnter(best, turn);
        });
      }
      for (const f of [...opp.actives]) if (f.truth && tracked.has(f)) { snapshot(f, turn); snapshotPbs(f, turn); }
      const aliveCount = s => [...s.actives, ...s.bench].filter(f => f.alive).length;
      if (!aliveCount(mine) || !aliveCount(opp)) { winner = aliveCount(mine) ? 'mine' : 'opp'; break; }
    }
    const individuals = [];
    for (const [f, tr] of tracked) {
      const t = truthOf(f);
      let firstConverged = null;
      for (const r of tr.rows) if (r.converged) { firstConverged = r.turn; break; }
      individuals.push({ species: f.spec.species, archetype: archetype(t.sp), truth: { nature: t.nature, item: t.item, ability: t.ability, sp: t.sp }, firstConverged, rows: tr.rows });
    }
    const pbsIndividuals = [];
    for (const [f, pt] of pbsTracked) {
      const t = truthOf(f);
      let firstConverged = null;
      for (const r of pt.rows) if (r.converged) { firstConverged = r.turn; break; }
      pbsIndividuals.push({ species: f.spec.species, archetype: archetype(t.sp), firstConverged, rows: pt.rows });
    }
    return { battle: battleIdx, winner, individuals, pbsIndividuals };
  }

  // ---- 実行と集計 ----
  const results = [];
  for (let i = 0; i < BATTLES; i++) {
    const r = runBattle(teamDeck[i % teamDeck.length], i);
    if (r) results.push(r);
  }
  const allInd = results.flatMap(r => r.individuals);
  const perTurn = [];
  for (let t = 0; t <= TURNS; t++) {
    const rows = allInd.map(ind => ind.rows.find(r => r.turn === t)).filter(Boolean);
    if (!rows.length) { perTurn.push(null); continue; }
    const mean = xs => xs.reduce((s, x) => s + x, 0) / xs.length;
    const frac = xs => mean(xs.map(x => x ? 1 : 0));
    perTurn.push({
      turn: t, n: rows.length,
      natureHit: +frac(rows.map(r => r.natureHit)).toFixed(3), itemHit: +frac(rows.map(r => r.itemHit)).toFixed(3),
      spDist: +mean(rows.map(r => r.spDist)).toFixed(1),
      nearestRank: +mean(rows.map(r => r.nearestRank || 99)).toFixed(2),
      spCover: (() => { const v = rows.map(r => r.spCover).filter(x => x != null); return v.length ? +mean(v).toFixed(3) : null; })(),
      converged: +frac(rows.map(r => r.converged)).toFixed(3),
    });
  }
  const arch = {};
  for (const ind of allInd) {
    arch[ind.archetype] = arch[ind.archetype] || { n: 0, conv: 0, distSum: 0 };
    const a = arch[ind.archetype];
    a.n++; if (ind.firstConverged !== null) a.conv++;
    const last = ind.rows[ind.rows.length - 1]; if (last) a.distSum += last.spDist;
  }
  console.log(`== M-C ダブル模擬対戦 (seed ${SEED} / ${results.length} 試合 / チーム数 ${teams.length} / merge-vgc=${MERGE_VGC ? 1 : 0}) ==`);
  console.log('経過T | n | 性格一致 | 持ち物一致 | SP距離 | 最寄り順位 | SP区間カバー | 収束率');
  for (const p of perTurn) if (p) console.log(`${String(p.turn).padStart(4)} | ${p.n} | ${p.natureHit.toFixed(3)} | ${p.itemHit.toFixed(3)} | ${String(p.spDist).padStart(5)} | ${p.nearestRank} | ${p.spCover} | ${p.converged.toFixed(3)}`);
  console.log('— アーキタイプ別 —');
  for (const [k, a] of Object.entries(arch)) console.log(`  ${k}: n=${a.n} 収束 ${a.conv}/${a.n} 最終SP距離平均=${(a.distSum / a.n).toFixed(1)}`);
  // ---- PBS 並走の集計 (本番と同一の収束定義) ----
  const allPbs = results.flatMap(r => r.pbsIndividuals || []);
  const mean2 = xs => xs.reduce((s, x) => s + x, 0) / xs.length;
  console.log(`\n== PBS 並走 (同ハーネス・同証拠・同収束定義) ==`);
  console.log('経過T | n | 性格一致 | 持ち物一致 | SP距離 | 収束率');
  for (let t = 0; t <= TURNS; t++) {
    const rows = allPbs.map(ind => ind.rows.find(r => r.turn === t)).filter(Boolean);
    if (!rows.length) continue;
    console.log(`${String(t).padStart(4)} | ${rows.length} | ${mean2(rows.map(r => r.natureHit ? 1 : 0)).toFixed(3)} | ${mean2(rows.map(r => r.itemHit ? 1 : 0)).toFixed(3)} | ${String(mean2(rows.map(r => r.spDist)).toFixed(1)).padStart(5)} | ${mean2(rows.map(r => r.converged ? 1 : 0)).toFixed(3)}`);
  }
  const everConv = inds => inds.length ? inds.filter(i => i.firstConverged !== null).length / inds.length : 0;
  console.log(`\n== 直接比較 (seed ${SEED} / ${results.length} 試合) ==`);
  console.log(`一度でも収束した個体の割合: 本番=${everConv(allInd).toFixed(3)} (${allInd.filter(i => i.firstConverged !== null).length}/${allInd.length})  PBS=${everConv(allPbs).toFixed(3)} (${allPbs.filter(i => i.firstConverged !== null).length}/${allPbs.length})`);
  const archP = {};
  for (const ind of allPbs) {
    archP[ind.archetype] = archP[ind.archetype] || { n: 0, conv: 0, distSum: 0 };
    const a = archP[ind.archetype];
    a.n++; if (ind.firstConverged !== null) a.conv++;
    const last = ind.rows[ind.rows.length - 1]; if (last) a.distSum += last.spDist;
  }
  console.log('— アーキタイプ別 (PBS) —');
  for (const [k, a] of Object.entries(archP)) console.log(`  ${k}: n=${a.n} 収束 ${a.conv}/${a.n} 最終SP距離平均=${(a.distSum / a.n).toFixed(1)}`);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify({ config: { seed: SEED, battles: results.length, turns: TURNS, mergeVgc: MERGE_VGC }, perTurn, archetypes: arch, battles: results }, null, 1));
  console.log('詳細記録:', path.relative(ROOT, OUT));
} catch (e) {
  console.log('ERROR', e && e.stack || e);
  process.exit(1);
}

process.exit(0);
