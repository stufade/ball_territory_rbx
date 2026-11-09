--!strict
-- Balls and match things on the board canvas, as the web drawBall / drawAim / drawHole / drawField: ball art with
-- the element icon, spike heads, charge ring, glow when ready, HP bar, YOU tag, aim lines, clones, bubbles, bombs and
-- black holes. Drawn from interpolated snapshots.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage.Shared.Look)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Field = require(script.Parent.Field)
local Geo = require(script.Parent.Geo)
local Gui = require(script.Parent.Gui)

local P = Rules.Config.P
local CELL = Gui.CELL
local BALL_PX = 31
local SNAP_JUMP = 3 -- cells: a longer step is a teleport, not interpolated
local SEGS = 40 -- charge ring segments
local DASHES = 28
local MAX_THINGS = 24
local F_STUN, F_BIG, F_INVULN, F_SURGE, F_PHASE, F_RUSH, F_SLOW = 1, 2, 4, 8, 16, 32, 64
local VOID = Rules.Config.VOID
local WHITE = Color3.new(1, 1, 1)

type Head = { out: Frame, mid: Frame, dot: Frame }
type BallView = {
	e: number,
	box: Frame,
	glow: Frame,
	heads: { Head },
	shadow: Frame,
	segs: { Frame },
	lit: number,
	rush: Frame,
	slow: Frame,
	img: ImageLabel,
	stun: { Frame },
	hpBg: Frame,
	hpFill: Frame,
	tag: TextLabel?,
	surge: Frame,
	surgeStroke: UIStroke,
	dashes: { Frame },
	aimOut: Frame,
	aimIn: Frame,
	hp: number,
	big: boolean,
	x: number,
	y: number,
	shown: boolean,
}

type Hole = { box: Frame, discs: { Frame }, arms: { Frame } }
type Thing = { box: Frame, parts: { GuiObject } }

export type Actors = {
	field: Field.Field,
	you: number?,
	names: { [number]: string },
	-- own aim before launch (Match start/aim): snapshots carry no directions until launch
	aim: { number }?,
	balls: { [number]: BallView },
	holes: { [number]: Hole },
	clones: { Thing },
	bombs: { Thing },
	bubbles: { Thing },
	tick: number,
}

local Actors = {}

local function newHead(box: Frame, e: number): Head
	local out = Gui.circle(box, 16, Look.OUT, 2)
	local mid = Gui.circle(out, 13, if e == VOID then Color3.fromHex("#783cdc") else Look.col(e), 2)
	mid.Position = UDim2.fromScale(0.5, 0.5)
	local dot = Gui.circle(out, 6, if e == VOID then Color3.fromHex("#c496ff") else WHITE, 3)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	return { out = out, mid = mid, dot = dot }
end

