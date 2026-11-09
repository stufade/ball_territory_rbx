--!strict
-- In-match HUD in the Ball vs Ball layout: the board sits in the middle (Render/Cam), each side column has the plates
-- of its players (portrait, name, hearts = balls left, current ball, land %, charge) above their avatars, the right
-- column has the power button at the bottom. Top centre: land bar with the round timer. Round end overlay (web
-- drawRoundEnd). Nothing is placed over the board or the Roblox topbar (left of ctx.topbar.X, above ctx.topbar.Y).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Screen = require("../Screen")
local Theme = require("./Theme")

local Hud = {}

local HINTS: { [string]: string } = {
	aim = "DRAG TO AIM",
	power = "TAP POWER!",
	react = "HIT TERRAIN FOR REACTIONS!",
	-- final: the board canvas shows FINAL! TAP ANYWHERE TO STEER (Render.Fx)
}

local PLATE_W = 300
local DUEL_H, FFA_H = 150, 100

type Power = {
	holder: Frame,
	holderScale: UIScale,
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

type Plate = {
	seat: Net.Seat,
	frame: Frame,
	scale: UIScale,
	right: boolean,
	slot: number,
	hearts: { TextLabel },
	pct: TextLabel,
	charge: Frame,
	medal: Frame?,
	medalText: TextLabel?,
}

export type Ctx = {
	seats: { [number]: Net.Seat },
	mySide: number,
	score: { number },
	lost: { { number } },
	you: number?,
	rounds: number,
}

export type Hud = {
	gui: Frame,
	start: Net.MatchStart,
	plates: { [number]: Plate }, -- by element
	landBar: Frame,
	segs: { [number]: Frame },
	timer: TextLabel,
	power: Power?,
	hint: TextLabel,
	hintArrow: TextLabel,
	hintToken: number,
	lost: { { number } },
	score: { number },
	you: number?,
	roundEnds: number,
	final: boolean,
	timeLeft: number,
	overlay: Frame?,
	mid: number,
	input: (kind: number, dx: number?, dy: number?) -> (),
}

local function reduced(): boolean
	return GuiService.ReducedMotionEnabled
end

local function seatColor(seat: Net.Seat): Color3
	return Theme.SEAT[seat.side % 4 + 1]
end

local function portrait(parent: Instance, seat: Net.Seat, d: number, pos: UDim2)
	local disc = Theme.disc(parent, d, Theme.PANEL, pos)
	Theme.stroke(disc, 4, seatColor(seat))
	if seat.userId > 0 then
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(
					seat.userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)
			if ok and disc.Parent then
				local i = Instance.new("ImageLabel")
				i.BackgroundTransparency = 1
				i.Size = UDim2.fromScale(1, 1)
				i.Image = img
				i.Parent = disc
				Theme.round(i, 999)
			end
		end)
	else
		-- the name already says BOT: the portrait shows a robot face
		local face = Theme.text(disc, "🤖", 44, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), {
			anchor = Vector2.new(0.5, 0.5),
			stroke = 0,
		})
		face.TextScaled = true
	end
end

local function nameOf(self: Hud, seat: Net.Seat): string
	if seat.e == self.you then
		return "YOU"
	end
	-- several bots in a 4-player match: number them by stand
	if seat.userId <= 0 and self.start.mode == "ffa" then
		return `BOT {seat.side + 1}`
	end
	return string.upper(seat.name)
end

-- x of a box of width w, mirrored on the right plates
local function mx(right: boolean, x: number, w: number): number
	return if right then PLATE_W - x - w else x
end

