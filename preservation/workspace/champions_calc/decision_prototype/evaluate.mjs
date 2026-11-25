// evaluate.mjs — decisions.json の実判断と叩き台の選択の一致度を測る
// 簡略化（叩き台の前提として明記）:
// - ランク変化は decisions.json に含まれないため 0 として評価する
// - 地形は decisions.json に含まれないため無しとして評価する
// - 控えの現在HPは、最後に場で確認された HP% を引き継ぐ。場から消えて交代行動も無い場合は瀕死と推定する
// - セット: 公開シートがある試合は実セット、それ以外は VGCPastes 統計の最頻セット（sets.mjs）で両軍とも補う。SP は全件、最頻 SP パターン
import { readFileSync } from 'node:fs';
import { decide, slotActions, toID } from './decision_engine.mjs';
import { completeSet, assumedSet } from './sets.mjs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const data = JSON.parse(readFileSync(new URL('./decisions.json', import.meta.url), 'utf8'));
const replays = Array.isArray(data) ? data : data.replays;

const WEATHER_NORM = { RainDance: 'Rain', Rain: 'Rain', SunnyDay: 'Sun', Sun: 'Sun', Sandstorm: 'Sand', Sand: 'Sand', Snowscape: 'Snow', Snow: 'Snow', Hail: 'Snow', '': null, None: null, null: null };
const COND_MAP = { Reflect: 'reflect', 'Light Screen': 'lightScreen', 'Aurora Veil': 'auroraVeil', Tailwind: 'tailwind', 'Stealth Rock': 'stealthRock', Spikes: 'spikes', 'Toxic Spikes': 'toxicSpikes' };

function condsFrom(list) {
  const c = {};
  for (const name of list || []) { const k = COND_MAP[name]; if (k) c[k] = k === 'spikes' || k === 'toxicSpikes' ? 1 : true; }
  return c;
}

function buildSet(entry) {
  if (entry.moves && entry.moves.length) return completeSet(entry);
  return assumedSet(entry.species);
}

// 場の個体名がメガフォルム（例: Charizard-Mega-Y）の場合、素の種族のセットを引き継ぎ、
// 種族名と特性だけメガ側に差し替える
function resolveActiveSet(speciesName, teamMap) {
  if (teamMap[speciesName]) return teamMap[speciesName];
  const base = speciesName.replace(/-Mega(-[A-Z])?$/, '');
  const baseSet = teamMap[base];
  if (!baseSet) return assumedSet(speciesName);
  const sd = gen.species.get(toID(speciesName));
  return { ...baseSet, species: speciesName, ability: sd ? sd.abilities[0] : baseSet.ability };
}

function normTarget(actual, mySide) {
  const t = actual.target || '';
  if (actual.type === 'switch') return { kind: 'switch', to: actual.switchTo };
  const md = gen.moves.get(toID(actual.move));
  if (md && (md.target === 'allAdjacentFoes' || md.target === 'allAdjacent' || md.target === 'all')) return { kind: 'move', move: actual.move, target: 'spread' };
  if (md && md.target === 'self') return { kind: 'move', move: actual.move, target: 'self' };
  const m = /^p(\d)([ab])$/.exec(t);
  if (m) {
    const myNum = mySide === 'p1' ? 1 : 2;
    const slot = m[2] === 'a' ? 'A' : 'B';
    return { kind: 'move', move: actual.move, target: Number(m[1]) === myNum ? 'partnerOrSelf' : `opp${slot}` };
  }
  if (/spread|both|all/i.test(t)) return { kind: 'move', move: actual.move, target: 'spread' };
  if (/self/i.test(t)) return { kind: 'move', move: actual.move, target: 'self' };
  return { kind: 'move', move: actual.move, target: t };
}

function engineTarget(a) {
  if (!a) return { kind: 'none' };
  if (a.type === 'switch') return { kind: 'switch', to: a.switchTo };
  return { kind: 'move', move: a.move, target: a.target };
}

function matchLevel(pred, actual) {
  if (pred.kind !== actual.kind) return 'none';
  if (pred.kind === 'switch') return pred.to === actual.to ? 'exact' : 'category';
  if (toID(pred.move) !== toID(actual.move)) return 'category';
  if (pred.target === actual.target) return 'exact';
  if (actual.target === 'partnerOrSelf' && (pred.target === 'self' || pred.target === 'partner')) return 'exact';
  return 'moveOnly';
}

function newStats() { return { turns: 0, slots: 0, exact: 0, moveOnly: 0, category: 0, none: 0, top3: 0 }; }
const total = newStats(), openStats = newStats(), closedStats = newStats();
const byActualType = {};
const misses = [];

