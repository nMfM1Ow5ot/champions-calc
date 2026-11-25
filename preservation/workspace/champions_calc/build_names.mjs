// names_raw.json (PokeAPI slug -> JA) を @smogon/calc のIDキーに変換して names_ja.json を作る
import { Generations } from '@smogon/calc';
import { readFileSync, writeFileSync } from 'fs';

const raw = JSON.parse(readFileSync(new URL('./data/names_raw.json', import.meta.url), 'utf8'));
const gen = Generations.get(9);

const slugify = (name) => name.toLowerCase().replace(/['’.]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const strip = (slug) => slug.replace(/-/g, '');

// --- species ---
const speciesJa = {};
let spMiss = [];
for (const s of gen.species) {
  const baseSlug = slugify(s.baseSpecies || s.name);
  let baseJa = raw.species[baseSlug];
  if (!baseJa) {
    // baseSpecies が兄弟フォルムを指す種族 (Aegislash 系: baseSlug 'aegislash-blade') は
    // PokeAPI のスラッグ 'aegislash' と一致しないため、'-' で切り詰めて再照合する。
    let s = baseSlug;
    while (s.includes('-')) {
      s = s.slice(0, s.lastIndexOf('-'));
      if (raw.species[s]) { baseJa = raw.species[s]; break; }
    }
  }
  if (!baseJa) { spMiss.push(s.name); speciesJa[s.id] = s.name; continue; }
  const f = (s.name === (s.baseSpecies || s.name)) ? '' : s.name.slice((s.baseSpecies || s.name).length + 1);
  let ja;
  if (!f) ja = baseJa;
  else if (f === 'Mega') ja = 'メガ' + baseJa;
  else if (f === 'Mega-X') ja = 'メガ' + baseJa + 'X';
  else if (f === 'Mega-Y') ja = 'メガ' + baseJa + 'Y';
  else if (f === 'Mega-Z') ja = 'メガ' + baseJa + 'Z';
  else if (f === 'Alola') ja = baseJa + '（アローラ）';
  else if (f === 'Galar') ja = baseJa + '（ガラル）';
  else if (f === 'Hisui') ja = baseJa + '（ヒスイ）';
  else if (f.startsWith('Paldea')) ja = baseJa + '（パルデア）';
  else ja = baseJa; // その他のフォルムは一旦ベース名 (UIで英語名も併記可能)
  speciesJa[s.id] = ja;
}

// --- moves ---
const movesJa = {};
let mvMiss = [];
const MOVE_ALIAS = { 'vise-grip': 'vice-grip' };
// PokeAPI に存在しない技の日本語名サプリメント (Zワザは PokeAPI の move 一覧に
// 含まれない。出典: veekun/pokedex の move_names (language_id=11) と公式表記)
const MOVE_JA_EXTRA = {
  'acid-downpour': 'アシッドポイズンデリート',
  'all-out-pummeling': 'ぜんりょくむそうげきれつけん',
  'black-hole-eclipse': 'ブラックホールイクリプス',
  'bloom-doom': 'ブルームシャインエクストラ',
  'breakneck-blitz': 'ウルトラダッシュアタック',
  'continental-crush': 'ワールズエンドフォール',
  'corkscrew-crash': 'ちょうぜつらせんれんげき',
  'devastating-drake': 'アルティメットドラゴンバーン',
  'gigavolt-havoc': 'スパーキングギガボルト',
  'hydro-vortex': 'スーパーアクアトルネード',
  'inferno-overdrive': 'ダイナミックフルフレイム',
  'never-ending-nightmare': 'むげんあんやへのいざない',
  'savage-spin-out': 'ぜったいほしょくかいてんざん',
  'shattered-psyche': 'マキシマムサイブレイカー',
  'subzero-slammer': 'レイジングジオフリーズ',
  'supersonic-skystrike': 'ファイナルダイブクラッシュ',
  'tectonic-rage': 'ライジングランドオーバー',
  'twinkle-tackle': 'ラブリースターインパクト',
  'nihil-light': 'むにきすひかり',
  // キョダイマックスわざ (PokeAPI の move 一覧に含まれない。出典: Bulbapedia
  // 各技ページの公式日本語名)
  'g-max-befuddle': 'キョダイコワク',
  'g-max-centiferno': 'キョダイヒャッカ',
  'g-max-cannonade': 'キョダイホウゲキ',
  'g-max-chi-strike': 'キョダイシンゲキ',
  'g-max-cuddle': 'キョダイホーヨー',
  'g-max-depletion': 'キョダイゲンスイ',
  'g-max-drum-solo': 'キョダイコランダ',
  'g-max-fireball': 'キョダイカキュウ',
  'g-max-finale': 'キョダイダンエン',
  'g-max-foam-burst': 'キョダイホウマツ',
  'g-max-gold-rush': 'キョダイコバン',
  'g-max-gravitas': 'キョダイテンドウ',
  'g-max-hydrosnipe': 'キョダイソゲキ',
  'g-max-malodor': 'キョダイシュウキ',
  'g-max-meltdown': 'キョダイユウゲキ',
  'g-max-one-blow': 'キョダイイチゲキ',
  'g-max-rapid-flow': 'キョダイレンゲキ',
  'g-max-replenish': 'キョダイサイセイ',
  'g-max-resonance': 'キョダイセンリツ',
  'g-max-sandblast': 'キョダイサジン',
  'g-max-smite': 'キョダイテンバツ',
  'g-max-snooze': 'キョダイスイマ',
  'g-max-steelsurge': 'キョダイコウジン',
  'g-max-stonesurge': 'キョダイガンジン',
  'g-max-stun-shock': 'キョダイカンデン',
  'g-max-sweetness': 'キョダイカンロ',
  'g-max-tartness': 'キョダイサンゲキ',
  'g-max-terror': 'キョダイゲンエイ',
  'g-max-vine-lash': 'キョダイベンタツ',
  'g-max-volcalith': 'キョダイフンセキ',
  'g-max-volt-crash': 'キョダイバンライ',
  'g-max-wildfire': 'キョダイゴクエン',
  'g-max-wind-rage': 'キョダイフウゲキ',
  // めざめるパワーのタイプ別エントリ (表示名はすべて めざめるパワー)
  'hidden-power-bug': 'めざめるパワー',
  'hidden-power-dark': 'めざめるパワー',
  'hidden-power-dragon': 'めざめるパワー',
  'hidden-power-electric': 'めざめるパワー',
  'hidden-power-fighting': 'めざめるパワー',
  'hidden-power-fire': 'めざめるパワー',
  'hidden-power-flying': 'めざめるパワー',
  'hidden-power-ghost': 'めざめるパワー',
  'hidden-power-grass': 'めざめるパワー',
  'hidden-power-ground': 'めざめるパワー',
  'hidden-power-ice': 'めざめるパワー',
  'hidden-power-poison': 'めざめるパワー',
  'hidden-power-psychic': 'めざめるパワー',
  'hidden-power-rock': 'めざめるパワー',
  'hidden-power-steel': 'めざめるパワー',
  'hidden-power-water': 'めざめるパワー',
};
for (const m of gen.moves) {
  const slug = slugify(m.name);
  const ja = raw.moves[MOVE_ALIAS[slug] || slug] || MOVE_JA_EXTRA[slug];
  if (ja) movesJa[m.id] = ja; else { mvMiss.push(m.name); movesJa[m.id] = m.name; }
}

// --- abilities ---
const abilitiesJa = {};
// PokeAPI に日本語名が無い新特性のサプリメント (出典: Bulbapedia の公式日本語名)
const ABILITY_JA_EXTRA = {
  'eelevate': 'うなぎのぼり',
  'aura-guard': 'はどうのぼうご',
  'fire-mane': 'ほのおのたてがみ',
  'spicy-spray': 'とびだすハバネロ',
  // オーガポンのフォルム別エントリ (特性名はいずれも おもかげやどし。
  // PokeAPI の embody-aspect の日本語名で確認)
  'embody-aspect-cornerstone': 'おもかげやどし',
  'embody-aspect-hearthflame': 'おもかげやどし',
  'embody-aspect-teal': 'おもかげやどし',
  'embody-aspect-wellspring': 'おもかげやどし',
  // CAP 特性 (公式日本語名なし。UI 側 ABILITY_JA_EXTRA と同じカタカナ
  // 表記でデータ側も揃える)
  'mountaineer': 'マウンテニア',
  'persistent': 'パーシステント',
  'rebound': 'リバウンド',
};
for (const a of gen.abilities) {
  const slug = slugify(a.name);
  abilitiesJa[a.id] = raw.abilities[slug] || ABILITY_JA_EXTRA[slug] || a.name;
}

writeFileSync(new URL('./data/names_ja.json', import.meta.url),
  JSON.stringify({ species: speciesJa, moves: movesJa, abilities: abilitiesJa }, null, 0));
console.log('species total', Object.keys(speciesJa).length, 'base-miss', spMiss.length, spMiss.slice(0, 10));
console.log('moves total', Object.keys(movesJa).length, 'miss', mvMiss.length, mvMiss.slice(0, 15));
// ユーザーのチームで確認
for (const id of ['raichu', 'raichumegay', 'raichumegax', 'garchomp', 'garchompmegaz', 'gholdengo', 'volcarona', 'rillaboom', 'incineroar'])
  console.log(id, '->', speciesJa[id]);
for (const id of ['zapcannon', 'focusblast', 'fakeout', 'protect', 'dragonpulse', 'earthpower', 'powergem', 'makeitrain', 'shadowball', 'nastyplot', 'overheat', 'strugglebug', 'ragepowder', 'tailwind', 'grassyglide', 'woodhammer', 'uturn', 'flareblitz', 'darkestlariat', 'partingshot'])
  console.log(id, '->', movesJa[id]);