local function makePlate(self: Hud, seat: Net.Seat, slot: number, right: boolean): Plate
	local duel = self.start.mode ~= "ffa"
	local h = if duel then DUEL_H else FFA_H
	local f = Theme.frame(self.gui, UDim2.fromOffset(PLATE_W, h), nil, Theme.PANEL)
	f.Name = "Plate" .. seat.side
	f.BackgroundTransparency = 0.3
	f.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
	Theme.round(f, 16)
	local sc = Instance.new("UIScale")
	sc.Parent = f
	local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local hearts: { TextLabel } = {}
	local pct: TextLabel
	local charge: Frame
	local medal: Frame?, medalText: TextLabel?
	local e = seat.e
	if duel then
		portrait(f, seat, 76, UDim2.fromOffset(mx(right, 8, 76) + 38, 44))
		Theme.text(
			f,
			nameOf(self, seat),
			28,
			UDim2.fromOffset(196, 34),
			UDim2.fromOffset(mx(right, 96, 196), 6),
			{ color = seatColor(seat), align = align }
		)
		for i = 1, Config.DUEL_SIZE do
			local x = mx(right, 96 + (i - 1) * 34, 32)
			table.insert(hearts, Theme.heart(f, 32, UDim2.fromOffset(x, 44), true))
		end
		Theme.ball(f, e, 52, UDim2.fromOffset(mx(right, 20, 52) + 26, 118))
		Theme.text(
			f,
			Config.TITLE[e] or "",
			24,
			UDim2.fromOffset(212, 28),
			UDim2.fromOffset(mx(right, 82, 212), 88),
			{ color = Theme.nameColor(e), align = align }
		)
		pct = Theme.text(
			f,
			"0%",
			32,
			UDim2.fromOffset(100, 34),
			UDim2.fromOffset(mx(right, 82, 100), 112),
			{ align = align }
		)
		local bar = Theme.frame(f, UDim2.fromOffset(104, 12), UDim2.fromOffset(mx(right, 188, 104), 124), Theme.INK)
		Theme.round(bar, 6)
		charge = Theme.frame(bar, UDim2.fromScale(0, 1), nil, Look.bright(e))
		Theme.round(charge, 6)
	else
		portrait(f, seat, 64, UDim2.fromOffset(mx(right, 8, 64) + 32, 40))
		local m = Theme.disc(f, 30, Theme.MEDAL[1], UDim2.fromOffset(mx(right, 50, 30) + 15, 70))
		Theme.stroke(m, 2)
		medal = m
		medalText = Theme.text(m, "1", 22, UDim2.fromScale(1, 1), nil, { color = Theme.INK, stroke = 0 })
		Theme.text(
			f,
			nameOf(self, seat),
			24,
			UDim2.fromOffset(210, 30),
			UDim2.fromOffset(mx(right, 84, 210), 4),
			{ color = seatColor(seat), align = align }
		)
		Theme.ball(f, e, 38, UDim2.fromOffset(mx(right, 84, 38) + 19, 54))
		pct = Theme.text(
			f,
			"0%",
			30,
			UDim2.fromOffset(90, 32),
			UDim2.fromOffset(mx(right, 128, 90), 38),
			{ align = align }
		)
		Theme.text(
			f,
			Config.TITLE[e] or "",
			20,
			UDim2.fromOffset(80, 24),
			UDim2.fromOffset(mx(right, 214, 80), 42),
			{ color = Theme.nameColor(e), align = align }
		)
		local bar = Theme.frame(f, UDim2.fromOffset(204, 10), UDim2.fromOffset(mx(right, 84, 204), 80), Theme.INK)
		Theme.round(bar, 5)
		charge = Theme.frame(bar, UDim2.fromScale(0, 1), nil, Look.bright(e))
		Theme.round(charge, 5)
	end
	if seat.e == self.you then
		Theme.stroke(f, 3, Theme.FRAME)
	end
	return {
		seat = seat,
		frame = f,
		scale = sc,
		right = right,
		slot = slot,
		hearts = hearts,
		pct = pct,
		charge = charge,
		medal = medal,
		medalText = medalText,
	}
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
-- Lives in a holder at the bottom of the right column; the holder's UIScale fits it to the column.
local function buildPower(self: Hud, gui: Frame, e: number)
	local holder = Theme.clear(
		gui,
		UDim2.fromOffset(Look.POWER_W + Look.POWER_PAD, Look.POWER_H + Look.POWER_PAD),
		UDim2.fromScale(1, 1),
		Vector2.new(1, 1)
	)
	holder.Name = "PowerHolder"
	local hs = Instance.new("UIScale")
	hs.Parent = holder
	local btn = Instance.new("TextButton")
	btn.Name = "Power"
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = Color3.fromHex("#464a78")
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Size = UDim2.fromOffset(Look.POWER_W, Look.POWER_H)
	btn.Position = UDim2.new(1, -Look.POWER_PAD, 1, -Look.POWER_PAD)
	btn.Parent = holder
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
		holder = holder,
		holderScale = hs,
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
	score: { number },
	input: (number, number?, number?) -> ()
): Hud
	local gui = Theme.clear(canvas, UDim2.fromScale(1, 1))
	gui.Name = "Hud"
	local self: Hud = {
		gui = gui,
		start = start,
		plates = {},
		segs = {},
		lost = lost,
		score = score,
		you = start.you,
		roundEnds = start.round,
		input = input,
		hintToken = 0,
		final = false,
		mid = 460,
		timeLeft = start.round,
	} :: any
	-- plates: duel side 0 left, 1 right; ffa sides 0, 2 left and 1, 3 right (Stand1, Stand3 / Stand2, Stand4)
	for _, seat in start.seats do
		local right = seat.side % 2 == 1
		local slot = if start.mode == "ffa" then seat.side // 2 else 0
		self.plates[seat.e] = makePlate(self, seat, slot, right)
	end
	-- land bar with the round timer (web: #f0f0fc frame, #2e325c inside, BRIGHT[e] shares)
	local bar = Theme.frame(gui, UDim2.fromOffset(400, 36), UDim2.new(0.5, 0, 0, 6), Look.FRAME, Vector2.new(0.5, 0))
	bar.Name = "LandBar"
	Theme.round(bar, 8)
	local inner = Theme.frame(bar, UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3), Color3.fromHex("#2e325c"))
	inner.ClipsDescendants = true
	Theme.round(inner, 6)
	self.landBar = bar
	for _, seat in start.seats do
		self.segs[seat.e] = Theme.frame(inner, UDim2.fromScale(0, 1), nil, Look.bright(seat.e))
	end
	self.timer = Theme.text(bar, "", 30, UDim2.new(0, 120, 1, 4), UDim2.fromScale(0.5, 0.5), {
		anchor = Vector2.new(0.5, 0.5),
		stroke = 4,
		z = 3,
	})
	if start.you then
		buildPower(self, gui, start.you)
	end
	self.hint = Theme.text(gui, "", 34, UDim2.fromOffset(460, 44), UDim2.new(0.5, 0, 1, -70), {
		anchor = Vector2.new(0.5, 0.5),
		color = Theme.YELLOW_TXT,
		stroke = 4,
	})
	self.hint.Visible = false
	self.hintArrow = Theme.text(gui, "▶", 70, UDim2.fromOffset(80, 80), nil, {
		anchor = Vector2.new(1, 0.5),
		color = Theme.YELLOW,
		bold = true,
	})
	self.hintArrow.Visible = false
	Hud.refreshHearts(self)
	return self
