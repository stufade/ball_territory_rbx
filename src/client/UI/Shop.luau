--!strict
-- One plaza shop, three tabs: BALLS, SPIN, SKINS. The ball of the day is a featured banner.
-- The rest of the shelf is a grid of cards. SPIN on the plaza opens this same panel on the spin tab.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Shelf = require("./Shelf")
local Spin = require("./Spin")
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local NEL = 27

local TIER_COL: { [string]: Color3 } = {
	common = Color3.fromHex("#3d6bff"),
	rare = Color3.fromHex("#14a4ff"),
	epic = Color3.fromHex("#c044ff"),
	legendary = Color3.fromHex("#ffd63c"),
}
local TIER_WORD: { [string]: string } = {
	common = "COMMON",
	rare = "RARE",
	epic = "EPIC",
	legendary = "LEGENDARY",
}

local Shop = {}

export type Tab = "balls" | "spin" | "skins"

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
	tab: Tab?,
	setTab: (tab: Tab) -> (),
}

local esc: RBXScriptConnection? = nil

local function tierOf(e: number): string?
	for tier, list in Economy.TIERS :: { [string]: { number } } do
		if table.find(list, e) then
			return tier
		end
	end
	return nil
end

local function fullPrice(e: number, cur: string): number
	local tier = tierOf(e)
	local row = Economy.PRICE[cur]
	return if tier and row then row[tier] else 0
end

-- Canvas pixels to keep clear under the Roblox top bar. Tests have no inset and stay at 12.
local function topClear(cv: Vector2): number
	local ok, y = pcall(function()
		local Screen = require(script.Parent.Parent:WaitForChild("Screen"))
		local top = Screen.topbar().Y
		local inset = GuiService:GetGuiInset()
		if typeof(inset) == "Vector2" then
			top = math.max(top, inset.Y)
		end
		local _, band = Screen.band()
		if band.Y < 1 then
			return 12
		end
		return math.ceil(top * cv.Y / band.Y) + 12
	end)
	if ok and type(y) == "number" and y >= 12 and y < cv.Y * 0.45 then
		return y
	end
	return 12
end

