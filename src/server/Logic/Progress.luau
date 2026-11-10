--!strict
-- Profile data of T2.2, pure (runs in lune, tests/profile): schema and migration, the tutorial reward, XP and levels,
-- level balls, the 2x XP boost. Numbers come in as `cfg` (src/server/Config.luau), time as os.time() seconds.
local Progress = {}

Progress.VERSION = 1

export type Data = {
	-- schema version
	v: number,
	-- tutorial cartoon finished once
	tut: boolean,
	-- the tutorial reward (4 starters, the spin, the boost) was given
	rewarded: boolean,
	-- the first real match was searched (the PLAY glow is off for good)
	played: boolean,
	-- owned balls (element ids), in the order they came
	balls: { number },
	level: number,
	-- XP inside the current level
	xp: number,
	-- 2x XP until this os.time() second (0 = none)
	boostUntil: number,
	-- lifetime counters
	matches: number,
	wins: number,
}

export type Cfg = {
	TIERS: { [string]: { number } },
	BASE_BALLS: { number },
	SPIN_POOL: { number },
	XP: {
		play: number,
		win: number,
		react: number,
		reactMax: number,
		ko: number,
		koMax: number,
		base: number,
		step: number,
		boost: number,
		boostTime: number,
	},
	LEVEL_BALLS: number,
	LEVEL_TIERS: { string },
}

export type Stats = { win: boolean, kills: number, rx: number }
export type LevelUp = { level: number, e: number? }
export type Gain = { xp: number, base: number, mult: number, ups: { LevelUp } }

local NEL = 27

function Progress.new(): Data
	return {
		v = Progress.VERSION,
		tut = false,
		rewarded = false,
		played = false,
		balls = {},
		level = 1,
		xp = 0,
		boostUntil = 0,
		matches = 0,
		wins = 0,
	}
end

