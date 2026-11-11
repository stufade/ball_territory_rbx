--!strict
-- Login reward window (M3.1, U2). Days 1-6 in a 3x2 grid on the left, day 7 a big card on the right with a live VOID:
-- a turning black hole (purple glow, swirling arcs, rings and specks pulled into the core, the VOID ball inside),
-- "DAY 7: VOID" and how many days are left. Opening: the window pops, the cards pop up one by one, day 7 last with a
-- flash, CLAIM! pulses. Taken days are dimmed with a green tick; today has a yellow frame and pulses.
-- CLAIM! -> Action daily; the server's answer rebuilds with `claim`: the card pops, coins/crystals fly from it into
-- a copy of the counter at its plaza place and it rolls up; VOID day: the hole flares, rays and confetti.
-- Opens by itself once a day on the plaza (Wallet), or from the DAILY button. Motion off with ReducedMotion.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cheer = require("./Cheer")
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local TOP_MID = V2(0.5, 0)

local Daily = {}

export type Ctx = {
	canvas: Vector2,
	topbar: Vector2?,
	act: (verb: string, arg: number?) -> (),
	close: () -> (),
	fx: Cheer.Ctx,
}

-- panel 884x480: header to y 96, grid of days 1-6 at (20, 100), CLAIM under it, day 7 on the right
local PW, PH = 884, 480
local CW, CH, GAP = 140, 134, 12
local GX, GY = 20, 100
local GRID_W = 3 * CW + 2 * GAP
local BX = GX + GRID_W + 20
local BW = PW - 20 - BX
local BH = PH - 14 - GY
local VOID_E = 13
local VOID_DEEP = Color3.fromHex("#14062a")
local VOID_GLOW = Color3.fromHex("#8a3cff")
local VOID_PINK = Color3.fromHex("#e05cff")
local VOID_EDGE = Color3.fromHex("#e9c8ff")

-- centre of the card of day i inside the panel
local function cardAt(i: number): (number, number)
	if i == 7 then
		return BX + BW / 2, GY + BH / 2
	end
	local col, row = (i - 1) % 3, (i - 1) // 3
	return GX + col * (CW + GAP) + CW / 2, GY + row * (CH + GAP) + CH / 2
end

local function pulse(fx: Cheer.Ctx, o: GuiObject, amp: number, speed: number)
	if Theme.reduced() then
		return
	end
	local s = Theme.scaleOf(o)
	table.insert(fx.frames, function()
		if o.Parent then
			s.Scale = 1 + amp * math.sin(os.clock() * speed)
		end
	end)
end

-- slide up 26 px while it pops (the stagger of the opening)
local function rise(o: GuiObject, delay: number)
	if Theme.reduced() then
		return
	end
	local p = o.Position
	o.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + 26)
	TweenService:Create(o, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay), {
		Position = p,
	}):Play()
	Theme.pop(o, delay, 0.4)
end

local function tick(f: GuiObject, d: number, z: number): Frame
	local t = Theme.disc(f, d, Theme.GOOD, UDim2.fromScale(0.5, 0.5))
	t.Name = "Got"
	t.ZIndex = z
	Theme.stroke(t, 3, Theme.INK)
	Theme.label(t, "✓", math.floor(d * 0.66), UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		color = Theme.INK,
		stroke = 0,
		z = z + 1,
	})
	return t
end

local function shade(f: GuiObject, radius: number)
	local s = Theme.frame(f, UDim2.fromScale(1, 1), nil, Theme.INK)
	s.Name = "Shade"
	s.BackgroundTransparency = 0.45
	s.ZIndex = 5
	Theme.round(s, radius)
end

