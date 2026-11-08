--!strict
-- Per-element tables are 0-based on purpose ({[0] = ...}), so mixed tables are expected here.
--# selene: allow(mixed_table)
-- Numbers and tables of the rules. Element ids are 0-based like in the web build:
-- per-element tables use `{[0] = first, second, ...}`.
local Config = {}

Config.DT = 1 / 30
Config.ROUND = 60
Config.FOREVER = 9999
Config.NEL = 27
Config.DUEL_ROUND = 30
Config.DUEL_SIZE = 3

-- Element ids.
Config.FIRE = 0
Config.ICE = 1
Config.PLANT = 2
Config.BOLT = 3
Config.WATER = 4
Config.EARTH = 5
Config.WIND = 6
Config.POISON = 7
Config.METAL = 8
Config.SUN = 9
Config.SAND = 10
Config.LAVA = 11
Config.SLIME = 12
Config.VOID = 13
Config.CRYSTAL = 14
Config.MUSHROOM = 15
Config.SMILEY = 16
Config.SIX7 = 17
Config.GAS = 18
Config.SOUND = 19
Config.YINYANG = 20
Config.TIME = 21
Config.GHOST = 22
Config.BOMB = 23
Config.BUBBLE = 24
Config.GLITCH = 25
Config.CANDY = 26

-- stylua: ignore start
Config.TITLE = { [0] = "FIRE", "ICE", "PLANT", "LIGHTNING", "WATER", "EARTH", "WIND", "POISON", "METAL", "LIGHT", "SAND", "LAVA",
	"SLIME", "VOID", "CRYSTAL", "MUSHROOM", "SMILEY", "67", "GAS", "SOUND", "YIN YANG", "TIME", "GHOST", "BOMB", "BUBBLE", "GLITCH", "CANDY" }
Config.WORD = { [0] = "IGNITE", "FREEZE", "GROW", "STRIKE", "WAVE", "QUAKE", "GUST", "TOXIN", "MAGNET", "FLASH", "SANDSTORM", "ERUPT",
	"SPLAT", "BLACK HOLE", "CRYSTALLIZE", "SPORES", "IT'S ME", "SIX SEVEN", "GAS CLOUD", "SONIC BOOM", "BALANCE", "SLOW TIME", "PHASE",
	"TICK TOCK", "BUBBLES", "TELEPORT", "SUGAR RUSH" }
Config.ABOUT = { [0] =
	"Burns the area around your ball.", "Freezes the area around your ball.", "Your zone spreads fast for a moment.",
	"Hits in a line ahead of your ball.", "A wave floods the line ahead.", "A ring of rock and a ground slam.",
	"Blows rivals away, takes a cone.", "A toxic cloud that creeps and hurts.", "Pulls rivals into your blades.",
	"Eight beams and a blinding flash.", "Sand that slows rivals down.", "A lava pool that creeps and burns.",
	"Sticky blobs that trap rivals.", "A black hole that eats the map.", "Eight crystal rays nobody can repaint.",
	"Spores that sprout into bushes.", "Three smiley clones run off and paint.",
	"Two shockwaves: SIX, then SEVEN.", "A cloud that slows rivals. Fire makes it explode.",
	"Three sound rings knock rivals back.", "Steals the leader's land around you.", "Rivals slow down, you speed up.",
	"Fly through anything and paint rivals' land.", "A bomb that blows up after 1.5 s.", "Bubbles drift out and trap rivals.",
	"Jump into the biggest rival zone and corrupt it.", "A sugar rush: faster and wider paint.",
}

