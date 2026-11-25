// PBS プロトタイプの LOTO 評価ハーネス。
// VGCPastes の実在チームを真の相手チームとし、その teamId を候補プールから
// 除外 (Leave-One-Team-Out) したうえで、ダブルバトルの証拠ストリームを
// ベースライン (現行エンジン相当の近似) と PBS 版へ同一に流し、ターン毎の
// 推定品質を比較する。簡略化: メガシンカ進化・天候特性・反動・道具の
// 一部発動は未再現 (DESIGN.md §9)。
// 使い方: node eval_pbs.mjs [--battles 30] [--turns 10] [--seed 1]
import fs from 'fs';
import path from 'path';
import url from 'url';
import { buildPools, createBaseline, createPbs, rolls, maxHp, effSpe, spDist, statVal } from './estimators.mjs';
import { Generations } from '../bundle.mjs';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : d; };
const BATTLES = parseInt(opt('battles', '30'), 10);
const TURNS = parseInt(opt('turns', '10'), 10);
const SEED = parseInt(opt('seed', '1'), 10);

let rngState = SEED >>> 0;
const rnd = () => { rngState = (rngState + 0x6D2B79F5) >>> 0; let t = rngState; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const rndInt = n => Math.floor(rnd() * n);
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = rndInt(i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };

const gen9 = Generations.get(9);
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
const moveInfo = mv => { try { return gen9.moves.get(idOf(mv)); } catch { return null; } };
const ENTRY_AB = new Set(['Intimidate', 'Drought', 'Drizzle', 'Sand Stream', 'Snow Warning', 'Electric Surge', 'Grassy Surge', 'Misty Surge', 'Psychic Surge', 'Download', 'Orichalcum Pulse', 'Hadron Engine', 'Dauntless Shield', 'Intrepid Sword', 'Slow Start', 'Screen Cleaner']);

const corpus = JSON.parse(fs.readFileSync(path.join(ROOT, 'data/vgc_pastes.json'), 'utf8'));
corpus.sets = corpus.sets.map(s => ({ ...s, forme: s.forme || s.species }));
const teamsMap = new Map();
for (const s of corpus.sets) {
  if (!s.teamId) continue;
  if (!teamsMap.has(s.teamId)) teamsMap.set(s.teamId, []);
  teamsMap.get(s.teamId).push(s);
}
const teams = [...teamsMap.entries()]
  .filter(([, sets]) => sets.length === 6 && new Set(sets.map(s => s.forme)).size === 6)
  .map(([teamId, sets]) => ({ teamId, sets }));
const ourTeam = teams[0];
const truthPool = teams.slice(1);
console.log(`teams: ${teams.length} (ours: ${ourTeam.teamId})`);

const KINDS = ['baseline', 'pbs', 'pbsNoAct'];
const metrics = {};
for (const k of KINDS) metrics[k] = Array.from({ length: TURNS + 1 }, () => ({ n: 0, sp: 0, nature: 0, item: 0, massNear: 0 }));

function record(kind, est, truth, turnIdx) {
  const cands = est.entry(truth.forme);
  if (!cands.length) return;
  const view = est.view(truth.forme);
  const m = metrics[kind][turnIdx];
  m.n++;
  m.sp += spDist(view.map.sps, truth.sps);
  if (view.map.nature === truth.nature) m.nature++;
  if (view.map.item === truth.item) m.item++;
  m.massNear += cands.filter(c => spDist(c.sps, truth.sps) <= 8 && c.nature === truth.nature)
    .reduce((s, c) => s + c.p, 0);
}

function pickAction(me, foes) {
  const dmg = (me.build.moves || []).filter(mv => { const i = moveInfo(mv); return i && (i.category === 'Physical' || i.category === 'Special') && (i.basePower || 0) > 0; });
  if (me.build.moves?.includes('Protect') && rnd() < 0.12) return { move: 'Protect', target: null };
  if (!dmg.length) return { move: me.build.moves?.[0] || 'Struggle', target: foes[0] || null };
  let best = null;
  for (const mv of dmg) for (const t of foes) {
    const foeForme = t.build.forme;
    let eff = 1; const mi = moveInfo(mv);
    try {
      for (const dt of (gen9.species.get(idOf(foeForme))?.types || [])) {
        const td = gen9.types.get(idOf(dt)); const v = td?.effectiveness?.[mi.type];
        eff *= (typeof v === 'number' ? v : 1);
      }
    } catch {}
    const score = eff * (mi.basePower || 0) * (0.8 + rnd() * 0.4);
    if (!best || score > best.score) best = { move: mv, target: t, score };
  }
  return best;
}

function runBattle(truthTeam) {
  const pools = buildPools(corpus.sets, { excludeTeamIds: new Set([truthTeam.teamId, ourTeam.teamId]), cap: 60 });
  const ests = {
    baseline: createBaseline(pools),
    pbs: createPbs(pools, {}),
    pbsNoAct: createPbs(pools, { actionChannel: false }),
  };
  const preview = truthTeam.sets.map(s => s.forme);
  ests.pbs.setPreview(preview); ests.pbsNoAct.setPreview(preview);

  const mkSide = sets => shuffle(sets.slice()).slice(0, 4).map(b => ({ build: b, hp: maxHp(b.forme, b.sps) || 150, max: maxHp(b.forme, b.sps) || 150, entered: false, itemRevealed: false }));
  const mine = mkSide(ourTeam.sets);
  const opp = mkSide(truthTeam.sets);
  const act = { mine: mine.slice(0, 2), opp: opp.slice(0, 2) };
  const bench = { mine: mine.slice(2), opp: opp.slice(2) };
  const enteredOpp = new Set();

  const onEnter = (mon, isOpp) => {
    mon.entered = true;
    if (isOpp) {
      enteredOpp.add(mon.build.forme);
      if (ENTRY_AB.has(mon.build.ability)) for (const k of KINDS) ests[k].reveal(mon.build.forme, { ability: mon.build.ability });
    }
  };
  act.mine.forEach(m => onEnter(m, false));
  act.opp.forEach(m => onEnter(m, true));
  for (const mon of act.opp) for (const k of KINDS) record(k, ests[k], mon.build, 0);

  for (let turn = 0; turn < TURNS; turn++) {
    const sides = [
      { me: act.mine, foes: act.opp, isOpp: false },
      { me: act.opp, foes: act.mine, isOpp: true },
    ];
    const actions = [];
    for (const s of sides) for (let i = 0; i < s.me.length; i++) {
      const mon = s.me[i]; if (!mon || mon.hp <= 0) continue;
      const foesAlive = s.foes.filter(f => f && f.hp > 0);
      if (!foesAlive.length) continue;
      const a = pickAction(mon, foesAlive);
      const mi = moveInfo(a.move);
      actions.push({ mon, side: s, slot: i, move: a.move, target: a.target, prio: mi?.priority || 0,
        spe: effSpe(mon.build.forme, mon.build.nature, mon.build.sps, mon.build.item) || 0, order: 0 });
    }
    actions.sort((a, b) => (b.prio - a.prio) || (b.spe - a.spe) || (rnd() - 0.5));
    actions.forEach((a, i) => a.order = i);
    const actedOrder = new Map(actions.map(a => [a.mon, a]));

    // 行動順の証拠 (同優先度・両者行動した場合のみ、スロット対応)
    for (let i = 0; i < 2; i++) {
      const o = act.opp[i], m = act.mine[i];
      if (!o || !m) continue;
      const ao = actedOrder.get(o), am = actedOrder.get(m);
      if (!ao || !am || ao.prio !== am.prio) continue;
      const oSpe = effSpe(o.build.forme, o.build.nature, o.build.sps, o.build.item);
      const mSpe = effSpe(m.build.forme, m.build.nature, m.build.sps, m.build.item);
      if (oSpe == null || mSpe == null || oSpe === mSpe) continue;
      for (const k of KINDS) ests[k].speed(o.build.forme, ao.order < am.order, mSpe, ao.prio, am.prio);
    }

    for (const a of actions) {
      if (a.mon.hp <= 0 || !a.target || a.target.hp <= 0) continue;
      const atkB = a.mon.build, tgt = a.target, tgtB = tgt.build;
      if (a.side.isOpp) {
        for (const k of KINDS) { if (k === 'baseline') ests[k].moveSeen(atkB.forme, a.move); else ests[k].action(atkB.forme, a.move, tgtB.forme); }
      }
      const rs = rolls(atkB, tgtB, a.move);
      if (!rs.length) continue;
      const dmg = rs[rndInt(rs.length)];
      const hpBefore = tgt.hp;
      let dealt = Math.min(dmg, hpBefore);
      let sashSaved = false;
      if (tgtB.item === 'Focus Sash' && hpBefore > 1 && dmg >= hpBefore) { dealt = hpBefore - 1; sashSaved = true; }
      tgt.hp -= dealt;
      if (a.side.isOpp) {
        // 相手→自軍: 実数ダメージ
        for (const k of KINDS) ests[k].damageBy(atkB.forme, a.move, tgtB, dealt, hpBefore);
      } else {
        // 自軍→相手: 残り % の観測
        const prevPct = Math.floor(100 * hpBefore / tgt.max);
        const nowPct = Math.floor(100 * Math.max(0, tgt.hp) / tgt.max);
        for (const k of KINDS) ests[k].damageTo(tgtB.forme, a.move, atkB, prevPct, nowPct);
      }
      if (!a.side.isOpp) {
        if (sashSaved && !tgt.itemRevealed) { tgt.itemRevealed = true; for (const k of KINDS) ests[k].reveal(tgtB.forme, { item: 'Focus Sash' }); }
        if (tgtB.item === 'Sitrus Berry' && !tgt.itemRevealed && tgt.hp > 0 && hpBefore >= tgt.max / 2 && tgt.hp < tgt.max / 2) {
          tgt.itemRevealed = true; tgt.hp = Math.min(tgt.max, tgt.hp + Math.floor(tgt.max / 4));
          for (const k of KINDS) ests[k].reveal(tgtB.forme, { item: 'Sitrus Berry' });
        }
      }
    }

    // 交代 (ひんし→控え)
    for (const sname of ['mine', 'opp']) {
      for (let i = 0; i < act[sname].length; i++) {
        if (act[sname][i] && act[sname][i].hp <= 0) {
          const nxt = bench[sname].find(b => b.hp > 0);
          act[sname][i] = nxt || null;
          if (nxt) { bench[sname] = bench[sname].filter(b => b !== nxt); onEnter(nxt, sname === 'opp'); }
        }
      }
    }
    for (const mon of opp) if (enteredOpp.has(mon.build.forme)) {
      for (const k of KINDS) record(k, ests[k], mon.build, turn + 1);
    }
    if (!act.mine.some(m => m && m.hp > 0) && !bench.mine.some(m => m.hp > 0)) break;
    if (!act.opp.some(m => m && m.hp > 0) && !bench.opp.some(m => m.hp > 0)) break;
  }
}

for (let b = 0; b < BATTLES; b++) {
  const t = truthPool[rndInt(truthPool.length)];
  runBattle(t);
  if ((b + 1) % 10 === 0) console.log(`battle ${b + 1}/${BATTLES} done`);
}

console.log(`\n=== 結果 (battles=${BATTLES}, turns=${TURNS}, seed=${SEED}) ===`);
for (const k of KINDS) {
  console.log(`\n[${k}]`);
  console.log('turn | n | MAP SP距離 | 性格一致 | 持ち物一致 | 真型近傍の事後質量');
  for (let t = 0; t <= TURNS; t++) {
    const m = metrics[k][t];
    if (!m.n) continue;
    console.log(`${t === 0 ? '事前' : t} | ${m.n} | ${(m.sp / m.n).toFixed(1)} | ${(100 * m.nature / m.n).toFixed(1)}% | ${(100 * m.item / m.n).toFixed(1)}% | ${(m.massNear / m.n).toFixed(3)}`);
  }
}
