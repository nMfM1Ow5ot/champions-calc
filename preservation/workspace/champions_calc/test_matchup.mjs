import { TEAM_PRESETS, assumedSet, calcMatchup, withCurHP } from './core.mjs';
import { readFileSync } from 'fs';
const names = JSON.parse(readFileSync(new URL('./data/names_ja.json', import.meta.url), 'utf8'));
const ja = (id, kind) => (names[kind] && names[kind][id.toLowerCase().replace(/[^a-z0-9]/g, '')]) || id;

const gar = { ...TEAM_PRESETS[1], mega: true };
const inc = { ...TEAM_PRESETS[5] };
const opp1 = { species: 'Garchomp', ...assumedSet('Garchomp', 'attacker'), moves: [] };
const opp2 = { species: 'Rillaboom', ...assumedSet('Rillaboom', 'attacker'), moves: [], curHPPercent: 62 };

const state = {
  mine: [withCurHP(gar), withCurHP(inc)],
  opps: [withCurHP(opp1), withCurHP(opp2)],
  field: { weather: undefined, terrain: undefined, tailwindMine: false, tailwindOpp: false },
};
const out = calcMatchup(state, names);
for (const r of out.results) {
  console.log('==', ja(r.species, 'species'), 'の技 ==');
  for (const mr of r.moveResults) {
    mr.vs.forEach((v, j) => {
      const oppName = ja(state.opps[j].species, 'species');
      console.log(`  ${ja(mr.move, 'moves')} -> ${oppName}: ${v.min}-${v.max} (${v.minPct}%-${v.maxPct}%) ${v.ko || v.error || ''}`);
    });
  }
}
console.log('素早さ 自分:', out.speeds.mine.join(', '), '/ 相手:', out.speeds.opps.join(', '));
console.log('相手想定:', opp1.note, '/', opp2.note);