for (const rep of replays) {
  const S = rep.openTeamSheet ? openStats : closedStats;
  const mySets = Object.fromEntries(rep.mikumikuTeam.map((s) => [s.species, buildSet(s)]));
  const oppSets = Object.fromEntries(rep.opponentTeam.map((s) => [s.species, buildSet(s)]));
  const picked = rep.selection || [];
  const lastHp = {}, alive = {};
  let megaUsed = false;
  let prevActiveSpecies = [null, null];
  let justIn = new Set(rep.leads || []);

  rep.turns.forEach((turn, ti) => {
    const st = turn.state;
    const myAct = st.myActives.map((m) => (m ? { set: resolveActiveSet(m.species, mySets), hpPct: m.hpPct ?? lastHp[m.species] ?? 100, boosts: {}, status: '', firstTurnOut: justIn.has(m.species) } : null));
    const oppAct = st.oppActives.map((m) => (m ? { set: resolveActiveSet(m.species, oppSets), hpPct: m.hpPct ?? 100, boosts: {}, status: '', firstTurnOut: false } : null));
    if (st.myActives.some((m) => m && m.species.includes('-Mega'))) megaUsed = true;
    const activeSpecies = st.myActives.filter(Boolean).map((m) => m.species);
    const bench = [];
    for (const sp of picked) {
      if (activeSpecies.includes(sp)) continue;
      let isAlive = alive[sp] !== false;
      const wasActive = prevActiveSpecies.includes(sp);
      const switchedOut = turn.actions.some((a) => a.type === 'switch' && prevActiveSpecies[a.slot === 'a' ? 0 : 1] === sp);
      if (wasActive && !switchedOut && ti > 0) isAlive = false;
      bench.push({ set: mySets[sp], hpPct: lastHp[sp] ?? 100, boosts: {}, status: '', firstTurnOut: false, alive: isAlive });
    }
    const state = {
      turn: ti + 1,
      field: { weather: WEATHER_NORM[st.weather] ?? null, terrain: null, trickRoom: !!st.trickRoom },
      me: { actives: myAct, bench, conditions: condsFrom(st.mySideConditions) },
      opp: { actives: oppAct, bench: [], conditions: condsFrom(st.oppSideConditions) },
      megaUsed: { me: megaUsed, opp: false },
    };
    let result, slotActs;
    try {
      result = decide(state);
      slotActs = [state.me.actives[0] ? slotActions(state.me.actives[0], 0, state) : [], state.me.actives[1] ? slotActions(state.me.actives[1], 1, state) : []];
    } catch (e) {
      console.error(`decide failed: ${rep.id} T${ti + 1}: ${e.message}`);
      return;
    }
    total.turns++; S.turns++;
    // スロットごとに評価対象を1つに絞る: 瀕死交代の「交代」と同ターンの「技」が併記される場合は技を、
    // 交代が複数ある場合は最後のものを、そのターンの判断として扱う
    const evalActions = [];
    for (const slotName of ['a', 'b']) {
      const acts = turn.actions.filter((x) => x.slot === slotName);
      if (!acts.length) continue;
      const mv = acts.filter((x) => x.type === 'move');
      evalActions.push(mv.length ? mv[mv.length - 1] : acts[acts.length - 1]);
    }
    for (const act of evalActions) {
      const si = act.slot === 'a' ? 0 : 1;
      if (!state.me.actives[si]) continue;
      const pred = si === 0 ? result.pair.a : result.pair.b;
      if (!pred) continue;
      const actual = normTarget(act, rep.mikumikuSide);
      const lvl = matchLevel(engineTarget(pred), actual);
      for (const T of [total, S]) { T.slots++; T[lvl]++; }
      const key = act.type === 'switch' ? 'switch' : act.move;
      byActualType[key] = byActualType[key] || { n: 0, exact: 0 };
      byActualType[key].n++; if (lvl === 'exact') byActualType[key].exact++;
      const top3 = slotActs[si].slice(0, 3).map(engineTarget);
      if (top3.some((p) => matchLevel(p, actual) === 'exact')) { total.top3++; S.top3++; }
      else if (misses.length < 16) misses.push({ replay: rep.id, turn: ti + 1, slot: act.slot, actual: JSON.stringify(actual), predicted: JSON.stringify(engineTarget(pred)) });
      if (act.mega) megaUsed = true;
    }
    st.myActives.forEach((m) => { if (m) { lastHp[m.species] = m.hpPct; alive[m.species] = (m.hpPct ?? 100) > 0; } });
    prevActiveSpecies = activeSpecies.concat([null, null]).slice(0, 2);
    justIn = new Set(turn.actions.filter((a) => a.type === 'switch').map((a) => a.switchTo));
  });
}

function report(name, s) {
  if (!s.slots) { console.log(`${name}: 対象なし`); return; }
  console.log(`${name}: ${s.slots} 行動 / 完全一致 ${(s.exact / s.slots * 100).toFixed(1)}% / 技のみ一致 ${(s.moveOnly / s.slots * 100).toFixed(1)}% / 種別のみ ${(s.category / s.slots * 100).toFixed(1)}% / 不一致 ${(s.none / s.slots * 100).toFixed(1)}% / 上位3候補に実行動 ${(s.top3 / s.slots * 100).toFixed(1)}%`);
}
console.log(`対象: ${replays.length} 試合 / ${total.turns} ターン`);
report('全体', total);
report('公開シートあり（実セット）', openStats);
report('公開シートなし（想定セット）', closedStats);
console.log('行動別の完全一致率（n>=3）:');
for (const [k, v] of Object.entries(byActualType).filter(([, v]) => v.n >= 3).sort((a, b) => b[1].n - a[1].n)) {
  console.log(`  ${k}: ${v.exact}/${v.n} (${(v.exact / v.n * 100).toFixed(0)}%)`);
}
console.log('不一致の例:');
for (const m of misses) console.log(`  ${m.replay} T${m.turn} slot${m.slot}: 実際=${m.actual} / 予測=${m.predicted}`);
