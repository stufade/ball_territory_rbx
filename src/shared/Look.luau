--!strict
-- Web palette and text style, one to one with ball_territory_web/public/index.html (RGB, COL, LIGHT, DARK, BRIGHT,
-- NAMECOL, PATTERN, RXCOL, BIG, FONT). Element tables are indexed by element id + 1.
local Look = {}

-- stylua: ignore start
local RGB = { { 255, 84, 44 }, { 64, 186, 255 }, { 46, 208, 104 }, { 255, 208, 40 }, { 26, 84, 230 }, { 150, 96, 52 }, { 128, 236, 200 },
	{ 156, 60, 226 }, { 150, 162, 184 }, { 255, 248, 214 }, { 226, 160, 70 }, { 206, 24, 58 }, { 255, 96, 196 }, { 22, 12, 34 }, { 0, 186, 170 },
	{ 176, 224, 48 }, { 255, 226, 40 }, { 255, 140, 0 }, { 150, 170, 40 }, { 230, 30, 150 }, { 200, 200, 200 }, { 80, 70, 200 }, { 200, 190, 255 },
	{ 80, 105, 55 }, { 120, 230, 240 }, { 255, 43, 214 }, { 255, 51, 85 } }
-- stylua: ignore end
local VOID, EARTH = 13, 5

local function rgb(c: { number }, k: number?): Color3
	local m = k or 1
	return Color3.fromRGB(math.floor(c[1] * m), math.floor(c[2] * m), math.floor(c[3] * m))
end
local function mix(c: { number }, d: { number }, k: number): Color3
	return Color3.fromRGB(
		math.floor(c[1] + (d[1] - c[1]) * k),
		math.floor(c[2] + (d[2] - c[2]) * k),
		math.floor(c[3] + (d[3] - c[3]) * k)
	)
end

Look.RGB = RGB
Look.COL = {} :: { Color3 }
Look.LIGHT = {} :: { Color3 }
Look.DARK = {} :: { Color3 }
for i, c in RGB do
	Look.COL[i] = rgb(c)
	Look.LIGHT[i] = mix(c, { 255, 255, 255 }, 0.5)
	Look.DARK[i] = mix(c, { 0, 0, 0 }, 0.55)
end
Look.LIGHT[VOID + 1] = Color3.fromHex("#c496ff")
Look.DARK[VOID + 1] = Color3.fromHex("#783cdc")
Look.NAMECOL = table.clone(Look.COL)
Look.NAMECOL[VOID + 1] = Color3.fromHex("#b078ff")
Look.NAMECOL[EARTH + 1] = Color3.fromHex("#d29660")
Look.BRIGHT = table.clone(Look.COL)
Look.BRIGHT[VOID + 1] = Color3.fromHex("#9650ff")

-- Two-colour checker territory of yin yang, glitch, candy (by element id).
Look.PATTERN = {
	[20] = { { 242, 242, 242 }, { 38, 38, 38 } },
	[25] = { { 255, 43, 214 }, { 43, 240, 255 } },
	[26] = { { 255, 51, 85 }, { 255, 255, 255 } },
} :: { [number]: { { number } } }

Look.BG = Color3.fromHex("#11132a")
Look.PANEL = Color3.fromHex("#1f2244")
Look.FRAME = Color3.fromHex("#f0f0fc")
Look.INK = Color3.fromHex("#0e0a22")
Look.OUT = Color3.fromHex("#101228")

-- Reaction word colours.
local RX: { [string]: string } = {
	WILDFIRE = "#ff781e",
	STEAM = "#ebf5ff",
	CHAIN = "#96d7ff",
	BLOOM = "#78ff96",
	SHATTER = "#bef0ff",
	BLAST = "#ffe15a",
	FROST = "#aaebff",
	OASIS = "#96ff78",
	OBSIDIAN = "#be8cff",
	QUICKSAND = "#f0c878",
	MUDSLIDE = "#c88c50",
	AVALANCHE = "#e6f5ff",
	FIRESTORM = "#ff8c28",
	["TOXIC STORM"] = "#c86eff",
	SANDSTORM = "#ffd68c",
	BLIGHT = "#be5aff",
	["TOXIC TIDE"] = "#aaff5a",
	FORGE = "#ffbe5a",
	GLASS = "#c8faff",
	["SLIME FLOOD"] = "#ff78d2",
	ACID = "#beff3c",
	DEVOUR = "#be78ff",
	PURIFY = "#ffffc8",
	BOOM = "#ffaa3c",
	PRISM = "#ffffff",
	GEODE = "#78ffeb",
	MYCELIUM = "#d2ff6e",
	SWAMP = "#96dc5a",
	REFLECTION = "#fff08c",
	MIRROR = "#e6ffff",
	DUNK = "#ffa028",
	SPLASH = "#8cc8ff",
	EXPLOSION = "#ffb43c",
	CRACK = "#c8faff",
	HARMONY = "#f0f0f0",
	HOURGLASS = "#ffd68c",
	["FREEZE FRAME"] = "#aab4ff",
	HAUNT = "#d2c8ff",
	DETONATE = "#ff8c3c",
	FOAM = "#c8f5ff",
	CORRUPT = "#ff2bd6",
	SYRUP = "#ff7896",
}
Look.RXCOL = {} :: { [string]: Color3 }
for k, v in RX do
	Look.RXCOL[k] = Color3.fromHex(v)
end
Look.BIG = {} :: { [string]: boolean }
for _, k in
	{
		"WILDFIRE",
		"CHAIN",
		"SHATTER",
		"BLAST",
		"BOOM",
		"DEVOUR",
		"FIRESTORM",
		"AVALANCHE",
		"PRISM",
		"GEODE",
		"DUNK",
		"MIRROR",
		"EXPLOSION",
		"DETONATE",
		"FREEZE FRAME",
	}
do
	Look.BIG[k] = true
end

-- Archivo Black of the web: Montserrat Heavy is the closest wide heavy face in Roblox.
Look.FONT = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy)
Look.BOLD = Font.new("rbxasset://fonts/families/Arimo.json", Enum.FontWeight.Bold)

-- Power button plate (design px of the 960x540 UI canvas); the match camera keeps a right column this wide free.
Look.POWER_W = 300
Look.POWER_H = 112
Look.POWER_PAD = 14

function Look.col(e: number): Color3
	return Look.COL[e + 1] or Color3.new(1, 1, 1)
end
function Look.bright(e: number): Color3
	return Look.BRIGHT[e + 1] or Color3.new(1, 1, 1)
end
function Look.light(e: number): Color3
	return Look.LIGHT[e + 1] or Color3.new(1, 1, 1)
end
function Look.dark(e: number): Color3
	return Look.DARK[e + 1] or Color3.new(0.2, 0.2, 0.2)
end

-- Territory colour of cell (i, j) owned by e, as drawCell: checker shade or the two-colour pattern.
function Look.cell(e: number, chk: number): Color3
	local p = Look.PATTERN[e]
	if p then
		return rgb(p[chk + 1])
	end
	return rgb(RGB[e + 1] or { 150, 150, 150 }, if chk == 1 then 0.86 else 0.94)
end

return Look