local function left(s: number): string
	s = math.max(0, math.floor(s))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, s // 60 % 60)
	end
	return string.format("%dm %02ds", s // 60, s % 60)
end

local function iconFn(parent: Instance, cur: string, d: number, pos: UDim2): GuiObject
	return Money.icon(parent, cur, d, pos)
end

-- Sizes (design px). Header: title, wallet and close in one row; tabs under it; body below.
local HEAD_H = 84
local TAB_Y, TAB_H = 88, 54
local BODY_Y = TAB_Y + TAB_H + 10
local CARD_NAT = 126 -- natural height of a grid card; rows stretch so only whole rows show
local GAP = 10

-- The ball of the day: a tall scene card (like day 7 of Daily) - deep tier gradient, turning rays, a glow,
-- the ball standing on its shadow and bobbing, a -30% star, ribbon, timer and two big price buttons.
local function banner(
	body: Frame,
	deal: { e: number, coins: number, crystals: number, endsAt: number },
	w: number,
	h: number,
	ctx: Ctx,
	pay: (
		parent: Instance,
		e: number,
		cur: string,
		x: number,
		y: number,
		bw: number,
		bh: number
	) -> TextButton
): (Frame, TextButton, TextLabel)
	local e = deal.e
	local tier = tierOf(e) or "common"
	local tint = TIER_COL[tier] or Theme.YELLOW
	local el = Look.col(e)
	local card = Theme.card(body, UDim2.fromOffset(w, h), UDim2.fromOffset(0, 0), tint:Lerp(el, 0.35), Theme.BG, 20)
	card.Name = "Today"
	local edge = card:FindFirstChild("Edge") :: UIStroke
	edge.Thickness = 5
	edge.Color = Theme.YELLOW
	-- inner floor: darker band at the bottom the ball stands over
	local floor = Theme.frame(card, UDim2.new(1, 0, 0, math.floor(h * 0.5)), UDim2.new(0, 0, 1, 0), Theme.BG)
	floor.AnchorPoint = V2(0, 1)
	floor.Name = "Floor"
	local fg = Instance.new("UIGradient")
	fg.Rotation = 90
	fg.Transparency = NumberSequence.new(1, 0.15)
	fg.Parent = floor
	Theme.pattern(card, Color3.new(1, 1, 1), 0.92, 40)

	local bh = 64
	local priceY = h - 12 - bh
	local nameH = if h < 290 then 34 else 40
	local tierY = priceY - 8 - 26
	local nameY = tierY - 2 - nameH
	local topY = 34 -- the ribbon overlaps the top of the scene, drawn above it
	local ballD = math.clamp(nameY - 6 - topY, 64, 150)
	local cx, cy = w / 2, topY + ballD / 2
	local still = Theme.reduced()

	local rays =
		Theme.rays(card, 12, math.floor(w * 1.5), 26, UDim2.fromOffset(cx, cy), Theme.YELLOW, Color3.new(1, 1, 1), 0.55)
	local glow =
		Theme.glow(card, math.floor(ballD * 2.1), Theme.YELLOW:Lerp(el, 0.4), UDim2.fromOffset(cx, cy), 6, 0.82)
	local shadow = Theme.shadow(card, math.floor(ballD * 0.8), UDim2.fromOffset(cx, cy + ballD / 2 + 4))
	local icon = Theme.ball(card, e, ballD, UDim2.fromOffset(cx, cy), MID)
	icon.Name = "Icon"
	-- sparkles around the ball
	local sparks: { Frame } = {}
	for k = 1, 6 do
		local a = k * math.pi / 3 + 0.4
		local r = ballD * (0.62 + 0.12 * (k % 2))
		local sp = Theme.frame(
			card,
			UDim2.fromOffset(8, 8),
			UDim2.fromOffset(cx + math.cos(a) * r, cy + math.sin(a) * r * 0.8),
			Color3.new(1, 1, 1),
			MID
		)
		sp.Rotation = 45
		sp.Name = "Spark"
		table.insert(sparks, sp)
	end

	local ribbon = Theme.ribbon(card, "BALL OF THE DAY", Theme.ORANGE, UDim2.fromOffset(w / 2, 10), 30, V2(0.5, 0))
	ribbon.ZIndex = 6
	for _, c in ribbon:GetDescendants() do
		if c:IsA("GuiObject") then
			c.ZIndex = 7
		end
	end
	local offD = math.clamp(math.floor(ballD * 0.62), 56, 76)
	local off = Theme.burst(card, "-30%", offD, UDim2.fromOffset(cx + ballD / 2 + offD * 0.3, cy - ballD * 0.1))
	off.Name = "Off"
	off.ZIndex = 5
	local offText = off:FindFirstChild("Text") :: TextLabel
	offText.Name = "Deal"

	local title = Rules.Config.TITLE[e] or "?"
	Theme.label(
		card,
		title,
		Theme.fit(title, 48, w - 24, nameH + 8),
		UDim2.fromOffset(w - 24, nameH),
		UDim2.fromOffset(cx, nameY),
		{
			anchor = V2(0.5, 0),
			color = Theme.nameColor(e),
			stroke = 5,
		}
	).Name =
		"Name"
	-- tier chip and the honest old price, crossed
	local chip = Theme.ribbon(card, TIER_WORD[tier] or "COMMON", tint, UDim2.fromOffset(cx - 6, tierY), 26, V2(1, 0))
	chip.Name = "Tier"
	-- real timer in a dark pill right of the tier
	local endsBox =
		Theme.frame(card, UDim2.fromOffset(math.floor(w / 2 - 18), 26), UDim2.fromOffset(cx + 6, tierY), Theme.INK)
	endsBox.Name = "EndsBox"
	endsBox.BackgroundTransparency = 0.3
	Theme.round(endsBox, 13)
	local ends = Theme.label(endsBox, "", 20, UDim2.new(1, -10, 1, 0), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		color = Theme.YELLOW_TXT,
		stroke = 2,
	})
	ends.Name = "Ends"

	local bw = math.floor((w - 24 - 10) / 2)
	local coins = pay(card, e, "coins", 12, priceY, bw, bh)
	local gems = pay(card, e, "crystals", 12 + bw + 10, priceY, bw, bh)
	coins.NextSelectionRight = gems
	gems.NextSelectionLeft = coins

	if not still then
		local t = 0
		local glowS = Theme.scaleOf(glow)
		local offS = Theme.scaleOf(off)
		local shadowW = shadow.Size.X.Offset
		table.insert(ctx.frames, function(dt: number)
			if not card.Parent then
				return
			end
			t += dt
			rays.Rotation = t * 9
			glowS.Scale = 1 + 0.06 * math.sin(t * 2.2)
			local bob = math.sin(t * 2.4)
			icon.Position = UDim2.fromOffset(cx, cy - 5 - 5 * bob)
			local k = 1 - 0.12 * (bob + 1) / 2
			shadow.Size = UDim2.fromOffset(shadowW * k, math.max(6, math.floor(shadowW * 0.22 * k)))
			offS.Scale = 1 + 0.07 * math.max(0, math.sin(t * 4))
			for i, sp in sparks do
				sp.BackgroundTransparency = 0.2 + 0.8 * (0.5 + 0.5 * math.sin(t * 3 + i * 1.7))
			end
		end)
	end
	return card, coins, ends
