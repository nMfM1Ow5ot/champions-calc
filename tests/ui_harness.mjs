// UI (ui.html) のヘッドレス検証ハーネス。
// ui.html の module スクリプトを DOM/fetch スタブ付きで実際に読み込み、
// state.json の投入シナリオで「画面に出るはずの状態」を検証する。
// 使い方: node tests/ui_harness.mjs (失敗があれば exit 1)
import fs from 'fs';
import path from 'path';
import url from 'url';

const ROOT = path.dirname(url.fileURLToPath(import.meta.url)) + '/..';
const html = fs.readFileSync(ROOT + '/ui.html', 'utf8');
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) { console.log('FAIL module script not found'); process.exit(1); }

// ---- DOM スタブ ----
function makeEl() {
  const el = {
    children: [], style: {}, dataset: {}, value: '', textContent: '', innerHTML: '',
    classList: { add() {}, remove() {}, toggle() {}, contains: () => false },
    addEventListener() {}, removeEventListener() {}, appendChild(c) { this.children.push(c); return c; },
    setAttribute() {}, getAttribute: () => null, remove() {}, focus() {}, click() {},
    querySelector: () => null, querySelectorAll: () => [],
    closest: () => null, getBoundingClientRect: () => ({ width: 0, height: 0, top: 0, left: 0 }),
  };
  return el;
}
const els = new Map();
globalThis.document = {
  getElementById: id => { if (!els.has(id)) els.set(id, makeEl()); return els.get(id); },
  querySelector: () => null, querySelectorAll: () => [],
  createElement: () => makeEl(), addEventListener() {},
  body: makeEl(), documentElement: makeEl(), hidden: false,
};
const lsStore = new Map();
globalThis.localStorage = { getItem: k => (lsStore.has(k) ? lsStore.get(k) : null), setItem(k, v) { lsStore.set(k, String(v)); }, removeItem(k) { lsStore.delete(k); } };
globalThis.location = { reload() { globalThis.__reloaded = true; } };
globalThis.matchMedia = () => ({ matches: false, addEventListener() {} });
if (!globalThis.navigator) globalThis.navigator = { clipboard: { writeText: async () => {} } };

