--!strict
-- M3.1 login reward screen: 7 day cards of the cycle (taken: dimmed with a green tick; today: yellow frame, pulse),
-- CLAIM! (Action daily, the server pays), then the card pops with a burst and the counters roll. VOID on day 7 of
-- the first cycle shows the ball. Opens by itself once a day on the plaza (Wallet decides), or from the DAILY button.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cheer = require("./Cheer")
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
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
	act: (verb: string, arg: number?) -> (),
	close: () -> (),
	fx: Cheer.Ctx,
}

local CW, CH, GAP = 116, 176, 10

local function card(parent: Instance, c: Net.DayCard, i: number, x: number, y: number, fx: Cheer.Ctx): Frame
	local col = if c.ball then Look.dark(c.ball) else Theme.SLOT
	local f = Theme.frame(parent, UDim2.fromOffset(CW, CH), UDim2.fromOffset(x, y), col, TOP_MID)
	f.Name = `Day{i}`
	Theme.round(f, 14)
	local stroke = Theme.stroke(f, if c.today then 5 else 3, if c.today then Theme.YELLOW else Theme.INK)
	stroke.Name = "Edge"
	Instance.new("UIScale").Parent = f
	Theme.text(f, `DAY {i}`, 24, UDim2.new(1, -10, 0, 28), UDim2.new(0.5, 0, 0, 8), {
		anchor = TOP_MID,
		color = if c.today then Theme.YELLOW_TXT else Theme.DIM,
	})
	local cy = 82
	if c.ball then
		Theme.ball(f, c.ball, 74, UDim2.fromOffset(CW / 2, cy))
		local nm = Theme.text(f, Rules.Config.TITLE[c.ball] or "?", 24, UDim2.new(1, -8, 0, 28), nil, {
			anchor = TOP_MID,
			color = Theme.nameColor(c.ball),
		})
		nm.Position = UDim2.new(0.5, 0, 0, 128)
	else
		local both = c.coins ~= nil and c.crystals ~= nil
		local amount = ""
		if c.coins then
			Money.icon(f, "coins", if both then 44 else 60, UDim2.fromOffset(if both then CW / 2 - 24 else CW / 2, cy))
			amount = Money.fmt(c.coins)
		end
		if c.crystals then
			Money.icon(
				f,
				"crystals",
				if both then 44 else 60,
				UDim2.fromOffset(if both then CW / 2 + 24 else CW / 2, cy)
			)
			amount = if both then `{amount} +{c.crystals}` else Money.fmt(c.crystals)
		end
		Theme.text(f, amount, 28, UDim2.new(1, -8, 0, 30), UDim2.new(0.5, 0, 0, 120), { anchor = TOP_MID })
		if c.trials then
			Theme.text(f, "+1 TRIAL", 20, UDim2.new(1, -8, 0, 22), UDim2.new(0.5, 0, 0, 150), {
				anchor = TOP_MID,
				color = Theme.GOOD_TXT,
				bold = true,
			})
		end
	end
	if c.got then
		local shade = Theme.frame(f, UDim2.fromScale(1, 1), nil, Theme.INK)
		shade.BackgroundTransparency = 0.45
		shade.ZIndex = 5
		Theme.round(shade, 14)
		local tick = Theme.disc(f, 52, Theme.GOOD, UDim2.fromScale(0.5, 0.5))
		tick.Name = "Got"
		tick.ZIndex = 6
		Theme.stroke(tick, 3, Theme.INK)
		Theme.text(tick, "✓", 36, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), {
			anchor = MID,
			color = Theme.INK,
			stroke = 0,
			z = 7,
		})
	elseif c.today and not Theme.reduced() then
		local s = f:FindFirstChildOfClass("UIScale") :: UIScale
		table.insert(fx.frames, function()
			if f.Parent then
				s.Scale = 1 + 0.04 * math.sin(os.clock() * 5)
			end
		end)
	end
	return f
end

