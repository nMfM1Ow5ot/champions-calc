// 型推定エンジン (champions_calc)
// 相手の型推定に関する純粋な処理を集めたモジュール。画面状態 (DOM や
// グローバルな対戦状態) は直接読まず、材料データは deps.getData() 経由、
// 対戦の証拠は UI 側が作るスナップショット (パネル・場・判明情報) 経由で
// 受け取る。ダメージ計算は「表示用」(core.mjs の calcMatchup を UI が使う)
// と分け、ここでは推定のための計算 (damageRolls による尤度評価と候補全体の
// ダメージ幅の集計) だけを行う。自チームの逆算 (deriveBuild) は含まない。
import { gen, statTable, damageRolls, withCurHP, moveData } from './core.mjs';

const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
export const labelSide = label => (label.startsWith('p1') ? 'p1' : 'p2');
export const labelSpecies = label => { const i = label.indexOf(':'); return i >= 0 ? label.slice(i + 1).trim() : ''; };

export function createEstimator(deps) {
  const effSpecies = deps.effSpecies;
  // 材料データ (UI 側のグローバルと同名で受ける。候補生成のたびに最新化する)
  let POKEDB_PARSED = null, USAGE_SETS = null, META_SETS = null, META_SETS_LOADED = false, NAMES = {};
  function syncData() {
    const d = deps.getData() || {};
    POKEDB_PARSED = d.POKEDB_PARSED ?? null;
    USAGE_SETS = d.USAGE_SETS ?? null;
    META_SETS = d.META_SETS ?? null;
    META_SETS_LOADED = !!d.META_SETS_LOADED;
    NAMES = d.NAMES || {};
  }
  let inference = { seen: 0, bySpecies: {} };
  let infCtx = { tailwindTurn: { p1: -99, p2: -99 }, screenTurn: { p1: {}, p2: {} }, trickRoomTurn: -99, hhTurn: { p1: -99, p2: -99 }, abBatches: {}, abPairs: new Set() };
  let infLastMove = null;
  let dirty = false;
  let bayes = null, lastSpeCtx = null;
  let pendingOpts = null; // processDamageInf が計算した場の条件を processDamageBayes が使う
  let teamContextSpecies = null; // 相手チームの種族一覧 (UI が setTeamContext で渡す)
  // 推論過程ログ (検証用): 更新のたびにスナップショットをキューへ積み、
  // UI が takeInferenceLog() でまとめて受け取る。読み取りのみで推論には影響しない
  let infLog = [], infLogSeq = 0, infLogTurn = null;
  let logTrigger = null; // bayesApply の呼び出し側が証拠の要約を渡すための一時変数

const INF_BLACKLIST = new Set(['Foul Play', 'Gyro Ball', 'Electro Ball', 'Endeavor', 'Final Gambit', 'Seismic Toss', 'Night Shade', 'Dragon Rage', 'Sonic Boom', 'Super Fang', "Nature's Madness", 'Fissure', 'Horn Drill', 'Guillotine', 'Sheer Cold', 'Counter', 'Mirror Coat', 'Metal Burst', 'Comeuppance', 'Pain Split']);

function infEntry(species) {
  if (!inference.bySpecies[species]) inference.bySpecies[species] = { pairs: { atk: null, spa: null, def: null, spd: null, spe: null }, hpSps: null, used: 0, dropped: 0 };
  return inference.bySpecies[species];
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
// 推論過程ログの1レコードを組み立ててキューへ積む。失敗しても推論は止めない
function logSnapshot(species, turn, trigger) {
  try {
    const ent = bayes && bayes.bySpecies ? bayes.bySpecies[species] : null;
    let map = null, cover90 = null, cands = null, used = null, hpLifted = false, marg = null;
    if (ent && ent.cands) {
      const sorted = [...ent.cands].sort((a, b) => b.post - a.post);
      const top = sorted[0];
      map = { nature: top.nature, sp: { ...top.sp }, item: top.item, ability: top.ability, p: +top.post.toFixed(6) };
      let acc = 0, n = 0;
      for (const c of sorted) { acc += c.post; n++; if (acc >= 0.9) break; }
      cover90 = { n, mass: +acc.toFixed(6) };
      cands = sorted.map(c => ({ nature: c.nature, sp: { ...c.sp }, item: c.item, ability: c.ability, p: +c.post.toFixed(6),
        src: c.moveExact ? 'corpus' : c.generic ? 'generic' : (c.bulkSynth || c.shapeSynth || c.itemSynth) ? 'synth' : 'pokedb' }));
      // 周辺分布 (マージナル) の首位: MAP (結合分布の最大) と分布全体の
      // 首位が食い違う場面を、ログ側が再計算なしで検出できるようにする
      const mN = new Map(), mI = new Map();
      for (const c of ent.cands) { mN.set(c.nature, (mN.get(c.nature) || 0) + c.post); mI.set(c.item, (mI.get(c.item) || 0) + c.post); }
      const topOf = m => { let bv = null, bp = -1; for (const [v, p] of m) if (p > bp) { bp = p; bv = v; } return { v: bv, p: +bp.toFixed(6) }; };
      marg = { nature: topOf(mN), item: topOf(mI) };
      used = ent.used;
      hpLifted = !!ent.hpLifted;
    }
    const ie = inference.bySpecies[species];
    const inf = ie ? { used: ie.used, dropped: ie.dropped,
      pairs: { atk: ie.pairs.atk ? ie.pairs.atk.size : null, spa: ie.pairs.spa ? ie.pairs.spa.size : null,
        def: ie.pairs.def ? ie.pairs.def.size : null, spd: ie.pairs.spd ? ie.pairs.spd.size : null,
        spe: ie.pairs.spe ? ie.pairs.spe.size : null },
      hpSps: ie.hpSps ? ie.hpSps.size : null } : null;
    infLog.push({ v: 1, seq: ++infLogSeq, turn: turn != null ? turn : infLogTurn, species, trigger, used, hpLifted, speFlag: (ent && ent.speFlag) || null, map, marg, cover90, cands, inf });
    if (infLog.length > 2000) infLog.splice(0, infLog.length - 2000);
  } catch (e) { /* ログ生成の失敗で推論を止めない */ }
}
function takeInferenceLog() { const out = infLog; infLog = []; return out; }
// 候補集合への交差適用 (空になるイベントは矛盾として捨てる)
function infIntersect(species, statKey, feasible, hpSps) {
  // 推論ログの時系列で entry より先に inf が記録され、その時点の候補状態が
  // 空になる不整合を防ぐため、未生成なら候補を先に用意する (生成は entry
  // スナップショットとして記録される)。失敗しても交差処理は続ける
  if (bayes && bayes.bySpecies[species] === undefined) { try { bayesEntry(species); } catch (err) { /* ログ都合で推論を止めない */ } }
  const e = infEntry(species);
  if (!feasible || !feasible.size) { e.dropped++; logSnapshot(species, infLogTurn, { kind: 'inf', stat: statKey, applied: false }); return; }
  const next = e.pairs[statKey] ? new Set([...e.pairs[statKey]].filter(x => feasible.has(x))) : feasible;
  if (!next.size) { e.dropped++; logSnapshot(species, infLogTurn, { kind: 'inf', stat: statKey, applied: false }); return; }
  let nh = null;
  if (hpSps) {
    nh = e.hpSps ? new Set([...e.hpSps].filter(x => hpSps.has(x))) : hpSps;
    if (!nh.size) { e.dropped++; logSnapshot(species, infLogTurn, { kind: 'inf', stat: statKey, applied: false }); return; }
  }
  e.pairs[statKey] = next;
  if (hpSps) e.hpSps = nh;
  e.used++;
  dirty = true;
  logSnapshot(species, infLogTurn, { kind: 'inf', stat: statKey, applied: true });
}
function processDamageInf(ev, ctx) {
  if (typeof ev.turn === 'number') infLogTurn = ev.turn;
  pendingOpts = null; // このイベントに場の条件が付かなければベイズ側は対象外
  const md = moveData(ev.move);
  if (!md || md.category === 'Status' || !md.basePower || md.multihit || md.fixedDamage || INF_BLACKLIST.has(md.name)) return;
  // 自分自身へのダメージ (反動など) は攻撃として扱わない (ベイズ側は
  // processRecoilBayes が持ち物推論の証拠として取り込む)
  if (ev.atk && ev.atk === ev.def) return;
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
  pendingOpts = opts; // ベイズ側も同じ場の条件で評価する (てだすけ消費などの副作用を共有するため)
  if (oppIsAtk) {
    // 相手の攻撃 -> 自分の正確な被ダメ量から相手の攻撃 (or Body Press は防御) を絞る
    if (typeof ev.amt !== 'number' || ev.amt <= 0) return;
    const statKey = md.name === 'Body Press' ? 'def' : (md.category === 'Physical' ? 'atk' : 'spa');
    const defSpec = ctx.myDef;
    const bases = ctx.basesAtk;
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
    const atkSpec = ctx.myAtk;
    const bases = ctx.basesDef;
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
// 【Champions 差分レイヤーの watch 点】ここから moveBracket までの素早さ・
// 優先度の力学 (スカーフ ×1.5、天候素早さ特性 ×2、かるわざ ×2、おいかぜ
// ×2、はやあし ×1.5 と まひ無効、まひ 半減、いたずらごころ +1、
// あとだし 最後尾) と、反動取り込みの割合窓 [8,11]% (いのちのたま 10%) は、
// @smogon/calc 本体の力学をエンジン側で再実装したものである。種族値・技・
// 特性の「データ」は core.mjs (statTable / damageRolls / moveData / gen) を
// 経由するため差分レイヤーが効くが、上記の「効果そのもの」が差分対象に
// なる場合は、calc 側の差分とあわせてここも更新すること
// (監査: 2026-11-22、総合チャットの依頼による)
const WEATHER_SPE = { Chlorophyll: 'Sun', 'Swift Swim': 'Rain', 'Sand Rush': 'Sand', 'Slush Rush': 'Snow' };
function infEffSpe(statVal, boosts, item, status, tailwind, ability, weather, terrain, unburden) {
  let v = statVal;
  const b = boosts?.spe || 0;
  v = b >= 0 ? Math.floor(v * (2 + b) / 2) : Math.floor(v * 2 / (2 - b));
  if (item === 'Choice Scarf') v = Math.floor(v * 1.5);
  if (item === 'Iron Ball') v = Math.floor(v / 2);
  if (ability && WEATHER_SPE[ability] === weather) v *= 2;
  if (ability === 'Surge Surfer' && terrain === 'Electric') v *= 2;
  if (unburden) v *= 2;
  if (tailwind) v *= 2;
  // はやあし: 状態異常のとき 1.5 倍になり、まひによる半減も受けない
  if (ability === 'Quick Feet' && status) v = Math.floor(v * 1.5);
  else if (status === 'par') v = Math.floor(v / 2);
  return v;
}
// 技の優先度枠: 特性による優先度の増減と、枠内で最後尾になる特性を見る。
// はやてのつばさ (HP 満タン時のひこう技 +1) は時点の HP が要るため呼び出し側で扱う
function moveBracket(md, ability) {
  let prio = md.priority, last = false;
  if (ability === 'Prankster' && md.category === 'Status') prio += 1;
  if (ability === 'Stall') last = true;
  return { prio, last };
}
function processMoveInf(ev, io) {
  if (typeof ev.turn === 'number') infLogTurn = ev.turn;
  const intents = [];
  const side = labelSide(ev.label);
  if (ev.move === 'Tailwind') { infCtx.tailwindTurn[side] = ev.turn; intents.push({ t: 'side', side, key: 'tailwind', turn: ev.turn }); }
  else if (ev.move === 'Trick Room') {
    // トリックルーム中に再度使うと解除される (張り直しにはならない)
    const trActive = ev.turn - infCtx.trickRoomTurn >= 0 && ev.turn - infCtx.trickRoomTurn < 5;
    infCtx.trickRoomTurn = trActive ? -99 : ev.turn;
  }
  else if (ev.move === 'Reflect') { infCtx.screenTurn[side].reflect = ev.turn; intents.push({ t: 'side', side, key: 'reflect', turn: ev.turn }); }
  else if (ev.move === 'Light Screen') { infCtx.screenTurn[side].light = ev.turn; intents.push({ t: 'side', side, key: 'light', turn: ev.turn }); }
  else if (ev.move === 'Aurora Veil') { infCtx.screenTurn[side].veil = ev.turn; intents.push({ t: 'side', side, key: 'veil', turn: ev.turn }); }
  else if (ev.move === 'Helping Hand') { infCtx.hhTurn[side] = ev.turn; intents.push({ t: 'side', side, key: 'hand', turn: ev.turn }); }
  // 設置物は使用者と反対側に置かれる。自動では切れず、解除技でのみ消える
  const foeSide = side === 'p1' ? 'p2' : 'p1';
  if (ev.move === 'Stealth Rock' || ev.move === 'Stone Axe') intents.push({ t: 'side', side: foeSide, key: 'rock', turn: ev.turn });
  else if (ev.move === 'Spikes') intents.push({ t: 'spikes', side: foeSide });
  else if (ev.move === 'Toxic Spikes') intents.push({ t: 'toxicSpikes', side: foeSide });
  else if (ev.move === 'Rapid Spin' || ev.move === 'Mortal Spin' || ev.move === 'Tidy Up') intents.push({ t: 'clear', side });
  else if (ev.move === 'Defog') { intents.push({ t: 'clear', side: 'p1' }); intents.push({ t: 'clear', side: 'p2' }); }
  else if (ev.move === 'Court Change') intents.push({ t: 'court' });
  const prev = infLastMove;
  infLastMove = { turn: ev.turn, side, species: labelSpecies(ev.label), move: ev.move };
  if (!prev || prev.turn !== ev.turn || prev.side === side) return intents;
  const mdA = moveData(prev.move), mdB = moveData(ev.move);
  if (!mdA || !mdB || mdA.priority !== mdB.priority) return intents;
  const firstIsOpp = prev.side === 'p2';
  const oppSpecies = firstIsOpp ? prev.species : labelSpecies(ev.label);
  const mySpecies = firstIsOpp ? labelSpecies(ev.label) : prev.species;
  const mySpec = io.my[mySpecies];
  const oppSpec = io.opp[oppSpecies] || null;
  // 行動順の比較は実際に動いている形態の実数値で行う。メガ進化している側は
  // メガ後の種族表を使う (相手候補側は valuesMega で判定済みだが、自分側の
  // 基準値と比較表が素の形態のままだと、メガで速くなる相手の観測が全候補と
  // 矛盾して証拠が丸ごと捨てられる。battle_20261121_233243 の seq25 が実例)
  const table = statTable(effSpecies(oppSpec));
  if (!mySpec || !oppSpec || !table) return intents;
  // 行動順が素早さで決まらないケースを除外する。特性で優先度が変わる技
  // (いたずらごころ)、枠内で最後尾になる特性 (あとだし)、順序を乱す持ち物
  // (せんせいのツメ/イバンのみ/こうこうのしっぽ/まんぷくおこう) があると
  // 順序から素早さは読み取れない。自分の側は正確に判定でき、相手は判明
  // している場合のみ判定する (未判明分はベイズ側で候補ごとに割り引く)
  const myMd = firstIsOpp ? mdB : mdA, oppMd = firstIsOpp ? mdA : mdB;
  const ORDER_ITEMS = ['Quick Claw', 'Custap Berry', 'Lagging Tail', 'Full Incense'];
  if (ORDER_ITEMS.includes(mySpec.itemLost ? '' : mySpec.item)) return intents;
  if ((oppSpec.corrected || []).includes('持ち物') && ORDER_ITEMS.includes(oppSpec.itemLost ? '' : oppSpec.item)) return intents;
  const myBr = moveBracket(myMd, mySpec.ability);
  if (myBr.last) return intents;
  // はやてのつばさは HP 満タン時のみ発動し、このスナップショットでは時点の HP が確定しないため除外する
  if (mySpec.ability === 'Gale Wings' && myMd.type === 'Flying') return intents;
  if ((oppSpec.corrected || []).includes('特性')) {
    const oppBr = moveBracket(oppMd, oppSpec.ability);
    if (oppBr.last || oppBr.prio !== myBr.prio) return intents;
    if (oppSpec.ability === 'Gale Wings' && oppMd.type === 'Flying') return intents;
  }
  const myTable = statTable(effSpecies(mySpec));
  const myRow = myTable?.spe.find(r => r.nature === mySpec.nature && r.sp === (mySpec.sp.spe || 0));
  if (!myRow) return intents;
  const tw = s => ev.turn - infCtx.tailwindTurn[s] >= 0 && ev.turn - infCtx.tailwindTurn[s] < 4;
  const myEff = infEffSpe(myRow.value, mySpec.boosts, mySpec.itemLost ? '' : mySpec.item, mySpec.status, tw('p1'), mySpec.ability, io.field.weather, io.field.terrain, !!mySpec.unburden);
  const trick = ev.turn - infCtx.trickRoomTurn >= 0 && ev.turn - infCtx.trickRoomTurn < 5;
  const itemKnown = (oppSpec.corrected || []).includes('持ち物');
  const abKnown = (oppSpec.corrected || []).includes('特性');
  const feasible = new Set();
  for (const row of table.spe) {
    const eff = infEffSpe(row.value, oppSpec.boosts, itemKnown ? (oppSpec.itemLost ? '' : oppSpec.item) : '', oppSpec.status, tw('p2'), abKnown ? oppSpec.ability : '', io.field.weather, io.field.terrain, !!oppSpec.unburden);
    // 通常: 先に動いた方が速い (同速の両勝ちはありうる)。トリックルーム下では逆
    const ok = trick ? (firstIsOpp ? eff <= myEff : eff >= myEff) : (firstIsOpp ? eff >= myEff : eff <= myEff);
    if (ok) feasible.add(row.nature + '|' + row.sp);
  }
  lastSpeCtx = { species: oppSpecies, turn: ev.turn, myEff, trick, firstIsOpp, twP2: tw('p2'), oppMd, myPrio: myBr.prio };
  infIntersect(oppSpecies, 'spe', feasible, null);
  return intents;
}
/* 特性の発動順からの素早さ推定: 同時入場 (対戦開始・両者同時交代・2 体同時
   補充など) では、入場時発動の特性はすばやさ順に発動する (天候の奪い合いで
   遅い方の天候が残るのはこのため)。reader が同じ入場バッチで記録した
   'ab' イベント同士を比べ、技の行動順と同じ形で両エンジンに証拠を与える。
   仕様 (ポケモンWiki「ターン」、第八世代以降): 発動順の比較はランク補正・
   持ち物・状態異常などの補正を一切含まない「すばやさ実数値のみ」で行われ、
   トリックルーム中は遅い順に反転する。きんちょうかん / じんばいったい /
   かがくへんかガスは前段のブロックで発動し、すばやさ比較の対象にならない
   ためペアリングから除外する */
const AB_ORDER_EXEMPT = new Set(['Unnerve', 'As One (Glastrier)', 'As One (Spectrier)', 'Neutralizing Gas']);
function infProcessAbility(ev, io) {
  if (typeof ev.turn === 'number') infLogTurn = ev.turn;
  if (typeof ev.batch !== 'number') return;
  if (AB_ORDER_EXEMPT.has(ev.ability)) return;
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
    applyAbilityOrderEvidence(oppSpecies, mySpecies, firstIsOpp, ev.turn, io);
  }
  list.push(me);
}
function applyAbilityOrderEvidence(oppSpecies, mySpecies, firstIsOpp, turn, io) {
  const mySpec = io.my[mySpecies];
  const oppSpec = io.opp[oppSpecies] || null;
  const table = statTable(oppSpecies);
  if (!mySpec || !oppSpec || !table) return;
  const myTable = statTable(mySpecies);
  const myRow = myTable?.spe.find(r => r.nature === mySpec.nature && r.sp === (mySpec.sp.spe || 0));
  if (!myRow) return;
  // 発動順の比較は補正なしの実数値のみ (持ち物・まひ・おいかぜ・天候特性
  // などは一切含まない)。トリックルーム中は遅い順に反転する
  const myRaw = myRow.value;
  const trick = turn - infCtx.trickRoomTurn >= 0 && turn - infCtx.trickRoomTurn < 5;
  // 制約交差エンジン: 実数値で実現可能な (性格, SP) 行を残す
  const feasible = new Set();
  for (const row of table.spe) {
    const ok = trick ? (firstIsOpp ? row.value <= myRaw : row.value >= myRaw) : (firstIsOpp ? row.value >= myRaw : row.value <= myRaw);
    if (ok) feasible.add(row.nature + '|' + row.sp);
  }
  infIntersect(oppSpecies, 'spe', feasible, null);
  // ベイズエンジン: 発動順も素早さの決定的な観測なので、技の行動順と
  // 同じくハード制約として適用する (同速は乱数のため残す)
  const ent = bayesEntry(oppSpecies);
  if (ent) {
    const verdicts = ent.cands.map(c => {
      if (c.values.spe == null) return null;
      if (c.values.spe === myRaw) return null;
      return trick ? (firstIsOpp ? c.values.spe < myRaw : c.values.spe > myRaw) : (firstIsOpp ? c.values.spe > myRaw : c.values.spe < myRaw);
    });
    const res = bayesHardSpe(ent, verdicts);
    logSnapshot(oppSpecies, turn, { kind: 'abilityOrder', firstIsOpp: !!firstIsOpp,
      applied: res.applied, excluded: res.excluded, ...(res.applied ? {} : { inconsistent: true }) });
  }
}
const NATURE_JA2EN = { 'がんばりや': 'Hardy', 'さみしがり': 'Lonely', 'ゆうかん': 'Brave', 'いじっぱり': 'Adamant', 'やんちゃ': 'Naughty', 'ずぶとい': 'Bold', 'すなお': 'Docile', 'のんき': 'Relaxed', 'わんぱく': 'Impish', 'のんてんき': 'Lax', 'おくびょう': 'Timid', 'せっかち': 'Hasty', 'まじめ': 'Serious', 'ようき': 'Jolly', 'むじゃき': 'Naive', 'ひかえめ': 'Modest', 'おっとり': 'Mild', 'れいせい': 'Quiet', 'てれや': 'Bashful', 'うっかりや': 'Rash', 'おだやか': 'Calm', 'おとなしい': 'Gentle', 'なまいき': 'Sassy', 'しんちょう': 'Careful', 'きまぐれ': 'Quirky' };
const BAYES_FLOOR = 0.02;    // 尤度の下限 (候補を完全に消さない)
const BAYES_REV_KEEP = 0.05; // 判明情報と矛盾する候補の減衰率
// 耐久配分の仮定 (ユーザーの指示): まず HP 振りのみを仮定し、HP に振り切って
// いないのに防御・特防へ振っている型は事前確率を強く割り引く。HP 全振りでも
// ダメージ結果と整合しない場合にだけ、尤度を通じてそちらが持ち上がる。
// 完全な排除はしない (HP を振らない耐久型も実在し、強い証拠では覆るため)。
// さらに、ダメージ証拠が HP優先候補の全てと矛盾し割り引き対象候補でのみ
// 説明できる場合は、仮定を撤廃して割り引きを解除する (bayesApply 内)。
// 使用率型に耐久寄りの型が無い種族向けに、最大耐久の合成候補も追加する
const HP_FIRST_FACTOR = 0.1;
const hpFirstCand = c => (c.sp.hp || 0) >= 32 || (!(c.sp.def > 0) && !(c.sp.spd > 0));
function bayesReset() { bayes = { bySpecies: {}, skipped: 0 }; try { moveStatsCache = {}; } catch (e) { /* モジュール初期化中の呼び出しでは宣言前になるため無視する */ } }
/* ===== 技構成からの型予測 (型推定エンジンチャンネル 32274233 の構想に基づく実装) =====
   判明した技を、技構成全体の証拠として扱うための拡張。
   - pokedb 候補には、性格 (攻撃側の補正) と持ち物 (こだわり系・とつげきチョッキ等) から
     予測した4技のプロファイルを持たせる (従来は全候補共通の使用率上位8技プールで、
     技の証拠が候補間を区別できなかった)。技の証拠はプロファイルを通じて
     性格・持ち物へも伝わる (アーキタイプの媒介)
   - プロファイル側の所持尤度は、その種族における技の採用率で重み付ける
     (珍しい技ほど強い証拠)。コーパスの確定技構成については、効果測定の結果を
     踏まえて従来の強い絞り込みを維持する (bayesMoveFactorSingle の注記参照)
   - コーパス型では、判明した2技の共起 (PMI) が実在の組み合わせらしい場合に係数を上乗せする
   - 技の更新は差分適用 (追加は係数、取り消しは逆数) とし、同じ技を二重に数えない
     (従来は判明技の集合が変わるたびに全技を再適用しており、二重計上があった)。
     ダメージ尤度とは別チャンネルで、1イベントの分解 (所持×ダメージ) として両立させる
   - 未判明技の予測 (bayesView.movePred) を同じ事後分布から算出し、推定セルの
     ツールチップに表示する
   BAYES_MOVE_V2=false で従来方式 (一律 0.2) に戻る (効果測定ハーネスの対照用) */
let BAYES_MOVE_V2 = true;
let moveStatsCache = {};
// 性格の補正先 [上昇, 下降] (標準の25性格。無補正は null)
const NATURE_MOD = { Lonely: ['atk', 'def'], Adamant: ['atk', 'spa'], Naughty: ['atk', 'spd'], Brave: ['atk', 'spe'],
  Bold: ['def', 'atk'], Impish: ['def', 'spa'], Lax: ['def', 'spd'], Relaxed: ['def', 'spe'],
  Modest: ['spa', 'atk'], Mild: ['spa', 'def'], Rash: ['spa', 'spd'], Quiet: ['spa', 'spe'],
  Calm: ['spd', 'atk'], Gentle: ['spd', 'def'], Careful: ['spd', 'spa'], Sassy: ['spd', 'spe'],
  Timid: ['spe', 'atk'], Hasty: ['spe', 'def'], Jolly: ['spe', 'spa'], Naive: ['spe', 'spd'],
  Hardy: [null, null], Docile: [null, null], Bashful: [null, null], Quirky: [null, null], Serious: [null, null] };
function pokedbForSpecies(species) {
  syncData();
  if (!POKEDB_PARSED || !USAGE_SETS) return null;
  let u = USAGE_SETS[idOf(species)];
  if (!u) {
    const base = gen.species.get(idOf(species))?.baseSpecies;
    if (base && base !== species) u = USAGE_SETS[idOf(base)];
  }
  if (!u || !u.code) return null;
  const pd = POKEDB_PARSED[u.code];
  return pd ? { u, pd } : null;
}
// その種族のコーパス型 (技構成と weight)。候補生成のコーパス統合と同じ対象範囲
function corpusSetsFor(species) {
  syncData();
  if (!META_SETS || !Array.isArray(META_SETS.sets)) return [];
  const sd = gen.species.get(idOf(species));
  const base = (sd && sd.baseSpecies) || species;
  const out = [];
  for (const e of META_SETS.sets) {
    if (!e || !e.species) continue;
    const full = metaFormeFullName(e);
    const isMega = full.includes('-Mega');
    if (full !== species && !(species === base && e.species === base && isMega)) continue;
    out.push({ moves: (e.moves || []).map(mv => metaNameEn('move', mv)).filter(Boolean), weight: Math.max(e.weight || 0, 0.01) });
  }
  return out;
}
// 種族ごとの技統計: 採用率 (pokedb 使用率とコーパス頻度の混合) と、コーパスでの2技共起 (PMI)
function bayesMoveStats(species) {
  if (moveStatsCache[species]) return moveStatsCache[species];
  const marg = new Map(), cat = new Map(), pair = new Map();
  const found = pokedbForSpecies(species);
  if (found) for (const mv of found.pd.moves || []) {
    const en = (NAMES._moveJa2en || {})[mv.ja];
    if (!en) continue;
    marg.set(en, Math.min(0.97, Math.max(0.02, (mv.rate || 0) / 100)));
    if (mv.cat) cat.set(en, mv.cat);
  }
  const sets = corpusSetsFor(species);
  if (sets.length) {
    let W = 0; const wf = new Map();
    for (const s of sets) { W += s.weight; for (const mv of s.moves) wf.set(mv, (wf.get(mv) || 0) + s.weight); }
    if (W > 0) {
      for (const [mv, w] of wf) {
        const f = w / W;
        if (marg.has(mv)) marg.set(mv, 0.65 * marg.get(mv) + 0.35 * f);
        else marg.set(mv, Math.min(0.9, Math.max(0.03, 0.75 * f + 0.02)));
      }
      const pairW = new Map();
      for (const s of sets) {
        const ms = [...new Set(s.moves)];
        for (let i = 0; i < ms.length; i++) for (let j = i + 1; j < ms.length; j++) {
          const key = bayesPairKey(ms[i], ms[j]);
          pairW.set(key, (pairW.get(key) || 0) + s.weight);
        }
      }
      for (const [key, w] of pairW) {
        const [a, b] = key.split('\u0000');
        const pa = (wf.get(a) || 0) / W, pb = (wf.get(b) || 0) / W, pab = w / W;
        if (pa > 0 && pb > 0 && pab > 0) pair.set(key, Math.max(-1.5, Math.min(2.5, Math.log(pab / (pa * pb)))));
      }
    }
  }
  const stats = { marg, cat, pair };
  moveStatsCache[species] = stats;
  return stats;
}
function bayesPairKey(a, b) { return a < b ? a + '\u0000' + b : b + '\u0000' + a; }
// 判明技1つに対する候補の係数 (所持尤度)。従来方式は含まなければ一律 0.2。
// コーパスの確定技構成については、効果測定 (tests/bayes_moves_eval.mjs の
// leave-one-out) で「実在型レベルでの採用率の重み付け (置換モデル)」が
// 最も近い候補の順位を悪化させたと確認されたため、従来の強い絞り込み
// (含む=1 / 含まない=0.2) を維持する。採用率による重み付けは、候補の
// アーキタイプを表す pokedb 候補の予測プロファイル側でのみ使う:
// プロファイルに含まれる場合は (1-q)+q*p、プール内だがプロファイル外は
// 中間、プール外は q*p (珍しい技ほど、その技を持つ型らしくない候補を強く下げる)
function bayesMoveFactorSingle(c, mv, stats) {
  if (!BAYES_MOVE_V2) return c.moves.includes(mv) ? 1 : 0.2;
  if (c.moveExact) return c.moves.includes(mv) ? 1 : 0.2;
  const p = stats && stats.marg.has(mv) ? stats.marg.get(mv) : 0.05;
  if (c.moves.includes(mv)) return 0.45 + 0.55 * p;
  if (c.movePool && c.movePool.includes(mv)) return 0.5;
  return Math.max(0.55 * p, 0.005);
}
// コーパス型で判明ペアが実在の組み合わせらしい場合の上乗せ係数
function bayesPairFactor(c, a, b, stats) {
  if (!BAYES_MOVE_V2 || !c.moveExact || !stats) return 1;
  if (!c.moves.includes(a) || !c.moves.includes(b)) return 1;
  const pmi = stats.pair.get(bayesPairKey(a, b));
  if (pmi == null) return 1;
  return Math.max(0.8, Math.min(1.55, Math.exp(Math.max(-1, Math.min(2, pmi)) * 0.22)));
}
// 判明技の集合の変化を、差分だけ事後確率へ適用する (追加=係数、取消=逆数で厳密に戻る)
function bayesMoveUpdate(ent, species, moves) {
  if (!ent || !ent.cands) return;
  const stats = bayesMoveStats(species);
  const prev = ent.revMoves || [];
  const added = moves.filter(mv => !prev.includes(mv));
  const removed = prev.filter(mv => !moves.includes(mv));
  if (!added.length && !removed.length) return;
  const pairSet = list => { const s = new Set(); for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) s.add(bayesPairKey(list[i], list[j])); return s; };
  const oldPairs = pairSet(prev), newPairs = pairSet(moves);
  for (const c of ent.cands) {
    let f = 1;
    for (const mv of added) f *= bayesMoveFactorSingle(c, mv, stats);
    for (const mv of removed) f /= bayesMoveFactorSingle(c, mv, stats);
    for (const key of newPairs) if (!oldPairs.has(key)) { const [a, b] = key.split('\u0000'); f *= bayesPairFactor(c, a, b, stats); }
    for (const key of oldPairs) if (!newPairs.has(key)) { const [a, b] = key.split('\u0000'); f /= bayesPairFactor(c, a, b, stats); }
    if (f !== 1) c.post *= f;
  }
  ent.revMoves = [...moves];
  let tot = 0;
  for (const c of ent.cands) tot += c.post;
  if (tot > 0) for (const c of ent.cands) c.post /= tot;
  ent.used++;
  dirty = true;
  logSnapshot(species, infLogTurn, { kind: 'moveSeen', added, removed, applied: true });
}
// meta_sets の名前は英語表記が正本だが、和名で来ても解決できるよう両対応にする
function metaNameEn(kind, name) {
  syncData();
  if (!name) return '';
  if (kind === 'nature') return NATURE_JA2EN[name] || name;
  const map = kind === 'item' ? NAMES._itemJa2en : kind === 'ability' ? NAMES._abilityJa2en : NAMES._moveJa2en;
  return (map || {})[name] || name;
}
// コーパスの forme 表記 ("-Mega" / "Mega-Z" / "Garchomp-Mega-Z" 等) を正式種族名へ寄せる
function metaFormeFullName(entry) {
  if (!entry.forme) return entry.species;
  if (entry.forme.startsWith('-')) return entry.species + entry.forme;
  if (entry.forme.includes(entry.species)) return entry.forme;
  return entry.species + '-' + entry.forme;
}
// コーパス (meta_sets) から対象種族の実在型候補を作る。事前確率は weight 按分。
// 対象は「その種族自身の型」と「ベース種族パネルに対する、そのメガ型」。
// メガ型の特性はメガ側の特性なので megaAbility に入れ、ベース特性は使用率
// 1位の特性 (fallback.topAbility) を仮置きする (pokedb 候補と同じ扱い)
function bayesCorpusCandidates(species, table, fallback) {
  if (!META_SETS || !Array.isArray(META_SETS.sets)) return [];
  const sd = gen.species.get(idOf(species));
  const base = (sd && sd.baseSpecies) || species;
  const out = [];
  for (const e of META_SETS.sets) {
    if (!e || !e.species) continue;
    const full = metaFormeFullName(e);
    const isMega = full.includes('-Mega');
    if (full !== species && !(species === base && e.species === base && isMega)) continue;
    const nature = metaNameEn('nature', e.nature);
    if (!nature) continue;
    const sp = {};
    for (const k of ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) sp[k] = (e.sps && e.sps[k]) || 0;
    const values = {};
    for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) {
      const row = table[k].find(r => r.nature === nature && r.sp === sp[k]);
      values[k] = row ? row.value : null;
    }
    const hpRow = table.hp.find(r => r.sp === sp.hp);
    values.hp = hpRow ? hpRow.value : null;
    // メガ後の実数値も併せて持つ (相手がメガ進化している間は、推定表示と
    // 行動順の判定をメガ後の種族値で評価するため。HP はメガ前後で不変)
    let valuesMega;
    const megaName = isMega ? full : fallback.megaSpecies;
    if (megaName) {
      const mt = statTable(megaName);
      if (mt) {
        valuesMega = { hp: values.hp };
        for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) {
          const row = mt[k].find(r => r.nature === nature && r.sp === sp[k]);
          valuesMega[k] = row ? row.value : null;
        }
      }
    }
    const ability = metaNameEn('ability', e.ability);
    out.push({
      nature, sp,
      item: metaNameEn('item', e.item),
      ability: isMega ? (fallback.topAbility || ability) : ability,
      megaAbility: isMega ? ability : fallback.megaAbility,
      megaSpecies: isMega ? full : fallback.megaSpecies,
      moves: (e.moves || []).map(mv => metaNameEn('move', mv)).filter(Boolean),
      moveExact: true,
      values, valuesMega, post: 0, corpus: true, _w: Math.max(e.weight || 0, 0.01),
    });
  }
  const tot = out.reduce((s, c) => s + c._w, 0) || 1;
  for (const c of out) { c.post = c._w / tot; delete c._w; }
  return out;
}
// 候補生成: pokedb の使用率分布 (SP配分×性格×持ち物×特性) から実在の型を作る。
// 事前確率は各要素の使用率の積 (独立近似) を正規化したもの
// 使用率データが無い種族向けの汎用候補: 種族値から代表的な形状
// (高速/低速アタッカー、物理/特殊/混合耐久、無振り) を組み立て、
// ベイズ推定が最低限動くようにする。使用率データが用意された種族では
// 通常経路が使われ、こちらは呼ばれない (bayesBuildCandidates の分岐参照)
function bayesGenericCandidates(species, table) {
  const sd = gen.species.get(idOf(species));
  if (!sd || !table) return null;
  const abilities = [...new Set(Object.values(sd.abilities || {}).filter(Boolean))];
  if (!abilities.length) return null;
  const bs = sd.baseStats || {};
  const phys = (bs.atk || 0) >= (bs.spa || 0);
  const off = phys ? 'atk' : 'spa';
  const fastNat = (bs.spe || 0) >= 90 ? (phys ? 'Jolly' : 'Timid') : (phys ? 'Adamant' : 'Modest');
  const shapes = [
    { sp: { hp: 2, [off]: 32, spe: 32 }, nature: fastNat, items: [phys ? 'Choice Band' : 'Choice Specs', 'Life Orb', ''], w: 1.0 },
    { sp: { hp: 32, [off]: 32, spe: 2 }, nature: phys ? 'Brave' : 'Quiet', items: ['Life Orb', ''], w: 0.6 },
    { sp: { hp: 32, [off]: 32, spe: 2 }, nature: phys ? 'Adamant' : 'Modest', items: ['Life Orb', ''], w: 0.5 },
    { sp: { hp: 32, def: 32, spe: 2 }, nature: 'Impish', items: ['Leftovers', ''], w: 0.5 },
    { sp: { hp: 32, spd: 32, spe: 2 }, nature: 'Careful', items: ['Leftovers', ''], w: 0.5 },
    { sp: { hp: 32, def: 16, spd: 16, spe: 2 }, nature: 'Bold', items: ['Leftovers', ''], w: 0.4 },
    { sp: {}, nature: 'Serious', items: [''], w: 0.3 },
  ];
  const out = [];
  shapes.forEach((sh, si) => {
    const sp = {};
    for (const k of ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) sp[k] = sh.sp[k] || 0;
    const values = {};
    for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) {
      const row = table[k].find(r => r.nature === sh.nature && r.sp === sp[k]);
      values[k] = row ? row.value : null;
    }
    const hpRow = table.hp.find(r => r.sp === sp.hp);
    values.hp = hpRow ? hpRow.value : null;
    if (values.hp == null) return;
    const abils = si === 0 && abilities[1] ? [abilities[0], abilities[1]] : [abilities[0]];
    for (const item of sh.items) for (const ability of abils) {
      out.push({ nature: sh.nature, sp: { ...sp }, item, ability, megaAbility: undefined, megaSpecies: undefined,
        moves: [], movePool: [], moveExact: false, values, valuesMega: undefined,
        post: 0, _w: sh.w * (ability === abilities[0] ? 1 : 0.5), generic: true });
    }
  });
  if (!out.length) return null;
  const tot = out.reduce((s, c) => s + c._w, 0) || 1;
  for (const c of out) { c.post = c._w / tot; delete c._w; }
  return out;
}
function bayesBuildCandidates(species) {
  if (!POKEDB_PARSED || !USAGE_SETS) return null;
  const table = statTable(species);
  if (!table) return null;
  let u = USAGE_SETS[idOf(species)];
  if (!u) {
    const base = gen.species.get(idOf(species))?.baseSpecies;
    if (base && base !== species) u = USAGE_SETS[idOf(base)];
  }
  if (!u || !u.code) return bayesGenericCandidates(species, table);
  const pd = POKEDB_PARSED[u.code];
  if (!pd) return bayesGenericCandidates(species, table);
  const patterns = (pd.patterns || []).slice(0, 5).map(p => ({ sp: p.sp || {}, rate: p.rate || 0 }));
  const natures = (pd.natures || []).map(n => ({ en: NATURE_JA2EN[n.name], rate: n.rate || 0 })).filter(n => n.en).slice(0, 5);
  const items = (pd.items || []).map(i => ({ en: (NAMES._itemJa2en || {})[i.name], rate: i.rate || 0 })).filter(i => i.en).slice(0, 4);
  const itemsAll = (pd.items || []).map(i => ({ en: (NAMES._itemJa2en || {})[i.name], rate: i.rate || 0 })).filter(i => i.en).slice(0, 10);
  const abilities = (pd.abilities || []).map(a => ({ en: (NAMES._abilityJa2en || {})[a.name], rate: a.rate || 0 })).filter(a => a.en).slice(0, 3);
  const poolInfo = (pd.moves || []).map(mv => ({ en: (NAMES._moveJa2en || {})[mv.ja], rate: mv.rate || 0, cat: mv.cat || '' })).filter(x => x.en).slice(0, 10);
  const movePool = poolInfo.map(x => x.en).slice(0, 8);
  if (!patterns.length || !natures.length) return bayesGenericCandidates(species, table);
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
  const mtable = u.megaSpecies ? statTable(u.megaSpecies) : null;
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
    // メガ後の実数値も併せて持つ (コーパス候補と同じ理由。HP は不変)
    let valuesMega;
    if (mtable) {
      valuesMega = { hp: values.hp };
      for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) {
        const row = mtable[k].find(r => r.nature === combo.n.en && r.sp === sp[k]);
        valuesMega[k] = row ? row.value : null;
      }
    }
    // 技プロファイル: この候補 (性格×持ち物) が持っていそうな4技を予測する。
    // 性格の攻撃側補正と持ち物 (こだわり系は変化技をほぼ持たない等) で技カテゴリに
    // 傾斜を付け、使用率順のプールから上位4技を選ぶ。判明技の証拠はこの
    // プロファイルを通じて性格・持ち物へも伝わる (アーキタイプの媒介)
    const mod = NATURE_MOD[combo.n.en] || [null, null];
    let phys = 1, spec = 1, statAff = 1;
    if (mod[0] === 'atk') phys *= 1.5; if (mod[1] === 'atk') phys *= 0.5;
    if (mod[0] === 'spa') spec *= 1.5; if (mod[1] === 'spa') spec *= 0.5;
    if (mod[1] === 'spa' && mod[0] !== 'spa') phys *= 1.15;
    if (mod[1] === 'atk' && mod[0] !== 'atk') spec *= 1.15;
    if (item.en === 'Choice Band') { phys *= 1.4; statAff = 0.25; }
    else if (item.en === 'Choice Specs') { spec *= 1.4; statAff = 0.25; }
    else if (item.en === 'Choice Scarf') statAff = 0.4;
    else if (item.en === 'Assault Vest') statAff = 0.15;
    else if (item.en === 'Life Orb') { phys *= 1.1; spec *= 1.1; }
    const profMoves = poolInfo.map(x => ({ en: x.en, s: (x.rate + 2) * (x.cat === '物理' ? phys : x.cat === '特殊' ? spec : statAff) }))
      .sort((a, b) => b.s - a.s).slice(0, 4).map(x => x.en);
    return { nature: combo.n.en, sp, item: item.en, ability: ability.en, megaAbility, megaSpecies: u.megaSpecies || undefined,
      moves: profMoves, movePool, moveExact: false, values, valuesMega, post: 0, _w: combo.w * Math.max(item.rate, 0.3) * Math.max(ability.rate, 0.3) * wMul * (hpFirstCand({ sp }) ? 1 : HP_FIRST_FACTOR) };
  };
  const raw = [];
  for (const c of combos.slice(0, 20)) raw.push(mk(c, topItem, topAbility, 1));
  for (const c of combos.slice(0, 4)) for (const it of items.slice(1, 3)) raw.push(mk(c, it, topAbility, 1));
  for (const c of combos.slice(0, 3)) for (const ab of abilities.slice(1, 2)) raw.push(mk(c, topItem, ab, 1));
  for (const c of combos.slice(0, 2)) raw.push(mk(c, { en: '', rate: 0 }, topAbility, 0.15));
  // 最大耐久の合成候補: 使用率型に防御・特防寄りの型が無い種族でも、HP 全振り
  // でも説明できない硬さを推定できるよう、HP32+防御32 / HP32+特防32 の型を
  // 各1件追加する (性格はその種族の使用率性格から防御・特防が上がるものを
  // 優先し、無ければ最上位の性格。重さは最上位パターンの半分)
  {
    const baseW = (patterns[0].rate + 0.5);
    const defNat = natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'def') || natures[0];
    const spdNat = natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'spd') || natures[0];
    const synth = (nat, sp) => {
      const c = mk({ p: { sp, rate: patterns[0].rate }, n: nat, w: baseW * (nat.rate + 0.5) }, topItem, topAbility, 0.5);
      c.bulkSynth = true;
      return c;
    };
    raw.push(synth(defNat, { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }));
    raw.push(synth(spdNat, { hp: 32, atk: 0, def: 0, spa: 0, spd: 32, spe: 0 }));
  }
  // 形状テンプレートの合成候補: 使用率パターンが「速いアタッカー」と
  // 「サポート型」に偏る種族では、遅いアタッカー型 (HP+攻撃全振り) や
  // 混合耐久型が候補に存在せず、実在する手作り型を推定できない
  // (模擬テストで最寄り候補まで SP 距離 50 の事例を確認)。代表的な形状を
  // 各1件追加し、証拠による選択に委ねる (重さは最大耐久合成と同じ半分)
  {
    const baseW = (patterns[0].rate + 0.5);
    const atkNat = natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'atk') || natures[0];
    const spaNat = natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'spa') || natures[0];
    const mixNat = natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'def') || natures.find(n => (NATURE_MOD[n.en] || [])[0] === 'spd') || natures[0];
    const synth = (nat, sp) => {
      const c = mk({ p: { sp, rate: patterns[0].rate }, n: nat, w: baseW * (nat.rate + 0.5) }, topItem, topAbility, 0.5);
      c.shapeSynth = true;
      return c;
    };
    raw.push(synth(atkNat, { hp: 32, atk: 32, def: 0, spa: 0, spd: 0, spe: 2 }));
    raw.push(synth(spaNat, { hp: 32, atk: 0, def: 0, spa: 32, spd: 0, spe: 2 }));
    raw.push(synth(mixNat, { hp: 32, atk: 0, def: 16, spa: 0, spd: 16, spe: 2 }));
  }
  const seen = new Set(), out = [];
  for (const c of raw) {
    const key = c.nature + '|' + JSON.stringify(c.sp) + '|' + c.item + '|' + c.ability;
    if (seen.has(key)) continue;
    seen.add(key); out.push(c);
  }
  const tot = out.reduce((s, c) => s + c._w, 0) || 1;
  for (const c of out) { c.post = c._w / tot; delete c._w; }
  // 持ち物カバレッジ: バリアント展開は使用率上位3件までしか届かないため、
  // それ以下の持ち物 (例: Farigiraf の いのちのたま = 9位 1.2%) は候補が
  // 1件も存在せず、判明しても反映先が無い構造になっていた。使用率1%以上の
  // 持ち物は、最上位の型との組合せで最低1件を保証する (重さは mk の
  // 使用率按分に合成候補と同じ 0.5 を掛けたもの)
  {
    const present = new Set(out.map(c => c.item));
    let added = false;
    for (const it of itemsAll) {
      if (it.rate < 1 || present.has(it.en)) continue;
      const c = mk(combos[0], it, topAbility, 0.5);
      c.itemSynth = true;
      c.post = c._w / tot; delete c._w;
      out.push(c); present.add(it.en); added = true;
    }
    if (added) { const t2 = out.reduce((s, c) => s + c.post, 0) || 1; for (const c of out) c.post /= t2; }
  }
  // 上位勢コーパス (meta_sets) の実在型を候補へ統合する: 事前確率は
  // コーパス側 6 割 (weight 按分) / pokedb 合成候補側 4 割 (従来の使用率積)。
  // pokedb 候補と同一の型がコーパスにある場合は、その質量をコーパス候補へ
  // 寄せて二重計上を避ける。コーパスが無い種族は従来動作のまま
  const corpus = bayesCorpusCandidates(species, table, { topAbility: topAbility.en, megaAbility, megaSpecies: u.megaSpecies || undefined });
  if (!corpus.length) return out.slice(0, 64);
  const keyOf = c => c.nature + '|' + JSON.stringify(c.sp) + '|' + c.item + '|' + c.ability + '|' + (c.megaSpecies || '');
  const byKey = new Map(corpus.map(c => [keyOf(c), c]));
  const merged = [...corpus];
  for (const c of corpus) c.post *= 0.6;
  for (const c of out) {
    const hit = byKey.get(keyOf(c));
    if (hit) hit.post += 0.4 * c.post;
    else { c.post *= 0.4; merged.push(c); }
  }
  const tot2 = merged.reduce((s, c) => s + c.post, 0) || 1;
  for (const c of merged) c.post /= tot2;
  merged.sort((a, b) => b.post - a.post);
  return merged.slice(0, 96);
}
// チーム文脈による持ち物の事前補正: 味方に地形を展開する特性の種族が
// いる場合、対応するシード持ちはその地形で発動して特性と連動する前提の
// 型であることが多い (例: サイコフィールド展開役 + サイコシード)。
// ダメージ証拠ではシードと無効果の持ち物を区別できないため、事前分布で
// 補正する。UI が対戦開始前に相手チームを渡した場合のみ働く
const TEAM_SEED_BOOST = 3;
const TERRAIN_SEED_BY_ABILITY = { 'Psychic Surge': 'Psychic Seed', 'Grassy Surge': 'Grassy Seed', 'Electric Surge': 'Electric Seed', 'Misty Surge': 'Misty Seed' };
function applyTeamItemBoost(cands, selfSpecies) {
  if (!teamContextSpecies || !teamContextSpecies.length || !POKEDB_PARSED || !USAGE_SETS) return;
  const seeds = new Set();
  for (const sp2 of teamContextSpecies) {
    if (sp2 === selfSpecies) continue;
    let u2 = USAGE_SETS[idOf(sp2)];
    if (!u2) {
      const base = gen.species.get(idOf(sp2))?.baseSpecies;
      if (base && base !== sp2) u2 = USAGE_SETS[idOf(base)];
    }
    const pd2 = u2 && u2.code ? POKEDB_PARSED[u2.code] : null;
    if (!pd2) continue;
    for (const a of pd2.abilities || []) {
      const seed = TERRAIN_SEED_BY_ABILITY[(NAMES._abilityJa2en || {})[a.name]];
      if (seed) seeds.add(seed);
    }
  }
  if (!seeds.size) return;
  let hit = false, tot = 0;
  for (const c of cands) { if (seeds.has(c.item)) { c.post *= TEAM_SEED_BOOST; hit = true; } tot += c.post; }
  if (hit && tot > 0) for (const c of cands) c.post /= tot;
}
function setTeamContext(list) {
  teamContextSpecies = Array.isArray(list) && list.length ? [...list] : null;
}
function bayesEntry(species) {
  syncData();
  if (!bayes) return null;
  if (!bayes.bySpecies[species]) {
    // 使用率データがまだ読み込めていない間は「候補なし」を確定させない
    if (!POKEDB_PARSED || !USAGE_SETS || !META_SETS_LOADED) return null;
    const cands = bayesBuildCandidates(species);
    if (!cands || !cands.length) { bayes.bySpecies[species] = null; return null; }
    applyTeamItemBoost(cands, species);
    bayes.bySpecies[species] = { species, cands, used: 0, revKey: '' };
    logSnapshot(species, infLogTurn, { kind: 'entry' });
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
function bayesApply(ent, counts, bulk) {
  const lt = logTrigger; logTrigger = null;
  const liftedBefore = !!ent.hpLifted;
  // HP優先の仮定の撤廃 (ダメージ証拠のみ): HP優先候補の全てと矛盾し、
  // 割り引き対象候補でのみ説明できる観測が得られたら、割り引きを解除する。
  // 蓄積済みの尤度は保持したまま、対象候補の確率を割り引き前の比率へ戻す
  if (bulk && !ent.hpLifted && counts.some(n => n > 0)) {
    let firstHit = false, penHit = false;
    ent.cands.forEach((c, i) => { if (counts[i] > 0) { if (hpFirstCand(c)) firstHit = true; else penHit = true; } });
    if (!firstHit && penHit) {
      ent.hpLifted = true;
      let t = 0;
      for (const c of ent.cands) { if (!hpFirstCand(c)) c.post /= HP_FIRST_FACTOR; t += c.post; }
      if (t > 0) for (const c of ent.cands) c.post /= t;
      dirty = true;
    }
  }
  if (!counts.some(n => n > 0)) { bayes.skipped++; if (lt && ent.species) logSnapshot(ent.species, lt.turn, { ...lt.trig, applied: false }); return; }
  let tot = 0;
  ent.cands.forEach((c, i) => { c.post *= Math.max(counts[i] / 16, BAYES_FLOOR); tot += c.post; });
  if (!(tot > 0)) { if (lt && ent.species) logSnapshot(ent.species, lt.turn, { ...lt.trig, applied: false }); return; }
  for (const c of ent.cands) c.post /= tot;
  ent.used++;
  dirty = true;
  if (lt && ent.species) logSnapshot(ent.species, lt.turn, { ...lt.trig, applied: true, lifted: !!ent.hpLifted && !liftedBefore });
}
// 反動による持ち物推論: いのちのたまの反動は最大HPのちょうど1/10 で、
// 表示は 10% 前後になる。技自身の反動 (与えたダメージに比例して割合が
// 一定しない) と区別できるこの形の自己ダメージだけを、持ち物の弱い
// 判明証拠として取り込む (反動が無いことは証拠にしない: 読み取り漏れの
// 可能性があるため)。減衰率は判明情報 (0.05) より緩やかな 0.1
const RECOIL_KEEP = 0.1;
function processRecoilBayes(ev) {
  if (typeof ev.turn === 'number') infLogTurn = ev.turn;
  if (typeof ev.pct !== 'number' || ev.pct < 8 || ev.pct > 11) return;
  const species = labelSpecies(ev.atk);
  const ent = bayesEntry(species);
  if (!ent) return;
  let tot = 0;
  for (const c of ent.cands) { if (c.item !== 'Life Orb') c.post *= RECOIL_KEEP; tot += c.post; }
  if (!(tot > 0)) return;
  for (const c of ent.cands) c.post /= tot;
  ent.used++;
  dirty = true;
  logSnapshot(species, ev.turn, { kind: 'recoil', pct: ev.pct, applied: true });
}
// 行動順のハード制約 (ユーザーの原則): 素早さ順は、同速の場合の乱数を
// 除けば乱数の絡まない絶対的な指標であり、観測された順序と矛盾する候補は
// 弱い尤度で割り引くのではなく確率0で除外する。verdicts は候補ごとの
// 判定 (true=残す / false=除外 / null=判定不能のため残す。同速・はやての
// つばさ・確率発動の順序変更持ち物など)。全候補が矛盾する場合は、観測側
// の未モデル要素 (読み取り誤り等) が疑われるため分布を壊さず適用を見送る
function bayesHardSpe(ent, verdicts) {
  let survivorMass = 0, excluded = 0;
  ent.cands.forEach((c, i) => { if (verdicts[i] === false) { if (c.post > 0) excluded++; } else survivorMass += c.post; });
  if (!(survivorMass > 0)) return { applied: false, excluded: 0 };
  if (excluded) {
    ent.cands.forEach((c, i) => { if (verdicts[i] === false) c.post = 0; });
    for (const c of ent.cands) c.post /= survivorMass;
  }
  ent.used++;
  dirty = true;
  return { applied: true, excluded };
}
function processDamageBayes(ev, ctx) {
  // 自分自身へのダメージは攻撃として処理せず、反動の経路へ回す
  if (ev.atk && ev.atk === ev.def) { if (labelSide(ev.atk) === 'p2') processRecoilBayes(ev); return; }
  const opts = pendingOpts;
  if (!opts) return; // 旧エンジンが対象外にした技 (変化・固定ダメ等) は同じく対象外
  const md = moveData(ev.move);
  if (!md) return;
  const atkSpecies = labelSpecies(ev.atk), defSpecies = labelSpecies(ev.def);
  if (labelSide(ev.atk) === 'p2') {
    // 相手の攻撃: 自分の正確な被ダメ量と両立するロールの割合が尤度
    if (typeof ev.amt !== 'number' || ev.amt <= 0) return;
    const ent = bayesEntry(atkSpecies);
    const defSpec = ctx.myDef;
    const base = ctx.baseAtk;
    if (!ent || !defSpec || !base) return;
    const counts = ent.cands.map(c => {
      const { rolls } = damageRolls(withCurHP(bayesCandSpec(base, c)), withCurHP(defSpec), md.name, opts);
      return rolls.filter(r => r === ev.amt).length;
    });
    logTrigger = { turn: ev.turn, trig: { kind: 'damage', move: md.name, by: 'opp', amt: ev.amt, crit: !!ev.crit } };
    bayesApply(ent, counts, true);
  } else {
    // 自分の攻撃: 相手の HP% 減少 (切り捨て/四捨五入の両対応) と両立するロールの割合
    if (typeof ev.pct !== 'number' || ev.pct <= 0) return;
    const ent = bayesEntry(defSpecies);
    const atkSpec = ctx.myAtk;
    const base = ctx.baseDef;
    if (!ent || !atkSpec || !base) return;
    const counts = ent.cands.map(c => {
      const hpVal = c.values.hp;
      if (!hpVal) return 0;
      const { rolls } = damageRolls(withCurHP(atkSpec), withCurHP(bayesCandSpec(base, c)), md.name, opts);
      let n = 0;
      for (const r of rolls) if (r > 0 && (Math.round(r / hpVal * 100) === ev.pct || Math.floor(r / hpVal * 100) === ev.pct)) n++;
      return n;
    });
    logTrigger = { turn: ev.turn, trig: { kind: 'damage', move: md.name, by: 'mine', pct: ev.pct, crit: !!ev.crit } };
    bayesApply(ent, counts, true);
  }
}
function processMoveBayes(ev, io) {
  const ctx = lastSpeCtx;
  if (!ctx || ctx.turn !== ev.turn) return;
  const ent = bayesEntry(ctx.species);
  if (!ent) return;
  const panel = io.opp[ctx.species] || null;
  // 行動順はハード制約として適用する (bayesHardSpe)。候補ごとの判定:
  // 優先度枠で順序が決まる候補は枠で判定し、確率発動の順序変更持ち物
  // (せんせいのツメ / イバンのみ) を持つ候補は順序から素早さを断定
  // できないため残す。同速ちょうどの候補も乱数で決まるため残す
  const verdicts = ent.cands.map(c => {
    // メガ進化している相手の行動順は、メガ後のすばやさで判定する
    const speVal = (panel && panel.mega && c.valuesMega) ? c.valuesMega.spe : c.values.spe;
    if (speVal == null) return null;
    // 実効素早さの補正 (天候で倍化する特性など) も、実際に発動している
    // メガ後の特性で判定する
    const cAb = panel && panel.mega && c.megaAbility ? c.megaAbility : c.ability;
    // 候補の特性で優先度枠がずれる場合、その候補については順序は素早さ
    // ではなく枠で決まる (枠が上の候補は先行が確定、下なら先行はあり得ない)
    if (ctx.oppMd) {
      if (cAb === 'Gale Wings' && ctx.oppMd.type === 'Flying') return null; // HP 条件で確定しないため残す
      const cBr = moveBracket(ctx.oppMd, cAb);
      if (cBr.last) return !ctx.firstIsOpp;
      if (cBr.prio !== ctx.myPrio) return (cBr.prio > ctx.myPrio) === ctx.firstIsOpp;
    }
    // 素早さ仮説フラグが立っている間は、候補の持ち物ではなくフラグの
    // 持ち物を仮定して判定する (下記の bayesHardSpe 後の処理を参照)
    const itemForSpe = panel && panel.itemLost ? '' : (ent.speFlag || c.item);
    if (itemForSpe === 'Quick Claw' || itemForSpe === 'Custap Berry') return null; // 発動が確率的で順序が素早さで決まらない
    if (itemForSpe === 'Lagging Tail' || itemForSpe === 'Full Incense') return !ctx.firstIsOpp; // 枠内で最後尾が確定
    const eff = infEffSpe(speVal, panel ? panel.boosts : {}, itemForSpe,
      panel ? panel.status : '', ctx.twP2, cAb, io.field.weather, io.field.terrain, !!(panel && panel.unburden));
    if (eff === ctx.myEff) return null; // 同速は乱数で決まるため残す
    return ctx.trick ? (ctx.firstIsOpp ? eff < ctx.myEff : eff > ctx.myEff) : (ctx.firstIsOpp ? eff > ctx.myEff : eff < ctx.myEff);
  });
  const res = bayesHardSpe(ent, verdicts);
  // 種族値と候補の持ち物では説明できない素早さ関係が判明した場合
  // (全候補が観測と矛盾) は、持ち物の仮説フラグを仮で立てる: 通常状況
  // なら こだわりスカーフ、トリックルーム下なら くろいてっきゅう
  // (ユーザーの指示)。以後の行動順の判定はこの持ち物を仮定して行い、
  // 持ち物が判明したらフラグは下ろす
  if (!res.applied && !ent.speFlag) ent.speFlag = ctx.trick ? 'Iron Ball' : 'Choice Scarf';
  logSnapshot(ctx.species, ev.turn, { kind: 'moveOrder', move: ctx.oppMd ? ctx.oppMd.name : null, firstIsOpp: !!ctx.firstIsOpp,
    applied: res.applied, excluded: res.excluded, ...(res.applied ? {} : { inconsistent: true }), speFlag: ent.speFlag || null });
}
// 判明情報 (持ち物・特性) と矛盾する候補の減衰。同じ判明内容では再適用しない。
// 判明技は bayesMoveUpdate が差分で適用する (技構成からの型予測)。
// list は UI 側が相手パネルから作るスナップショット
// [{species, knownMoves, itemLost, item, ability, corrected, mega}]
function applyRevealed(list) {
  if (!bayes) return;
  syncData();
  for (const p of list) {
    const species = p.species;
    let ent = bayes.bySpecies[species];
    // 技だけが判明している段階でも推定が始まるよう、候補を先に用意する
    if (!ent && (p.knownMoves || []).length) ent = bayesEntry(species);
    if (!ent) continue;
    bayesMoveUpdate(ent, species, p.knownMoves || []);
    const corr = p.corrected || [];
    // 判明値は候補の英語名と突き合わせる。メガストーン等が日本語名で
    // 届く経路があり (battle_20261121_234913 seq6: リザードナイトY)、
    // そのままだと全候補が不一致になって判明が無効化されるため、
    // 名前マップで正規化してから比較する
    const normItem = v => v == null ? null : ((NAMES._itemJa2en || {})[v] || v);
    const normAbility = v => v == null ? null : ((NAMES._abilityJa2en || {})[v] || v);
    const item = p.itemLost ? '' : (corr.includes('持ち物') ? normItem(p.item || '') : null);
    const ability = corr.includes('特性') ? normAbility(p.ability) : null;
    const key = (item ?? '?') + '|' + (ability ?? '?');
    if (key === ent.revKey) continue;
    ent.revKey = key;
    // 判明内容が無い呼び出し (item/ability とも null) は記録しない
    // (空の revealed スナップショットの抑制)
    if (item === null && ability === null) continue;
    // 判明情報はハード制約として固定する: 確定した持ち物・特性と矛盾する
    // 候補は確率0で除外する (行動順と同じ原則。乗算の尤度更新では0は
    // 復活しないため、その後の証拠で覆ることはない)。持ち物を失った
    // 状態 (itemLost の '') は「元々何も持っていなかった」ことの判明では
    // ないため対象外とし、従来どおりの減衰に留める。全候補が矛盾する
    // 場合は判明値の取り違えが疑われるため、分布を壊さず減衰へ
    // フォールバックし、hard:false として記録する
    const itemHard = item !== null && !p.itemLost;
    const matchItem = c => !itemHard || c.item === item;
    const matchAbility = c => ability === null || c.ability === ability || (p.mega && c.megaAbility === ability);
    let survivorMass = 0, excluded = 0;
    for (const c of ent.cands) { if (matchItem(c) && matchAbility(c)) survivorMass += c.post; else if (c.post > 0) excluded++; }
    const hardMode = (itemHard || ability !== null) && survivorMass > 0;
    let applied = false;
    if (hardMode && itemHard) ent.speFlag = null; // 持ち物が判明したら素早さ仮説フラグは下ろす
    if (hardMode) {
      if (excluded > 0) {
        for (const c of ent.cands) if (!(matchItem(c) && matchAbility(c))) c.post = 0;
        for (const c of ent.cands) c.post /= survivorMass;
        dirty = true;
      }
      applied = true;
    } else {
      let changed = false;
      for (const c of ent.cands) {
        let f = 1;
        if (item !== null && c.item !== item) f *= BAYES_REV_KEEP;
        if (ability !== null && c.ability !== ability && !(p.mega && c.megaAbility === ability)) f *= BAYES_REV_KEEP;
        if (f !== 1) { c.post *= f; changed = true; }
      }
      if (changed) {
        let tot = 0;
        for (const c of ent.cands) tot += c.post;
        if (tot > 0) for (const c of ent.cands) c.post /= tot;
        dirty = true;
      }
      applied = changed;
    }
    logSnapshot(species, infLogTurn, { kind: 'revealed', item, ability, applied, hard: hardMode, excluded: hardMode ? excluded : 0 });
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
  const view = { nature: null, sp: {}, stat: {}, rows: {}, bayes: true, mapProb: map.post, speFlag: ent.speFlag || null, map: { nature: map.nature, item: map.item, sp: { ...map.sp } } };
  // 周辺分布の首位 (性格・持ち物): MAP は結合分布の最大であり、分布が
  // 拡散している局面では周辺の首位と食い違う。UI が表示で併記できるよう
  // 両方を渡す (採用する型そのものは従来どおり MAP)
  {
    const mN = new Map(), mI = new Map();
    for (const c of ent.cands) { mN.set(c.nature, (mN.get(c.nature) || 0) + c.post); mI.set(c.item, (mI.get(c.item) || 0) + c.post); }
    const topOf = m => { let bv = null, bp = -1; for (const [v, p] of m) if (p > bp) { bp = p; bv = v; } return { value: bv, mass: bp }; };
    view.marginals = { nature: topOf(mN), item: topOf(mI) };
  }
  // 未判明技の予測: 事後確率で重み付けした候補の技構成から、まだ判明していない
  // 技が含まれている確率を集計する (型予測と同じ事後分布の逆向きの出力)。
  // pokedb 候補の技は予測プロファイルなので、確定技構成より少し割り引く
  {
    const known = spec.knownMoves || [];
    const mp = new Map();
    for (const c of ent.cands) {
      const w = c.post * (c.moveExact ? 1 : 0.8);
      for (const mv of c.moves) if (!known.includes(mv)) mp.set(mv, (mp.get(mv) || 0) + w);
    }
    view.movePred = [...mp.entries()].map(([move, prob]) => ({ move, prob }))
      .filter(x => x.prob >= 0.08).sort((a, b) => b.prob - a.prob).slice(0, 6);
  }
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
    // メガ進化している相手は、候補のメガ後の実数値でレンジを作る
    const valOf = c => (spec.mega && c.valuesMega) ? c.valuesMega[k] : c.values[k];
    const byVal = ent.cands.filter(c => valOf(c) != null).sort((a, b) => valOf(a) - valOf(b));
    if (byVal.length) {
      acc = 0; let vlo = null, vhi = null;
      for (const c of byVal) {
        if (vlo === null && acc >= 0.05) vlo = valOf(c);
        acc += c.post;
        if (acc >= 0.95) { vhi = valOf(c); break; }
      }
      view.stat[k] = [vlo ?? valOf(byVal[0]), vhi ?? valOf(byVal[byVal.length - 1])];
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
// 選択中マッチアップについて、相手の事後上位候補 (累積90%) を通じた
// ダメージの最小〜最大を出す。MAP 型だけの通常表示に対する「型が違った場合の幅」。
// args: {mine, opp, field, side, critMine, critOpps, isSingleMine, isSingleOpps}
function candRanges(args) {
  const out = { mine: [null, null, null, null], opps: [null, null, null, null], acc: 0 };
  const opp = args.opp, mine = args.mine;
  const cov = bayesCover(opp.species);
  if (!cov) return out;
  out.acc = cov.acc;
  const F = { weather: args.field.weather, terrain: args.field.terrain };
  const sideFor = (atkKey, defKey) => ({
    atkSide: { isHelpingHand: !!args.side[atkKey === 'mine' ? 'mine' : 'opp'].hand },
    defSide: { isLightScreen: !!args.side[defKey === 'mine' ? 'mine' : 'opp'].light, isReflect: !!args.side[defKey === 'mine' ? 'mine' : 'opp'].reflect, isAuroraVeil: !!args.side[defKey === 'mine' ? 'mine' : 'opp'].veil, isFriendGuard: !!args.side[defKey === 'mine' ? 'mine' : 'opp'].guard, isSR: !!args.side[defKey === 'mine' ? 'mine' : 'opp'].rock, spikes: args.side[defKey === 'mine' ? 'mine' : 'opp'].spikes || 0 },
  });
  const run = (atkSpec, defSpec, defHp, moves, crit, atkKey, defKey, singleFn, dst) => {
    const sc = sideFor(atkKey, defKey);
    (moves || []).forEach((mv, mi) => {
      if (!mv || !defHp) return;
      // Zワザ/ダイマックス技は変換トグル経由でのみ正しい威力になる機構技で、
      // 候補横断の計算には変換を入れない (計算側の方針)。ダミー威力の幅を
      // 出さないよう対象外にする (moveData の isZ / isMax で判定)
      const md = moveData(mv);
      if (md && (md.isZ || md.isMax)) return;
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
    run(mine, candSpec, c.values.hp, mine.moves, args.critMine, 'mine', 'opps', args.isSingleMine, out.mine);
    // 相手候補の技 → 自分 (攻撃側が変動)
    const myTable = statTable(effSpecies(mine));
    const myHp = myTable ? (myTable.hp.find(r => r.sp === (mine.sp.hp || 0)) || {}).value : null;
    run(candSpec, mine, myHp, opp.moves, args.critOpps, 'opps', 'mine', args.isSingleOpps, out.opps);
  }
  return out;
}

  function reset() {
    inference = { seen: 0, bySpecies: {} };
    infCtx = { tailwindTurn: { p1: -99, p2: -99 }, screenTurn: { p1: {}, p2: {} }, trickRoomTurn: -99, hhTurn: { p1: -99, p2: -99 }, abBatches: {}, abPairs: new Set() };
    infLastMove = null;
    dirty = false;
    pendingOpts = null;
    infLog = []; infLogSeq = 0; infLogTurn = null; logTrigger = null;
    bayesReset();
    lastSpeCtx = null;
  }
  return {
    reset,
    resetBayes: bayesReset,
    entry: bayesEntry,
    cover: bayesCover,
    view: bayesView,
    fallbackView: estView,
    candSpec: bayesCandSpec,
    applyCounts: bayesApply,
    moveUpdate: bayesMoveUpdate,
    processDamageInf, processDamageBayes, processMoveInf, processMoveBayes,
    processAbility: infProcessAbility,
    applyRevealed, candRanges,
    setTeamContext,
    setMoveV2(v) { BAYES_MOVE_V2 = v; },
    takeDirty() { const d = dirty; dirty = false; return d; },
    takeInferenceLog,
    getSeen() { return inference.seen; },
    setSeen(n) { inference.seen = n; },
    _debug() { return { bayes, inference }; },
  };
}
