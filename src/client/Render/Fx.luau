--!strict
-- Effects of Match "ev" events on the board canvas, ported from the web applyFx / reactionFx / drawCalls:
-- particle bursts, rings, beams, lightning arcs, screen shake, zoom to the reaction, colour tint, hit pause,
-- power words over the ball, huge reaction words, the "ball + terrain = WORD" formula, FINAL! and the
-- CHOOSE DIRECTION bar, floating damage numbers. Everything is pooled; nothing is created per event.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage.Shared.Look)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Field = require(script.Parent.Field)
local Gui = require(script.Parent.Gui)

local P = Rules.Config.P
local CELL = Gui.CELL
local NPARTS, NRINGS, NBEAMS, NARCS, ARC_SEGS, NCALLS, NWORDS, NPOPS = 300, 40, 24, 10, 12, 6, 6, 12
local WHITE = Color3.new(1, 1, 1)
local C = Color3.fromHex

type Part = { f: Frame, x: number, y: number, vx: number, vy: number, life: number, t: number, r: number, on: boolean }
type Ring = {
	f: Frame,
	s: UIStroke,
	x: number,
	y: number,
	r0: number,
	r1: number,
	t: number,
	life: number,
	w: number,
	on: boolean,
}
type Beam = {
	a: Frame,
	b: Frame,
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	t: number,
	life: number,
	w: number,
	on: boolean,
}
type Arc = {
	segs: { Frame },
	core: { Frame },
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	t: number,
	life: number,
	on: boolean,
}
type Call = {
	l: TextLabel,
	s: UIStroke,
	k: UIScale,
	size: number,
	x: number,
	y: number,
	t: number,
	life: number,
	on: boolean,
}
type Word = { l: TextLabel, s: UIStroke, e: number, t: number, on: boolean }
type Pop = { l: TextLabel, s: UIStroke, x: number, y: number, t: number, on: boolean }

export type Fx = {
	field: Field.Field,
	words: { [number]: string }, -- Config.WORD by element id
	you: number?,
	ballPos: (e: number) -> (number?, number?),
	now: number,
	shake: number,
	zoom: number,
	focus: Vector2,
	tint: Color3,
	tintK: number,
	pause: number, -- s of hit pause left; Render holds the playback while > 0
	finalAt: number,
	seen: { [string]: boolean },
	parts: { Part },
	nextPart: number,
	rings: { Ring },
	beams: { Beam },
	arcs: { Arc },
	calls: { Call },
	wordViews: { Word },
	pops: { Pop },
	formula: { box: Frame, ball: ImageLabel, layer: ImageLabel, word: TextLabel, items: { GuiObject }, t: number },
	final: { band: Frame, big: TextLabel, bigScale: UIScale, sub: TextLabel },
	prompt: { box: Frame, bar: Frame },
	k: number, -- text scale of this canvas against the 680 px web field
	sound: (name: string) -> (),
	cam: (amount: number) -> (),
}

local Fx = {}