-- coins / crystals of a gift: icons at y `cy`, amount under them
local function goods(f: Frame, c: Net.DayCard, w: number, cy: number, icon: number, size: number, ay: number)
	local both = c.coins ~= nil and c.crystals ~= nil
	local d = if both then math.floor(icon * 0.78) else icon
	local dx = if both then d * 0.56 else 0
	local amount = ""
	if c.coins then
		Money.icon(f, "coins", d, UDim2.fromOffset(w / 2 - dx, cy))
		amount = Money.fmt(c.coins)
	end
	if c.crystals then
		Money.icon(f, "crystals", d, UDim2.fromOffset(w / 2 + dx, cy))
		amount = if both then `{amount} +{c.crystals}` else Money.fmt(c.crystals)
	end
	local col = if c.coins then Money.COIN else Money.GEM
	Theme.label(f, amount, size, UDim2.new(1, -8, 0, size + 4), UDim2.new(0.5, 0, 0, ay), {
		anchor = TOP_MID,
		color = col,
	}).Name =
		"Amount"
end

-- a small card of days 1-6
local function card(panel: Frame, c: Net.DayCard, i: number, fx: Cheer.Ctx): Frame
	local x, y = cardAt(i)
	local f = Theme.frame(panel, UDim2.fromOffset(CW, CH), UDim2.fromOffset(x, y), Theme.SLOT, MID)
	f.Name = `Day{i}`
	Theme.round(f, 16)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromHex("#363b72"), Theme.SLOT)
	g.Parent = f
	Theme.stroke(f, if c.today then 5 else 3, if c.today then Theme.YELLOW else Theme.INK).Name = "Edge"
	Theme.label(f, `DAY {i}`, 22, UDim2.new(1, -10, 0, 24), UDim2.new(0.5, 0, 0, 6), {
		anchor = TOP_MID,
		color = if c.today then Theme.YELLOW_TXT else Theme.DIM,
	})
	goods(f, c, CW, 56, 50, 26, 84)
	if c.trials then
		Theme.label(f, "+1 TRIAL", 20, UDim2.new(1, -8, 0, 22), UDim2.new(0.5, 0, 0, 110), {
			anchor = TOP_MID,
			color = Theme.GOOD_TXT,
			bold = true,
		})
	end
	if c.got then
		shade(f, 16)
		tick(f, 50, 6)
	elseif c.today then
		pulse(fx, f, 0.045, 5)
	end
	return f
end

