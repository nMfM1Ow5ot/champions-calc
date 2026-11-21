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
  dirty = true;
}
function processDamageInf(ev, ctx) {
  pendingOpts = null; // このイベントに場の条件が付かなければベイズ側は対象外
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
  const table = statTable(oppSpecies);
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
  const myTable = statTable(mySpecies);
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
  // ベイズエンジン: 技の行動順と同じ尤度 (一致 16 / 同速 8 / 矛盾 0→下限)
  const ent = bayesEntry(oppSpecies);
  if (ent) {
    const counts = ent.cands.map(c => {
      if (c.values.spe == null) return 0;
      if (c.values.spe === myRaw) return 8;
      const ok = trick ? (firstIsOpp ? c.values.spe < myRaw : c.values.spe > myRaw) : (firstIsOpp ? c.values.spe > myRaw : c.values.spe < myRaw);
      return ok ? 16 : 0;
    });
    bayesApply(ent, counts);
  }
}
const NATURE_JA2EN = { 'がんばりや': 'Hardy', 'さみしがり': 'Lonely', 'ゆうかん': 'Brave', 'いじっぱり': 'Adamant', 'やんちゃ': 'Naughty', 'ずぶとい': 'Bold', 'すなお': 'Docile', 'のんき': 'Relaxed', 'わんぱく': 'Impish', 'のんてんき': 'Lax', 'おくびょう': 'Timid', 'せっかち': 'Hasty', 'まじめ': 'Serious', 'ようき': 'Jolly', 'むじゃき': 'Naive', 'ひかえめ': 'Modest', 'おっとり': 'Mild', 'れいせい': 'Quiet', 'てれや': 'Bashful', 'うっかりや': 'Rash', 'おだやか': 'Calm', 'おとなしい': 'Gentle', 'なまいき': 'Sassy', 'しんちょう': 'Careful', 'きまぐれ': 'Quirky' };
const BAYES_FLOOR = 0.02;    // 尤度の下限 (候補を完全に消さない)
const BAYES_REV_KEEP = 0.05; // 判明情報と矛盾する候補の減衰率
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
  const poolInfo = (pd.moves || []).map(mv => ({ en: (NAMES._moveJa2en || {})[mv.ja], rate: mv.rate || 0, cat: mv.cat || '' })).filter(x => x.en).slice(0, 10);
  const movePool = poolInfo.map(x => x.en).slice(0, 8);
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
      moves: profMoves, movePool, moveExact: false, values, valuesMega, post: 0, _w: combo.w * Math.max(item.rate, 0.3) * Math.max(ability.rate, 0.3) * wMul };
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
function bayesEntry(species) {
  syncData();
  if (!bayes) return null;
  if (!bayes.bySpecies[species]) {
    // 使用率データがまだ読み込めていない間は「候補なし」を確定させない
    if (!POKEDB_PARSED || !USAGE_SETS || !META_SETS_LOADED) return null;
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
  dirty = true;
}
function processDamageBayes(ev, ctx) {
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
    bayesApply(ent, counts);
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
    bayesApply(ent, counts);
  }
}
function processMoveBayes(ev, io) {
  const ctx = lastSpeCtx;
  if (!ctx || ctx.turn !== ev.turn) return;
  const ent = bayesEntry(ctx.species);
  if (!ent) return;
  const panel = io.opp[ctx.species] || null;
  const counts = ent.cands.map(c => {
    // メガ進化している相手の行動順は、メガ後のすばやさで判定する
    const speVal = (panel && panel.mega && c.valuesMega) ? c.valuesMega.spe : c.values.spe;
    if (speVal == null) return 0;
    // 候補の特性で優先度枠がずれる場合、その候補については順序は素早さ
    // ではなく枠で決まる (枠が上の候補は先行が確定、下なら先行はあり得ない)
    if (ctx.oppMd) {
      const cAb = panel && panel.mega && c.megaAbility ? c.megaAbility : c.ability;
      if (cAb === 'Gale Wings' && ctx.oppMd.type === 'Flying') return 16; // HP 条件で確定しないため中立
      const cBr = moveBracket(ctx.oppMd, cAb);
      if (cBr.last) return ctx.firstIsOpp ? 0 : 16;
      if (cBr.prio !== ctx.myPrio) return (cBr.prio > ctx.myPrio) === ctx.firstIsOpp ? 16 : 0;
    }
    const eff = infEffSpe(speVal, panel ? panel.boosts : {}, panel && panel.itemLost ? '' : c.item,
      panel ? panel.status : '', ctx.twP2, c.ability, io.field.weather, io.field.terrain, !!(panel && panel.unburden));
    if (eff === ctx.myEff) return 8; // 同速の可能性は中間
    const ok = ctx.trick ? (ctx.firstIsOpp ? eff < ctx.myEff : eff > ctx.myEff) : (ctx.firstIsOpp ? eff > ctx.myEff : eff < ctx.myEff);
    return ok ? 16 : 0;
  });
  bayesApply(ent, counts);
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
    const item = p.itemLost ? '' : (corr.includes('持ち物') ? (p.item || '') : null);
    const ability = corr.includes('特性') ? p.ability : null;
    const key = (item ?? '?') + '|' + (ability ?? '?');
    if (key === ent.revKey) continue;
    ent.revKey = key;
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
    setMoveV2(v) { BAYES_MOVE_V2 = v; },
    takeDirty() { const d = dirty; dirty = false; return d; },
    getSeen() { return inference.seen; },
    setSeen(n) { inference.seen = n; },
    _debug() { return { bayes, inference }; },
  };
}
