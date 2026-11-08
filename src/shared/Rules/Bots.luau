--!strict
-- Bots: where to aim and when to press the power; the press itself is shared with players.
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local Powers = require("./Powers")
local Types = require("./Types")

type State = Types.State
type Ball = Types.Ball

local C, P, TOUCH = Config, Config.P, Config.TOUCH
local cos, sin, pi = math.cos, math.sin, math.pi

local Bots = {}

-- Elements whose power is worth more with rivals nearby.
local NEAR = {
	[C.METAL] = true,
	[C.WIND] = true,
	[C.VOID] = true,
	[C.SUN] = true,
	[C.CRYSTAL] = true,
	[C.SIX7] = true,
	[C.SOUND] = true,
	[C.TIME] = true,
	[C.BOMB] = true,
	[C.BUBBLE] = true,
}

local function likes(S: State, e: number): { number }
	local w = table.create(S.N, 0)
	for _, pair in TOUCH[e] do
		local L = S.L[pair[1]]
		for k = 1, S.N do
			if L[k] > 0 then
				w[k] += 3
			end
		end
	end
	return w
end

-- Turn the ball along the best of 16 directions: its reaction terrain and neutral land.
function Bots.aim(S: State, b: Ball)
	local w = likes(S, b.e)
	local owner, inA = S.owner, S.inA
	for k = 1, S.N do
		if owner[k] == -1 and inA[k] then
			w[k] += 1
		end
	end
	local best, ba = -1e9, 0
	local base = Core.rnd(S, pi * 2)
	local nbr = S.nbr
	local line: { number } = table.create(S.N, 0)
	for i = 0, 15 do
		local a = base + i * pi / 8
		local out = Grid.rayCells(S, b.x, b.y, b.x + cos(a), b.y + sin(a))
		-- grow(rayMask) without full-field passes: mark cells with this direction's stamp
		local lo, hi = S.N, 1
		for _, k in out do
			line[k] = i + 1
			if k < lo then
				lo = k
			end
			if k > hi then
				hi = k
			end
			for _, q in nbr[k] do
				line[q] = i + 1
				if q < lo then
					lo = q
				end
				if q > hi then
					hi = q
				end
			end
		end
		local s = Core.rnd(S, 3)
		for k = lo, hi do
			if line[k] == i + 1 then
				s += w[k]
			end
		end
		if s > best then
			best, ba = s, a
		end
	end
	b.dx, b.dy = cos(ba), sin(ba)
end

local function value(S: State, b: Ball): number
	local counts = S.counts
	local top
	for _, e in S.players do
		if e ~= b.e and (top == nil or counts[e] > counts[top]) then
			top = e
		end
	end
	local area, w = Powers.areaOf(S, b), likes(S, b.e)
	local owner, me = S.owner, b.e
	local v, n = 0, 0
	for k = 1, S.N do
		if not area[k] then
			continue
		end
		n += 1
		local o = owner[k]
		local rival = if o >= 0 and o ~= me then 1 else 0
		local lead = if o == top then 0.6 else 0
		local free = if o == -1 then 0.7 else 0
		local mine = if o == me then 0.4 else 0
		v += w[k] + rival + lead + free - mine
	end
	if NEAR[me] then
		v += 6 * #Core.ballsIn(S, Grid.disc(S, b.x, b.y, 6.5), b)
	end
	return v / (0.5 * n + 4)
end

function Bots.press(S: State, b: Ball)
	if not b.alive or b.charge < 1 then
		return
	end
	b.readyT = 0
	b.charge = 0
	if b.ctl then
		Core.ev(S, "tap", { e = b.e })
	end
	Powers.power(S, b)
end

-- Bot with a full charge presses when the power would pay off, sooner the longer it waits.
function Bots.decide(S: State, b: Ball)
	if S.tick % 6 ~= 0 then
		return
	end
	local wait = if b.powers > 0 then P.patience else P.patience * 0.3
	if value(S, b) >= 1 - b.readyT / wait then
		Bots.press(S, b)
	end
end

return Bots
