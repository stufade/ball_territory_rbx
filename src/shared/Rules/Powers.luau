--!strict
-- The 27 element powers and the area each one covers (bots read the area to judge a press).
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local React = require("./React")
local Types = require("./Types")

type State = Types.State
type Ball = Types.Ball
type Mask = Types.Mask

local C, P = Config, Config.P
local r2, disc, grow, center, rayMask, rayCells, rays, ringMask =
	Grid.r2, Grid.disc, Grid.grow, Grid.center, Grid.rayMask, Grid.rayCells, Grid.rays, Grid.ringMask
local capture, put, lockedAt, hardAt, ballsIn, hit, ev, own, ahead =
	Core.capture, Core.put, Core.lockedAt, Core.hardAt, Core.ballsIn, Core.hit, Core.ev, Core.own, Core.ahead
local cos, sin, atan2, max, min, pi = math.cos, math.sin, math.atan2, math.max, math.min, math.pi

local Powers = {}

local function filter(S: State, m: Mask, f: (number) -> boolean): Mask
	local out: Mask = table.create(S.N, false)
	for k = 1, S.N do
		out[k] = m[k] and f(k)
	end
	return out
end

function Powers.areaOf(S: State, b: Ball): Mask
	local e, x, y = b.e, b.x, b.y
	if e == C.FIRE then
		return disc(S, x, y, P.fireR)
	elseif e == C.ICE then
		return disc(S, x, y, P.freezeR)
	elseif e == C.PLANT then
		return disc(S, x, y, 4)
	elseif e == C.BOLT or e == C.WATER then
		local l = grow(S, rayMask(S, x, y, x + b.dx, y + b.dy))
		return if e == C.WATER then grow(S, grow(S, l)) else l
	elseif e == C.EARTH then
		return disc(S, x, y, P.quakeR + 0.6)
	elseif e == C.WIND then
		local d, near, h = disc(S, x, y, P.gustR), disc(S, x, y, 1.5), atan2(b.dy, b.dx)
		local cxs, cys = S.cxs, S.cys
		local m: Mask = table.create(S.N, false)
		for k = 1, S.N do
			m[k] = near[k]
				or (
					d[k]
					and math.abs(math.fmod(atan2(cys[k] + 0.5 - y, cxs[k] + 0.5 - x) - h + pi * 3, pi * 2) - pi)
						<= P.gustCone
				)
		end
		return m
	elseif e == C.POISON then
		return disc(S, x, y, P.toxinR)
	elseif e == C.METAL then
		return disc(S, x, y, 3.8)
	elseif e == C.SUN then
		return (rays(S, x, y, 8, P.flashLen, pi / 8))
	elseif e == C.SAND then
		return disc(S, x, y, P.sandR)
	elseif e == C.LAVA then
		return disc(S, x, y, P.eruptReach)
	elseif e == C.SLIME then
		local ax, ay = ahead(S, b, 3.5)
		return disc(S, ax, ay, 3.6)
	elseif e == C.CRYSTAL then
		return (rays(S, x, y, P.crystalN, P.crystalLen, atan2(b.dy, b.dx)))
	elseif e == C.MUSHROOM then
		return disc(S, x, y, 4.2)
	elseif e == C.SMILEY then
		return disc(S, x, y, 4)
	elseif e == C.SIX7 then
		local a, c = ringMask(S, x, y, P.sixR), ringMask(S, x, y, P.sevenR)
		for k = 1, S.N do
			a[k] = a[k] or c[k]
		end
		return a
	elseif e == C.GAS or e == C.BUBBLE then
		return disc(S, x, y, P.gasR)
	elseif e == C.SOUND then
		return disc(S, x, y, 5)
	elseif e == C.GLITCH then
		return disc(S, x, y, 6)
	elseif e == C.YINYANG then
		return disc(S, x, y, P.balanceR)
	elseif e == C.TIME then
		return disc(S, x, y, 2.5)
	elseif e == C.GHOST or e == C.CANDY then
		local ax, ay = ahead(S, b, 3)
		return disc(S, ax, ay, 3.5)
	elseif e == C.BOMB then
		return disc(S, x, y, P.bombR)
	end
	return disc(S, x, y, P.holeR)
end

