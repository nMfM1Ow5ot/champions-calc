// 型推定エンジン (ベイズ) の模擬対戦テスト (データ収集用ハーネス)。
// 用意した複数の相手型 (真値) に対して、自分の登録チームで擬似的にダメージを
// 発生させ、推定がターンごとに真値へどのくらい近づくかを計測する。
// 目的は推定の修正・改善に活かすデータ収集であり、恒常スイート (run_all.sh)
// には組み込まない手動実行用。実行ごとに JSON へ詳細記録を残す。
//
// 使い方:
//   node tests/bayes_sim.mjs [--seed 1] [--battles 60] [--turns 10]
//                            [--pool candidate|corpus] [--perturb 0.3]
//                            [--opp-atk 1] [--out <path>]
//   --pool candidate : 真値を候補 (pokedb 合成候補。コーパス候補は SP 不明の
//                      ため除外) の事前分布から抽選する (既定)
//   --pool corpus    : 真値を meta_sets の実在型とする (SP は公開情報が無い
//                      ため 0 扱い。bayes_eval と同じ前提)
//   --pool mine      : 真値を自分の登録チーム (my_team.json の6体、そのままの
//                      型) とする。ユーザーが登録した型への推定精度の計測用
//   --perturb        : 真値の SP を確率 p で少しずらす (候補集合に無い型の再現)
//   --opp-atk        : 相手の反撃 (実数ダメージ) も観測に含めるか (1=有効)
//
// 計測項目 (ターンごと): 性格・持ち物の一致率、MAP と真値の SP 距離、
// 真値最寄り候補の順位と事後確率、90% 区間 (SP・実数値) の真値カバー率と幅、
// 収束率 (性格・持ち物一致 かつ SP距離 <= 8) と初回収束ターンの分布。
// ダメージの尤度計算は UI の processDamageBayes と同じ % 照合ルール
// (round / floor の両対応) と実数照合を使い、仮定の撤廃を含む本番経路
// (bayesApply の bulk 適用) をそのまま通す。
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf('--' + name); return i >= 0 ? args[i + 1] : def; };
const SEED = parseInt(opt('seed', '1'), 10) || 1;
const BATTLES = Math.max(1, parseInt(opt('battles', '60'), 10) || 60);
const TURNS = Math.max(1, parseInt(opt('turns', '10'), 10) || 10);
const POOL = opt('pool', 'candidate');
const PERTURB = Math.min(1, Math.max(0, parseFloat(opt('perturb', '0.3')) || 0));
const OPP_ATK = opt('opp-atk', '1') !== '0';
const SPEED = opt('speed', '1') !== '0'; // 行動順 (素早さ) の証拠も生成するか
const ARCHETYPE = opt('archetype', ''); // 指定時はそのアーキタイプの真値だけを抽選する (弱点クラスの重点収集用)
const OUT = opt('out', path.join(ROOT, 'tests', 'sim_results', `sim_seed${SEED}_${POOL}.json`));

// ---- 乱数 (mulberry32: seed 固定で再現可能に) ----
let rngState = SEED >>> 0;
const rnd = () => { rngState = (rngState + 0x6D2B79F5) >>> 0; let t = rngState; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const rndInt = n => Math.floor(rnd() * n);
const pickWeighted = (items, w) => { let s = 0; for (const x of items) s += w(x); let r = rnd() * s; for (const x of items) { r -= w(x); if (r <= 0) return x; } return items[items.length - 1]; };
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = rndInt(i + 1); [a[i], a[j]] = [a[j], a[i]]; } return a; };