-- Charge speed of each element's power (1 = normal), tuned by tests/tune.luau.
-- WEB_* are the values of the 20x24 web build, kept for the parity test.
Config.WEB_PACE = { [0] = 0.45,2.2,0.46,0.89,0.88,0.87,1.88,2.18,1.24,0.66,1.42,0.61,1.46,2.09,1,1.67,0.75,0.6,1.35,0.77,1.28,1,0.62,1,0.58,0.89,1.35 }
Config.WEB_DUEL_PACE = { [0] = 0.79,1.65,0.46,1.51,1.54,0.68,3,0.68,1.25,0.88,0.93,0.39,1.09,2.09,1.33,0.94,1.01,0.78,1.72,1.32,0.72,1.74,0.65,0.95,0.58,1.24,1.82 }
Config.PACE = { [0] = 0.35,3,0.53,0.73,0.88,1.02,1.91,2.63,1.34,0.51,1.92,0.61,1.71,1.83,1.14,1.43,0.64,0.6,1.83,0.62,1.34,1,0.55,1,0.57,0.89,1.8 }
Config.DUEL_PACE = { [0] = 0.79,2.06,0.35,1.23,2.08,0.54,3.73,0.68,1.25,0.72,1.53,0.39,1.32,2.09,1.33,1.17,1.01,0.78,2.14,1.14,0.57,1.12,0.65,0.81,0.49,1.24,2.21 }

-- Who beats whom (element ids): 4-player share of meetings finished higher, and duel rounds won.
-- Recomputed for the turned field by tests/balance.luau and tests/duel.luau.
Config.STRONG = { [0] = {15,18,7},{4,16,17},{15,10,4},{18,1,4},{10,11,0},{1,11,22},{7,10,0},{15,16,5},{1,0,11},{1,7,14},{15,26,18},{15,10,2},{7,3,4},{12,2,26},{10,1,3},{13,26,19},{14,0,11},{5,4,23},{19,13,9},{14,1,9},{0,4,13},{10,1,22},{12,7,3},{11,25,3},{0,4,13},{14,5,10},{17,19,0} }
Config.WEAK = { [0] = {26,20,8},{5,9,14},{11,7,20},{26,12,23},{17,26,20},{17,25,14},{12,23,2},{12,22,0},{6,17,12},{19,18,5},{14,21,2},{5,23,4},{22,13,21},{18,20,15},{19,16,25},{2,7,11},{7,18,1},{26,1,9},{3,0,10},{18,26,5},{23,12},{6,23,19},{5,10,21},{17,7},{18,10,20},{23,18,26},{10,15,13} }
Config.DSTRONG = { [0] = {7,10,15},{4,16,26},{10,15,4},{18,1,0},{21,0,11},{1,11,22},{10,7,0},{15,21,16},{11,0,1},{1,7,14},{8,3,22},{15,10,2},{7,4,24},{12,11,21},{1,10,3},{26,16,25},{14,21,0},{5,21,6},{19,21,6},{14,1},{4,0,21},{10,1},{12,7,26},{18,11},{4,6,21},{14,5,11},{4,25,20} }
Config.DWEAK = { [0] = {4,8,20},{5,14,21},{0,1,11},{10,14,7},{1,26,20},{17,25,10},{4,1,11},{0,12,9},{10,4,15},{10,4,11},{2,0,6},{23,5,4},{22,13,1},{1,10,9},{19,25,16},{11,0,2},{15,1,7},{15,1,7},{3,23,0},{4,15,7},{15,1,7},{4,7,15},{10,5,1},{10,1,7},{1,10,15},{15,10,26},{15,1,10} }
-- stylua: ignore end

Config.LAYERS = { "water", "ice", "bush", "burn", "toxic", "sand", "lava", "slime", "rock", "glass", "shock", "gas" }
Config.TOP = { "shock", "burn", "gas", "lava", "toxic", "slime", "water", "ice", "glass", "rock", "sand", "bush" }

