// pokedb (champs.pokedb.tokyo) から使用率データを取得し、
// 各種族の「最も使用されている型」を構築して data/usage_sets.json を生成する。
// rule は data/regulation.json から読み、シーズンとレギュレーション名は一覧ページから自動検出する
// (レギュレーションが変わったら regulation.json の rule を新しい値にして実行するだけで追従できる)。
// 実行: node fetch_usage.mjs [--limit N] [--no-fetch]
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { Generations } from '@smogon/calc';

const gen = Generations.get(9);
const CACHE = new URL('./data/pokedb_cache/', import.meta.url).pathname;
mkdirSync(CACHE, { recursive: true });
const args = process.argv.slice(2);
const LIMIT = args.includes('--limit') ? +args[args.indexOf('--limit') + 1] : Infinity;
const NO_FETCH = args.includes('--no-fetch');

function curl(url) {
  return execFileSync('curl', ['-sL', '--retry', '3', url], { maxBuffer: 64 * 1024 * 1024 }).toString('utf-8');
}
const z2h = s => s.replace(/[Ａ-Ｚａ-ｚ０-９]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0));
const stripTags = s => s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();

/* ---------- JA -> EN maps ---------- */
const namesJa = JSON.parse(readFileSync(new URL('./data/names_ja.json', import.meta.url), 'utf-8'));
const namesIdx = JSON.parse(readFileSync(new URL('./data/names_index.json', import.meta.url), 'utf-8'));
const ja2enSpecies = {};
for (const e of namesIdx.species || []) { if (!(e.ja in ja2enSpecies)) ja2enSpecies[e.ja] = e.en; }
const ja2enMove = {}, ja2enAbility = {};
for (const [id, jaName] of Object.entries(namesJa.moves || {})) { try { ja2enMove[jaName] = gen.moves.get(id).name; } catch {} }
for (const [id, jaName] of Object.entries(namesJa.abilities || {})) { try { ja2enAbility[jaName] = gen.abilities.get(id).name; } catch {} }
const NAT_JA2EN = { 'がんばりや': 'Hardy', 'さみしがり': 'Lonely', 'ゆうかん': 'Brave', 'いじっぱり': 'Adamant', 'やんちゃ': 'Naughty', 'ずぶとい': 'Bold', 'すなお': 'Docile', 'のんき': 'Relaxed', 'わんぱく': 'Impish', 'のうてんき': 'Lax', 'おくびょう': 'Timid', 'せっかち': 'Hasty', 'まじめ': 'Serious', 'ようき': 'Jolly', 'むじゃき': 'Naive', 'ひかえめ': 'Modest', 'おっとり': 'Mild', 'れいせい': 'Quiet', 'てれや': 'Bashful', 'うっかりや': 'Rash', 'おだやか': 'Calm', 'おとなしい': 'Gentle', 'なまいき': 'Sassy', 'しんちょう': 'Careful', 'きまぐれ': 'Quirky' };
const ITEM_JA2EN = {
  'いのちのたま': 'Life Orb', 'こだわりスカーフ': 'Choice Scarf', 'こだわりメガネ': 'Choice Specs', 'こだわりハチマキ': 'Choice Band',
  'きあいのタスキ': 'Focus Sash', 'たべのこし': 'Leftovers', 'オボンのみ': 'Sitrus Berry', 'ゴツゴツメット': 'Rocky Helmet',
  'ハバンのみ': 'Haban Berry', 'オッカのみ': 'Occa Berry', 'ロゼルのみ': 'Roseli Berry', 'やわらかいすな': 'Soft Sand',
  'とつげきチョッキ': 'Assault Vest', 'じゃくてんほけん': 'Weakness Policy', 'シルクのスカーフ': 'Silk Scarf', 'もくたん': 'Charcoal',
  'しんぴのしずく': 'Mystic Water', 'りゅうのキバ': 'Dragon Fang', 'メタルコート': 'Metal Coat', 'くろいメガネ': 'Black Glasses',
  'どくバリ': 'Poison Barb', 'じしゃく': 'Magnet', 'かたいいし': 'Hard Stone', 'きせきのタネ': 'Miracle Seed',
  'のろいの札': 'Spell Tag', 'まがったスプーン': 'Twisted Spoon', 'フェアリーフェザー': 'Fairy Feather', 'ようせいのハネ': 'Fairy Feather', 'ノーマルジュエル': 'Normal Gem', 'パンチグローブ': 'Punching Glove',
  'サイコシード': 'Psychic Seed', 'グラスシード': 'Grassy Seed', 'ミストシード': 'Misty Seed', 'エレキシード': 'Electric Seed',
  'ひかりのねんど': 'Light Clay', 'だっしゅつボタン': 'Eject Button', 'レッドカード': 'Red Card', 'メンタルハーブ': 'Mental Herb',
  'パワフルハーブ': 'Power Herb', 'しろいハーブ': 'White Herb', 'きあいのハチマキ': 'Focus Band', 'おうじゃのしるし': "King's Rock",
  'ピントレンズ': 'Scope Lens', 'こうかくレンズ': 'Wide Lens', 'するどいキバ': 'Razor Fang', 'するどいツメ': 'Razor Claw',
  'たつじんのおび': 'Expert Belt', 'ちからのハチマキ': 'Muscle Band', 'ものしりメガネ': 'Wise Glasses', 'くろおび': 'Black Belt',
  'ゆうきのおこう': 'Odd Incense', 'がんせきおこう': 'Rock Incense', 'うしおのおこう': 'Wave Incense', 'おはなのおこう': 'Rose Incense',
  'あやしいおこう': 'Odd Incense', 'ひかりのこな': 'Bright Powder', 'のんきのおこう': 'Lax Incense', 'フォーカスレンズ': 'Zoom Lens',
  'メトロノーム': 'Metronome', 'たまむしプレート': 'Insect Plate', 'ランチプレート': 'Pixie Plate', 'モスプレート': 'Meadow Plate',
  'フィストプレート': 'Fist Plate', 'どくバリプレート': 'Toxic Plate', 'だいちのプレート': 'Earth Plate', 'あおぞらプレート': 'Sky Plate',
  'ふしぎのプレート': 'Mind Plate', 'かみなりのプレート': 'Zap Plate', 'りゅうのプレート': 'Draco Plate', 'こわもてプレート': 'Dread Plate',
  'こうてつプレート': 'Iron Plate', 'たまごプレート': 'Stone Plate', 'ゆきのプレート': 'Icicle Plate', 'ひのたまプレート': 'Flame Plate',
  'しずくのプレート': 'Splash Plate', 'もののけプレート': 'Spooky Plate', 'ラムのみ': 'Lum Berry', 'チイラのみ': 'Liechi Berry',
  'リュガのみ': 'Ganlon Berry', 'ヤタピのみ': 'Petaya Berry', 'ズアのみ': 'Micle Berry', 'カムラのみ': 'Jaboca Berry',
  'タラプのみ': 'Rowap Berry', 'バコウのみ': 'Wacan Berry', 'ヨロギのみ': 'Tanga Berry', 'ソクノのみ': 'Kasib Berry',
  'リンドのみ': 'Rindo Berry', 'ヤチェのみ': 'Yache Berry', 'ヨプのみ': 'Payapa Berry', 'シュカのみ': 'Shuca Berry',
  'バンジのみ': 'Babiri Berry', 'ナモのみ': 'Passho Berry', 'モモンのみ': 'Pecha Berry', 'クラボのみ': 'Cheri Berry',
  'チーゴのみ': 'Chesto Berry', 'ナナシのみ': 'Rawst Berry', 'レンブのみ': 'Persim Berry', 'ヒメリのみ': 'Leppa Berry',
  'オレンのみ': 'Oran Berry', 'カゴのみ': 'Aspear Berry', 'ウイのみ': 'Wiki Berry', 'マゴのみ': 'Mago Berry',
  'バンジロのみ': 'Aguav Berry', 'イアのみ': 'Iapapa Berry', 'フィラのみ': 'Figy Berry', 'ゴールドスプレー': 'Gold Bottle Cap',
  'ぼうじんゴーグル': 'Safety Goggles', 'だっしゅつパック': 'Eject Pack', 'ルームサービス': 'Room Service',
  'グランドコート': 'Grand Court', 'クリアチャーム': 'Clear Amulet', 'ミラーコート': 'Mirror Herb', 'おんみつマント': 'Covert Cloak',
  'せんせいのツメ': 'Quick Claw', 'しめつけバンド': 'Binding Band', 'とけないこおり': 'Never-Melt Ice', 'するどいくちばし': 'Sharp Beak',
  'いかさまダイス': 'Loaded Dice', 'ブーストエナジー': 'Booster Energy', 'あつぞこブーツ': 'Heavy-Duty Boots',
  'くちたけん': 'Rusted Sword', 'くちたたて': 'Rusted Shield', 'でんきだま': 'Light Ball', 'ふといホネ': 'Thick Club',
  'ながねぎ': 'Leek', 'ラッキーパンチ': 'Lucky Punch', 'メタルパウダー': 'Metal Powder', 'スピードパウダー': 'Quick Powder',
  'しんかいのキバ': 'Deep Sea Tooth', 'しんかいのウロコ': 'Deep Sea Scale', 'こころのしずく': 'Soul Dew',
};
// メガストーンは calc データから自動生成 (JA名 = 種族JA名 + ナイト + 接尾辞)
const megaStoneByJa = {};
for (const item of gen.items) {
  const it = item;
  if (it && it.megaStone) {
    const forme = Object.values(it.megaStone)[0];
    const base = Object.keys(it.megaStone)[0];
    const m = forme.match(/-Mega-?(.*)$/);
    const suffix = m && m[1] ? m[1] : '';
    const jaBase = Object.keys(ja2enSpecies).find(j => ja2enSpecies[j] === base);
    // 日本語のメガストーン名は種族名の末尾の「ー」「ン」を落として「ナイト」を付ける (ゲンガー→ゲンガナイト)
    if (jaBase) megaStoneByJa[jaBase.replace(/ー$/, '').replace(/ン$/, '') + 'ナイト' + suffix] = it.name;
  }
}
function mapItem(jaName) {
  const n = z2h(jaName.trim());
  return ITEM_JA2EN[n] || megaStoneByJa[n] || null;
}

