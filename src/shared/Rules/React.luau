--!strict
-- Named reactions: a ball touches a terrain layer and the connected patch becomes its land.
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local Types = require("./Types")

type State = Types.State
type Ball = Types.Ball
type Mask = Types.Mask

local P, TOUCH, CONV, CDS = Config.P, Config.TOUCH, Config.CONV, Config.CDS
local PLANT = Config.PLANT
local r2, f32 = Grid.r2, Grid.f32
local disc, grow, dilate, count, center, component =
	Grid.disc, Grid.grow, Grid.dilate, Grid.count, Grid.center, Grid.component
local own, capture, put, clearCell, lockedAt, hardAt, ballsIn, hit, gain, ev =
	Core.own,
	Core.capture,
	Core.put,
	Core.clearCell,
	Core.lockedAt,
	Core.hardAt,
	Core.ballsIn,
	Core.hit,
	Core.gain,
	Core.ev

local React = {}

-- A reaction counts for the match; drawing and sound come from the event.
function React.reaction(S: State, k: string, x: number, y: number, by: number, layer: string, extra: { [string]: any }?)
	S.reactions += 1
	S.rxCount[k] = (S.rxCount[k] or 0) + 1
	if not S.seen[k] then
		S.seen[k] = true
		if not S.final then
			S.slow = 0.2
		end
	end
	local d: { [string]: any } = { k = k, x = r2(x), y = r2(y), by = by, layer = layer }
	if extra then
		for key, v in extra do
			d[key] = v
		end
	end
	ev(S, "rx", d)
end
local reaction = React.reaction

-- Patch of `layer` not made by ball e.
local function patchOf(S: State, layer: { number }, e: number): Mask
	local m: Mask = table.create(S.N, false)
	local src = S.src
	for k = 1, S.N do
		if layer[k] > 0 and src[k] ~= e then
			m[k] = true
		end
	end
	return m
end

function React.ignite(S: State, m: Mask, by: number)
	local water, ice, bush, burn, owner, src, burnFlam = S.water, S.ice, S.bush, S.burn, S.owner, S.src, S.burnFlam
	local plant = S.by[PLANT] ~= nil
	local burnT = f32(P.burnT)
	for k = 1, S.N do
		if not m[k] or water[k] > 0 or ice[k] > 0 or lockedAt(S, k) or owner[k] == by then
			continue
		end
		burnFlam[k] = bush[k] > 0 or (plant and owner[k] == PLANT)
		burn[k] = burnT
		src[k] = by
	end
end

function React.accumulate(S: State, kind: string, m: Mask, n: number, by: number)
	local a = S.acc[kind]
	a.n += n
	a.idle = 0
	a.x, a.y = center(S, m)
	a.by = by
	if not a.fired and a.n >= (if kind == "WILDFIRE" then P.wildMin else 4) then
		a.fired = true
		if kind ~= "WILDFIRE" or S.t >= S.wildNext then
			S.wildNext = S.t + P.wildGap
			reaction(S, kind, a.x, a.y, by, if kind == "BLOOM" then "water" else "bush")
		end
	end
end

function React.flushAcc(S: State, kind: string)
	local a = S.acc[kind]
	if a.idle > 0.5 then
		a.n = 0
		a.fired = false
	end
end

local function chain(S: State, k0: number, b: Ball): number
	local m = component(S, patchOf(S, S.water, b.e), k0)
	local n = count(S, m)
	if n < 3 then
		return 0
	end
	S.cd.CHAIN = CDS.CHAIN
	local cx, cy = center(S, m)
	local pts = {}
	for k = 1, S.N do
		if m[k] then
			S.water[k] = 0
			own(S, k, b.e)
			if #pts < 14 and S.rand() < 14 / n then
				table.insert(pts, { S.cxs[k] + 0.5, S.cys[k] + 0.5 })
			end
		end
	end
	reaction(S, "CHAIN", cx, cy, b.e, "water", { pts = Core.shuffle(S, pts) })
	for _, t in ballsIn(S, m, b) do
		t.stun = 0.9
		hit(S, t, P.chainDmg, b)
	end
	return n
end

local function shatter(S: State, k0: number, b: Ball): number
	local m = component(S, patchOf(S, S.ice, b.e), k0)
	local n = count(S, m)
	if n < 3 then
		return 0
	end
	S.cd.SHATTER = CDS.SHATTER
	local d = dilate(S, m)
	local ring: Mask = table.create(S.N, false)
	for k = 1, S.N do
		ring[k] = d[k] and not m[k]
	end
	local cx, cy = center(S, m)
	for k = 1, S.N do
		if m[k] then
			S.ice[k] = 0
		end
	end
	local take: Mask = table.create(S.N, false)
	for k = 1, S.N do
		take[k] = ring[k] or (m[k] and S.rand() < 0.75)
	end
	capture(S, take, b.e)
	reaction(S, "SHATTER", cx, cy, b.e, "ice")
	for _, t in ballsIn(S, ring, b) do
		hit(S, t, P.shardDmg, b)
	end
	return n
end

