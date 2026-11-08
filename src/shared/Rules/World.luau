--!strict
-- Terrain that lives on its own: fire, plant surge, lava, spores, toxic cloud, black hole, ground damage.
local Config = require("./Config")
local Core = require("./Core")
local Grid = require("./Grid")
local React = require("./React")
local Types = require("./Types")

type State = Types.State
type Ball = Types.Ball
type Mask = Types.Mask

local P, DT, NEL, FOREVER = Config.P, Config.DT, Config.NEL, Config.FOREVER
local PLANT, LAVA, FIRE, EARTH, POISON = Config.PLANT, Config.LAVA, Config.FIRE, Config.EARTH, Config.POISON
local r2, f32, disc, dilate, count, center, neighbors =
	Grid.r2, Grid.f32, Grid.disc, Grid.dilate, Grid.count, Grid.center, Grid.neighbors
local own, capture, clearCell, lockedAt, hardAt, hit, gain, ev =
	Core.own, Core.capture, Core.clearCell, Core.lockedAt, Core.hardAt, Core.hit, Core.gain, Core.ev
local max = math.max

local World = {}

function World.fireStep(S: State)
	local dt = DT * 4
	local burn, water, ice, bush, owner, src, burnFlam = S.burn, S.water, S.ice, S.bush, S.owner, S.src, S.burnFlam
	local wf = S.acc.WILDFIRE
	wf.idle += dt
	local N = S.N
	local burning: Mask = table.create(N, false)
	local any = false
	for k = 1, N do
		if burn[k] > 0 then
			burning[k] = true
			any = true
		end
	end
	if any then
		local n = neighbors(S, burning)
		local hot = if wf.n < P.wildCap then P.plantBurnP else P.fireP
		local flamIgn: Mask = table.create(N, false)
		local byCount = table.create(NEL, 0)
		local plant = S.by[PLANT] ~= nil
		local kf = 0
		local nbr = S.nbr
		local plantBurnT, burnT = f32(P.plantBurnT), f32(P.burnT)
		for k = 1, N do
			if n[k] == 0 or burning[k] or water[k] > 0 or ice[k] > 0 or lockedAt(S, k) then
				continue
			end
			local ns = -1
			for _, q in nbr[k] do
				if burning[q] then
					ns = max(ns, src[q])
				end
			end
			if owner[k] == ns then
				continue
			end
			local flam = bush[k] > 0 or (plant and owner[k] == PLANT)
			if S.rand() < 1 - (1 - (if flam then hot else P.fireP)) ^ n[k] then
				burn[k] = if flam then plantBurnT else burnT
				burnFlam[k] = flam
				src[k] = ns
				if flam then
					flamIgn[k] = true
					kf += 1
					if ns >= 0 then
						byCount[ns + 1] += 1
					end
				end
			end
		end
		if kf > 0 then
			local best, bi = -1, 0
			for i = 1, NEL do
				if byCount[i] > best then
					best, bi = byCount[i], i - 1
				end
			end
			React.accumulate(S, "WILDFIRE", flamIgn, kf, bi)
		end
		for k = 1, N do
			if not burning[k] then
				continue
			end
			burn[k] = f32(burn[k] - dt)
			if burn[k] > 0 then
				continue
			end
			burn[k] = 0
			local ash = burnFlam[k] and S.rand() < P.ashP
			local bushy, e = bush[k] > 0, src[k]
			if ash or e < 0 then
				owner[k] = -1
			else
				own(S, k, e)
			end
			bush[k] = 0
			burnFlam[k] = false
			S.fade[k] = 0
			local eb = S.by[e]
			if bushy and eb then
				gain(S, eb, 1)
			end
		end
	end
	React.flushAcc(S, "WILDFIRE")
end

function World.plantStep(S: State)
	S.acc.BLOOM.idle += DT * 6
	local b = S.by[PLANT]
	if b and b.surge > 0 and b.alive then
		local N, owner, water, bush = S.N, S.owner, S.water, S.bush
		local area = disc(S, b.sx, b.sy, P.surgeArea)
		local mine: Mask = table.create(N, false)
		for k = 1, N do
			mine[k] = owner[k] == PLANT
		end
		local near = dilate(S, mine)
		local wet: Mask = table.create(N, false)
		local nw = 0
		for k = 1, N do
			if not area[k] or not near[k] then
				continue
			end
			local roll = S.rand()
			if water[k] > 0 and roll < 0.5 then
				own(S, k, PLANT)
				water[k] = 0
				wet[k] = true
				nw += 1
				continue
			end
			if owner[k] == PLANT or hardAt(S, k) then
				continue
			end
			local pr = if bush[k] > 0 then 0.7 elseif owner[k] == -1 then P.growNeutralP else P.growEnemyP
			if roll < pr then
				own(S, k, PLANT)
				bush[k] = 0
			end
		end
		if nw > 0 then
			React.accumulate(S, "BLOOM", wet, nw, PLANT)
		end
	end
	React.flushAcc(S, "BLOOM")
end

