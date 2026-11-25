// smoke_test.mjs — リプレイ1（vs perish blast）ターン1 の局面で叩き台を試す
// 実際の mikumiku37 の行動: オーロンゲ=リフレクター / リザードン→ブリジュラスへ交代
import { decide } from './decision_engine.mjs';
import { completeSet } from './sets.mjs';

const mon = (set, extra = {}) => ({ set: completeSet(set), hpPct: 100, boosts: {}, status: '', firstTurnOut: true, ...extra });

const state = {
  turn: 1,
  field: { weather: null, terrain: null, trickRoom: false },
  me: {
    actives: [
      mon({ species: 'Grimmsnarl', item: 'Light Clay', ability: 'Prankster', nature: 'Careful', moves: ['Spirit Break', 'Light Screen', 'Reflect', 'Parting Shot'] }),
      mon({ species: 'Charizard', item: 'Charizardite Y', ability: 'Blaze', nature: 'Timid', moves: ['Heat Wave', 'Weather Ball', 'Solar Beam', 'Protect'] }),
    ],
    bench: [
      mon({ species: 'Archaludon', item: 'Leftovers', ability: 'Stamina', nature: 'Calm', moves: ['Electro Shot', 'Snarl', 'Dragon Pulse', 'Protect'] }, { firstTurnOut: false }),
      mon({ species: 'Pelipper', item: 'Sitrus Berry', ability: 'Drizzle', nature: 'Bold', moves: ['Hurricane', 'Weather Ball', 'Tailwind', 'Wide Guard'] }, { firstTurnOut: false }),
      mon({ species: 'Venusaur', item: 'Focus Sash', ability: 'Chlorophyll', nature: 'Modest', moves: ['Earth Power', 'Sludge Bomb', 'Sleep Powder', 'Protect'] }, { firstTurnOut: false }),
      mon({ species: 'Garchomp', item: 'Garchompite Z', ability: 'Rough Skin', nature: 'Modest', moves: ['Earth Power', 'Draco Meteor', 'Power Gem', 'Protect'] }, { firstTurnOut: false }),
    ],
    conditions: {},
  },
  opp: {
    actives: [
      mon({ species: 'Froslass', item: 'Froslassite', ability: 'Cursed Body', nature: 'Timid', moves: ['Blizzard', 'Shadow Ball', 'Aurora Veil', 'Protect'] }),
      mon({ species: 'Lycanroc-Dusk', item: 'Focus Sash', ability: 'Tough Claws', nature: 'Adamant', moves: ['Rock Slide', 'Close Combat', 'Accelerock', 'Protect'] }),
    ],
    bench: [],
    conditions: {},
  },
  megaUsed: { me: false, opp: false },
};

const fmt = (a) => !a ? '—' : a.type === 'switch' ? `交代→${a.switchTo} (${a.score.toFixed(1)})` : `${a.move}${a.mega ? ' [メガ]' : ''} → ${a.target} (${a.score.toFixed(1)})`;
const out = decide(state);
console.log('最善手:', fmt(out.pair.a), '/', fmt(out.pair.b), ' 合計', out.pair.total.toFixed(1));
console.log('内訳:', JSON.stringify(out.pair.parts));
for (const alt of out.alternatives) console.log('次点 :', fmt(alt.a), '/', fmt(alt.b), ' 合計', alt.total.toFixed(1));