local function rnd(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function newText(parent: Instance, size: number, z: number): (TextLabel, UIStroke, UIScale)
	local l, s = Gui.text(parent, size, WHITE, { z = z })
	l.Visible = false
	local k = Instance.new("UIScale")
	k.Parent = l
	return l, s, k
end

function Fx.new(field: Field.Field, sound: (string) -> (), cam: (number) -> ()): Fx
	local parts, rings, beams, arcs, calls, wordViews, pops = {}, {}, {}, {}, {}, {}, {}
	local layer = field.fx
	for i = 1, NPARTS do
		local f = Gui.circle(layer, 3, WHITE, 3)
		f.Visible = false
		parts[i] = { f = f, x = 0, y = 0, vx = 0, vy = 0, life = 0, t = 0, r = 0, on = false }
	end
	for i = 1, NRINGS do
		local f, s = Gui.ring(layer, 10, 4, WHITE, 2)
		f.Visible = false
		rings[i] = { f = f, s = s, x = 0, y = 0, r0 = 0, r1 = 0, t = 0, life = 1, w = 1, on = false }
	end
	for i = 1, NBEAMS do
		local a = Gui.frame(layer, WHITE, 1)
		local b = Gui.frame(layer, WHITE, 2)
		Gui.round(a, 0.5)
		a.Visible, b.Visible = false, false
		beams[i] = { a = a, b = b, x0 = 0, y0 = 0, x1 = 0, y1 = 0, t = 0, life = 1, w = 1, on = false }
	end
	for i = 1, NARCS do
		local segs, core = {}, {}
		for j = 1, ARC_SEGS do
			segs[j] = Gui.frame(layer, WHITE, 2)
			core[j] = Gui.frame(layer, WHITE, 3)
			segs[j].Visible, core[j].Visible = false, false
		end
		arcs[i] = { segs = segs, core = core, x0 = 0, y0 = 0, x1 = 0, y1 = 0, t = 0, life = 1, on = false }
	end
	for i = 1, NCALLS do
		local l, s, k = newText(field.calls, 84, 20)
		calls[i] = { l = l, s = s, k = k, size = 84, x = 0, y = 0, t = 0, life = 1, on = false }
	end
	for i = 1, NWORDS do
		local l, s = newText(field.calls, 44, 18)
		s.Thickness = 6
		wordViews[i] = { l = l, s = s, e = 0, t = 0, on = false }
	end
	for i = 1, NPOPS do
		local l, s = newText(field.calls, 26, 17)
		s.Thickness = 4
		pops[i] = { l = l, s = s, x = 0, y = 0, t = 0, on = false }
	end
	-- formula: dark plate on the top of the field, "ball + terrain = WORD"
	local x0, y0, x1 = Field.rect(field)
	local box = Instance.new("Frame")
	box.BorderSizePixel = 0
	box.BackgroundColor3 = C("#0c0c22")
	box.Position = UDim2.fromOffset(x0 + 30, y0 + 10)
	box.Size = UDim2.fromOffset(x1 - x0 - 60, 92)
	box.ZIndex = 16
	box.Visible = false
	box.Parent = field.calls
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box
	local ball = Gui.ballImage(box, 0, 32, 17)
	ball.LayoutOrder = 1
	local plus = Gui.text(box, 54, WHITE, { font = Look.BOLD, stroke = 3, z = 17 })
	plus.Text, plus.LayoutOrder = "+", 2
	local lay = Gui.ballImage(box, 27, 32, 17)
	lay.LayoutOrder = 3
	local eq = Gui.text(box, 54, WHITE, { font = Look.BOLD, stroke = 3, z = 17 })
	eq.Text, eq.LayoutOrder = "=", 4
	local word = Gui.text(box, 40, WHITE, { stroke = 4, z = 17 })
	word.LayoutOrder = 5
	-- FINAL! band in the middle of the field
	local band = Instance.new("Frame")
	band.BorderSizePixel = 0
	band.BackgroundColor3 = C("#0c0c22")
	band.AnchorPoint = Vector2.new(0, 0.5)
	band.Size = UDim2.fromOffset(x1 - x0, 230)
	band.Position = UDim2.fromOffset(x0, field.h / 2)
	band.ZIndex = 15
	band.Visible = false
	band.Parent = field.calls
	local big, bigStroke, bigScale = newText(band, 100, 16)
	big.Text = "FINAL!"
	big.TextColor3 = C("#ffd63c")
	bigStroke.Thickness = 7
	bigStroke.Enabled = true
	big.Position = UDim2.new(0.5, 0, 0, 80)
	big.Visible = true
	local sub = Gui.text(band, 40, WHITE, { stroke = 5, z = 16 })
	sub.Text = "TAP ANYWHERE TO STEER"
	sub.Position = UDim2.new(0.5, 0, 0, 185)
	-- CHOOSE DIRECTION bar at the bottom of the field
	local _, _, _, y1 = Field.rect(field)
	local pbox = Instance.new("Frame")
	pbox.BorderSizePixel = 0
	pbox.BackgroundColor3 = C("#0c0c22")
	pbox.BackgroundTransparency = 0.28
	pbox.Position = UDim2.fromOffset(x0, y1 - 118)
	pbox.Size = UDim2.fromOffset(x1 - x0, 108)
	pbox.ZIndex = 15
	pbox.Visible = false
	pbox.Parent = field.calls
	local pt = Gui.text(pbox, 46, C("#ffe65a"), { stroke = 5, z = 16 })
	pt.Text = "CHOOSE DIRECTION!"
	pt.Position = UDim2.new(0.5, 0, 0, 36)
	local ps = Gui.text(pbox, 22, WHITE, { font = Look.BOLD, z = 16 })
	ps.Text = "Tap the field where your ball should fly"
	ps.Position = UDim2.new(0.5, 0, 0, 74)
	local bar = Instance.new("Frame")
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = C("#ffe65a")
	bar.Position = UDim2.fromOffset(40, 92)
	bar.Size = UDim2.fromOffset(x1 - x0 - 80, 8)
	bar.ZIndex = 16
	bar.Parent = pbox
	return {
		field = field,
		words = {},
		you = nil,
		ballPos = function()
			return nil, nil
		end,
		now = 0,
		shake = 0,
		zoom = 0,
		focus = Vector2.new(field.w / 2, field.h / 2),
		tint = WHITE,
		tintK = 0,
		pause = 0,
		finalAt = -9,
		seen = {},
		parts = parts,
		nextPart = 1,
		rings = rings,
		beams = beams,
		arcs = arcs,
		calls = calls,
		wordViews = wordViews,
		pops = pops,
		formula = { box = box, ball = ball, layer = lay, word = word, items = { ball, plus, lay, eq, word }, t = -9 },
		final = { band = band, big = big, bigScale = bigScale, sub = sub },
		prompt = { box = pbox, bar = bar },
		k = math.min(1, field.fw / 680),
		sound = sound,
		cam = cam,
	}
end

-- ---- primitives (field coordinates in cells, sizes in canvas px, like the web fx object) ----

function Fx.burst(
	self: Fx,
	x: number,
	y: number,
	col: Color3,
	n: number,
	speed: number?,
	life: number?,
	s0: number?,
	s1: number?
)
	local f = self.field
	local sp, lf, a0, a1 = speed or 260, life or 0.6, s0 or 3, s1 or 7
	local cx, cy = Field.px(f, x), Field.py(f, y)
	for _ = 1, n do
		local p = self.parts[self.nextPart]
		self.nextPart = self.nextPart % NPARTS + 1
		local a, v = math.random() * 2 * math.pi, rnd(0.25, 1) * sp
		p.x, p.y, p.vx, p.vy = cx, cy, math.cos(a) * v, math.sin(a) * v
		p.life, p.t, p.r, p.on = lf * rnd(0.6, 1.2), 0, math.random(a0, a1), true
		p.f.BackgroundColor3 = col
		p.f.Visible = true
	end
end

-- Particle with its own velocity (px/s), as the web gust and ambient sparks.
function Fx.spark(self: Fx, px: number, py: number, vx: number, vy: number, life: number, r: number, col: Color3)
	local p = self.parts[self.nextPart]
	self.nextPart = self.nextPart % NPARTS + 1
	p.x, p.y, p.vx, p.vy, p.life, p.t, p.r, p.on = px, py, vx, vy, life, 0, r, true
	p.f.BackgroundColor3 = col
	p.f.Visible = true
end

function Fx.ring(
	self: Fx,
	x: number,
	y: number,
	r0: number,
	r1: number,
	life: number,
	col: Color3,
	w: number,
	delay: number?
)
	for _, r in self.rings do
		if not r.on then
			r.on, r.x, r.y, r.r0, r.r1, r.life, r.w =
				true, Field.px(self.field, x), Field.py(self.field, y), r0, r1, life, w
			r.t = self.now + (delay or 0)
			r.s.Color = col
			return
		end
	end
end

function Fx.beam(self: Fx, x0: number, y0: number, x1: number, y1: number, col: Color3, w: number, life: number)
	local f = self.field
	for _, b in self.beams do
		if not b.on then
			b.on, b.t, b.life, b.w = true, self.now, life, w
			b.x0, b.y0, b.x1, b.y1 = Field.px(f, x0), Field.py(f, y0), Field.px(f, x1), Field.py(f, y1)
			b.a.BackgroundColor3 = col
			b.a.Visible, b.b.Visible = true, true
			return
		end
	end
end

function Fx.arc(self: Fx, x0: number, y0: number, x1: number, y1: number, col: Color3, life: number?)
	local f = self.field
	for _, a in self.arcs do
		if not a.on then
			a.on, a.t, a.life = true, self.now, life or 0.28
			a.x0, a.y0, a.x1, a.y1 = Field.px(f, x0), Field.py(f, y0), Field.px(f, x1), Field.py(f, y1)
			for _, s in a.segs do
				s.BackgroundColor3 = col
			end
			return
		end
	end
end

-- Big word on the field (web fx.callout): picks a free row near y, pops in with a bounce.
function Fx.callout(self: Fx, s: string, x: number, y: number, col: Color3, size: number, life: number?)
	local f = self.field
	local k = self.k
	local yy = Field.py(f, y)
	local x0, y0, _, y1 = Field.rect(f)
	local busy: { [number]: boolean } = {}
	for _, c in self.calls do
		if c.on then
			busy[math.floor(c.y)] = true
		end
	end
	local best: number? = nil
	local q = y0 + 120 * k
	while q < y1 - 40 * k do
		if not busy[math.floor(q)] and (best == nil or math.abs(q - yy) < math.abs((best :: number) - yy)) then
			best = q
		end
		q += 100 * k
	end
	if not best then
		return
	end
	for _, c in self.calls do
		if not c.on then
			c.on, c.t, c.life, c.y, c.x = true, self.now, life or 1.15, best :: number, Field.px(f, x)
			c.size = size * k
			c.l.Text = s
			c.l.TextColor3 = col
			c.l.TextSize = math.min(100, c.size)
			c.s.Thickness = math.max(4, c.size / 11)
			c.s.Enabled = true
			c.l.Visible = true
			c.l.Position = UDim2.fromOffset(math.max(x0, c.x), c.y)
			return
		end
	end
end

local function text(self: Fx, x: number, y: number, s: string, col: Color3)
	for _, p in self.pops do
		if not p.on then
			p.on, p.t, p.x, p.y = true, self.now, Field.px(self.field, x), Field.py(self.field, y)
			p.l.Text = s
			p.l.TextColor3 = col
			p.s.Enabled = true
			p.l.Visible = true
			return
		end
	end
end

-- Floating HP change over a ball.
function Fx.damage(self: Fx, x: number, y: number, delta: number)
	if delta < 0 then
		text(self, x, y - 1.2, tostring(delta), C("#ff463c"))
	elseif delta > 0 then
		text(self, x, y - 1.2, "+" .. delta, C("#46f078"))
	end
end

local function shake(self: Fx, v: number)
	self.shake = math.max(self.shake, v)
	self.cam(v / 48)
end

-- ---- events (web applyFx) ----

local function reaction(self: Fx, d: { [string]: any })
	local k = tostring(d.k or "")
	local col = Look.RXCOL[k] or C("#ffe15a")
	local power = if Look.BIG[k] then 1 else 0.75
	local x, y = d.x :: number, d.y :: number
	if not self.seen[k] and type(d.by) == "number" then
		self.seen[k] = true
		local layer = tostring(d.layer or "")
		local row = table.find(Rules.Config.TOP, layer)
		local fm = self.formula
		fm.t = self.now
		Gui.setBall(fm.ball, d.by, 32)
		fm.layer.Visible = row ~= nil
		if row then
			Gui.setBall(fm.layer, 26 + row, 32)
		end
		fm.word.Text = k
		fm.word.TextColor3 = col
		fm.word.TextSize = if #k > 9 then 32 else 40
	end
	Fx.callout(self, k .. "!", x, y, col, if power >= 0.8 then 84 else 72)
	shake(self, 15 * power)
	self.zoom = math.max(self.zoom, 0.05 * power)
	self.focus = Vector2.new(Field.px(self.field, x), Field.py(self.field, y))
	self.tint = col
	self.tintK = math.max(self.tintK, 0.22 * power)
	self.pause = math.max(self.pause, 0.12 * power)
	Fx.burst(self, x, y, col, 60, 520, 0.9, 4, 10)
	Fx.burst(self, x, y, WHITE, 26, 380, 0.6, 3, 6)
	Fx.ring(self, x, y, 40, 240, 0.45, col, 16)
	if k == "DEVOUR" then
		Fx.ring(self, x, y, 4 * CELL, 8, 0.45, C("#a05aff"), 16)
	end
	if type(d.pts) == "table" then
		for i = 2, #d.pts do
			local a, b = d.pts[i - 1], d.pts[i]
			Fx.arc(self, a[1], a[2], b[1], b[2], C("#78c8ff"), 0.42)
		end
	end
	if type(d.ends) == "table" then
		local rainbow = { "#ff5050", "#ffaa28", "#fff03c", "#50f078", "#3cbeff", "#8c6eff", "#ff6edc", "#ffffff" }
		for i, e in d.ends do
			Fx.beam(self, x, y, e[1], e[2], C(rainbow[(i - 1) % 8 + 1]), 18, 0.6)
		end
	end
	self.sound("reaction")
end

-- One rules event of Match "ev" (docs/net.md); the same picture as the web applyFx.
function Fx.event(self: Fx, kind: string, d: { [string]: any })
	local x, y = d.x, d.y
	if kind == "bump" then
		Fx.burst(self, x, y, C("#dce1ff"), 4, 120, 0.25, 2, 3)
	elseif kind == "hit" then
		Fx.burst(self, x, y, WHITE, 8, 240, 0.3, 2, 4)
		shake(self, 3.5)
		self.pause = math.max(self.pause, 0.05)
	elseif kind == "ko" then
		local c = Look.bright(d.e)
		Fx.burst(self, x, y, c, 34, 420, 0.8, 4, 9)
		Fx.burst(self, x, y, WHITE, 14, 300, 0.5, 3, 6)
		Fx.ring(self, x, y, 20, 120, 0.4, c, 10)
		Fx.callout(self, "KO!", x, y - 1.5, WHITE, 46, 0.8)
		shake(self, 9)
		self.pause = math.max(self.pause, 0.1)
	elseif kind == "power" then
		Fx.ring(self, x, y, 30, CELL * 4, 0.45, Look.bright(d.e), 12)
		Fx.burst(self, x, y, Look.light(d.e), 18, 340, 0.55, 3, 6)
		for _, w in self.wordViews do
			if not w.on then
				w.on, w.t, w.e = true, self.now, d.e
				w.l.Text = self.words[d.e] or ""
				w.l.TextColor3 = if d.e == Rules.Config.VOID then Look.NAMECOL[d.e + 1] else Look.light(d.e)
				w.l.TextSize = 44 * self.k
				w.s.Enabled = true
				w.l.Visible = true
				break
			end
		end
		self.sound("power")
	elseif kind == "strike" then
		Fx.arc(self, d.x0, d.y0, d.x1, d.y1, C("#ffe65a"))
		shake(self, 6)
		Fx.burst(self, d.x1, d.y1, C("#fff4aa"), 16, 300, 0.4, 2, 5)
	elseif kind == "wave" then
		Fx.beam(self, d.x0, d.y0, d.x1, d.y1, C("#3c8cff"), 40, 0.45)
		shake(self, 6)
	elseif kind == "quake" then
		for i = 0, 2 do
			Fx.ring(self, x, y, 20, (3.6 + i) * CELL, 0.5, C("#c88c50"), 16, i * 0.08)
		end
		Fx.burst(self, x, y, C("#aa7846"), 40, 380, 0.7, 4, 9)
		shake(self, 12)
	elseif kind == "gust" then
		local h = math.atan2(d.dy, d.dx)
		local f = self.field
		for _ = 1, 26 do
			local a, v = h + rnd(-0.6, 0.6), rnd(300, 700)
			Fx.spark(
				self,
				Field.px(f, x),
				Field.py(f, y),
				math.cos(a) * v,
				math.sin(a) * v,
				rnd(0.4, 0.7),
				math.random(2, 4),
				C("#dcfff0")
			)
		end
		Fx.ring(self, x, y, 20, 6 * CELL, 0.4, C("#a0f0d2"), 10)
	elseif kind == "magnet" then
		Fx.ring(self, x, y, 8 * CELL, 30, 0.5, C("#c8d2e6"), 10)
	elseif kind == "flash" then
		for _, e in d.ends or {} do
			Fx.beam(self, x, y, e[1], e[2], C("#fff0a0"), 16, 0.4)
		end
		self.tint = C("#fffad2")
		self.tintK = math.max(self.tintK, 0.3)
	elseif kind == "splat" then
		for _, s in d.spots or {} do
			Fx.burst(self, s[1], s[2], C("#ff6ec8"), 14, 260, 0.5, 4, 8)
			Fx.ring(self, s[1], s[2], 10, 1.9 * CELL, 0.3, C("#ff8cd2"), 8)
		end
	elseif kind == "crystal" then
		for _, e in d.ends or {} do
			Fx.beam(self, x, y, e[1], e[2], C("#50ffe6"), 18, 0.45)
			Fx.burst(self, e[1], e[2], C("#c8fffa"), 8, 220, 0.5, 3, 6)
		end
		shake(self, 6)
	elseif kind == "spores" then
		for _, s in d.spots or {} do
			Fx.ring(self, s[1], s[2], 1.8 * CELL, 6, P.sporeDelay, C("#bef050"), 8)
		end
		local bx, by = self.ballPos(Rules.Config.MUSHROOM)
		if bx and by then
			Fx.burst(self, bx, by, C("#c8fa64"), 16, 320, 0.5, 3, 5)
		end
	elseif kind == "spore" then
		Fx.burst(self, x, y, C("#c8fa64"), 18, 260, 0.5, 3, 7)
		Fx.ring(self, x, y, 10, 1.6 * CELL, 0.3, C("#dcff78"), 10)
	elseif kind == "hole" then
		Fx.ring(self, x, y, 5 * CELL, 10, 0.6, C("#9650ff"), 14)
	elseif kind == "gas" then
		Fx.ring(self, x, y, 20, P.gasR * CELL, 0.5, C("#b4d23c"), 14)
		Fx.burst(self, x, y, C("#c8e664"), 30, 260, 0.7, 4, 9)
	elseif kind == "sonic" then
		Fx.callout(self, "SONIC BOOM!", x, y - 2, C("#ff3caa"), 64, 0.8)
	elseif kind == "balance" then
		Fx.ring(self, x, y, P.balanceR * CELL, 20, 0.5, C("#f2f2f2"), 12)
		Fx.ring(self, x, y, 20, P.balanceR * CELL, 0.5, C("#262626"), 8, 0.1)
		Fx.callout(self, "BALANCE!", x, y - 2, C("#f2f2f2"), 64, 0.8)
	elseif kind == "slowtime" then
		self.tint = C("#5046c8")
		self.tintK = math.max(self.tintK, 0.35)
		Fx.callout(self, "SLOW TIME!", x, y - 2, C("#aab4ff"), 64, 0.9)
	elseif kind == "phase" then
		Fx.ring(self, x, y, 60, 10, 0.4, C("#c8beff"), 10)
		Fx.callout(self, "BOO!", x, y - 2, C("#e6e0ff"), 70, 0.7)
	elseif kind == "kaboom" then
		Fx.burst(self, x, y, C("#ffb43c"), 70, 640, 0.8, 5, 12)
		Fx.burst(self, x, y, C("#3a3a3a"), 30, 300, 0.9, 6, 12)
		Fx.ring(self, x, y, 20, P.bombR * CELL + 30, 0.4, C("#ffd27a"), 24)
		Fx.callout(self, "KABOOM!", x, y, C("#ffb43c"), 92, 0.9)
		shake(self, 16)
		self.tint = C("#ffb43c")
		self.tintK = math.max(self.tintK, 0.3)
		self.pause = math.max(self.pause, 0.1)
		self.sound("reaction")
	elseif kind == "bubbles" then
		Fx.burst(self, x, y, C("#bff5ff"), 20, 200, 0.5, 3, 6)
	elseif kind == "pop" then
		Fx.burst(self, x, y, C("#e6fbff"), 14, 220, 0.4, 2, 5)
		if (d.trap or -1) >= 0 then
			Fx.callout(self, "TRAPPED!", x, y - 1.5, C("#bff5ff"), 50, 0.7)
		end
	elseif kind == "glitch" then
		Fx.beam(self, d.x0, d.y0, x, y, C("#ff2bd6"), 12, 0.3)
		Fx.ring(self, x, y, 10, 6 * CELL, 0.4, C("#2bf0ff"), 12)
		Fx.callout(self, "GLITCH!", x, y - 2, C("#ff2bd6"), 70, 0.8)
		shake(self, 8)
	elseif kind == "rush" then
		Fx.burst(self, x, y, C("#ff6688"), 24, 300, 0.5, 3, 7)
		Fx.callout(self, "SUGAR RUSH!", x, y - 2, C("#ff7896"), 62, 0.8)
	elseif kind == "itsme" then
		Fx.ring(self, x, y, 20, 3 * CELL, 0.4, C("#ffe228"), 12)
		Fx.callout(self, "IT'S ME!", x, y - 2, C("#ffe228"), 64, 0.9)
		Fx.burst(self, x, y, C("#fff08c"), 24, 320, 0.5, 3, 6)
	elseif kind == "six" then
		Fx.ring(self, x, y, (d.r - 1) * CELL, (d.r + 0.6) * CELL, 0.45, C("#ff8c00"), 22)
		Fx.callout(self, tostring(d.word) .. "!", x, y - d.r, C("#ffb43c"), if d.word == "SIX" then 80 else 96, 0.8)
		shake(self, if d.word == "SIX" then 8 else 12)
	elseif kind == "rx" and type(x) == "number" then
		reaction(self, d)
	elseif kind == "final" then
		self.finalAt = self.now
		self.tint = C("#ffd63c")
		self.tintK = math.max(self.tintK, 0.3)
		shake(self, 10)
		self.sound("final")
	elseif kind == "steal" then
		if (d.n or 0) > 0 then
			Fx.ring(self, x, y, 20, P.stealR * CELL, 0.45, Look.bright(d.e), 14)
			Fx.burst(self, x, y, Look.bright(d.e), 30, 380, 0.7, 4, 8)
			if d.e == self.you then
				Fx.callout(self, "+" .. d.n .. " LAND!", x, y + 1.5, C("#ffe65a"), 56, 1)
			elseif d.v == self.you then
				Fx.callout(self, "LAND STOLEN!", x, y + 1.5, C("#ff7878"), 50, 1)
			end
		end
	elseif kind == "cut" then
		Fx.callout(self, "CUT OFF!", x, y, WHITE, 44, 0.9)
	elseif kind == "spawn" then
		Fx.ring(self, x, y, 70, 16, 0.35, Look.bright(d.e), 7)
	elseif kind == "launch" then
		local bd = self.field.board
		Fx.callout(self, "LAUNCH!", bd.ox + bd.gw / 2, bd.oy + bd.gh / 2, WHITE, 74, 0.7)
	elseif kind == "redirect" and d.e == self.you then
		Fx.ring(self, d.tx, d.ty, 70, 10, 0.4, WHITE, 8)
		Fx.beam(self, x, y, d.tx, d.ty, C("#fff4b4"), 8, 0.3)
	end
end

type Hot = { layer: string, n: number, cols: { Color3 }, v0: number, v1: number }
local HOT: { Hot } = {
	{ layer = "burn", n = 5, cols = { C("#ffd246"), C("#ff781e") }, v0 = -170, v1 = -70 },
	{ layer = "lava", n = 2, cols = { C("#ffa028"), C("#ff5a14") }, v0 = -120, v1 = -40 },
	{ layer = "toxic", n = 2, cols = { C("#d68cff"), C("#aaff5a") }, v0 = -60, v1 = -20 },
}

-- Hot terrain sparks and splashes under rolling balls (web ambient), called by Render ~30% of frames.
function Fx.ambient(
	self: Fx,
	hot: { [string]: { number } },
	balls: { { e: number, x: number, y: number, layer: string? } }
)
	local SPLASH = { bush = "#5ad678", water = "#96d2ff", ice = "#ebfaff", sand = "#f0d296", slime = "#ff8cd2" }
	for _, b in balls do
		local c = if b.layer then SPLASH[b.layer] else nil
		if c then
			Fx.burst(self, b.x, b.y, C(c), 3, 130, 0.3, 2, 4)
		end
	end
	local f = self.field
	for _, q in HOT do
		local list = hot[q.layer]
		if list and #list > 0 then
			for _ = 1, math.min(q.n, #list) do
				local c = list[math.random(1, #list)]
				local i, j = c % f.board.gw, c // f.board.gw
				Fx.spark(
					self,
					Field.px(f, f.board.ox + i + math.random()),
					Field.py(f, f.board.oy + j + math.random()),
					rnd(-30, 30),
					rnd(q.v0, q.v1),
					rnd(0.3, 0.6),
					math.random(2, 4),
					q.cols[math.random(1, 2)]
				)
			end
		end
	end
end

-- ---- per frame ----

local function updateCalls(self: Fx, frame: any?)
	local f = self.field
	local x0, _, x1 = Field.rect(f)
	for _, c in self.calls do
		if c.on then
			local u = self.now - c.t
			if u >= c.life then
				c.on = false
				c.l.Visible = false
			else
				local q = if u < 0.1 then 0.6 + 7 * u elseif u < 0.2 then 1.3 - 3 * (u - 0.1) else 1
				local s0 = c.size / c.l.TextSize
				local w = c.l.TextBounds.X * s0 * q
				local maxW = (x1 - x0) + 10
				if w > maxW then
					s0 *= maxW / w
					w = maxW
				end
				c.k.Scale = s0 * q
				local half = w / 2
				c.l.Position =
					UDim2.fromOffset(math.clamp(c.x, x0 + half - 4, math.max(x0 + half - 4, x1 - half + 4)), c.y)
				local al = math.min(1, (c.life - u) / 0.22)
				c.l.TextTransparency = 1 - al
				c.s.Transparency = 1 - al
			end
		end
	end
	for _, w in self.wordViews do
		if w.on then
			local u = (self.now - w.t) / 0.95
			local bx, by = self.ballPos(w.e)
			if u >= 1 or not bx then
				w.on = false
				w.l.Visible = false
			else
				local hw = math.min(300, w.l.TextBounds.X / 2 + 8)
				local px = math.clamp(Field.px(f, bx :: number), x0 + hw, math.max(x0 + hw, x1 - hw))
				local _, y0 = Field.rect(f)
				w.l.Position = UDim2.fromOffset(px, math.max(y0 + 40, Field.py(f, by :: number) - 92 * self.k - 28 * u))
				local al = math.min(1, (1 - u) * 3)
				w.l.TextTransparency = 1 - al
				w.s.Transparency = 1 - al
			end
		end
	end
	for _, p in self.pops do
		if p.on then
			local u = (self.now - p.t) / 0.8
			if u >= 1 then
				p.on = false
				p.l.Visible = false
			else
				p.l.Position = UDim2.fromOffset(p.x, p.y - 40 * u)
				local al = math.min(1, (1 - u) * 3)
				p.l.TextTransparency = 1 - al
				p.s.Transparency = 1 - al
			end
		end
	end
	-- formula
	local fm = self.formula
	local fu = (self.now - fm.t) / 1.5
	if fu >= 0 and fu < 1 then
		local al = math.max(0, math.min(1, fu * 10, (1 - fu) * 5))
		fm.box.Visible = true
		fm.box.BackgroundTransparency = 1 - al * 0.78
		for _, it in fm.items do
			if it:IsA("ImageLabel") then
				it.ImageTransparency = 1 - al
			elseif it:IsA("TextLabel") then
				it.TextTransparency = 1 - al
				local s = it:FindFirstChildOfClass("UIStroke")
				if s then
					s.Transparency = 1 - al
				end
			end
		end
	else
		fm.box.Visible = false
	end
	-- FINAL!
	local fin = self.final
	local fk = self.now - self.finalAt
	if fk < 2.2 then
		local q = if fk < 0.15 then 0.5 + fk / 0.15 * 0.8 elseif fk < 0.3 then 1.3 - (fk - 0.15) / 0.15 * 0.3 else 1
		local al = math.min(1, (2.2 - fk) / 0.4)
		fin.band.Visible = true
		fin.band.BackgroundTransparency = 1 - al * 0.6
		fin.bigScale.Scale = 1.5 * q * self.k
		fin.big.TextTransparency = 1 - al
		local bs = fin.big:FindFirstChildOfClass("UIStroke") :: UIStroke
		bs.Transparency = 1 - al
		fin.sub.Visible = self.you ~= nil
		local sa = al * math.min(1, fk * 3)
		fin.sub.TextTransparency = 1 - sa
		local ss = fin.sub:FindFirstChildOfClass("UIStroke") :: UIStroke
		ss.Transparency = 1 - sa
	else
		fin.band.Visible = false
	end
	-- CHOOSE DIRECTION
	local pr = self.prompt
	local on = frame ~= nil and self.you ~= nil and frame.pu > 0 and frame.t < frame.pu and not frame.final
	pr.box.Visible = on
	if on then
		local left = frame.pu - frame.t
		local _, _, x1b = Field.rect(f)
		pr.bar.Size = UDim2.fromOffset((x1b - x0 - 80) * math.clamp(left / P.promptLen, 0, 1), 8)
	end
end

function Fx.update(self: Fx, dt: number, frame: any?)
	self.now += dt
	local now = self.now
	for _, p in self.parts do
		if p.on then
			p.t += dt
			if p.t >= p.life then
				p.on = false
				p.f.Visible = false
			else
				p.x += p.vx * dt
				p.y += p.vy * dt
				local damp = 0.95 ^ (dt * 60)
				p.vx *= damp
				p.vy *= damp
				local u = p.t / p.life
				local r = math.max(1, p.r * (1 - u * 0.6))
				p.f.Position = UDim2.fromOffset(p.x, p.y)
				p.f.Size = UDim2.fromOffset(r * 2, r * 2)
				p.f.BackgroundTransparency = 1 - math.clamp(1.5 * (1 - u), 0, 1)
			end
		end
	end
	for _, r in self.rings do
		if r.on then
			local u = (now - r.t) / r.life
			if u >= 1 then
				r.on = false
				r.f.Visible = false
			elseif u >= 0 then
				r.f.Visible = true
				r.f.Position = UDim2.fromOffset(r.x, r.y)
				local rad = math.max(1, r.r0 + (r.r1 - r.r0) * (1 - (1 - u) ^ 2))
				Gui.setRing(r.f, r.s, rad, math.max(2, r.w * (1 - u)))
				r.s.Transparency = 1 - math.max(0, 1 - u * 0.6)
			end
		end
	end
	for _, b in self.beams do
		if b.on then
			local u = (now - b.t) / b.life
			if u >= 1 then
				b.on = false
				b.a.Visible, b.b.Visible = false, false
			else
				Gui.segment(b.a, b.x0, b.y0, b.x1, b.y1, math.max(2, b.w * (1 - u * 0.7)))
				Gui.segment(b.b, b.x0, b.y0, b.x1, b.y1, 3)
				local tr = 1 - math.max(0, 1 - u * 0.8)
				b.a.BackgroundTransparency, b.b.BackgroundTransparency = tr, tr
			end
		end
	end
	for _, a in self.arcs do
		if a.on then
			local u = (now - a.t) / a.life
			if u >= 1 then
				a.on = false
				for j = 1, ARC_SEGS do
					a.segs[j].Visible, a.core[j].Visible = false, false
				end
			else
				local dx, dy = a.x1 - a.x0, a.y1 - a.y0
				local d = math.max(1, math.sqrt(dx * dx + dy * dy))
				local n = math.clamp(math.floor(d / 34), 3, ARC_SEGS)
				local nx, ny = -dy / d, dx / d
				local px, py = a.x0, a.y0
				for j = 1, ARC_SEGS do
					local s, c = a.segs[j], a.core[j]
					if j <= n then
						local qx, qy
						if j == n then
							qx, qy = a.x1, a.y1
						else
							local f, o = j / n, rnd(-16, 16)
							qx, qy = a.x0 + dx * f + nx * o, a.y0 + dy * f + ny * o
						end
						Gui.segment(s, px, py, qx, qy, 11)
						Gui.segment(c, px, py, qx, qy, 3)
						s.Visible, c.Visible = true, true
						px, py = qx, qy
					else
						s.Visible, c.Visible = false, false
					end
				end
			end
		end
	end
	-- shake, zoom, tint decay like the web update()
	local f = dt * 60
	local f0 = self.field
	Field.view(f0, rnd(-self.shake, self.shake), rnd(-self.shake, self.shake), self.zoom, self.focus.X, self.focus.Y)
	self.shake *= 0.86 ^ f
	self.zoom *= 0.84 ^ f
	self.tintK *= 0.78 ^ f
	if self.shake < 0.2 then
		self.shake = 0
	end
	f0.tint.BackgroundColor3 = self.tint
	f0.tint.BackgroundTransparency = if self.tintK > 0.01 then 1 - self.tintK else 1
	self.pause = math.max(0, self.pause - dt)
	updateCalls(self, frame)
end

function Fx.destroy(_self: Fx) end

return Fx