// ---- fetch スタブ (プロジェクトの実ファイルを返す。state.json は差し替え可能) ----
let stateText = '{}';
globalThis.fetch = async (u) => {
  const p = String(u).split('?')[0];
  const resp = text => ({ ok: true, status: 200, text: async () => text, json: async () => JSON.parse(text) });
  if (p.endsWith('state.json')) return resp(stateText);
  if (p.endsWith('ui_version.txt')) return resp('harness');
  const file = path.join(ROOT, p.replace(/^\.\//, ''));
  if (fs.existsSync(file)) return resp(fs.readFileSync(file, 'utf8'));
  return { ok: false, status: 404, text: async () => '', json: async () => { throw new Error('404'); } };
};

// ---- モジュール読み込み (内部関数をテスト用に露出) ----
const hook = `\n;globalThis.__T = { get state(){ return state; }, applyState, applyMineTeamPreview, oppSpec, resetInference, sideChips, loadMyTeam, setFieldManual, calcAll, movesBox, ddListHTML, ddHTML, setFocusMode, effScopeSet, fallbackMovesFor, itemOptionsFor, abilityOptionsFor, moveOptionsFor, zInfoFor, buildMoveZs, drainInferenceLog, sendInferenceLog, inferBattleKey, playerBar, loadPresetStore, savePresetStore, savePreset, applyPreset, deletePreset, renamePreset, presetPopHTML, currentRegulation, marginalNoteHTML, attachEstimate, setSpecPatchData, specPatchVersions, activeSpecPatch, applySpecPatch, defaultSpecPatchId, dispStat, applySetterAbility, parseTeam, exportText, pokeTetsuURL, vgcBuildsFor, ensureVgcTeams, applyVgcTeam, formesOf, formePopHTML, spriteImg, spriteIdAlt, statsGrid, commitEstStat, get presetApplied(){ return presetApplied; }, get VGC_SETS(){ return VGC_SETS; }, get VGC_TEAMS(){ return VGC_TEAMS; }, get VGC_CORPUS(){ return VGC_CORPUS; }, get calcLog(){ return calcLog; }, markCalcSrc, get loadStatus(){ return loadStatus; }, get ui(){ return ui; }, get inferLog(){ return inferLog; }, get uiErrors(){ return uiErrors; }, flagBtnLabel, pressBattleFlag, flagBtnDisabled, get flagPhase(){ return flagPhase; }, get flagSeen(){ return flagSeen; }, get MINE_TEAM_PREVIEW_APPLY(){ return MINE_TEAM_PREVIEW_APPLY; }, applyLastUsedStartup, get lastUsedStartup(){ return lastUsedStartup; }, myTeamPreset, deriveBuild, get DDREG(){ return DDREG; }, get MOVE_OPTIONS(){ return MOVE_OPTIONS; }, get ITEM_OPTIONS(){ return ITEM_OPTIONS; }, get ABILITY_OPTIONS(){ return ABILITY_OPTIONS; }, get estimator(){ return estimator; }, get lastCalc(){ return lastCalc; }, get autoSideTurn(){ return autoSideTurn; }, noteVersionChange, resetVersionState, fetchCriticalJson, fillRevLine, get uiRevText(){ return uiRevText; }, get pendingReload(){ return pendingReload; }, get tempTrainerSets(){ return tempTrainerSets; }, confirmNewBattle, get presetRental(){ return presetRental; }, pokedbURL, supplementMineFromState, pokedbParsedFor, get NAMES(){ return NAMES; }, get NAT_JA2EN(){ return NAT_JA2EN; }, itemJa2en, z2h };\n`;
const tmp = ROOT + '/.ui_harness_module.mjs';
fs.writeFileSync(tmp, m[1] + hook);
let failures = 0;
const check = (name, cond) => { console.log((cond ? 'PASS ' : 'FAIL ') + name); if (!cond) failures++; };
try {
  await import(url.pathToFileURL(tmp).href);
  const T = globalThis.__T;
  // 初期化 (自チーム読み込み) の完了待ち
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (T.state.mine && T.state.mine.length === 6 && T.state.mine[0] && T.state.mine[0].species === 'Blastoise') break;
    await new Promise(r => setTimeout(r, 100));
  }
  // 件数だけでなく先頭の種族まで確認する。過去に my_team.json のチーム名
  // 番兵エントリで loadMyTeam が例外失敗し、内蔵プリセット (6体) のまま
  // 「読み込み成功」と誤判定した事故があったため
  check('init: my team loaded', T.state.mine?.length === 6 && T.state.mine[0]?.species === 'Blastoise');

  // loadMyTeam が本当にファイルの内容へ追随することの確認。デフォルト
  // プリセットと登録チームが同内容になったため、初期表示だけでは
  // 「ファイルを読めたか」と「フォールバックのままか」を区別できない。
  // 別内容のチームファイルに差し替えて読み直し、追随を検証する
  {
    const origFetch = globalThis.fetch;
    const altTeam = JSON.stringify([{ teamName: 'harness' },
      { species: 'Eevee', ability: 'てきおうりょく', item: '', moves: [], stats: null }]);
    globalThis.fetch = async (u) => {
      if (String(u).split('?')[0].endsWith('my_team.json')) {
        return { ok: true, status: 200, text: async () => altTeam, json: async () => JSON.parse(altTeam) };
      }
      return origFetch(u);
    };
    const okAlt = await T.loadMyTeam();
    check('loadMyTeam: follows file content', okAlt === true && T.state.mine?.length === 1 && T.state.mine[0]?.species === 'Eevee');
    globalThis.fetch = origFetch;
    const okBack = await T.loadMyTeam();
    check('loadMyTeam: restores registered team', okBack === true && T.state.mine?.length === 6 && T.state.mine[0]?.species === 'Blastoise');
  }

  // 実機の state.json の流れを再現する: 対戦開始 (oppReset + 空イベント) の後、
  // イベント配列が単調に伸びていく
  let evs = [];
  const newBattle = species => { evs = []; T.applyState({ oppReset: true, oppTeam: [species], opps: [], events: evs, field: {} }); };
  const sendMove = (species, move, turn = 1, side = 'p2') => {
    evs = [...evs, { k: 'mv', turn, label: `${side}a: ${species}`, move }];
    T.applyState({ events: evs });
  };

  // --- 場の状態イベント (オーロラベール/壁/おいかぜ) ---
  newBattle('Ninetales-Alola');
  sendMove('Ninetales-Alola', 'Aurora Veil');
  check('veil: veil chip on', T.state.side.opp.veil === true);
  check('veil: reflect stays off', T.state.side.opp.reflect === false);
  check('veil: light stays off', T.state.side.opp.light === false);
  check('veil: chip html shows veil on', /tgl primary on" data-sidechip="opp:veil"/.test(T.sideChips('opp')));

  newBattle('Ninetales-Alola');
  sendMove('Ninetales-Alola', 'Reflect');
  check('reflect: reflect on only', T.state.side.opp.reflect === true && T.state.side.opp.veil === false && T.state.side.opp.light === false);

  newBattle('Ninetales-Alola');
  sendMove('Ninetales-Alola', 'Light Screen');
  check('light: light on only', T.state.side.opp.light === true && T.state.side.opp.reflect === false && T.state.side.opp.veil === false);

  newBattle('Whimsicott');
  sendMove('Whimsicott', 'Tailwind');
  check('tailwind: tailwind on only', T.state.side.opp.tailwind === true && T.state.side.opp.reflect === false);

  // --- 対戦切り替え: battle キー (試合 ID) の変化で前の対戦の状態を初期化する ---
  // battle_20261121_132153 の再現: 前戦で自分のエルフーンがおいかぜを使い、
  // 次の対戦では oppReset が来ず、イベント列も縮まず、相手チームも前戦と
  // 同じだったため、従来の検知 (縮小 / 別チーム) では初期化されなかった
  evs = [];
  T.applyState({ battle: 'battle_A', oppTeam: ['Whimsicott'], opps: [], events: evs, field: {} });
  sendMove('Whimsicott', 'Tailwind', 5, 'p1');
  check('battlekey: tailwind on in battle A', T.state.side.mine.tailwind === true);
  const evsB = [
    { k: 'mv', turn: 1, label: 'p2a: Whimsicott', move: 'Protect' },
    { k: 'mv', turn: 1, label: 'p1a: Blastoise', move: 'Protect' },
    { k: 'mv', turn: 2, label: 'p2a: Whimsicott', move: 'Protect' },
  ];
  T.applyState({ battle: 'battle_B', oppTeam: ['Whimsicott'], opps: [], events: evsB, field: {} });
  check('battlekey: tailwind cleared on battle change', T.state.side.mine.tailwind === false);
  check('battlekey: autoSideTurn cleared on battle change', T.autoSideTurn.mine.tailwind === -99);

  // --- 天候/フィールドの手動編集: 実盤面が実際に変わるまで編集値を保持する ---
  T.applyState({ field: { weather: 'Sun', terrain: '' } });
  check('field: incoming weather applied', T.state.field.weather === 'Sun');
  T.setFieldManual('weather', 'Rain');
  T.applyState({ field: { weather: 'Sun', terrain: '' } });
  check('field: manual weather held while board unchanged', T.state.field.weather === 'Rain');
  T.applyState({ field: { weather: 'Sand', terrain: '' } });
  check('field: manual weather released when board changes', T.state.field.weather === 'Sand');
  T.setFieldManual('terrain', 'Psychic');
  T.applyState({ field: { weather: 'Sand', terrain: '' } });
  check('field: manual terrain held while board unchanged', T.state.field.terrain === 'Psychic');
  T.applyState({ field: { weather: 'Sand', terrain: 'Electric' } });
  check('field: manual terrain released when board changes', T.state.field.terrain === 'Electric');

  // ベールの期限切れ (5ターン)
  newBattle('Ninetales-Alola');
  sendMove('Ninetales-Alola', 'Aurora Veil', 1);
  sendMove('Blastoise', 'Protect', 7, 'p1');
  check('veil: expires after 5 turns', T.state.side.opp.veil === false);

  // --- 相手パネルの技 (使用率型 + フォルム) ---
  const champ = JSON.parse(fs.readFileSync(ROOT + '/data/champions_dex.json', 'utf8'));
  const usage = JSON.parse(fs.readFileSync(ROOT + '/data/usage_sets.json', 'utf8'));
  const { usageSpec, Generations } = await import(url.pathToFileURL(ROOT + '/bundle.mjs').href);
  const gen = Generations.get(9);
  const idOf = en => String(en).toLowerCase().replace(/[^a-z0-9]/g, '');
  let formeBad = 0, formeChecked = 0;
  for (const sp of champ.species) {
    const spec = T.oppSpec(sp, 'usage');
    const has = usageSpec(sp, usage.sets) ||
      (() => { const b = gen.species.get(idOf(sp))?.baseSpecies; return b && b !== sp && usageSpec(b, usage.sets); })();
    if (!has) continue;
    formeChecked++;
    if (!spec.moves || spec.moves.filter(Boolean).length === 0) { formeBad++; if (formeBad <= 8) console.log('  no moves: ' + sp); }
  }
  check(`panels: all ${formeChecked} usage-covered species/forme get moves`, formeBad === 0);

  // --- KO% は相手の現在 HP 前提 (両方向とも) ---
  T.resetInference();
  T.state.field.weather = ''; T.state.field.terrain = '';
  const blasIdx = T.state.mine.findIndex(s => s.species === 'Blastoise');
  T.state.sel.mine = blasIdx;
  T.state.opps = [T.oppSpec('Garchomp', 'usage')];
  T.state.sel.opps = 0;
  const koOf = (res, move) => { const row = (res?.[0]?.moveResults || []).find(r => r.move === move); return row?.vs?.[0]?.ko || ''; };
  const koN = t => /OHKO/.test(t) ? 1 : (t.match(/(\d+)HKO/) ? +t.match(/(\d+)HKO/)[1] : 99);
  T.calcAll();
  const eqFull = koOf(T.lastCalc.oppResults, 'Earthquake');
  const auraFull = koOf(T.lastCalc.results, 'Aura Sphere');
  check('ko%: opp move vs full HP is 2HKO class', koN(eqFull) === 2);
  T.state.mine[blasIdx].curHPPercent = 50; T.calcAll();
  check('ko%: opp move vs half HP becomes OHKO', koN(koOf(T.lastCalc.oppResults, 'Earthquake')) === 1);
  T.state.mine[blasIdx].curHPPercent = 100;
  T.state.opps[0].curHPPercent = 30; T.calcAll();
  check('ko%: my move improves as opp HP drops', koN(koOf(T.lastCalc.results, 'Aura Sphere')) < koN(auraFull));
  T.state.opps[0].curHPPercent = 100; T.calcAll();

  // --- 連続技ヒット数等の指定 (moveSpec) ---
  {
    const opp = T.oppSpec('Breloom', 'usage');
    opp.moves = ['Bullet Seed', 'Mach Punch', '', ''];
    T.state.opps = [opp];
    T.state.sel.opps = 0;
    T.resetInference();
    T.state.field.weather = ''; T.state.field.terrain = '';
    T.calcAll();
    const bsVs = () => T.lastCalc.oppResults[0].moveResults[0].vs[0];
    const defMax = bsVs().maxPct;
    opp.moveSpec = { 0: 5 };
    T.calcAll();
    check('movespec: 5 hits exceeds default damage', bsVs().maxPct > defMax);
    opp.moveSpec = { 0: 2 };
    T.calcAll();
    check('movespec: 2 hits is below default damage', bsVs().maxPct < defMax);
    const box = T.movesBox('opps', T.lastCalc.oppResults[0]);
    check('movespec: selector shown on the spec move row', box.includes('data-mspec="opps:0"'));
    check('movespec: no selector on a non-spec move row', !box.includes('data-mspec="opps:1"'));
    // コピー内容は Showdown 公式計算機と同じ詳細説明文 (desc) 形式
    check('copy: damage button carries the full desc text', box.includes('data-copy="') && box.includes('Bullet Seed') && box.includes(' -- '));
    opp.moveSpec = { 0: 5 };
    T.DDREG['move:opps:0'].onPick('Mach Punch');
    check('movespec: changing the move resets the spec', opp.moveSpec[0] === undefined && opp.moves[0] === 'Mach Punch');
  }

  {
    // 自分のポケモンもプルダウンで全種族から選べること + 英名併記と日英両対応検索
    const dd = T.DDREG['species:mine'];
    check('species-mine: dropdown registered', !!dd);
    check('species-mine: options cover all species/formes (>1300)', (dd?.options.length || 0) > 1300);
    const deox = dd?.options.find(o => o.v === 'Deoxys-Attack');
    check('species-mine: JA-sharing forme listed separately (Deoxys-Attack)', !!deox && deox.l === 'デオキシス (Deoxys-Attack)');
    const mew = dd?.options.find(o => o.v === 'Mew');
    check('species-mine: non-champions species selectable (Mew)', !!mew && mew.l === 'ミュウ (Mew)');
    const snor = dd?.options.find(o => o.v === 'Snorlax');
    check('species-mine: label has EN in parens', !!snor && snor.l === 'カビゴン (Snorlax)');
    check('search: EN query finds Snorlax', T.ddListHTML(dd, 'snorlax', 0).list.some(o => o.v === 'Snorlax'));
    check('search: JA query finds Snorlax', T.ddListHTML(dd, 'カビ', 0).list.some(o => o.v === 'Snorlax'));
    const selM = T.state.sel.mine;
    const before = T.state.mine[selM];
    before.curHPPercent = 37; before.boosts.atk = 2; before.status = 'brn';
    dd.onPick('Snorlax');
    check('species-mine: pick changes own species', T.state.mine[selM]?.species === 'Snorlax');
    check('species-mine: picked build has moves', (T.state.mine[selM]?.moves || []).filter(Boolean).length > 0);
    check('species-mine: pick resets HP/boosts/status', T.state.mine[selM]?.curHPPercent === 100 && (T.state.mine[selM]?.boosts.atk || 0) === 0 && !T.state.mine[selM]?.status);
    dd.onPick('Mew');
    check('species-mine: non-champions pick applies (Mew)', T.state.mine[selM]?.species === 'Mew' && !!T.lastCalc);
    const mv = T.MOVE_OPTIONS.find(o => o.v === 'Water Spout');
    check('moves: label has EN in parens', !!mv && mv.l.includes('(Water Spout)'));
  }

  {
    // チーム文脈の配線: 相手チームに地形展開役 (サイコメイカー) がいると、
    // 対応するシード持ち候補の事前確率が上がること
    const seedShare = () => {
      const ent = T.estimator.entry('Sneasler');
      if (!ent) return null;
      let seed = 0, tot = 0;
      for (const c of ent.cands) { tot += c.post; if (c.item === 'Psychic Seed') seed += c.post; }
      return tot > 0 ? seed / tot : null;
    };
    T.resetInference();
    T.applyState({ oppTeam: ['Sneasler', 'Blastoise', 'Garchomp', 'Rillaboom', 'Incineroar', 'Amoonguss'], events: [] });
    const sharePlain = seedShare();
    T.resetInference();
    T.applyState({ oppTeam: ['Indeedee-F', 'Sneasler', 'Blastoise', 'Garchomp', 'Rillaboom', 'Incineroar'], events: [] });
    const shareBoosted = seedShare();
    check('teamctx: seed share measurable', sharePlain !== null && shareBoosted !== null && sharePlain > 0);
    check('teamctx: terrain setter on team boosts seed prior', shareBoosted > sharePlain);
  }

  {
    // データ範囲の取り決め: 技・持ち物は regulation スコープで絞る /
    // 使用率セットが無い種族は習得技から初期技を補完する
    const regWins = T.effScopeSet(new Set(['A']), ['B', 'C']);
    check('scope: regulation list wins over universe', regWins.size === 2 && regWins.has('B'));
    const fbSet = T.effScopeSet(new Set(['A']), []);
    check('scope: empty regulation list falls back to champions_dex', fbSet.size === 1 && fbSet.has('A'));
    check('scope: MOVE_OPTIONS includes universe-only move', T.MOVE_OPTIONS.some(o => o.v === 'Baby-Doll Eyes'));
    check('scope: ITEM_OPTIONS includes universe-only item', T.ITEM_OPTIONS.some(o => o.v === 'Ability Shield'));
    check('scope: ITEM_OPTIONS includes Z crystals', T.ITEM_OPTIONS.some(o => o.v === 'Electrium Z'));
    check('scope: MOVE_OPTIONS excludes mechanism moves (Z/Max are toggle-only)', !T.MOVE_OPTIONS.some(o => o.v === 'Gigavolt Havoc') && !T.MOVE_OPTIONS.some(o => o.v === 'Max Lightning') && !T.MOVE_OPTIONS.some(o => o.v === 'G-Max Volt Crash'));
    check('scope: MOVE_OPTIONS includes Tera Blast', T.MOVE_OPTIONS.some(o => o.v === 'Tera Blast'));
    check('scope: Hidden Power variants are individually selectable', T.MOVE_OPTIONS.some(o => o.v === 'Hidden Power Fire') && T.MOVE_OPTIONS.some(o => o.v === 'Hidden Power Water') && T.MOVE_OPTIONS.some(o => o.v === 'Hidden Power'));
    check('scope: ABILITY_OPTIONS covers all calc abilities', T.ABILITY_OPTIONS.length >= 320 && T.ABILITY_OPTIONS.some(o => o.v === 'Stench'));
    const mew = T.oppSpec('Mew', 'usage');
    check('fallback: no-usage species gets 4 moves', Array.isArray(mew.moves) && mew.moves.filter(Boolean).length === 4);
    check('fallback: Mew top move is Future Sight (STAB, max power)', mew.moves[0] === 'Future Sight');
    check('fallback: filled moves are all selectable', mew.moves.every(m => T.MOVE_OPTIONS.some(o => o.v === m)));
  }

  // 使用率の期待値は固定値にせず、読み込んだ pokedb の生分布から導く
  // (シーズンが変わるたびに率が動いても壊れないように)。生分布の
  // 日本語名を英名へ写し、率の降順に並べたものを期待値とする
  const rateDist = (species, key) => {
    const e = T.pokedbParsedFor(species);
    if (!e || !Array.isArray(e[key])) return [];
    const map = key === 'moves' ? (T.NAMES._moveJa2en || {}) : key === 'abilities' ? (T.NAMES._abilityJa2en || {}) : null;
    return e[key].map(x => {
      // UI の各ビルダーと同じく z2h で正規化してから引く (pokedb 側は
      // 「アブソルナイトＺ」のように全角英字で書くことがある)。持ち物は
      // UI 自身の解決 (items_ja 補完を含む) を使う
      const jaName = T.z2h(x.name || x.ja || '');
      const en = key === 'natures' ? T.NAT_JA2EN[jaName] : key === 'items' ? T.itemJa2en(jaName) : (map ? map[jaName] : null);
      return { en, rate: x.rate };
    }).filter(d => d.en != null).sort((a, b) => b.rate - a.rate);
  };

  {
    // 性格プルダウン: その種族の使用率降順 + 色付き±表示。プリセット表記は半角かっこ
    T.state.opps[T.state.sel.opps] = T.oppSpec('Blastoise', 'usage');
    T.calcAll();
    const nd = T.DDREG['nature:opps'];
    check('nature: options count is 25', (nd?.options.length || 0) === 25);
    const ndist = rateDist('Blastoise', 'natures');
    check('nature: usage order for Blastoise follows the data', nd?.options[0]?.v === ndist[0]?.en && nd?.options[1]?.v === ndist[1]?.en && nd?.options[2]?.v === ndist[2]?.en);
    const mod = nd?.options.find(o => o.v === 'Modest');
    check('nature: Modest carries colored +/- marks', !!mod && mod.extra.includes('natp') && mod.extra.includes('+SPA') && mod.extra.includes('-ATK'));
    const topNat = nd?.options[0];
    check('nature: top nature carries usage % right of the marks', !!topNat && topNat.extra.includes(`${ndist[0]?.rate}%`) && topNat.extra.indexOf('natp') < topNat.extra.indexOf('ddrate'));
    const hardy = nd?.options.find(o => o.v === 'Hardy');
    check('nature: neutral nature has no marks', !!hardy && hardy.extra === '');
    check('nature: list HTML renders marks', T.ddListHTML(nd, '', -1).html.includes('natp'));
    T.state.opps[T.state.sel.opps] = T.oppSpec('Mew', 'usage');
    T.calcAll();
    const mewNats = T.DDREG['nature:opps']?.options || [];
    check('nature: no-data species is aiueo-sorted with no % (marks only)', mewNats.length === 25 && mewNats.every(o => !(o.extra || '').includes('ddrate')) && mewNats.every((o, i, a) => i === 0 || a[i - 1].l.localeCompare(o.l, 'ja') <= 0));
    check('labels: preset usage label uses half-width parens', T.DDREG['preset:opps']?.options[0]?.l === '使用率トップ型 (pokedb)');
  }

  {
    // 持ち物プルダウン: 使用率順 (% 併記) + 残りはあいうえお順
    const io = T.itemOptionsFor({ species: 'Blastoise' });
    check('items: empty option first', io[0]?.v === '');
    const idist = rateDist('Blastoise', 'items');
    check('items: usage order with % follows the data', io[1]?.v === idist[0]?.en && (io[1]?.extra || '').includes(`${idist[0]?.rate}%`) && io[2]?.v === idist[1]?.en);
    const rated = io.filter(o => o.extra);
    const tail = io.slice(1 + rated.length);
    check('items: tail has no % and is aiueo-sorted', tail.every(o => !o.extra) && tail.every((o, i) => i === 0 || tail[i - 1].l.localeCompare(o.l, 'ja') <= 0));
    check('items: all options preserved', io.length === T.ITEM_OPTIONS.length);
    const ioMew = T.itemOptionsFor({ species: 'Mew' });
    check('items: no-data species has no % and is fully aiueo-sorted', ioMew.every(o => !o.extra) && ioMew.slice(1).every((o, i, a) => i === 0 || a[i - 1].l.localeCompare(o.l, 'ja') <= 0));
    const ioBas = T.itemOptionsFor({ species: 'Basculegion' });
    const st = ioBas.find(o => o.v === 'Spell Tag');
    const stRate = (rateDist('Basculegion', 'items').find(d => d.en === 'Spell Tag') || {}).rate;
    check('items: Spell Tag uses the in-game hiragana name with its usage %', !!st && st.l === 'のろいのおふだ (Spell Tag)' && stRate != null && (st.extra || '').includes(`${stRate}%`));
    check('items: every item option carries a Japanese name', T.ITEM_OPTIONS.every(o => !o.v || o.l.includes(' (')));
    const ioLeek = T.ITEM_OPTIONS.find(o => o.v === 'Leek');
    check('items: Leek shows as ながねぎ', !!ioLeek && ioLeek.l === 'ながねぎ (Leek)');
  }

  {
    // 特性・技プルダウンも持ち物と同じ仕様 (使用率順 + %、残りはあいうえお順)
    const ao = T.abilityOptionsFor({ species: 'Blastoise' }, ['Torrent', 'Rain Dish']);
    const adist = rateDist('Blastoise', 'abilities');
    check('abilities: usage order with % follows the data', ao[0]?.v === adist[0]?.en && (ao[0]?.extra || '').includes(`${adist[0]?.rate}%`) && ao[1]?.v === adist[1]?.en && (ao[1]?.extra || '').includes(`${adist[1]?.rate}%`));
    check('abilities: non-mega dropdown covers all abilities (universe)', ao.length >= 320 && ao.some(o => o.v === 'Stench' && !o.extra));
    const mo = T.moveOptionsFor({ species: 'Blastoise' });
    const mdist = rateDist('Blastoise', 'moves');
    check('moves: empty option first, then usage order with % follows the data', mo[0]?.v === '' && mo[1]?.v === mdist[0]?.en && (mo[1]?.extra || '').includes(`${mdist[0]?.rate}%`) && mo[2]?.v === mdist[1]?.en);
    const mRated = mo.filter(o => o.extra);
    const mTail = mo.slice(1 + mRated.length);
    check('moves: tail has no % and is aiueo-sorted, all options preserved', mTail.every(o => !o.extra) && mTail.every((o, i) => i === 0 || mTail[i - 1].l.localeCompare(o.l, 'ja') <= 0) && mo.length === T.MOVE_OPTIONS.length);
    const moMew = T.moveOptionsFor({ species: 'Mew' });
    check('moves: no-data species has no % and is fully aiueo-sorted', moMew.every(o => !o.extra) && moMew.slice(1).every((o, i, a) => i === 0 || a[i - 1].l.localeCompare(o.l, 'ja') <= 0));
  }

  {
    // テラスタル: 攻撃側の STAB 変化と防御側のタイプ変化が計算に反映される
    const slotM = T.state.sel.mine, slotO = T.state.sel.opps;
    const savedM = T.state.mine[slotM], savedO = T.state.opps[slotO];
    const g = T.oppSpec('Gardevoir', 'usage'); g.moves = ['Moonblast', '', '', ''];
    T.state.mine[slotM] = g;
    T.state.opps[slotO] = T.oppSpec('Bulbasaur', 'usage');
    T.calcAll();
    const baseAtk = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    g.terastallized = true; g.teraType = 'Fairy';
    T.calcAll();
    const teraAtk = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    check('tera: attacker tera STAB increases damage', teraAtk > baseAtk * 1.2);
    check('tera: tera type dropdown registered (19 types)', (T.DDREG['tera:mine']?.options.length || 0) === 19);
    const bl = T.oppSpec('Blastoise', 'usage'); bl.moves = ['Surf', '', '', ''];
    T.state.mine[slotM] = bl;
    const b2 = T.oppSpec('Bulbasaur', 'usage');
    T.state.opps[slotO] = b2;
    T.calcAll();
    const baseDef = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    b2.terastallized = true; b2.teraType = 'Fire';
    T.calcAll();
    const teraDef = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    check('tera: defender tera type changes effectiveness (resist -> weak)', teraDef > baseDef * 3);
    T.state.mine[slotM] = savedM; T.state.opps[slotO] = savedO;
    T.calcAll();
  }

  {
    // 自チームの SET 欄: 相手側と同じ型選択方式 (登録型はカスタム表示、カスタム選択で登録型へ復帰)
    const slotM = T.state.sel.mine;
    const savedM = T.state.mine[slotM];
    T.state.mine[slotM] = { species: 'Gardevoir', sp: { hp: 2, spa: 32, spe: 32 }, nature: 'Timid', ability: 'Synchronize', item: 'Gardevoirite', moves: ['Hyper Voice'], curHPPercent: 100, boosts: { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 }, status: '' };
    T.calcAll();
    const stdOpts = dd => (dd?.options || []).filter(o => !o.divider && !o.v.startsWith('vgc:')).map(o => o.l).join('|');
    check('import: Champions-style EVs line (SP values, total 66) is read as SP directly', (() => { const t = T.parseTeam('Charizard-Mega-Y @ Charizardite Y\nAbility: Drought\nEVs: 32 Def / 2 SpA / 32 Spe\nTimid Nature\n- Heat Wave\n\nSylveon @ Fairy Feather\nAbility: Pixilate\nEVs: 23 HP / 32 Def / 10 SpA / 1 Spe\nModest Nature\n- Hyper Voice'); return t.length === 2 && t[0].species === 'Charizard-Mega-Y' && t[0].sp.def === 32 && t[0].sp.spa === 2 && t[0].sp.spe === 32 && t[1].sp.hp === 23 && t[1].sp.def === 32 && t[1].sp.spa === 10 && t[1].sp.spe === 1; })());
    check('poketetsu: button sits next to the type chips and URLs follow the yakkun Champions zukan scheme', html.includes('data-poketetsu="${side}"') && T.pokeTetsuURL({ species: 'Garchomp' }) === 'https://yakkun.com/ch/zukan/n445' && T.pokeTetsuURL({ species: 'Garchomp', mega: true, megaSpecies: 'Garchomp-Mega' }) === 'https://yakkun.com/ch/zukan/n445m' && T.pokeTetsuURL({ species: 'Charizard', mega: true, megaSpecies: 'Charizard-Mega-Y' }) === 'https://yakkun.com/ch/zukan/n6my' && T.pokeTetsuURL({ species: 'Indeedee-F' }) === 'https://yakkun.com/ch/zukan/n876f');
    check('vgcpastes: SET dropdown puts a from VGCPastes divider above the collected builds (kept under search, not selectable)', (() => { const list = T.vgcBuildsFor({ species: 'Garchomp' }); if (!list.length) return false; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps; T.state.oppTeam = ['Garchomp']; T.state.opps = [T.oppSpec('Garchomp', 'usage')]; T.state.sel.opps = 0; T.calcAll(); const dd = T.DDREG['preset:opps']; const di = dd ? dd.options.findIndex(o => o.divider) : -1; let ok = di > 0 && dd.options[di].l === 'from VGCPastes' && dd.options[di + 1] && dd.options[di + 1].v === 'vgc:0'; if (ok) { const r = T.ddListHTML(dd, '', 0); ok = r.html.includes('sdd-divider') && r.html.includes('from VGCPastes') && !r.list.some(o => o.divider); const r2 = T.ddListHTML(dd, 'zzz-no-match', 0); ok = ok && r2.html.includes('from VGCPastes'); } T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.calcAll(); return ok; })());
    check('vgcpastes: SET dropdown lists collected builds by Team Description and applies one wholesale', (() => { if (!T.VGC_SETS) return false; const list = T.vgcBuildsFor({ species: 'Garchomp' }); if (list.length < 10) return false; const e = list[0]; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps, savedActive = T.state.active.opps; T.state.oppTeam = ['Garchomp']; T.state.opps = [T.oppSpec('Garchomp', 'usage')]; T.state.sel.opps = 0; T.calcAll(); const dd = T.DDREG['preset:opps']; let ok = !!dd && dd.options.some(o => o.v === 'vgc:0' && o.l === e.build.label); if (ok) { dd.onPick('vgc:0'); const ns = T.state.opps[0]; ok = ns.kind === 'vgc:0' && ns.ability === e.build.ability && ns.item === e.build.item && ns.nature === e.build.nature && JSON.stringify(ns.moves) === JSON.stringify(e.build.moves) && (!e.build.sp || (ns.sp.atk === e.build.sp.atk && ns.sp.spe === e.build.sp.spe)); } T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.state.active.opps = savedActive; T.calcAll(); return ok; })());
    check('import: standard EVs are still divided by 8', (() => { const t = T.parseTeam('Garchomp @ Choice Scarf\nAbility: Rough Skin\nEVs: 4 HP / 252 Atk / 252 Spe\nAdamant Nature\n- Earthquake'); return t.length === 1 && t[0].sp.atk === 32 && t[0].sp.spe === 32 && t[0].sp.hp === 1; })());
    T.ensureVgcTeams();
    for (let i = 0; i < 100 && !T.VGC_TEAMS; i++) await new Promise(r => setTimeout(r, 20));
    check('preset: opening the popover auto-focuses the search input', html.includes('if (ui.presetPop) { const si = document.querySelector(`[data-presetsearch="${side}"]`); if (si) { si.focus();'));
    check('presetbtn: button sits left of the icons, styled like the SET dropdown, and shows the applied preset name', (() => { const bar = T.playerBar('opps'); const bi = bar.indexOf('data-presetbtn'); const ii = bar.indexOf('data-icon'); if (!(bi >= 0 && ii > bi)) return false; if (!/\.presetbtn\{[^}]*width:21rem/.test(html)) return false; T.savePreset('opps', 'ボタン表示テスト'); const store = T.loadPresetStore(); const idx = store.opps.findIndex(p => p.name === 'ボタン表示テスト'); if (idx < 0) return false; T.applyPreset('opps', idx); const bar2 = T.playerBar('opps'); const seg = bar2.slice(bar2.indexOf('data-presetbtn'), bar2.indexOf('data-presetbtn') + 400); const ok = T.presetApplied.opps === 'ボタン表示テスト' && seg.includes('ボタン表示テスト') && seg.includes('sdd-chev'); T.deletePreset('opps', idx); return ok && T.presetApplied.opps === ''; })());
    check('formes: Aegislash popup lists exactly Shield and Blade with bilingual labels (no internal Both, no BASE tile)', (() => { const f1 = T.formesOf('Aegislash-Blade'); const f2 = T.formesOf('Aegislash-Shield'); if (JSON.stringify(f1) !== JSON.stringify(['Aegislash-Blade', 'Aegislash-Shield']) || JSON.stringify(f2) !== JSON.stringify(f1)) return false; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps; T.state.oppTeam = ['Aegislash-Shield']; T.state.opps = [T.oppSpec('Aegislash-Shield', 'usage')]; T.state.sel.opps = 0; T.calcAll(); const h = T.formePopHTML('opps'); T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.calcAll(); return h.includes('ギルガルド (Aegislash-Blade)') && h.includes('ギルガルド (Aegislash-Shield)') && !h.includes('Both') && !h.includes('>BASE<'); })());
    check('formes: no species in the universe yields a forme outside champions_dex', (() => { const dex = new Set(JSON.parse(fs.readFileSync(new URL('../data/champions_dex.json', import.meta.url), 'utf8')).species); const vals = (T.DDREG['species:opps']?.options || []).map(o => o.v); if (!vals.length) return false; return vals.every(sp => T.formesOf(sp).every(f => dex.has(f))); })());
    check('sprites: Aegislash-Shield resolves to its own sprite and alt ids follow the Showdown file naming', (() => { const sh = T.spriteImg('Aegislash-Shield', 'Aegislash-Blade', ''); const bl = T.spriteImg('Aegislash-Blade', 'Aegislash-Blade', ''); return sh.includes('sprites/gen5/aegislash.png') && sh.includes('data-sid="aegislash"') && bl.includes('sprites/gen5/aegislash-blade.png') && T.spriteIdAlt('great-tusk') === 'greattusk' && T.spriteIdAlt('basculin-blue-striped') === 'basculin-bluestriped' && T.spriteIdAlt('necrozma-dawn-wings') === 'necrozma-dawnwings' && T.spriteIdAlt('rotom-wash') === 'rotomwash' && html.includes('img.dataset.alt'); })());
    check('vgc-corpus: the VGCPastes corpus is loaded and wired to the estimator via getData', !!T.VGC_CORPUS && Array.isArray(T.VGC_CORPUS.sets) && T.VGC_CORPUS.sets.length > 4000 && html.includes('VGC_SETS: VGC_CORPUS'));
    check('dataload: critical loaders are tracked with ok status (items_ja, corpus, meta, pokedb)', !!T.loadStatus.items_ja && T.loadStatus.items_ja.ok === true && !!T.loadStatus.vgc_pastes && T.loadStatus.vgc_pastes.ok === true && !!T.loadStatus.meta_sets && T.loadStatus.meta_sets.ok === true && !!T.loadStatus.pokedb_parsed && T.loadStatus.pokedb_parsed.ok === true);
    check('dataload: failures are surfaced and retried (warning element + retry scheduler)', html.includes('id="loadWarn"') && html.includes('data-loadretry') && html.includes('scheduleDataRetry') && html.includes('missingCriticalLoaders'));
    check('eststat-boost: estimated final stats reflect rank boosts, and committing the boosted value round-trips', (() => { const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps; const spec = T.oppSpec('Garchomp', 'usage'); spec.estStat = { hp: [180, 180], atk: [150, 150], def: [130, 130], spa: [145, 145], spd: [120, 120], spe: [160, 160] }; spec.boosts = { spa: 1 }; T.state.oppTeam = ['Garchomp']; T.state.opps = [spec]; T.state.sel.opps = 0; T.calcAll(); const st = (T.lastCalc && T.lastCalc.stats && T.lastCalc.stats.opps[0]) || { hp: 180, atk: 150, def: 130, spa: 145, spd: 120, spe: 160 }; const grid = T.statsGrid('opps', st); const m = grid.match(/data-statest="opps:spa"[^>]*value="(\d+)"/); let ok = !!m && m[1] === '217'; if (ok) { T.commitEstStat('opps', 'spa', '217'); ok = spec.sp.spa === 32 && ['Modest', 'Mild', 'Rash', 'Quiet'].includes(spec.nature) && !(spec.estStat && spec.estStat.spa); } T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.calcAll(); return ok; })());
    check('eststat-boost: estimated stat cells are colored green on boost and red on drop', (() => { const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps; const spec = T.oppSpec('Garchomp', 'usage'); spec.estStat = { hp: [180, 180], atk: [150, 150], def: [130, 130], spa: [145, 145], spd: [120, 120], spe: [160, 160] }; T.state.oppTeam = ['Garchomp']; T.state.opps = [spec]; T.state.sel.opps = 0; T.calcAll(); const st = { hp: 180, atk: 150, def: 130, spa: 145, spd: 120, spe: 160 }; const cell = () => { const g = T.statsGrid('opps', st); const mm = g.match(/<input data-statest="opps:spa" class="([^"]*)"[^>]*value="(\d+)"/); return mm ? { cls: mm[1], val: mm[2] } : null; }; spec.boosts = { spa: 1 }; const up = cell(); spec.boosts = { spa: -1 }; const down = cell(); spec.boosts = {}; const flat = cell(); T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.calcAll(); return !!up && up.val === '217' && up.cls.includes('pos') && !!down && down.val === '96' && down.cls.includes('neg') && !!flat && flat.val === '145' && !flat.cls.includes('pos') && !flat.cls.includes('neg'); })());
    check('vgcteam: preset popover has a search row and lists VGCPastes teams below the sync divider', (() => { if (!T.VGC_TEAMS || !T.VGC_TEAMS.teams.length) return false; const h = T.presetPopHTML('opps'); const searchIdx = h.indexOf('data-presetsearch="opps"'); const saveIdx = h.indexOf('data-presetname="opps"'); const syncIdx = Math.max(h.indexOf('data-presettoken'), h.indexOf('プリセットは')); const divIdx = h.indexOf('from VGCPastes'); const vgcIdx = h.indexOf('data-vgcteam="opps:'); if (!(saveIdx >= 0 && searchIdx > saveIdx && syncIdx > 0 && divIdx > syncIdx && vgcIdx > divIdx && h.includes(T.VGC_TEAMS.teams[0].description))) return false; T.ui.presetDraft.search.opps = 'zzz-no-such-team-zzz'; const h2 = T.presetPopHTML('opps'); T.ui.presetDraft.search.opps = ''; return h2.includes('from VGCPastes') && !h2.includes('data-vgcteam='); })());
    check('vgcteam: loading a collected team replaces the whole side', (() => { if (!T.VGC_TEAMS || !T.VGC_TEAMS.teams.length) return false; const t0 = T.VGC_TEAMS.teams[0]; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps, savedActive = T.state.active.opps; T.applyVgcTeam('opps', t0.teamId); const ok = T.state.opps.length === Math.min(6, t0.members.length) && T.state.opps[0].species === t0.members[0].species && T.state.oppTeam[0] === t0.members[0].species && T.state.opps[0].item === (t0.members[0].item || ''); T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.state.active.opps = savedActive; T.calcAll(); return ok; })());
    check('vgcteam: MC869 loads all 6 (incl. ZA megas) and non-mega formes are not treated as mega', (() => { if (!T.VGC_TEAMS) return false; const t = T.VGC_TEAMS.teams.find(x => x.teamId === 'MC869'); if (!t || t.members.length !== 6) return true; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps, savedActive = T.state.active.opps; T.applyVgcTeam('opps', 'MC869'); const aegi = T.state.opps.find(s2 => s2.species.startsWith('Aegislash')); const ok = T.state.opps.length === 6 && !!aegi && !aegi.mega && T.state.opps.some(s2 => s2.mega && s2.megaSpecies === 'Garchomp-Mega-Z'); T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.state.active.opps = savedActive; T.calcAll(); return ok; })());
    check('vgcpastes: a non-mega forme build (Indeedee-F) applies as that forme, not as a mega', (() => { const list = T.vgcBuildsFor({ species: 'Indeedee-F' }); if (!list.length) return false; const savedOpps = T.state.opps, savedTeam = T.state.oppTeam, savedSel = T.state.sel.opps, savedActive = T.state.active.opps; T.state.oppTeam = ['Indeedee-F']; T.state.opps = [T.oppSpec('Indeedee-F', 'usage')]; T.state.sel.opps = 0; T.calcAll(); const dd = T.DDREG['preset:opps']; let ok = !!dd && dd.options.some(o => o.v === 'vgc:0'); if (ok) { dd.onPick('vgc:0'); const ns = T.state.opps[0]; ok = ns.species === 'Indeedee-F' && !ns.mega; } T.state.opps = savedOpps; T.state.oppTeam = savedTeam; T.state.sel.opps = savedSel; T.state.active.opps = savedActive; T.calcAll(); return ok; })());
    check('preset: mine offers the same build kinds as opps', stdOpts(T.DDREG['preset:mine']) === stdOpts(T.DDREG['preset:opps']) && stdOpts(T.DDREG['preset:mine']).includes('使用率トップ型 (pokedb)'));
    check('preset: registered own-team build shows as custom', (T.DDREG['preset:mine']?.value || '') === 'custom');
    T.DDREG['preset:mine'].onPick('usage');
    const afterUsage = T.state.mine[slotM];
    check('preset: picking usage on mine applies the pokedb top build', afterUsage.kind === 'usage' && afterUsage.species === 'Gardevoir');
    T.DDREG['preset:mine'].onPick('custom');
    const restored = T.state.mine[slotM];
    check('preset: picking custom restores the registered own-team build', restored.species === 'Gardevoir' && restored.item === 'Gardevoirite' && restored.nature === 'Timid' && !restored.kind);
    T.state.mine[slotM] = savedM;
    T.calcAll();
  }

  {
    // Zワザ: 汎用 Z の威力上昇、専用 Z の解決、Z変化技の効果表示
    check('zmove: exclusive Z resolves (Pikachu + Volt Tackle + Pikanium Z)', T.zInfoFor({ species: 'Pikachu', item: 'Pikanium Z' }, 'Volt Tackle')?.name === 'Catastropika');
    check('zmove: generic Z name resolves (Thunderbolt)', T.zInfoFor({ species: 'Pikachu', item: 'Electrium Z' }, 'Thunderbolt')?.name === 'Gigavolt Havoc');
    check('zmove: status Z effect text (Hypnosis -> speed +1)', (T.zInfoFor({ species: 'Gengar' }, 'Hypnosis')?.fx || '').includes('すばやさ+1'));
    check('zmove: unknown move has no Z info', T.zInfoFor({ species: 'Gengar' }, 'Not A Move') === null);
    const slotM = T.state.sel.mine, slotO = T.state.sel.opps;
    const savedM = T.state.mine[slotM], savedO = T.state.opps[slotO];
    const pk = T.oppSpec('Pikachu', 'usage'); pk.moves = ['Thunderbolt', 'Volt Tackle', '', '']; pk.item = 'Electrium Z';
    T.state.mine[slotM] = pk;
    T.state.opps[slotO] = T.oppSpec('Bulbasaur', 'usage');
    T.calcAll();
    const base = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    pk.moveZ = { 0: true };
    T.calcAll();
    const zRow = T.lastCalc.results[0].moveResults[0].vs[0];
    check('zmove: generic Z boosts damage (175 BP)', zRow.maxPct > base * 1.7 && (zRow.desc || '').includes('Gigavolt Havoc'));
    pk.item = 'Pikanium Z'; pk.moveZ = { 1: true };
    T.calcAll();
    const exRow = T.lastCalc.results[0].moveResults[1].vs[0];
    check('zmove: exclusive Z used in calc (Catastropika)', (exRow.desc || '').includes('Catastropika'));
    T.state.mine[slotM] = savedM; T.state.opps[slotO] = savedO;
    T.calcAll();
  }

  {
    // ダイマックス: わざのダイマックス化、キョダイマックス技、HP 倍化
    const slotM = T.state.sel.mine, slotO = T.state.sel.opps;
    const savedM = T.state.mine[slotM], savedO = T.state.opps[slotO];
    const pk = T.oppSpec('Pikachu', 'usage'); pk.moves = ['Thunderbolt', '', '', '']; pk.item = '';
    T.state.mine[slotM] = pk;
    T.state.opps[slotO] = T.oppSpec('Bulbasaur', 'usage');
    T.calcAll();
    const baseVs = T.lastCalc.results[0].moveResults[0].vs[0];
    pk.dynamax = true;
    T.calcAll();
    const maxRow = T.lastCalc.results[0].moveResults[0].vs[0];
        check('dynamax: move becomes G-Max Volt Crash for Pikachu (130 BP)', (maxRow.desc || '').includes('G-Max Volt Crash') && (maxRow.desc || '').includes('130 BP'));
    check('dynamax: max move damage exceeds base move', maxRow.maxPct > baseVs.maxPct * 1.3);
    const garch = T.oppSpec('Garchomp', 'usage'); garch.moves = ['Earthquake', '', '', ''];
    const pk2 = T.oppSpec('Pikachu', 'usage');
    T.state.mine[slotM] = garch;
    T.state.opps[slotO] = pk2;
    T.calcAll();
    const baseDef = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
    pk2.dynamax = true;
    T.calcAll();
    const dmaxDef = T.lastCalc.results[0].moveResults[0].vs[0].maxPct;
        check('dynamax: defender HP doubles (damage % halves)', dmaxDef < baseDef * 0.6 && dmaxDef > baseDef * 0.4);
    T.state.mine[slotM] = savedM; T.state.opps[slotO] = savedO;
    T.calcAll();
  }

  {
    // 配置・ずれ修正: テラスタルはタイプ表示の下の独立行 (固定幅)、Zボタンはプルダウンの右横、
    // プルダウン開閉で要素が動かないための CSS
    check('layout: terastal button sits in its own row below the type line', html.includes('class="terarow"') && !html.includes('terawrap'));
    const teraSeg = html.slice(html.indexOf('class="terarow"'), html.indexOf('class="terarow"') + 320);
    check('layout: dynamax button left of terastal in the row below types', teraSeg.indexOf('data-dynamax') >= 0 && teraSeg.indexOf('data-dynamax') < teraSeg.indexOf('data-tera'));
    check('layout: tera dropdown space is reserved while off (no size change on toggle)', html.includes('.terarow .sdd{width:10.5rem') && html.includes('.sdd.teraoff{visibility:hidden') && html.includes("class=\"sdd teraoff'"));
    check('layout: terarow elements are evenly spaced (single uniform gap, no child margins)', html.includes('.terarow{display:flex; flex-wrap:wrap; align-items:center; column-gap:.35rem') && html.includes('.terarow>*{margin:0}') && html.includes('.terarow .tgl{white-space:nowrap; flex:none}'));
    check('layout: terarow spacing is glow-inclusive (on-state ring is inset, dd control has no outer shadow)', html.includes('.terarow .tgl.on{box-shadow:inset 0 0 0 1px rgba(33,150,243,.95)}') && html.includes('.terarow .sdd-control{box-shadow:none}'));
    check('layout: opp info line always renders with a reserved height (no shift on species switch)', html.includes('return `<div class="oppinfo">${marginalNoteHTML(spec)}</div>`;') && html.includes('.oppinfo{font-size:.9rem; color:var(--dim); margin:.6rem 1.2rem 0; line-height:1.5; min-height:calc(.9rem * 1.5 * 2)}'));
    check('layout: mega button space is reserved for non-mega species (header height stable)', html.includes('class="tgl megares" style="visibility:hidden"'));
    check('ability: every ability option carries a Japanese name (no EN-only labels)', T.ABILITY_OPTIONS.length === 320 && T.ABILITY_OPTIONS.every(o => o.l.includes(' (')) && T.ABILITY_OPTIONS.find(o => o.v === 'Mountaineer')?.l === 'マウンテニア (Mountaineer)' && T.ABILITY_OPTIONS.find(o => o.v === 'Rebound')?.l === 'リバウンド (Rebound)');
    // --- どくびし (Toxic Spikes) side condition: chip, 2 layers, calc passthrough ---
    T.state.side.opp.toxicSpikes = 2;
    const chipsTs = T.sideChips('opp');
    check('toxicspikes: chip renders with layer count (どくびし×2 at 2 layers)', chipsTs.includes('data-toxicchip="opp"') && chipsTs.includes('どくびし×2'));
    let tsCalcOk = false;
    try { T.calcAll(); tsCalcOk = !!T.lastCalc; } catch (e) { /* calc must accept toxicSpikes */ }
    check('toxicspikes: calcAll accepts toxicSpikes=2 on the defender side', tsCalcOk);
    T.state.side.opp.toxicSpikes = 0;
    try { T.calcAll(); } catch (e) { /* restore */ }
    check('toxicspikes: intent applier and court/clear handling exist', html.includes("it.t === 'toxicSpikes'") && html.includes('a.toxicSpikes = b.toxicSpikes') && html.includes('state.side[sk].toxicSpikes = 0'));
    // --- 判明した技は上から順に埋める ---
    T.resetInference();
    T.applyState({ oppReset: true, oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
    const gspec = () => T.state.opps.find(s => s && s.species === 'Garchomp');
    const usageTop4 = [...gspec().moves];
    const rv1 = 'Poison Jab', rv2 = 'Iron Head';
    check('reveal-order: test moves are outside the usage top4', !usageTop4.includes(rv1) && !usageTop4.includes(rv2));
    T.applyState({ opps: [{ species: 'Garchomp', revealed: { moves: [rv1] } }] });
    check('reveal-order: first revealed move fills slot 1', gspec().moves[0] === rv1);
    T.applyState({ opps: [{ species: 'Garchomp', revealed: { moves: [rv1, rv2] } }] });
    check('reveal-order: later revealed moves keep filling from the top in reveal order', gspec().moves[0] === rv1 && gspec().moves[1] === rv2);
    // --- 推論過程ログの蓄積 (エンジン側 takeInferenceLog の受け口) ---
    check('inferlog: drain is wired into applyState and archives records per battle', html.includes('estimator.takeInferenceLog()') && html.includes('drainInferenceLog();') && html.includes('inferArchive'));
    let drainSafe = true;
    try { T.drainInferenceLog(); } catch (e) { drainSafe = false; }
    check('inferlog: drain is safe before the engine provides takeInferenceLog, accumulation is an array', drainSafe && Array.isArray(T.inferLog));
    const inferLenBeforeReset = T.inferLog.length;
    T.resetInference();
    check('inferlog: resetInference keeps the accumulated log (archived per battle)', T.inferLog.length === inferLenBeforeReset);
    check('inferlog: send posts the full accumulation to /inference_log in the agreed shape', html.includes("fetch('./inference_log'") && html.includes("kind: 'inference-log'"));
    T.applyState({ battle: '20261121_224409', oppReset: true, oppTeam: ['Garchomp'], opps: [{ species: 'Garchomp', revealed: { moves: [rv1, rv2] } }], events: [], field: {} });
    check('inferlog: records are stamped with the battle key and the send key is derived bare', T.inferLog.length > 0 && T.inferLog[0].battle === '20261121_224409' && T.inferBattleKey() === '20261121_224409');
    const keptInferLen = T.inferLog.length;
    const keptFirstSeq = T.inferLog[0] && T.inferLog[0].seq;
    T.resetInference();
    check('inferlog: a mid-battle reset does not truncate the accumulated log', T.inferLog.length === keptInferLen && T.inferLog[0] && T.inferLog[0].seq === keptFirstSeq && T.inferLog[0].battle === '20261121_224409');
    check('inferlog: sends are serialized so a reset flush is never dropped', !html.includes('inferSendBusy') && html.includes('inferSendChain') && html.includes('inferPendingKeys'));
    let sendSafe = true;
    try { await T.sendInferenceLog(true); } catch (e) { sendSafe = false; }
    check('inferlog: send is a safe no-op away from localhost', sendSafe);
    // --- 試合中のダメ計ログ ---
    check('calclog: posting shape and endpoint are wired', html.includes("fetch('./calclog'") && html.includes("kind: 'calc-log'") && html.includes('CALCLOG_MAX'));
    const clBase = T.calcLog.length;
    T.markCalcSrc('user');
    T.state.field.weather = 'Rain'; T.calcAll();
    check('calclog: a user-triggered recalculation is recorded with its inputs and outputs', T.calcLog.length === clBase + 1 && T.calcLog[T.calcLog.length - 1].src === 'user' && T.calcLog[T.calcLog.length - 1].field.weather === 'Rain' && !!T.calcLog[T.calcLog.length - 1].mine && Array.isArray(T.calcLog[T.calcLog.length - 1].out.mine));
    T.calcAll();
    check('calclog: an unchanged recalculation is not recorded twice', T.calcLog.length === clBase + 1);
    T.state.field.weather = 'Sun'; T.calcAll();
    T.resetInference();
    check('calclog: thinned auto recalcs are flushed at reset and kept for the battle', T.calcLog.some(r => r.src === 'auto' && r.field.weather === 'Sun') && T.calcLog.length >= clBase + 1);
    T.state.field.weather = ''; T.calcAll();
    // --- チームプリセット (保存/切替/削除・両サイド) ---
    check('preset: button is rendered next to the rack on both sides', T.playerBar('mine').includes('data-presetbtn="mine"') && T.playerBar('opps').includes('data-presetbtn="opps"'));
    const mineFirst = T.state.mine[0].species;
    T.savePreset('mine', 'テスト構成');
    let store = T.loadPresetStore();
    check('preset: save stores the side builds under the given name', store.mine.length === 1 && store.mine[0].name === 'テスト構成' && store.mine[0].slots.length === T.state.mine.length && store.mine[0].slots[0].species === mineFirst);
    T.state.mine[0].species = 'Mew';
    T.state.mine[0].curHPPercent = 37;
    T.applyPreset('mine', 0);
    check('preset: switch restores the saved builds with fresh HP', T.state.mine[0].species === mineFirst && T.state.mine[0].curHPPercent === 100);
    const oppFirst = T.state.opps[0].species;
    T.savePreset('opps', '相手テスト');
    T.state.opps[0].species = 'Mew';
    T.applyPreset('opps', 0);
    check('preset: opponent switch restores builds and the team list', T.state.opps[0].species === oppFirst && T.state.oppTeam[0] === oppFirst);
    T.deletePreset('mine', 0);
    T.deletePreset('opps', 0);
    store = T.loadPresetStore();
    check('preset: delete removes the entry', store.mine.length === 0 && store.opps.length === 0);
    check('preset: popover offers save and lists entries', T.presetPopHTML('mine').includes('data-presetsave="mine"'));
    T.savePreset('opps', 'アイコン選択テスト');
    check('preset: icons and name form one combined load button', (() => { const h = T.presetPopHTML('opps'); const bi = h.indexOf('data-presetload="opps:'); if (bi < 0) return false; const btn = h.slice(bi, h.indexOf('</button>', bi)); return btn.includes('class="preseticons"') && btn.includes('class="presetnametext"') && btn.includes('アイコン選択テスト') && !html.includes('.preseticons[data-presetload]'); })());
    T.deletePreset('opps', T.loadPresetStore().opps.findIndex(p => p.name === 'アイコン選択テスト'));
    check('capture: buttons are always shown (no hostname-based hiding)', html.includes('id="camBox"') && html.includes('data-capture="ability"') && html.includes('data-capture="status"') && !html.includes("getElementById('camBox')"));
    check('itemicon: own rack picons carry the held item icon at the corner', T.playerBar('mine').includes('class="pitem"') && T.playerBar('mine').includes('sprites/items/gardevoirite.png') && T.playerBar('mine').includes('sprites/items/rocky-helmet.png'));
    check('itemicon: opponent rack picons carry the item icon too', T.playerBar('opps').includes('class="pitem"'));
    check('itemicon: corner overlay CSS and the fallback chain are wired', html.includes('.picon .pitem{position:absolute') && html.includes('data-ispr') && html.includes('sprites/itemicons/'));
    check('revline: current rev is shown in small text right under the title', html.includes('<div class="titlebox"><h1>チャンピオンズ ダメージ計算</h1><div class="revline" id="revLine"></div></div>') && html.includes('function fillRevLine') && html.includes("fetch('./ui_rev.txt'") && html.includes('.revline{font-size:1.36rem'));
    {
      // rev 表示は ui_rev.txt の版数を出し、変更検知用の指紋
      // (ui_version.txt) は出さない
      const origFetch2 = globalThis.fetch;
      globalThis.fetch = async (u) => {
        const p = String(u).split('?')[0];
        if (p.endsWith('ui_rev.txt')) return { ok: true, status: 200, text: async () => '20990101_0000', json: async () => ({}) };
        return origFetch2(u);
      };
      await T.fillRevLine();
      globalThis.fetch = origFetch2;
      check('revline: displays the ui_rev.txt value, not the version fingerprint', globalThis.document.getElementById('revLine').textContent === 'rev 20990101_0000' && T.uiRevText === '20990101_0000');
    }
    // --- プリセット欄の改善 (レギュレーション記録/絞り込み・名前変更・アイコン・下書き保持) ---
    T.savePreset('mine', 'レギュテスト');
    store = T.loadPresetStore();
    check('preset2: save records the current regulation', store.mine.length === 1 && store.mine[0].regulation === T.currentRegulation() && !!store.mine[0].regulation);
    const st2 = T.loadPresetStore();
    st2.mine.push({ name: '他レギュ', regulation: 'ZZZ-OLD', slots: store.mine[0].slots });
    st2.mine.push({ name: '旧データ', slots: store.mine[0].slots });
    T.savePresetStore(st2);
    const popHtml = T.presetPopHTML('mine');
    check('preset2: list is filtered to the current regulation, legacy entries stay visible', popHtml.includes('レギュテスト') && popHtml.includes('旧データ') && !popHtml.includes('他レギュ') && popHtml.includes('他のレギュレーションのプリセットが 1 件あります'));
    check('preset2: rows show the six member icons', (popHtml.match(/preseticon/g) || []).length >= 12);
    check('preset2: rename applies and rejects empty names', T.renamePreset('mine', 0, '新しい名前') === true && T.loadPresetStore().mine[0].name === '新しい名前' && T.renamePreset('mine', 0, '  ') === false);
    check('preset-unify: a preset saved on one side is the same list on the other side', T.loadPresetStore().opps.length === T.loadPresetStore().mine.length && T.loadPresetStore().opps[0] && T.loadPresetStore().opps[0].name === '新しい名前');
    check('preset-unify: renaming from the opponent side rewrites the shared list', T.renamePreset('opps', 0, '相手側から改名') === true && T.loadPresetStore().mine[0].name === '相手側から改名');
    T.renamePreset('mine', 0, '新しい名前');
    T.ui.presetDraft.save.mine = '下書きテスト';
    check('preset2: the name input renders the draft so re-renders keep the typed text', T.presetPopHTML('mine').includes('value="下書きテスト"'));
    delete T.ui.presetDraft.save.mine;
    check('preset2: focus preservation for the preset inputs is wired into renderAll', html.includes('presetFocus') && html.includes("ae.matches('[data-presetname]')"));
    T.savePresetStore({ mine: [], opps: [] });
    // --- プルダウン検索のかな区別なし ---
    const kanaDD = { value: '', options: [
      { v: 'Pixilate', l: 'フェアリースキン (Pixilate)' },
      { v: 'Modest', l: 'ひかえめ (Modest)' },
      { v: 'Blastoise', l: 'カメックス (Blastoise)' },
    ] };
    check('kana-search: hiragana query matches a katakana label', T.ddListHTML(kanaDD, 'ふぇありーすきん', -1).list.length === 1 && T.ddListHTML(kanaDD, 'ふぇありーすきん', -1).list[0].v === 'Pixilate');
    check('kana-search: katakana query matches a hiragana label', T.ddListHTML(kanaDD, 'ヒカエメ', -1).list.length === 1 && T.ddListHTML(kanaDD, 'ヒカエメ', -1).list[0].v === 'Modest');
    check('kana-search: mixed kana query matches, unrelated query does not', T.ddListHTML(kanaDD, 'かメッくす', -1).list.length === 1 && T.ddListHTML(kanaDD, 'ピカチュウ', -1).list.length === 0);
    // --- 推定の周辺分布の首位の併記 ---
    check('marginal: note renders the differing marginal leaders with masses', T.marginalNoteHTML({ estMarginal: { nature: { value: 'Bold', mass: 0.337 } } }).includes('ずぶとい') && T.marginalNoteHTML({ estMarginal: { nature: { value: 'Bold', mass: 0.337 } } }).includes('34%') && T.marginalNoteHTML({ estMarginal: { item: { value: 'Wise Glasses', mass: 0.28 } } }).includes('ものしりメガネ'));
    check('marginal: no note without a stored divergence', T.marginalNoteHTML({ estMarginal: null }) === '' && T.marginalNoteHTML({}) === '');
    check('marginal: attachEstimate keeps divergences only when the MAP probability is low', html.includes('view.mapProb < 0.5') && html.includes('view.marginals.nature.value !== view.map.nature'));
    // --- KO% の回復考慮 (きのみ / きんちょうかん / ねをはる / やどりぎのタネ) ---
    {
      const mi = T.state.sel.mine, oi = T.state.sel.opps;
      T.state.mine[mi] = Object.assign(T.oppSpec('Garchomp', 'usage'), { nature: 'Adamant', ability: 'Rough Skin', item: '', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 0 }, moves: ['Earthquake'] });
      const blissey = item => Object.assign(T.oppSpec('Blissey', 'usage'), { nature: 'Bold', ability: 'Natural Cure', item, sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Soft-Boiled'], ingrain: false });
      const koOf = () => { T.calcAll(); const row = T.lastCalc.results[0].moveResults.find(r => r.move === 'Earthquake'); return row.vs[0].ko; };
      T.state.opps[oi] = blissey('');
      const koNone = koOf();
      T.state.opps[oi] = blissey('Sitrus Berry');
      const koSitrus = koOf();
      check('ko-recovery: Sitrus Berry is factored into the KO text', koSitrus !== koNone && koSitrus.includes('Sitrus Berry recovery'));
      T.state.mine[mi].ability = 'Unnerve';
      check('ko-recovery: Unnerve on the attacking side disables the berry', koOf() === koNone);
      T.state.mine[mi].ability = 'Rough Skin';
      T.state.opps[oi] = Object.assign(blissey(''), { ingrain: true });
      const koIngrain = koOf();
      check('ko-recovery: Ingrain is factored into the KO text', koIngrain !== koNone && koIngrain.includes('Ingrain recovery'));
      T.state.opps[oi] = Object.assign(blissey(''), { seedHeal: true });
      check('ko-recovery: Leech Seed recovery on the defender is factored into the KO text', koOf() !== koNone);
      T.state.opps[oi] = blissey('');
      T.state.mine[mi].seedDmg = true;
      check('ko-recovery: the attacker being seeded does not feed the defender (damage/recovery are independent)', koOf() === koNone);
      T.state.mine[mi].seedDmg = false;
      T.state.opps[oi] = Object.assign(blissey(''), { seedDmg: true });
      check('ko-recovery: Leech Seed damage on the defender is factored into the KO text', koOf() !== koNone);
      T.state.opps[oi] = blissey('');
      check('ko-recovery: volatile toggles moved into the status dropdown next to Helping Hand', (() => { const seg = html.slice(html.indexOf('<div class="terarow">'), html.indexOf('<div class="terarow">') + 1200); return seg.includes('data-hand') && seg.includes('statusDDHTML(side, spec)') && seg.indexOf('data-hand') < seg.indexOf('statusDDHTML(side, spec)') && html.includes('data-vstatusbtn') && !html.includes('data-seeded=') && !html.includes('data-aquaring=') && !html.includes('data-ingrain=') && !html.includes('data-octolock=') && !T.sideChips('opp').includes('やどりぎのタネ') && !T.sideChips('mine').includes('てだすけ'); })());
      check('ko-recovery: status dropdown lists the nine conditions in order', (() => { const seg = html.slice(html.indexOf('const STATUS_DEFS'), html.indexOf('function statusActiveCount')); const keys = ['curse', 'seedDmg', 'seedHeal', 'aquaring', 'ingrain', 'octolock', 'bind', 'saltcure', 'nightmare']; let pos = -1; for (const k of keys) { const i = seg.indexOf(`'${k}'`); if (i < 0 || i < pos) return false; pos = i; } return seg.includes('のろい') && seg.includes('やどりぎのタネ（ダメージ）') && seg.includes('やどりぎのタネ（回復）') && seg.includes('まとわりつく') && seg.includes('しおづけ') && seg.includes('あくむ'); })());
      // 毎ターン変動: じきゅうりょく / たこがため / りゅうせいぐん が KO% に効く
      const litSpec = (o) => ({ boosts: {}, status: '', curHPPercent: 100, knownMoves: [], corrected: [], ...o });
      T.state.mine[mi] = litSpec({ species: 'Garchomp', ability: 'Rough Skin', nature: 'Adamant', item: 'Yache Berry', sp: { hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, moves: ['Earthquake'] });
      T.state.opps[oi] = litSpec({ species: 'Mudsdale', ability: 'Heavy Metal', nature: 'Impish', item: 'Leftovers', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Protect'] });
      T.calcAll();
      const koControl = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      T.state.opps[oi] = litSpec({ species: 'Mudsdale', ability: 'Stamina', nature: 'Impish', item: 'Leftovers', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Protect'] });
      T.calcAll();
      const koStamina = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      check('ko-dynamic: Stamina changes the KO text (defense rises per hit)', !!koControl && !!koStamina && koControl !== koStamina);
      T.state.opps[oi] = litSpec({ species: 'Mudsdale', ability: 'Heavy Metal', nature: 'Impish', item: 'Leftovers', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Protect'], octolock: true });
      T.calcAll();
      const koOcto = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      check('ko-dynamic: Octolock changes the KO text (defenses drop per turn)', !!koOcto && koOcto !== koControl && koOcto.includes('3HKO'));
      T.state.mine[mi] = litSpec({ species: 'Latios', ability: 'Levitate', nature: 'Modest', item: 'Soul Dew', sp: { hp: 2, atk: 0, def: 0, spa: 32, spd: 0, spe: 32 }, moves: ['Draco Meteor'] });
      T.state.opps[oi] = litSpec({ species: 'Blissey', ability: 'Natural Cure', nature: 'Bold', item: '', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Protect'] });
      T.calcAll();
      const koDraco = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      check('ko-dynamic: Draco Meteor accounts for the SpA drop per use', koDraco === 'possible 7HKO');
      // 状態プルダウンの継続ダメージ: のろい / あくむ (ねむり時のみ) / しおづけ (タイプで倍化)
      T.state.mine[mi] = litSpec({ species: 'Garchomp', ability: 'Rough Skin', nature: 'Adamant', item: '', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 0 }, moves: ['Earthquake'] });
      T.state.opps[oi] = litSpec({ species: 'Blissey', ability: 'Natural Cure', nature: 'Bold', item: '', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Protect'] });
      T.calcAll();
      const koBase2 = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      T.state.opps[oi].curse = true;
      T.calcAll();
      const curseRow = T.lastCalc.results[0].moveResults[0].vs[0];
      check('ko-status: Curse damage is factored into the KO text', curseRow.ko !== koBase2 && curseRow.desc.includes('Curse damage'));
      T.state.opps[oi].curse = false;
      T.state.opps[oi].nightmare = true;
      T.calcAll();
      check('ko-status: Nightmare does nothing while the defender is awake', T.lastCalc.results[0].moveResults[0].vs[0].ko === koBase2);
      T.state.opps[oi].status = 'slp';
      T.calcAll();
      check('ko-status: Nightmare damages a sleeping defender per turn', T.lastCalc.results[0].moveResults[0].vs[0].ko !== koBase2);
      T.state.opps[oi].status = '';
      T.state.opps[oi].nightmare = false;
      T.state.opps[oi].saltcure = true;
      T.calcAll();
      const koSalt = T.lastCalc.results[0].moveResults[0].vs[0].ko;
      T.state.opps[oi].terastallized = true;
      T.state.opps[oi].teraType = 'Water';
      T.calcAll();
      check('ko-status: Salt Cure hits harder against a Water type', koSalt !== koBase2 && T.lastCalc.results[0].moveResults[0].vs[0].ko !== koSalt);
      T.state.mine[mi] = Object.assign(T.oppSpec('Garchomp', 'usage'), { nature: 'Adamant', ability: 'Rough Skin', item: '', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 0 }, moves: ['Earthquake'] });
      T.state.opps[oi] = Object.assign(blissey(''), { aquaring: true });
      const koAqua = koOf();
      check('ko-recovery: Aqua Ring is factored into the KO text', koAqua !== koNone && koAqua.includes('Aqua Ring recovery'));
      T.state.opps[oi] = blissey('');
      T.calcAll();
      const baseMax = T.lastCalc.results[0].moveResults.find(r => r.move === 'Earthquake').vs[0].max;
      T.state.mine[mi].hand = true;
      T.calcAll();
      const handMax = T.lastCalc.results[0].moveResults.find(r => r.move === 'Earthquake').vs[0].max;
      check('ko-recovery: Helping Hand on the attacker boosts its damage', handMax > baseMax);
      T.state.mine[mi].hand = false;
      const bundleSrc = fs.readFileSync('bundle.mjs', 'utf8');
      check('ko-recovery: the recovery KO layer is in the bundle', bundleSrc.includes('recoveryKoText') && bundleSrc.includes('koChanceRec') && bundleSrc.includes('Ingrain recovery') && bundleSrc.includes('defAquaRing'));
      // ライブラリが返さない 9HKO 超でも KO% が表示される (がんせきふうじの事例。
      // 相手がじきゅうりょくだと防御が上がり続けて実際に倒せないため、特性を差し替えて確認する)
      T.state.mine[mi] = { species: 'Sneasler', ability: 'Unburden', nature: 'Adamant', item: 'Psychic Seed', sp: { hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, moves: ['Rock Tomb'], boosts: {}, status: '', curHPPercent: 100, knownMoves: [], corrected: [] };
      T.state.opps[oi] = Object.assign(T.oppSpec('Archaludon', 'usage'), { ability: 'Heavy Metal' });
      T.calcAll();
      const rtRow = T.lastCalc.results[0].moveResults.find(r => r.move === 'Rock Tomb');
      check('ko-recovery: beyond-9HKO damage still shows a KO label', !!rtRow && /possible \d+HKO/.test(rtRow.vs[0].ko || ''));
    }
    // --- 仕様差分レイヤー ---
    {
      const mi = T.state.sel.mine, oi = T.state.sel.opps;
      T.state.mine[mi] = Object.assign(T.oppSpec('Garchomp', 'usage'), { nature: 'Adamant', ability: 'Rough Skin', item: '', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 0 }, moves: ['Earthquake'] });
      T.state.opps[oi] = Object.assign(T.oppSpec('Blissey', 'usage'), { nature: 'Bold', ability: 'Natural Cure', item: '', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, moves: ['Soft-Boiled'], ingrain: false });
      const rangeOf = () => { T.calcAll(); const row = T.lastCalc.results[0].moveResults.find(r => r.move === 'Earthquake'); return row.vs[0].min + '-' + row.vs[0].max; };
      const base = rangeOf();
      T.setSpecPatchData({ versions: [{ id: 'testpatch', label: 'テスト調整', species: { Garchomp: { baseStats: { atk: 200 } } }, moves: { Earthquake: { basePower: 50 } } }] });
      T.applySpecPatch('testpatch');
      const patched = rangeOf();
      check('specpatch: a registered patch changes the affected calc', patched !== base && T.activeSpecPatch() && T.activeSpecPatch().id === 'testpatch' && T.specPatchVersions().length === 1);
      T.applySpecPatch(null);
      check('specpatch: removing the patch restores the exact baseline', rangeOf() === base && T.activeSpecPatch() === null);
      T.setSpecPatchData({ versions: [] });
      check('specpatch: the topbar selector offers the current spec', html.includes('id="specSel"') && html.includes('現行仕様'));
      check('specpatch: the regulation default applies only without a saved choice', T.defaultSpecPatchId({ specPatch: 'vX' }) === 'vX' && T.defaultSpecPatchId({ specPatch: null }) === null && T.defaultSpecPatchId(null) === null);
    }
    // --- プリセットの共有 (localhost ⇔ デバック用ページ) ---
    check('init-watchdog: a standalone watchdog offers a cache-busting reload when panels never render', html.includes('id="loadwatchBtn"') && html.includes("querySelector('.playerbar')") && html.includes('searchParams.set'));
    check('preset-sync: saves stamp updatedAt and the popover shows the sharing UI', !!T.loadPresetStore().updatedAt && T.presetPopHTML('mine').includes('共有'));
    check('preset-sync: the token row renders off-localhost and both sync routes are wired', T.presetPopHTML('mine').includes('data-presettoken') && html.includes('api.github.com/repos/nMfM1Ow5ot/champions-calc/contents/presets.json') && html.includes("fetch('./presets'"));
    check('layout: terastal button has a fixed width (size never changes on toggle)', html.includes('.terarow .tgl[data-tera]{width:6rem'));
    check('layout: scrollbar gutter is stable (no shift on rerender)', html.includes('html{scrollbar-gutter:stable}'));
    check('layout: bare dropdown input matches closed height', html.includes('.sdd.bare .sdd-input{font-size:1.3rem; font-weight:700; padding:.1rem 0}'));
    check('layout: opening a dropdown keeps focus in its search input', html.includes('else { e.preventDefault(); openDD(id); }'));
    check('layout: pressing the focused dropdown input again closes it', html.includes('e.target === inp && document.activeElement === inp) { e.preventDefault(); closeDD(); }'));
    check('layout: dynamax HP value is tinted like other boosted stats', html.includes("raw.hp * 2 : raw.hp, spec.dynamax ? 'green' : ''"));
    check('layout: tera chip frame stays visible in light mode', html.includes(':root[data-theme="light"] .typechip.tera{box-shadow:0 0 0 2px rgba(0,0,0,.75) inset'));
    check('debug: send button is removed but the snapshot mechanism remains', !html.includes('id="dbgSend"') && html.includes('function debugSnapshot()') && html.includes('async function sendDebugSnapshot()') && html.includes("fetch('./debug_report'") && html.includes("addEventListener('click', sendDebugSnapshot)"));
    check('debug: off-Mac path shares/downloads the snapshot file for chat attachment', html.includes('navigator.canShare') && html.includes('このチャットに添付してください') && html.includes('debug_ui_'));
    check('layout: closing a dropdown restores the value label (no gray placeholder left)', html.includes("host.querySelector('.sdd-input') && DDREG[id]") && html.includes('old.replaceWith(ctl)'));
    const slotM = T.state.sel.mine;
    const savedM = T.state.mine[slotM];
    const pk = T.oppSpec('Pikachu', 'usage'); pk.moves = ['Thunderbolt', '', '', '']; pk.item = '';
    T.state.mine[slotM] = pk;
    const mb = T.movesBox('mine', null);
    check('layout: Z button renders right of the move dropdown (outside its control)', mb.includes('mvcell') && mb.includes('data-zmove="mine:0"') && mb.indexOf('data-zmove="mine:0"') > mb.indexOf('data-sdd="move:mine:0"'));
    T.state.mine[slotM] = savedM;
    T.calcAll();
  }

  {
    // メガシンカ中は特性プルダウンにメガ後の特性のみが出る (メガ前が混ざらない)
    const slot = T.state.sel.mine;
    const saved = T.state.mine[slot];
    const g = T.oppSpec('Gardevoir', 'usage'); // ability Synchronize / megaAbility Pixilate
    T.state.mine[slot] = g;
    g.mega = true;
    T.calcAll();
    const abMega = (T.DDREG['ability:mine']?.options || []).map(o => o.v);
        check('ability: mega panel lists only the mega ability', abMega.length === 1 && abMega[0] === 'Pixilate');
    g.mega = false;
    T.calcAll();
    const abBase = (T.DDREG['ability:mine']?.options || []).map(o => o.v);
    check('ability: non-mega panel lists the base abilities', abBase.includes('Synchronize') && abBase.includes('Trace'));
    T.state.mine[slot] = saved;
    T.calcAll();
  }

  {
    // 使用率トップ型は率1位の性格・型をそのまま使う (ブリジュラスの事例)。
    // 期待値は固定値にせず pokedb の生分布から導く
    const arch = T.oppSpec('Archaludon', 'usage');
    const archNats = rateDist('Archaludon', 'natures');
    check('usage-top: Archaludon top set uses the most-used nature in the data', arch.nature === archNats[0]?.en && arch.usageRates && arch.usageRates.nature === archNats[0]?.rate);
    const archPats = T.pokedbParsedFor('Archaludon')?.patterns || [];
    const famSum = {};
    for (const p of archPats) { const f = (p.label || '').split(' +')[0]; famSum[f] = (famSum[f] || 0) + (p.rate || 0); }
    const topFam = Object.entries(famSum).sort((a, b) => b[1] - a[1])[0]?.[0];
    const topPat = archPats.filter(p => (p.label || '').split(' +')[0] === topFam).sort((a, b) => (b.rate || 0) - (a.rate || 0))[0];
    check('usage-top: Archaludon pattern is the dominant family top in the data', !!topPat && arch.usageRates && arch.usageRates.patternLabel === topPat.label && ['hp', 'atk', 'def', 'spa', 'spd', 'spe'].every(k => (arch.sp[k] || 0) === ((topPat.sp || {})[k] || 0)));
    const corv = T.oppSpec('Corviknight', 'usage');
    check('usage-top: Corviknight top set uses the most-used nature in the data', corv.nature === rateDist('Corviknight', 'natures')[0]?.en);
  }

  {
    // 天候/フィールド特性の自動反映・天候ステータス補正の実数値表示・クリアボタン
    const wIdx = html.indexOf("regDD('weather'"), tIdx = html.indexOf("regDD('terrain'");
    check('field-setter: weather and terrain dropdowns are clearable', wIdx >= 0 && tIdx > wIdx && html.slice(wIdx, tIdx).includes('clearable: true') && html.slice(tIdx, tIdx + 700).includes('clearable: true'));
    T.state.field.weather = ''; T.state.field.terrain = '';
    T.applySetterAbility({ ability: 'Snow Warning' });
    check('field-setter: Snow Warning overwrites the weather on selection', T.state.field.weather === 'Snow');
    T.applySetterAbility({ ability: 'Psychic Surge' });
    check('field-setter: Psychic Surge overwrites the terrain on selection', T.state.field.terrain === 'Psychic');
    T.applySetterAbility({ ability: 'Levitate' });
    check('field-setter: a non-setter ability leaves the field untouched', T.state.field.weather === 'Snow' && T.state.field.terrain === 'Psychic');
    T.applySetterAbility({ species: 'Charizard', ability: 'Blaze', mega: true, megaSpecies: 'Charizard-Mega-Y', megaAbility: 'Drought' });
    check('field-setter: the mega ability is used while mega evolved', T.state.field.weather === 'Sun');
    const rawStats = { hp: 165, atk: 100, def: 100, spa: 100, spd: 100, spe: 100 };
    const aboma = { species: 'Abomasnow-Mega', mega: true, megaSpecies: 'Abomasnow-Mega', ability: 'Snow Warning', boosts: {}, item: '', status: '' };
    T.state.field.weather = 'Snow';
    check('field-stat: Snow boosts an Ice type Defense display by 1.5x', T.dispStat(aboma, 'def', rawStats, 'mine')[0] === 150 && T.dispStat(aboma, 'def', rawStats, 'mine')[1] === 'green');
    check('field-stat: Snow does not boost Sp. Def', T.dispStat(aboma, 'spd', rawStats, 'mine')[0] === 100);
    T.state.field.weather = '';
    check('field-stat: no weather, no boost', T.dispStat(aboma, 'def', rawStats, 'mine')[0] === 100);
    const tyranitar = { species: 'Tyranitar', ability: 'Sand Stream', boosts: {}, item: '', status: '' };
    T.state.field.weather = 'Sand';
    check('field-stat: Sand boosts a Rock type Sp. Def display by 1.5x', T.dispStat(tyranitar, 'spd', rawStats, 'mine')[0] === 150);
    const speOf = (spec, weather, terrain) => { T.state.field.weather = weather; T.state.field.terrain = terrain || ''; return T.dispStat(spec, 'spe', rawStats, 'mine')[0]; };
    const baseSpe = { boosts: {}, item: '', status: '' };
    check('field-stat: Chlorophyll doubles Speed in sun', speOf({ ...baseSpe, species: 'Venusaur', ability: 'Chlorophyll' }, 'Sun') === 200 && speOf({ ...baseSpe, species: 'Venusaur', ability: 'Chlorophyll' }, 'Rain') === 100);
    check('field-stat: Swift Swim doubles Speed in rain', speOf({ ...baseSpe, species: 'Kingdra', ability: 'Swift Swim' }, 'Heavy Rain') === 200);
    check('field-stat: Sand Rush doubles Speed in sand', speOf({ ...baseSpe, species: 'Excadrill', ability: 'Sand Rush' }, 'Sand') === 200);
    check('field-stat: Slush Rush doubles Speed in snow', speOf({ ...baseSpe, species: 'Sandslash-Alola', ability: 'Slush Rush' }, 'Snow') === 200);
    check('field-stat: Surge Surfer doubles Speed in Electric terrain', speOf({ ...baseSpe, species: 'Raichu-Alola', ability: 'Surge Surfer' }, '', 'Electric') === 200 && speOf({ ...baseSpe, species: 'Raichu-Alola', ability: 'Surge Surfer' }, '', 'Grassy') === 100);
    check('field-stat: Quick Feet boosts Speed 1.5x when statused and ignores paralysis drop', speOf({ ...baseSpe, species: 'Ursaring', ability: 'Quick Feet', status: 'par' }, '') === 150 && speOf({ ...baseSpe, species: 'Ursaring', ability: 'Quick Feet', status: '' }, '') === 100);
    T.state.field.weather = ''; T.state.field.terrain = '';
    T.state.field.weather = ''; T.state.field.terrain = '';
  }

  {
    // レイアウト切り替え: 上部のボタン3つと、選択の localStorage 保存
    check('layout: switcher buttons present (sp/tablet/pc)', ['sp', 'tablet', 'pc'].every(l => html.includes(`data-layoutpick="${l}"`)));
    check('layout: choice persisted via localStorage', html.includes("localStorage.setItem('champions-calc-layout'") && html.includes("localStorage.getItem('champions-calc-layout')"));
    check('layout: pc layout reverted to pre-device-pages rendering (no zoom, viewport removed)', !html.includes('--pcscale') && !html.includes('zoom:var(') && html.includes("if(l==='pc'){var vp=document.querySelector('meta[name=\"viewport\"]');if(vp)vp.remove();}"));
    check('layout: pc layout renders at 0.9 scale (100% = former 90% look)', html.includes('html[data-layout="pc"] body{zoom:.9}'));
    check('layout: preset box wraps by fit, not by a fixed breakpoint', html.includes('.pokeinfo{display:flex; flex-wrap:wrap') && html.includes('.infomain{flex:999 1 26rem') && html.includes('.presetbox{flex:1 1 21rem') && !html.includes('.presetbox{width:100%'));
    // 日本語名サプリメント: Zワザ等が英名のみにならないこと
    // (Zワザ自体は仕組み側の技として技プルダウンから外れたため、名前データで確認する)
    const zm = Object.fromEntries(T.MOVE_OPTIONS.map(o => [o.v, o.l]));
    const njm = JSON.parse(fs.readFileSync(ROOT + '/data/names_ja.json', 'utf8'));
    check('names: Z-moves have JA names in data', njm.moves.aciddownpour === 'アシッドポイズンデリート' && njm.moves.bloomdoom === 'ブルームシャインエクストラ' && njm.moves.nihillight === 'むにきすひかり');
    check('names: Nihil Light stays selectable with JA label', zm['Nihil Light'] === 'むにきすひかり (Nihil Light)');
    const nj = JSON.parse(fs.readFileSync(ROOT + '/data/names_ja.json', 'utf8'));
    check('names: new Mega abilities have JA names', nj.abilities.eelevate === 'うなぎのぼり' && nj.abilities.auraguard === 'はどうのぼうご' && nj.abilities.firemane === 'ほのおのたてがみ' && nj.abilities.spicyspray === 'とびだすハバネロ');
    // --- 推定値の計算用 SP はレンジ内最大の候補を使う (ベイズ経路) ---
    T.resetInference();
    T.applyState({ battle: '20261122_060500', oppReset: true, oppTeam: ['Tyranitar'], opps: [{ species: 'Tyranitar', revealed: { moves: ['Rock Slide'] } }], events: [], field: {} });
    const tSpec = T.state.opps.find(s => s && s.species === 'Tyranitar');
    const tView = tSpec ? T.estimator.view(tSpec) : null;
    let maxRuleOk = !!(tView && tView.bayes && tSpec);
    if (maxRuleOk) {
      const cov = T.estimator.cover('Tyranitar');
      for (const k of Object.keys(tView.sp)) {
        const valOf = c => (tSpec.mega && c.valuesMega) ? c.valuesMega[k] : (c.values ? c.values[k] : null);
        const withVal = ((cov && cov.cover) || []).filter(c => valOf(c) != null);
        const sameNature = withVal.filter(c => c.nature === tSpec.nature);
        const pool = sameNature.length ? sameNature : withVal;
        let best = null;
        for (const c of pool) if (!best || valOf(c) > valOf(best)) best = c;
        const expected = best ? (best.sp[k] || 0) : tView.sp[k][1];
        if (tSpec.sp[k] !== expected) { maxRuleOk = false; break; }
      }
    }
    check('estmax: bayes path panel SP follows the max-value candidate per stat', maxRuleOk);
    // --- 推論ログのターン刻印: 判明情報の反映はイベント処理の後 (刻印が遅れない) ---
    T.resetInference();
    T.applyState({ battle: '20261122_061200', oppReset: true, oppTeam: ['Tyranitar'], opps: [{ species: 'Tyranitar', revealed: { moves: ['Rock Slide'] } }], events: [{ k: 'mv', label: 'p2a: Tyranitar', move: 'Rock Slide', turn: 3 }], field: {} });
    T.applyState({ battle: '20261122_061200', oppTeam: ['Tyranitar'], opps: [{ species: 'Tyranitar', revealed: { moves: ['Rock Slide', 'Knock Off'] } }], events: [{ k: 'mv', label: 'p2a: Tyranitar', move: 'Rock Slide', turn: 3 }, { k: 'mv', label: 'p2a: Tyranitar', move: 'Knock Off', turn: 4 }], field: {} });
    const koSeen = T.inferLog.filter(r => r.trigger && r.trigger.kind === 'moveSeen' && (r.trigger.added || []).includes('Knock Off'));
    check('turnstamp: moveSeen revealed in the same write as its turn event is stamped with that turn', koSeen.length > 0 && koSeen.every(r => r.turn === 4));
    // --- 対戦中の版数リロード遅延 ---
    globalThis.__reloaded = false;
    T.resetVersionState();
    check('reload-defer: first seen version does not reload', T.noteVersionChange('v1') === 'none' && !globalThis.__reloaded);
    T.applyState({ battle: '20261122_062500', oppReset: true, oppTeam: ['Tyranitar'], opps: [{ species: 'Tyranitar' }], events: [], field: {} });
    check('reload-defer: a version change during a battle is deferred', T.noteVersionChange('v2') === 'deferred' && T.pendingReload === true && !globalThis.__reloaded);
    T.applyState({ battle: '20261122_063000', oppReset: true, oppTeam: ['Garchomp'], opps: [{ species: 'Garchomp' }], events: [], field: {} });
    check('reload-defer: the deferred reload fires when the next battle starts', globalThis.__reloaded === true);
    T.resetVersionState();

    // --- 同一種族が複数の場合の判明情報の統合 (推定の振動防止) ---
    T.resetInference();
    T.applyState({ battle: '20261122_073500', oppReset: true, oppTeam: ['Milotic', 'Milotic'], opps: [{ species: 'Milotic', revealed: { moves: ['Scald'], item: 'Leftovers' } }, { species: 'Milotic' }], events: [], field: {} });
    const milSeen = T.inferLog.filter(r => r.species === 'Milotic' && r.trigger && r.trigger.kind === 'moveSeen');
    const milRev = T.inferLog.filter(r => r.species === 'Milotic' && r.trigger && r.trigger.kind === 'revealed');
    check('dup-species: revealed info for a duplicated species is merged into one entry', milSeen.length === 1 && (milSeen[0].trigger.added || []).includes('Scald') && milRev.length === 1 && milRev[0].trigger.item === 'Leftovers');
    // --- ダメ計ログの out (計算出力) が記録されること ---
    T.state.field.weather = 'Rain'; T.calcAll(); T.resetInference();
    const lastRec = T.calcLog[T.calcLog.length - 1];
    check('calclog: records carry computed outputs, not just panel inputs', !!lastRec && lastRec.out.mine.length > 0 && lastRec.out.opps.length > 0 && (lastRec.out.mine.some(x => typeof x.maxPct === 'number') || lastRec.out.opps.some(x => typeof x.maxPct === 'number')));
    // --- 特性による天候上書きは実盤面に対して保持されないこと ---
    T.applyState({ battle: '20261122_074000', oppReset: true, oppTeam: ['Garchomp'], opps: [{ species: 'Garchomp' }], events: [], field: { weather: 'Snow', terrain: '' } });
    T.applySetterAbility({ species: 'Torkoal', ability: 'Drought' });
    const setterApplied = T.state.field.weather === 'Sun';
    T.applyState({ battle: '20261122_074000', oppTeam: ['Garchomp'], opps: [{ species: 'Garchomp' }], events: [], field: { weather: 'Snow', terrain: '' } });
    check('setter: setter-ability weather is not held against the real board value', setterApplied && T.state.field.weather === 'Snow');



    // --- 重要データ取得のフォールバック (配信元が失敗したら公開ページから) ---
    {
      const origFetch2 = globalThis.fetch;
      globalThis.fetch = async (u) => {
        const s = String(u);
        if (s.startsWith('https://nmfm1ow5ot.github.io/champions-calc/')) return origFetch2('./' + s.slice('https://nmfm1ow5ot.github.io/champions-calc/'.length));
        if (s.includes('data/vgc_pastes.json')) return { ok: false, status: 404, json: async () => { throw new Error('not json'); } };
        return origFetch2(u);
      };
      const fb = await T.fetchCriticalJson('data/vgc_pastes.json');
      check('dataload: corpus falls back to the public page when the local copy fails', fb.source === 'pages' && Array.isArray(fb.json.sets));
      globalThis.fetch = async (u) => { if (String(u).includes('vgc_pastes')) return { ok: false, status: 404, json: async () => ({}) }; return origFetch2(u); };
      let fbErr = '';
      try { await T.fetchCriticalJson('data/vgc_pastes.json'); } catch (e) { fbErr = String((e && e.message) || e); }
      check('dataload: total failure reports the HTTP status from both routes', fbErr.includes('HTTP 404') && fbErr.includes('pages:'));
      globalThis.fetch = origFetch2;
      check('dataload: the warning line carries the failure reason', html.includes('st.lastError'));
    }
    // --- 取り込み: 性別表記つき種族名 (イダイトウ等) が落ちないこと ---
    {
      const teamText = [
        'Dragonite @ Dragoninite\nAbility: Inner Focus\nLevel: 50\nEVs: 18 HP / 25 SpA / 2 SpD / 21 Spe\nModest Nature\n- Dragon Pulse\n- Heat Wave\n- Thunderbolt\n- Tailwind',
        'Garchomp @ Choice Scarf\nAbility: Rough Skin\nLevel: 50\nEVs: 32 Atk / 2 SpD / 32 Spe\nAdamant Nature\n- Earthquake\n- Rock Slide\n- Stomping Tantrum\n- Dragon Claw',
        'Basculegion (M) @ Life Orb\nAbility: Adaptability\nLevel: 50\nEVs: 26 Atk / 14 Def / 26 Spe\nJolly Nature\n- Wave Crash\n- Last Respects\n- Aqua Jet\n- Protect',
        'Sneasler @ Focus Sash\nAbility: Poison Touch\nLevel: 50\nEVs: 2 HP / 32 Atk / 32 Spe\nJolly Nature\n- Dire Claw\n- Close Combat\n- Fake Out\n- Feint',
        'Kingambit @ Chople Berry\nAbility: Defiant\nLevel: 50\nEVs: 32 HP / 15 Atk / 14 Def / 5 Spe\nAdamant Nature\n- Kowtow Cleave\n- Iron Head\n- Sucker Punch\n- Low Kick',
        'Delphox @ Delphoxite\nAbility: Blaze\nLevel: 50\nEVs: 1 HP / 2 Def / 31 SpA / 32 Spe\nTimid Nature\n- Heat Wave\n- Psychic\n- Encore\n- Protect',
      ].join('\n\n');
      const pt = T.parseTeam(teamText);
      const basc = pt.find(s => s.species && s.species.startsWith('Basculegion'));
      check('import: a full 6-set paste loads all six, including a gender-marked species', pt.length === 6 && !!basc && basc.species === 'Basculegion' && basc.item === 'Life Orb' && basc.moves.includes('Wave Crash'));
      const ptF = T.parseTeam('Indeedee (F) @ Psychic Seed\nAbility: Psychic Surge\n- Psychic\n');
      check('import: (F) resolves to the female forme when one exists', ptF.length === 1 && ptF[0].species === 'Indeedee-F');
      // Showdown 本家の読み込み (Teams.import) と同じ挙動の確認
      const headed = T.parseTeam('=== [gen9] Folder / My Team ===\nPikachu @ Light Ball\nAbility: Static\n- Thunderbolt\n\n---\nEevee @ Leftovers\nTrait: Run Away\n- Quick Attack\n');
      check('import: team header lines and --- separators follow Showdown import', headed.length === 2 && headed[0].species === 'Pikachu' && headed[0].item === 'Light Ball' && headed[1].species === 'Eevee' && headed[1].ability === 'Run Away');
      const nick = T.parseTeam('Bubbles (Basculegion) (M) @ Life Orb\nAbility: Adaptability\n- Wave Crash\n');
      check('import: nickname form resolves the parenthesized species', nick.length === 1 && nick[0].species === 'Basculegion' && nick[0].item === 'Life Orb');
      const aux = T.parseTeam('Charizard @ Charcoal\nAbility: Blaze\nLevel: 50\nShiny: Yes\nHappiness: 255\nPokeball: Poke Ball\nDynamax Level: 10\nGigantamax: Yes\nTera Type: Fire\nEVs: 4 HP / 252 SpA / 252 Spe\nmodest nature\n- Flamethrower\n~ Hidden Power [Ice]\n');
      check('import: auxiliary lines are tolerated, gigantamax maps to dynamax, tera and lowercase nature parse', aux.length === 1 && aux[0].species === 'Charizard' && aux[0].dynamax === true && aux[0].teraType === 'Fire' && aux[0].nature === 'Modest' && aux[0].moves.includes('Hidden Power Ice'));
      const noItem = T.parseTeam('Pikachu @ No Item\nAbility: Static\n- Thunderbolt\n');
      check('import: No Item means no item', noItem.length === 1 && !noItem[0].item);
      const jsonTeam = T.parseTeam(JSON.stringify([{ species: 'Basculegion', gender: 'M', item: 'Life Orb', ability: 'Adaptability', nature: 'Jolly', evs: { atk: 26, def: 14, spe: 26 }, moves: ['Wave Crash', 'Aqua Jet'] }]));
      check('import: JSON format teams load', jsonTeam.length === 1 && jsonTeam[0].species === 'Basculegion' && jsonTeam[0].item === 'Life Orb' && jsonTeam[0].sp.atk === 26 && jsonTeam[0].sp.spe === 26 && jsonTeam[0].moves.includes('Wave Crash'));
      const packed = T.parseTeam('|Basculegion|LifeOrb|Adaptability|WaveCrash,LastRespects,AquaJet,Protect|Jolly|,26,14,,,26|M||||');
      check('import: packed format teams load', packed.length === 1 && packed[0].species === 'Basculegion' && packed[0].item === 'Life Orb' && packed[0].nature === 'Jolly' && packed[0].sp.atk === 26 && packed[0].sp.def === 14 && packed[0].moves.includes('Last Respects'));
      // --- export は Showdown の exportSet 形式 (行順は Ability →
      // Level → Tera → EVs → Nature、SPs: 行は出さない)。努力値は
      // M-C の作法で EVs: 行に SP の値をそのまま書く
      const expSpec = { species: 'Blastoise', ability: 'Rain Dish', item: 'Blastoisinite', mega: false, nature: 'Modest', sp: { hp: 2, atk: 0, def: 0, spa: 32, spd: 0, spe: 32 }, moves: ['Water Spout', 'Aura Sphere'], teraType: 'Water' };
      const expText = T.exportText(expSpec);
      check('export: EVs line carries SP values as-is (M-C convention) and no SPs line', expText.includes('EVs: 2 HP / 32 SpA / 32 Spe') && !expText.includes('SPs:'));
      check('export: line order follows exportSet', expText.indexOf('Ability:') < expText.indexOf('Level: 50') && expText.indexOf('Level: 50') < expText.indexOf('EVs:') && expText.indexOf('EVs:') < expText.indexOf('Modest Nature') && expText.split('\n')[0] === 'Blastoise @ Blastoisinite');
      check('export: no Tera Type line under the M-C regulation', !expText.includes('Tera Type:'));
      const rt = T.parseTeam(expText);
      check('export: exported paste re-imports with the same SP', rt.length === 1 && rt[0].sp.hp === 2 && rt[0].sp.spa === 32 && rt[0].sp.spe === 32 && rt[0].nature === 'Modest');
      const expM = T.exportText({ species: 'Basculegion', ability: 'Adaptability', item: '', mega: false, nature: 'Jolly', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, moves: ['Wave Crash'], teraType: '' });
      const expF = T.exportText({ species: 'Basculegion-F', ability: 'Adaptability', item: '', mega: false, nature: 'Jolly', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, moves: ['Wave Crash'], teraType: '' });
      check('export: gender suffixes follow exportSet', expM.split('\n')[0] === 'Basculegion (M)' && expF.split('\n')[0] === 'Basculegion-F (F)' && T.parseTeam(expM)[0].species === 'Basculegion' && T.parseTeam(expF)[0].species === 'Basculegion-F');
    }

    // --- 重要データ取得のフォールバック (配信元が失敗したら公開ページから) ---
    {
      const origFetch2 = globalThis.fetch;
      globalThis.fetch = async (u) => {
        const s = String(u);
        if (s.startsWith('https://nmfm1ow5ot.github.io/champions-calc/')) return origFetch2('./' + s.slice('https://nmfm1ow5ot.github.io/champions-calc/'.length));
        if (s.includes('data/vgc_pastes.json')) return { ok: false, status: 404, json: async () => { throw new Error('not json'); } };
        return origFetch2(u);
      };
      const fb = await T.fetchCriticalJson('data/vgc_pastes.json');
      check('dataload: corpus falls back to the public page when the local copy fails', fb.source === 'pages' && Array.isArray(fb.json.sets));
      globalThis.fetch = async (u) => { if (String(u).includes('vgc_pastes')) return { ok: false, status: 404, json: async () => ({}) }; return origFetch2(u); };
      let fbErr = '';
      try { await T.fetchCriticalJson('data/vgc_pastes.json'); } catch (e) { fbErr = String((e && e.message) || e); }
      check('dataload: total failure reports the HTTP status from both routes', fbErr.includes('HTTP 404') && fbErr.includes('pages:'));
      globalThis.fetch = origFetch2;
      check('dataload: the warning line carries the failure reason', html.includes('st.lastError'));
    }
    // --- 取り込み: 性別表記つき種族名 (イダイトウ等) が落ちないこと ---
    {
      const teamText = [
        'Dragonite @ Dragoninite\nAbility: Inner Focus\nLevel: 50\nEVs: 18 HP / 25 SpA / 2 SpD / 21 Spe\nModest Nature\n- Dragon Pulse\n- Heat Wave\n- Thunderbolt\n- Tailwind',
        'Garchomp @ Choice Scarf\nAbility: Rough Skin\nLevel: 50\nEVs: 32 Atk / 2 SpD / 32 Spe\nAdamant Nature\n- Earthquake\n- Rock Slide\n- Stomping Tantrum\n- Dragon Claw',
        'Basculegion (M) @ Life Orb\nAbility: Adaptability\nLevel: 50\nEVs: 26 Atk / 14 Def / 26 Spe\nJolly Nature\n- Wave Crash\n- Last Respects\n- Aqua Jet\n- Protect',
        'Sneasler @ Focus Sash\nAbility: Poison Touch\nLevel: 50\nEVs: 2 HP / 32 Atk / 32 Spe\nJolly Nature\n- Dire Claw\n- Close Combat\n- Fake Out\n- Feint',
        'Kingambit @ Chople Berry\nAbility: Defiant\nLevel: 50\nEVs: 32 HP / 15 Atk / 14 Def / 5 Spe\nAdamant Nature\n- Kowtow Cleave\n- Iron Head\n- Sucker Punch\n- Low Kick',
        'Delphox @ Delphoxite\nAbility: Blaze\nLevel: 50\nEVs: 1 HP / 2 Def / 31 SpA / 32 Spe\nTimid Nature\n- Heat Wave\n- Psychic\n- Encore\n- Protect',
      ].join('\n\n');
      const pt = T.parseTeam(teamText);
      const basc = pt.find(s => s.species && s.species.startsWith('Basculegion'));
      check('import: a full 6-set paste loads all six, including a gender-marked species', pt.length === 6 && !!basc && basc.species === 'Basculegion' && basc.item === 'Life Orb' && basc.moves.includes('Wave Crash'));
      const ptF = T.parseTeam('Indeedee (F) @ Psychic Seed\nAbility: Psychic Surge\n- Psychic\n');
      check('import: (F) resolves to the female forme when one exists', ptF.length === 1 && ptF[0].species === 'Indeedee-F');
      // Showdown 本家の読み込み (Teams.import) と同じ挙動の確認
      const headed = T.parseTeam('=== [gen9] Folder / My Team ===\nPikachu @ Light Ball\nAbility: Static\n- Thunderbolt\n\n---\nEevee @ Leftovers\nTrait: Run Away\n- Quick Attack\n');
      check('import: team header lines and --- separators follow Showdown import', headed.length === 2 && headed[0].species === 'Pikachu' && headed[0].item === 'Light Ball' && headed[1].species === 'Eevee' && headed[1].ability === 'Run Away');
      const nick = T.parseTeam('Bubbles (Basculegion) (M) @ Life Orb\nAbility: Adaptability\n- Wave Crash\n');
      check('import: nickname form resolves the parenthesized species', nick.length === 1 && nick[0].species === 'Basculegion' && nick[0].item === 'Life Orb');
      const aux = T.parseTeam('Charizard @ Charcoal\nAbility: Blaze\nLevel: 50\nShiny: Yes\nHappiness: 255\nPokeball: Poke Ball\nDynamax Level: 10\nGigantamax: Yes\nTera Type: Fire\nEVs: 4 HP / 252 SpA / 252 Spe\nmodest nature\n- Flamethrower\n~ Hidden Power [Ice]\n');
      check('import: auxiliary lines are tolerated, gigantamax maps to dynamax, tera and lowercase nature parse', aux.length === 1 && aux[0].species === 'Charizard' && aux[0].dynamax === true && aux[0].teraType === 'Fire' && aux[0].nature === 'Modest' && aux[0].moves.includes('Hidden Power Ice'));
      const noItem = T.parseTeam('Pikachu @ No Item\nAbility: Static\n- Thunderbolt\n');
      check('import: No Item means no item', noItem.length === 1 && !noItem[0].item);
      const jsonTeam = T.parseTeam(JSON.stringify([{ species: 'Basculegion', gender: 'M', item: 'Life Orb', ability: 'Adaptability', nature: 'Jolly', evs: { atk: 26, def: 14, spe: 26 }, moves: ['Wave Crash', 'Aqua Jet'] }]));
      check('import: JSON format teams load', jsonTeam.length === 1 && jsonTeam[0].species === 'Basculegion' && jsonTeam[0].item === 'Life Orb' && jsonTeam[0].sp.atk === 26 && jsonTeam[0].sp.spe === 26 && jsonTeam[0].moves.includes('Wave Crash'));
      const packed = T.parseTeam('|Basculegion|LifeOrb|Adaptability|WaveCrash,LastRespects,AquaJet,Protect|Jolly|,26,14,,,26|M||||');
      check('import: packed format teams load', packed.length === 1 && packed[0].species === 'Basculegion' && packed[0].item === 'Life Orb' && packed[0].nature === 'Jolly' && packed[0].sp.atk === 26 && packed[0].sp.def === 14 && packed[0].moves.includes('Last Respects'));
    }






    // --- 自チーム暫定リスト (mineTeam): 種族構成が矛盾すれば上書きし、
    // 判明項目は同構成のまま後続の更新でも取り込む。
    // 2026-11-23 から一時無効化中 (スイッチ MINE_TEAM_PREVIEW_APPLY)。
    // 無効化中は「上書きされないこと」を固定し、有効時は従来の検証を行う ---
    {
      const beforeSpecies = T.state.mine.map(s => s.species);
      check('mineteam: baseline panels hold six members', beforeSpecies.length === 6 && beforeSpecies.includes('Gardevoir'));
      if (!T.MINE_TEAM_PREVIEW_APPLY) {
        T.applyState({ mineTeam: ['Gengar', 'Politoed', 'Archaludon'] });
        check('mineteam: while disabled, a contradicting list does not overwrite the panels', JSON.stringify(T.state.mine.map(s => s.species)) === JSON.stringify(beforeSpecies));
        check('mineteam: while disabled, direct application is a no-op', T.applyMineTeamPreview(['Gengar']) === false && T.state.mine[0].species === beforeSpecies[0]);
      } else {
        const hpBefore = T.state.mine[1].curHPPercent;
        T.applyState({ mineTeam: ['Gengar', 'Politoed', 'Archaludon'] });
        check('mineteam: identified species lead the panels and unidentified slots keep their panels', T.state.mine.length === 6 && JSON.stringify(T.state.mine.slice(0, 3).map(s => s.species)) === JSON.stringify(['Gengar', 'Politoed', 'Archaludon']) && !!T.state.mine[0].ability);
        T.applyState({ mineTeam: [{ species: 'Gengar', item: 'Focus Sash' }, 'Politoed', 'Archaludon'] });
        check('mineteam: later info updates land on the same composition', T.state.mine[0].item === 'Focus Sash');
        const keepRef = T.state.mine[0];
        T.applyState({ mineTeam: ['Gengar', 'Politoed', 'Archaludon', 'Incineroar', 'Gardevoir', 'Armarouge'] });
        check('mineteam: a full six-species list replaces the panels exactly', JSON.stringify(T.state.mine.map(s => s.species)) === JSON.stringify(['Gengar', 'Politoed', 'Archaludon', 'Incineroar', 'Gardevoir', 'Armarouge']) && T.state.mine[0] === keepRef && T.state.mine[0].item === 'Focus Sash');
        T.applyState({ mineTeam: beforeSpecies });
        check('mineteam: restoring the registered composition reuses preset builds', T.state.mine.length === 6 && T.state.mine[1].species === 'Gardevoir' && T.state.mine[1].curHPPercent === hpBefore);
      }
    }
    // --- 閉じたプルダウンの表示にも使用率 % を併記する ---
    {
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
      T.calcAll();
      const ids = Object.keys(T.DDREG);
      const natId = ids.find(k => k.startsWith('nature:'));
      const abiId = ids.find(k => k.startsWith('ability:'));
      const natHtml = natId ? T.ddHTML(natId) : '';
      const abiHtml = abiId ? T.ddHTML(abiId) : '';
      check('ddclosed: nature control shows its usage rate', /class="ddrate">[0-9.]+%<\/span>/.test(natHtml));
      check('ddclosed: ability control shows its usage rate', /class="ddrate">[0-9.]+%<\/span>/.test(abiHtml));
    }
    // --- 持ち物の使用率 % (ZA メガストーンを含む) ---
    {
      T.applyState({ oppTeam: ['Absol'], opps: [], events: [], field: {} });
      T.calcAll();
      const absDist = rateDist('Absol', 'items');
      const itemHtml = T.ddHTML('item:opps');
      check('ddclosed: item control shows its usage rate', absDist[0] != null && itemHtml.includes(`class="ddrate">${absDist[0].rate}%</span>`));
      const sp = T.oppSpec('Absol', 'usage');
      const head = T.itemOptionsFor(sp).find(o => o.v === sp.item);
      const spRate = absDist.find(d => d.en === sp.item)?.rate;
      check('ddclosed: top item option carries its usage rate', !!head && spRate != null && head.rate === spRate);
      check('ddclosed: item map cache is invalidated when item maps load', html.includes('_itemJa2en = null;'));
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
    }
    // --- フォーカストグル (自動/手動、両サイド独立) ---
    {
      check('focus: toggle renders on both racks', T.playerBar('mine').includes('data-focuspick="mine:auto"') && T.playerBar('mine').includes('data-focuspick="mine:manual"') && T.playerBar('opps').includes('data-focuspick="opps:auto"') && T.playerBar('opps').includes('data-focuspick="opps:manual"'));
      const sp = i => T.state.mine[i].species;
      const entry = i => ({ species: sp(i), curHPPercent: 90 });
      T.state.sel.mine = 0; T.state.active.mine = [];
      T.applyState({ mine: [entry(2), entry(3)] });
      check('focus: manual mode keeps the focus on board reads', T.state.sel.mine === 0 && JSON.stringify(T.state.active.mine) === JSON.stringify([2, 3]));
      T.setFocusMode('mine', 'auto');
      T.applyState({ mine: [entry(3), entry(4)] });
      check('focus: auto mode follows the newly entered one', T.state.sel.mine === 4);
      T.applyState({ mine: [entry(0), entry(1)] });
      check('focus: auto mode takes the leftmost when both switch', T.state.sel.mine === 0);
      T.setFocusMode('mine', 'manual');
      T.applyState({ mine: [entry(5), entry(1)] });
      check('focus: back in manual the focus stays put', T.state.sel.mine === 0);
      // 相手側: 自分側が手動でも、相手側は独立に自動で追随する
      T.applyState({ oppTeam: ['Garchomp', 'Dragonite', 'Incineroar'], opps: [], events: [], field: {} });
      const osp = i => T.state.opps[i] && T.state.opps[i].species;
      check('focus: opponent team has three panels', !!osp(0) && !!osp(1) && !!osp(2));
      T.state.sel.opps = 0; T.state.active.opps = [];
      T.applyState({ opps: [{ species: osp(1), curHPPercent: 90 }, { species: osp(2), curHPPercent: 90 }] });
      check('focus: opponent manual keeps its focus too', T.state.sel.opps === 0 && JSON.stringify(T.state.active.opps) === JSON.stringify([1, 2]));
      T.setFocusMode('opps', 'auto');
      T.state.sel.opps = 1;
      T.applyState({ opps: [{ species: osp(2), curHPPercent: 90 }, { species: osp(0), curHPPercent: 90 }] });
      check('focus: opponent auto follows the entered one independently', T.state.sel.opps === 0 && T.state.active.opps.length === 2);
      T.setFocusMode('opps', 'manual');
      // 後続チェック (対戦切り替え) の前提に合わせ、相手チームを戻しておく
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
    }
    // --- 行動順の証拠はターン開始時点のランク補正で評価する
    // (battle_20261122_171847 seq34/35 の再現: グレンアルマはターン開始時
    // 素早さ 127 で相手候補の最大 189 と矛盾しないが、がんせきふうじを
    // 受けた後の補正 (+1 段階で 190) を使うと全候補が矛盾してしまう) ---
    {
      T.applyState({ battle: '20990101_000001', oppReset: true, oppTeam: ['Sneasler'], opps: [{ species: 'Sneasler', curHPPercent: 100 }], mine: [{ species: 'Armarouge', curHPPercent: 100 }], events: [], field: {} });
      T.applyState({ battle: '20990101_000001', oppTeam: ['Sneasler'], opps: [{ species: 'Sneasler', curHPPercent: 92 }], mine: [{ species: 'Armarouge', curHPPercent: 74, boosts: { spe: 1, def: -1 } }], events: [{ k: 'mv', turn: 1, label: 'p2a: Sneasler', move: 'Rock Tomb' }, { k: 'mv', turn: 1, label: 'p1a: Armarouge', move: 'Expanding Force' }], field: {} });
      const arm = T.state.mine.find(s => s.species === 'Armarouge');
      check('speboost: panel itself carries the post-hit boosts', !!arm && arm.boosts.spe === 1);
      const mo = T.inferLog.filter(r => r.battle === '20990101_000001' && r.trigger && r.trigger.kind === 'moveOrder');
      check('speboost: move order is judged with turn-start boosts', mo.length >= 1 && mo.every(r => r.trigger.applied === true && !r.trigger.inconsistent && !r.trigger.speFlag));
    }
    // --- 推定した相手の型をトレーナー名のカスタムとして一時保持する ---
    {
      T.applyState({ battle: '20990101_000001', oppTrainer: 'Ihd666', oppTeam: ['Sneasler'], opps: [{ species: 'Sneasler', revealed: { item: 'Focus Sash' } }], events: [], field: {} });
      const kept = T.tempTrainerSets['Sneasler'];
      check('tempset: estimated build is kept under the trainer name', !!kept && kept.trainer === 'Ihd666' && kept.build.item === 'Focus Sash');
      T.calcAll();
      const dd = T.DDREG['preset:opps'];
      const customOpt = dd && dd.options.find(o => o.v === 'custom');
      check('tempset: custom option carries the trainer name', !!customOpt && customOpt.l === 'Ihd666');
      T.state.opps[T.state.sel.opps] = T.oppSpec('Sneasler', 'usage');
      dd.onPick('custom');
      const restored = T.state.opps[T.state.sel.opps];
      check('tempset: picking custom reapplies the kept build', restored.kind === 'custom' && restored.item === 'Focus Sash');
      T.confirmNewBattle();
      check('tempset: kept builds are dropped when the next battle begins', Object.keys(T.tempTrainerSets).length === 0);
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
    }
    // --- 行動前に倒された個体への先行証拠 (spe イベント → faintOrder) ---
    {
      const saveOppTeam = T.state.oppTeam, saveOpps = T.state.opps;
      const gv = T.state.mine.find(s => s.species === 'Gardevoir');
      const saveMega = gv ? gv.mega : false;
      if (gv) gv.mega = true; // メガサーナイト (素早さ実数 167) が基準になる受け入れ場面
      T.applyState({ oppTeam: ['Archaludon'], opps: [], events: [], field: {} });
      T.drainInferenceLog();
      T.applyState({ oppTeam: ['Archaludon'], opps: [], events: [{ k: 'spe', turn: 1, fast: 'p2a: Archaludon', slow: 'p1a: Gardevoir', move: 'Steel Beam' }], field: {} });
      T.drainInferenceLog();
      const fo = (T.inferLog || []).find(r => r.trigger && r.trigger.kind === 'faintOrder' && r.species === 'Archaludon');
      check('faintorder: spe event produces a faintOrder record', !!fo);
      check('faintorder: non-scarf candidates are excluded and Choice Scarf is the map', !!fo && fo.map && fo.map.item === 'Choice Scarf');
      if (gv) gv.mega = saveMega;
      T.state.oppTeam = saveOppTeam; T.state.opps = saveOpps;
      T.applyState({ oppTeam: saveOppTeam, opps: [], events: [], field: {} });
    }
    // --- 一括再生時の自軍パネル補完 (battle_20261122_192108 の受け入れ場面) ---
    {
      const snapMine = T.state.mine, snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      T.loadMyTeam();
      for (let i = 0; i < 50 && !(T.state.mine[0] && T.state.mine[0].species === 'Blastoise'); i++) await new Promise(r => setTimeout(r, 10));
      check('replay: panels start as the registered team', T.state.mine.some(s => s.species === 'Gardevoir') && !T.state.mine.some(s => s.species === 'Charizard'));
      const bst = JSON.stringify({ battle: '20990202_000000',
        oppTeam: ['Vanilluxe', 'Blaziken', 'Farigiraf', 'Glimmora', 'Sandaconda', 'Weavile'], opps: [], minePreview: false,
        mine: [{ species: 'Charizard', curHPPercent: 88, boosts: { atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, status: '' },
               { species: 'Garchomp', curHPPercent: 100, boosts: { atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, status: '' }],
        events: [
          { k: 'mv', turn: 1, label: 'p1a: Garchomp', move: 'Earthquake' },
          { k: 'dmg', turn: 1, atk: 'p1a: Garchomp', def: 'p2a: Glimmora', move: 'Earthquake', amt: 160, pct: 100 },
          { k: 'spe', turn: 1, fast: 'p1a: Garchomp', slow: 'p2a: Glimmora', move: 'Earthquake' },
          { k: 'mv', turn: 1, label: 'p2a: Vanilluxe', move: 'Freeze-Dry' },
          { k: 'mv', turn: 1, label: 'p1b: Charizard', move: 'Heat Wave' }],
        field: { weather: '', terrain: '' } });
      T.resetInference();
      T.applyState(JSON.parse(bst));
      check('replay: Charizard and Garchomp are supplemented into the panels', T.state.mine.some(s => s.species === 'Charizard') && T.state.mine.some(s => s.species === 'Garchomp'));
      const log = T.inferLog;
      const vo = log.filter(r => r.species === 'Vanilluxe' && r.trigger && r.trigger.kind === 'moveOrder');
      check('replay: Vanilluxe moveOrder evidence is recorded', vo.length >= 1);
      check('replay: both moveOrder pairs are processed (Garchomp pair applied, Charizard pair recorded)', vo.length >= 2 && vo[0].trigger.applied === true);
      check('replay: Glimmora faintOrder context is built', log.some(r => r.species === 'Glimmora' && r.trigger && r.trigger.kind === 'faintOrder'));
      // 通常の適用 (同じ battle キー) では補完しない
      const bst2 = JSON.stringify({ battle: '20990202_000000', oppTeam: ['Vanilluxe', 'Blaziken', 'Farigiraf', 'Glimmora', 'Sandaconda', 'Weavile'], opps: [], mine: [{ species: 'Dragonite', curHPPercent: 100, boosts: { atk: 0, def: 0, spa: 0, spd: 0, spe: 0 }, status: '' }], events: [], field: { weather: '', terrain: '' } });
      T.applyState(JSON.parse(bst2));
      check('replay: no supplement on a non-replay application', !T.state.mine.some(s => s.species === 'Dragonite'));
      T.state.mine = snapMine; T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- crit イベント (急所の後付け確定) の振り分け ---
    {
      const snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      T.state.oppTeam = ['Garchomp'];
      T.state.opps = [T.oppSpec('Garchomp', 'usage')];
      T.resetInference();
      const evs = [
        { k: 'dmg', turn: 1, atk: 'p2a: Garchomp', def: 'p1a: Gardevoir', move: 'Rock Slide', crit: false, amt: 40, pct: 25 },
        { k: 'crit', turn: 1, atk: 'p2a: Garchomp', def: 'p1a: Gardevoir', move: 'Rock Slide' },
        { k: 'dmg', turn: 1, atk: 'p2a: Garchomp', def: 'p1a: Gardevoir', move: 'Rock Slide', crit: false, amt: 30, pct: 19 }];
      T.applyState({ battle: '20990303_000000', oppTeam: ['Garchomp'], opps: [], mine: [], events: evs, field: { weather: '', terrain: '' } });
      const dmgRecs = T.inferLog.filter(r => r.trigger && r.trigger.kind === 'damage' && r.species === 'Garchomp');
      check('crit: events after a crit event are still processed', dmgRecs.length >= 2);
      check('crit: routing branch exists', html.includes("ev.k === 'crit'") && html.includes('processCritInf') && html.includes('processCritBayes'));
      T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- ダメージ % ホバーで乱数 16 本を吹き出し表示 ---
    {
      const snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
      T.calcAll();
      const withRolls = T.lastCalc.results[0].moveResults.map(mr => mr.vs[0]).filter(v => v && Array.isArray(v.rolls) && v.rolls.length > 1);
      const box = T.movesBox('mine', T.lastCalc.results[0]);
      // 吹き出しはセルに1つで、上段が本体の乱数、下段 (rolltip-alt) が
      // 反対の急所状態の乱数
      const grabRolls = (s) => { const m = s.match(/\d+(?:, \d+){7,}/); return m ? m[0].split(', ').map(Number) : []; };
      const tipSegs = box.split('class="rolltip">').slice(1).map(s => {
        const altIdx = s.indexOf('rolltip-alt');
        const main = grabRolls(altIdx >= 0 ? s.slice(0, altIdx) : s);
        let alt = null;
        if (altIdx >= 0) { const br = s.slice(altIdx).indexOf('<br>'); if (br >= 0) alt = grabRolls(s.slice(altIdx + br)); }
        return { main, alt };
      });
      check('rolltip: every damaging move cell carries a roll balloon with 16 values', withRolls.length > 0 && tipSegs.length === withRolls.length && tipSegs.every(t => t.main.length === 16));
      check('rolltip: balloons span the displayed ranges', tipSegs.length === withRolls.length && tipSegs.every((t, i) => {
        const v = withRolls[i];
        if (!(t.main[0] === v.min && t.main[15] === v.max && t.main.every((x, j) => j === 0 || t.main[j - 1] <= x))) return false;
        const wantAlt = v.alt && (v.alt.min !== v.min || v.alt.max !== v.max) && Array.isArray(v.alt.rolls) && v.alt.rolls.length > 1;
        if (!wantAlt) return t.alt === null;
        return !!t.alt && t.alt.length === 16 && t.alt[0] === v.alt.min && t.alt[15] === v.alt.max;
      }));
      check('rolltip: fixed-damage and status cells carry no balloon', html.includes('r.rolls && r.rolls.length > 1'));
      T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- 急所ダメージの併記 (通常ダメージの下) ---
    {
      const snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      T.applyState({ oppTeam: ['Garchomp'], opps: [], events: [], field: {} });
      T.ui.crit.mine = false;
      T.calcAll();
      const withAlt = T.lastCalc.results[0].moveResults.map(mr => mr.vs[0]).filter(v => v && v.alt && (v.alt.min !== v.min || v.alt.max !== v.max));
      check('critdmg: opposite-crit range is computed alongside', withAlt.length > 0 && withAlt.every(v => v.alt.max >= v.max));
      const box = T.movesBox('mine', T.lastCalc.results[0]);
      check('critdmg: crit range sits inside the hover balloon, not as a cell line', box.includes('rolltip-alt') && box.includes('急所') && !box.includes('critsub'));
      const before = withAlt[0];
      T.ui.crit.mine = true;
      T.calcAll();
      const toggled = T.lastCalc.results[0].moveResults.map(mr => mr.vs[0]).find(v => v && v.alt && v.min === before.alt.min && v.max === before.alt.max);
      const box2 = T.movesBox('mine', T.lastCalc.results[0]);
      check('critdmg: with the crit toggle on, the main range is the crit range and the balloon shows the normal range', !!toggled && box2.includes('通常'));
      T.ui.crit.mine = false;
      T.calcAll();
      T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- 例外耐性: 途中のイベントで例外が起きても後続が継続し、記録が残る ---
    {
      const snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      const origDmgInf = T.estimator.processDamageInf;
      T.estimator.processDamageInf = (ev, io) => { if (ev && ev.move === 'Weather Ball') throw new Error('probe-boom'); return origDmgInf(ev, io); };
      const evs = [
        { k: 'mv', turn: 4, label: 'p2a: Farigiraf', move: 'Protect' },
        { k: 'mv', turn: 4, label: 'p1b: Torkoal', move: 'Weather Ball' },
        { k: 'dmg', turn: 4, atk: 'p1b: Torkoal', def: 'p2b: Staraptor', move: 'Weather Ball', amt: 153, pct: 100, crit: false },
        { k: 'spe', turn: 4, fast: 'p1b: Torkoal', slow: 'p2b: Staraptor', move: 'Weather Ball', fastB: {}, slowB: {}, fastMega: '', slowMega: 'Staraptor-Mega' },
        { k: 'crit', turn: 4, atk: 'p1b: Torkoal', def: 'p2b: Staraptor', move: 'Weather Ball' },
      ];
      let threw = null;
      const snapMine = T.state.mine;
      T.state.mine = ['Kingambit', 'Torkoal', 'Delphox'].map(sp => T.oppSpec(sp, 'usage'));
      try {
        T.applyState({ battle: '20990303_000000', oppTeam: ['Farigiraf', 'Torkoal', 'Staraptor'], events: [] });
        const si = T.state.oppTeam.indexOf('Staraptor');
        if (si >= 0) { T.state.opps[si].mega = true; T.state.opps[si].megaSpecies = 'Staraptor-Mega'; }
        T.applyState({ battle: '20990303_000000', oppTeam: ['Farigiraf', 'Torkoal', 'Staraptor'], events: evs });
      } catch (e) { threw = e; }
      T.state.mine = snapMine;
      T.estimator.processDamageInf = origDmgInf;
      const kinds = T.inferLog.map(r => (r.trigger || {}).kind);
      check('errguard: a throwing event intake does not escape applyState', !threw);
      check('errguard: the exception is recorded with its context', T.uiErrors.some(e => e.where === 'event' && e.message === 'probe-boom' && e.kind === 'dmg'));
      check('errguard: later events still process (faintOrder and critPatch recorded)', kinds.includes('faintOrder') && kinds.includes('critPatch'));
      check('errguard: the seen pointer advances past the bad event', T.estimator.getSeen() === evs.length);
      check('errguard: poll wraps applyState and records failures', html.includes("recordUiError({ where: 'applyState'"));
      T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- 判明持ち物が消費済みでも名前が推定へ届くこと ---
    {
      const snapOpps = T.state.opps, snapOppTeam = T.state.oppTeam;
      const snapSel = JSON.parse(JSON.stringify(T.state.sel)), snapActive = JSON.parse(JSON.stringify(T.state.active));
      const evsLO = [{ k: 'mv', turn: 1, label: 'p1a: Torkoal', move: 'Lava Plume' }, { k: 'mv', turn: 1, label: 'p2a: Milotic', move: 'Scald' }];
      const snapMineLO = T.state.mine;
      T.state.mine = [T.oppSpec('Torkoal', 'usage')];
      T.applyState({ battle: '20990404_000000', oppTeam: ['Milotic'], events: evsLO });
      T.applyState({ battle: '20990404_000000', oppTeam: ['Milotic'], opps: [{ species: 'Milotic', itemLost: true, revealed: { item: 'オボンのみ' } }], oppRevealed: { Milotic: { item: 'オボンのみ' } }, events: evsLO });
      T.state.mine = snapMineLO;
      const mi = T.state.oppTeam.indexOf('Milotic');
      const mspec = mi >= 0 ? T.state.opps[mi] : null;
      check('lostitem: panel keeps the revealed name and the lost flag', !!mspec && mspec.item === 'Sitrus Berry' && mspec.itemLost === true);
      const rev = T.inferLog.filter(r => r.species === 'Milotic' && (r.trigger || {}).kind === 'revealed');
      const lastRev = rev[rev.length - 1];
      check('lostitem: the revealed record carries the item name as a hard constraint', !!lastRev && lastRev.trigger.item === 'Sitrus Berry' && lastRev.trigger.hard === true);
      check('lostitem: calc snapshots keep the consumed item name as lostItem', html.includes('lostItem: spec.item'));
      T.state.opps = snapOpps; T.state.oppTeam = snapOppTeam; T.state.sel = snapSel; T.state.active = snapActive;
    }
    // --- 試合開始／終了ボタン (battlePhase が権威、押下は toggle のみ。
    // 開始か終了かは serve.py が権威ある phase で判断する) ---
    {
      check('flagbtn: button exists with the start label', html.includes('id="battleFlagBtn"') && html.includes('>試合開始</button>'));
      check('flagbtn: disabled before the first state application', T.flagSeen === false && T.flagBtnDisabled() === true && T.flagBtnLabel() === '試合開始');
      T.applyState({ battle: '20990505_000000', battlePhase: 'inBattle', flagMode: 'manual', events: [] });
      check('flagbtn: enabled once a valid battlePhase arrives, label follows it', T.flagSeen === true && T.flagBtnDisabled() === false && T.flagPhase === 'inBattle' && T.flagBtnLabel() === '試合終了');
      T.applyState({ battlePhase: 'idle', flagMode: 'manual' });
      check('flagbtn: label follows battlePhase back to idle', T.flagPhase === 'idle' && T.flagBtnLabel() === '試合開始');
      const origFetch = globalThis.fetch;
      const seenActions = [];
      let stubPhase = 'inBattle';
      let stubOk = true;
      globalThis.fetch = async (u, opts) => {
        if (String(u).split('?')[0].endsWith('battle_flag')) {
          const body = JSON.parse(opts.body);
          seenActions.push(body.action);
          if (!stubOk) return { ok: false, status: 409, text: async () => '', json: async () => ({}) };
          return { ok: true, status: 200, text: async () => '', json: async () => ({ ok: true, phase: stubPhase, mode: 'manual', startSeq: 1, endSeq: 0 }) };
        }
        return origFetch(u);
      };
      await T.pressBattleFlag();
      check('flagbtn: pressing sends toggle regardless of the UI phase', seenActions.join(',') === 'toggle' && T.flagPhase === 'inBattle' && T.flagBtnLabel() === '試合終了');
      stubPhase = 'idle';
      await T.pressBattleFlag();
      check('flagbtn: pressing again still sends toggle and follows the response phase', seenActions.join(',') === 'toggle,toggle' && T.flagPhase === 'idle' && T.flagBtnLabel() === '試合開始');
      stubOk = false;
      await T.pressBattleFlag();
      check('flagbtn: a failed response leaves the UI phase unchanged', seenActions.join(',') === 'toggle,toggle,toggle' && T.flagPhase === 'idle' && T.flagBtnLabel() === '試合開始');
      globalThis.fetch = origFetch;
    }
    // --- pokedb ボタン (ポケ徹の右横) ---
    {
      const sp = T.oppSpec('Absol', 'usage');
      check('pokedb: url resolves with the usage code and current season', T.pokedbURL(sp) === 'https://champs.pokedb.tokyo/pokemon/show/0359-00?season=8&rule=1');
      sp.mega = true;
      check('pokedb: mega forme resolves to the base species page', T.pokedbURL(sp) === 'https://champs.pokedb.tokyo/pokemon/show/0359-00?season=8&rule=1');
      const outside = T.oppSpec('Rayquaza', 'usage');
      check('pokedb: species without pokedb data gets no button url', T.pokedbURL(outside) === null);
      check('pokedb: button markup sits next to the poketetsu button', html.includes('data-pokedb="${side}"'));
    }
    // --- レンタルコード付きチームプリセットのコピーボタン ---
    {
      check('rental: no copy button without a code', !T.playerBar('mine').includes('data-rentalcopy'));
      await T.ensureVgcTeams();
      const teams = T.VGC_TEAMS.teams;
      teams.push({ teamId: 'TESTCODE', description: 'Test Team', rentalCode: 'ABCD1234', members: [{ species: 'Garchomp', forme: 'Garchomp', ability: 'Rough Skin', item: 'Life Orb', nature: 'Adamant', sps: { hp: 2, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, moves: ['Earthquake'] }] });
      T.applyVgcTeam('mine', 'TESTCODE');
      check('rental: loading a coded team shows the copy button with the code', T.presetRental.mine === 'ABCD1234' && T.playerBar('mine').includes('data-rentalcopy="mine"') && T.playerBar('mine').includes('ABCD1234'));
      const plain = teams.find(t => t.teamId !== 'TESTCODE' && !t.rentalCode);
      T.applyVgcTeam('mine', plain.teamId);
      check('rental: loading a team without a code hides the button', T.presetRental.mine === '' && !T.playerBar('mine').includes('data-rentalcopy'));
      teams.splice(teams.findIndex(t => t.teamId === 'TESTCODE'), 1);
    }
    // --- 対戦が切り替わったら、前の対戦の判明情報を証拠として再投入しない ---
    {
      T.resetInference();
      T.applyState({ battle: '20261122_080100', oppReset: true, oppTeam: ['Incineroar'], opps: [{ species: 'Incineroar', revealed: { moves: ['Flare Blitz'] } }], events: [], field: {} });
      const beforeOk = T.state.opps[0].knownMoves.includes('Flare Blitz');
      T.applyState({ battle: '20261122_080500', oppTeam: ['Incineroar', 'Raichu'], opps: [], events: [], field: {} });
      const phantom = T.inferLog.filter(r => r.battle === '20261122_080500' && r.species === 'Incineroar' && r.trigger && (r.trigger.kind === 'moveSeen' || r.trigger.kind === 'entry'));
      check('battle-switch: revealed info from the previous battle is not re-fed as evidence', beforeOk && phantom.length === 0 && T.state.opps[0].knownMoves.length === 0);
    }
  }

  // --- プリセット使用履歴 (lastUsed) の記録と起動時適用 ---
  {
    T.state.mine = [T.oppSpec('Dragonite', 'usage')];
    T.savePreset('mine', 'LU-M');
    T.state.opps = [T.oppSpec('Tyranitar', 'usage')]; T.state.oppTeam = ['Tyranitar'];
    T.savePreset('opps', 'LU-O');
    let storeLU = T.loadPresetStore();
    const miLU = storeLU.mine.findIndex(p => p.name === 'LU-M');
    const oiLU = storeLU.opps.findIndex(p => p.name === 'LU-O');
    T.state.mine = [T.oppSpec('Garchomp', 'usage')];
    T.applyPreset('mine', miLU);
    T.state.opps = [T.oppSpec('Garchomp', 'usage')]; T.state.oppTeam = ['Garchomp'];
    T.applyPreset('opps', oiLU);
    storeLU = T.loadPresetStore();
    check('lastused: preset application records lastUsed on both sides', !!storeLU.lastUsed && !!storeLU.lastUsed.mine && storeLU.lastUsed.mine.kind === 'preset' && storeLU.lastUsed.mine.name === 'LU-M' && !!storeLU.lastUsed.opps && storeLU.lastUsed.opps.kind === 'preset' && storeLU.lastUsed.opps.name === 'LU-O');
    // 新規読み込み相当: パネルを既定へ戻し、起動時適用で両側が履歴のプリセットになる
    T.state.mine = [T.oppSpec('Garchomp', 'usage')];
    T.state.opps = [T.oppSpec('Garchomp', 'usage')]; T.state.oppTeam = ['Garchomp'];
    T.lastUsedStartup.done.mine = false; T.lastUsedStartup.done.opps = false; T.lastUsedStartup.boardSeen = false;
    T.applyLastUsedStartup();
    check('lastused: startup application restores both sides from lastUsed', T.state.mine[0].species === 'Dragonite' && T.state.opps[0].species === 'Tyranitar');
    // 参照先が無い場合は既定のまま・履歴は不変
    storeLU = T.loadPresetStore(); storeLU.lastUsed.mine = { kind: 'preset', name: 'LU-MISSING' }; T.savePresetStore(storeLU);
    T.state.mine = [T.oppSpec('Garchomp', 'usage')];
    T.lastUsedStartup.done.mine = false;
    T.applyLastUsedStartup();
    check('lastused: a missing reference keeps the default and the history', T.state.mine[0].species === 'Garchomp' && T.loadPresetStore().lastUsed.mine.name === 'LU-MISSING');
    // VGC チーム: 適用で記録され、起動時適用でも復元される
    T.ensureVgcTeams();
    for (let i = 0; i < 50 && !T.VGC_TEAMS; i++) await new Promise(r => setTimeout(r, 100));
    const teamLU = T.VGC_TEAMS.teams[0];
    T.applyVgcTeam('opps', teamLU.teamId);
    const appliedFirstLU = T.state.opps[0].species;
    storeLU = T.loadPresetStore();
    check('lastused: a VGC team application records lastUsed', !!storeLU.lastUsed.opps && storeLU.lastUsed.opps.kind === 'vgc' && storeLU.lastUsed.opps.teamId === String(teamLU.teamId));
    T.state.opps = [T.oppSpec('Garchomp', 'usage')]; T.state.oppTeam = ['Garchomp'];
    T.lastUsedStartup.done.opps = false;
    T.applyLastUsedStartup();
    check('lastused: startup application restores a VGC team', T.state.opps[0].species === appliedFirstLU && T.state.oppTeam[0] === appliedFirstLU);
    // リネーム・削除への追随
    storeLU = T.loadPresetStore(); storeLU.lastUsed.mine = { kind: 'preset', name: 'LU-M' }; T.savePresetStore(storeLU);
    const riLU = T.loadPresetStore().mine.findIndex(p => p.name === 'LU-M');
    T.renamePreset('mine', riLU, 'LU-M2');
    const afterRenameLU = T.loadPresetStore().lastUsed.mine;
    const diLU = T.loadPresetStore().mine.findIndex(p => p.name === 'LU-M2');
    T.deletePreset('mine', diLU);
    check('lastused: rename and delete are followed', !!afterRenameLU && afterRenameLU.name === 'LU-M2' && T.loadPresetStore().lastUsed.mine === null);
  }

  // 登録性格 (e.nature) による逆算候補の絞り込み。ガブリアス いじっぱり
  // (atk 200) の atk が 182 と誤読された実例の再現値: 逆算候補は
  // ようき 先頭の4件で、いじっぱり は2件含まれる。
  {
    const statsNF = { hp: 183, atk: 182, def: 115, spa: 90, spd: 105, spe: 154 };
    const allNF = T.deriveBuild('Garchomp', statsNF);
    const adamNF = allNF.filter(s => s.nature === 'Adamant');
    check('naturefilter: fixture has Jolly first and Adamant candidates', allNF.length === 4 && allNF[0].nature === 'Jolly' && adamNF.length === 2);
    const noNat = T.myTeamPreset({ species: 'Garchomp', stats: statsNF });
    check('naturefilter: without nature the first candidate wins as before', !!noNat && noNat.nature === 'Jolly' && noNat.derivedAmbiguous === true);
    const withNat = T.myTeamPreset({ species: 'Garchomp', stats: statsNF, nature: 'Adamant' });
    check('naturefilter: registered nature narrows candidates', !!withNat && withNat.nature === 'Adamant'
      && JSON.stringify(withNat.sp) === JSON.stringify(adamNF[0].sp) && withNat.derivedAmbiguous === (adamNF.length > 1));
    const hinted = T.myTeamPreset({ species: 'Garchomp', stats: statsNF, nature: 'Adamant', spHint: adamNF[1].sp });
    check('naturefilter: spHint exact match is preferred inside the narrowed set', !!hinted && hinted.nature === 'Adamant'
      && JSON.stringify(hinted.sp) === JSON.stringify(adamNF[1].sp));
    const contra = T.myTeamPreset({ species: 'Garchomp', stats: { ...statsNF, atk: 175 }, nature: 'Adamant' });
    check('naturefilter: contradiction falls back to all candidates', !!contra && contra.nature === 'Jolly');
    const bogus = T.myTeamPreset({ species: 'Garchomp', stats: statsNF, nature: 'Bogus' });
    check('naturefilter: invalid nature name is ignored', !!bogus && bogus.nature === 'Jolly');
  }

  // コピー文章の確定数は満タン前提 (画面表示は現在 HP 前提のまま)。
  // ガブリアスのドラゴンクロー vs カビゴン (HP 32 / 防御 32): 満タンでは
  // guaranteed 4HKO、HP 20% では guaranteed OHKO になる組み合わせ。
  {
    const snapMine0 = T.state.mine[0], snapOpps0 = T.state.opps[0];
    const snapWeather = T.state.field.weather, snapTerrain = T.state.field.terrain;
    T.state.field.weather = ''; T.state.field.terrain = '';
    const zeroB = { atk: 0, def: 0, spa: 0, spd: 0, spe: 0, acc: 0, eva: 0 };
    T.state.mine[0] = { species: 'Garchomp', sp: { hp: 0, atk: 32, def: 0, spa: 0, spd: 0, spe: 32 }, nature: 'Adamant', ability: 'Rough Skin', item: '', moves: ['Dragon Claw'], curHPPercent: 100, boosts: { ...zeroB }, status: '' };
    T.state.opps[0] = { species: 'Snorlax', sp: { hp: 32, atk: 0, def: 32, spa: 0, spd: 0, spe: 0 }, nature: 'Bold', ability: 'Thick Fat', item: '', moves: ['Body Slam'], curHPPercent: 20, boosts: { ...zeroB }, status: '' };
    T.calcAll();
    const vsCK = T.lastCalc.results[0].moveResults[0].vs[0];
    check('copyko: display KO text uses current HP', !!vsCK && vsCK.ko === 'guaranteed OHKO' && vsCK.desc.includes('guaranteed OHKO'));
    check('copyko: descFull assumes full HP', !!vsCK && !!vsCK.descFull && vsCK.descFull.includes('guaranteed 4HKO'));
    const boxCK = T.movesBox('mine', T.lastCalc.results[0]);
    const copies = [...boxCK.matchAll(/data-copy="([^"]*)"/g)].map(m => m[1]);
    check('copyko: copied text uses the full-HP KO text', copies.length > 0 && copies.some(c => c.includes('guaranteed 4HKO')) && !copies.some(c => c.includes('guaranteed OHKO')));
    T.state.opps[0].curHPPercent = 100;
    T.calcAll();
    const vsFull = T.lastCalc.results[0].moveResults[0].vs[0];
    check('copyko: no descFull at full HP', !!vsFull && vsFull.descFull === null && vsFull.ko === 'guaranteed 4HKO');
    T.state.mine[0] = snapMine0; T.state.opps[0] = snapOpps0;
    T.state.field.weather = snapWeather; T.state.field.terrain = snapTerrain;
    T.calcAll();
  }

  const pal = T.oppSpec('Palafin-Hero', 'usage');
  check('palafin-hero: gets base moves', Array.isArray(pal.moves) && pal.moves.filter(Boolean).length >= 3);
} finally {
  try { fs.unlinkSync(tmp); } catch (e) {}
}
console.log(failures === 0 ? 'ALL PASS' : `${failures} FAILURES`);
process.exit(failures === 0 ? 0 : 1);
