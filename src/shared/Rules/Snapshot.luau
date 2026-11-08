--!strict
-- Compact picture of a match for clients, like snapshot() in the web build.
local Config = require("./Config")
local Grid = require("./Grid")
local Types = require("./Types")

type State = Types.State

local P, TOP = Config.P, Config.TOP
local r2 = Grid.r2

local CH = {}
for i = 0, 25 do
	CH[i] = string.char(97 + i)
end
CH[26] = "{"

export type Snapshot = {
	t: number,
	rx: number,
	pu: number,
	fin: number,
	rd: number,
	fa: number,
	ar: { number },
	w: number,
	h: number,
	-- owner per cell: "." or "a" + element id; g: top layer per cell, "a" + index in Config.TOP; f: fade 0-9 or ""
	o: string,
	g: string,
	f: string,
	-- per ball: e, x, y, ang, hp, alive, charge, flags, hole, hx, hy, sx, sy, dx, dy, powers, kills, name, pid
	b: { { any } },
	c: { { number } },
	k: { { number } },
	u: { { number } },
	ev: { Types.Event },
	meta: any,
}

local Snapshot = {}

function Snapshot.take(S: State, meta: any?): Snapshot
	local N = S.N
	local o, g, f = table.create(N, "."), table.create(N, "."), table.create(N, "0")
	local anyFade = false
	local layers = {}
	for i, n in TOP do
		layers[i] = S.L[n]
	end
	for k = 1, N do
		local ow = S.owner[k]
		if ow >= 0 then
			o[k] = CH[ow]
		end
		for i = 1, #layers do
			if layers[i][k] > 0 then
				g[k] = CH[i - 1]
				break
			end
		end
		local fv = S.fade[k]
		if fv > 0 then
			local v = math.min(9, math.floor(fv / P.fadeT * 9 + 0.5))
			if v > 0 then
				anyFade = true
				f[k] = tostring(v)
			end
		end
	end
	local bs = {}
	for _, b in S.balls do
		local flags = (if b.stun > 0 then 1 else 0)
			+ (if b.bigT > 0 then 2 else 0)
			+ (if b.invuln > 0 then 4 else 0)
			+ (if b.surge > 0 then 8 else 0)
			+ (if b.phaseT > 0 then 16 else 0)
			+ (if b.rushT > 0 then 32 else 0)
			+ (if b.slowT > 0 then 64 else 0)
			+ (if b.hasteT > 0 then 128 else 0)
		local row: { any } = {
			b.e,
			r2(b.x),
			r2(b.y),
			r2(math.fmod(b.ang, math.pi * 2)),
			math.floor(b.hp + 0.5),
			if b.alive then 1 else 0,
			r2(b.charge),
			flags,
			r2(math.max(0, b.hole)),
			r2(b.hx),
			r2(b.hy),
			r2(b.sx),
			r2(b.sy),
			r2(b.dx),
			r2(b.dy),
			b.powers,
			b.kills,
			b.name,
			b.pid,
		}
		table.insert(bs, row)
	end
	local cs, ks, us = {}, {}, {}
	for _, c in S.clones do
		table.insert(cs, { r2(c.x), r2(c.y), c.e })
	end
	for _, q in S.bombs do
		table.insert(ks, { r2(q.x), r2(q.y), r2(q.t - S.t) })
	end
	for _, q in S.bubbles do
		table.insert(us, { r2(q.x), r2(q.y), q.e })
	end
	local events = S.events
	S.events = {}
	return {
		t = r2(S.t),
		rx = S.reactions,
		pu = r2(S.promptUntil),
		fin = if S.final then 1 else 0,
		rd = S.round,
		fa = S.finalAt,
		ar = { S.ax0, S.ay0, S.ax1, S.ay1 },
		w = S.W,
		h = S.H,
		o = table.concat(o),
		g = table.concat(g),
		f = if anyFade then table.concat(f) else "",
		b = bs,
		c = cs,
		k = ks,
		u = us,
		ev = events,
		meta = meta,
	}
end

return Snapshot
