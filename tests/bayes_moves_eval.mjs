// 技構成からの型予測 (技の所持尤度モデル) の効果測定ハーネス。
// data/meta_sets.json の実在型を真値として、真値の型をコーパスから1件抜いた
// leave-one-out 条件で、真値の技を 1〜3 個まで順に判明させたときの
//   (a) 最有力候補 (MAP) の性格・持ち物一致率
//   (b) 真値と技構成が最も重なる候補の事後順位
//   (c) 未判明技の予測 (bayesView.movePred) の上位3件への的中率と、
//       真値の残り技に付いた確率の合計
// を、新モデル (BAYES_MOVE_V2=true) と従来モデル (一律 0.2, false) で比較する。
// 使い方: node tests/bayes_moves_eval.mjs
// meta_sets.json が無い場合は測定をスキップして終了する (exit 0)。
// 恒常スイート (run_all.sh) には組み込まない手動測定用 (bayes_eval.mjs と同じ扱い)。
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
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

const hook = `\n;globalThis.__T = { bayesEntry, bayesReset, bayesMoveUpdate, bayesView,
  setMoveV2: v => { BAYES_MOVE_V2 = v; },
  getMeta: () => META_SETS, setMeta: v => { META_SETS = v; META_SETS_LOADED = true; },
  dataReady: () => !!(POKEDB_PARSED && USAGE_SETS && META_SETS_LOADED) };\n`;
const tmp = ROOT + '/.bayes_moves_eval_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);

const formeFull = (e) => !e.forme ? e.species : (e.forme.startsWith('-') ? e.species + e.forme
  : (e.forme.includes(e.species) ? e.forme : e.species + '-' + e.forme));
const mean = xs => xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
const fmt = (x, d = 2) => x == null ? '-' : x.toFixed(d);

try {
  await import(url.pathToFileURL(ROOT + '/bundle.mjs').href);
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !T.dataReady()) await new Promise(r => setTimeout(r, 100));
  if (!T.dataReady()) { console.log('SKIP: pokedb データの読み込みが完了しませんでした'); process.exit(0); }
  const meta = T.getMeta();
  if (!meta || !Array.isArray(meta.sets) || !meta.sets.length) {
    console.log('SKIP: data/meta_sets.json が無いため測定できません');
    process.exit(0);
  }

  function evaluate(truth, truthIdx, useV2) {
    T.setMoveV2(useV2);
    T.setMeta({ ...meta, sets: meta.sets.filter((_, i) => i !== truthIdx) });
    T.bayesReset();
    const species = formeFull(truth);
    const ent = T.bayesEntry(species);
    if (!ent || !ent.cands.length) return null;
    const truthMoves = truth.moves || [];
    if (truthMoves.length < 2) return null;
    const map = () => ent.cands.reduce((a, b) => (b.post > a.post ? b : a));
    const prior = { nature: map().nature === truth.nature, item: map().item === (truth.item || '') };
    const K = Math.min(3, truthMoves.length - 1);
    const revealed = [];
    let after = null;
    for (let k = 0; k < K; k++) {
      revealed.push(truthMoves[k]);
      T.bayesMoveUpdate(ent, species, [...revealed]);
    }
    const sorted = [...ent.cands].sort((a, b) => b.post - a.post);
    const overlap = c => (c.moves || []).filter(mv => truthMoves.includes(mv)).length;
    const maxOv = Math.max(...ent.cands.map(overlap));
    let bestRank = -1;
    sorted.forEach((c, i) => { if (bestRank < 0 && overlap(c) === maxOv) bestRank = i + 1; });
    const view = T.bayesView({ species, knownMoves: [...revealed] });
    const remaining = truthMoves.filter(mv => !revealed.includes(mv));
    let predHit = null, predMass = null;
    if (view && view.movePred) {
      const top3 = view.movePred.slice(0, 3).map(x => x.move);
      predHit = remaining.some(mv => top3.includes(mv)) ? 1 : 0;
      predMass = view.movePred.filter(x => remaining.includes(x.move)).reduce((s, x) => s + x.prob, 0);
    }
    after = {
      nature: map().nature === truth.nature, item: map().item === (truth.item || ''),
      bestRank, maxOv, predHit, predMass,
    };
    return { prior, after };
  }

  for (const useV2 of [true, false]) {
    const rows = [];
    let skipped = 0;
    meta.sets.forEach((truth, i) => {
      const r = evaluate(truth, i, useV2);
      if (!r) { skipped++; return; }
      rows.push(r);
    });
    const A = rows.map(r => r.after).filter(Boolean);
    console.log(`== 技構成予測 効果測定 [${useV2 ? '新モデル (採用率の重み付け+置換モデル+共起)' : '従来モデル (一律 0.2)'}] ==`);
    console.log(`  評価 ${rows.length} 件 / スキップ ${skipped} 件 (真値はコーパスから1件抜いた leave-one-out)`);
    console.log(`  判明前 MAP: 性格一致率 ${fmt(mean(rows.map(r => r.prior.nature ? 1 : 0)))} / 持ち物一致率 ${fmt(mean(rows.map(r => r.prior.item ? 1 : 0)))}`);
    console.log(`  技1〜3個判明後 MAP: 性格一致率 ${fmt(mean(A.map(r => r.nature ? 1 : 0)))} / 持ち物一致率 ${fmt(mean(A.map(r => r.item ? 1 : 0)))}`);
    console.log(`  真値と最も重なる候補の平均順位: ${fmt(mean(A.map(r => r.bestRank)))} (平均の重なり ${fmt(mean(A.map(r => r.maxOv)), 1)} 技)`);
    const P = A.filter(r => r.predHit != null);
    console.log(`  未判明技の予測: 上位3件への的中率 ${fmt(mean(P.map(r => r.predHit)))} / 残り技への確率合計の平均 ${fmt(mean(P.map(r => r.predMass)))} (評価 ${P.length} 件)`);
  }
} catch (e) {
  console.log('EXCEPTION: ' + (e && e.stack || e));
  process.exit(1);
} finally {
  fs.unlinkSync(tmp);
}
process.exit(0);