local function int(v: any, lo: number, hi: number, def: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return def
	end
	return math.clamp(math.floor(v), lo, hi)
end

-- Any stored value (nil, an older schema, junk) -> a valid Data of the current schema. Unknown keys are dropped,
-- a newer schema than this server knows is read field by field (what it understands is kept).
function Progress.migrate(raw: any): Data
	local d = Progress.new()
	if type(raw) ~= "table" then
		return d
	end
	local v = int(raw.v, 0, 1e6, 0)
	-- v0 (before T2.2 nothing was saved; kept for hand-made records): {done = bool, owned = {e}}
	if v == 0 then
		raw = {
			tut = raw.done == true or raw.tut == true,
			balls = raw.owned or raw.balls,
			level = raw.level,
			xp = raw.xp,
		}
	end
	d.tut = raw.tut == true
	d.rewarded = raw.rewarded == true or (v == 0 and d.tut)
	d.played = raw.played == true
	local seen = {}
	if type(raw.balls) == "table" then
		for _, e in raw.balls do
			local x = int(e, -1, NEL - 1, -1)
			if x >= 0 and x == e and not seen[x] then
				seen[x] = true
				table.insert(d.balls, x)
			end
		end
	end
	d.level = int(raw.level, 1, 1000, 1)
	d.xp = int(raw.xp, 0, 1e9, 0)
	d.boostUntil = int(raw.boostUntil, 0, 2 ^ 40, 0)
	d.matches = int(raw.matches, 0, 1e9, 0)
	d.wins = int(raw.wins, 0, 1e9, 0)
	return d
end

-- A finished tutorial always comes with the starters (a v0 record, a hand-edited one).
function Progress.repair(d: Data, cfg: Cfg)
	if d.tut then
		for _, e in cfg.BASE_BALLS do
			if not table.find(d.balls, e) then
				table.insert(d.balls, e)
			end
		end
	end
end

function Progress.owns(d: Data, e: number): boolean
	return table.find(d.balls, e) ~= nil
end

local function give(d: Data, e: number): boolean
	if Progress.owns(d, e) then
		return false
	end
	table.insert(d.balls, e)
	return true
end

-- XP from `level` to the next one.
function Progress.need(level: number, cfg: Cfg): number
	return cfg.XP.base + cfg.XP.step * (math.max(1, level) - 1)
end

function Progress.boostLeft(d: Data, now: number): number
	return math.max(0, d.boostUntil - now)
end

function Progress.mult(d: Data, now: number, cfg: Cfg): number
	return if Progress.boostLeft(d, now) > 0 then cfg.XP.boost else 1
end

-- Base XP of one match (before the boost).
function Progress.matchXp(s: Stats, cfg: Cfg): number
	local x = cfg.XP
	local rx = math.min(x.reactMax, math.max(0, s.rx) * x.react)
	local ko = math.min(x.koMax, math.max(0, s.kills) * x.ko)
	return x.play + (if s.win then x.win else 0) + rx + ko
end

-- Balls a level may give: tiers of cfg.LEVEL_TIERS, not owned yet.
function Progress.levelPool(d: Data, cfg: Cfg): { number }
	local out = {}
	for _, tier in cfg.LEVEL_TIERS do
		local list: { number } = cfg.TIERS[tier] or {}
		for _, e in list do
			if not Progress.owns(d, e) then
				table.insert(out, e)
			end
		end
	end
	table.sort(out)
	return out
end

-- Adds XP (already multiplied), levels up as far as it reaches. Levels 2..LEVEL_BALLS give a random ball of the pool.
function Progress.addXp(d: Data, amount: number, cfg: Cfg, rand: () -> number): { LevelUp }
	local ups = {}
	d.xp += math.max(0, math.floor(amount))
	while d.xp >= Progress.need(d.level, cfg) do
		d.xp -= Progress.need(d.level, cfg)
		d.level += 1
		local up: LevelUp = { level = d.level, e = nil }
		if d.level <= cfg.LEVEL_BALLS then
			local pool = Progress.levelPool(d, cfg)
			if #pool > 0 then
				local e = pool[math.floor(rand() * #pool) + 1]
				give(d, e)
				up.e = e
			end
		end
		table.insert(ups, up)
	end
	return ups
end

-- A match is over for this person: counters, XP times the boost, level ups.
function Progress.award(d: Data, s: Stats, now: number, cfg: Cfg, rand: () -> number): Gain
	d.matches += 1
	if s.win then
		d.wins += 1
	end
	local base = Progress.matchXp(s, cfg)
	local mult = Progress.mult(d, now, cfg)
	local xp = base * mult
	return { xp = xp, base = base, mult = mult, ups = Progress.addXp(d, xp, cfg, rand) }
end

-- The free spin of the tutorial: one of SPIN_POOL, each equally likely, and only a ball not owned yet when possible.
-- Decided here before the client spins; the strip only shows it.
function Progress.spin(d: Data, cfg: Cfg, rand: () -> number): number
	local pool = {}
	for _, e in cfg.SPIN_POOL do
		if not Progress.owns(d, e) then
			table.insert(pool, e)
		end
	end
	if #pool == 0 then
		pool = cfg.SPIN_POOL
	end
	return pool[math.floor(rand() * #pool) + 1]
end

export type Reward = { balls: { number }, legend: number, boost: number }

-- The tutorial reward, once per profile: the 4 starters, a legendary of the spin, the boost. nil when given before.
function Progress.tutorialReward(d: Data, now: number, cfg: Cfg, rand: () -> number): Reward?
	d.tut = true
	if d.rewarded then
		return nil
	end
	d.rewarded = true
	for _, e in cfg.BASE_BALLS do
		give(d, e)
	end
	local legend = Progress.spin(d, cfg, rand)
	give(d, legend)
	d.boostUntil = math.max(d.boostUntil, now) + cfg.XP.boostTime
	return { balls = table.clone(cfg.BASE_BALLS), legend = legend, boost = cfg.XP.boostTime }
end

return Progress
