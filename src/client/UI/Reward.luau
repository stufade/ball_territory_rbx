--!strict
-- T2.2 reward after the tutorial (State ph = "reward"), in the V2 victory style:
--   1. the 4 starters one by one: a card flies in, flips, a flash of the element colour, the name, "+1";
--   2. the free spin: a strip of the legendaries runs, slows down and stops on the ball the server already gave;
--      rays, a burst, confetti, "LEGENDARY!";
--   3. the "2x XP · 15 MIN" badge, LET'S PLAY! -> Action claim (the badge flies up to its place on the plaza).
-- The spin is free, so no PolicyService here; paid spins (M3) must check PolicyService.ArePaidRandomItemsRestricted.
-- Progress for checks without a screen: root attribute RewardStage = cards | spin | spinning | stopped | boost.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cheer = require("./Cheer")
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local TITLE = Rules.Config.TITLE
local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local TOP_MID = V2(0.5, 0)

export type Ctx = Cheer.Ctx & {
	act: (verb: string, arg: number?) -> (),
	topbar: Vector2,
}

local Reward = {}

-- seconds: a card each, the spin, the pause before the boost
Reward.CARD_EVERY = 0.95
Reward.SPIN_TIME = 4.2
Reward.AUTO_SPIN = 3

local function tween(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, delay: number?)
	local tw = TweenService:Create(
		o,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0),
		props
	)
	tw:Play()
	return tw
end

local function backOut(k: number): number
	local c = 1.70158
	return 1 + (c + 1) * (k - 1) ^ 3 + c * (k - 1) ^ 2
end

-- Expanding disc of colour c at (x, y): the flash of an opened card.
local function flash(parent: Instance, c: Color3, x: number, y: number, d: number)
	local f = Theme.disc(parent, 40, c, UDim2.fromOffset(x, y), 0.15)
	f.ZIndex = 2
	if Theme.reduced() then
		f:Destroy()
		return
	end
	tween(f, 0.45, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 })
	task.delay(0.5, function()
		f:Destroy()
	end)
end

-- "+1" that floats up from (x, y) and fades.
local function plusOne(parent: Instance, x: number, y: number, delay: number)
	local t = Theme.text(parent, "+1", 44, UDim2.fromOffset(90, 50), UDim2.fromOffset(x, y), {
		anchor = MID,
		color = Theme.GOOD_TXT,
		stroke = 5,
		z = 8,
	})
	t.TextTransparency = 1
	task.delay(delay, function()
		if not t.Parent then
			return
		end
		t.TextTransparency = 0
		if not Theme.reduced() then
			tween(t, 0.9, { Position = UDim2.fromOffset(x, y - 60) }, Enum.EasingStyle.Cubic)
			tween(t, 0.4, { TextTransparency = 1 }, nil, 0.8)
		end
	end)
end

