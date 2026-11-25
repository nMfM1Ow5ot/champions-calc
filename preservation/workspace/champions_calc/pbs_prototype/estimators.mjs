// PBS 形式の型推定プロトタイプ（CTS Bo1 VGC 向け叩き台の検証コード）
// 設計は DESIGN.md。現行エンジン相当のベースライン (createBaseline) と
// PBS 版 (createPbs) を、同じ候補プール・同じ証拠で比較できるように実装する。
// 本番ファイル (estimate_engine.mjs 等) には一切触れない検証専用コード。
import { damageRolls, statTable, Generations } from '../bundle.mjs';

const gen9 = Generations.get(9);
export const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');

export const spDist = (a, b) => STATS.reduce((s, k) => s + Math.abs((a?.[k] || 0) - (b?.[k] || 0)), 0);

export function statVal(forme, nature, sps, stat) {
  const t = statTable(forme);
  if (!t) return null;
  if (stat === 'hp') { const r = t.hp.find(r => r.sp === (sps?.hp || 0)); return r ? r.value : null; }
  const r = t[stat].find(r => r.nature === nature && r.sp === (sps?.[stat] || 0));
  return r ? r.value : null;
}
export function effSpe(forme, nature, sps, item) {
  const v = statVal(forme, nature, sps, 'spe');
  if (v == null) return null;
  return item === 'Choice Scarf' ? Math.floor(v * 1.5) : v;
}
export function maxHp(forme, sps) { return statVal(forme, null, sps, 'hp'); }

function moveType(move) { try { return gen9.moves.get(idOf(move))?.type || null; } catch { return null; } }
function moveCat(move) { try { return gen9.moves.get(idOf(move))?.category || null; } catch { return null; } }
function typesOf(forme) { try { return gen9.species.get(idOf(forme))?.types || []; } catch { return []; } }
function effOf(move, defForme) {
  const t = moveType(move); if (!t) return 1;
  let e = 1;
  for (const dt of typesOf(defForme)) {
    const td = gen9.types.get(idOf(dt));
    const v = td?.effectiveness?.[t];
    e *= (typeof v === 'number' ? v : 1);
  }
  return e;
}

// ---- 候補プール ----
// corpus: vgc_pastes.json の sets 配列。excludeTeamIds は LOTO 用。
export function buildPools(corpusSetsRaw, { excludeTeamIds = new Set(), cap = 60, keyFn = null } = {}) {
  const keyOf = keyFn || (s => s.forme || s.species);
  const corpusSets = corpusSetsRaw.map(s => ({ ...s, forme: s.forme || s.species, _key: keyOf(s) }));
  const byForme = new Map();
  const teamSpecies = new Map(); // teamId -> Set(key)
  for (const s of corpusSets) {
    if (s.teamId && !excludeTeamIds.has(s.teamId)) {
      if (!teamSpecies.has(s.teamId)) teamSpecies.set(s.teamId, new Set());
      teamSpecies.get(s.teamId).add(s._key);
    }
  }
  for (const s of corpusSets) {
    if (s.teamId && excludeTeamIds.has(s.teamId)) continue;
    if (!byForme.has(s._key)) byForme.set(s._key, []);
    byForme.get(s._key).push({
      forme: s.forme, nature: s.nature, sps: s.sps || {}, item: s.item || null,
      ability: s.ability || null, moves: s.moves || [],
      w: (s.weight || 1), teamId: s.teamId || null, synthetic: false,
    });
  }
  const pools = new Map();
  for (const [forme, list] of byForme) {
    list.sort((a, b) => b.w - a.w);
    const top = list.slice(0, cap);
    // 尾: 周辺モードの合成候補（最頻の性格×持ち物×努力値配分の複合）を低質量で追加
    if (list.length) {
      const mode = key => {
        const c = new Map();
        for (const x of list) { const k = key(x); c.set(k, (c.get(k) || 0) + x.w); }
        return [...c.entries()].sort((a, b) => b[1] - a[1])[0][0];
      };
      const syn = {
        forme, nature: mode(x => x.nature), item: mode(x => x.item),
        ability: mode(x => x.ability), moves: JSON.parse(mode(x => JSON.stringify(x.moves))),
        sps: JSON.parse(mode(x => JSON.stringify(x.sps))),
        w: top.reduce((s, x) => s + x.w, 0) * 0.05, teamId: null, synthetic: true,
      };
      if (!top.some(x => x.nature === syn.nature && x.item === syn.item && spDist(x.sps, syn.sps) === 0)) top.push(syn);
    }
    for (const c of top) c.teamFormes = c.teamId ? [...(teamSpecies.get(c.teamId) || [])] : [];
    pools.set(forme, top);
  }
  return pools;
}

