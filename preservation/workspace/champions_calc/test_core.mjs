import { Generations, Pokemon, Move, Field, calculate, Stats } from '@smogon/calc';

const gen = Generations.get(9);

// --- 1. Champions実数値の再現チェック: EV = SP x 8, IV31, Lv50 ---
function championsStat(base, sp, isHP, natureMod) {
  if (isHP) return base + 75 + sp;
  return Math.floor((base + 20 + sp) * natureMod);
}
function check(speciesName, stat, sp, nature, natureMod) {
  const sp2 = gen.species.get(speciesName.toLowerCase().replace(/[^a-z0-9]/g, ''));
  const base = sp2.baseStats[stat];
  const p = new Pokemon(gen, speciesName, {
    level: 50, nature, ivs: { hp:31, atk:31, def:31, spa:31, spd:31, spe:31 },
    evs: { [stat]: sp * 8 },
  });
  const got = p.stats[stat];
  const want = championsStat(base, sp, stat === 'hp', natureMod);
  console.log(`${speciesName} ${stat} SP${sp} nature=${nature}: calc=${got} champions=${want} ${got === want ? 'OK' : 'MISMATCH'}`);
}
check('Garchomp', 'spe', 32, 'Jolly', 1.1);
check('Garchomp', 'spe', 0, 'Jolly', 1.1);
check('Garchomp', 'hp', 0, 'Jolly', 1.0);
check('Garchomp', 'hp', 32, 'Jolly', 1.0);
check('Raichu', 'spa', 0, 'Timid', 1.0);
check('Garchomp', 'spa', 30, 'Modest', 1.1);
check('Garchomp', 'atk', 17, 'Adamant', 1.1);
check('Incineroar', 'hp', 30, 'Impish', 1.0);
check('Incineroar', 'def', 20, 'Impish', 1.1);

// --- 2. メガシンカ (Championsのメガ) のデータ有無 ---
for (const g of [9, 8, 7, 6]) {
  const gg = Generations.get(g);
  const names = [];
  for (const s of gg.species) {
    if ((s.name.includes('Garchomp') || s.name.includes('Raichu')) && s.name !== 'Garchomp' && s.name !== 'Raichu') names.push(s.name);
  }
  console.log(`gen${g}:`, names.join(', ') || '(none)');
}

// --- 3. サンプル計算 (ダブルス) ---
try {
  const gar = new Pokemon(gen, 'Garchomp-Mega-Z', {
    level: 50, nature: 'Modest', ability: 'Levitate',
    ivs: { hp:31, atk:31, def:31, spa:31, spd:31, spe:31 },
    evs: { def: 4 * 8, spa: 30 * 8, spe: 32 * 8 },
  });
  const inc = new Pokemon(gen, 'Incineroar', {
    level: 50, nature: 'Impish', ability: 'Intimidate', item: 'Sitrus Berry',
    ivs: { hp:31, atk:31, def:31, spa:31, spd:31, spe:31 },
    evs: { hp: 30 * 8, def: 20 * 8, spd: 14 * 8, spe: 2 * 8 },
  });
  const field = new Field({ gameType: 'doubles' });
  const res = calculate(gen, gar, inc, new Move(gen, 'Dragon Pulse'), field);
  console.log('Mega Garchomp Z Dragon Pulse vs Incineroar:', res.range(), res.desc());
} catch (e) {
  console.log('sample calc failed:', e.message);
}