/* ---------- ranking list ---------- */
let REG = { regulation: 'M-C', rule: 1, season: 'M-8' };
try { REG = { ...REG, ...JSON.parse(readFileSync(new URL('./data/regulation.json', import.meta.url), 'utf8')) }; } catch (e) { /* 既定値 */ }
const RULE = REG.rule || 1;
const listHtml = curl(`https://champs.pokedb.tokyo/pokemon/list?rule=${RULE}`);
const seasonMatch = listHtml.match(new RegExp(`season=(\\d+)&rule=${RULE}`));
const SEASON_NUM = seasonMatch ? +seasonMatch[1] : 8;
const SEASON_LABEL = 'M-' + SEASON_NUM;
const regMatch = listHtml.match(/レギュレーション\s*([A-Z]-[A-Z0-9]+)/);
const REG_LABEL = regMatch ? regMatch[1] : REG.regulation;
console.log(`rule=${RULE} season=${SEASON_LABEL} regulation=${REG_LABEL}`);
const entries = [];
for (const m of listHtml.matchAll(new RegExp(`href="\\/pokemon\\/show\\/(\\d+-\\d+)\\?season=${SEASON_NUM}&rule=${RULE}"[\\s\\S]{0,1600}?class="pokemon-name">([^<]+)<\\/div>`, 'g'))) {
  entries.push({ code: m[1], ja: m[2].trim() });
}
console.log('list entries:', entries.length);