-- Card of a ball: a face-down card flies in to (x, y) after `delay`, flips to the ball with its name, flashes.
-- Returns the card. Used by NEW BALL! too.
function Reward.card(
	parent: Instance,
	ctx: Cheer.Ctx,
	e: number,
	x: number,
	y: number,
	w: number,
	delay: number
): CanvasGroup
	local h = math.floor(w * 1.3)
	local card = Instance.new("CanvasGroup")
	card.BackgroundColor3 = Theme.PURPLE
	card.BorderSizePixel = 0
	card.AnchorPoint = MID
	card.Size = UDim2.fromOffset(w, h)
	card.Position = UDim2.fromOffset(x, ctx.canvas.Y + h)
	card.Rotation = -14
	card.ZIndex = 4
	Theme.round(card, 16)
	card.Parent = parent
	local border = Instance.new("UIStroke")
	border.Thickness = 5
	border.Color = Theme.INK
	border.Parent = card
	-- back: purple with a big "?"
	local back = Theme.clear(card, UDim2.fromScale(1, 1))
	local q = Theme.text(back, "?", math.floor(w * 0.55), UDim2.fromScale(0.8, 0.6), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		color = Theme.YELLOW,
		stroke = 6,
	})
	q.ZIndex = 5
	-- front: element background, ball, name
	local front = Theme.clear(card, UDim2.fromScale(1, 1))
	front.Visible = false
	local bg = Theme.frame(front, UDim2.fromScale(1, 1), nil, Look.dark(e):Lerp(Theme.BG, 0.35))
	Theme.round(bg, 16)
	local shine = Theme.frame(front, UDim2.fromScale(1, 0.5), nil, Look.bright(e))
	shine.BackgroundTransparency = 0.7
	Theme.round(shine, 16)
	local ball = Theme.ball(front, e, w * 0.62, UDim2.fromScale(0.5, 0.42))
	ball.ZIndex = 5
	local nm = Theme.text(front, TITLE[e] or "?", 30, UDim2.new(1, -12, 0, 34), UDim2.new(0.5, 0, 1, -12), {
		anchor = V2(0.5, 1),
		color = Theme.nameColor(e),
		stroke = 4,
		z = 6,
	})
	nm.ZIndex = 6
	local function open()
		front.Visible = true
		back.Visible = false
		border.Color = Look.light(e)
		flash(parent, Look.bright(e), x, y, w * 2.4)
		Cheer.burst(parent, ctx, e, x, y)
	end
	if Theme.reduced() then
		card.Position = UDim2.fromOffset(x, y)
		card.Rotation = 0
		task.delay(delay, function()
			if card.Parent then
				open()
			end
		end)
		return card
	end
	-- frame-driven (not TweenService), so the order fly -> flip -> open never waits on a tween's Completed
	local y0 = ctx.canvas.Y + h
	local t = -delay
	local opened = false
	table.insert(ctx.frames, function(dt)
		if not card.Parent or t > 1 then
			return
		end
		t += dt
		if t < 0 then
			return
		end
		local fly = math.min(1, t / 0.38)
		card.Position = UDim2.fromOffset(x, y0 + (y - y0) * backOut(fly))
		card.Rotation = -14 * (1 - fly)
		-- flip: squeeze to an edge, swap the face, spring back
		if t < 0.42 then
			return
		elseif t < 0.54 then
			local k = (t - 0.42) / 0.12
			card.Size = UDim2.fromOffset(w + (4 - w) * k, h * (1 + 0.06 * k))
		else
			if not opened then
				opened = true
				open()
			end
			local k = math.min(1, (t - 0.54) / 0.22)
			card.Size = UDim2.fromOffset(4 + (w - 4) * backOut(k), h * (1.06 - 0.06 * k))
		end
	end)
	return card
end

-- Stage 1: four cards in a row.
local function cards(root: Frame, ctx: Ctx, balls: { number }, title: TextLabel): number
	local cv = ctx.canvas
	local n = #balls
	local w = math.min(180, (cv.X - 80) / n - 24)
	local gap = w + 24
	local y = cv.Y * 0.52
	for i, e in balls do
		local x = cv.X / 2 + (i - (n + 1) / 2) * gap
		local at = 0.5 + (i - 1) * Reward.CARD_EVERY
		Reward.card(root, ctx, e, x, y, w, at)
		plusOne(root, x, y - w * 0.65 - 10, at + 0.6)
	end
	title.Text = "YOUR FIRST BALLS!"
	return 0.5 + n * Reward.CARD_EVERY + 0.6
end