local function strike(S: State, b: Ball)
	local out, ex, ey = rayCells(S, b.x, b.y, b.x + b.dx, b.y + b.dy)
	local line: Mask = table.create(S.N, false)
	for _, k in out do
		line[k] = true
	end
	local wide = grow(S, line)
	ev(S, "strike", { x0 = r2(b.x), y0 = r2(b.y), x1 = r2(ex), y1 = r2(ey) })
	local shockT = Grid.f32(P.shockT)
	for k = 1, S.N do
		if wide[k] and not hardAt(S, k) then
			own(S, k, b.e)
			S.bush[k] = 0
			S.shock[k] = shockT
			S.fade[k] = -(P.shockT + 1.5)
		end
	end
	for _, t in ballsIn(S, wide, b) do
		hit(S, t, P.strikeDmg, b)
	end
end

-- Players other than e sorted by land, most first; ties keep seat order (stable like Array.sort).
local function rivalsByLand(S: State, e: number): { number }
	local others = {}
	for _, q in S.players do
		if q ~= e then
			local i = #others + 1
			while i > 1 and S.counts[others[i - 1]] < S.counts[q] do
				others[i] = others[i - 1]
				i -= 1
			end
			others[i] = q
		end
	end
	return others
end

local function waterPower(S: State, b: Ball, area: Mask)
	local x, y = b.x, b.y
	local _, ex, ey = rayCells(S, x, y, x + b.dx, y + b.dy)
	ev(S, "wave", { x0 = r2(x), y0 = r2(y), x1 = r2(ex), y1 = r2(ey) })
	local got, track = capture(S, area, b.e), rayMask(S, x, y, x + b.dx, y + b.dy)
	local wet: Mask = table.create(S.N, false)
	for k = 1, S.N do
		wet[k] = got[k] and track[k]
	end
	put(S, "water", wet, P.waterT, b.e)
	for _, t in ballsIn(S, area, b) do
		Core.shove(S, t, b.dx, b.dy, 2.5)
		hit(S, t, P.waveDmg, b)
	end
end