local function fmtLeft(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d:%02d", s // 3600, s // 60 % 60, s % 60)
end

-- Builds the screen into `parent` (cleared). claim: the server's answer just came (the card of that day pops).
function Daily.build(parent: Frame, v: Net.ProfileView, ctx: Ctx, claim: any?)
	parent:ClearAllChildren()
	local d = v.daily
	if not d then
		return
	end
	local cv = ctx.canvas
	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local w = 7 * CW + 6 * GAP + 40
	local panel = Theme.frame(parent, UDim2.fromOffset(w, 420), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "DailyPanel"
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.6)
	Theme.text(panel, "DAILY REWARD", 46, UDim2.fromOffset(600, 52), UDim2.new(0.5, 0, 0, 14), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
		stroke = 5,
	})
	Theme.text(panel, "COME BACK EVERY DAY · DAY 7: A LEGENDARY BALL!", 22, UDim2.fromOffset(700, 26), nil, {
		anchor = TOP_MID,
		color = Theme.DIM,
		bold = true,
	}).Position =
		UDim2.new(0.5, 0, 0, 66)
	local close =
		Theme.button(panel, "X", UDim2.fromOffset(56, 56), UDim2.new(1, -10, 0, 10), Theme.BAD, nil, 30, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)
	local cards = d.cards
	local x0 = 20 + CW / 2
	local today: Frame? = nil
	for i, c in cards do
		local f = card(panel, c, i, x0 + (i - 1) * (CW + GAP), 104, ctx.fx)
		Theme.pop(f, 0.05 * i, 0.5)
		if c.today then
			today = f
		end
	end
	if d.ready then
		local b =
			Theme.button(panel, "CLAIM!", UDim2.fromOffset(280, 80), UDim2.new(0.5, 0, 1, -16), Theme.GO, Theme.INK, 44)
		b.Name = "Claim"
		b.AnchorPoint = V2(0.5, 1)
		local s = Instance.new("UIScale")
		s.Parent = b
		if not Theme.reduced() then
			table.insert(ctx.fx.frames, function()
				if b.Parent then
					s.Scale = 1 + 0.05 * math.sin(os.clock() * 6)
				end
			end)
		end
		local sent = false
		b.Activated:Connect(function()
			if not sent then
				sent = true
				ctx.act(Net.Action.daily)
			end
		end)
	else
		local left = Theme.text(panel, "", 24, UDim2.fromOffset(520, 30), UDim2.new(0.5, -90, 1, -46), {
			anchor = MID,
			color = Theme.YELLOW_TXT,
		})
		left.Name = "Next"
		local function tick()
			local secs = 86400 - workspace:GetServerTimeNow() % 86400
			left.Text = `NEXT REWARD IN {fmtLeft(secs)}`
		end
		tick()
		table.insert(ctx.fx.frames, function()
			if left.Parent then
				tick()
			end
		end)
		local ok =
			Theme.button(panel, "OK", UDim2.fromOffset(160, 64), UDim2.new(1, -24, 1, -14), Theme.GO, Theme.INK, 36)
		ok.Name = "Ok"
		ok.AnchorPoint = V2(1, 1)
		ok.Activated:Connect(ctx.close)
	end
	if claim and today then
		-- the day just taken: pop, flash and burst in its colour
		local f = today :: Frame
		local e = if claim.gift and claim.gift.ball then claim.gift.ball else 13
		local px = x0 + (claim.pos - 1) * (CW + GAP) + (cv.X - w) / 2
		local py = 104 + CH / 2 + (cv.Y - 420) / 2
		local layer = Theme.clear(parent, UDim2.fromScale(1, 1))
		layer.ZIndex = 20
		local s = f:FindFirstChildOfClass("UIScale") :: UIScale
		local t = 0
		table.insert(ctx.fx.frames, function(dt)
			t += dt
			if f.Parent and t < 0.5 and not Theme.reduced() then
				s.Scale = 1 + 0.25 * math.sin(math.pi * t / 0.5)
			end
		end)
		if claim.gift and claim.gift.ball then
			Cheer.rays(layer, ctx.fx, e, px, py, 420).ZIndex = 1
			Cheer.confetti(layer, ctx.fx)
		end
		-- coins burst in LIGHT yellow, crystals in CRYSTAL blue
		local col = if claim.gift and claim.gift.ball then e elseif claim.gift and claim.gift.crystals then 14 else 9
		Cheer.burst(layer, ctx.fx, col, px, py)
		local plus =
			Theme.text(layer, "TAKEN!", 34, UDim2.fromOffset(240, 40), UDim2.fromOffset(px, py - CH / 2 - 10), {
				anchor = V2(0.5, 1),
				color = Theme.GOOD_TXT,
			})
		plus.Name = "Taken"
		Theme.pop(plus, 0, 0.4)
	end
end

return Daily
