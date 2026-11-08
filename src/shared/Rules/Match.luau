--!strict
-- Match state and the 30 Hz step: movement, collisions, painting, spikes, timers.
local Bots = require("./Bots")
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local React = require("./React")
local Rng = require("./Rng")
local Specials = require("./Specials")
local Types = require("./Types")
local World = require("./World")

type State = Types.State
type Ball = Types.Ball
type Mask = Types.Mask

local C, P, DT, NEL, FOREVER = Config, Config.P, Config.DT, Config.NEL, Config.FOREVER
local r2, f32 = Grid.r2, Grid.f32
local floor, min, max, abs, cos, sin, sqrt, pi =
	math.floor, math.min, math.max, math.abs, math.cos, math.sin, math.sqrt, math.pi
local own, hardAt, lockedAt, at, turn, ev, gain =
	Core.own, Core.hardAt, Core.lockedAt, Core.at, Core.turn, Core.ev, Core.gain

local Match = {}

export type Seat = { e: number, ctl: string? }
export type Options = {
	-- "ffa" (24x20, default), "duel" (16x14 arena), "web" (20x24), "webDuel" (14x16 arena of 20x24)
	layout: string?,
	round: number?,
	pace: { [number]: number }?,
	seed: number?,
	rand: Rng.Rand?,
}

local function newBall(S: State, e: number, x: number, y: number, ctl: string?): Ball
	local a, ang = Core.rnd(S, pi * 2), Core.rnd(S, pi * 2)
	return {
		e = e,
		x = x,
		y = y,
		px = x,
		py = y,
		dx = cos(a),
		dy = sin(a),
		hp = 100,
		alive = true,
		respawn = 0,
		invuln = 1,
		ang = ang,
		pang = ang,
		charge = 0,
		readyT = 0,
		stun = 0,
		surge = 0,
		sx = x,
		sy = y,
		erupt = 0,
		ex = x,
		ey = y,
		hole = 0,
		hx = x,
		hy = y,
		bigT = 0,
		slowT = 0,
		hasteT = 0,
		phaseT = 0,
		rushT = 0,
		hitCd = Core.newHitCd(),
		powers = 0,
		kills = 0,
		redirectAt = 0,
		finAim = 0,
		dirAt = nil,
		ctl = ctl,
		auto = false,
		prompts = true,
		name = "",
		pid = "",
	}
end

function Match.recount(S: State)
	local counts = S.counts
	for i = 0, NEL - 1 do
		counts[i] = 0
	end
	local owner = S.owner
	for k = 1, S.N do
		local o = owner[k]
		if o >= 0 then
			counts[o] += 1
		end
	end
end

-- Symmetric terrain blobs: grown in the top-left quarter, mirrored to the other three.
local function makeMap(S: State)
	local W, H, N = S.W, S.H, S.N
	local owned: Mask = table.create(N, false)
	for k = 1, N do
		owned[k] = S.owner[k] >= 0
	end
	local taken = Grid.grow(S, owned)
	local k0 = min(1, (S.area / N) ^ 0.7)
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local kinds = { "bush", "water", "ice", "sand", "lava", "bush" }
	local sizes = { 9, 6, 5, 5, 3, 4 }
	for idx, kind in kinds do
		local size0 = sizes[idx]
		local size = max(2, floor(size0 * k0 + 0.5))
		for _ = 1, 60 do
			local bx = Core.irnd(S, S.ax0 + 1, W / 2 - S.blob[1])
			local by = Core.irnd(S, S.ay0 + 1, H / 2 - S.blob[2])
			local list, has = { by * W + bx }, { [by * W + bx] = true }
			while #list < size do
				local c = Core.pick(S, list)
				local d = Core.pick(S, dirs)
				local x, y = c % W + d[1], c // W + d[2]
				if x >= S.ax0 and x < W / 2 and y >= S.ay0 and y < H / 2 then
					local q = y * W + x
					if not has[q] then
						has[q] = true
						table.insert(list, q)
					end
				end
			end
			local all = {}
			for _, c in list do
				local x, y = c % W, c // W
				all[y * W + x + 1] = true
				all[(H - 1 - y) * W + (W - 1 - x) + 1] = true
				all[y * W + (W - 1 - x) + 1] = true
				all[(H - 1 - y) * W + x + 1] = true
			end
			local clash = false
			for k in all do
				if taken[k] then
					clash = true
					break
				end
			end
			if clash then
				continue
			end
			local layer = S.L[kind]
			for k in all do
				taken[k] = true
				layer[k] = FOREVER
			end
			break
		end
	end
