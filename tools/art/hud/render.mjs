// Renders icons.html (own SVG art) to PNGs: node tools/art/hud/render.mjs -> assets/art/hud/<id>.png
import fs from "node:fs"; import path from "node:path"; import { createRequire } from "node:module"; import { fileURLToPath } from "node:url";
const HERE = path.dirname(fileURLToPath(import.meta.url)), ROOT = path.resolve(HERE, "../../..");
const require = createRequire(path.resolve(ROOT, "../ball_territory_web/package.json"));
const puppeteer = require("puppeteer-core");
const OUT = path.join(ROOT, "assets/art/hud"); fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true });
const p = await b.newPage(); await p.setViewport({ width: 256, height: 2000 });
await p.setContent(fs.readFileSync(path.join(HERE, "icons.html"), "utf8"));
for (const id of ["daily", "quests", "book", "shop", "coins"]) {
  const el = await p.$("#" + id); await el.screenshot({ path: path.join(OUT, id + ".png"), omitBackground: true }); console.log(id);
}
await b.close();
