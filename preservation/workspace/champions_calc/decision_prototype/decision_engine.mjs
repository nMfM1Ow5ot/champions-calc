// decision_engine.mjs — 判断エンジンの叩き台 (v0)
// 参考: Pokémon Showdown Reg M-C ラダー首位の mikumiku37 の公開リプレイから抽出した判断方針。
// 方針は patterns.md に集計し、ここの重みはその観察に合わせて調整する前提で置いてある。
//
// 入力 state:
// {
//   turn: Number,
//   field: { weather: 'Rain'|'Sun'|'Sand'|'Snow'|null, terrain: String|null, trickRoom: Boolean },
//   me:  Side, opp: Side,
//   megaUsed: { me: Boolean, opp: Boolean }  // 任意
// }
// Side = {
//   actives: [Mon|null, Mon|null],   // スロット a, b
//   bench: [Mon],                    // 控え（alive=false は瀕死）
//   conditions: { reflect, lightScreen, auroraVeil, tailwind, stealthRock, spikes, toxicSpikes }
// }
// Mon = {
//   set: { species, item, ability, nature, evs:{hp,atk,def,spa,spd,spe}, moves:[String] },
//   hpPct: 0-100, boosts: {atk,def,spa,spd,spe}, status: ''|'brn'|'par'|..., firstTurnOut: Boolean
// }
//
// 出力: { pair: {a: Action, b: Action|null, total, parts}, alternatives: [pair...] }
// Action = { type:'move', slot, move, target:'oppA'|'oppB'|'spread'|'self'|'partner'|'oppSide'|'mySide', mega, score, parts }
//        | { type:'switch', slot, switchTo, score, parts }
import { Generations, Pokemon, Move, Field, Side, calculate } from '@smogon/calc';

const gen = Generations.get(9);
export const toID = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');
const moveData = (name) => gen.moves.get(toID(name));
const speciesData = (name) => gen.species.get(toID(name));

// ---------- 基本ユーティリティ ----------

const BOOST_MULT = { '-6': 2 / 8, '-5': 2 / 7, '-4': 2 / 6, '-3': 2 / 5, '-2': 2 / 4, '-1': 2 / 3, '0': 1, '1': 3 / 2, '2': 2, '3': 5 / 2, '4': 3, '5': 7 / 2, '6': 4 };

function toPokemon(mon) {
  const s = mon.set;
  const p = new Pokemon(gen, s.species, {
    item: s.item, ability: s.ability, nature: s.nature, evs: s.evs,
    ivs: { hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31 },
    level: 50, boosts: mon.boosts || {}, status: mon.status || '',
  });
  const cur = Math.max(0, Math.round((p.maxHP() * (mon.hpPct ?? 100)) / 100));
  try { p.hp = cur; } catch { /* noop */ }
  try { p.originalCurHP = cur; } catch { /* noop */ }
  return p;
}

function sideForCalc(conds = {}) {
  return new Side({
    isReflect: !!conds.reflect, isLightScreen: !!conds.lightScreen,
    isAuroraVeil: !!conds.auroraVeil, isTailwind: !!conds.tailwind,
    isSR: !!conds.stealthRock, spikes: conds.spikes || 0,
  });
}

const WEATHER_MAP = { Rain: 'Rain', HeavyRain: 'Rain', Sun: 'Sun', 'Harsh Sunshine': 'Sun', Sand: 'Sand', Sandstorm: 'Sand', Snow: 'Snow', Hail: 'Snow' };