end

-- A shelf card: element glow behind the ball on the left, name and tier on the right, two prices at the bottom.
local function shelfCard(
	list: Instance,
	e: number,
	w: number,
	h: number,
	x: number,
	y: number,
	pay: (
		parent: Instance,
		e: number,
		cur: string,
		x: number,
		y: number,
		bw: number,
		bh: number
	) -> TextButton
): Frame
	local tier = tierOf(e) or "common"
	local tint = TIER_COL[tier] or Theme.SLOT
	local el = Look.col(e)
	local card =
		Theme.card(list, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), Theme.SLOT:Lerp(el, 0.28), Theme.SLOT, 16)
	card.Name = `Row{e}`
	if tier == "legendary" or tier == "epic" then
		local edge = card:FindFirstChild("Edge") :: UIStroke
		edge.Color = tint
		edge.Thickness = 4
	end
	-- tier stripe along the top edge
	local stripe = Theme.frame(card, UDim2.new(1, 0, 0, 6), nil, tint)
	stripe.Name = "Stripe"
	local bh = 46
	local by = h - 10 - bh
	local ballD = math.clamp(by - 30, 48, 74)
	local bx, byc = 12 + ballD / 2 + 4, 10 + (by - 10) / 2
	Theme.glow(card, math.floor(ballD * 1.6), el, UDim2.fromOffset(bx, byc), 4, 0.78)
	Theme.shadow(card, math.floor(ballD * 0.7), UDim2.fromOffset(bx, byc + ballD / 2 + 1))
	local icon = Theme.ball(card, e, ballD, UDim2.fromOffset(bx, byc - 2), MID)
	icon.Name = "Icon"
	local tx = math.floor(bx + ballD / 2 + 12)
	local tw = w - tx - 10
	local title = Rules.Config.TITLE[e] or "?"
	Theme.label(card, title, Theme.fit(title, 30, tw, 34), UDim2.fromOffset(tw, 32), UDim2.fromOffset(tx, byc - 32), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.nameColor(e),
		stroke = 3,
	}).Name =
		"Name"
	local chip = Theme.ribbon(card, TIER_WORD[tier] or "COMMON", tint, UDim2.fromOffset(tx, byc + 4), 24)
	chip.Name = "Chip"
	local tl = chip:FindFirstChild("Text") :: TextLabel
	tl.Name = "Tier"
	tl.Parent = card
	tl.AnchorPoint = V2(0, 0)
	tl.Position = UDim2.fromOffset(tx + 4, byc + 4)
	tl.Size = UDim2.fromOffset(chip.Size.X.Offset - 8, 24)
	tl.ZIndex = 3
	local bw = math.floor((w - 20 - 8) / 2)
	pay(card, e, "coins", 10, by, bw, bh)
	pay(card, e, "crystals", 10 + bw + 8, by, bw, bh)
	return card
end

