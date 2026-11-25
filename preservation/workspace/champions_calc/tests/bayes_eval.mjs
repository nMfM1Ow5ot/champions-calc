// 型推定エンジン (ベイズ) の効果測定ハーネス。
// data/meta_sets.json の実在型を真値として、
//   (a) 証拠なし時点で最有力候補 (MAP) と真値の近さ
//       … 性格・持ち物の一致率、SP 配分の距離 (6能力の |差| 合計の平均)
//   (b) ダメージ観測を K 回与えた後、真値に最も近い候補が事後確率で何位か
//       … 平均順位と top1 / top3 率 (コーパス混合 run では真値候補そのものの順位も)
// を、コーパス混合あり / pokedb のみ (対照) で比較する。
// 使い方: node tests/bayes_eval.mjs [観測回数=4]
// meta_sets.json が無い場合は測定をスキップして終了する (exit 0)。
// 恒常スイート (run_all.sh) には組み込まない手動測定用。
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const OBS = Math.max(1, parseInt(process.argv[2] || '4', 10) || 4);
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

const hook = `\n;globalThis.__T = { bayesEntry, bayesReset, bayesApply, bayesCandSpec,
  getMeta: () => META_SETS, setMeta: v => { META_SETS = v; META_SETS_LOADED = true; },
  dataReady: () => !!(POKEDB_PARSED && USAGE_SETS && META_SETS_LOADED) };\n`;
const tmp = ROOT + '/.bayes_eval_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);

const STATS = ['hp', 'atk', 'def', 'spa', 'spd', 'spe'];
const blankBoosts = () => ({ atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 });
const spDist = (a, b) => STATS.reduce((s, k) => s + Math.abs((a[k] || 0) - (b[k] || 0)), 0);