// ダメージ計算: {minPct, maxPct, avgPct, koChance} を返す（対象の現在HPに対する割合ではなく最大HP比）
function damageInfo(atkMon, defMon, moveName, ctx, atkConds, defConds) {
  const atk = toPokemon(atkMon);
  const def = toPokemon(defMon);
  const field = new Field({
    gameType: 'Doubles',
    weather: WEATHER_MAP[ctx.weather] || undefined,
    terrain: ctx.terrain || undefined,
    attackerSide: sideForCalc(atkConds), defenderSide: sideForCalc(defConds),
  });
  const res = calculate(gen, atk, def, new Move(gen, moveName), field);
  const maxHP = res.defender.maxHP();
  const curHP = Math.max(1, Math.round((maxHP * (defMon.hpPct ?? 100)) / 100));
  let rolls;
  const d = res.damage;
  if (Array.isArray(d) && d.length && Array.isArray(d[0])) rolls = d.flat();
  else if (Array.isArray(d)) rolls = d;
  else rolls = [d];
  // マルチスケイルは満タン時に半減（ロール単位で近似）
  if (defMon.set.ability === 'Multiscale' && (defMon.hpPct ?? 100) >= 99) {
    for (let i = 0; i < rolls.length; i++) rolls[i] = Math.floor(rolls[i] / 2);
  }
  const min = Math.min(...rolls), max = Math.max(...rolls);
  const avg = rolls.reduce((a, b) => a + b, 0) / rolls.length;
  let koChance = rolls.length ? rolls.filter((r) => r >= curHP).length / rolls.length : 0;
  // きあいのタスキ・がんじょう: 満タンからの単発KOは成立しない
  const md = moveData(moveName);
  if (koChance > 0 && (defMon.hpPct ?? 100) >= 99 && !(md && md.multihit) &&
      (defMon.set.item === 'Focus Sash' || defMon.set.ability === 'Sturdy')) koChance = 0;
  return {
    minPct: (min / maxHP) * 100, maxPct: (max / maxHP) * 100, avgPct: (avg / maxHP) * 100,
    koChance, curHPpct: defMon.hpPct ?? 100,
  };
}

function effSpe(mon, sideConds, ctx) {
  const p = toPokemon(mon);
  let spe = p.rawStats.spe * (BOOST_MULT[String((mon.boosts && mon.boosts.spe) || 0)] || 1);
  if (sideConds && sideConds.tailwind) spe *= 2;
  if (mon.status === 'par') spe *= 0.5;
  // 天候加速特性（簡易）: 雨=すいすい / 晴=ようりょくそ / 砂=すなかき / 雪=ゆきかき
  const ab = mon.set.ability;
  if ((ctx.weather === 'Rain' && ab === 'Swift Swim') || (ctx.weather === 'Sun' && ab === 'Chlorophyll') ||
      (ctx.weather === 'Sand' && ab === 'Sand Rush') || (ctx.weather === 'Snow' && ab === 'Slush Rush')) spe *= 2;
  return spe;
}

// 攻撃順（トリックルーム反転込み）: a が b より先に動くか
function movesBefore(aMon, aConds, bMon, bConds, ctx, aPriority = 0, bPriority = 0) {
  if (aPriority !== bPriority) return aPriority > bPriority;
  const sa = effSpe(aMon, aConds, ctx), sb = effSpe(bMon, bConds, ctx);
  if (sa === sb) return false;
  return ctx.trickRoom ? sa < sb : sa > sb;
}

// ある個体が相手2体から受ける最大脅威（最良技の平均ダメージ%）
function bestDamageAgainst(targetMon, attackers, ctx, targetConds, atkConds) {
  let best = null;
  for (const atk of attackers) {
    if (!atk) continue;
    for (const mv of atk.set.moves || []) {
      const md = moveData(mv);
      if (!md || md.basePower === 0) continue;
      if (md.target === 'self' || md.target === 'ally' || md.target === 'adjacentAlly') continue;
      try {
        const info = damageInfo(atk, targetMon, mv, ctx, atkConds, targetConds);
        if (!best || info.avgPct > best.avgPct) best = { ...info, move: mv, attacker: atk };
      } catch { /* 計算できない技は無視 */ }
    }
  }
  return best;
}

// その個体の最良攻撃（相手アクティブへの平均ダメージ最大の技）
function bestAttack(mon, targets, ctx, myConds, oppConds) {
  let best = null;
  targets.forEach((t, ti) => {
    if (!t) return;
    for (const mv of mon.set.moves || []) {
      const md = moveData(mv);
      if (!md || md.basePower === 0) continue;
      if (md.target === 'self' || md.target === 'ally' || md.target === 'adjacentAlly' || md.target === 'foeSide' || md.target === 'allySide') continue;
      try {
        const info = damageInfo(mon, t, mv, ctx, myConds, oppConds);
        if (!best || info.avgPct > best.avgPct) best = { ...info, move: mv, targetIdx: ti };
      } catch { /* noop */ }
    }
  });
  return best;
}

// ---------- メガシンカ ----------