local function newBall(self: Actors, e: number): BallView
	local f = self.field
	local box = Instance.new("Frame")
	box.Name = "Ball" .. e
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(0, 0)
	box.ZIndex = 5
	box.Parent = f.balls
	local glow = Gui.circle(box, 62, WHITE, 1)
	glow.Visible = false
	local heads = { newHead(box, e), newHead(box, e) }
	local shadow = Gui.ring(box, 40, 7, Color3.new(0, 0, 0), 3)
	local stroke = shadow:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Transparency = 0.55
	local segs = {}
	local len = 2 * math.pi * 40 / SEGS + 1.2
	for i = 1, SEGS do
		local a = -math.pi / 2 + (i - 0.5) / SEGS * 2 * math.pi
		local s = Gui.frame(box, WHITE, 4)
		s.Size = UDim2.fromOffset(len, 6)
		s.Position = UDim2.fromOffset(math.cos(a) * 40, math.sin(a) * 40)
		s.Rotation = math.deg(a) + 90
		s.Visible = false
		segs[i] = s
	end
	local rush = Gui.circle(box, 52, Color3.fromHex("#ff6688"), 2)
	rush.BackgroundTransparency = 0.55
	rush.Visible = false
	local slow = Gui.ring(box, 50, 4, Color3.fromRGB(170, 180, 255), 5)
	slow.Visible = false
	local img = Gui.ballImage(box, e, BALL_PX, 6)
	local stun = {}
	for i = 1, 20 do
		local s = Gui.frame(box, WHITE, 7)
		s.BackgroundTransparency = 0.3
		s.Size = UDim2.fromOffset(7, 3)
		s.Visible = false
		stun[i] = s
	end
	local hpBg = Gui.frame(box, Color3.fromHex("#141428"), 8)
	hpBg.AnchorPoint = Vector2.new(0, 0)
	hpBg.Position = UDim2.fromOffset(-26, -54)
	hpBg.Size = UDim2.fromOffset(52, 9)
	hpBg.Visible = false
	local hpFill = Gui.frame(hpBg, Color3.fromHex("#46f078"), 9)
	hpFill.AnchorPoint = Vector2.new(0, 0)
	hpFill.Position = UDim2.fromOffset(2, 2)
	hpFill.Size = UDim2.fromOffset(48, 5)
	local tag: TextLabel? = nil
	local name = if e == self.you then "YOU" else self.names[e]
	if name then
		local t = Gui.text(box, if e == self.you then 26 else 20, WHITE, { stroke = 4, z = 8 })
		t.Text = name
		t.Position = UDim2.fromOffset(0, 56)
		tag = t
	end
	local surge, surgeStroke = Gui.ring(f.under, P.surgeArea * CELL, 4, Color3.fromHex("#28964f"), 1)
	surge.Visible = false
	local dashes = {}
	local mine = e == self.you
	for i = 1, DASHES do
		local d = Gui.frame(f.under, if mine then Color3.fromHex("#ebebff") else Look.bright(e), 3)
		d.BackgroundTransparency = if mine then 0 else 0.45
		d.Size = UDim2.fromOffset(if mine then 18 else 10, if mine then 7 else 3)
		d.Visible = false
		dashes[i] = d
	end
	local aimOut = Gui.ring(f.under, 30, 6, WHITE, 4)
	local aimIn = Gui.ring(f.under, 15, 5, Look.col(e), 4)
	aimOut.Visible, aimIn.Visible = false, false
	return {
		e = e,
		box = box,
		glow = glow,
		heads = heads,
		shadow = shadow,
		segs = segs,
		lit = 0,
		rush = rush,
		slow = slow,
		img = img,
		stun = stun,
		hpBg = hpBg,
		hpFill = hpFill,
		tag = tag,
		surge = surge,
		surgeStroke = surgeStroke,
		dashes = dashes,
		aimOut = aimOut,
		aimIn = aimIn,
		hp = 100,
		big = false,
		x = 0,
		y = 0,
		shown = true,
	}
end

function Actors.new(field: Field.Field, you: number?, names: { [number]: string }): Actors
	return {
		field = field,
		you = you,
		names = names,
		aim = nil,
		balls = {},
		holes = {},
		clones = {},
		bombs = {},
		bubbles = {},
		tick = 0,
	}
end

local function hideAim(v: BallView)
	for _, d in v.dashes do
		d.Visible = false
	end
	v.aimOut.Visible, v.aimIn.Visible = false, false
end

local function setShown(v: BallView, on: boolean)
	if v.shown == on then
		return
	end
	v.shown = on
	v.box.Visible = on
	if not on then
		hideAim(v)
		v.surge.Visible = false
	end
end

-- Position of ball e on the interpolated frame, in field cells (for the tap direction).
function Actors.ballPos(self: Actors, e: number): (number?, number?)
	local v = self.balls[e]
	if not v or not v.shown then
		return nil, nil
	end
	return v.x, v.y
end

local function lerpBall(a: any, b: any, t: number): (number, number, number)
	if Geo.dist2(a.x, a.y, b.x, b.y) > SNAP_JUMP then
		return b.x, b.y, b.ang
	end
	return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, Geo.angleLerp(a.ang, b.ang, t)
end

-- End of the aim ray on the arena border, as rayCells ends on the field edge.
local function rayEnd(self: Actors, x: number, y: number, dx: number, dy: number): (number, number)
	local bd = self.field.board
	local x0, y0, x1, y1 = bd.ox, bd.oy, bd.ox + bd.gw, bd.oy + bd.gh
	local t = 1e9
	if dx > 1e-6 then
		t = math.min(t, (x1 - 0.5 - x) / dx)
	elseif dx < -1e-6 then
		t = math.min(t, (x0 + 0.5 - x) / dx)
	end
	if dy > 1e-6 then
		t = math.min(t, (y1 - 0.5 - y) / dy)
	elseif dy < -1e-6 then
		t = math.min(t, (y0 + 0.5 - y) / dy)
	end
	t = math.max(0, t)
	return x + dx * t, y + dy * t
end