-- Layer a ball touches -> reaction name, per element.
Config.TOUCH = {
	[0] = {
		{ "bush", "WILDFIRE" },
		{ "ice", "STEAM" },
		{ "toxic", "BOOM" },
		{ "sand", "GLASS" },
		{ "gas", "EXPLOSION" },
	},
	{ { "water", "FROST" }, { "lava", "OBSIDIAN" }, { "burn", "STEAM" } },
	{ { "water", "BLOOM" }, { "sand", "OASIS" }, { "bush", "BLOOM" } },
	{ { "water", "CHAIN" }, { "ice", "SHATTER" }, { "burn", "BLAST" }, { "gas", "EXPLOSION" } },
	{ { "burn", "STEAM" }, { "lava", "OBSIDIAN" }, { "sand", "QUICKSAND" } },
	{ { "water", "MUDSLIDE" }, { "lava", "OBSIDIAN" }, { "ice", "AVALANCHE" } },
	{ { "burn", "FIRESTORM" }, { "toxic", "TOXIC STORM" }, { "sand", "SANDSTORM" } },
	{ { "bush", "BLIGHT" }, { "water", "TOXIC TIDE" } },
	{ { "burn", "FORGE" }, { "lava", "FORGE" }, { "ice", "SHATTER" } },
	{ { "ice", "PRISM" }, { "glass", "PRISM" }, { "toxic", "PURIFY" } },
	{ { "water", "QUICKSAND" }, { "burn", "GLASS" }, { "lava", "GLASS" } },
	{
		{ "water", "OBSIDIAN" },
		{ "ice", "STEAM" },
		{ "bush", "WILDFIRE" },
		{ "sand", "GLASS" },
		{ "gas", "EXPLOSION" },
	},
	{ { "water", "SLIME FLOOD" }, { "toxic", "ACID" } },
	{ { "water", "DEVOUR" }, { "lava", "DEVOUR" }, { "toxic", "DEVOUR" }, { "slime", "DEVOUR" } },
	{ { "water", "GEODE" }, { "ice", "GEODE" }, { "sand", "GLASS" } },
	{ { "bush", "MYCELIUM" }, { "water", "SWAMP" } },
	{ { "water", "REFLECTION" }, { "glass", "MIRROR" } },
	{ { "rock", "DUNK" }, { "water", "SPLASH" } },
	{ { "burn", "EXPLOSION" }, { "lava", "EXPLOSION" } },
	{ { "ice", "SHATTER" }, { "glass", "CRACK" } },
	{ { "water", "HARMONY" }, { "burn", "HARMONY" } },
	{ { "sand", "HOURGLASS" }, { "ice", "FREEZE FRAME" } },
	{ { "toxic", "HAUNT" }, { "slime", "HAUNT" } },
	{ { "lava", "DETONATE" }, { "gas", "EXPLOSION" } },
	{ { "water", "FOAM" } },
	{ { "glass", "CORRUPT" }, { "rock", "CORRUPT" } },
	{ { "water", "SYRUP" } },
}

export type Conv = { to: string?, t: number, rings: number, dmg: number, stun: number }
local function cv(to: string?, t: number, rings: number, dmg: number, stun: number): Conv
	return { to = to, t = t, rings = rings, dmg = dmg, stun = stun }
