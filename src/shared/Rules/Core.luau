--!strict
-- Shared cell and ball helpers: ownership, capture, damage, knock-outs, respawn.
local Config = require("./Config")
local Grid = require("./Grid")
local Types = require("./Types")

type State = Types.State
type Ball = Types.Ball
type Mask = Types.Mask

local P = Config.P
local NEL = Config.NEL
local r2, f32, disc = Grid.r2, Grid.f32, Grid.disc
local floor, min, max, cos, sin, abs = math.floor, math.min, math.max, math.cos, math.sin, math.abs

local Core = {}

function Core.rnd(S: State, a: number): number
	return S.rand() * a
end
function Core.rndr(S: State, a: number, b: number): number
	return a + S.rand() * (b - a)
end
function Core.irnd(S: State, a: number, b: number): number
	return a + floor(S.rand() * (b - a + 1))
end
function Core.pick<T>(S: State, a: { T }): T
	return a[floor(S.rand() * #a) + 1]
end
function Core.shuffle<T>(S: State, a: { T }): { T }
	for i = #a - 1, 1, -1 do
		local j = Core.irnd(S, 0, i)
		a[i + 1], a[j + 1] = a[j + 1], a[i + 1]
	end
	return a
end

function Core.ev(S: State, kind: string, d: { [string]: any }?)
	S.evId += 1
	table.insert(S.events, { id = S.evId, kind = kind, d = d or {} })
end

function Core.cellOf(S: State, b: { x: number, y: number }): number
	local W, H = S.W, S.H
	local y = b.y // 1
	local x = b.x // 1
	return min(H - 1, max(0, y)) * W + min(W - 1, max(0, x)) + 1
end

function Core.hardAt(S: State, k: number): boolean
	return S.ice[k] > 0
		or S.rock[k] > 0
		or S.glass[k] > 0
		or S.water[k] > 0
		or S.shock[k] > 0
		or S.toxic[k] > 0
		or S.lava[k] > 0
		or S.burn[k] > 0
		or S.slime[k] > 0
		or S.gas[k] > 0
end

function Core.lockedAt(S: State, k: number): boolean
	return S.rock[k] > 0 or S.glass[k] > 0
end

function Core.clampX(S: State, x: number): number
	return min(S.ax1 - P.ballR, max(S.ax0 + P.ballR, x))
end
function Core.clampY(S: State, y: number): number
	return min(S.ay1 - P.ballR, max(S.ay0 + P.ballR, y))
end

function Core.own(S: State, k: number, e: number)
	if not S.inA[k] then
		return
	end
	if S.owner[k] ~= e then
		S.owner[k] = e
		S.flash[k] = 1
	end
	S.fade[k] = 0
end

local LAYERS = Config.LAYERS
-- keepLocked keeps rock and glass, keepBush keeps bush.
function Core.clearCell(S: State, k: number, keepLocked: boolean, keepBush: boolean)
	local L = S.L
	for _, n in LAYERS do
		if keepLocked and (n == "rock" or n == "glass") then
			continue
		end
		if keepBush and n == "bush" then
			continue
		end
		L[n][k] = 0
	end
	S.burnFlam[k] = false
end

function Core.put(S: State, name: string, m: Mask, t: number, by: number)
	local a, inA, src = S.L[name], S.inA, S.src
	local v = f32(t)
	for k = 1, S.N do
		if m[k] and inA[k] then
			a[k] = v
			src[k] = by
		end
	end
end

function Core.capture(S: State, m: Mask, e: number, clear: boolean?): Mask
	local doClear = clear ~= false
	local got: Mask = table.create(S.N, false)
	local lockedAt, clearCell, own = Core.lockedAt, Core.clearCell, Core.own
	for k = 1, S.N do
		if not m[k] or lockedAt(S, k) then
			continue
		end
		if doClear then
			clearCell(S, k, true, true)
			if S.owner[k] ~= e then
				S.bush[k] = 0
			end
		end
		own(S, k, e)
		got[k] = true
	end
	return got
end

function Core.ballsIn(S: State, m: Mask, b: Ball?): { Ball }
	local out = {}
	for _, t in S.balls do
		if t ~= b and t.alive and m[Core.cellOf(S, t)] then
			table.insert(out, t)
		end
	end
	return out
end

-- Ball stands on a layer someone else made.
function Core.at(S: State, b: Ball, layer: { number }): boolean
	local c = Core.cellOf(S, b)
	return layer[c] > 0 and S.src[c] ~= b.e
end

function Core.turn(b: Ball, a: number)
	local c, s = cos(a), sin(a)
	b.dx, b.dy = b.dx * c - b.dy * s, b.dx * s + b.dy * c
	if abs(b.dx) < 0.22 then
		b.dx = (if b.dx < 0 then -1 else 1) * 0.3
	end
	if abs(b.dy) < 0.22 then
		b.dy = (if b.dy < 0 then -1 else 1) * 0.3
	end
	local n = Grid.hypot(b.dx, b.dy)
	b.dx /= n
	b.dy /= n
end

function Core.point(b: Ball, x: number, y: number, away: boolean?)
	local dx, dy = x - b.x, y - b.y
	if away then
		dx, dy = -dx, -dy
	end
	local n = Grid.hypot(dx, dy)
	if n == 0 then
		n = 1
	end
	b.dx = dx / n
	b.dy = dy / n
	Core.turn(b, 0)
end

function Core.shove(S: State, t: Ball, ux: number, uy: number, d: number)
	t.x = Core.clampX(S, t.x + ux * d)
	t.y = Core.clampY(S, t.y + uy * d)
end

function Core.steer(b: Ball, dx: number, dy: number)
	local n = Grid.hypot(dx, dy)
	if n > 0.3 then
		b.dx = dx / n
		b.dy = dy / n
		Core.turn(b, 0)
	end
end

function Core.ahead(S: State, b: Ball, d: number): (number, number)
	return Core.clampX(S, b.x + b.dx * d), Core.clampY(S, b.y + b.dy * d)
end

-- Power charge from n painted cells; the ball with the least land charges faster (comeback).
function Core.gain(S: State, b: Ball, n: number)
	local lo, hi = math.huge, 1
	for _, e in S.players do
		local c = S.counts[e]
		if c < lo then
			lo = c
		end
		if c > hi then
			hi = c
		end
	end
	local mine = S.counts[b.e]
	local lag = if mine == lo then 1 - mine / hi else 0
	local was = b.charge
	b.charge = min(1, b.charge + n / P.chargeCells * S.pace[b.e] * (1 + P.behindCharge * lag))
	if b.ctl and was < 1 and b.charge >= 1 then
		Core.ev(S, "ready", { e = b.e })
	end
end

function Core.hit(S: State, t: Ball, dmg: number, by: Ball?, quiet: boolean?, x: number?, y: number?)
	if not t.alive then
		return
	end
	t.hp -= dmg
	if not quiet then
		Core.ev(S, "hit", { x = r2(x or t.x), y = r2(y or t.y) })
	end
	if t.hp > 0 then
		return
	end
	t.alive = false
	t.respawn = 3
	t.surge, t.erupt, t.hole = 0, 0, 0
	Core.ev(S, "ko", { e = t.e, x = r2(t.x), y = r2(t.y) })
	if by and by ~= t then
		by.kills += 1
		by.charge = min(1, by.charge + P.killCharge)
		if by.alive then
			by.hp = min(100, by.hp + P.stealHeal)
		end
		local d = disc(S, t.x, t.y, P.stealR)
		local n = 0
		for k = 1, S.N do
			if d[k] and S.owner[k] == t.e and not Core.lockedAt(S, k) then
				Core.own(S, k, by.e)
				n += 1
			end
		end
		Core.ev(S, "steal", { e = by.e, v = t.e, x = r2(t.x), y = r2(t.y), n = n })
	end
end

function Core.revive(S: State, b: Ball)
	local opts = {}
	for k = 1, S.N do
		if S.owner[k] == b.e and not Core.hardAt(S, k) then
			table.insert(opts, k)
		end
	end
	local k
	if #opts > 0 then
		k = Core.pick(S, opts)
	else
		local j = Core.irnd(S, S.ay0 + 2, S.ay1 - 3)
		k = j * S.W + Core.irnd(S, S.ax0 + 2, S.ax1 - 3) + 1
	end
	b.x = Core.clampX(S, S.cxs[k] + 0.5)
	b.y = Core.clampY(S, S.cys[k] + 0.5)
	b.px, b.py = b.x, b.y
	b.hp = 100
	b.alive = true
	b.invuln = 1
	local a = Core.rnd(S, math.pi * 2)
	b.dx, b.dy = cos(a), sin(a)
	Core.turn(b, 0)
	Core.ev(S, "spawn", { e = b.e, x = r2(b.x), y = r2(b.y) })
end

function Core.spawnClones(S: State, b: Ball, x: number, y: number, n: number)
	local a0 = math.atan2(b.dy, b.dx)
	for i = 0, n - 1 do
		local a = a0 + i * math.pi * 2 / max(3, n) + Core.rndr(S, -0.3, 0.3)
		table.insert(
			S.clones,
			{ x = Core.clampX(S, x), y = Core.clampY(S, y), dx = cos(a), dy = sin(a), untilT = S.t + P.cloneT, e = b.e }
		)
	end
end

function Core.newHitCd(): { [number]: number }
	local t = {}
	for i = 0, NEL - 1 do
		t[i] = 0
	end
	return t
end

return Core