local function drawAim(self: Actors, v: BallView, x: number, y: number, dx: number, dy: number, now: number)
	local m = math.sqrt(dx * dx + dy * dy)
	if m < 0.05 then
		hideAim(v)
		return
	end
	dx, dy = dx / m, dy / m
	local ex, ey = rayEnd(self, x, y, dx, dy)
	local f = self.field
	local x0, y0, x1, y1 = Field.px(f, x), Field.py(f, y), Field.px(f, ex), Field.py(f, ey)
	local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local mine = v.e == self.you
	local dash, gap = if mine then 18 else 10, if mine then 16 else 14
	local period = dash + gap
	local off = (now * 60) % period
	local rot = math.deg(math.atan2(y1 - y0, x1 - x0))
	for i, d in v.dashes do
		local s0 = (i - 1) * period + off - period
		local a, b = math.max(0, s0), math.min(len, s0 + dash)
		if b > a then
			local mid = (a + b) / 2
			d.Visible = true
			d.Position = UDim2.fromOffset(x0 + (x1 - x0) * mid / len, y0 + (y1 - y0) * mid / len)
			d.Size = UDim2.fromOffset(b - a, if mine then 7 else 3)
			d.Rotation = rot
		else
			d.Visible = false
		end
	end
	if mine then
		v.aimOut.Visible, v.aimIn.Visible = true, true
		v.aimOut.Position = UDim2.fromOffset(x1, y1)
		v.aimIn.Position = UDim2.fromOffset(x1, y1)
	end
end

local function updateBall(self: Actors, e: number, a: any, b: any, t: number, now: number, aiming: boolean)
	local v = self.balls[e]
	if not v then
		v = newBall(self, e)
		self.balls[e] = v
	end
	if not b.alive then
		setShown(v, false)
		return
	end
	setShown(v, true)
	local f = self.field
	local x, y, ang = lerpBall(a, b, t)
	v.x, v.y = x, y
	v.box.Position = Field.at(f, x, y)
	local big = bit32.btest(b.flags, F_BIG)
	local reach = P.orbitR * (if big then 1.5 else 1) * CELL
	if big ~= v.big then
		v.big = big
		local hr = if big then 20 else 16
		for _, h in v.heads do
			h.out.Size = UDim2.fromOffset(hr * 2, hr * 2)
			h.mid.Size = UDim2.fromOffset((hr - 3) * 2, (hr - 3) * 2)
			h.dot.Size = UDim2.fromOffset(hr * 0.76, hr * 0.76)
		end
	end
	for i, h in v.heads do
		local an = ang + (i - 1) * math.pi
		h.out.Position = UDim2.fromOffset(math.cos(an) * reach, math.sin(an) * reach)
	end
	local ready = b.charge >= 1
	v.glow.Visible = ready
	if ready then
		v.glow.BackgroundTransparency = 1 - (0.3 + 0.15 * math.sin(now * 14))
	end
	local lit = math.floor(math.clamp(b.charge, 0, 1) * SEGS + 0.5)
	if lit ~= v.lit then
		for i, s in v.segs do
			s.Visible = i <= lit
		end
		v.lit = lit
	end
	v.rush.Visible = bit32.btest(b.flags, F_RUSH)
	v.slow.Visible = bit32.btest(b.flags, F_SLOW)
	local alpha = if bit32.btest(b.flags, F_PHASE)
		then 0.4 + 0.15 * math.sin(now * 10)
		elseif bit32.btest(b.flags, F_INVULN) and math.floor(now * 15) % 2 == 0 then 0.55
		else 1
	v.img.ImageTransparency = 1 - alpha
	local stunned = bit32.btest(b.flags, F_STUN)
	for i, s in v.stun do
		s.Visible = stunned
		if stunned then
			local an = now * 6 + (i - 1) / #v.stun * 2 * math.pi
			s.Position = UDim2.fromOffset(math.cos(an) * 46, math.sin(an) * 46)
			s.Rotation = math.deg(an) + 90
		end
	end
	if b.hp ~= v.hp then
		v.hp = b.hp
		v.hpBg.Visible = b.hp < 100
		v.hpFill.Size = UDim2.fromOffset(48 * math.max(0, b.hp) / 100, 5)
		v.hpFill.BackgroundColor3 = if b.hp > 40 then Color3.fromHex("#46f078") else Color3.fromHex("#ff463c")
	end
	local surge = bit32.btest(b.flags, F_SURGE)
	v.surge.Visible = surge
	if surge then
		v.surge.Position = Field.at(f, b.sx, b.sy)
	end
	local aim = self.aim
	if aiming and e == self.you and aim then
		drawAim(self, v, x, y, aim[1], aim[2], now)
	else
		hideAim(v)
	end
end

local function newHole(self: Actors): Hole
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(0, 0)
	box.Parent = self.field.under
	local discs = {}
	for i, q in { { 1, 0.75 }, { 0.7, 0.45 }, { 0.42, 0.08 } } do
		local d = Gui.circle(box, 10, if i == 3 then Color3.fromRGB(6, 0, 14) else Color3.fromRGB(20, 4, 40), i)
		d.BackgroundTransparency = q[2]
		d:SetAttribute("k", q[1])
		discs[i] = d
	end
	local arms = {}
	for i = 1, 4 * 8 do
		local s = Gui.frame(box, Color3.fromHex("#a05aff"), 4)
		arms[i] = s
	end
	return { box = box, discs = discs, arms = arms }