function megaForme(mon) {
  const s = speciesData(mon.set.species);
  if (!s || !s.otherFormes) return null;
  for (const f of s.otherFormes) {
    const fs = speciesData(f);
    if (fs && fs.requiredItem && toID(fs.requiredItem) === toID(mon.set.item)) {
      return { species: f, ability: fs.abilities[0] };
    }
  }
  return null;
}

function asMega(mon) {
  const mf = megaForme(mon);
  if (!mf) return null;
  return { ...mon, set: { ...mon.set, species: mf.species, ability: mf.ability }, mega: true };
}

// ---------- 変化技の基礎価値 ----------

const SETUP_BOOST = { 'Swords Dance': 2, 'Nasty Plot': 2, 'Dragon Dance': 2, 'Calm Mind': 2, 'Bulk Up': 2, 'Quiver Dance': 2, 'Shell Smash': 3, 'Tail Glow': 3, 'Iron Defense': 1, 'Agility': 1, 'Rock Polish': 1 };
const STATUS_VALUE = { 'Will-O-Wisp': 17, 'Thunder Wave': 14, 'Spore': 22, 'Sleep Powder': 19, 'Hypnosis': 15, 'Toxic': 10, 'Taunt': 10, 'Encore': 10 };

function statusMoveScore(mon, mv, tgt, tgtIdx, state, slotIdx) {
  const { me, opp } = state;
  const ctx = state.field;
  const myConds = me.conditions || {}, oppConds = opp.conditions || {};
  const partner = me.actives[1 - slotIdx];
  const name = mv;
  const acc = (moveData(name)?.accuracy ?? 100) / 100;
  const oppBestVsMe = bestDamageAgainst(mon, opp.actives, ctx, myConds, oppConds);
  const lethal = oppBestVsMe && oppBestVsMe.avgPct >= (mon.hpPct ?? 100);

  switch (name) {
    case 'Protect': case 'Detect': case 'Spiky Shield': case "King's Shield": case 'Baneful Bunker': case 'Silk Trap': {
      let v = 6;
      if (lethal) v += 18;                                   // 致死圏で時間を稼ぐ
      const partnerBest = partner ? bestAttack(partner, opp.actives, ctx, myConds, oppConds) : null;
      if (partnerBest && partnerBest.avgPct >= 55) v += 10;  // 相方の大技を通す
      if (ctx.weather && (mon.set.ability === 'Swift Swim' || mon.set.ability === 'Chlorophyll')) v += 2;
      return { score: v, parts: { protect: v } };
    }
    case 'Tailwind': {
      if (myConds.tailwind) return { score: -40, parts: { duplicate: -40 } };
      let v = 28;
      const mySpes = me.actives.filter(Boolean).map((m) => effSpe(m, myConds, ctx));
      const oppSpes = opp.actives.filter(Boolean).map((m) => effSpe(m, oppConds, ctx));
      if (Math.max(...mySpes) < Math.min(...oppSpes)) v += 10; // 全員抜かれている
      if (Math.min(...mySpes) > Math.max(...oppSpes)) v -= 14; // 既に全員速い
      return { score: v, parts: { tailwind: v } };
    }
    case 'Trick Room': {
      if (ctx.trickRoom) return { score: -30, parts: { duplicate: -30 } };
      const mySpes = me.actives.filter(Boolean).map((m) => effSpe(m, myConds, ctx));
      const oppSpes = opp.actives.filter(Boolean).map((m) => effSpe(m, oppConds, ctx));
      let v = 6;
      if (Math.max(...mySpes) < Math.min(...oppSpes)) v += 28; // 自分たちが遅い側
      else if (Math.min(...mySpes) > Math.max(...oppSpes)) v -= 22;
      return { score: v, parts: { trickRoom: v } };
    }
    case 'Reflect': case 'Light Screen': case 'Aurora Veil': {
      if (name === 'Aurora Veil' && ctx.weather !== 'Snow' && ctx.weather !== 'Hail') return { score: -999, parts: { unusable: -999 } };
      const key = name === 'Reflect' ? 'reflect' : name === 'Light Screen' ? 'lightScreen' : 'auroraVeil';
      if (myConds[key]) return { score: -40, parts: { duplicate: -40 } };
      let v = 20;
      const physThreat = name !== 'Light Screen';
      let pressure = 0;
      for (const o of opp.actives) {
        if (!o) continue;
        const b = bestDamageAgainst(me.actives[slotIdx] || mon, [o], ctx, myConds, oppConds);
        if (b) pressure = Math.max(pressure, b.avgPct);
      }
      v += Math.min(12, pressure / 5);
      if (physThreat && name === 'Aurora Veil') v += 2;
      // 相方が致死圏にいるなら、壁で相方の居座りを助ける価値が上がる
      if (partner) {
        const pIn = bestDamageAgainst(partner, opp.actives, ctx, myConds, oppConds);
        if (pIn && pIn.avgPct >= (partner.hpPct ?? 100)) v += 6;
      }
      return { score: v, parts: { screen: v } };
    }
    case 'Stealth Rock': return { score: oppConds.stealthRock ? -40 : 13, parts: { hazard: oppConds.stealthRock ? -40 : 13 } };
    case 'Spikes': return { score: (oppConds.spikes || 0) >= 2 ? -20 : 10, parts: { hazard: 10 } };
    case 'Toxic Spikes': return { score: (oppConds.toxicSpikes || 0) >= 2 ? -20 : 9, parts: { hazard: 9 } };
    case 'Fake Out': {
      if (!mon.firstTurnOut) return { score: -999, parts: { unusable: -999 } };
      const threat = tgt ? bestDamageAgainst(me.actives[0] || mon, [tgt], ctx, oppConds, myConds) : null;
      const v = 15 + (threat ? Math.min(15, threat.avgPct * 0.25) : 0);
      return { score: v, parts: { fakeOut: v } };
    }
    case 'Parting Shot': return { score: 11, parts: { pivot: 11 } };
    case 'Helping Hand': {
      const pb = partner ? bestAttack(partner, opp.actives, ctx, myConds, oppConds) : null;
      const v = pb ? pb.avgPct * 0.3 : 4;
      return { score: v, parts: { helpingHand: v } };
    }
    case 'Wide Guard': {
      const hasSpread = opp.actives.some((o) => o && (o.set.moves || []).some((m) => { const d = moveData(m); return d && d.isSpread; }));
      return { score: hasSpread ? 11 : -6, parts: { wideGuard: hasSpread ? 11 : -6 } };
    }
    case 'Follow Me': case 'Rage Powder': {
      const v = partner && (partner.hpPct ?? 100) <= 60 ? 13 : 8;
      return { score: v, parts: { redirect: v } };
    }
    case 'Rain Dance': case 'Sunny Day': case 'Sandstorm': case 'Snowscape': {
      const wants = { 'Rain Dance': 'Rain', 'Sunny Day': 'Sun', 'Sandstorm': 'Sand', 'Snowscape': 'Snow' }[name];
      if (ctx.weather === wants) return { score: -30, parts: { duplicate: -30 } };
      const benefits = [...me.actives, ...(me.bench || [])].some((m) => m && ((wants === 'Rain' && m.set.ability === 'Swift Swim') || (wants === 'Sun' && m.set.ability === 'Chlorophyll') || (wants === 'Sand' && m.set.ability === 'Sand Rush') || (wants === 'Snow' && m.set.ability === 'Slush Rush')));
      return { score: benefits ? 16 : 4, parts: { weather: benefits ? 16 : 4 } };
    }
    default: break;
  }
  if (SETUP_BOOST[name]) {
    const survives = !lethal;
    const best = bestAttack(mon, opp.actives, ctx, myConds, oppConds);
    let v = survives ? 19 : 4;
    if (best && best.avgPct >= 35) v += 6;
    return { score: v, parts: { setup: v } };
  }
  if (STATUS_VALUE[name] != null) {
    let v = STATUS_VALUE[name] * acc;
    if (name === 'Will-O-Wisp' && tgt) {
      const ts = speciesData(tgt.set.species);
      if (ts && ts.baseStats.atk < ts.baseStats.spa) v *= 0.4; // 特殊型へのおにびは薄い
    }
    return { score: v, parts: { status: v } };
  }
  const md = moveData(name);
  if (md && (name === 'Recover' || name === 'Roost' || name === 'Slack Off' || name === 'Soft-Boiled' || name === 'Milk Drink' || name === 'Moonlight' || name === 'Morning Sun' || name === 'Synthesis' || name === 'Rest' || name === 'Life Dew' || name === 'Wish')) {
    const missing = 100 - (mon.hpPct ?? 100);
    const v = missing >= 30 ? missing * 0.42 : missing * 0.12;
    return { score: v, parts: { heal: v } };
  }
  return { score: 6, parts: { otherStatus: 6 } };
}

