--!strict
-- In-match HUD: player cards in the top corners, land bar, round timer, power button, banners and hints.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Theme = require("./Theme")

local Hud = {}
Hud.__index = Hud

local buildPower: (self: any, gui: Frame, e: number) -> ()

local HINTS: { [string]: string } = {
	aim = "Drag to aim",
	power = "Tap POWER!",
	react = "Hit terrain for reactions!",
	-- final: the board canvas shows FINAL! TAP ANYWHERE TO STEER (Render.Fx)
}

type Power = {
	btn: TextButton,
	fill: Frame,
	blink: Frame,
	press: Frame,
	word: TextLabel,
	wordStroke: UIStroke,
	sub: TextLabel,
	subStroke: UIStroke,
	scale: UIScale,
	pressedAt: number,
	ready: boolean,
}

type Card = {
	seat: Net.Seat,
	idx: number,
	hp: TextLabel,
	hpFill: Frame,
	hearts: { Frame },
	elem: TextLabel,
}

export type Hud = {
	gui: Frame,
	start: Net.MatchStart,
	cards: { [number]: Card },
	landBar: Frame,
	segs: { [number]: Frame },
	timer: TextLabel,
	power: Power?,
	banner: TextLabel,
	hint: TextLabel,
	hintArrow: TextLabel,
	hintToken: number,
	lost: { { number } },
	you: number?,
	roundEnds: number,
	input: (kind: number, dx: number?, dy: number?) -> (),
}

local function reduced(): boolean
	return GuiService.ReducedMotionEnabled
end

local function popText(l: TextLabel, from: number)
	if reduced() then
		return
	end
	local s = l:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Scale = from
	s.Parent = l
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function heartsFor(seat: Net.Seat, mode: string, lost: { { number } }): number
	if mode ~= "duel" then
		return 0
	end
	return Config.DUEL_SIZE - #(lost[seat.side + 1] or {})
end

local function makeCard(gui: Frame, seat: Net.Seat, idx: number, mode: string): Card
	-- duel: side 0 left, side 1 right. ffa: seats 1,3 left, 2,4 right, stacked.
	local right = if mode == "duel" then seat.side == 1 else idx % 2 == 0
	local slot = if mode == "duel" then 0 else math.floor((idx - 1) / 2)
	local w, h = 250, 112
	local f = Theme.frame(
		gui,
		UDim2.fromOffset(w, h),
		UDim2.new(if right then 1 else 0, if right then -12 else 12, 0, 12 + slot * (h + 6)),
		Theme.PANEL,
		Vector2.new(if right then 1 else 0, 0)
	)
	f.BackgroundTransparency = 0.15
	Theme.round(f, 16)
	Theme.stroke(f, 4, Theme.SEAT[if mode == "duel" then seat.side + 1 else (idx - 1) % 4 + 1])
	local portrait =
		Theme.frame(f, UDim2.fromOffset(64, 64), UDim2.fromOffset(if right then w - 76 else 12, 8), Theme.NEUTRAL)
	Theme.round(portrait, 12)
	if seat.userId > 0 then
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(
					seat.userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)
			if ok and portrait.Parent then
				local i = Instance.new("ImageLabel")
				i.BackgroundTransparency = 1
				i.Size = UDim2.fromScale(1, 1)
				i.Image = img
				i.Parent = portrait
				Theme.round(i, 12)
			end
		end)
	else
		Theme.label(portrait, "BOT", 22, UDim2.fromScale(1, 1), nil, { title = true })
	end
	local tx = if right then 8 else 84
	local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local textW = w - 96
	Theme.label(f, seat.name, 22, UDim2.fromOffset(textW, 26), UDim2.fromOffset(tx, 6), { align = align })
	local elem = Theme.label(
		f,
		Config.TITLE[seat.e] or "",
		22,
		UDim2.fromOffset(textW, 26),
		UDim2.fromOffset(tx, 34),
		{ align = align, color = Theme.ACCENT }
	)
	local hearts = {}
	if mode == "duel" then
		for i = 1, Config.DUEL_SIZE do
			local hx = if right then w - 84 - 22 - (i - 1) * 26 else 84 + (i - 1) * 26
			local dot = Theme.frame(f, UDim2.fromOffset(22, 22), UDim2.fromOffset(hx, 66), Theme.BAD)
			Theme.round(dot, 22)
			Theme.stroke(dot, 2)
			table.insert(hearts, dot)
		end
	end
	local bar = Theme.frame(f, UDim2.new(1, -24, 0, 20), UDim2.new(0, 12, 1, -28), Theme.BG)
	Theme.round(bar, 8)
	local fill = Theme.frame(bar, UDim2.fromScale(1, 1), nil, Theme.GOOD)
	Theme.round(fill, 8)
	local hp = Theme.label(bar, "", 16, UDim2.fromScale(1, 1))
	return { seat = seat, idx = idx, hp = hp, hpFill = fill, hearts = hearts, elem = elem }
end

