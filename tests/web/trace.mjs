// Web side of tests/trace.luau: node tests/web/trace.mjs <seed> ffa|duel <elements...>. Reads the web repo next to this one.
import { Game, seedRandom, DUEL_OPTS, DUEL_PACE } from "../../../ball_territory_web/public/game.js";
const [seed, mode, ...es] = process.argv.slice(2);
seedRandom(+seed);
const els = es.map(Number);
const g = mode === "duel" ? new Game(els.map(e => ({ e, ctl: null })), Object.assign({ pace: DUEL_PACE }, DUEL_OPTS)) : new Game(els.map(e => ({ e, ctl: null })));
g.launch();
const f = v => v.toPrecision(17);
const out = [];
const dump = () => { const S = g.S; let h = 0; for (let k = 0; k < S.owner.length; k++) h = (h * 31 + S.owner[k] + 2) % 1000000007;
  let lh = 0; for (const n of ["water","ice","bush","burn","toxic","sand","lava","slime","rock","glass","shock","gas"]) for (let k = 0; k < S.owner.length; k++) lh = (lh * 7 + (S.L[n][k] > 0 ? 1 : 0)) % 1000000007;
  out.push(`${S.tick} ${h} ${lh} ${S.reactions} ` + S.balls.map(b => `${f(b.x)},${f(b.y)},${f(b.charge)},${f(b.hp)}`).join(" ")); };
dump();
while (!g.S.done) { g.step(); g.drain(); dump(); }
console.log(out.join("\n"));
