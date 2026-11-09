// Exports web art to PNG atlases by calling the very same canvas functions of the web build
// (icon/ballArt/terrain/terrainIcon/crownArt from ball_territory_web/public/index.html).
// node tools/art/export.mjs  ->  assets/art/balls.png, assets/art/terrain.png, assets/art/layout.json
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../..");
const WEB = path.resolve(ROOT, "../ball_territory_web");
const OUT = path.join(ROOT, "assets/art");
const require = createRequire(path.join(WEB, "package.json"));
const puppeteer = require("puppeteer-core");

const html = fs.readFileSync(path.join(WEB, "public/index.html"), "utf8");
const a = html.indexOf("const VW = 720"), b = html.indexOf("// текст с бегущими точками");
const c = html.indexOf("function crownArt"), d = html.indexOf("\n}\n", c) + 3;
if (a < 0 || b < a || c < 0) throw new Error("index.html layout changed");
const art = html.slice(a, b) + "\n" + html.slice(c, d);

// Same order as Rules.Config.TOP.
const TOP = ["shock", "burn", "gas", "lava", "toxic", "slime", "water", "ice", "glass", "rock", "sand", "bush"];
// Animated layers: loop period (s) of their time term; 8 frames per loop.
const PERIOD = { water: Math.PI / 2, burn: Math.PI / 8, toxic: 1 / 0.6, lava: Math.PI * 2, gas: Math.PI };
const BALL = 128, TILE = 64, FRAMES = 8;

const page_ = `<!doctype html><html><head>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo+Black&display=swap"></head>
<body style="margin:0;background:transparent"><canvas id="game"></canvas>
<script type="module">
import * as G from "/game.js";
Object.assign(window, G);
const fx = { now: 0 };
try { await document.fonts.load('80px "Archivo Black"'); } catch (e) {}
${art}
const TOP = ${JSON.stringify(TOP)}, PERIOD = ${JSON.stringify(PERIOD)}, BALL = ${BALL}, TILE = ${TILE}, FRAMES = ${FRAMES};
function atlas(w, h, draw) { cv.width = w; cv.height = h; g.clearRect(0, 0, w, h); draw(); return cv.toDataURL("image/png"); }
const balls = atlas(BALL * 8, BALL * 5, () => {
  for (let e = 0; e < NEL; e++) ballArt(e, (e % 8 + .5) * BALL, ((e / 8 | 0) + .5) * BALL, BALL * .44);
  TOP.forEach((n, i) => { const s = 27 + i; terrainIcon(n, (s % 8 + .5) * BALL, ((s / 8 | 0) + .5) * BALL, BALL * .44); });
  crownArt((39 % 8 + .5) * BALL, (4 + .55) * BALL, BALL * .36);
});
const terrainPng = atlas(TILE * 16, TILE * TOP.length, () => {
  TOP.forEach((n, row) => {
    for (let chk = 0; chk < 2; chk++) for (let f = 0; f < FRAMES; f++) {
      const t = PERIOD[n] ? f / FRAMES * PERIOD[n] : 0;
      g.save(); g.beginPath(); g.rect((chk * 8 + f) * TILE, row * TILE, TILE, TILE); g.clip();
      terrain(n, (chk * 8 + f) * TILE, row * TILE, TILE, t, 0, chk);
      g.restore();
    }
  });
});
const icons = atlas(BALL * 8, BALL * 4, () => {
  for (let e = 0; e < NEL; e++) icon(e, (e % 8 + .5) * BALL, ((e / 8 | 0) + .5) * BALL, BALL * .4, "#fff", "rgba(0,0,0,0)");
});
window.__out = { balls, terrain: terrainPng, icons, fontOk: document.fonts.check('80px "Archivo Black"') };
</script></body></html>`;

const server = http.createServer((req, res) => {
  if (req.url === "/" || req.url.startsWith("/export")) { res.writeHead(200, { "content-type": "text/html" }); return res.end(page_); }
  const f = path.join(WEB, "public", path.normalize(req.url).replace(/^\/+/, ""));
  if (!f.startsWith(path.join(WEB, "public")) || !fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { "content-type": f.endsWith(".js") ? "text/javascript" : "application/octet-stream" });
  fs.createReadStream(f).pipe(res);
}).listen(0);
const port = server.address().port;

const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true });
try {
  const page = await browser.newPage();
  page.on("pageerror", e => console.error("page:", e.message));
  await page.goto(`http://127.0.0.1:${port}/export`);
  await page.waitForFunction("window.__out", { timeout: 20000 });
  const out = await page.evaluate("window.__out");
  fs.mkdirSync(OUT, { recursive: true });
  for (const k of ["balls", "terrain", "icons"]) fs.writeFileSync(path.join(OUT, k + ".png"), Buffer.from(out[k].split(",")[1], "base64"));
  fs.writeFileSync(path.join(OUT, "layout.json"), JSON.stringify({ ball: BALL, ballCols: 8, ballR: BALL * .44, terrainIcon0: 27, crown: 39,
    tile: TILE, frames: FRAMES, top: TOP, period: PERIOD }, null, 1));
  console.log("ok, Archivo Black loaded:", out.fontOk);
} finally { await browser.close(); server.close(); }
