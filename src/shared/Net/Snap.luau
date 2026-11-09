--!strict
-- Battle snapshot codec on `buffer`, pure (runs in lune). Layout: docs/net.md, section Snap.
-- The server keeps one Encoder per round; every packet carries all balls, a rolling slice of full cells
-- and the cells changed in the last HIST frames, so a lost packet heals by itself.
local Rules = require("../Rules")

local Config = Rules.Config
local TOP, FADE_T = Config.TOP, Config.P.fadeT

local floor, min, max, pi = math.floor, math.min, math.max, math.pi
local TAU = pi * 2

local Snap = {}

Snap.FRAME = 1
Snap.CONT = 2
Snap.KEY = 3
Snap.HEADER = 18
Snap.BALL = 26
Snap.THING = 5
-- frames a changed cell is repeated in; one lost packet is covered
Snap.HIST = 2
-- frames to send every cell once as a full value
Snap.REFRESH = 8
-- UnreliableRemoteEvent drops payloads over 1000 bytes; keep a margin.
Snap.MAX = 900

export type Encoder = {
	ep: number,
	ox: number,
	oy: number,
	w: number,
	h: number,
	n: number,
	seq: number,
	cursor: number,
	refN: number,
	prev: { number },
	hist: { { number } },
}

export type BallFrame = {
	e: number,
	x: number,
	y: number,
	ang: number,
	hp: number,
	alive: boolean,
	charge: number,
	flags: number,
	dx: number,
	dy: number,
	hole: number,
	hx: number,
	hy: number,
	sx: number,
	sy: number,
	powers: number,
	kills: number,
	cnt: number,
}

export type Frame = {
	seq: number,
	t: number,
	pu: number,
	final: boolean,
	launched: boolean,
	slow: boolean,
	rx: number,
	balls: { BallFrame },
	clones: { { number } },
	bombs: { { number } },
	bubbles: { { number } },
}

export type Decoder = {
	ep: number,
	seq: number,
	n: number,
	cells: { number },
	changed: { [number]: boolean },
}

-- Cell value: bits 0-4 owner + 1, 5-8 top layer index in Config.TOP, 9-12 fade 0-9.
function Snap.owner(v: number): number
	return bit32.band(v, 31) - 1
end
function Snap.layer(v: number): number
	return bit32.band(bit32.rshift(v, 5), 15)
end
function Snap.fade(v: number): number
	return bit32.band(bit32.rshift(v, 9), 15)
end
function Snap.layerName(v: number): string?
	local i = Snap.layer(v)
	return if i > 0 then TOP[i] else nil
end

local function u16(v: number): number
	return min(65535, max(0, floor(v * 1000 + 0.5)))
end
local function u8(v: number, scale: number): number
	return min(255, max(0, floor(v * scale + 0.5)))
end
local function i8(v: number): number
	return min(127, max(-127, floor(v * 127 + 0.5)))
end

local function cellValue(S: Rules.State, layers: { { number } }, k: number): number
	local v = S.owner[k] + 1
	for i = 1, #layers do
		if layers[i][k] > 0 then
			v += i * 32
			break
		end
	end
	local fv = S.fade[k]
	if fv > 0 then
		v += min(9, floor(fv / FADE_T * 9 + 0.5)) * 512
	end
	return v
end

