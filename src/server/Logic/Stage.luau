--!strict
-- Staging helper of the tutorial (T2.1), pure. It only writes state the rules already have: ball positions,
-- directions and timers, terrain layers, land owners. The rules then run unchanged; nothing here changes what they mean.
-- Coordinates are field cells (fractional), as in the rules. The duel arena is x 4..20, y 3..17.
local Stage = {}

local FOREVER = 9999 -- Rules.Config.FOREVER: layers this long never run out

local function inArena(S: any, i: number, j: number): boolean
	return i >= S.ax0 and i < S.ax1 and j >= S.ay0 and j < S.ay1
end

-- Cells (1-based k) whose centres lie within r of (x, y), inside the arena.
local function discCells(S: any, x: number, y: number, r: number): { number }
	local out = {}
	for j = math.floor(y - r - 1), math.ceil(y + r) do
		for i = math.floor(x - r - 1), math.ceil(x + r) do
			local dx, dy = i + 0.5 - x, j + 0.5 - y
			if inArena(S, i, j) and dx * dx + dy * dy <= r * r then
				table.insert(out, j * S.W + i + 1)
			end
		end
	end
	return out
end

local function clearLayers(S: any, k: number)
	for _, layer in S.L do
		layer[k] = 0
	end
	S.burnFlam[k] = false
	S.src[k] = -1
end

-- Empty arena: no terrain, no land.
function Stage.clear(S: any)
	for k = 1, S.N do
		clearLayers(S, k)
		S.owner[k] = -1
		S.fade[k] = 0
	end
end

-- Land of e in a disc; terrain under it goes, so the land reads clearly.
function Stage.land(S: any, e: number, x: number, y: number, r: number)
	for _, k in discCells(S, x, y, r) do
		clearLayers(S, k)
		S.owner[k] = e
	end
end

-- Only the land of e goes (terrain stays).
function Stage.unland(S: any, e: number)
	for k = 1, S.N do
		if S.owner[k] == e then
			S.owner[k] = -1
		end
	end
end

-- Terrain layer on the cells x0..x1, y0..y1 (inclusive), forever. The cells lose their owner.
function Stage.patch(S: any, name: string, x0: number, y0: number, x1: number, y1: number)
	local layer = S.L[name]
	for j = y0, y1 do
		for i = x0, x1 do
			if inArena(S, i, j) then
				local k = j * S.W + i + 1
				clearLayers(S, k)
				layer[k] = FOREVER
				S.owner[k] = -1
			end
		end
	end
end

export type BallOpts = {
	hp: number?,
	stun: number?,
	charge: number?,
	-- false: the ball is out of the scene (dead, back after `respawn` seconds)
	alive: boolean?,
	respawn: number?,
}

-- A ball at (x, y) flying along (dx, dy). Previous positions too, so nothing is drawn sliding in.
function Stage.ball(S: any, e: number, x: number, y: number, dx: number, dy: number, o: BallOpts?)
	local b = S.by[e]
	local opts: BallOpts = o or {}
	local n = math.sqrt(dx * dx + dy * dy)
	b.x, b.y, b.px, b.py = x, y, x, y
	b.sx, b.sy, b.ex, b.ey, b.hx, b.hy = x, y, x, y, x, y
	b.dx, b.dy = dx / n, dy / n
	b.invuln = 0
	b.hp = opts.hp or 100
	b.stun = opts.stun or 0
	b.charge = opts.charge or 0
	b.readyT = 0
	b.alive = opts.alive ~= false
	b.respawn = if opts.alive == false then (opts.respawn or 999) else 0
end

-- Direction from ball a to ball b (unit), and the angle between it and (dx, dy) in radians.
function Stage.offAngle(S: any, a: number, b: number, dx: number, dy: number): (number, number, number)
	local p, q = S.by[a], S.by[b]
	local tx, ty = q.x - p.x, q.y - p.y
	local tn = math.sqrt(tx * tx + ty * ty)
	local dn = math.sqrt(dx * dx + dy * dy)
	if tn < 1e-6 or dn < 1e-6 then
		return 0, 0, math.pi
	end
	local c = math.clamp((tx * dx + ty * dy) / (tn * dn), -1, 1)
	return tx / tn, ty / tn, math.acos(c)
end

return Stage