function Shop.build(parent: Frame, v: Net.ProfileView, ctx: Ctx)
	parent:ClearAllChildren()
	local cv = ctx.canvas
	local tab: Tab = ctx.tab or "balls"
	local owned: { [number]: boolean } = {}
	for _, e in v.balls do
		owned[e] = true
	end
	local deal = v.dailyBall
	if deal and owned[deal.e] then
		deal = nil
	end

	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local top = topClear(cv)
	local pw = math.min(cv.X - 24, 940)
	local ph = math.min(cv.Y - top - 12, 620)
	local panel =
		Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, top + ph / 2), Theme.PANEL, MID)
	panel.Name = "ShopPanel"
	panel.Active = true
	panel:SetAttribute("Tab", tab)
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.gradient(panel, Theme.PANEL_HI:Lerp(Theme.PANEL, 0.55), Theme.PANEL)
	Theme.pop(panel, 0, 0.92)

	local missingN = 0
	for e = 0, NEL - 1 do
		if not owned[e] and tierOf(e) and not (deal ~= nil and e == deal.e) then
			missingN += 1
		end
	end

	-- header: SHOP (Daily's title size) with the count under it, wallet, close
	Theme.label(panel, "SHOP", 46, UDim2.fromOffset(170, 50), UDim2.fromOffset(20, 6), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 5,
	}).Name =
		"Head"
	Theme.label(panel, `{missingN} BALLS LEFT`, 20, UDim2.fromOffset(220, 24), UDim2.fromOffset(22, 56), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.DIM,
		bold = true,
	}).Name =
		"Left"

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(72, 72), UDim2.fromOffset(pw - 12 - 72, 8), Theme.BAD, nil, 36)
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local pillW = 168
	local gemsX = pw - 12 - 72 - 16 - pillW
	local coinsX = gemsX - 26 - pillW
	Theme.purse(panel, "coins", Money.fmt(v.coins or 0), pillW, UDim2.fromOffset(coinsX + 18, 22), Theme.YELLOW, iconFn)
	Theme.purse(
		panel,
		"crystals",
		Money.fmt(v.crystals or 0),
		pillW,
		UDim2.fromOffset(gemsX + 18, 22),
		Money.GEM,
		iconFn
	)

	-- tabs: each in its own colour; the open one is bright, taller, with the yellow edge
	local tabGap = 10
	local tabW = math.floor((pw - 32 - tabGap * 2) / 3)
	local order: { Tab } = { "balls", "spin", "skins" }
	local tabName = { balls = "TabBalls", spin = "TabSpin", skins = "TabSkins" }
	local tabWord = { balls = "BALLS", spin = "SPIN", skins = "SKINS" }
	local tabCol = { balls = Theme.YELLOW, spin = Theme.ORANGE, skins = Theme.PURPLE }
	for i, id in order do
		local x = 16 + (i - 1) * (tabW + tabGap)
		local on = tab == id
		local col = if on then tabCol[id] else tabCol[id]:Lerp(Theme.SLOT, 0.62)
		local b =
			Theme.button(panel, tabWord[id], UDim2.fromOffset(tabW, TAB_H), UDim2.fromOffset(x, TAB_Y), col, nil, 28)
		b.Name = tabName[id]
		Theme.select(b, on)
		if not on then
			local l = b:FindFirstChild("Label") :: TextLabel?
			if l then
				l.TextColor3 = Theme.DIM
			end
		end
		b.Activated:Connect(function()
			if tab ~= id then
				ctx.setTab(id)
			end
		end)
	end

	local bodyW, bodyH = pw - 24, ph - BODY_Y - 12
	-- the well: dark inset with a faint pattern, the body sits in it
	local well = Theme.frame(panel, UDim2.fromOffset(bodyW + 8, bodyH + 8), UDim2.fromOffset(8, BODY_Y - 4), Theme.BG)
	well.Name = "Well"
	Theme.round(well, 18)
	Theme.stroke(well, 3, Theme.INK)
	Theme.gradient(well, Theme.BG, Theme.GLOW:Lerp(Theme.BG, 0.4))
	if tab == "balls" then
		Theme.pattern(well, Theme.GLOW:Lerp(Color3.new(1, 1, 1), 0.2), 0.8, 44)
	end
	local body = Theme.clear(panel, UDim2.fromOffset(bodyW, bodyH), UDim2.fromOffset(12, BODY_Y))
	body.Name = "Body"
	body.ClipsDescendants = true

	local function priceOf(e: number, cur: string): number
		if deal and e == deal.e then
			return if cur == "coins" then deal.coins else deal.crystals
		end
		return fullPrice(e, cur)
	end

	local function pay(row: Instance, e: number, cur: string, x: number, y: number, bw: number, bh: number): TextButton
		local b = Theme.price(
			row,
			Money.fmt(priceOf(e, cur)),
			UDim2.fromOffset(bw, bh),
			UDim2.fromOffset(x, y),
			cur,
			iconFn,
			if bh >= 60 then 30 else 24
		)
		b:SetAttribute("E", e)
		b:SetAttribute("Cur", cur)
		b.Activated:Connect(function()
			ctx.act(Net.Action.buy, e, cur)
		end)
		return b
	end

	if tab == "spin" then
		Spin.fill(body, v, {
			canvas = cv,
			frames = ctx.frames,
			close = ctx.close,
			act = ctx.act,
			panel = panel,
		}, bodyW, bodyH)
	elseif tab == "skins" then
		Shelf.fill(body, v, {
			canvas = cv,
			frames = ctx.frames,
			close = ctx.close,
			act = ctx.act,
		}, bodyW, bodyH)
		GuiService.SelectedObject = close
	else
		local listX = 0
		local todayCoin: TextButton? = nil
		local endsLabel: TextLabel? = nil
		if deal then
			local bw = math.clamp(math.floor(bodyW * 0.42), 300, 420)
			local card, coins, ends = banner(body, deal, bw, bodyH, ctx, pay)
			Theme.rise(card, 0.08)
			todayCoin = coins
			endsLabel = ends
			listX = bw + GAP
		else
			-- no deal: keep an empty Ends so the old screens find it
			local ends = Theme.label(body, "", 20, UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0))
			ends.Name = "Ends"
			ends.Visible = false
		end
		if deal and endsLabel then
			local lab = endsLabel
			local function upd()
				if deal then
					lab.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
				end
			end
			upd()
			table.insert(ctx.frames, function()
				if lab.Parent then
					upd()
				end
			end)
		end

		local listW = bodyW - listX
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Position = UDim2.fromOffset(listX, 0)
		list.Size = UDim2.fromOffset(listW, bodyH)
		list.CanvasSize = UDim2.fromOffset(0, 0)
		list.ScrollBarThickness = 8
		list.ScrollBarImageColor3 = Theme.YELLOW
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ElasticBehavior = Enum.ElasticBehavior.Never
		list.Active = true
		list.Parent = body

		local missing = {}
		for e = 0, NEL - 1 do
			if not owned[e] and tierOf(e) and not (deal ~= nil and e == deal.e) then
				table.insert(missing, e)
			end
		end
		table.sort(missing, function(a: number, b: number)
			local pa, pb = fullPrice(a, "coins"), fullPrice(b, "coins")
			if pa ~= pb then
				return pa < pb
			end
			return a < b
		end)

		if #missing == 0 then
			Theme.label(
				list,
				"ALL YOURS!",
				40,
				UDim2.fromOffset(listW - 16, 50),
				UDim2.fromOffset(listW / 2, bodyH / 2),
				{
					anchor = MID,
					color = Theme.GOOD_TXT,
					stroke = 4,
				}
			).Name =
				"Empty"
		end

		-- whole rows only: the card height stretches so the visible rows fill the list exactly
		local scrollW = 12
		local cols = math.max(2, math.floor((listW - scrollW + GAP) / (250 + GAP)))
		local cardW = math.floor((listW - scrollW - GAP * (cols - 1)) / cols)
		local fit = math.max(1, math.floor((bodyH + GAP) / (CARD_NAT + GAP)))
		local cardH = math.floor((bodyH - GAP * (fit - 1)) / fit)
		for i, e in missing do
			local col = (i - 1) % cols
			local rowI = (i - 1) // cols
			local c = shelfCard(list, e, cardW, cardH, col * (cardW + GAP), rowI * (cardH + GAP), pay)
			if i <= cols * fit then
				Theme.rise(c, 0.14 + 0.05 * i)
			end
		end
		local rowsN = math.ceil(#missing / cols)
		list.CanvasSize = UDim2.fromOffset(0, math.max(rowsN * (cardH + GAP) - GAP, 1))
		GuiService.SelectedObject = todayCoin or close
	end

	if esc then
		esc:Disconnect()
	end
	esc = UserInputService.InputBegan:Connect(function(input)
		if panel.Parent == nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
			ctx.close()
		end
	end)
end

return Shop
