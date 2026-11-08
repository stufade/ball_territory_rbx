--!strict
-- Cell masks and rays. Cells are 1-based: k = y * W + x + 1; masks are boolean arrays of size N.
local Types = require("./Types")

type State = Types.State
type Mask = Types.Mask

local Grid = {}

local floor, sqrt, abs, max, min, cos, sin = math.floor, math.sqrt, math.abs, math.max, math.min, math.cos, math.sin

export type Geometry = { cxs: { number }, cys: { number }, nbr: { { number } } }
local cache: { [string]: Geometry } = {}

-- Cell coordinates and 4-neighbours (up, down, left, right like nb() in the web build).
function Grid.geometry(W: number, H: number): Geometry
	local key = W .. "x" .. H
	local hit = cache[key]
	if hit then
		return hit
	end
	local N = W * H
	local cxs, cys, nbr = table.create(N, 0), table.create(N, 0), table.create(N)
	for k = 1, N do
		local i, j = (k - 1) % W, (k - 1) // W
		cxs[k], cys[k] = i, j
		local out = {}
		if j > 0 then
			table.insert(out, k - W)
		end
		if j < H - 1 then
			table.insert(out, k + W)
		end
		if i > 0 then
			table.insert(out, k - 1)
		end
		if i < W - 1 then
			table.insert(out, k + 1)
		end
		nbr[k] = out
	end
	local g: Geometry = { cxs = cxs, cys = cys, nbr = nbr }
	cache[key] = g
	return g
end

local scratch = buffer.create(4)
-- Round to float32: the web keeps layer timers in Float32Array.
function Grid.f32(v: number): number
	buffer.writef32(scratch, 0, v)
	return buffer.readf32(scratch, 0)
end

-- Math.hypot as V8 computes it (normalised Kahan sum), so rays and distances match the web bit for bit.
function Grid.hypot(a: number, b: number): number
	a, b = abs(a), abs(b)
	local m = if a > b then a else b
	if m == 0 then
		return 0
	end
	local n = a / m
	local summand = n * n
	local sum = summand
	local comp = (sum - 0) - summand
	n = b / m
	summand = n * n - comp
	sum = sum + summand
	return sqrt(sum) * m
end

function Grid.new(S: State): Mask
	return table.create(S.N, false)
end

function Grid.disc(S: State, x: number, y: number, r: number): Mask
	local W = S.W
	local m: Mask = table.create(S.N, false)
	local q = r * r
	local x0, x1 = max(S.ax0, floor(x - r - 1)), min(S.ax1 - 1, math.ceil(x + r))
	local y0, y1 = max(S.ay0, floor(y - r - 1)), min(S.ay1 - 1, math.ceil(y + r))
	for j = y0, y1 do
		local dy = j + 0.5 - y
		local dy2 = dy * dy
		local row = j * W + 1
		for i = x0, x1 do
			local dx = i + 0.5 - x
			if dx * dx + dy2 <= q then
				m[row + i] = true
			end
		end
	end
	return m
end

-- Number of set 4-neighbours of every cell.
function Grid.neighbors(S: State, m: Mask): { number }
	local N, nbr = S.N, S.nbr
	local r = table.create(N, 0)
	for k = 1, N do
		if m[k] then
			for _, q in nbr[k] do
				r[q] += 1
			end
		end
	end
	return r
end

function Grid.dilate(S: State, m: Mask): Mask
	local N, nbr = S.N, S.nbr
	local r: Mask = table.create(N, false)
	for k = 1, N do
		if m[k] then
			for _, q in nbr[k] do
				r[q] = true
			end
		end
	end
	return r
end

function Grid.grow(S: State, m: Mask): Mask
	local N, nbr = S.N, S.nbr
	local r: Mask = table.create(N, false)
	for k = 1, N do
		if m[k] then
			r[k] = true
			for _, q in nbr[k] do
				r[q] = true
			end
		end
	end
	return r
end

function Grid.mask(S: State, f: (number) -> boolean): Mask
	local m: Mask = table.create(S.N, false)
	for k = 1, S.N do
		if f(k) then
			m[k] = true
		end
	end
	return m
