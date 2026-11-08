// Web numbers for tests/parity.luau: node tests/web/stats.mjs ffa 2000; node tests/web/stats.mjs duel 1000
import { Game, NEL, TITLE, pickFree, seedRandom, DUEL_OPTS, DUEL_PACE } from "../../../ball_territory_web/public/game.js";
const mode = process.argv[2] || "ffa", R = +process.argv[3] || 2000;
seedRandom(12345);
let rx = 0, pw = 0, ko = 0, first = 0, firstN = 0, steps = 0, t0 = performance.now();
const wins = new Array(NEL).fill(0), games = new Array(NEL).fill(0), seen = {};
for (let r = 0; r < R; r++) {
  let used = [];
  if (mode === "ffa") for (let i = 0; i < 4; i++) used.push(pickFree(used));
  else { const a = r % NEL, b = (a + 1 + Math.floor(r / NEL) % (NEL - 1)) % NEL; used = [a, b]; }
  const g = mode === "ffa" ? new Game(used.map(e => ({ e, ctl: null }))) : new Game(used.map(e => ({ e, ctl: null })), Object.assign({ pace: DUEL_PACE }, DUEL_OPTS));
  g.launch();
  let fp = -1;
  while (!g.S.done) { g.step(); steps++; for (const [, k, d] of g.drain()) { if (k === "power") { pw++; if (fp < 0) fp = g.S.t; } if (k === "ko") ko++; if (k === "rx") seen[d.k] = (seen[d.k] || 0) + 1; } }
  if (fp >= 0) { first += fp; firstN++; }
  rx += g.S.reactions;
  const c = g.S.counts, top = used.reduce((a, e) => c[e] > c[a] ? e : a, used[0]);
  if (mode === "ffa") { wins[top]++; } else { if (c[used[0]] > c[used[1]]) wins[used[0]]++; else if (c[used[1]] > c[used[0]]) wins[used[1]]++; else { wins[used[0]] += .5; wins[used[1]] += .5; } }
  for (const e of used) games[e]++;
}
const ms = performance.now() - t0;
console.log(JSON.stringify({ mode, R, reactions: rx / R, powers: pw / R, kos: ko / R, firstPower: first / firstN, msPerStep: ms / steps, kinds: Object.keys(seen).length, seen }));
console.log(TITLE.map((n, e) => `${n} ${(100 * wins[e] / games[e]).toFixed(1)}`).join("  "));