// 溜め技: 条件を満たさない場合は1ターン溜めるため大きく割り引く
const CHARGE_MOVES = {
  'Solar Beam': (ctx) => ctx.weather === 'Sun' || ctx.weather === 'Harsh Sunshine',
  'Solar Blade': (ctx) => ctx.weather === 'Sun' || ctx.weather === 'Harsh Sunshine',
  'Electro Shot': (ctx) => ctx.weather === 'Rain' || ctx.weather === 'HeavyRain',
  'Meteor Beam': () => false, 'Sky Attack': () => false, 'Razor Wind': () => false,
  'Freeze Shock': () => false, 'Ice Burn': () => false, 'Geomancy': () => false,
};
const PROTECT_MOVES = new Set(['Protect', 'Detect', 'Spiky Shield', "King's Shield", 'Baneful Bunker', 'Silk Trap', 'Wide Guard']);

// ---------- 行動生成と採点 ----------

function moveActionsFor(mon, slotIdx, state, monVariant, megaFlag) {
  const { me, opp } = state;
  const ctx = state.field;
  const myConds = me.conditions || {}, oppConds = opp.conditions || {};
  const actions = [];
  const myBestVs = {}; // targetIdx -> best info (脅威評価用に後で使う)

  for (const mv of monVariant.set.moves || []) {
    const md = moveData(mv);
    if (!md) continue;
    const target = md.target;
    if (target === 'self' || (md.basePower === 0 && (target === 'normal' || target === 'any' || target === 'adjacentFoe'))) {
      if (md.basePower === 0) {
        // 変化技（対象あり/なし共通で評価）
        const tgtIdx = 0;
        const r = statusMoveScore(monVariant, mv, opp.actives[tgtIdx], tgtIdx, state, slotIdx);
        actions.push({ type: 'move', slot: slotIdx, move: mv, target: target === 'self' ? 'self' : 'oppA', mega: megaFlag, score: r.score, parts: r.parts });
        continue;
      }
    }
    if (md.basePower > 0) {
      if (target === 'allAdjacentFoes' || target === 'allAdjacent' || target === 'all') {
        // 範囲技: 両対象への合計で評価
        let total = 0; const parts = { damage: 0, ko: 0 };
        opp.actives.forEach((t, ti) => {
          if (!t) return;
          const info = damageInfo(monVariant, t, mv, ctx, myConds, oppConds);
          total += info.avgPct * 0.92 + info.koChance * 48;
          parts.damage += info.avgPct * 0.92; parts.ko += info.koChance * 48;
          myBestVs[ti] = info;
        });
        actions.push({ type: 'move', slot: slotIdx, move: mv, target: 'spread', mega: megaFlag, score: total, parts, dmgByTarget: myBestVs });
        continue;
      }
      if (target === 'self' || target === 'allySide' || target === 'foeSide') {
        const r = statusMoveScore(monVariant, mv, null, -1, state, slotIdx);
        actions.push({ type: 'move', slot: slotIdx, move: mv, target: target === 'self' ? 'self' : target === 'foeSide' ? 'oppSide' : 'mySide', mega: megaFlag, score: r.score, parts: r.parts });
        continue;
      }
      // 単体攻撃技: 各相手アクティブへ
      opp.actives.forEach((t, ti) => {
        if (!t) return;
        const info = damageInfo(monVariant, t, mv, ctx, myConds, oppConds);
        const parts = { damage: info.avgPct, ko: info.koChance * 55 };
        let score = info.avgPct + info.koChance * 55;
        // 相手の脅威の除去価値
        if (info.koChance >= 0.5) {
          const threat = bestDamageAgainst(monVariant, [t], ctx, myConds, oppConds);
          if (threat) { const tv = Math.min(20, threat.avgPct * 0.3); score += tv; parts.threatRemoval = tv; }
        }
        // 先制技で速い相手を落とす
        if (md.priority > 0 && info.koChance > 0 && !movesBefore(monVariant, myConds, t, oppConds, ctx)) { score += 8; parts.priorityKO = 8; }
        // 相手が先に動いて自分を落とす見込みなら、技は通りにくい
        const theirBest = bestDamageAgainst(monVariant, [t], ctx, myConds, oppConds);
        if (theirBest && md.priority <= 0 && !movesBefore(monVariant, myConds, t, oppConds, ctx, 0, moveData(theirBest.move)?.priority || 0)) {
          if (theirBest.avgPct >= (monVariant.hpPct ?? 100)) { score *= 0.35; parts.outspedLethal = 'x0.35'; }
        }
        // 味方への反動・自傷の軽い割引は省略（叩き台）
        actions.push({ type: 'move', slot: slotIdx, move: mv, target: ti === 0 ? 'oppA' : 'oppB', mega: megaFlag, score, parts, dmgInfo: info });
        if (!myBestVs[ti] || info.avgPct > myBestVs[ti].avgPct) myBestVs[ti] = info;
      });
      continue;
    }
    // basePower 0 の単体変化技など
    if (target === 'normal' || target === 'any' || target === 'adjacentFoe' || target === 'adjacentAlly' || target === 'ally' || target === 'any') {
      opp.actives.forEach((t, ti) => {
        if (!t && target !== 'adjacentAlly' && target !== 'ally') return;
        const r = statusMoveScore(monVariant, mv, t, ti, state, slotIdx);
        actions.push({ type: 'move', slot: slotIdx, move: mv, target: ti === 0 ? 'oppA' : 'oppB', mega: megaFlag, score: r.score, parts: r.parts });
      });
      continue;
    }
    const r = statusMoveScore(monVariant, mv, null, -1, state, slotIdx);
    actions.push({ type: 'move', slot: slotIdx, move: mv, target: 'self', mega: megaFlag, score: r.score, parts: r.parts });
  }
  // 溜め技の割引と、このターン倒れる見込みのコストを全行動へ適用
  for (const a of actions) {
    if (a.type !== 'move') continue;
    if (CHARGE_MOVES[a.move] && !CHARGE_MOVES[a.move](ctx) && monVariant.set.item !== 'Power Herb') {
      a.score *= 0.45; a.parts.charge = 'x0.45';
    }
    if (PROTECT_MOVES.has(a.move)) continue;
    let incoming = 0;
    opp.actives.forEach((o, oi) => {
      if (!o) return;
      const killsFirst = a.dmgInfo && ((a.target === 'oppA' && oi === 0) || (a.target === 'oppB' && oi === 1)) &&
        a.dmgInfo.koChance >= 0.99 && movesBefore(monVariant, myConds, o, oppConds, ctx, moveData(a.move)?.priority || 0, 0);
      if (killsFirst) return;
      const bd = bestDamageAgainst(monVariant, [o], ctx, myConds, oppConds);
      if (bd) incoming += bd.avgPct;
    });
    if (incoming >= (monVariant.hpPct ?? 100)) {
      const anyKo = (a.dmgInfo && a.dmgInfo.koChance >= 0.5) || (a.dmgByTarget && Object.values(a.dmgByTarget).some((d) => d.koChance >= 0.5));
      const cost = a.dmgInfo || a.dmgByTarget ? (anyKo ? -25 : -40) : -10;
      a.score += cost; a.parts.faintCost = cost;
    }
  }
  return actions;
}