end

function Match.new(seats: { Seat }, opts: Options?): State
	local o: Options = opts or {}
	local layout = C.LAYOUTS[o.layout or "ffa"]
	assert(layout, "unknown layout")
	local W, H = layout.w, layout.h
	local N = W * H
	local geo = Grid.geometry(W, H)
	local round = o.round or C.ROUND
	local arena = layout.arena or { 0, 0, W, H }
	local players = {}
	for _, s in seats do
		table.insert(players, s.e)
	end
	local L: { [string]: Types.Layer } = {}
	for _, n in C.LAYERS do
		L[n] = table.create(N, 0)
	end
	local counts = {}
	for i = 0, NEL - 1 do
		counts[i] = 0
	end
	local S: State = {
		W = W,
		H = H,
		N = N,
		cxs = geo.cxs,
		cys = geo.cys,
		nbr = geo.nbr,
		rand = o.rand or Rng.new(o.seed),
		tick = 0,
		t = 0,
		owner = table.create(N, -1),
		src = table.create(N, -1),
		L = L,
		water = L.water,
		ice = L.ice,
		bush = L.bush,
		burn = L.burn,
		toxic = L.toxic,
		sand = L.sand,
		lava = L.lava,
		slime = L.slime,
		rock = L.rock,
		glass = L.glass,
		shock = L.shock,
		gas = L.gas,
		fade = table.create(N, 0),
		burnFlam = table.create(N, false),
		flash = table.create(N, 0),
		players = players,
		balls = {},
		by = {},
		counts = counts,
		acc = {
			WILDFIRE = { n = 0, idle = 0, fired = false, x = 0, y = 0, by = -1 },
			BLOOM = { n = 0, idle = 0, fired = false, x = 0, y = 0, by = -1 },
		},
		cd = {},
		wildNext = 0,
		reactions = 0,
		seen = {},
		rxCount = {},
		done = false,
		final = false,
		launched = false,
		pods = {},
		nextPrompt = P.promptEvery,
		promptUntil = -1,
		events = {},
		evId = 0,
		slow = 0,
		clones = {},
		six = {},
		bombs = {},
		bubbles = {},
		round = round,
		finalAt = round - (if round <= 30 then 10 else 15),
		pace = o.pace or C.PACE,
		ax0 = arena[1],
		ay0 = arena[2],
		ax1 = arena[3],
		ay1 = arena[4],
		inA = table.create(N, false),
		area = (arena[3] - arena[1]) * (arena[4] - arena[2]),
		blob = layout.blob,
		inset = layout.inset,
	}
	for j = S.ay0, S.ay1 - 1 do
		for i = S.ax0, S.ax1 - 1 do
			S.inA[j * W + i + 1] = true
		end
	end
	-- two balls start on a diagonal so nobody gets the better corner
	local Lx, Rx, Ty, By = S.ax0 + S.inset[1], S.ax1 - S.inset[1], S.ay0 + S.inset[2], S.ay1 - S.inset[2]
	local spots
	if #seats == 2 then
		spots = Core.shuffle(S, { { { Lx, Ty }, { Rx, By } }, { { Rx, Ty }, { Lx, By } } })[1]
	else
		spots = Core.shuffle(S, { { Lx, Ty }, { Rx, Ty }, { Lx, By }, { Rx, By } })
	end
	local start = max(0, 1 - P.flightCells / P.chargeCells)
	for i, st in seats do
		local b = newBall(S, st.e, spots[i][1], spots[i][2], st.ctl)
		b.charge = start
		table.insert(S.balls, b)
		S.by[st.e] = b
		local d = Grid.disc(S, b.x, b.y, 2.3)
		for k = 1, N do
			if d[k] then
				S.owner[k] = st.e
			end
		end
	end
	makeMap(S)
	for _, b in S.balls do
		if b.ctl then
			b.dx = W / 2 - b.x
			b.dy = H / 2 - b.y
		else
			Bots.aim(S, b)
		end
		turn(b, 0)
	end
	Match.recount(S)
	return S
end

local TIMED = {}
for _, n in C.LAYERS do
	if n ~= "bush" and n ~= "burn" then
		table.insert(TIMED, n)
	end
end