// ---- UI モジュールの読み込み (bayes_eval と同じスタブ) ----
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
  getMeta: () => META_SETS,
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
  const movePrio = mv => { try { return gen9.moves.get(mv)?.priority || 0; } catch { return 0; } };
  const speValue = spec => {
    const table = statTable(spec.species); if (!table) return null;
    const row = table.spe.find(r => r.nature === spec.nature && r.sp === (spec.sp?.spe || 0));
    return row ? row.value : null;
  };
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !(T.dataReady() && T.state.mine?.length === 6)) await new Promise(r => setTimeout(r, 100));
  if (!T.dataReady() || T.state.mine?.length !== 6) { console.log('SKIP: データ読み込みが完了しませんでした'); process.exit(0); }

  // ---- 攻撃側: 自分の登録チーム (state.mine) と、その使用可能攻撃技 ----
  const myTeamRaw = JSON.parse(fs.readFileSync(ROOT + '/my_team.json', 'utf8')).filter(x => x.species);
  const dummyDef = { species: 'Blastoise', nature: 'Serious', sp: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, item: '', ability: '', moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '', mega: false };
  const attackers = T.state.mine.map(spec => {
    const raw = myTeamRaw.find(x => x.species === spec.species) || {};
    const moves = (spec.moves?.length ? spec.moves : raw.moves || []).filter(mv => {
      try { const { rolls } = damageRolls(withCurHP(spec), withCurHP(dummyDef), mv, {}); return rolls && rolls.length >= 8 && Math.max(...rolls) > 0 && new Set(rolls).size >= 4; }
      catch { return false; }
    });
    return { spec, moves };
  }).filter(a => a.moves.length);
  if (!attackers.length) { console.log('SKIP: 使用可能な攻撃側がいません'); process.exit(0); }
  const myDefender = T.state.mine.find(x => x.species === 'Blastoise') || T.state.mine[0];

  // ---- 真値プール ----
  const dexRaw = JSON.parse(fs.readFileSync(ROOT + '/data/champions_dex.json', 'utf8'));
  const dexSpecies = Array.isArray(dexRaw) ? dexRaw : (dexRaw.species || Object.keys(dexRaw));
  const speciesList = shuffle(dexSpecies.filter(sp => { try { return !!T.bayesEntry(sp); } catch { return false; } }));
  const meta = T.getMeta();
  const corpusSets = (meta && Array.isArray(meta.sets)) ? meta.sets : [];
  if (POOL === 'corpus' && !corpusSets.length) { console.log('SKIP: meta_sets がありません'); process.exit(0); }

  const truthValues = (species, truth) => {
    const table = statTable(species); if (!table) return null;
    const v = {};
    for (const k of ['atk', 'def', 'spa', 'spd', 'spe']) { const row = table[k].find(r => r.nature === truth.nature && r.sp === (truth.sp[k] || 0)); v[k] = row ? row.value : null; }
    const hr = table.hp.find(r => r.sp === (truth.sp.hp || 0)); v.hp = hr ? hr.value : null;
    return v;
  };
  const perturbSp = sp => {
    const out = { ...sp };
    for (let n = 0; n < 2; n++) {
      const from = STATS[rndInt(6)], to = STATS[rndInt(6)];
      if (from === to) continue;
      const amt = Math.min(out[from] || 0, 2 + rndInt(5), 32 - (out[to] || 0));
      if (amt <= 0) continue;
      out[from] -= amt; out[to] = (out[to] || 0) + amt;
    }
    return out;
  };
  function makeTruth(battleIdx) {
    if (POOL === 'mine') {
      const spec = T.state.mine[battleIdx % T.state.mine.length];
      const sp = {}; for (const k of STATS) sp[k] = spec.sp?.[k] || 0;
      let out = { species: spec.species, nature: spec.nature, sp, item: spec.item || '', ability: spec.ability || '', moves: spec.moves || [], corpusTruth: false, perturbed: false };
      if (rnd() < PERTURB) { out = { ...out, sp: perturbSp(sp), perturbed: true }; }
      return out;
    }
    if (POOL === 'corpus') {
      const s = corpusSets[rndInt(corpusSets.length)];
      const sp = {}; for (const k of STATS) sp[k] = (s.sps && s.sps[k]) || 0;
      return { species: s.species, nature: s.nature, sp, item: s.item || '', ability: s.ability || '', moves: s.moves || [], corpusTruth: true, perturbed: false };
    }
    let species = speciesList[battleIdx % speciesList.length];
    let ent = T.bayesEntry(species);
    let pool = ent.cands.filter(c => !c.corpus);
    if (ARCHETYPE) {
      pool = pool.filter(c => archetype(c.sp) === ARCHETYPE);
      if (!pool.length) {
        // この種族に該当アーキタイプが無い場合は、持つ種族を順に探す
        for (let k = 1; k <= speciesList.length; k++) {
          const sp2 = speciesList[(battleIdx + k) % speciesList.length];
          const p2 = T.bayesEntry(sp2).cands.filter(c => !c.corpus && archetype(c.sp) === ARCHETYPE);
          if (p2.length) { species = sp2; ent = T.bayesEntry(sp2); pool = p2; break; }
        }
        if (!pool.length) return null;
      }
    }
    if (!pool.length) return null;
    const c = pickWeighted(pool, x => x.post);
    let sp = { ...c.sp }, perturbed = false;
    if (rnd() < PERTURB) { sp = perturbSp(sp); perturbed = true; }
    return { species, nature: c.nature, sp, item: c.item, ability: c.ability, moves: c.moves || [], corpusTruth: false, perturbed };
  }

  // ---- 1 試合のシミュレーション ----
  function runBattle(battleIdx) {
    const truth = makeTruth(battleIdx);
    if (!truth) return null;
    T.bayesReset();
    // 登録型プールでは、真値の所属チーム (自分の登録チーム) が相手チームとして
    // 分かっている状況を再現する (エンジンがチーム文脈を使う場合の計測用。
    // 未対応のエンジンでは無視される)
    if (POOL === 'mine' && T.estimator?.setTeamContext) T.estimator.setTeamContext(T.state.mine.map(x => x.species));
    const ent = T.bayesEntry(truth.species);
    if (!ent || !ent.cands.length) return null;
    const tVals = truthValues(truth.species, truth);
    if (!tVals || !tVals.hp) return null;
    const truthSpec = { species: truth.species, nature: truth.nature, sp: { ...truth.sp }, item: truth.item, ability: truth.ability, moves: truth.moves, curHPPercent: 100, boosts: blankBoosts(), status: '', mega: false };
    const base = { species: truth.species, nature: 'Serious', sp: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, item: '', ability: '', moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '', mega: false };
    const exactIdx = ent.cands.findIndex(c => c.nature === truth.nature && c.item === truth.item && c.ability === truth.ability && spDist(c.sp, truth.sp) === 0);
    const rows = [];
    let firstConverged = null;
    for (let turn = 0; turn <= TURNS; turn++) {
      if (turn > 0) {
        // 自分の攻撃 (% 観測)
        const atk = attackers[rndInt(attackers.length)];
        let myPair = null;
        for (let tries = 0; tries < 3; tries++) {
          const mv = atk.moves[rndInt(atk.moves.length)];
          const { rolls } = damageRolls(withCurHP(atk.spec), withCurHP(truthSpec), mv, {});
          if (!rolls || rolls.length < 8 || Math.max(...rolls) <= 0) continue;
          const pct = Math.round(rolls[rndInt(16)] / tVals.hp * 100);
          if (!(pct > 0)) continue;
          const counts = ent.cands.map(c => {
            const hpVal = c.values.hp; if (!hpVal) return 0;
            const r2 = damageRolls(withCurHP(atk.spec), withCurHP(T.bayesCandSpec(base, c)), mv, {}).rolls;
            let n = 0; for (const r of r2) if (r > 0 && (Math.round(r / hpVal * 100) === pct || Math.floor(r / hpVal * 100) === pct)) n++;
            return n;
          });
          T.bayesApply(ent, counts, true);
          myPair = { spec: atk.spec, move: mv };
          break;
        }
        // 相手の反撃 (実数観測) + 行動順 (素早さ) の証拠
        if (OPP_ATK && truth.moves.length && rnd() < 0.5) {
          for (let tries = 0; tries < 3; tries++) {
            const mv = truth.moves[rndInt(truth.moves.length)];
            let rolls; try { rolls = damageRolls(withCurHP(truthSpec), withCurHP(myDefender), mv, {}).rolls; } catch { continue; }
            if (!rolls || rolls.length < 8 || Math.max(...rolls) <= 0 || new Set(rolls).size < 4) continue;
            const amt = rolls[rndInt(16)];
            const counts = ent.cands.map(c => damageRolls(withCurHP(T.bayesCandSpec(base, c)), withCurHP(myDefender), mv, {}).rolls.filter(r => r === amt).length);
            T.bayesApply(ent, counts, true);
            // 行動順: 両者が同じターンに攻撃技を使った場合のみ。優先度が
            // 異なれば順序は素早さで決まらないため証拠にしない。本番の
            // processMoveBayes と同じ数え方 (一致 16 / 同速候補は中立 8 /
            // 不一致 0)。こだわりスカーフのみ実効値へ反映する
            if (SPEED && myPair) {
              const eff = (v, item) => item === 'Choice Scarf' ? Math.floor(v * 1.5) : v;
              const mySpe = speValue(myPair.spec), tSpe = tVals.spe;
              if (mySpe != null && tSpe != null && movePrio(myPair.move) === movePrio(mv)) {
                const myEff = eff(mySpe, myPair.spec.item), tEff = eff(tSpe, truth.item);
                if (tEff !== myEff) {
                  const firstIsOpp = tEff > myEff;
                  const scounts = ent.cands.map(c => {
                    const cs = eff(c.values.spe, c.item);
                    if (cs == null) return 0;
                    if (cs === myEff) return 8;
                    return (firstIsOpp ? cs > myEff : cs < myEff) ? 16 : 0;
                  });
                  T.bayesApply(ent, scounts);
                }
              }
            }
            break;
          }
        }
      }
      // スナップショット
      const sorted = [...ent.cands].sort((a, b) => b.post - a.post);
      const map = sorted[0];
      let nearest = null, nearestRank = null;
      {
        let best = Infinity;
        for (const c of ent.cands) { const d = spDist(c.sp, truth.sp) + (c.nature === truth.nature ? 0 : 0.5) + (c.item === truth.item ? 0 : 0.25); if (d < best) { best = d; nearest = c; } }
        nearestRank = sorted.indexOf(nearest) + 1;
      }
      const view = T.bayesView({ species: truth.species, mega: false, knownMoves: [] });
      let spCover = null, statCover = null, spWidth = null;
      if (view && view.sp && view.stat) {
        let cs = 0, cv = 0, w = 0;
        for (const k of STATS) {
          const rs = view.sp[k], rv = view.stat[k];
          if (Array.isArray(rs)) { if ((truth.sp[k] || 0) >= rs[0] && (truth.sp[k] || 0) <= rs[1]) cs++; w += rs[1] - rs[0]; }
          if (Array.isArray(rv) && tVals[k] != null && tVals[k] >= rv[0] && tVals[k] <= rv[1]) cv++;
        }
        spCover = cs / 6; statCover = cv / 6; spWidth = w / 6;
      }
      const natureHit = map.nature === truth.nature, itemHit = map.item === truth.item;
      const dist = spDist(map.sp, truth.sp);
      const converged = natureHit && itemHit && dist <= 8;
      if (converged && firstConverged === null) firstConverged = turn;
      rows.push({
        turn, used: ent.used, lifted: !!ent.hpLifted,
        natureHit, itemHit, spDist: dist, mapPost: +map.post.toFixed(4),
        mapNature: map.nature, mapItem: map.item, mapSp: { ...map.sp },
        nearestRank, nearestPost: nearest ? +nearest.post.toFixed(4) : null,
        exactRank: exactIdx >= 0 ? sorted.indexOf(ent.cands[exactIdx]) + 1 : null,
        spCover, statCover, spWidth: spWidth != null ? +spWidth.toFixed(2) : null,
        converged,
      });
    }
    return { species: truth.species, archetype: archetype(truth.sp), perturbed: truth.perturbed, corpusTruth: !!truth.corpusTruth, truth: { nature: truth.nature, item: truth.item, ability: truth.ability, sp: truth.sp }, firstConverged, rows };
  }

  const battles = [];
  for (let i = 0; i < BATTLES; i++) { const b = runBattle(i); if (b) battles.push(b); }

  // ---- 集計 ----
  const agg = [];
  for (let t = 0; t <= TURNS; t++) {
    const rs = battles.map(b => b.rows[t]).filter(Boolean);
    const mean = f => rs.length ? rs.reduce((s, r) => s + f(r), 0) / rs.length : null;
    const meanN = f => { const vs = rs.map(f).filter(v => v != null); return vs.length ? vs.reduce((s, v) => s + v, 0) / vs.length : null; };
    agg.push({
      turn: t, n: rs.length,
      natureHit: mean(r => r.natureHit ? 1 : 0), itemHit: mean(r => r.itemHit ? 1 : 0),
      spDist: mean(r => r.spDist), nearestRank: mean(r => r.nearestRank),
      exactTop1: meanN(r => r.exactRank == null ? null : (r.exactRank === 1 ? 1 : 0)),
      spCover: meanN(r => r.spCover), statCover: meanN(r => r.statCover), spWidth: meanN(r => r.spWidth),
      converged: mean(r => r.converged ? 1 : 0),
      convCum: battles.length ? battles.filter(b => b.firstConverged != null && b.firstConverged <= t).length / battles.length : null,
      lifted: mean(r => r.lifted ? 1 : 0),
    });
  }
  const archAgg = {};
  for (const b of battles) {
    const a = archAgg[b.archetype] = archAgg[b.archetype] || { n: 0, conv: 0, firstTurns: [], finalDist: [] };
    a.n++; if (b.firstConverged != null) { a.conv++; a.firstTurns.push(b.firstConverged); }
    a.finalDist.push(b.rows[b.rows.length - 1].spDist);
  }
  for (const a of Object.values(archAgg)) {
    a.firstTurns.sort((x, y) => x - y);
    a.medianFirst = a.firstTurns.length ? a.firstTurns[Math.floor(a.firstTurns.length / 2)] : null;
    a.meanFinalDist = a.finalDist.reduce((s, v) => s + v, 0) / a.finalDist.length;
    delete a.firstTurns; delete a.finalDist;
  }

  const result = { config: { seed: SEED, battles: battles.length, turns: TURNS, pool: POOL, perturb: PERTURB, oppAtk: OPP_ATK, speed: SPEED, archetype: ARCHETYPE || null }, perTurn: agg, archetypes: archAgg, battles };
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(result, null, 1));

  const f3 = v => v == null ? '  -  ' : v.toFixed(3);
  console.log(`== 模擬対戦テスト (seed ${SEED} / ${battles.length} 試合 / ${TURNS} ターン / pool=${POOL} perturb=${PERTURB} opp-atk=${OPP_ATK ? 1 : 0}) ==`);
  console.log('turn | 性格一致 | 持ち物一致 | SP距離 | 最寄り順位 | SP区間カバー | 区間幅 | 収束率 | 累積収束 | 撤廃率');
  for (const a of agg) console.log(
    String(a.turn).padStart(4), '|', f3(a.natureHit), '|', f3(a.itemHit), '|', a.spDist == null ? ' - ' : a.spDist.toFixed(1).padStart(5),
    '|', a.nearestRank == null ? ' - ' : a.nearestRank.toFixed(2).padStart(6), '|', f3(a.spCover), '|', a.spWidth == null ? ' - ' : a.spWidth.toFixed(1).padStart(5),
    '|', f3(a.converged), '|', f3(a.convCum), '|', f3(a.lifted));
  console.log('— アーキタイプ別 (最終ターンまで) —');
  for (const [k, a] of Object.entries(archAgg)) console.log(`  ${k}: n=${a.n} 収束 ${a.conv}/${a.n} 初回収束ターン中央値=${a.medianFirst} 最終SP距離平均=${a.meanFinalDist.toFixed(1)}`);
  console.log('詳細記録:', OUT);
} finally { fs.unlinkSync(tmp); }
process.exit(0);