end

local function drawHole(self: Actors, e: number, b: any, now: number)
	local h = self.holes[e]
	if b.hole <= 0 or not b.alive then
		if h then
			h.box.Visible = false
		end
		return
	end
	if not h then
		h = newHole(self)
		self.holes[e] = h
	end
	h.box.Visible = true
	h.box.Position = Field.at(self.field, b.hx, b.hy)
	local u = 1 - math.max(0, b.hole) / P.holeT
	local R = (1 + u * (P.holeR - 1)) * CELL + 16
	for _, d in h.discs do
		local k = d:GetAttribute("k") :: number
		d.Size = UDim2.fromOffset(R * 2 * k, R * 2 * k)
	end
	for arm = 0, 3 do
		local px, py
		for i = 0, 8 do
			local q = 1 - i / 8
			local a = now * 7 + arm * math.pi / 2 + (1 - q) * 3.2
			local x, y = math.cos(a) * R * q, math.sin(a) * R * q
			if i > 0 then
				Gui.segment(h.arms[arm * 8 + i], px, py, x, y, 6)
			end
			px, py = x, y
		end
	end
end

local function thing(self: Actors, pool: { Thing }, i: number, make: (Frame) -> { GuiObject }): Thing
	local q = pool[i]
	if not q then
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(0, 0)
		box.ZIndex = 3
		box.Parent = self.field.balls
		q = { box = box, parts = make(box) }
		pool[i] = q
	end
	return q
end

local function things(
	self: Actors,
	pool: { Thing },
	la: { any },
	lb: { any },
	t: number,
	make: (Frame) -> { GuiObject },
	style: (Thing, any) -> ()
)
	local n = math.min(#lb, MAX_THINGS)
	for i = 1, n do
		local q = thing(self, pool, i, make)
		local b, a = lb[i], la[i]
		local x, y = b[1], b[2]
		if a and Geo.dist2(a[1], a[2], b[1], b[2]) < SNAP_JUMP then
			x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
		end
		q.box.Visible = true
		q.box.Position = Field.at(self.field, x, y)
		style(q, b)
	end
	for i = n + 1, #pool do
		pool[i].box.Visible = false
	end
end

function Actors.update(self: Actors, a: any, b: any, t: number, now: number, aiming: boolean)
	local seen: { [number]: boolean } = {}
	local prev: { [number]: any } = {}
	for _, ba in a.balls do
		prev[ba.e] = ba
	end
	for _, bb in b.balls do
		seen[bb.e] = true
		updateBall(self, bb.e, prev[bb.e] or bb, bb, t, now, aiming)
		drawHole(self, bb.e, bb, now)
	end
	for e, v in self.balls do
		if not seen[e] then
			setShown(v, false)
		end
	end
	things(self, self.clones, a.clones, b.clones, t, function(box)
		local img = Gui.ballImage(box, 0, 15, 1)
		img.ImageTransparency = 0.15
		return { img }
	end, function(q, c)
		Gui.setBall(q.parts[1] :: ImageLabel, c[3], 15)
	end)
	things(self, self.bubbles, a.bubbles, b.bubbles, t, function(box)
		local r = Gui.ring(box, 18, 4, Color3.fromHex("#bff5ff"), 1)
		local d = Gui.circle(box, 4, WHITE, 2)
		d.Position = UDim2.fromOffset(-6, -6)
		return { r, d }
	end, function() end)
	things(self, self.bombs, a.bombs, b.bombs, t, function(box)
		local zone, st = Gui.ring(box, 10, 4, Color3.fromRGB(255, 80, 60), 1)
		st.Transparency = 0.5
		local body = Gui.circle(box, 18, Color3.fromHex("#1a1a1a"), 2)
		local fuse = Gui.frame(box, Color3.fromHex("#c8a060"), 2)
		Gui.segment(fuse, 8, -12, 16, -24, 4)
		local spark = Gui.circle(box, 6, Color3.fromHex("#ffd63c"), 3)
		spark.Position = UDim2.fromOffset(17, -26)
		return { zone, body, fuse, spark }
	end, function(q, c)
		local left = math.max(0, c[3])
		local zone = q.parts[1] :: Frame
		Gui.setRing(
			zone,
			zone:FindFirstChildOfClass("UIStroke") :: UIStroke,
			P.bombR * CELL * (1 - left / P.bombT * 0.3),
			4
		)
		q.parts[4].Visible = math.sin(now * (10 + 20 * (1 - left / P.bombT))) > 0
	end)
end

function Actors.destroy(_self: Actors) end

return Actors