local function timers(S: State, dt: number)
	local N = S.N
	for _, n in TIMED do
		local a = S.L[n]
		for k = 1, N do
			local v = a[k]
			if v > 0 then
				a[k] = f32(max(0, v - dt))
			end
		end
	end
	for k, v in S.cd do
		S.cd[k] = v - dt
	end
	for _, b in S.balls do
		b.bigT -= dt
		b.stun -= dt
		b.surge -= dt
		b.erupt -= dt
		b.invuln -= dt
		b.slowT -= dt
		b.hasteT -= dt
		b.phaseT -= dt
		b.rushT -= dt
		if b.phaseT > 0 then
			b.invuln = max(b.invuln, 0.1)
		end
		local cd = b.hitCd
		for i = 0, NEL - 1 do
			cd[i] -= dt
		end
	end
end

local ORBIT = pi * 2 / P.orbitPeriod * DT

local function updateBall(S: State, b: Ball)
	if not b.alive then
		b.respawn -= DT
		if b.respawn <= 0 then
			Core.revive(S, b)
		end
		return
	end
	b.ang += ORBIT
	if b.charge >= 1 then
		b.readyT += DT
		if not b.ctl then
			Bots.decide(S, b)
		elseif b.auto then
			Bots.press(S, b)
		end
	end
	if S.final and not b.ctl and S.t >= b.finAim then
		b.finAim = S.t + Core.rndr(S, P.finalBotAimLo, P.finalBotAimHi)
		Bots.aim(S, b)
		turn(b, 0)
	end
	if b.redirectAt ~= 0 and S.t >= b.redirectAt then
		b.redirectAt = 0
		if S.t <= S.promptUntil then
			Bots.aim(S, b)
			turn(b, 0)
			local tx, ty = Core.ahead(S, b, 5)
			ev(S, "redirect", { e = b.e, x = r2(b.x), y = r2(b.y), tx = r2(tx), ty = r2(ty) })
		end
	end
	local e = b.e
	local sp = P.speed
	if at(S, b, S.ice) then
		sp *= 1.35
	end
	if at(S, b, S.water) and e ~= C.WATER then
		sp *= 0.75
	end
	if at(S, b, S.bush) and e ~= C.PLANT and e ~= C.MUSHROOM then
		sp *= 0.75
	end
	if at(S, b, S.sand) and e ~= C.SAND then
		sp *= 0.6
	end
	if at(S, b, S.slime) and e ~= C.SLIME then
		sp *= 0.45
	end
	if at(S, b, S.gas) and e ~= C.GAS then
		sp *= 0.6
		if S.rand() < 0.08 then
			turn(b, Core.rndr(S, -0.6, 0.6))
		end
	end
	if b.slowT > 0 then
		sp *= 0.4
	end
	if b.hasteT > 0 then
		sp *= 1.5
	end
	if b.rushT > 0 then
		sp *= 1.8
	end
	if b.stun > 0 then
		sp *= 0.2
	end
	local nx, ny, hit = b.x + b.dx * sp * DT, b.y + b.dy * sp * DT, false
	local R = P.ballR
	if nx < S.ax0 + R then
		nx = S.ax0 + R
		b.dx = abs(b.dx)
		hit = true
	elseif nx > S.ax1 - R then
		nx = S.ax1 - R
		b.dx = -abs(b.dx)
		hit = true
	end
	if ny < S.ay0 + R then
		ny = S.ay0 + R
		b.dy = abs(b.dy)
		hit = true
	elseif ny > S.ay1 - R then
		ny = S.ay1 - R
		b.dy = -abs(b.dy)
		hit = true
	end
	b.x, b.y = nx, ny
	if hit then
		turn(b, Core.rndr(S, -0.16, 0.16))
		ev(S, "wall")
	end
end

local function collide(S: State)
	local R2, bs = P.ballR * 2, S.balls
	local clampX, clampY = Core.clampX, Core.clampY
	for i = 1, #bs do
		for j = i + 1, #bs do
			local a, c = bs[i], bs[j]
			if not a.alive or not c.alive then
				continue
			end
			local dx, dy = c.x - a.x, c.y - a.y
			local d2 = dx * dx + dy * dy
			if d2 >= R2 * R2 or d2 == 0 then
				continue
			end
			local d = sqrt(d2)
			local nx, ny = dx / d, dy / d
			local push = (R2 - d) / 2
			a.x = clampX(S, a.x - nx * push)
			a.y = clampY(S, a.y - ny * push)
			c.x = clampX(S, c.x + nx * push)
			c.y = clampY(S, c.y + ny * push)
			local va, vc = a.dx * nx + a.dy * ny, c.dx * nx + c.dy * ny
			if va - vc > 0 then
				a.dx += (vc - va) * nx
				a.dy += (vc - va) * ny
				c.dx += (va - vc) * nx
				c.dy += (va - vc) * ny
				turn(a, Core.rndr(S, -0.3, 0.3))
				turn(c, Core.rndr(S, -0.3, 0.3))
				ev(S, "bump", { x = r2((a.x + c.x) / 2), y = r2((a.y + c.y) / 2) })
			end
		end
	end
