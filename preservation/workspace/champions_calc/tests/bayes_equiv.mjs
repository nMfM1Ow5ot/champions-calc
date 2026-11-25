// 型推定エンジンの等価性テスト (抽出・移行時の退行検知用)。
// 固定した証拠列 (state.json イベント列) を実コードへ流し、推定結果
// (候補と事後確率・ベイズ表示・旧エンジン表示・パネル反映・候補ダメージ幅) を
// 正規化 JSON として tests/bayes_equiv_golden.json と比較する。
// 使い方:
//   node tests/bayes_equiv.mjs           … ゴールデンと比較 (差分があれば exit 1)
//   node tests/bayes_equiv.mjs --record  … 現在の出力をゴールデンとして記録
// 推定処理を移す・直す変更では、意図した差分以外が出ないことを確認するために使う。
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const GOLDEN = path.join(ROOT, 'tests', 'bayes_equiv_golden.json');
const RECORD = process.argv.includes('--record');
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
  addEventListener() {},
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
  if (p.endsWith('ui_version.txt')) return resp('harness');
  const file = path.join(ROOT, p.replace(/^\.\//, ''));
  if (fs.existsSync(file)) return resp(fs.readFileSync(file, 'utf8'));
  return { ok: false, status: 404, text: async () => '', json: async () => { throw new Error('404'); } };
};

const hook = `\n;globalThis.__T = { get state(){ return state; }, get lastCalc(){ return lastCalc; },
  applyState, calcAll, bayesEntry, bayesView, estView, syncBayesRevealed,
  getBayes: () => estimator._debug().bayes, getInference: () => estimator._debug().inference };\n`;
const tmp = ROOT + '/.bayes_equiv_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);

const r6 = x => (typeof x === 'number' && isFinite(x)) ? Math.round(x * 1e6) / 1e6 : x;
function canon(v) {
  if (Array.isArray(v)) return v.map(canon);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) o[k] = canon(v[k]);
    return o;
  }
  return r6(v);
}
const B0 = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };

try {
  const bundle = await import(url.pathToFileURL(ROOT + '/bundle.mjs').href);
  const { damageRolls, withCurHP, statTable } = bundle;
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    if (T.state.mine?.length === 6 && T.state.mine[0]?.species === 'Blastoise' && T.bayesEntry('Garchomp')) break;
    await new Promise(r => setTimeout(r, 100));
  }
  if (!T.bayesEntry('Garchomp')) { console.log('FAIL: estimation data not loaded'); process.exit(1); }

  const mySpec = sp => T.state.mine.find(x => x.species === sp);
  const hpOf = (species, spec) => {
    const t = statTable(species);
    const row = t.hp.find(r => r.sp === (spec.sp.hp || 0));
    return row ? row.value : null;
  };
  // 真値 (固定): 相手ガブリアスとサーナイト
  const truthChomp = { species: 'Garchomp', nature: 'Jolly', sp: { hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, item: 'Focus Sash', ability: 'Rough Skin', moves: ['Earthquake'], curHPPercent: 100, boosts: { ...B0 }, status: '', mega: false };
  const truthVoir = { species: 'Gardevoir', nature: 'Timid', sp: { hp: 2, atk: 0, def: 0, spa: 32, spd: 0, spe: 32 }, item: 'Gardevoirite', ability: 'Trace', moves: ['Hyper Voice'], curHPPercent: 100, boosts: { ...B0 }, status: '', mega: false };
  const chompHP = hpOf('Garchomp', truthChomp);
  const myVoir = mySpec('Gardevoir');
  const myVoirHP = hpOf('Gardevoir', myVoir);

  const evBase = { w: '', t: '', crit: false, atkB: { ...B0 }, defB: { ...B0 }, atkS: '', defS: '', atkHp: 100, defHp: 100, atkAlive: 1, defAlive: 1 };
  // E1: 自分ブラストイズの Earth Power が相手ガブリアスへ (pct 証拠 ×4)
  const e1Rolls = damageRolls(withCurHP(mySpec('Blastoise')), withCurHP(truthChomp), 'Earth Power', { gameType: 'Singles' }).rolls;
  const evs = [3, 8, 12, 15].map((ri, i) => ({ k: 'dmg', atk: 'p1a: Blastoise', def: 'p2a: Garchomp', move: 'Earth Power', pct: Math.round(e1Rolls[ri] / chompHP * 100), turn: 1 + i, ...evBase }));
  // E2: 相手ガブリアスの Earthquake が自分サーナイトへ (amt 証拠 ×3)
  const e2Rolls = damageRolls(withCurHP(truthChomp), withCurHP(myVoir), 'Earthquake', { gameType: 'Singles' }).rolls;
  const evs2 = [2, 9, 14].map((ri, i) => ({ k: 'dmg', atk: 'p2a: Garchomp', def: 'p1a: Gardevoir', move: 'Earthquake', amt: e2Rolls[ri], turn: 5 + i, ...evBase }));
  // E3: 行動順 (mv) と特性発動順 (ab) の証拠
  const evs3 = [
    { k: 'mv', label: 'p2a: Garchomp', move: 'Earthquake', turn: 8 },
    { k: 'mv', label: 'p1a: Blastoise', move: 'Earth Power', turn: 8 },
    { k: 'ab', label: 'p2a: Gardevoir', ability: 'Trace', batch: 1, turn: 8 },
    { k: 'ab', label: 'p1a: Gardevoir', ability: 'Synchronize', batch: 1, turn: 8 },
  ];
  const all = [...evs, ...evs2, ...evs3];
  const payload = (events) => ({
    oppTeam: ['Garchomp', 'Gardevoir'],
    opps: [{ species: 'Garchomp', curHPPercent: 100 }, { species: 'Gardevoir', curHPPercent: 100 }],
    events, field: { weather: '', terrain: '' },
  });

  function snap(species) {
    const ent = T.bayesEntry(species);
    const pi = T.state.oppTeam.indexOf(species);
    const panel = pi >= 0 ? T.state.opps[pi] : null;
    const view = panel ? T.bayesView(panel) : null;
    return canon({
      cands: ent ? ent.cands.map(c => ({ n: c.nature, sp: c.sp, i: c.item, a: c.ability, ms: c.megaSpecies || null, ma: c.megaAbility || null, p: c.post, corp: !!c.corpus, mv: c.moves })) : null,
      used: ent ? ent.used : null,
      view: view ? { sp: view.sp, stat: view.stat, nature: view.nature, mapProb: view.mapProb, movePred: (view.movePred || []).slice(0, 5).map(x => [x.move, x.prob]) } : null,
      est: T.estView(species),
      panel: panel ? { nature: panel.nature, sp: panel.sp, estSp: panel.estSp, estStat: panel.estStat, estNature: panel.estNature, estMapProb: panel.estMapProb, estMovePred: panel.estMovePred } : null,
    });
  }
  const out = {};
  T.applyState(payload([]));
  out.cp0_init = { Garchomp: snap('Garchomp'), Gardevoir: snap('Gardevoir') };
  T.applyState(payload(evs));
  out.cp1_pct_damage = { Garchomp: snap('Garchomp'), Gardevoir: snap('Gardevoir') };
  T.applyState(payload([...evs, ...evs2]));
  out.cp2_amt_damage = { Garchomp: snap('Garchomp'), Gardevoir: snap('Gardevoir') };
  T.applyState(payload(all));
  out.cp3_speed_ability = { Garchomp: snap('Garchomp'), Gardevoir: snap('Gardevoir') };
  // E4: 判明情報 (持ち物・技) をパネルへ反映して減衰と技予測を動かす
  const pi = T.state.oppTeam.indexOf('Garchomp');
  const panel = T.state.opps[pi];
  panel.item = 'Life Orb';
  if (!panel.corrected.includes('持ち物')) panel.corrected.push('持ち物');
  panel.knownMoves = ['Earthquake', 'Dragon Claw'];
  T.syncBayesRevealed();
  T.calcAll();
  out.cp4_revealed = { Garchomp: snap('Garchomp'), Gardevoir: snap('Gardevoir') };
  // E5: 候補全体のダメージ幅 (選択中対面)
  T.state.sel.mine = T.state.mine.findIndex(x => x.species === 'Blastoise');
  T.state.sel.opps = pi;
  T.calcAll();
  out.cp5_cand_ranges = canon(T.lastCalc ? T.lastCalc.candRanges : null);
  // E6: メガ進化した相手の推定表示は、メガ後の実数値でレンジが作られる
  const vpi = T.state.oppTeam.indexOf('Gardevoir');
  T.state.opps[vpi].mega = true;
  T.calcAll();
  out.cp6_mega_view = { Gardevoir: snap('Gardevoir') };
  out.bayes_skipped = T.getBayes().skipped;

  const text = JSON.stringify(out, null, 1);
  if (RECORD) {
    fs.writeFileSync(GOLDEN, text + '\n');
    console.log('RECORDED golden: ' + GOLDEN);
  } else {
    if (!fs.existsSync(GOLDEN)) { console.log('FAIL: golden not found (run with --record first)'); process.exit(1); }
    const golden = fs.readFileSync(GOLDEN, 'utf8').trim();
    if (golden === text.trim()) { console.log('PASS bayes_equiv: outputs identical to golden'); process.exit(0); }
    const a = golden.split('\n'), b = text.trim().split('\n');
    console.log('FAIL bayes_equiv: differences vs golden (first 30 differing lines):');
    let shown = 0;
    for (let i = 0; i < Math.max(a.length, b.length) && shown < 30; i++) {
      if (a[i] !== b[i]) { console.log(`  L${i + 1}\n    golden: ${a[i]}\n    actual: ${b[i]}`); shown++; }
    }
    process.exit(1);
  }
} catch (e) {
  console.log('EXCEPTION: ' + (e && e.stack || e));
  process.exit(1);
} finally {
  fs.unlinkSync(tmp);
}
process.exit(0);
