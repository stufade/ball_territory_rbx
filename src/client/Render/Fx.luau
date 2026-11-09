--!strict
-- Effects from Match "ev" events and HP changes: flashes, big words, floating numbers. Pooled, nothing is created per event.
local Board = require(script.Parent.Board)
local Palette = require(script.Parent.Palette)

local FLASHES = 24
local POPS = 14

type Flash = { part: Part, t: number, dur: number, r0: number, r1: number }
type Pop = {
	part: Part,
	gui: BillboardGui,
	label: TextLabel,
	t: number,
	dur: number,
	rise: number,
	base: CFrame?,
	active: boolean,
}

export type Fx = {
	board: Board.Board,
	words: { [string]: string }, -- Config.WORD by element id as string key
	flashes: { Flash },
	pops: { Pop },
	nextFlash: number,
	nextPop: number,
	root: Folder,
	shake: (amount: number) -> (),
	sound: (name: string) -> (),
}

local Fx = {}

local OFF = CFrame.new(0, -10000, 0)

function Fx.new(board: Board.Board, shake: (number) -> (), sound: (string) -> ()): Fx
	local root = Instance.new("Folder")
	root.Name = "Fx"
	root.Parent = board.folder
	local flashes, pops = {}, {}
	for i = 1, FLASHES do
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.CFrame = OFF
		p.Parent = root
		flashes[i] = { part = p, t = 0, dur = 0, r0 = 0, r1 = 0 }
	end
	for i = 1, POPS do
		local p = Instance.new("Part")
		p.Transparency = 1
		p.Size = Vector3.one
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.CFrame = OFF
		p.Parent = root
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromOffset(260, 70)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.Adornee = p
		g.Enabled = false
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextStrokeTransparency = 0
		l.Parent = g
		g.Parent = p
		pops[i] = { part = p, gui = g, label = l, t = 0, dur = 0, rise = 0, base = nil, active = false }
	end
	return {
		board = board,
		words = {},
		flashes = flashes,
		pops = pops,
		nextFlash = 1,
		nextPop = 1,
		root = root,
		shake = shake,
		sound = sound,
	}
end

function Fx.flash(self: Fx, x: number, y: number, color: Color3, r0: number, r1: number, dur: number)
	local f = self.flashes[self.nextFlash]
	self.nextFlash = self.nextFlash % FLASHES + 1
	f.t, f.dur, f.r0, f.r1 = 0, dur, r0 * self.board.cs, r1 * self.board.cs
	f.part.Color = color
	f.part.CFrame = Board.cframe(self.board, x, y, 0.8)
	f.part.Size = Vector3.one * f.r0
	f.part.Transparency = 0.2
end

-- Text over a world spot (field cells). size in studs-ish pixels height factor.
function Fx.text(self: Fx, x: number, y: number, text: string, color: Color3, scale: number, dur: number, rise: number)
	local p = self.pops[self.nextPop]
	self.nextPop = self.nextPop % POPS + 1
	p.t, p.dur, p.rise, p.active = 0, dur, rise * self.board.cs, true
	p.base = Board.cframe(self.board, x, y, 1.5)
	p.part.CFrame = p.base :: CFrame
	p.gui.Size = UDim2.fromOffset(260 * scale, 70 * scale)
	p.gui.Enabled = true
	p.label.Text = text
	p.label.TextColor3 = color
	p.label.TextTransparency = 0
	p.label.TextStrokeTransparency = 0
end

function Fx.damage(self: Fx, x: number, y: number, delta: number)
	if delta < 0 then
		Fx.text(self, x, y - 1, tostring(delta), Color3.fromRGB(255, 60, 60), 0.5, 0.8, 2)
	elseif delta > 0 then
		Fx.text(self, x, y - 1, "+" .. delta, Color3.fromRGB(90, 255, 120), 0.5, 0.9, 2)
	end
end

local function at(d: { [string]: any }): (number?, number?)
	local x = d.x or d.x1 or d.x0
	local y = d.y or d.y1 or d.y0
	if type(x) == "number" and type(y) == "number" then
		return x, y
	end
	return nil, nil
end

local SMALL_SPOT =
	{ strike = true, wave = true, quake = true, gust = true, magnet = true, flash = true, crystal = true }

-- One rules event of Match "ev".
function Fx.event(self: Fx, kind: string, d: { [string]: any })
	local x, y = at(d)
	if kind == "power" and x and y then
		local e = d.e
		local color = if type(e) == "number" then Palette.elementColor(e) else Color3.new(1, 1, 1)
		Fx.flash(self, x, y, color, 1.5, 5, 0.35)
		local word = if type(e) == "number" then self.words[tostring(e)] else nil
		if word then
			Fx.text(self, x, y, word, color, 1, 1.1, 2.5)
		end
		self.shake(0.25)
		self.sound("power")
	elseif kind == "rx" and x and y then
		Fx.flash(self, x, y, Color3.fromRGB(255, 255, 255), 2, 8, 0.5)
		Fx.text(self, x, y, tostring(d.k or ""), Color3.fromRGB(255, 225, 90), 1.5, 1.5, 3)
		self.shake(0.6)
		self.sound("reaction")
	elseif kind == "final" then
		Fx.text(
			self,
			self.board.ox + self.board.gw / 2,
			self.board.oy + self.board.gh / 2,
			"FINAL!",
			Color3.fromRGB(255, 90, 60),
			2,
			1.6,
			1
		)
		self.shake(0.5)
		self.sound("final")
	elseif (kind == "hit" or kind == "bump") and x and y then
		Fx.flash(self, x, y, Color3.fromRGB(255, 240, 200), 0.6, 2.2, 0.2)
	elseif kind == "ko" and x and y then
		Fx.flash(self, x, y, Color3.fromRGB(255, 120, 60), 1, 6, 0.5)
		self.shake(0.4)
	elseif SMALL_SPOT[kind] and x and y then
		Fx.flash(self, x, y, Color3.fromRGB(255, 255, 255), 1, 3.5, 0.3)
	end
end

function Fx.update(self: Fx, dt: number)
	for _, f in self.flashes do
		if f.dur > 0 then
			f.t += dt
			local k = f.t / f.dur
			if k >= 1 then
				f.dur = 0
				f.part.CFrame = OFF
			else
				f.part.Size = Vector3.one * (f.r0 + (f.r1 - f.r0) * k)
				f.part.Transparency = 0.2 + 0.8 * k
			end
		end
	end
	for _, p in self.pops do
		if p.active then
			p.t += dt
			local k = p.t / p.dur
			if k >= 1 then
				p.active = false
				p.part.CFrame = OFF
				p.gui.Enabled = false
			else
				p.part.CFrame = (p.base :: CFrame) * CFrame.new(0, p.rise * k, 0)
				local fade = math.max(0, (k - 0.6) / 0.4)
				p.label.TextTransparency = fade
				p.label.TextStrokeTransparency = fade
			end
		end
	end
end

function Fx.destroy(self: Fx)
	self.root:Destroy()
end

return Fx