end

-- Paint under the ball: neutral cells always, rival cells on enemy ticks. Ghost and candy paint rivals always.
local function paint(S: State, b: Ball, enemy: boolean)
	local ghost, rush = b.phaseT > 0, b.rushT > 0
	local x, y = b.x, b.y
	local r = if rush then 2 else P.paintR
	local re = if not (enemy or ghost or rush) then -1 elseif ghost or rush then 1.5 else P.paintEnemyR
	local q, qe = r * r, re * re
	local R = max(r, re)
	local W, owner, bush, e = S.W, S.owner, S.bush, b.e
	local plantish = e == C.PLANT or e == C.MUSHROOM
	local x0, x1 = max(S.ax0, floor(x - R - 1)), min(S.ax1 - 1, math.ceil(x + R))
	local y0, y1 = max(S.ay0, floor(y - R - 1)), min(S.ay1 - 1, math.ceil(y + R))
	local n = 0
	for j = y0, y1 do
		local dy = j + 0.5 - y
		local dy2 = dy * dy
		local row = j * W + 1
		for i = x0, x1 do
			local k = row + i
			local o = owner[k]
			local dx = i + 0.5 - x
			local d2 = dx * dx + dy2
			if not ((d2 <= q and o == -1) or (re >= 0 and d2 <= qe and o >= 0 and o ~= e)) then
				continue
			end
			if if ghost then lockedAt(S, k) else hardAt(S, k) or (not plantish and bush[k] > 0) then
				continue
			end
			own(S, k, e)
			bush[k] = 0
			n += 1
		end
	end
	if n > 0 then
		gain(S, b, n)
	end
end

local function weapon(S: State, b: Ball)
	local big = b.bigT > 0
	local reach = P.orbitR * (if big then 1.5 else 1)
	local hr = P.headR * (if big then 1.3 else 1) + P.ballR
	for _, t in S.balls do
		if t == b or not t.alive or t.invuln > 0 or b.hitCd[t.e] > 0 then
			continue
		end
		if abs(t.x - b.x) > reach + hr or abs(t.y - b.y) > reach + hr then
			continue
		end
		for i = 0, 1 do
			local a = b.ang + i * pi
			local hx, hy = b.x + cos(a) * reach, b.y + sin(a) * reach
			local ddx, ddy = hx - t.x, hy - t.y
			if ddx * ddx + ddy * ddy <= hr * hr then
				b.hitCd[t.e] = P.hitCd
				Core.hit(S, t, P.damage, b, false, hx, hy)
				break
			end
		end
	end
end

function Match.step(S: State)
	S.tick += 1
	S.t = S.tick * DT
	for _, b in S.balls do
		b.px, b.py, b.pang = b.x, b.y, b.ang
	end
	if S.tick % 3 == 0 then
		timers(S, DT * 3)
	end
	if not S.final and S.t >= S.finalAt then
		S.final = true
		S.promptUntil = -1
		ev(S, "final")
	end
	if S.t >= S.nextPrompt and S.t + P.promptLen < S.finalAt then
		S.nextPrompt += P.promptEvery
		S.promptUntil = S.t + P.promptLen
		ev(S, "prompt", { ["until"] = r2(S.promptUntil) })
		for _, b in S.balls do
			b.redirectAt = if b.ctl then 0 else S.t + Core.rndr(S, 0.5, 1.7)
		end
	end
	for _, b in S.balls do
		updateBall(S, b)
	end
	collide(S)
	if S.tick % P.paintNeutral == 0 then
		local enemy = S.tick % P.paintEnemy == 0
		for _, b in S.balls do
			if b.alive then
				React.touch(S, b)
				paint(S, b, enemy)
			end
		end
	end
	for _, b in S.balls do
		if b.alive then
			weapon(S, b)
		end
	end
	Specials.cloneStep(S)
	Specials.sixStep(S)
	Specials.bombStep(S)
	Specials.bubbleStep(S)
	if S.tick % 3 == 0 then
		World.hazardStep(S)
	end
	if S.tick % 4 == 0 then
		World.fireStep(S)
	end
	if S.tick % 6 == 0 then
		World.plantStep(S)
	end
	Match.recount(S)
	if S.tick >= S.round / DT then
		S.done = true
	end
end

return Match