-- Stage 2: the strip. The landing tile is the server's ball; it decelerates straight onto it (no bounce back, no
-- stop next to it): the strip only shows a result decided before it started.
local function spin(root: Frame, ctx: Ctx, pool: { number }, legend: number, done: () -> ())
	local cv = ctx.canvas
	local ww = math.min(cv.X - 80, 760)
	local tile = 150
	local cy = cv.Y * 0.5
	local win = Theme.frame(root, UDim2.fromOffset(ww, 180), UDim2.fromOffset(cv.X / 2, cy), Theme.PANEL, MID)
	win.ClipsDescendants = true
	win.ZIndex = 3
	Theme.round(win, 18)
	Theme.stroke(win, 5, Theme.YELLOW)
	local strip = Theme.clear(win, UDim2.fromOffset(tile, 180))
	strip.ZIndex = 3
	-- the strip: the pool over and over; the landing tile is `land`, the strip starts `land - 1 - laps` tiles back
	local count = 34
	local land = count - 3
	local idx = table.find(pool, legend) or 1
	local tiles: { Frame } = {}
	for i = 1, count do
		local e = if i == land then legend else pool[((idx - 1 + i - land) % #pool) + 1]
		local t = Theme.frame(strip, UDim2.fromOffset(tile - 12, 164), UDim2.fromOffset((i - 1) * tile + 6, 8))
		t.BackgroundColor3 = Look.dark(e):Lerp(Theme.BG, 0.4)
		t.ZIndex = 3
		Theme.round(t, 14)
		Theme.stroke(t, 3, Look.light(e))
		local b = Theme.ball(t, e, 96, UDim2.new(0.5, 0, 0, 62))
		b.ZIndex = 4
		local nm = Theme.text(t, TITLE[e] or "?", 22, UDim2.new(1, -10, 0, 28), UDim2.new(0.5, 0, 1, -8), {
			anchor = V2(0.5, 1),
			color = Theme.nameColor(e),
			z = 5,
		})
		nm.ZIndex = 5
		tiles[i] = t
	end
	-- offset that puts tile i in the middle of the window
	local function centre(i: number): number
		return ww / 2 - ((i - 1) * tile + tile / 2)
	end
	local x0, x1 = centre(3), centre(land)
	strip.Position = UDim2.fromOffset(x0, 0)
	-- the marker: a yellow line with two triangles
	local line = Theme.frame(win, UDim2.fromOffset(6, 180), UDim2.fromScale(0.5, 0), Theme.YELLOW, TOP_MID)
	line.ZIndex = 7
	line.BackgroundTransparency = 0.25
	for _, top in { true, false } do
		local tri = Theme.text(
			root,
			if top then "▼" else "▲",
			44,
			UDim2.fromOffset(50, 44),
			UDim2.fromOffset(cv.X / 2, if top then cy - 112 else cy + 112),
			{ anchor = MID, color = Theme.YELLOW, stroke = 4, z = 8 }
		)
		tri.ZIndex = 8
	end
	local markScale = Instance.new("UIScale")
	markScale.Parent = line
	local btn = Theme.button(
		root,
		"SPIN FREE!",
		UDim2.fromOffset(300, Theme.BTN_H),
		UDim2.fromOffset(cv.X / 2, cy + 140),
		Theme.GO,
		Theme.INK,
		44,
		TOP_MID
	)
	Theme.pop(btn, 0.2, 0.5)
	local bs = btn:FindFirstChildOfClass("UIScale")
	local started = false
	local t = 0
	local lastTile = 3
	local function go()
		if started or not root.Parent then
			return
		end
		started = true
		btn.Visible = false
		root:SetAttribute("RewardStage", "spinning")
		if Theme.reduced() then
			strip.Position = UDim2.fromOffset(x1, 0)
			t = Reward.SPIN_TIME
		end
	end
	btn.Activated:Connect(go)
	task.delay(Reward.AUTO_SPIN, go)
	local stopped = false
	table.insert(ctx.frames, function(dt)
		if not started then
			if bs and not Theme.reduced() then
				bs.Scale = 1 + 0.06 * math.sin(os.clock() * 7)
			end
			return
		end
		if stopped then
			return
		end
		t = math.min(Reward.SPIN_TIME, t + dt)
		local u = t / Reward.SPIN_TIME
		local k = 1 - (1 - u) ^ 4
		local x = x0 + (x1 - x0) * k
		strip.Position = UDim2.fromOffset(x, 0)
		root:SetAttribute("SpinX", math.floor(x))
		-- tick: the marker jumps each time a tile passes it
		local under = math.floor((ww / 2 - x) / tile) + 1
		if under ~= lastTile then
			lastTile = under
			markScale.Scale = 1.5
		end
		markScale.Scale += (1 - markScale.Scale) * math.min(1, dt * 12)
		if t >= Reward.SPIN_TIME then
			stopped = true
			markScale.Scale = 1
			root:SetAttribute("RewardStage", "stopped")
			root:SetAttribute("SpinOn", legend)
			local wt = tiles[land]
			wt.ZIndex = 6
			local s = Instance.new("UIScale")
			s.Parent = wt
			if not Theme.reduced() then
				tween(s, 0.3, { Scale = 1.12 }, Enum.EasingStyle.Back)
			end
			done()
		end
	end)
	return win
end

-- Where the plaza's 2x XP badge sits (centre, design px): UI/Level lays the bar and the badge out by this.
-- Where the 2x XP medal lives on the plaza (top centre): right of the level bar at the bottom (Theme.plaza, U1).
function Reward.badgeAt(cv: Vector2, topbar: Vector2): Vector2
	local L = Theme.plaza(cv, topbar)
	return V2(L.barX + L.barW / 2 + 14 + 36, L.barY - 8)
end

function Reward.build(parent: Frame, st: Net.State, ctx: Ctx)
	local cv = ctx.canvas
	-- own container: a rebuild destroys it, and every pending step checks it is still there
	local root = Theme.clear(parent, UDim2.fromScale(1, 1))
	root.Name = "Reward"
	local balls: { number } = st.balls or {}
	local legend = st.legend or 17
	local pool: { number } = if st.pool and #st.pool > 0 then st.pool else { legend }
	local boost = st.boost or 900
	Theme.backdrop(root)
	root:SetAttribute("RewardStage", "cards")
	local top = math.max(14, if cv.X / 2 - 300 < ctx.topbar.X then ctx.topbar.Y else 14)
	local title = Theme.text(root, "", 52, UDim2.fromOffset(640, 60), UDim2.fromOffset(cv.X / 2, top), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
		stroke = 6,
	})
	Theme.pop(title, 0, 0.4)
	local sub = Theme.text(root, "", 26, UDim2.fromOffset(640, 32), UDim2.fromOffset(cv.X / 2, top + 62), {
		anchor = TOP_MID,
		color = Theme.DIM,
	})
	local function alive(): boolean
		return root.Parent ~= nil
	end
	local cardsEnd = cards(root, ctx, balls, title)
	sub.Text = "FOR WINNING YOUR FIRST BATTLE"

	local function boostStage(winBox: Frame)
		if not alive() then
			return
		end
		root:SetAttribute("RewardStage", "boost")
		local mins = math.floor(boost / 60 + 0.5)
		if not Theme.reduced() then
			tween(winBox, 0.35, { Position = UDim2.fromOffset(cv.X / 2, cv.Y * 0.42) })
		end
		local badge =
			Theme.frame(root, UDim2.fromOffset(360, 84), UDim2.fromOffset(cv.X / 2, cv.Y * 0.42 + 130), Theme.GO, MID)
		badge.ZIndex = 20
		Theme.round(badge, 42)
		Theme.stroke(badge, 5, Theme.INK)
		local bt = Theme.text(badge, `2x XP · {mins} MIN`, 44, UDim2.new(1, -24, 1, -12), UDim2.fromScale(0.5, 0.5), {
			anchor = MID,
			color = Theme.INK,
			stroke = 0,
			z = 21,
		})
		bt.ZIndex = 21
		badge.Name = "Boost"
		Theme.pop(badge, 0, 0.2)
		local bs = Instance.new("UIScale")
		bs.Parent = badge
		Cheer.burst(root, ctx, 2, cv.X / 2, cv.Y * 0.42 + 130)
		local btn = Theme.button(
			root,
			"LET'S PLAY!",
			UDim2.fromOffset(300, Theme.BTN_H),
			UDim2.new(0.5, 0, 1, -16),
			Theme.GO,
			Theme.INK,
			44,
			V2(0.5, 1)
		)
		btn.Name = "Claim"
		Theme.pop(btn, 0.6, 0.5)
		table.insert(ctx.frames, function()
			if not Theme.reduced() then
				bs.Scale = 1 + 0.04 * math.sin(os.clock() * 5)
			end
		end)
		local sent = false
		local function press()
			if sent then
				return
			end
			sent = true
			btn.Active = false
			-- the badge flies up to the plaza badge's place, then the plaza
			if Theme.reduced() then
				ctx.act(Net.Action.claim)
				return
			end
			local at = Reward.badgeAt(cv, ctx.topbar)
			tween(badge, 0.4, { Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(170, 52) })
			task.delay(0.42, function()
				ctx.act(Net.Action.claim)
			end)
		end
		btn.Activated:Connect(press)
		-- debug (screenshots): workspace attribute BTRewardAuto = true presses LET'S PLAY! after 3 s
		if workspace:GetAttribute("BTRewardAuto") == true then
			task.delay(3, function()
				if btn.Parent then
					press()
				end
			end)
		end
	end

	local function stopped(winBox: Frame)
		if not alive() then
			return
		end
		title.Text = "LEGENDARY!"
		title.TextColor3 = Theme.YELLOW
		Theme.pop(title, 0, 0.3)
		sub.Text = (TITLE[legend] or "?") .. "  +1"
		sub.TextColor3 = Theme.nameColor(legend)
		local r = Cheer.rays(root, ctx, legend, cv.X / 2, cv.Y * 0.5, 760)
		r.ZIndex = 1
		Cheer.burst(root, ctx, legend, cv.X / 2, cv.Y * 0.5)
		Cheer.confetti(root, ctx)
		flash(root, Look.bright(legend), cv.X / 2, cv.Y * 0.5, 520)
		task.delay(2.2, function()
			boostStage(winBox)
		end)
	end

	task.delay(cardsEnd, function()
		if not alive() then
			return
		end
		root:SetAttribute("RewardStage", "spin")
		-- the cards fly away, the free spin comes
		for _, c in root:GetChildren() do
			if c:IsA("CanvasGroup") then
				if Theme.reduced() then
					c:Destroy()
				else
					tween(c, 0.35, { GroupTransparency = 1, Position = c.Position - UDim2.fromOffset(0, 80) })
					task.delay(0.4, function()
						c:Destroy()
					end)
				end
			end
		end
		title.Text = "FREE SPIN!"
		Theme.pop(title, 0, 0.5)
		sub.Text = "A LEGENDARY BALL FOR YOU"
		local box: Frame
		box = spin(root, ctx, pool, legend, function()
			stopped(box)
		end)
		Theme.pop(box, 0, 0.6)
	end)
end

return Reward