-- The live black hole, diameter ~300, centred in `parent` at (cx, cy). Returns its box (flare it with its UIScale).
local function hole(parent: Frame, cx: number, cy: number, fx: Cheer.Ctx): Frame
	local still = Theme.reduced()
	local box = Theme.clear(parent, UDim2.fromOffset(300, 300), UDim2.fromOffset(cx, cy), MID)
	box.Name = "Hole"
	local C = UDim2.fromScale(0.5, 0.5)
	-- glow: stacked translucent discs stand in for a radial gradient
	local glow = Theme.clear(box, UDim2.fromScale(1, 1), C, MID)
	glow.Name = "Glow"
	for k = 0, 8 do
		local g = Theme.disc(glow, 300 - k * 20, if k > 5 then VOID_PINK else VOID_GLOW, C, 0.9)
		g.ZIndex = 2
	end
	-- infalling rings: big and faint -> small and bright, then gone
	local rings: { Frame } = {}
	for k = 1, 3 do
		local r = Theme.ring(box, 200, VOID_EDGE, 2, C)
		r.Name = "Fall"
		r.ZIndex = 3
		rings[k] = r
	end
	-- swirling arcs (a gradient on the ring's stroke shows a crescent), faster nearer the core
	local arcs: { { f: Frame, w: number } } = {}
	for k, a in { { 220, 12, 50 }, { 180, 10, 85 }, { 144, 7, 140 } } do
		for half = 0, 1 do
			local r = Theme.clear(box, UDim2.fromOffset(a[1], a[1]), C, MID)
			r.Name = "Arc"
			r.ZIndex = 4
			r.Rotation = half * 180 + k * 40
			Theme.round(r, 999)
			local s = Theme.stroke(r, a[2], VOID_PINK)
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, VOID_GLOW),
				ColorSequenceKeypoint.new(0.6, VOID_PINK),
				ColorSequenceKeypoint.new(1, VOID_EDGE),
			})
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.8),
				NumberSequenceKeypoint.new(0.88, 0),
				NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = s
			table.insert(arcs, { f = r, w = a[3] })
		end
	end
	-- specks spiralling in
	local specks: { { f: Frame, a: number, r: number } } = {}
	if not still then
		for k = 1, 26 do
			local d = 4 + (k % 4)
			local p = Theme.disc(box, d, VOID_EDGE, C)
			p.Name = "Speck"
			p.ZIndex = 5
			table.insert(specks, { f = p, a = math.random() * math.pi * 2, r = 60 + math.random() * 90 })
		end
	end
	-- the core: black disc, bright photon ring, the VOID ball turning inside
	local halo = Theme.ring(box, 112, VOID_EDGE, 2, C)
	halo.Name = "Halo"
	halo.ZIndex = 6
	local core = Theme.disc(box, 100, Color3.new(0, 0, 0), C)
	core.Name = "Core"
	core.ZIndex = 7
	Theme.stroke(core, 4, VOID_PINK)
	local ball = Theme.ball(core, VOID_E, 84, C)
	ball.Name = "VoidBall"
	ball.ZIndex = 8
	if still then
		for k, r in rings do
			r.Size = UDim2.fromOffset(140 + 50 * k, 140 + 50 * k)
			local s = r:FindFirstChildOfClass("UIStroke") :: UIStroke
			s.Transparency = 0.5 + 0.12 * k
		end
		return box
	end
	local glowScale = Theme.scaleOf(glow)
	local haloStroke = halo:FindFirstChildOfClass("UIStroke") :: UIStroke
	local t = 0
	table.insert(fx.frames, function(dt: number)
		if not box.Parent then
			return
		end
		t += dt
		glowScale.Scale = 1 + 0.06 * math.sin(t * 2.4)
		haloStroke.Transparency = 0.35 + 0.3 * math.sin(t * 3.1)
		for _, a in arcs do
			a.f.Rotation += a.w * dt
		end
		ball.Rotation = -t * 25
		for k, r in rings do
			local u = (t / 2.4 + (k - 1) / 3) % 1 -- 0 big and faint -> 1 at the core
			local d = 290 - 190 * (u * u)
			r.Size = UDim2.fromOffset(d, d)
			local s = r:FindFirstChildOfClass("UIStroke") :: UIStroke
			s.Transparency = 1 - 0.5 * math.sin(math.pi * u)
		end
		for _, p in specks do
			-- faster and quicker to turn as they near the core
			p.r -= (18 + 2600 / p.r) * dt
			p.a += (0.8 + 140 / p.r) * dt
			if p.r < 52 then
				p.r = 130 + math.random() * 20
				p.a = math.random() * math.pi * 2
			end
			p.f.Position = UDim2.new(0.5, math.cos(p.a) * p.r, 0.5, math.sin(p.a) * p.r * 0.8)
			p.f.BackgroundTransparency = math.clamp((p.r - 70) / 80, 0, 0.9)
		end
	end)
	return box
end