local function current(enc: Encoder, S: Rules.State): { number }
	local layers = {}
	for i, name in TOP do
		layers[i] = S.L[name]
	end
	local out = table.create(enc.n, 0)
	local W, ox, oy, w = S.W, enc.ox, enc.oy, enc.w
	for c = 0, enc.n - 1 do
		local k = (oy + c // w) * W + ox + c % w + 1
		out[c + 1] = cellValue(S, layers, k)
	end
	return out
end

-- ep: match number, packets of another ep are dropped by the decoder.
function Snap.newEncoder(S: Rules.State, ep: number): Encoder
	local w, h = S.ax1 - S.ax0, S.ay1 - S.ay0
	local n = w * h
	return {
		ep = ep % 256,
		ox = S.ax0,
		oy = S.ay0,
		w = w,
		h = h,
		n = n,
		seq = 0,
		cursor = 0,
		refN = math.ceil(n / Snap.REFRESH),
		prev = table.create(n, -1),
		hist = {},
	}
end

-- Full cell picture, sent reliably with Match "start".
function Snap.keyframe(enc: Encoder, S: Rules.State): buffer
	local cur = current(enc, S)
	enc.prev = cur
	enc.hist = {}
	local b = buffer.create(6 + enc.n * 2)
	buffer.writeu8(b, 0, Snap.KEY)
	buffer.writeu8(b, 1, enc.ep)
	buffer.writeu16(b, 2, enc.seq)
	buffer.writeu16(b, 4, enc.n)
	for c = 1, enc.n do
		buffer.writeu16(b, 6 + (c - 1) * 2, cur[c])
	end
	return b
end

local function writeBall(b: buffer, o: number, S: Rules.State, ball: Rules.Ball)
	local ang = math.fmod(ball.ang, TAU)
	if ang < 0 then
		ang += TAU
	end
	local flags = (if ball.stun > 0 then 1 else 0)
		+ (if ball.bigT > 0 then 2 else 0)
		+ (if ball.invuln > 0 then 4 else 0)
		+ (if ball.surge > 0 then 8 else 0)
		+ (if ball.phaseT > 0 then 16 else 0)
		+ (if ball.rushT > 0 then 32 else 0)
		+ (if ball.slowT > 0 then 64 else 0)
		+ (if ball.hasteT > 0 then 128 else 0)
	buffer.writeu8(b, o, ball.e)
	buffer.writeu16(b, o + 1, u16(ball.x))
	buffer.writeu16(b, o + 3, u16(ball.y))
	buffer.writeu16(b, o + 5, floor(ang / TAU * 65536) % 65536)
	buffer.writeu8(b, o + 7, u8(ball.hp, 1))
	buffer.writeu8(b, o + 8, if ball.alive then 1 else 0)
	buffer.writeu8(b, o + 9, u8(min(1, ball.charge), 250))
	buffer.writeu8(b, o + 10, flags)
	-- before launch every direction is secret: the owner draws its own aim from Match "aim"
	local hide = not S.launched
	buffer.writei8(b, o + 11, if hide then 0 else i8(ball.dx))
	buffer.writei8(b, o + 12, if hide then 0 else i8(ball.dy))
	buffer.writeu8(b, o + 13, u8(ball.hole, 50))
	buffer.writeu16(b, o + 14, u16(ball.hx))
	buffer.writeu16(b, o + 16, u16(ball.hy))
	buffer.writeu16(b, o + 18, u16(ball.sx))
	buffer.writeu16(b, o + 20, u16(ball.sy))
	buffer.writeu8(b, o + 22, min(255, ball.powers))
	buffer.writeu8(b, o + 23, min(255, ball.kills))
	buffer.writeu16(b, o + 24, min(65535, S.counts[ball.e] or 0))
end

local function writeThing(b: buffer, o: number, x: number, y: number, last: number)
	buffer.writeu16(b, o, u16(x))
	buffer.writeu16(b, o + 2, u16(y))
	buffer.writeu8(b, o + 4, last)
end

-- Packets of one snapshot: a frame, then continuation packets if the deltas do not fit SNAP_MAX.
function Snap.encode(enc: Encoder, S: Rules.State): { buffer }
	enc.seq = (enc.seq + 1) % 65536
	local cur = current(enc, S)
	local changed = {}
	for c = 1, enc.n do
		if cur[c] ~= enc.prev[c] then
			table.insert(changed, c - 1)
		end
	end
	enc.prev = cur
	table.insert(enc.hist, 1, changed)
	if #enc.hist > Snap.HIST then
		table.remove(enc.hist)
	end
	local refStart, refN = enc.cursor, enc.refN
	enc.cursor = (enc.cursor + refN) % enc.n
	local function inRefresh(c: number): boolean
		return (c - refStart) % enc.n < refN
	end
	local delta, seen = {}, {}
	for _, list in enc.hist do
		for _, c in list do
			if not seen[c] and not inRefresh(c) then
				seen[c] = true
				table.insert(delta, c)
			end
		end
	end

	local nb, nc, nk, nu = #S.balls, min(255, #S.clones), min(255, #S.bombs), min(255, #S.bubbles)
	local fixed = Snap.HEADER + nb * Snap.BALL + (nc + nk + nu) * Snap.THING + 3 + refN * 2 + 2
	local room = max(0, (Snap.MAX - fixed) // 4)
	local first = min(#delta, room)
	local b = buffer.create(fixed + first * 4)
	buffer.writeu8(b, 0, Snap.FRAME)
	buffer.writeu8(b, 1, enc.ep)
	buffer.writeu16(b, 2, enc.seq)
	buffer.writeu32(b, 4, min(4294967295, max(0, floor(S.t * 1000 + 0.5))))
	buffer.writeu16(b, 8, if S.promptUntil < 0 then 0 else min(65535, floor(S.promptUntil * 100) + 1))
	buffer.writeu8(b, 10, (if S.final then 1 else 0) + (if S.launched then 2 else 0) + (if S.slow > 0 then 4 else 0))
	buffer.writeu16(b, 11, min(65535, S.reactions))
	buffer.writeu8(b, 13, nb)
	buffer.writeu8(b, 14, nc)
	buffer.writeu8(b, 15, nk)
	buffer.writeu8(b, 16, nu)
	local o = Snap.HEADER
	for _, ball in S.balls do
		writeBall(b, o, S, ball)
		o += Snap.BALL
	end
	for i = 1, nc do
		local q = S.clones[i]
		writeThing(b, o, q.x, q.y, q.e)
		o += Snap.THING
	end
	for i = 1, nk do
		local q = S.bombs[i]
		writeThing(b, o, q.x, q.y, u8(q.t - S.t, 50))
		o += Snap.THING
	end
	for i = 1, nu do
		local q = S.bubbles[i]
		writeThing(b, o, q.x, q.y, q.e)
		o += Snap.THING
	end
	buffer.writeu16(b, o, refStart)
	buffer.writeu8(b, o + 2, refN)
	o += 3
	for i = 0, refN - 1 do
		buffer.writeu16(b, o, cur[(refStart + i) % enc.n + 1])
		o += 2
	end
	buffer.writeu16(b, o, first)
	o += 2
	for i = 1, first do
		local c = delta[i]
		buffer.writeu16(b, o, c)
		buffer.writeu16(b, o + 2, cur[c + 1])
		o += 4
	end
	local out = { b }
	local per = (Snap.MAX - 6) // 4
	local i = first + 1
	while i <= #delta do
		local cnt = min(per, #delta - i + 1)
		local p = buffer.create(6 + cnt * 4)
		buffer.writeu8(p, 0, Snap.CONT)
		buffer.writeu8(p, 1, enc.ep)
		buffer.writeu16(p, 2, enc.seq)
		buffer.writeu16(p, 4, cnt)
		for j = 0, cnt - 1 do
			local c = delta[i + j]
			buffer.writeu16(p, 6 + j * 4, c)
			buffer.writeu16(p, 8 + j * 4, cur[c + 1])
		end
		table.insert(out, p)
		i += cnt
	end
	return out
end

-- Client side ---------------------------------------------------------------

function Snap.newDecoder(): Decoder
	return { ep = -1, seq = -1, n = 0, cells = {}, changed = {} }
end

local function set(dec: Decoder, c: number, v: number)
	if c < dec.n and dec.cells[c + 1] ~= v then
		dec.cells[c + 1] = v
		dec.changed[c] = true
	end
end

-- Full cells from Match "start".key. Resets the decoder to that match. Returns false on a bad buffer.
function Snap.applyKey(dec: Decoder, b: buffer): boolean
	if typeof(b) ~= "buffer" or buffer.len(b) < 6 or buffer.readu8(b, 0) ~= Snap.KEY then
		return false
	end
	local n = buffer.readu16(b, 4)
	if buffer.len(b) < 6 + n * 2 then
		return false
	end
	dec.ep, dec.seq, dec.n = buffer.readu8(b, 1), buffer.readu16(b, 2), n
	dec.cells = table.create(n, 0)
	dec.changed = {}
	for c = 0, n - 1 do
		dec.cells[c + 1] = buffer.readu16(b, 6 + c * 2)
		dec.changed[c] = true
	end
	return true
end

-- true if seq a is not older than b (16-bit wrap).
function Snap.fresh(a: number, b: number): boolean
	return b < 0 or (a - b) % 65536 < 32768
end

-- Applies one Snap packet. Returns the frame for type 1, nil for continuation, stale or broken packets.
function Snap.decode(dec: Decoder, b: buffer): Frame?
	if typeof(b) ~= "buffer" or buffer.len(b) < 6 then
		return nil
	end
	local kind, ep, seq = buffer.readu8(b, 0), buffer.readu8(b, 1), buffer.readu16(b, 2)
	if ep ~= dec.ep or not Snap.fresh(seq, dec.seq) then
		return nil
	end
	local ok, frame = pcall(function(): Frame?
		if kind == Snap.CONT then
			local cnt = buffer.readu16(b, 4)
			for j = 0, cnt - 1 do
				set(dec, buffer.readu16(b, 6 + j * 4), buffer.readu16(b, 8 + j * 4))
			end
			return nil
		elseif kind ~= Snap.FRAME then
			return nil
		end
		local st = buffer.readu8(b, 10)
		local nb, nc, nk, nu = buffer.readu8(b, 13), buffer.readu8(b, 14), buffer.readu8(b, 15), buffer.readu8(b, 16)
		local f: Frame = {
			seq = seq,
			t = buffer.readu32(b, 4) / 1000,
			pu = (buffer.readu16(b, 8) - 1) / 100,
			final = bit32.btest(st, 1),
			launched = bit32.btest(st, 2),
			slow = bit32.btest(st, 4),
			rx = buffer.readu16(b, 11),
			balls = {},
			clones = {},
			bombs = {},
			bubbles = {},
		}
		local o = Snap.HEADER
		for _ = 1, nb do
			table.insert(f.balls, {
				e = buffer.readu8(b, o),
				x = buffer.readu16(b, o + 1) / 1000,
				y = buffer.readu16(b, o + 3) / 1000,
				ang = buffer.readu16(b, o + 5) / 65536 * TAU,
				hp = buffer.readu8(b, o + 7),
				alive = buffer.readu8(b, o + 8) == 1,
				charge = buffer.readu8(b, o + 9) / 250,
				flags = buffer.readu8(b, o + 10),
				dx = buffer.readi8(b, o + 11) / 127,
				dy = buffer.readi8(b, o + 12) / 127,
				hole = buffer.readu8(b, o + 13) / 50,
				hx = buffer.readu16(b, o + 14) / 1000,
				hy = buffer.readu16(b, o + 16) / 1000,
				sx = buffer.readu16(b, o + 18) / 1000,
				sy = buffer.readu16(b, o + 20) / 1000,
				powers = buffer.readu8(b, o + 22),
				kills = buffer.readu8(b, o + 23),
				cnt = buffer.readu16(b, o + 24),
			})
			o += Snap.BALL
		end
		for _, list in { f.clones, f.bombs, f.bubbles } do
			local cnt = if list == f.clones then nc elseif list == f.bombs then nk else nu
			for _ = 1, cnt do
				local last = buffer.readu8(b, o + 4)
				table.insert(list, {
					buffer.readu16(b, o) / 1000,
					buffer.readu16(b, o + 2) / 1000,
					if list == f.bombs then last / 50 else last,
				})
				o += Snap.THING
			end
		end
		local refStart, refN = buffer.readu16(b, o), buffer.readu8(b, o + 2)
		o += 3
		for i = 0, refN - 1 do
			set(dec, (refStart + i) % math.max(1, dec.n), buffer.readu16(b, o))
			o += 2
		end
		local nd = buffer.readu16(b, o)
		o += 2
		for _ = 1, nd do
			set(dec, buffer.readu16(b, o), buffer.readu16(b, o + 2))
			o += 4
		end
		return f
	end)
	if not ok then
		return nil
	end
	dec.seq = seq
	return frame
end

-- Cells changed since the last call (0-based indices), for the renderer.
function Snap.takeChanged(dec: Decoder): { number }
	local out = {}
	for c in dec.changed do
		table.insert(out, c)
	end
	dec.changed = {}
	return out
end

return Snap