end

-- Places the plates, bar and power button for the canvas size (design px) and the topbar corner.
function Hud.layout(self: Hud, canvas: Vector2, topbar: Vector2)
	local col = canvas.X * Screen.COLUMN
	local fitPlate = math.min(1, (col - 12) / PLATE_W)
	local y0 = math.max(topbar.Y, 10)
	for _, p in self.plates do
		p.scale.Scale = fitPlate
		local h = if self.start.mode == "ffa" then FFA_H else DUEL_H
		local y = y0 + p.slot * (h + 8) * fitPlate
		p.frame.Position = if p.right then UDim2.new(1, -6, 0, y) else UDim2.fromOffset(6, y)
	end
	local mid = canvas.X - 2 * col
	self.mid = mid
	self.landBar.Size = UDim2.fromOffset(math.clamp(mid - 24, 240, 440), 36)
	local pw = self.power
	if pw then
		-- a narrow column narrows the plate but keeps its height (>= 80 px on a 390 px phone); scale only below 220
		local w = math.clamp(col - Look.POWER_PAD - 4, 220, Look.POWER_W)
		local k = math.min(1, col / (220 + Look.POWER_PAD + 4))
		pw.btn.Size = UDim2.fromOffset(w, Look.POWER_H)
		pw.holder.Size = UDim2.fromOffset(w + Look.POWER_PAD, Look.POWER_H + Look.POWER_PAD)
		pw.holderScale.Scale = k
		self.hintArrow.Position = UDim2.new(1, -(w + Look.POWER_PAD) * k, 1, -(Look.POWER_H / 2 + 14) * k)
	end
	self.hint.Size = UDim2.fromOffset(math.max(240, mid - 20), 44)