-- the big card of day 7: VOID on the first cycle, coins and crystals later
local function big(panel: Frame, c: Net.DayCard, pos: number, fx: Cheer.Ctx): Frame
	local x, y = cardAt(7)
	local isVoid = c.ball ~= nil
	local f = Theme.frame(panel, UDim2.fromOffset(BW, BH), UDim2.fromOffset(x, y), VOID_DEEP, MID)
	f.Name = "Day7"
	f.ClipsDescendants = true
	Theme.round(f, 20)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromHex("#2a0f52"), Color3.fromHex("#07020f"))
	g.Parent = f
	Theme.stroke(f, if c.today then 5 else 4, if c.today then Theme.YELLOW else VOID_GLOW).Name = "Edge"
	local name = if isVoid then (Rules.Config.TITLE[c.ball :: number] or "VOID") else "BIG PRIZE"
	local title = Theme.label(f, `DAY 7: {name}`, 34, UDim2.new(1, -16, 0, 38), UDim2.new(0.5, 0, 0, 10), {
		anchor = TOP_MID,
		color = if isVoid then Theme.nameColor(c.ball :: number) else Theme.YELLOW,
		stroke = 4,
		z = 10,
	})
	title.Name = "Title"
	if isVoid then
		hole(f, BW / 2, 176, fx)
		Theme.label(f, "LEGENDARY BALL", 22, UDim2.new(1, -16, 0, 26), UDim2.new(0.5, 0, 0, 292), {
			anchor = TOP_MID,
			color = Theme.DIM,
			bold = true,
			z = 10,
		})
	else
		goods(f, c, BW, 160, 120, 40, 240)
	end
	-- days left to day 7 (pos = today's day of the cycle)
	local left = 7 - pos
	local txt, col
	if c.got then
		txt, col = if isVoid then "IT'S YOURS!" else "TAKEN!", Theme.GOOD_TXT
	elseif left <= 0 then
		txt, col = "TODAY!", Theme.YELLOW
	elseif left == 1 then
		txt, col = "TOMORROW!", Theme.YELLOW_TXT
	else
		txt, col = `IN {left} DAYS`, Theme.YELLOW_TXT
	end
	local l = Theme.label(f, txt, 32, UDim2.new(1, -16, 0, 36), UDim2.new(0.5, 0, 1, -12), {
		anchor = V2(0.5, 1),
		color = col,
		stroke = 4,
		z = 10,
	})
	l.Name = "Left"
	if c.got then
		tick(f, 54, 11).Position = UDim2.new(1, -40, 0, 84)
	elseif c.today then
		pulse(fx, f, 0.025, 4)
	end
	return f
end

local function fmtLeft(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d:%02d", s // 3600, s // 60 % 60, s % 60)
end

-- Claim: coins/crystals fly from the card (px, py) into a copy of the plaza counter, which rolls up as they land.
local function fly(layer: Frame, v: Net.ProfileView, gift: Net.DayCard, px: number, py: number, ctx: Ctx)
	local cv = ctx.canvas
	local L = Theme.plaza(cv, ctx.topbar or V2(0, 0))
	local k = 0
	for _, cur in { "coins", "crystals" } do
		local n = (gift :: any)[cur] :: number?
		if not n then
			continue
		end
		k += 1
		local y = L.moneyY[k]
		local total = ((v :: any)[cur] or n) :: number
		local box = Theme.frame(layer, UDim2.fromOffset(L.moneyW, L.moneyH), UDim2.fromOffset(L.right, y), Theme.PANEL)
		box.AnchorPoint = V2(1, 0)
		box.Name = if cur == "coins" then "FlyCoins" else "FlyCrystals"
		box.ZIndex = 30
		Theme.round(box, L.moneyH / 2)
		Theme.stroke(box, 3, Theme.INK)
		Money.icon(box, cur, 40, UDim2.fromOffset(20, L.moneyH / 2)).ZIndex = 31
		local roll = Money.roll(total - n)
		local t =
			Theme.label(box, Money.fmt(total - n), 28, UDim2.fromOffset(L.moneyW - 54, 30), UDim2.new(1, -14, 0.5, 0), {
				anchor = V2(1, 0.5),
				align = Enum.TextXAlignment.Right,
				color = if cur == "coins" then Money.COIN else Money.GEM,
				z = 31,
			})
		t.Name = "Value"
		roll.label, roll.box = t, box
		local tx, ty = L.right - L.moneyW + 20, y + L.moneyH / 2
		if Theme.reduced() then
			t.Text = Money.fmt(total)
			continue
		end
		Theme.pop(box, 0, 0.6)
		local count = 8
		local landed = 0
		for j = 1, count do
			local ic = Money.icon(layer, cur, 34, UDim2.fromOffset(px, py))
			ic.Name = "Flying"
			ic.ZIndex = 32
			local sx, sy = px + math.random(-40, 40), py + math.random(-30, 30)
			local cx, cy = (sx + tx) / 2 + math.random(-120, 40), math.min(sy, ty) - 120
			local tt = -0.25 - 0.06 * j - 0.15 * (k - 1)
			table.insert(ctx.fx.frames, function(dt: number)
				if not ic.Parent then
					return
				end
				tt += dt
				if tt < 0 then
					ic.Visible = false
					return
				end
				ic.Visible = true
				local u = math.min(1, tt / 0.6)
				local e = u * u
				local a, b = (1 - e) * (1 - e), 2 * (1 - e) * e
				local c = e * e
				ic.Position = UDim2.fromOffset(a * sx + b * cx + c * tx, a * sy + b * cy + c * ty)
				Theme.scaleOf(ic).Scale = 1.2 - 0.4 * u
				if u >= 1 then
					ic:Destroy()
					landed += 1
					Money.target(roll, total - n + n * landed / count)
				end
			end)
		end
		table.insert(ctx.fx.frames, function(dt: number)
			if box.Parent then
				Money.step(roll, dt)
			end
		end)
	end
end

-- Builds the screen into `parent` (cleared). claim: the server's answer just came (the card of that day pops).
function Daily.build(parent: Frame, v: Net.ProfileView, ctx: Ctx, claim: any?)
	parent:ClearAllChildren()
	local d = v.daily
	if not d then
		return
	end
	local intro = claim == nil
	local cv = ctx.canvas
	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local panel = Theme.frame(parent, UDim2.fromOffset(PW, PH), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "DailyPanel"
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	if intro then
		Theme.pop(panel, 0, 0.6)
	end
	Theme.label(panel, "DAILY REWARD", 46, UDim2.fromOffset(600, 52), UDim2.new(0.5, 0, 0, 12), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
		stroke = 5,
	})
	Theme.label(panel, "COME BACK EVERY DAY · MISSED DAYS DON'T RESET", 22, UDim2.fromOffset(700, 26), nil, {
		anchor = TOP_MID,
		color = Theme.DIM,
		bold = true,
	}).Position =
		UDim2.new(0.5, 0, 0, 64)
	local close =
		Theme.button(panel, "X", UDim2.fromOffset(56, 56), UDim2.new(1, -10, 0, 10), Theme.BAD, nil, 30, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)
	local cards = d.cards
	local today: Frame? = nil
	for i, c in cards do
		local f = if i == 7 then big(panel, c, d.pos, ctx.fx) else card(panel, c, i, ctx.fx)
		if intro then
			if i == 7 then
				rise(f, 0.62)
				-- a flash as the VOID card lands
				if not Theme.reduced() then
					local x, y = cardAt(7)
					local fl = Theme.frame(panel, UDim2.fromOffset(BW, BH), UDim2.fromOffset(x, y), VOID_EDGE, MID)
					fl.Name = "Flash"
					fl.ZIndex = 15
					fl.BackgroundTransparency = 1
					Theme.round(fl, 20)
					task.delay(0.78, function()
						if fl.Parent then
							fl.BackgroundTransparency = 0.3
							TweenService:Create(fl, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
						end
					end)
					task.delay(1.4, function()
						fl:Destroy()
					end)
				end
			else
				rise(f, 0.12 + 0.07 * i)
			end
		end
		if c.today then
			today = f
		end
	end
	local cx = GX + GRID_W / 2
	if d.ready then
		-- the pulse goes on a wrapper, the press keeps the button's own scale (U1)
		local wrap = Theme.clear(panel, UDim2.fromOffset(260, 72), UDim2.new(0, cx, 1, -14), V2(0.5, 1))
		wrap.Name = "ClaimWrap"
		local b = Theme.button(wrap, "CLAIM!", UDim2.fromOffset(260, 72), nil, Theme.GO, nil, 40)
		b.Name = "Claim"
		if intro then
			Theme.pop(wrap, 0.95, 0.4)
		end
		if not Theme.reduced() then
			local s = Theme.scaleOf(wrap)
			local t0 = os.clock() + 1.3
			table.insert(ctx.fx.frames, function()
				if b.Parent and os.clock() > t0 and not b:GetAttribute("Pressed") then
					s.Scale = 1 + 0.05 * math.sin((os.clock() - t0) * 6)
				end
			end)
		end
		local sent = false
		b.Activated:Connect(function()
			if not sent then
				sent = true
				b:SetAttribute("Pressed", true)
				ctx.act(Net.Action.daily)
			end
		end)
	else
		local left = Theme.label(panel, "", 24, UDim2.fromOffset(GRID_W - 150, 30), UDim2.new(0, GX, 1, -40), {
			anchor = V2(0, 0.5),
			color = Theme.YELLOW_TXT,
			align = Enum.TextXAlignment.Left,
		})
		left.Name = "Next"
		local function upd()
			local secs = 86400 - workspace:GetServerTimeNow() % 86400
			left.Text = `NEXT IN {fmtLeft(secs)}`
		end
		upd()
		table.insert(ctx.fx.frames, function()
			if left.Parent then
				upd()
			end
		end)
		local ok =
			Theme.button(panel, "OK", UDim2.fromOffset(140, 64), UDim2.new(0, GX + GRID_W, 1, -14), Theme.GO, nil, 36)
		ok.Name = "Ok"
		ok.AnchorPoint = V2(1, 1)
		if claim then
			Theme.pop(ok, 1.2, 0.4)
		end
		ok.Activated:Connect(ctx.close)
	end
	if claim and today then
		-- the day just taken: pop, flash and burst in its colour, the goods fly into the counter
		local f = today :: Frame
		local gift = (claim.gift or {}) :: any
		local isVoid = gift.ball ~= nil
		local e = if isVoid then gift.ball else VOID_E
		local ix, iy = cardAt(claim.pos)
		local px, py = ix + (cv.X - PW) / 2, iy + (cv.Y - PH) / 2
		local layer = Theme.clear(parent, UDim2.fromScale(1, 1))
		layer.Name = "ClaimFx"
		layer.ZIndex = 20
		if not Theme.reduced() then
			local s = Theme.scaleOf(f)
			local amp = if isVoid then 0.12 else 0.25
			local t = 0
			table.insert(ctx.fx.frames, function(dt: number)
				t += dt
				if f.Parent and t < 0.5 then
					s.Scale = 1 + amp * math.sin(math.pi * t / 0.5)
				end
			end)
			local hb = f:FindFirstChild("Hole") :: Frame?
			if hb then
				-- the hole swallows the light, then lets it out
				local hs = Theme.scaleOf(hb)
				local th = 0
				table.insert(ctx.fx.frames, function(dt: number)
					th += dt
					if hb.Parent and th < 1.2 then
						hs.Scale = 1 + 0.35 * math.sin(math.pi * th / 1.2)
					end
				end)
			end
		end
		if isVoid then
			Cheer.rays(layer, ctx.fx, e, px, py, 520).ZIndex = 1
			Cheer.confetti(layer, ctx.fx)
		end
		-- coins burst in LIGHT yellow, crystals in CRYSTAL blue
		local col = if isVoid then e elseif gift.crystals and not gift.coins then 14 else 9
		Cheer.burst(layer, ctx.fx, col, px, py)
		local hy = if claim.pos == 7 then py - BH / 2 + 60 else py - CH / 2 - 6
		local taken = Theme.label(
			layer,
			if isVoid then "VOID IS YOURS!" else "TAKEN!",
			if isVoid then 40 else 34,
			UDim2.fromOffset(360, 44),
			UDim2.fromOffset(px, hy),
			{ anchor = V2(0.5, 1), color = Theme.GOOD_TXT, stroke = 4 }
		)
		taken.Name = "Taken"
		taken.ZIndex = 25
		Theme.pop(taken, 0, 0.4)
		fly(layer, v, gift, px, py, ctx)
	end
end

return Daily