end
local FOREVER = Config.FOREVER
-- Reaction: a connected patch of terrain becomes yours. Turns into `to` for `t` seconds, plus `rings` around.
Config.CONV = {
	STEAM = cv("water", 7, 0, 0, 0),
	FROST = cv("ice", 8, 0, 0, 0),
	BLOOM = cv(nil, 0, 1, 0, 0),
	OASIS = cv("bush", FOREVER, 1, 0, 0),
	OBSIDIAN = cv("rock", 12, 0, 0, 0),
	QUICKSAND = cv("sand", 8, 1, 10, 1.6),
	MUDSLIDE = cv(nil, 0, 2, 14, 0.6),
	AVALANCHE = cv(nil, 0, 2, 25, 0.8),
	FIRESTORM = cv("burn", 1.6, 2, 0, 0),
	["TOXIC STORM"] = cv("toxic", 6, 2, 0, 0),
	SANDSTORM = cv("sand", 8, 2, 0, 0.5),
	BLIGHT = cv("toxic", 6, 0, 0, 0),
	["TOXIC TIDE"] = cv("toxic", 6, 0, 20, 0),
	FORGE = cv("rock", 12, 1, 0, 0),
	GLASS = cv("glass", 12, 0, 0, 0),
	["SLIME FLOOD"] = cv("slime", 9, 1, 0, 0),
	ACID = cv("slime", 9, 0, 25, 0),
	DEVOUR = cv(nil, 0, 0, 0, 0),
	PURIFY = cv(nil, 0, 1, 0, 0),
	BOOM = cv(nil, 0, 2, 35, 0),
	GEODE = cv("glass", 10, 0, 0, 0),
	MYCELIUM = cv("bush", FOREVER, 1, 0, 0),
	SWAMP = cv("bush", FOREVER, 1, 0, 1),
	REFLECTION = cv(nil, 0, 1, 0, 0),
	MIRROR = cv("glass", 8, 0, 0, 0),
	DUNK = cv(nil, 0, 2, 25, 0.6),
	SPLASH = cv(nil, 0, 1, 10, 0),
	EXPLOSION = cv(nil, 0, 2, 30, 0),
	CRACK = cv(nil, 0, 1, 10, 0),
	HARMONY = cv(nil, 0, 1, 0, 0),
	HOURGLASS = cv(nil, 0, 2, 0, 0.8),
	["FREEZE FRAME"] = cv("ice", 6, 0, 0, 2),
	HAUNT = cv(nil, 0, 1, 0, 1),
	DETONATE = cv(nil, 0, 2, 25, 0),
	FOAM = cv(nil, 0, 2, 0, 0.6),
	CORRUPT = cv(nil, 0, 1, 0, 0),
	SYRUP = cv("slime", 9, 1, 0, 0),
} :: { [string]: Conv }

-- Reaction cooldowns; others use P.cd.
Config.CDS = {
	STEAM = 6,
	FROST = 6,
	SHATTER = 6,
	CHAIN = 1.2,
	BLAST = 4,
	BLOOM = 0,
	DEVOUR = 9,
	PRISM = 5,
	FIRESTORM = 5,
	REFLECTION = 4,
	MIRROR = 5,
	EXPLOSION = 3,
} :: { [string]: number }

-- All 42 named reactions (the reaction book).
-- stylua: ignore
Config.REACTIONS = { "WILDFIRE", "STEAM", "BOOM", "GLASS", "EXPLOSION", "FROST", "OBSIDIAN", "BLOOM", "OASIS", "CHAIN", "SHATTER",
	"BLAST", "QUICKSAND", "MUDSLIDE", "AVALANCHE", "FIRESTORM", "TOXIC STORM", "SANDSTORM", "BLIGHT", "TOXIC TIDE", "FORGE", "PRISM",
	"PURIFY", "SLIME FLOOD", "ACID", "DEVOUR", "GEODE", "MYCELIUM", "SWAMP", "REFLECTION", "MIRROR", "DUNK", "SPLASH", "CRACK",
	"HARMONY", "HOURGLASS", "FREEZE FRAME", "HAUNT", "DETONATE", "FOAM", "CORRUPT", "SYRUP" }

