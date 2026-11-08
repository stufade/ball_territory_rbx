--!strict
-- Things that live after a power: smiley clones, SIX/SEVEN and sound rings, bombs, bubbles.
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local React = require("./React")
local Types = require("./Types")

type State = Types.State
type Mask = Types.Mask

local P, DT = Config.P, Config.DT
local r2, disc, count = Grid.r2, Grid.disc, Grid.count
local own, capture, clearCell, lockedAt, hardAt, ballsIn, hit, gain, ev =
	Core.own, Core.capture, Core.clearCell, Core.lockedAt, Core.hardAt, Core.ballsIn, Core.hit, Core.gain, Core.ev
local min, max = math.min, math.max

local Specials = {}

function Specials.cloneStep(S: State)
	if #S.clones == 0 then
		return
	end
	local paintNow = S.tick % 6 == 0
	local kept = {}
	for _, c in S.clones do
		local b = S.by[c.e]
		if S.t < c.untilT and b and b.alive then
			table.insert(kept, c)
		end
	end
	S.clones = kept
	for _, c in kept do
		c.x += c.dx * P.cloneSpeed * DT
		c.y += c.dy * P.cloneSpeed * DT
		if c.x < S.ax0 + 0.6 or c.x > S.ax1 - 0.6 then
			c.dx = -c.dx
			c.x = min(S.ax1 - 0.6, max(S.ax0 + 0.6, c.x))
		end
		if c.y < S.ay0 + 0.6 or c.y > S.ay1 - 0.6 then
			c.dy = -c.dy
			c.y = min(S.ay1 - 0.6, max(S.ay0 + 0.6, c.y))
		end
		if not paintNow then
			continue
		end
		local d = disc(S, c.x, c.y, P.cloneR)
		local n = 0
		for k = 1, S.N do
			if d[k] and S.owner[k] ~= c.e and not hardAt(S, k) and S.bush[k] <= 0 then
				own(S, k, c.e)
				n += 1
			end
		end
		if n > 0 then
			gain(S, S.by[c.e], n * 0.3)
		end
	end
end

function Specials.sixStep(S: State)
	if #S.six == 0 then
		return
	end
	local left = {}
	for _, w in S.six do
		if S.t < w.t then
			table.insert(left, w)
			continue
		end
		local b = S.by[w.e]
		if not b then
			continue
		end
		local m = Grid.ringMask(S, w.x, w.y, w.r)
		local take: Mask = table.create(S.N, false)
		for k = 1, S.N do
			take[k] = m[k] and not hardAt(S, k)
		end
		capture(S, take, w.e)
		ev(S, "six", { x = r2(w.x), y = r2(w.y), r = w.r, word = w.word, e = w.e })
		for _, t in ballsIn(S, m, b) do
			Core.point(t, w.x, w.y, true)
			local push = w.push
			if push then
				local dd = Grid.hypot(t.x - w.x, t.y - w.y)
				if dd == 0 then
					dd = 1
				end
				Core.shove(S, t, (t.x - w.x) / dd, (t.y - w.y) / dd, push)
			end
			local stun = w.stun
			if stun then
				t.stun = max(t.stun, stun)
			end
			hit(S, t, w.dmg or P.sixDmg, b)
		end
	end
	S.six = left
end

function Specials.bombStep(S: State)
	if #S.bombs == 0 then
		return
	end
	local kept = {}
	for _, q in S.bombs do
		if S.t < q.t then
			table.insert(kept, q)
			continue
		end
		local b = S.by[q.e]
		if not b then
			continue
		end
		local d = disc(S, q.x, q.y, P.bombR)
		local take: Mask = table.create(S.N, false)
		for k = 1, S.N do
			take[k] = d[k] and not lockedAt(S, k)
		end
		local got = capture(S, take, q.e)
		for k = 1, S.N do
			if got[k] then
				clearCell(S, k, true, false)
			end
		end
		local gas: Mask = table.create(S.N, false)
		local ng, g0 = 0, -1
		for k = 1, S.N do
			if d[k] and S.gas[k] > 0 then
				gas[k] = true
				ng += 1
				if g0 < 0 then
					g0 = k
				end
			end
		end
		if ng >= 3 then
			React.react(S, b, "EXPLOSION", "gas", g0, gas)
		end
		ev(S, "kaboom", { x = r2(q.x), y = r2(q.y) })
		for _, t in ballsIn(S, d, b) do
			Core.point(t, q.x, q.y, true)
			hit(S, t, P.bombDmg, b)
		end
		gain(S, b, count(S, got) // 2)
	end
	S.bombs = kept
end

function Specials.bubbleStep(S: State)
	if #S.bubbles == 0 then
		return
	end
	local kept = {}
	for _, q in S.bubbles do
		local b = S.by[q.e]
		if not b then
			continue
		end
		q.x += q.dx * P.bubbleSpeed * DT
		q.y += q.dy * P.bubbleSpeed * DT
		if q.x < S.ax0 + 0.5 or q.x > S.ax1 - 0.5 then
			q.dx = -q.dx
		end
		if q.y < S.ay0 + 0.5 or q.y > S.ay1 - 0.5 then
			q.dy = -q.dy
		end
		local t
		for _, o in S.balls do
			if o ~= b and o.alive and o.invuln <= 0 and Grid.hypot(o.x - q.x, o.y - q.y) < 1.2 then
				t = o
				break
			end
		end
		if not t and S.t < q.untilT then
			table.insert(kept, q)
			continue
		end
		local d = disc(S, q.x, q.y, if t then 2.2 else 1.9)
		local take: Mask = table.create(S.N, false)
		for k = 1, S.N do
			take[k] = d[k] and not hardAt(S, k)
		end
		capture(S, take, q.e)
		if t then
			t.stun = max(t.stun, 1.5)
			hit(S, t, 6, b)
		end
		ev(S, "pop", { x = r2(q.x), y = r2(q.y), trap = if t then t.e else -1 })
	end
	S.bubbles = kept
end

return Specials