end

function Grid.count(S: State, m: Mask): number
	local c = 0
	for k = 1, S.N do
		if m[k] then
			c += 1
		end
	end
	return c
end

function Grid.center(S: State, m: Mask): (number, number)
	local sx, sy, n = 0, 0, 0
	local cxs, cys = S.cxs, S.cys
	for k = 1, S.N do
		if m[k] then
			sx += cxs[k] + 0.5
			sy += cys[k] + 0.5
			n += 1
		end
	end
	if n > 0 then
		return sx / n, sy / n
	end
	return S.W / 2, S.H / 2
end

function Grid.component(S: State, src: Mask, k0: number): Mask
	local m: Mask = table.create(S.N, false)
	if not src[k0] then
		return m
	end
	local nbr = S.nbr
	local st, top = { k0 }, 1
	m[k0] = true
	while top > 0 do
		local k = st[top]
		st[top] = nil
		top -= 1
		for _, q in nbr[k] do
			if src[q] and not m[q] then
				m[q] = true
				top += 1
				st[top] = q
			end
		end
	end
	return m
end

-- Cells a ray from (x0, y0) towards (x1, y1) crosses inside the arena, with diagonal steps filled in.
function Grid.rayCells(S: State, x0: number, y0: number, x1: number, y1: number): ({ number }, number, number)
	local dx, dy = x1 - x0, y1 - y0
	local n = Grid.hypot(dx, dy)
	if n < 1e-6 then
		dx, dy, n = 1, 0, 1
	end
	dx /= n
	dy /= n
	local W = S.W
	local out, seen = {}, {}
	local x, y = x0, y0
	local lx, ly = -1, -1
	local ax0, ay0, ax1, ay1 = S.ax0, S.ay0, S.ax1, S.ay1
	while x >= ax0 and x < ax1 and y >= ay0 and y < ay1 do
		local cx, cy = floor(x), floor(y)
		if lx < 0 or cx ~= lx or cy ~= ly then
			if lx >= 0 and cx ~= lx and cy ~= ly then
				local q = ly * W + cx + 1
				if not seen[q] then
					seen[q] = true
					table.insert(out, q)
				end
			end
			local q = cy * W + cx + 1
			if not seen[q] then
				seen[q] = true
				table.insert(out, q)
			end
			lx, ly = cx, cy
		end
		x += dx * 0.25
		y += dy * 0.25
	end
	return out, x - dx * 0.25, y - dy * 0.25
end

function Grid.rayMask(S: State, x0: number, y0: number, x1: number, y1: number): Mask
	local m: Mask = table.create(S.N, false)
	local out = Grid.rayCells(S, x0, y0, x1, y1)
	for _, k in out do
		m[k] = true
	end
	return m
end

local function r2(v: number): number
	return floor(v * 100 + 0.5) / 100
end
Grid.r2 = r2

-- n rays of length len from (x, y), first at angle a0. Returns the mask and the ray ends for drawing.
function Grid.rays(S: State, x: number, y: number, n: number, len: number, a0: number?): (Mask, { { number } })
	local m: Mask = table.create(S.N, false)
	local ends = {}
	local cxs, cys, hypot = S.cxs, S.cys, Grid.hypot
	local base = a0 or 0
	for i = 0, n - 1 do
		local a = base + i * math.pi * 2 / n
		local out, ex, ey = Grid.rayCells(S, x, y, x + cos(a), y + sin(a))
		for _, k in out do
			if hypot(cxs[k] + 0.5 - x, cys[k] + 0.5 - y) <= len then
				m[k] = true
			end
		end
		local d = min(len, hypot(ex - x, ey - y))
		table.insert(ends, { r2(x + cos(a) * d), r2(y + sin(a) * d) })
	end
	return m, ends
end

function Grid.ringMask(S: State, x: number, y: number, r: number): Mask
	local d, inner = Grid.disc(S, x, y, r + 0.75), Grid.disc(S, x, y, max(0, r - 0.75))
	for k = 1, S.N do
		if d[k] and inner[k] then
			d[k] = false
		end
	end
	return d
end

return Grid