local function plateText(parent: Instance, font: Font, size: number, y: number, stroke: number): (TextLabel, UIStroke)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = font
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.AnchorPoint = Vector2.new(0, 0.5)
	t.Position = UDim2.fromOffset(104, y)
	t.Size = UDim2.new(1, -112, 0, size)
	t.ZIndex = 6
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.Parent = t
	local s = Instance.new("UIStroke")
	s.Color = Look.INK
	s.Thickness = stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t, s
end

local function fillFrame(parent: Instance, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- Web drawButton: border plate, dark element colour, charge fill, ball art, power word, CHARGING / READY, TAP!
function buildPower(self: Hud, gui: Frame, e: number)
	local btn = Instance.new("TextButton")
	btn.Name = "Power"
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = Color3.fromHex("#464a78")
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Size = UDim2.fromOffset(Look.POWER_W, Look.POWER_H)
	btn.Position = UDim2.new(1, -Look.POWER_PAD, 1, -Look.POWER_PAD)
	btn.Parent = gui
	local inner = fillFrame(btn, Look.dark(e), 2)
	inner.Position = UDim2.fromOffset(4, 4)
	inner.Size = UDim2.new(1, -8, 1, -8)
	inner.ClipsDescendants = true
	local shade = fillFrame(inner, Color3.new(0, 0, 0), 3)
	shade.BackgroundTransparency = 0.5
	local fill = fillFrame(inner, if e == Config.VOID then Color3.fromHex("#6a32c8") else Look.col(e), 4)
	fill.Size = UDim2.fromScale(0, 1)
	local blink = fillFrame(inner, Color3.new(1, 1, 1), 5)
	blink.BackgroundTransparency = 0.72
	blink.Visible = false
	local press = fillFrame(inner, Color3.new(1, 1, 1), 5)
	press.Visible = false
	local ball = Instance.new("ImageLabel")
	ball.BackgroundTransparency = 1
	ball.Image = Art.BALLS
	ball.ImageRectSize = Vector2.new(Art.BALL, Art.BALL)
	ball.ImageRectOffset = Art.ballRect(e)
	local bs = Art.BALL * 36 / Art.BALL_R
	ball.Size = UDim2.fromOffset(bs, bs)
	ball.AnchorPoint = Vector2.new(0.5, 0.5)
	ball.Position = UDim2.new(0, 50, 0.5, 0)
	ball.ZIndex = 6
	ball.Parent = inner
	local word, ws = plateText(inner, Look.FONT, 44, 36, 4)
	word.Text = Config.WORD[e] or "POWER"
	local sub, ss = plateText(inner, Look.BOLD, 21, 76, 3)
	sub.Text = "CHARGING"
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	local p: Power = {
		btn = btn,
		fill = fill,
		blink = blink,
		press = press,
		word = word,
		wordStroke = ws,
		sub = sub,
		subStroke = ss,
		scale = scale,
		pressedAt = -9,
		ready = false,
	}
	self.power = p
	btn.Activated:Connect(function()
		self.input(Net.Input.power)
		p.pressedAt = os.clock()
		if not reduced() then
			scale.Scale = 0.92
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
end

function Hud.new(
	canvas: Frame,
	start: Net.MatchStart,
	lost: { { number } },
	input: (number, number?, number?) -> ()
): Hud
	local gui = Theme.frame(canvas, UDim2.fromScale(1, 1), nil, Color3.new())
	gui.BackgroundTransparency = 1
	gui.Name = "Hud"
	local self: Hud = {
		gui = gui,
		start = start,
		cards = {},
		segs = {},
		lost = lost,
		you = start.you,
		roundEnds = start.round,
		input = input,
		hintToken = 0,
	} :: any
	for i, seat in start.seats do
		self.cards[seat.e] = makeCard(gui, seat, i, start.mode)
	end
	-- land bar (top center)
	local bar = Theme.frame(gui, UDim2.fromOffset(300, 28), UDim2.new(0.5, 0, 0, 12), Theme.BG, Vector2.new(0.5, 0))
	Theme.round(bar, 10)
	Theme.stroke(bar, 3)
	bar.ClipsDescendants = true
	self.landBar = bar
	for i, seat in start.seats do
		local seg = Theme.frame(
			bar,
			UDim2.fromScale(0, 1),
			nil,
			Theme.SEAT[if start.mode == "duel" then seat.side + 1 else (i - 1) % 4 + 1]
		)
		self.segs[seat.e] = seg
	end
	self.timer = Theme.label(
		gui,
		"",
		52,
		UDim2.fromOffset(200, 60),
		UDim2.new(0.5, 0, 0, 44),
		{ title = true, anchor = Vector2.new(0.5, 0) }
	)
	-- power button: the web drawButton plate in the right column the match camera keeps free
	if start.you then
		buildPower(self, gui, start.you)
	end
	-- banners
	self.banner = Theme.label(
		gui,
		"",
		64,
		UDim2.new(1, 0, 0, 90),
		UDim2.fromScale(0, 0.22),
		{ title = true, color = Theme.ACCENT }
	)
	self.banner.Visible = false
	self.hint = Theme.label(
		gui,
		"",
		40,
		UDim2.new(0.8, 0, 0, 60),
		UDim2.fromScale(0.5, 0.78),
		{ title = true, anchor = Vector2.new(0.5, 0.5) }
	)
	self.hint.Visible = false
	self.hintArrow = Theme.label(
		gui,
		"▶",
		70,
		UDim2.fromOffset(80, 80),
		UDim2.new(1, -(Look.POWER_W + Look.POWER_PAD + 6), 1, -(Look.POWER_PAD + Look.POWER_H / 2)),
		{ title = true, anchor = Vector2.new(1, 0.5), color = Theme.ACCENT }
	)
	self.hintArrow.Visible = false
	Hud.refreshHearts(self)
	return self
end

function Hud.refreshHearts(self: Hud)
	for _, c in self.cards do
		local alive = heartsFor(c.seat, self.start.mode, self.lost)
		for i, dot in c.hearts do
			dot.BackgroundColor3 = if i <= alive then Theme.BAD else Theme.BG
		end
	end
end

function Hud.setLost(self: Hud, lost: { { number } })
	self.lost = lost
	Hud.refreshHearts(self)
end

function Hud.showHint(self: Hud, k: string)
	local text = HINTS[k]
	if not text then
		return
	end
	self.hintToken += 1
	local token = self.hintToken
	self.hint.Text = text
	self.hint.Visible = true
	popText(self.hint, 0.6)
	self.hintArrow.Visible = k == "power"
	task.delay(4, function()
		if self.hintToken == token and self.hint.Parent then
			self.hint.Visible = false
			self.hintArrow.Visible = false
		end
	end)
end

function Hud.showBanner(self: Hud, text: string, seconds: number)
	self.banner.Text = text
	self.banner.Visible = true
	popText(self.banner, 0.5)
	local token = self.hintToken + 1000 * os.clock()
	self.banner:SetAttribute("t", token)
	task.delay(seconds, function()
		if self.banner.Parent and self.banner:GetAttribute("t") == token then
			self.banner.Visible = false
		end
	end)
end

function Hud.onFrame(self: Hud, f: any)
	local total = math.max(1, self.start.w * self.start.h)
	local x = 0
	local info: { [number]: any } = {}
	for _, b in f.balls do
		info[b.e] = b
	end
	for _, seat in self.start.seats do
		local b = info[seat.e]
		local c = self.cards[seat.e]
		local seg = self.segs[seat.e]
		if b and c and seg then
			local w = math.clamp(b.cnt / total, 0, 1)
			seg.Position = UDim2.fromScale(x, 0)
			seg.Size = UDim2.fromScale(w, 1)
			x += w
			local hpv = math.max(0, b.hp)
			c.hp.Text = if b.alive then tostring(hpv) else "OUT"
			c.hpFill.Size = UDim2.fromScale(if b.alive then math.clamp(hpv / 100, 0, 1) else 0, 1)
			c.elem.Text = (Config.TITLE[seat.e] or "") .. string.format(" %d%%", math.floor(b.cnt / total * 100 + 0.5))
		end
	end
	-- round timer from match time
	local left = math.max(0, self.roundEnds - f.t)
	self.timer.Text = tostring(math.ceil(left))
	self.timer.TextColor3 = if left <= 10 then Theme.BAD else Theme.TEXT
	-- CHOOSE DIRECTION and FINAL! are drawn on the board canvas (Render.Fx), like the web drawCalls.
	-- power button
	local p = self.power
	local mine = if self.you then info[self.you] else nil
	if p and mine then
		local ch = math.clamp(mine.charge, 0, 1)
		local ready = mine.alive and ch >= 1
		local pressed = os.clock() - p.pressedAt < 0.35
		p.fill.Size = UDim2.fromScale(ch, 1)
		p.fill.BackgroundTransparency = if ready then 0 else 0.3
		p.btn.BackgroundColor3 = if ready or pressed then Look.FRAME else Color3.fromHex("#464a78")
		p.press.Visible = pressed
		local ink = pressed
		p.word.TextColor3 = if ink then Look.INK else Color3.new(1, 1, 1)
		p.sub.TextColor3 = p.word.TextColor3
		p.wordStroke.Enabled = not ink
		p.subStroke.Enabled = not ink
		p.sub.Text = if pressed
			then "TAP!"
			elseif not mine.alive then "RESPAWNING"
			elseif ready then "READY, TAP!"
			else "CHARGING"
		p.ready = ready
	end
end

-- Blink of a ready power plate (web: white 28% while sin(t*14) > 0); called every render frame.
function Hud.step(self: Hud)
	local p = self.power
	if p then
		p.blink.Visible = p.ready and not reduced() and math.sin(os.clock() * 14) > 0
	end
end

function Hud.destroy(self: Hud)
	self.gui:Destroy()
end

return Hud
