--!strict
-- In-match HUD: player cards in the top corners, land bar, round timer, power button, banners and hints.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Theme = require("./Theme")

local Hud = {}
Hud.__index = Hud

local HINTS: { [string]: string } = {
	aim = "Drag to aim",
	power = "Tap POWER!",
	react = "Hit terrain for reactions!",
	final = "FINAL — tap anywhere to steer",
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
	powerBtn: TextButton,
	powerFill: Frame,
	powerScale: UIScale,
	powerLabel: TextLabel,
	pulse: Tween?,
	banner: TextLabel,
	hint: TextLabel,
	hintArrow: TextLabel,
	hintToken: number,
	lost: { { number } },
	you: number?,
	roundEnds: number,
	input: (kind: number, dx: number?, dy: number?) -> (),
	ready: boolean,
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
		ready = false,
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
	-- power button, right bottom under the thumb
	local pb = Theme.button(
		gui,
		"",
		UDim2.fromOffset(200, 200),
		UDim2.new(1, -28, 1, -28),
		Theme.PANEL,
		nil,
		Vector2.new(1, 1)
	)
	pb.ClipsDescendants = true
	Theme.round(pb, 200)
	pb.Name = "Power"
	local fill = Theme.frame(pb, UDim2.fromScale(1, 0), UDim2.fromScale(0, 1), Theme.ACCENT, Vector2.new(0, 1))
	fill.ZIndex = 1
	self.powerFill = fill
	local pl = Theme.label(pb, "POWER", 38, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.3), { title = true })
	pl.ZIndex = 3
	self.powerLabel = pl
	self.powerBtn = pb
	self.powerScale = Instance.new("UIScale")
	self.powerScale.Parent = pb
	pb.Activated:Connect(function()
		input(Net.Input.power)
		if not reduced() then
			self.powerScale.Scale = 0.9
			TweenService:Create(self.powerScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)
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
		UDim2.new(1, -240, 1, -120),
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
	-- CHOOSE DIRECTION
	if f.pu >= 0 and f.pu > f.t then
		self.banner.Visible = true
		self.banner.Text = string.format("CHOOSE DIRECTION  %.1f", f.pu - f.t)
	elseif f.final then
		self.banner.Visible = true
		self.banner.Text = "FINAL!"
	elseif self.banner.Text ~= "" and (string.find(self.banner.Text, "CHOOSE") or self.banner.Text == "FINAL!") then
		self.banner.Visible = false
		self.banner.Text = ""
	end
	-- power button
	local mine = if self.you then info[self.you] else nil
	if mine then
		local ch = math.clamp(mine.charge, 0, 1)
		self.powerFill.Size = UDim2.fromScale(1, ch)
		local ready = ch >= 1
		if ready ~= self.ready then
			self.ready = ready
			if self.pulse then
				self.pulse:Cancel()
				self.pulse = nil
				self.powerScale.Scale = 1
			end
			self.powerLabel.Text = if ready then "POWER!" else "POWER"
			if ready and not reduced() then
				local t = TweenService:Create(
					self.powerScale,
					TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.12 }
				)
				self.pulse = t
				t:Play()
			end
		end
	end
end

function Hud.destroy(self: Hud)
	if self.pulse then
		self.pulse:Cancel()
	end
	self.gui:Destroy()
end

return Hud