function switchActionsFor(mon, slotIdx, state) {
  const { me, opp } = state;
  const ctx = state.field;
  const myConds = me.conditions || {}, oppConds = opp.conditions || {};
  const actions = [];
  // このまま居座る価値 = 最良行動スコアの 55%
  const myActions = moveActionsFor(mon, slotIdx, state, mon, false);
  const stayValue = myActions.length ? Math.max(...myActions.map((a) => a.score)) * 0.55 : 0;
  const oppBestVsMe = bestDamageAgainst(mon, opp.actives, ctx, myConds, oppConds);
  const lethal = oppBestVsMe && oppBestVsMe.avgPct >= (mon.hpPct ?? 100);

  for (const b of me.bench || []) {
    if (b.alive === false || (b.hpPct ?? 100) <= 0) continue;
    if (me.actives.some((a) => a && a.set.species === b.set.species)) continue;
    const offense = bestAttack(b, opp.actives, ctx, myConds, oppConds);
    const defense = bestDamageAgainst(b, opp.actives, ctx, myConds, oppConds);
    let score = 10 + (offense ? offense.avgPct * 0.7 : 0) - (defense ? defense.avgPct * 0.5 : 0) - stayValue;
    const parts = { switchBase: 10, offense: offense ? offense.avgPct * 0.7 : 0, defense: defense ? -defense.avgPct * 0.5 : 0, stayCost: -stayValue };
    if (lethal) { score += 22; parts.escapeLethal = 22; }
    if (defense && defense.avgPct >= (b.hpPct ?? 100)) { score -= 18; parts.switchIntoLethal = -18; }
    actions.push({ type: 'switch', slot: slotIdx, switchTo: b.set.species, score, parts });
  }
  return actions;
}