// ---- ダメージロールのキャッシュ ----
const rollCache = new Map();
export function rolls(atkSpec, defSpec, move) {
  const key = [atkSpec.forme || atkSpec.species, atkSpec.nature, atkSpec.item, JSON.stringify(atkSpec.sps),
    defSpec.forme || defSpec.species, defSpec.nature, defSpec.item, JSON.stringify(defSpec.sps), move].join('|');
  if (rollCache.has(key)) return rollCache.get(key);
  const spec = s => ({ species: s.forme || s.species, nature: s.nature, sps: s.sps, item: s.item, ability: s.ability, moves: s.moves });
  let out = [];
  try { out = damageRolls(spec(atkSpec), spec(defSpec), move, { gameType: 'Doubles' }).rolls || []; } catch { out = []; }
  rollCache.set(key, out);
  return out;
}

function normalize(cands) {
  const sum = cands.reduce((s, c) => s + c.p, 0);
  if (sum > 0) for (const c of cands) c.p /= sum;
}

// 観測倍率の上限つき更新 (PokaiTrainer 式: 1 回の観測で最大 maxRatio 倍)
function applyCapped(cands, likes, maxRatio) {
  const before = cands.map(c => c.p);
  let sum = 0;
  for (let i = 0; i < cands.length; i++) { cands[i].p *= likes[i]; sum += cands[i].p; }
  if (sum <= 0) { for (let i = 0; i < cands.length; i++) cands[i].p = before[i]; return false; }
  normalize(cands);
  if (maxRatio) {
    let changed = true, guard = 0;
    while (changed && guard++ < 8) {
      changed = false;
      for (let i = 0; i < cands.length; i++) {
        if (before[i] > 0 && cands[i].p / before[i] > maxRatio) { cands[i].p = before[i] * maxRatio; changed = true; }
      }
      normalize(cands);
    }
  }
  return true;
}

// ============ ベースライン (現行エンジン相当の近似) ============
export function createBaseline(pools) {
  const state = new Map(); // forme -> candidates with p
  function entry(forme) {
    if (!state.has(forme)) {
      const pool = pools.get(forme) || [];
      const cands = pool.map(c => ({ ...c, p: c.w }));
      normalize(cands);
      state.set(forme, cands);
    }
    return state.get(forme);
  }
  function hardFilter(forme, ok, keepFactor = 0.05) {
    const cands = entry(forme);
    if (!cands.length) return;
    if (cands.every(c => !ok(c))) { for (const c of cands) if (!ok(c)) c.p *= keepFactor; normalize(cands); return; }
    for (const c of cands) if (!ok(c)) c.p = 0;
    normalize(cands);
  }
  return {
    kind: 'baseline',
    entry,
    reveal(forme, { item, ability, move } = {}) {
      if (item) hardFilter(forme, c => c.item === item);
      if (ability) hardFilter(forme, c => c.ability === ability);
      if (move) hardFilter(forme, c => c.moves.includes(move), 0.1);
    },
    // 相手が攻撃 (候補=攻撃側)。amt は実数 (自軍の最大 HP 既知)
    damageBy(forme, move, defSpec, amt, defCurHp) {
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const rs = rolls(c, defSpec, move);
        if (!rs.length) return 1;
        const hit = rs.filter(r => Math.min(r, defCurHp) === amt).length;
        return Math.max(hit / rs.length, 0.02);
      });
      if (likes.every(l => l <= 0.02)) return; // 全滅なら更新しない (現行の skipped 相当)
      applyCapped(cands, likes, null);
    },
    // 自軍が攻撃 (候補=防御側)。観測は残り % (0-100, 整数)
    damageTo(forme, move, atkSpec, prevPct, nowPct) {
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const mh = maxHp(c.forme, c.sps); if (!mh) return 1;
        const rs = rolls(atkSpec, c, move);
        if (!rs.length) return 1;
        const hpB = Math.round(mh * prevPct / 100);
        const hit = rs.filter(r => Math.floor(100 * Math.max(0, hpB - r) / mh) === nowPct).length;
        return Math.max(hit / rs.length, 0.02);
      });
      if (likes.every(l => l <= 0.02)) return;
      applyCapped(cands, likes, null);
    },
    speed(forme, oppMovedFirst, ourSpeV, candMovePrio, ourPrio) {
      if (candMovePrio !== ourPrio) return;
      hardFilter(forme, c => {
        const s = effSpe(c.forme, c.nature, c.sps, c.item);
        if (s == null || ourSpeV == null) return true;
        return oppMovedFirst ? s > ourSpeV : s < ourSpeV;
      });
    },
    moveSeen(forme, move) {
      const cands = entry(forme); if (!cands.length) return;
      applyCapped(cands, cands.map(c => c.moves.includes(move) ? 1 : 0.1), null);
    },
    view(forme) { return viewOf(entry(forme)); },
  };
}