end

function Hud.refreshHearts(self: Hud)
	for _, p in self.plates do
		local alive = Config.DUEL_SIZE - #(self.lost[p.seat.side + 1] or {})
		for i, h in p.hearts do
			h.TextColor3 = if i <= alive then Theme.HEART else Theme.RING
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
	Theme.pop(self.hint, 0, 0.6)
	self.hintArrow.Visible = k == "power"
	task.delay(4, function()
		if self.hintToken == token and self.hint.Parent then
			self.hint.Visible = false
			self.hintArrow.Visible = false
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
	local order = {}
	for _, seat in self.start.seats do
		local b = info[seat.e]
		local p = self.plates[seat.e]
		local seg = self.segs[seat.e]
		if b and p and seg then
			local w = math.clamp(b.cnt / total, 0, 1)
			seg.Position = UDim2.fromScale(x, 0)
			seg.Size = UDim2.fromScale(w, 1)
			x += w
			p.pct.Text = string.format("%d%%", math.floor(b.cnt / total * 100 + 0.5))
			local ch = if b.alive then math.clamp(b.charge, 0, 1) else 0
			p.charge.Size = UDim2.fromScale(ch, 1)
			p.charge.BackgroundColor3 = if ch >= 1 then Color3.new(1, 1, 1) else Look.bright(seat.e)
			p.frame.BackgroundTransparency = if b.alive then 0.3 else 0.6
			table.insert(order, { e = seat.e, cnt = b.cnt })
		end
	end
	-- ffa places by land
	table.sort(order, function(a, b)
		return a.cnt > b.cnt
	end)
	for i, o in order do
		local p = self.plates[o.e]
		if p.medal and p.medalText then
			p.medal.BackgroundColor3 = Theme.MEDAL[i] or Theme.MUTED
			p.medalText.Text = tostring(i)
		end
	end
	-- round timer m:ss from match time; red blink in the last 10 s, yellow in the final
	local left = math.max(0, self.roundEnds - f.t)
	self.timeLeft = left
	self.final = bit32.band(f.st or 0, 1) ~= 0
	local c = math.ceil(left)
	self.timer.Text = string.format("%d:%02d", c // 60, c % 60)
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

-- Every render frame: ready-power blink (web: white 28% while sin(t*14) > 0), timer colour.
function Hud.step(self: Hud, _dt: number?)
	local p = self.power
	local t = os.clock()
	if p then
		p.blink.Visible = p.ready and not reduced() and math.sin(t * 14) > 0
	end
	local blink = self.timeLeft <= 10 and math.floor(t * 2) % 2 == 0
	self.timer.TextColor3 = if blink
		then Color3.fromHex("#ff5a46")
		elseif self.final then Theme.YELLOW_TXT
		else Theme.TEXT
end

local function cross(parent: Instance, d: number, delay: number)
	for _, rot in { 45, -45 } do
		local l =
			Theme.frame(parent, UDim2.fromOffset(d, 14), UDim2.fromScale(0.5, 0.5), Theme.BAD, Vector2.new(0.5, 0.5))
		l.Rotation = rot
		l.ZIndex = 4
		Theme.round(l, 7)
		Theme.pop(l, delay, 0)
	end
end

-- Web drawRoundEnd over the field: ROUND n, ROUND WON/LOST, both balls with land %, crown on the winner, a red
-- cross on the loser, who picks next. Stays until the next State closes the HUD.
function Hud.roundEnd(self: Hud, data: Net.RoundEnd, ctx: Ctx)
	if self.overlay then
		self.overlay:Destroy()
	end
	-- covers the board only: the side columns stay visible, the avatars cheer and hang their heads there
	local W = self.mid
	local o = Theme.frame(self.gui, UDim2.new(0, W, 1, 0), UDim2.fromScale(0.5, 0), Color3.fromHex("#0b0c22"))
	o.AnchorPoint = Vector2.new(0.5, 0)
	o.Name = "RoundEnd"
	o.ZIndex = 20
	o.BackgroundTransparency = 1
	self.overlay = o
	TweenService:Create(o, TweenInfo.new(0.25), { BackgroundTransparency = 0.06 }):Play()
	local mine = ctx.mySide
	local w = data.win
	local rounds = math.max(ctx.rounds, 1)
	local spectator = self.you == nil
	local title = if w < 0
		then "DRAW!"
		elseif spectator then (Config.TITLE[if w == 0 then data.a else data.b] or "") .. " WINS"
		elseif w == mine then "ROUND WON!"
		else "ROUND LOST"
	local tcol = if w < 0 then Theme.TEXT elseif spectator or w == mine then Theme.YELLOW_TXT else Theme.BAD_TXT
	local top = Vector2.new(0.5, 0)
	Theme.text(o, `ROUND {rounds}`, 28, UDim2.fromOffset(W - 20, 34), UDim2.fromOffset(W / 2, 40), {
		anchor = top,
		color = Theme.DIM,
	})
	local tl = Theme.text(o, title, 60, UDim2.fromOffset(W - 20, 70), UDim2.fromOffset(W / 2, 74), {
		anchor = top,
		color = tcol,
		stroke = 6,
	})
	Theme.pop(tl, 0.05, 0.3)
	local nameBySide: { [number]: string } = {}
	for _, seat in self.start.seats do
		nameBySide[seat.side] = if seat.e == self.you then "YOU" else string.upper(seat.name)
	end
	local cw = W * 0.46
	for side = 0, 1 do
		local e = if side == 0 then data.a else data.b
		local p = if side == 0 then data.pa else data.pb
		local cx = if side == 0 then W * 0.26 else W * 0.74
		local cell = Theme.clear(o, UDim2.fromOffset(cw, 280), UDim2.fromOffset(cx, 160), top)
		local ball = Theme.ball(cell, e, 110, UDim2.fromOffset(cw / 2, 108))
		if w ~= side then
			ball.ImageTransparency = 0.45
			cross(ball, 120, 0.5)
		else
			local c = Theme.crown(cell, 84, UDim2.fromOffset(cw / 2, 24))
			Theme.pop(c, 0.3, 0)
		end
		Theme.text(
			cell,
			string.format("%d%%", math.floor(p + 0.5)),
			40,
			UDim2.fromOffset(cw, 46),
			UDim2.fromOffset(0, 172)
		)
		Theme.text(cell, nameBySide[side] or "", 24, UDim2.fromOffset(cw, 30), UDim2.fromOffset(0, 220), {
			color = if side == mine and not spectator then Theme.YELLOW_TXT else Theme.DIM,
		})
	end
	Theme.text(o, "VS", 40, UDim2.fromOffset(80, 46), UDim2.fromOffset(W / 2, 244), {
		anchor = top,
		color = Theme.MUTED,
	})
	local done = false
	for _, l in data.lost do
		if #l >= Config.DUEL_SIZE then
			done = true
		end
	end
	local next = if done
		then "DUEL OVER"
		elseif w < 0 then "BOTH CHOOSE THE NEXT BALL"
		elseif not spectator and w ~= mine then "YOU CHOOSE YOUR NEXT BALL"
		else `{nameBySide[1 - w] or "RIVAL"} CHOOSES NEXT`
	local nl = Theme.text(o, next, 30, UDim2.fromOffset(W - 20, 40), UDim2.new(0, W / 2, 1, -58), {
		anchor = top,
	})
	Theme.pop(nl, 0.9, 0.6)
end

function Hud.destroy(self: Hud)
	self.gui:Destroy()
end

return Hud