try {
  const bundle = await import(url.pathToFileURL(ROOT + '/bundle.mjs').href);
  const { damageRolls, withCurHP, statTable } = bundle;
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !T.dataReady()) await new Promise(r => setTimeout(r, 100));
  if (!T.dataReady()) { console.log('SKIP: pokedb データの読み込みが完了しませんでした'); process.exit(0); }
  const meta = T.getMeta();
  if (!meta || !Array.isArray(meta.sets) || !meta.sets.length) {
    console.log('SKIP: data/meta_sets.json が無いため測定できません (pokedb のみの動作は従来通り)');
    process.exit(0);
  }

  // 参照アタッカー (固定): 物理ガブリアス / 特殊ゲンガー
  const ATTACKERS = [
    { spec: { species: 'Garchomp', nature: 'Adamant', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, item: 'Life Orb', ability: 'Rough Skin', moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '' },
      moves: ['Earthquake', 'Dragon Claw', 'Stone Edge', 'Iron Head'] },
    { spec: { species: 'Gengar', nature: 'Modest', sp: { hp: 0, atk: 0, def: 0, spa: 32, spd: 0, spe: 32 }, item: 'Life Orb', ability: 'Cursed Body', moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '' },
      moves: ['Shadow Ball', 'Sludge Bomb', 'Thunderbolt', 'Focus Blast'] },
  ];
  const formeFull = (e) => !e.forme ? e.species : (e.forme.startsWith('-') ? e.species + e.forme
    : (e.forme.includes(e.species) ? e.forme : e.species + '-' + e.forme));

  function evaluate(truth, useCorpus) {
    T.setMeta(useCorpus ? meta : null);
    T.bayesReset();
    const species = truth.species;
    const ent = T.bayesEntry(species);
    if (!ent || !ent.cands.length) return null;
    const isMega = (truth.forme || '').includes('Mega') || formeFull(truth).includes('-Mega');
    const truthSp = {}; for (const k of STATS) truthSp[k] = (truth.sps && truth.sps[k]) || 0;
    // (a) 証拠なし: MAP と真値の近さ
    const map = ent.cands.reduce((a, b) => (b.post > a.post ? b : a));
    const a = {
      nature: map.nature === truth.nature,
      item: map.item === (truth.item || ''),
      spDist: spDist(map.sp, truthSp),
      forme: isMega ? (map.megaSpecies === formeFull(truth)) : null,
    };
    // (b) ダメージ観測: 真値が防御側。UI と同じ % 照合ルールで尤度を作る
    let b = null;
    if (!isMega) {
      const truthSpec = { species, nature: truth.nature, sp: truthSp, item: truth.item || '', ability: truth.ability || '',
        moves: truth.moves || [], curHPPercent: 100, boosts: blankBoosts(), status: '', mega: false };
      const table = statTable(species);
      const truthHP = table ? (table.hp.find(r => r.sp === truthSp.hp) || {}).value : null;
      let chosen = null;
      if (truthHP) {
        for (const atk of ATTACKERS) {
          for (const mv of atk.moves) {
            const { rolls } = damageRolls(withCurHP(atk.spec), withCurHP(truthSpec), mv, {});
            if (rolls && rolls.length >= 8 && Math.max(...rolls) > 0 && new Set(rolls).size >= 4) { chosen = { atk, mv, rolls }; break; }
          }
          if (chosen) break;
        }
      }
      if (chosen) {
        const base = { species, nature: 'Serious', sp: { hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, item: '', ability: '',
          moves: [], curHPPercent: 100, boosts: blankBoosts(), status: '', mega: false };
        const idxs = [2, 7, 11, 14, 0, 5, 9, 15, 3, 6].slice(0, OBS);
        for (const ri of idxs) {
          const pct = Math.round(chosen.rolls[ri % chosen.rolls.length] / truthHP * 100);
          if (!(pct > 0)) continue;
          const counts = ent.cands.map(c => {
            const hpVal = c.values.hp;
            if (!hpVal) return 0;
            const { rolls } = damageRolls(withCurHP(chosen.atk.spec), withCurHP(T.bayesCandSpec(base, c)), chosen.mv, {});
            let n = 0;
            for (const r of rolls) if (r > 0 && (Math.round(r / hpVal * 100) === pct || Math.floor(r / hpVal * 100) === pct)) n++;
            return n;
          });
          T.bayesApply(ent, counts);
        }
        const sorted = [...ent.cands].sort((x, y) => y.post - x.post);
        const nearest = (c) => spDist(c.sp, truthSp) * 10 + (c.nature === truth.nature ? 0 : 3) + (c.item === (truth.item || '') ? 0 : 3);
        let bestNear = Infinity, nearRank = -1;
        sorted.forEach((c, i) => { const d = nearest(c); if (d < bestNear) { bestNear = d; nearRank = i + 1; } });
        let exactRank = -1;
        sorted.forEach((c, i) => {
          if (exactRank < 0 && c.corpus && c.nature === truth.nature && c.item === (truth.item || '') && spDist(c.sp, truthSp) === 0) exactRank = i + 1;
        });
        b = { nearRank, exactRank };
      }
    }
    return { a, b, nCands: ent.cands.length, nCorpus: ent.cands.filter(c => c.corpus).length };
  }

  const agg = (rows) => {
    const A = rows.filter(r => r.a), B = rows.filter(r => r.b);
    const mean = xs => xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : null;
    const fmt = (x, d = 2) => x == null ? '-' : x.toFixed(d);
    return {
      n: rows.length,
      natureRate: fmt(mean(A.map(r => r.a.nature ? 1 : 0))),
      itemRate: fmt(mean(A.map(r => r.a.item ? 1 : 0))),
      spDist: fmt(mean(A.map(r => r.a.spDist)), 1),
      formeRate: fmt(mean(A.filter(r => r.a.forme != null).map(r => r.a.forme ? 1 : 0))),
      bN: B.length,
      nearRank: fmt(mean(B.map(r => r.b.nearRank))),
      nearTop1: fmt(mean(B.map(r => r.b.nearRank === 1 ? 1 : 0))),
      nearTop3: fmt(mean(B.map(r => r.b.nearRank <= 3 ? 1 : 0))),
      exactRank: fmt(mean(B.filter(r => r.b.exactRank > 0).map(r => r.b.exactRank))),
      exactN: B.filter(r => r.b.exactRank > 0).length,
    };
  };

  const mixedRows = [], controlRows = [];
  let skipped = 0;
  for (const truth of meta.sets) {
    const r1 = evaluate(truth, true);
    const r2 = evaluate(truth, false);
    if (!r1 || !r2) { skipped++; continue; }
    mixedRows.push(r1); controlRows.push(r2);
  }
  const M = agg(mixedRows), C = agg(controlRows);
  console.log(`== ベイズ推定 効果測定 (真値 ${meta.sets.length} 件 / 評価 ${M.n} 件 / スキップ ${skipped} 件, ダメージ観測 ${OBS} 回) ==`);
  console.log(`候補数 (平均): 混合 ${mixedRows.length ? (mixedRows.reduce((s, r) => s + r.nCands, 0) / mixedRows.length).toFixed(1) : '-'} (うちコーパス ${(mixedRows.reduce((s, r) => s + r.nCorpus, 0) / Math.max(1, mixedRows.length)).toFixed(1)}) / pokedbのみ ${controlRows.length ? (controlRows.reduce((s, r) => s + r.nCands, 0) / controlRows.length).toFixed(1) : '-'}`);
  console.log('(a) 証拠なし MAP の真値との一致');
  console.log(`  性格一致率:   混合 ${M.natureRate} / pokedbのみ ${C.natureRate}`);
  console.log(`  持ち物一致率: 混合 ${M.itemRate} / pokedbのみ ${C.itemRate}`);
  console.log(`  SP距離 (小さいほど近い): 混合 ${M.spDist} / pokedbのみ ${C.spDist}`);
  console.log(`  メガ型のフォルム一致率: 混合 ${M.formeRate}`);
  console.log(`(b) ダメージ観測 ${OBS} 回後: 真値最寄り候補の順位 (評価 ${M.bN} 件)`);
  console.log(`  平均順位: 混合 ${M.nearRank} / pokedbのみ ${C.nearRank}`);
  console.log(`  top1率:   混合 ${M.nearTop1} / pokedbのみ ${C.nearTop1}`);
  console.log(`  top3率:   混合 ${M.nearTop3} / pokedbのみ ${C.nearTop3}`);
  console.log(`  真値候補そのものの平均順位 (混合のみ, ${M.exactN} 件): ${M.exactRank}`);
} catch (e) {
  console.log('EXCEPTION: ' + (e && e.stack || e));
  process.exit(1);
} finally {
  fs.unlinkSync(tmp);
}
process.exit(0);