local function earthPower(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	ev(S, "quake", { x = r2(x), y = r2(y) })
	local d, inner = disc(S, x, y, P.quakeR + 0.6), disc(S, x, y, P.quakeR - 0.6)
	capture(S, d, e)
	put(
		S,
		"rock",
		filter(S, d, function(k)
			return not inner[k] and not lockedAt(S, k)
		end),
		P.rockT,
		e
	)
	for _, t in ballsIn(S, disc(S, x, y, P.quakeR + 1), b) do
		Core.point(t, x, y, true)
		hit(S, t, P.quakeDmg, b)
	end
end

local function windPower(S: State, b: Ball, area: Mask)
	local e, x, y = b.e, b.x, b.y
	ev(S, "gust", { x = r2(x), y = r2(y), dx = r2(b.dx), dy = r2(b.dy) })
	capture(
		S,
		filter(S, area, function(k)
			return not hardAt(S, k)
		end),
		e
	)
	for _, t in ballsIn(S, disc(S, x, y, P.gustR), b) do
		local ux, uy = t.x - x, t.y - y
		local n = Grid.hypot(ux, uy)
		if n == 0 then
			n = 1
		end
		Core.shove(S, t, ux / n, uy / n, 3)
		Core.point(t, x, y, true)
		t.stun = max(t.stun, 0.5)
	end
end

local function metalPower(S: State, b: Ball, area: Mask)
	local x, y = b.x, b.y
	ev(S, "magnet", { x = r2(x), y = r2(y) })
	capture(S, area, b.e)
	b.bigT = max(b.bigT, 5)
	for _, t in ballsIn(S, disc(S, x, y, P.magnetPull), b) do
		Core.point(t, x, y)
		local d = Grid.hypot(t.x - x, t.y - y)
		if d == 0 then
			d = 1
		end
		Core.shove(S, t, (x - t.x) / d, (y - t.y) / d, min(2, d - 1.8))
	end
end

local function sunPower(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	local m, ends = rays(S, x, y, 8, P.flashLen, pi / 8)
	ev(S, "flash", { x = r2(x), y = r2(y), ends = ends })
	capture(
		S,
		filter(S, m, function(k)
			return not hardAt(S, k)
		end),
		e
	)
	for k = 1, S.N do
		if m[k] and S.owner[k] == e then
			S.shock[k] = 1
		end
	end
	for _, t in ballsIn(S, disc(S, x, y, P.flashLen), b) do
		t.stun = max(t.stun, P.flashStun)
	end
end

local function slimePower(S: State, b: Ball)
	local cx, cy = ahead(S, b, 3.5)
	local spots = {}
	for i = 0, P.splatN - 1 do
		local a = Core.rnd(S, pi * 2)
		local r = if i > 0 then Core.rnd(S, 2.6) else 0
		local sx, sy = Core.clampX(S, cx + cos(a) * r), Core.clampY(S, cy + sin(a) * r)
		local d = disc(S, sx, sy, P.splatR)
		put(
			S,
			"slime",
			capture(
				S,
				filter(S, d, function(k)
					return not lockedAt(S, k)
				end),
				b.e
			),
			P.slimeT,
			b.e
		)
		table.insert(spots, { r2(sx), r2(sy) })
	end
	ev(S, "splat", { spots = spots })
end

local function crystalPower(S: State, b: Ball)
	local x, y = b.x, b.y
	local m, ends = rays(S, x, y, P.crystalN, P.crystalLen, atan2(b.dy, b.dx))
	local near = disc(S, x, y, 1.2)
	local got = capture(
		S,
		filter(S, m, function(k)
			return not lockedAt(S, k) and not near[k]
		end),
		b.e
	)
	put(S, "glass", got, P.crystalT, b.e)
	ev(S, "crystal", { x = r2(x), y = r2(y), ends = ends })
	for _, t in ballsIn(S, got, b) do
		hit(S, t, P.crystalDmg, b)
	end
end

local function mushroomPower(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	local spots = {}
	for i = 0, P.sporeN - 1 do
		local a = i * pi * 2 / P.sporeN + Core.rndr(S, -0.3, 0.3)
		local r = Core.rndr(S, 2.4, 3.9)
		local sx, sy = Core.clampX(S, x + cos(a) * r), Core.clampY(S, y + sin(a) * r)
		table.insert(spots, { r2(sx), r2(sy) })
		table.insert(S.pods, { x = sx, y = sy, t = S.t + P.sporeDelay + i * 0.08, e = e })
	end
	capture(S, disc(S, x, y, 1.5), e)
	ev(S, "spores", { spots = spots })
end

local function yinYangPower(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	local others = rivalsByLand(S, e)
	local target = if S.counts[e] >= S.counts[others[1]] then others[2] else others[1]
	local d = disc(S, x, y, P.balanceR)
	capture(
		S,
		filter(S, d, function(k)
			return S.owner[k] == target and not lockedAt(S, k)
		end),
		e,
		false
	)
	capture(S, disc(S, x, y, 2.2), e)
	b.hp = min(100, b.hp + 30)
	ev(S, "balance", { x = r2(x), y = r2(y), target = target })
end

local function glitchPower(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	local lab = rivalsByLand(S, e)[1]
	local theirs: Mask = table.create(S.N, false)
	local any = false
	for k = 1, S.N do
		if S.owner[k] == lab then
			theirs[k] = true
			any = true
		end
	end
	local cx, cy = x, y
	if any then
		cx, cy = center(S, theirs)
	end
	b.x, b.y = Core.clampX(S, cx), Core.clampY(S, cy)
	b.px, b.py = b.x, b.y
	local d = disc(S, b.x, b.y, 6)
	local cand = {}
	for k = 1, S.N do
		if d[k] and S.owner[k] >= 0 and S.owner[k] ~= e and not lockedAt(S, k) then
			table.insert(cand, k)
		end
	end
	Core.shuffle(S, cand)
	local take: Mask = table.create(S.N, false)
	for i = 1, min(#cand, P.glitchN) do
		take[cand[i]] = true
	end
	capture(S, take, e)
	ev(S, "glitch", { x0 = r2(x), y0 = r2(y), x = r2(b.x), y = r2(b.y) })
end

function Powers.power(S: State, b: Ball)
	local e, x, y = b.e, b.x, b.y
	local area = Powers.areaOf(S, b)
	b.powers += 1
	ev(S, "power", { e = e, x = r2(x), y = r2(y) })
	React.trigger(S, b, area, true)
	if e == C.FIRE then
		React.ignite(S, area, e)
	elseif e == C.ICE then
		put(S, "ice", capture(S, area, e), P.freezeT, e)
	elseif e == C.PLANT then
		capture(S, disc(S, x, y, 1.7), e)
		b.surge = P.surgeT
		b.sx, b.sy = x, y
	elseif e == C.BOLT then
		strike(S, b)
	elseif e == C.WATER then
		waterPower(S, b, area)
	elseif e == C.EARTH then
		earthPower(S, b)
	elseif e == C.WIND then
		windPower(S, b, area)
	elseif e == C.POISON then
		put(S, "toxic", capture(S, area, e), P.toxinT, e)
	elseif e == C.METAL then
		metalPower(S, b, area)
	elseif e == C.SUN then
		sunPower(S, b)
	elseif e == C.SAND then
		put(S, "sand", capture(S, area, e), P.sandT, e)
	elseif e == C.LAVA then
		put(S, "lava", capture(S, disc(S, x, y, P.eruptR), e), P.lavaT, e)
		b.erupt = P.eruptT
		b.ex, b.ey = x, y
	elseif e == C.SLIME then
		slimePower(S, b)
	elseif e == C.CRYSTAL then
		crystalPower(S, b)
	elseif e == C.MUSHROOM then
		mushroomPower(S, b)
	elseif e == C.SMILEY then
		capture(S, disc(S, x, y, 1.5), e)
		Core.spawnClones(S, b, x, y, P.cloneN)
		ev(S, "itsme", { x = r2(x), y = r2(y) })
	elseif e == C.SIX7 then
		table.insert(S.six, { x = x, y = y, t = S.t, r = P.sixR, e = e, word = "SIX" })
		table.insert(S.six, { x = x, y = y, t = S.t + P.sevenDelay, r = P.sevenR, e = e, word = "SEVEN" })
	elseif e == C.GAS then
		put(
			S,
			"gas",
			capture(
				S,
				filter(S, area, function(k)
					return not lockedAt(S, k)
				end),
				e
			),
			P.gasT,
			e
		)
		ev(S, "gas", { x = r2(x), y = r2(y) })
	elseif e == C.SOUND then
		for i, r in P.soundRings do
			table.insert(S.six, {
				x = x,
				y = y,
				t = S.t + (i - 1) * 0.2,
				r = r,
				e = e,
				word = "",
				push = P.soundPush,
				dmg = P.soundDmg,
				stun = 0.6,
			})
		end
		ev(S, "sonic", { x = r2(x), y = r2(y) })
	elseif e == C.YINYANG then
		yinYangPower(S, b)
	elseif e == C.TIME then
		capture(S, disc(S, x, y, 2.5), e)
		for _, t in S.balls do
			if t ~= b then
				t.slowT = P.slowT
			end
		end
		b.hasteT = P.slowT
		ev(S, "slowtime", { x = r2(x), y = r2(y) })
	elseif e == C.GHOST then
		b.phaseT = P.phaseT
		ev(S, "phase", { e = e, x = r2(x), y = r2(y) })
	elseif e == C.BOMB then
		table.insert(S.bombs, { x = x, y = y, t = S.t + P.bombT, e = e })
		ev(S, "bomb", { x = r2(x), y = r2(y) })
	elseif e == C.BUBBLE then
		local a0 = Core.rnd(S, pi * 2)
		for i = 0, P.bubbleN - 1 do
			local a = a0 + i * pi * 2 / P.bubbleN
			table.insert(S.bubbles, { x = x, y = y, dx = cos(a), dy = sin(a), untilT = S.t + P.bubbleT, e = e })
		end
		ev(S, "bubbles", { x = r2(x), y = r2(y) })
	elseif e == C.GLITCH then
		glitchPower(S, b)
	elseif e == C.CANDY then
		b.rushT = P.rushT
		ev(S, "rush", { e = e, x = r2(x), y = r2(y) })
	else
		b.hole = P.holeT
		b.hx, b.hy = x, y
		ev(S, "hole", { x = r2(x), y = r2(y) })
	end
end

return Powers