Config.P = {
	speed = 4.6,
	ballR = 0.85,
	paintR = 1.5,
	paintEnemyR = 1,
	paintNeutral = 3,
	paintEnemy = 9,
	orbitR = 2,
	headR = 0.6,
	orbitPeriod = 1.15,
	damage = 16,
	hitCd = 0.75,
	killCharge = 0.4,
	chargeCells = 50,
	flightCells = 42,
	patience = 3,
	touchR = 1.1,
	fadeT = 3,
	behindCharge = 1.5,
	minRx = 3,
	cd = 4,
	fireR = 4.3,
	burnT = 1.5,
	fireP = 0.018,
	plantBurnP = 0.62,
	plantBurnT = 0.7,
	ashP = 0.3,
	wildMin = 6,
	wildGap = 5,
	wildCap = 26,
	freezeR = 4.6,
	freezeT = 8,
	surgeT = 1.6,
	surgeArea = 6.5,
	growNeutralP = 0.35,
	growEnemyP = 0.2,
	waterT = 9,
	strikeDmg = 30,
	shockT = 2.5,
	chainDmg = 30,
	shardDmg = 14,
	blastR = 3,
	blastDmg = 22,
	waveDmg = 22,
	quakeR = 2.8,
	quakeDmg = 30,
	rockT = 6,
	gustR = 7.5,
	gustCone = 0.62,
	toxinR = 3,
	toxinT = 5,
	toxicSpreadP = 0.015,
	toxicDps = 12,
	magnetPull = 8,
	flashLen = 6,
	flashStun = 1.2,
	sandR = 6.2,
	sandT = 8,
	eruptR = 1.8,
	eruptReach = 3.6,
	eruptT = 4,
	lavaT = 5.5,
	lavaSpreadP = 0.11,
	lavaDps = 25,
	burnDps = 8,
	splatN = 7,
	splatR = 2.1,
	slimeT = 9,
	holeT = 2.2,
	holeR = 3.4,
	holePull = 3.5,
	holeDmg = 0,
	holeTug = 0.1,
	crystalN = 8,
	crystalLen = 4.4,
	crystalT = 7,
	crystalDmg = 20,
	sporeN = 5,
	sporeR = 1.3,
	sporeDelay = 1.2,
	promptEvery = 12,
	promptLen = 2.5,
	stealR = 3.2,
	stealHeal = 40,
	finalDirCd = 0.2,
	finalBotAimLo = 1.4,
	finalBotAimHi = 2.6,
	gasR = 4,
	gasT = 5,
	soundRings = { 2.4, 4.2 },
	soundPush = 2.4,
	soundDmg = 6,
	balanceR = 6.5,
	slowT = 2.5,
	phaseT = 4.5,
	bombT = 1.5,
	bombR = 3.4,
	bombDmg = 32,
	bubbleN = 8,
	bubbleT = 3,
	bubbleSpeed = 2.6,
	glitchN = 40,
	rushT = 2,
	cloneN = 3,
	cloneT = 2.6,
	cloneSpeed = 5.2,
	cloneR = 1,
	sixR = 3.6,
	sevenR = 5.2,
	sixDmg = 18,
	sevenDelay = 0.67,
}

-- Field layouts. arena = {x0, y0, x1, y1} cells, end-exclusive. inset = start spot distance from the arena
-- edge, blob = how far map blobs stay from the field centre line (x, y). Web is portrait 20x24;
-- Roblox turns it to landscape 24x20, so x and y swap.
export type Layout = { w: number, h: number, arena: { number }?, inset: { number }, blob: { number } }
Config.LAYOUTS = {
	web = { w = 20, h = 24, inset = { 4, 5 }, blob = { 2, 1 } },
	webDuel = { w = 20, h = 24, arena = { 3, 4, 17, 20 }, inset = { 4, 5 }, blob = { 2, 1 } },
	ffa = { w = 24, h = 20, inset = { 5, 4 }, blob = { 1, 2 } },
	duel = { w = 24, h = 20, arena = { 4, 3, 20, 17 }, inset = { 5, 4 }, blob = { 1, 2 } },
} :: { [string]: Layout }

-- Bot elements avoid pairs of similar colours.
Config.CLASH = {
	{ 3, 16 },
	{ 0, 17 },
	{ 15, 18 },
	{ 18, 23 },
	{ 12, 19 },
	{ 4, 21 },
	{ 7, 21 },
	{ 1, 24 },
	{ 6, 24 },
	{ 14, 24 },
	{ 9, 22 },
	{ 2, 23 },
}

return Config