/* ---------- page parser ---------- */
function parseUsageList(html, label) {
  const h3 = html.indexOf(`<h3>${label}</h3>`);
  if (h3 < 0) return [];
  const ulStart = html.indexOf('<ul class="usage-list"', h3);
  if (ulStart < 0) return [];
  const ulEnd = html.indexOf('</ul>', ulStart);
  const seg = html.slice(ulStart, ulEnd);
  const out = [];
  for (const item of seg.split('<li class="usage-list-item">').slice(1)) {
    const name = stripTags((item.match(/class="usage-name[^"]*">([\s\S]*?)<\/span>/) || [])[1] || '').split(/[(（]/)[0].trim();
    const rate = parseFloat(((item.match(/class="usage-rate[^"]*">([\d.]+)%/) || [])[1] || '0'));
    if (name) out.push({ name, rate });
  }
  return out;
}
function parseMoves(html) {
  const out = [];
  for (const m of html.matchAll(/data-move-detail="(\{[^"]*\})"/g)) {
    try {
      const j = JSON.parse(m[1].replace(/&quot;/g, '"'));
      out.push({ ja: j.name, rate: j.rate, cat: j.category_label });
    } catch {}
  }
  return out.sort((a, b) => b.rate - a.rate);
}
const STAT_LETTER = { H: 'hp', A: 'atk', B: 'def', C: 'spa', D: 'spd', S: 'spe' };
function parsePatterns(html) {
  const h3 = html.indexOf('<h3>能力ポイント</h3>');
  if (h3 < 0) return [];
  const rawIdx = html.indexOf(`x-show="statViewMode === 'raw'"`, h3);
  const seg = rawIdx > 0 ? html.slice(rawIdx, rawIdx + 400000) : html.slice(h3, h3 + 400000);
  const out = [];
  for (const item of seg.split('<li class="usage-list-item').slice(1)) {
    const name = stripTags((item.match(/class="usage-name[^"]*">([\s\S]*?)<\/span>/) || [])[1] || '');
    const rate = parseFloat(((item.match(/class="usage-rate[^"]*">([\d.]+)%/) || [])[1] || '0'));
    const sp = {};
    for (const chip of item.matchAll(/pokemon-stat-spread__label">([A-Z+])<\/span>\s*<span class="pokemon-stat-spread__value[^"]*">(\d+)<\/span>/g)) {
      if (STAT_LETTER[chip[1]]) sp[STAT_LETTER[chip[1]]] = +chip[2];
    }
    if (name && Object.keys(sp).length) out.push({ label: name, rate, sp });
    if (out.length >= 12) break;
  }
  return out.sort((a, b) => b.rate - a.rate);
}
function parsePage(html) {
  return {
    moves: parseMoves(html),
    abilities: parseUsageList(html, '特性'),
    natures: parseUsageList(html, '能力補正'),
    items: parseUsageList(html, '持ち物'),
    patterns: parsePatterns(html),
  };
}

/* ---------- fetch + parse all ---------- */
const parsed = {};
const todo = entries.slice(0, LIMIT);
let done = 0;
for (const e of todo) {
  const cachePath = CACHE + e.code + '_s' + SEASON_NUM + '.html';
  let html;
  if (existsSync(cachePath)) html = readFileSync(cachePath, 'utf-8');
  else if (!NO_FETCH) {
    html = curl(`https://champs.pokedb.tokyo/pokemon/show/${e.code}?season=${SEASON_NUM}&rule=${RULE}`);
    writeFileSync(cachePath, html);
  } else continue;
  parsed[e.code] = { ja: e.ja, ...parsePage(html) };
  done++;
  if (done % 25 === 0) console.log('parsed', done, '/', todo.length);
}
writeFileSync(new URL('./data/pokedb_parsed.json', import.meta.url), JSON.stringify(parsed, null, 1));
console.log('parsed total:', Object.keys(parsed).length);

/* ---------- build most-used sets ---------- */
const NAT_UPDOWN = { Lonely: ['atk', 'def'], Brave: ['atk', 'spe'], Adamant: ['atk', 'spa'], Naughty: ['atk', 'spd'], Bold: ['def', 'atk'], Relaxed: ['def', 'spe'], Impish: ['def', 'spa'], Lax: ['def', 'spd'], Timid: ['spe', 'atk'], Hasty: ['spe', 'def'], Jolly: ['spe', 'spa'], Naive: ['spe', 'spd'], Modest: ['spa', 'atk'], Mild: ['spa', 'def'], Quiet: ['spa', 'spe'], Rash: ['spa', 'spd'], Calm: ['spd', 'atk'], Gentle: ['spd', 'def'], Sassy: ['spd', 'spe'], Careful: ['spd', 'spa'] };
const unmapped = { items: new Set(), moves: new Set(), abilities: new Set(), species: new Set(), natures: new Set() };

const FORME_SPECIAL = { 'ギルガルド': 'Aegislash', 'ウォッシュロトム': 'Rotom-Wash', 'ヒートロトム': 'Rotom-Heat', 'フロストロトム': 'Rotom-Frost', 'スピンロトム': 'Rotom-Fan', 'カットロトム': 'Rotom-Mow' };
const FORME_RULES = [
  [/[(（]ヒスイ[)）]/, '-Hisui'], [/[(（]アローラ[)）]/, '-Alola'], [/[(（]ガラル[)）]/, '-Galar'],
  [/[(（]たそがれ[)）]/, '-Dusk'], [/[(（]まよなか[)）]/, '-Midnight'], [/[(（]まひる[)）]/, ''],
  [/[(（]ハイ[)）]/, ''], [/[(（]ロー[)）]/, '-Low-Key'],
  [/[(（]グリーン[)）]/, ''], [/[(（]イエロー[)）]/, '-Yellow'], [/[(（]ブルー[)）]/, '-Blue'], [/[(（]レッド[)）]/, '-Red'], [/[(（]ホワイト[)）]/, '-White'],
  [/[(（]こだま[)）]/, '-Small'], [/[(（]ちゅうだま[)）]/, ''], [/[(（]おおだま[)）]/, '-Large'], [/[(（]ギガだま[)）]/, '-Super'],
  [/:永遠/, '-Eternal'], [/:炎/, '-Paldea-Blaze'], [/:水/, '-Paldea-Aqua'], [/:格/, '-Paldea-Combat'],
];
function resolveSpecies(jaName) {
  let n = jaName.trim();
  let female = false;
  if (/\(メス\)|（メス）/.test(n)) { female = true; n = n.replace(/[(（]メス[)）]/, '').trim(); }
  if (/\(オス\)|（オス）/.test(n)) { n = n.replace(/[(（]オス[)）]/, '').trim(); }
  if (FORME_SPECIAL[n]) return FORME_SPECIAL[n];
  let suffix = '';
  for (const [re, suf] of FORME_RULES) if (re.test(n)) { suffix = suf; n = n.replace(re, '').trim(); break; }
  let en = ja2enSpecies[n];
  if (!en) { unmapped.species.add(jaName); return null; }
  if (suffix) { const f = gen.species.get((en + suffix).toLowerCase().replace(/[^a-z0-9]/g, '')); if (f) en = f.name; }
  if (female) { const f = gen.species.get((en + '-F').toLowerCase().replace(/[^a-z0-9]/g, '')); if (f) en = f.name; }
  return en;
}
// calc のアイテムデータに無い新メガストーンでも、種族データ側にメガ形態があれば導出する
function megaFromItemJa(jaName, speciesEn) {
  const n = z2h(String(jaName).trim());
  const m = n.match(/ナイト([XYZ])?$/);
  if (!m) return null;
  const sd = gen.species.get((speciesEn + '-Mega' + (m[1] ? '-' + m[1] : '')).toLowerCase().replace(/[^a-z0-9]/g, ''));
  if (!sd) return null;
  let itemEn = null;
  for (const it of gen.items) if (it.megaStone && Object.values(it.megaStone)[0] === sd.name) { itemEn = it.name; break; }
  return { megaSpecies: sd.name, itemEn };
}
function pickNature(naturesJa, sp, styleKey) {
  const cands = [];
  for (const n of naturesJa) {
    const en = NAT_JA2EN[n.name];
    if (!en) { unmapped.natures.add(n.name); continue; }
    cands.push({ en, rate: n.rate });
  }
  if (!cands.length) return { en: 'Serious', rate: 0 };
  const invested = k => (sp[k] || 0) >= 16;
  const ok = cands.filter(c => {
    const ud = NAT_UPDOWN[c.en];
    if (!ud) return true;
    return !invested(ud[1]); // 振った能力を下げる性格は避ける
  });
  const pool = ok.length ? ok : cands;
  const boosting = pool.filter(c => { const ud = NAT_UPDOWN[c.en]; return ud && invested(ud[0]); });
  const finalPool = boosting.length ? boosting : pool;
  return finalPool.sort((a, b) => b.rate - a.rate)[0];
}
function buildSet(code, d) {
  const species = resolveSpecies(d.ja);
  if (!species) return null;
  const sd = gen.species.get(species.toLowerCase().replace(/[^a-z0-9]/g, ''));
  const topItemJa = d.items[0];
  const topItemEn = topItemJa ? mapItem(topItemJa.name) : null;
  let megaSpecies = null, itemEn = topItemEn || '';
  // メガストーンの場合はまず種族側から形態を導く (性別フォルム等でアイテム登録側と形態がずれるため)
  if (topItemJa && /ナイト[XYZ]?$/.test(z2h(topItemJa.name))) {
    const md = megaFromItemJa(topItemJa.name, species);
    if (md) { megaSpecies = md.megaSpecies; if (!itemEn) itemEn = md.itemEn || ''; }
  }
  if (!megaSpecies && topItemEn) {
    const it = gen.items.get(topItemEn.toLowerCase().replace(/[^a-z0-9]/g, ''));
    if (it && it.megaStone) megaSpecies = Object.values(it.megaStone)[0];
  }
  if (topItemJa && !topItemEn && !megaSpecies) unmapped.items.add(topItemJa.name);
  const effSd = megaSpecies ? gen.species.get(megaSpecies.toLowerCase().replace(/[^a-z0-9]/g, '')) : sd;
  // SP pattern: メガの場合はその攻撃スタイルに合う最上位パターンを優先
  let pattern = d.patterns[0];
  if (megaSpecies && d.patterns.length) {
    const styleKey = effSd.baseStats.spa > effSd.baseStats.atk ? 'spa' : 'atk';
    pattern = d.patterns.find(p => (p.sp[styleKey] || 0) >= 16) || pattern;
  }
  const sp = pattern ? { ...pattern.sp } : {};
  const styleKey = (sp.spa || 0) > (sp.atk || 0) ? 'spa' : (sp.atk || 0) > 0 ? 'atk' : (effSd.baseStats.spa > effSd.baseStats.atk ? 'spa' : 'atk');
  const nature = pickNature(d.natures, sp, styleKey);
  // ability
  let ability = null, abilityRate = 0;
  for (const a of d.abilities) { const en = ja2enAbility[a.name]; if (en) { ability = en; abilityRate = a.rate; break; } unmapped.abilities.add(a.name); }
  if (!ability) ability = (Array.isArray(sd.abilities) ? sd.abilities[0] : Object.values(sd.abilities)[0]);
  // moves: スタイルに合う技を優先して上位4つ
  const mappedMoves = [];
  for (const mv of d.moves) {
    const en = ja2enMove[mv.ja];
    if (!en) { unmapped.moves.add(mv.ja); continue; }
    mappedMoves.push({ en, rate: mv.rate, cat: mv.cat });
  }
  const styleCat = styleKey === 'spa' ? '特殊' : '物理';
  const picked = [];
  for (const mv of mappedMoves) { if (picked.length < 4 && (mv.cat === '変化' || mv.cat === styleCat)) picked.push(mv.en); }
  for (const mv of mappedMoves) { if (picked.length < 4 && !picked.includes(mv.en)) picked.push(mv.en); }
  return {
    species, megaSpecies,
    ability, nature: nature.en, item: itemEn,
    sp, moves: picked.slice(0, 4),
    rates: {
      ability: abilityRate, nature: nature.rate,
      item: topItemJa ? topItemJa.rate : 0, pattern: pattern ? pattern.rate : 0,
      patternLabel: pattern ? pattern.label : '',
    },
  };
}
if (entries.length && !Object.keys(parsed).length) { console.error('中止: 1件も解析できませんでした (キャッシュなしで --no-fetch を実行していませんか)'); process.exit(1); }
const sets = {};
for (const [code, d] of Object.entries(parsed)) {
  const s = buildSet(code, d);
  if (s) sets[s.species.toLowerCase().replace(/[^a-z0-9]/g, '')] = { code, ja: d.ja, ...s };
}
writeFileSync(new URL('./data/usage_sets.json', import.meta.url), JSON.stringify({ season: SEASON_LABEL, rule: RULE, source: 'champs.pokedb.tokyo', sets }, null, 1));
writeFileSync(new URL('./data/regulation.json', import.meta.url), JSON.stringify({ regulation: REG_LABEL, rule: RULE, season: SEASON_LABEL, updated: new Date().toISOString().slice(0, 10) }, null, 1));
console.log('regulation.json updated:', REG_LABEL, SEASON_LABEL);
// 既存の items_ja.json を優先してマージする (再取得のたびに、監査等で追加された
// 項目が消えないように。新規項目だけが生成マップから足される)
let existingItems = {};
try { existingItems = JSON.parse(readFileSync(new URL('./data/items_ja.json', import.meta.url), 'utf8')); } catch (e) { /* 既定値 */ }
writeFileSync(new URL('./data/items_ja.json', import.meta.url), JSON.stringify({ ...ITEM_JA2EN, ...megaStoneByJa, ...existingItems }, null, 1));
console.log('sets built:', Object.keys(sets).length);
console.log('unmapped items:', [...unmapped.items].slice(0, 30));
console.log('unmapped moves:', [...unmapped.moves].slice(0, 20));
console.log('unmapped abilities:', [...unmapped.abilities].slice(0, 20));
console.log('unmapped species:', [...unmapped.species]);
console.log('sample garchomp:', JSON.stringify(sets['garchomp'], null, 1));