local function eruptStep(S: State, b: Ball)
	local N, lava, src, water, ice, bush = S.N, S.lava, S.src, S.water, S.ice, S.bush
	local mine: Mask = table.create(N, false)
	for k = 1, N do
		mine[k] = lava[k] > 0 and src[k] == b.e
	end
	local d, reach = dilate(S, mine), disc(S, b.ex, b.ey, P.eruptReach)
	local wet: Mask, bushM: Mask = table.create(N, false), table.create(N, false)
	local nf, nw, nb = 0, 0, 0
	local rockT, lavaT = f32(P.rockT), f32(P.lavaT)
	for k = 1, N do
		if not d[k] or mine[k] or not reach[k] or lockedAt(S, k) or S.rand() >= P.lavaSpreadP then
			continue
		end
		nf += 1
		if water[k] > 0 or ice[k] > 0 then
			clearCell(S, k, false, false)
			S.rock[k] = rockT
			src[k] = b.e
			own(S, k, b.e)
			wet[k] = true
			nw += 1
		elseif bush[k] > 0 then
			bushM[k] = true
			nb += 1
		else
			clearCell(S, k, true, false)
			lava[k] = lavaT
			src[k] = b.e
			own(S, k, b.e)
		end
	end
	if nw > 0 and (S.cd.OBSIDIAN or 0) <= 0 then
		S.cd.OBSIDIAN = 3
		local x, y = center(S, wet)
		React.reaction(S, "OBSIDIAN", x, y, b.e, "water")
	end
	if nb > 0 then
		React.ignite(S, bushM, b.e)
	end
	if nf > 0 then
		gain(S, b, nf)
	end
end

local function podStep(S: State)
	local live = {}
	for _, pod in S.pods do
		if S.t < pod.t then
			table.insert(live, pod)
			continue
		end
		local d = disc(S, pod.x, pod.y, P.sporeR)
		local m: Mask = table.create(S.N, false)
		for k = 1, S.N do
			m[k] = d[k] and not hardAt(S, k)
		end
		local got = capture(S, m, pod.e)
		for k = 1, S.N do
			if got[k] then
				S.bush[k] = FOREVER
				S.src[k] = pod.e
			end
		end
		local pb = S.by[pod.e]
		if pb then
			gain(S, pb, count(S, got) // 2)
		end
		ev(S, "spore", { x = r2(pod.x), y = r2(pod.y) })
	end
	S.pods = live
end

local function toxicStep(S: State)
	local N, tox, src, nbr = S.N, S.toxic, S.src, S.nbr
	local any = false
	for k = 1, N do
		if tox[k] > 0 then
			any = true
			break
		end
	end
	if not any then
		return
	end
	local lv: Mask = table.create(N, false)
	for k = 1, N do
		lv[k] = tox[k] > 0 and src[k] >= 0
	end
	local near = neighbors(S, lv)
	local add = {}
	for k = 1, N do
		if near[k] == 0 or lv[k] or hardAt(S, k) then
			continue
		end
		local ns = -1
		for _, q in nbr[k] do
			if lv[q] then
				ns = max(ns, src[q])
			end
		end
		if ns < 0 or S.owner[k] == ns then
			continue
		end
		if S.rand() < 1 - (1 - P.toxicSpreadP) ^ near[k] then
			table.insert(add, k)
			table.insert(add, ns)
		end
	end
	local v = f32(P.toxinT * 0.6)
	for i = 1, #add, 2 do
		local k, ns = add[i], add[i + 1]
		tox[k] = v
		src[k] = ns
		own(S, k, ns)
	end
end

local function holeStep(S: State, b: Ball, dt: number)
	b.hole -= dt
	local u = 1 - max(0, b.hole) / P.holeT
	local d = disc(S, b.hx, b.hy, 1 + u * (P.holeR - 1))
	local eat: Mask = table.create(S.N, false)
	local n = 0
	for k = 1, S.N do
		if d[k] and not lockedAt(S, k) and S.ice[k] <= 0 and S.owner[k] ~= b.e then
			eat[k] = true
			n += 1
		end
	end
	if n > 0 then
		capture(S, eat, b.e)
		gain(S, b, n // 2)
	end
	for _, t in S.balls do
		if t == b or not t.alive then
			continue
		end
		local dist = Grid.hypot(t.x - b.hx, t.y - b.hy)
		if dist < P.holePull then
			Core.point(t, b.hx, b.hy)
			local dd = if dist == 0 then 1 else dist
			Core.shove(S, t, (b.hx - t.x) / dd, (b.hy - t.y) / dd, math.min(dist, P.holeTug))
			if dist < 1.3 and t.invuln <= 0 and b.hitCd[t.e] <= 0 then
				b.hitCd[t.e] = 0.9
				hit(S, t, P.holeDmg, b)
			end
		end
	end
end

function World.hazardStep(S: State)
	local dt = DT * 3
	for _, b in S.balls do
		if b.erupt > 0 then
			eruptStep(S, b)
		end
	end
	podStep(S)
	toxicStep(S)
	for _, b in S.balls do
		if b.hole > 0 then
			holeStep(S, b, dt)
		end
	end
	for _, b in S.balls do
		if not b.alive or b.invuln > 0 then
			continue
		end
		local c = Core.cellOf(S, b)
		local by = S.src[c]
		if by == b.e then
			continue
		end
		local dmg = 0
		if S.lava[c] > 0 and b.e ~= LAVA and b.e ~= FIRE and b.e ~= EARTH then
			dmg += P.lavaDps * dt
		end
		if S.toxic[c] > 0 and b.e ~= POISON then
			dmg += P.toxicDps * dt
		end
		if S.burn[c] > 0 and b.e ~= FIRE and b.e ~= LAVA then
			dmg += P.burnDps * dt
		end
		if dmg ~= 0 then
			hit(S, b, dmg, S.by[by], true)
		end
	end
end

return World