export function slotActions(mon, slotIdx, state) {
  let acts = moveActionsFor(mon, slotIdx, state, mon, false);
  const mega = !(state.megaUsed && state.megaUsed.me) ? asMega(mon) : null;
  if (mega) {
    const megaActs = moveActionsFor(mon, slotIdx, state, mega, true);
    // メガで KO が取れるようになる技には小さな後押し（温存しすぎない）
    for (const a of megaActs) if (a.parts && a.parts.ko) a.parts.ko *= 1.05;
    acts = acts.concat(megaActs);
  }
  acts = acts.concat(switchActionsFor(mon, slotIdx, state));
  return acts.filter((a) => a.score > -500).sort((x, y) => y.score - x.score);
}

// ---------- 組み合わせ評価 ----------

function jointBonus(pa, pb, state) {
  if (!pa || !pb) return { bonus: 0, parts: {} };
  const parts = {};
  let bonus = 0;
  const isDmg = (a) => a.type === 'move' && a.dmgInfo;
  // 集中攻撃: 両方とも同じ対象への単体技
  if (isDmg(pa) && isDmg(pb) && pa.target === pb.target && (pa.target === 'oppA' || pa.target === 'oppB')) {
    const tIdx = pa.target === 'oppA' ? 0 : 1;
    const tgt = state.opp.actives[tIdx];
    if (tgt) {
      const combined = pa.dmgInfo.avgPct + pb.dmgInfo.avgPct;
      const hp = tgt.hpPct ?? 100;
      const eitherGuaranteed = pa.dmgInfo.koChance >= 0.99 || pb.dmgInfo.koChance >= 0.99;
      if (combined >= hp && !eitherGuaranteed) { bonus += 26; parts.focusFireKO = 26; }
      else if (eitherGuaranteed && combined >= hp) { bonus -= 8; parts.overkill = -8; }
    }
  }
  // 片方がまもる + 相方の強い攻撃
  const prot = [pa, pb].find((a) => a.type === 'move' && a.move === 'Protect');
  const other = prot === pa ? pb : pa;
  if (prot && other && other.score >= 55) { bonus += 6; parts.protectCombo = 6; }
  // 速度操作 + 攻撃
  const sc = [pa, pb].find((a) => a.type === 'move' && (a.move === 'Tailwind' || a.move === 'Trick Room'));
  if (sc && other !== sc && other && other.type === 'move' && other.score >= 45) { bonus += 6; parts.speedControlCombo = 6; }
  // 両方交代は原則割引
  if (pa.type === 'switch' && pb.type === 'switch') { bonus -= 12; parts.doubleSwitch = -12; }
  return { bonus, parts };
}

export function decide(state) {
  const a = state.me.actives[0];
  const b = state.me.actives[1];
  const actsA = a ? slotActions(a, 0, state) : [];
  const actsB = b ? slotActions(b, 1, state) : [];
  const topA = actsA.slice(0, 6), topB = actsB.slice(0, 6);
  const pairs = [];
  if (a && b) {
    for (const pa of topA) for (const pb of topB) {
      if (pa.type === 'switch' && pb.type === 'switch' && pa.switchTo === pb.switchTo) continue;
      const { bonus, parts } = jointBonus(pa, pb, state);
      pairs.push({ a: pa, b: pb, total: pa.score + pb.score + bonus, parts: { ...pa.parts, ...pb.parts, joint: parts } });
    }
  } else if (a) {
    for (const pa of topA) pairs.push({ a: pa, b: null, total: pa.score, parts: pa.parts });
  }
  pairs.sort((x, y) => y.total - x.total);
  return { pair: pairs[0], alternatives: pairs.slice(1, 5) };
}