local function blast(S: State, x: number, y: number, b: Ball)
	S.cd.BLAST = CDS.BLAST
	local d = disc(S, x, y, P.blastR)
	for k = 1, S.N do
		if d[k] then
			S.burn[k] = 0
		end
	end
	capture(S, d, b.e)
	reaction(S, "BLAST", x, y, b.e, "burn")
	for _, t in S.balls do
		if t ~= b and t.alive and Grid.hypot(t.x - x, t.y - y) <= P.blastR + 1 then
			Core.point(t, x, y, true)
			hit(S, t, P.blastDmg, b)
		end
	end
end

local function prism(S: State, m: Mask, b: Ball, layer: string): number
	local cx, cy = center(S, m)
	local beams, ends = Grid.rays(S, cx, cy, 8, 9)
	local take: Mask = table.create(S.N, false)
	for k = 1, S.N do
		take[k] = (beams[k] and not hardAt(S, k)) or m[k]
	end
	local got = capture(S, take, b.e, false)
	for k = 1, S.N do
		if beams[k] and not hardAt(S, k) then
			S.shock[k] = 1
		end
	end
	reaction(S, "PRISM", cx, cy, b.e, layer, { ends = ends })
	for _, t in ballsIn(S, beams, b) do
		hit(S, t, 20, b)
	end
	return count(S, got)
end

local function convert(S: State, b: Ball, rx: string, layer: string, m: Mask): number
	local c = CONV[rx]
	local to, rings = c.to, c.rings
	local cx, cy = center(S, m)
	local ring = table.clone(m)
	for _ = 1, rings do
		ring = grow(S, ring)
	end
	local spread = to == "burn" or to == "toxic" or to == "sand"
	local L = S.L[layer]
	for k = 1, S.N do
		ring[k] = ring[k] and not m[k] and not lockedAt(S, k) and not (spread and (S.water[k] > 0 or S.ice[k] > 0))
		if m[k] then
			L[k] = 0
			if layer == "burn" then
				S.burnFlam[k] = false
			end
			own(S, k, b.e)
		end
	end
	local clear = rx == "DEVOUR" or rx == "PURIFY" or rx == "BOOM"
	local taken = capture(S, ring, b.e, clear)
	local both: Mask = table.create(S.N, false)
	for k = 1, S.N do
		both[k] = m[k] or taken[k]
	end
	if to == "burn" then
		put(S, "burn", both, c.t, b.e)
	elseif to then
		put(S, to, if rings > 0 and to ~= "bush" then both else m, c.t, b.e)
	end
	if clear then
		for k = 1, S.N do
			if m[k] then
				clearCell(S, k, true, false)
			end
		end
	end
	reaction(S, rx, cx, cy, b.e, layer)
	if rx == "REFLECTION" then
		Core.spawnClones(S, b, cx, cy, 1)
	end
	if rx == "MIRROR" then
		Core.spawnClones(S, b, cx, cy, 2)
	end
	local hitm = if rx == "BOOM" then disc(S, cx, cy, 3.5) else both
	for _, v in ballsIn(S, hitm, b) do
		if c.stun > 0 then
			v.stun = math.max(v.stun, c.stun)
		end
		if c.dmg > 0 then
			hit(S, v, c.dmg, b)
		end
		if rx == "BOOM" then
			Core.point(v, cx, cy, true)
		end
	end
	return count(S, m) + count(S, taken)
end

function React.react(S: State, b: Ball, rx: string, layer: string, k0: number, touched: Mask): number
	if rx == "WILDFIRE" then
		React.ignite(S, touched, b.e)
		return 0
	end
	if (S.cd[rx] or 0) > 0 then
		return 0
	end
	if rx == "CHAIN" then
		return chain(S, k0, b)
	end
	if rx == "SHATTER" then
		return shatter(S, k0, b)
	end
	if rx == "BLAST" then
		blast(S, S.cxs[k0] + 0.5, S.cys[k0] + 0.5, b)
		return 6
	end
	local m = component(S, patchOf(S, S.L[layer], b.e), k0)
	local n = count(S, m)
	if n < P.minRx then
		return 0
	end
	S.cd[rx] = if CDS[rx] ~= nil then CDS[rx] else P.cd
	if rx == "PRISM" then
		return prism(S, m, b, layer)
	end
	return convert(S, b, rx, layer, m)
end

-- Ball meets its reaction layers inside `area`.
function React.trigger(S: State, b: Ball, area: Mask, skipWild: boolean)
	local n = 0
	local src, burn = S.src, S.burn
	for _, pair in TOUCH[b.e] do
		local layer, rx = pair[1], pair[2]
		if skipWild and rx == "WILDFIRE" then
			continue
		end
		local L = S.L[layer]
		local isBush = layer == "bush"
		local m: Mask = table.create(S.N, false)
		local k0 = -1
		for k = 1, S.N do
			if area[k] and L[k] > 0 and src[k] ~= b.e and not (isBush and burn[k] > 0) then
				m[k] = true
				if k0 < 0 then
					k0 = k
				end
			end
		end
		if k0 >= 0 then
			n += React.react(S, b, rx, layer, k0, m)
		end
	end
	if n ~= 0 then
		gain(S, b, n)
	end
end

function React.touch(S: State, b: Ball)
	React.trigger(S, b, disc(S, b.x, b.y, P.touchR), false)
end

return React