// ============ PBS 版 ============
export function createPbs(pools, { eps = 0.05, maxRatio = 20, actionChannel = true } = {}) {
  const state = new Map();
  let previewFormes = [];
  function entry(forme) {
    if (!state.has(forme)) {
      const pool = pools.get(forme) || [];
      const others = previewFormes.filter(f => f !== forme);
      const cands = pool.map(c => {
        // チーム条件づけ: 候補のチームが選出画面の他種族を何体含むかで補正
        const match = c.teamFormes ? others.filter(f => c.teamFormes.includes(f)).length : 0;
        return { ...c, p: c.w * Math.pow(1 + match, 1.5) };
      });
      normalize(cands);
      state.set(forme, cands);
    }
    return state.get(forme);
  }
  function softReveal(forme, ok) {
    const cands = entry(forme); if (!cands.length) return;
    applyCapped(cands, cands.map(c => ok(c) ? 1 : eps), maxRatio);
  }
  return {
    kind: 'pbs',
    entry,
    setPreview(formes) { previewFormes = formes.slice(); },
    reveal(forme, { item, ability, move } = {}) {
      if (item) softReveal(forme, c => c.item === item);
      if (ability) softReveal(forme, c => c.ability === ability);
      if (move) softReveal(forme, c => c.moves.includes(move));
    },
    damageBy(forme, move, defSpec, amt, defCurHp) {
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const rs = rolls(c, defSpec, move);
        if (!rs.length) return 1;
        return Math.max(rs.filter(r => Math.min(r, defCurHp) === amt).length / rs.length, eps);
      });
      applyCapped(cands, likes, maxRatio);
    },
    damageTo(forme, move, atkSpec, prevPct, nowPct) {
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const mh = maxHp(c.forme, c.sps); if (!mh) return 1;
        const rs = rolls(atkSpec, c, move);
        if (!rs.length) return 1;
        const hpB = Math.round(mh * prevPct / 100);
        return Math.max(rs.filter(r => Math.floor(100 * Math.max(0, hpB - r) / mh) === nowPct).length / rs.length, eps);
      });
      applyCapped(cands, likes, maxRatio);
    },
    // 自軍が攻撃 (候補=防御側)。観測はダメージ % (本番ハーネスの feedMyAttack と同じ形式):
    // ロールのうち round(r/最大HP*100) または floor(...) が観測 % に一致する割合を尤度とする
    damageToPct(forme, move, atkSpec, pct) {
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const mh = maxHp(c.forme, c.sps); if (!mh) return 1;
        const rs = rolls(atkSpec, c, move);
        if (!rs.length) return 1;
        const hit = rs.filter(r => r > 0 && (Math.round(r / mh * 100) === pct || Math.floor(r / mh * 100) === pct)).length;
        return Math.max(hit / rs.length, eps);
      });
      applyCapped(cands, likes, maxRatio);
    },
    // 行動順は結果の一種として柔らかく (同速・乱数・読み違いを floor で吸収)
    speed(forme, oppMovedFirst, ourSpeV, candPrio, ourPrio) {
      if (candPrio !== ourPrio) return;
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        const s = effSpe(c.forme, c.nature, c.sps, c.item);
        if (s == null || ourSpeV == null) return 1;
        if (s === ourSpeV) return 0.5;
        return (oppMovedFirst ? s > ourSpeV : s < ourSpeV) ? 1 : eps;
      });
      applyCapped(cands, likes, maxRatio);
    },
    // 行動による更新: その型がその技を選ぶ確率で条件づけ
    action(forme, move, targetForme) {
      if (!actionChannel) { // アブレーション: 技判明としてのみ処理
        const cands = entry(forme); if (!cands.length) return;
        applyCapped(cands, cands.map(c => c.moves.includes(move) ? 1 : eps), maxRatio);
        return;
      }
      const cands = entry(forme); if (!cands.length) return;
      const likes = cands.map(c => {
        if (!c.moves.includes(move)) return 0.01;
        const ws = c.moves.map(mv => {
          if (mv === 'Protect') return 0.6;
          const cat = moveCat(mv);
          if (cat !== 'Physical' && cat !== 'Special') return 0.35;
          return 0.2 + effOf(mv, targetForme);
        });
        const sum = ws.reduce((s, x) => s + x, 0) || 1;
        return Math.max(ws[c.moves.indexOf(move)] / sum, 0.05);
      });
      applyCapped(cands, likes, maxRatio);
    },
    view(forme) { return viewOf(entry(forme)); },
    // 世界サンプリング (判断側が使う想定の出力)
    sampleWorld(rng) {
      const out = {};
      for (const [forme, cands] of state) {
        let r = rng(), acc = 0, pick = cands[cands.length - 1];
        for (const c of cands) { acc += c.p; if (r <= acc) { pick = c; break; } }
        if (pick) out[forme] = pick;
      }
      return out;
    },
  };
}

export function viewOf(cands) {
  if (!cands.length) return null;
  const sorted = [...cands].sort((a, b) => b.p - a.p);
  const map = sorted[0];
  let acc = 0; const cover = [];
  for (const c of sorted) { cover.push(c); acc += c.p; if (acc >= 0.9) break; }
  return { map, mapP: map.p, cover, n: cands.length };
}
