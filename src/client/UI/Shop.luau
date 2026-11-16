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

local ROBUX_COL = Color3.fromHex("#1c9e6a")

local Shop = {}

export type Tab = "balls" | "spin" | "skins" | "packs"

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

-- Sizes (design px). Header: one row - the tabs on the left, the coin pill, "+" and close on the right; body below.
-- 62 design px = 44 px on a 844x390 phone (scale 0.72); the tabs and close are 72 (52 px).
local HEAD_Y, HEAD_H = 8, 72
local BODY_Y = HEAD_Y + HEAD_H + 12
local GAP = 10
local BANNER_H = 150

-- A phone in landscape: the Theme phone rule, or a canvas wider than 16:9 (tests have no device).
local function phoneLike(cv: Vector2): boolean
	return Theme.phone or cv.X > 1100
end

-- The ball of the day: a wide banner on top of the list (the day-7 family) - deep tier gradient; on the left
-- the ball on turning rays, glow and shadow with the -30% star; in the middle the ribbon, the name, the tier
-- and the real timer; on the right one big coin price.
local function banner(
	body: Instance,
	deal: { e: number, coins: number, endsAt: number },
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
	card.ClipsDescendants = true
	local edge = card:FindFirstChild("Edge") :: UIStroke
	edge.Thickness = 5
	edge.Color = Theme.YELLOW
	Theme.pattern(card, Color3.new(1, 1, 1), 0.92, 40)
	local still = Theme.reduced()

	-- left: the scene
	local sceneW = math.clamp(math.floor(w * 0.22), 170, 230)
	local ballD = math.min(h - 34, 112)
	local cx, cy = sceneW / 2 + 6, h / 2 - 4
	local rays = Theme.rays(
		card,
		12,
		math.floor(sceneW * 1.7),
		26,
		UDim2.fromOffset(cx, cy),
		Theme.YELLOW,
		Color3.new(1, 1, 1),
		0.55
	)
	local glow =
		Theme.glow(card, math.floor(ballD * 1.9), Theme.YELLOW:Lerp(el, 0.4), UDim2.fromOffset(cx, cy), 6, 0.82)
	local shadow = Theme.shadow(card, math.floor(ballD * 0.8), UDim2.fromOffset(cx, cy + ballD / 2 + 4))
	local icon = Theme.ball(card, e, ballD, UDim2.fromOffset(cx, cy), MID)
	icon.Name = "Icon"
	local offD = 62
	local off = Theme.burst(card, "-30%", offD, UDim2.fromOffset(cx + ballD * 0.48, cy - ballD * 0.32))
	off.Name = "Off"
	off.ZIndex = 5
	local offText = off:FindFirstChild("Text") :: TextLabel
	offText.Name = "Deal"

	-- right: the price
	local bw = math.clamp(math.floor(w * 0.3), 230, 340)
	local bh = 72
	local coins = pay(card, e, "coins", w - 14 - bw, math.floor((h - bh) / 2), bw, bh)

	-- middle: ribbon, name, tier and timer
	local mx = sceneW + 22
	local mw = w - mx - bw - 28
	local ribbon = Theme.ribbon(card, "BALL OF THE DAY", Theme.ORANGE, UDim2.fromOffset(mx, 12), 30)
	ribbon.ZIndex = 6
	for _, c in ribbon:GetDescendants() do
		if c:IsA("GuiObject") then
			c.ZIndex = 7
		end
	end
	local title = Rules.Config.TITLE[e] or "?"
	Theme.label(card, title, Theme.fit(title, 46, mw, 52), UDim2.fromOffset(mw, 48), UDim2.fromOffset(mx, 48), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.nameColor(e),
		stroke = 5,
	}).Name =
		"Name"
	local rowY = h - 14 - 30
	local chip = Theme.ribbon(card, TIER_WORD[tier] or "COMMON", tint, UDim2.fromOffset(mx, rowY), 30)
	chip.Name = "Tier"
	local cw = chip.Size.X.Offset
	local endsW = math.max(120, math.min(220, mw - cw - 10))
	local endsBox = Theme.frame(card, UDim2.fromOffset(endsW, 30), UDim2.fromOffset(mx + cw + 10, rowY), Theme.INK)
	endsBox.Name = "EndsBox"
	endsBox.BackgroundTransparency = 0.3
	Theme.round(endsBox, 15)
	local ends = Theme.label(endsBox, "", 22, UDim2.new(1, -10, 1, 0), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		color = Theme.YELLOW_TXT,
		stroke = 2,
	})
	ends.Name = "Ends"

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
			icon.Position = UDim2.fromOffset(cx, cy - 3 - 3 * bob)
			local k = 1 - 0.12 * (bob + 1) / 2
			shadow.Size = UDim2.fromOffset(shadowW * k, math.max(6, math.floor(shadowW * 0.22 * k)))
			offS.Scale = 1 + 0.07 * math.max(0, math.sin(t * 4))
		end)
	end
	return card, coins, ends
end

-- A shelf card: element glow behind the ball on the left, name and tier on the right, the price at the bottom.
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
	-- the price row is 62 design px (44 px on a phone); the ball, name and tier share the space above it
	local bh = 62
	local by = h - 8 - bh
	local topH = by - 6
	local ballD = math.clamp(topH - 10, 40, 92)
	local bx, byc = 12 + ballD / 2 + 4, 6 + topH / 2
	Theme.glow(card, math.floor(ballD * 1.6), el, UDim2.fromOffset(bx, byc), 4, 0.78)
	Theme.shadow(card, math.floor(ballD * 0.7), UDim2.fromOffset(bx, byc + ballD / 2 + 1))
	local icon = Theme.ball(card, e, ballD, UDim2.fromOffset(bx, byc - 2), MID)
	icon.Name = "Icon"
	local tx = math.floor(bx + ballD / 2 + 12)
	local tw = w - tx - 10
	local nh = math.clamp(math.floor(topH * 0.5), 24, 34)
	local chH = math.clamp(topH - nh - 10, 20, 26)
	local ny = math.floor(byc - (nh + 4 + chH) / 2)
	local cy = ny + nh + 4
	local title = Rules.Config.TITLE[e] or "?"
	Theme.label(card, title, Theme.fit(title, 34, tw, nh + 2), UDim2.fromOffset(tw, nh), UDim2.fromOffset(tx, ny), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.nameColor(e),
		stroke = 3,
	}).Name =
		"Name"
	local chip = Theme.ribbon(card, TIER_WORD[tier] or "COMMON", tint, UDim2.fromOffset(tx, cy), chH)
	chip.Name = "Chip"
	local tl = chip:FindFirstChild("Text") :: TextLabel
	tl.Name = "Tier"
	tl.Parent = card
	tl.AnchorPoint = V2(0, 0)
	tl.Position = UDim2.fromOffset(tx + 4, cy)
	tl.Size = UDim2.fromOffset(chip.Size.X.Offset - 8, chH)
	tl.ZIndex = 3
	pay(card, e, "coins", 10, by, w - 20, bh)
	return card
end

-- A pile of coins that grows with the pack: 1 big coin for the smallest, a heap for the biggest.
local PILES: { { { number } } } = {
	{ { 0, 0, 1 } },
	{ { -0.22, 0.08, 0.8 }, { 0.2, 0, 0.9 } },
	{ { -0.28, 0.12, 0.72 }, { 0.28, 0.12, 0.72 }, { 0, -0.08, 0.88 } },
	{ { -0.34, 0.16, 0.62 }, { 0.34, 0.16, 0.62 }, { -0.12, 0.1, 0.7 }, { 0.14, 0.12, 0.7 }, { 0, -0.14, 0.82 } },
	{
		{ -0.4, 0.18, 0.56 },
		{ 0.4, 0.18, 0.56 },
		{ -0.18, 0.14, 0.64 },
		{ 0.18, 0.14, 0.64 },
		{ -0.2, -0.1, 0.66 },
		{ 0.2, -0.1, 0.66 },
		{ 0, -0.24, 0.78 },
	},
	{
		{ -0.44, 0.2, 0.52 },
		{ 0.44, 0.2, 0.52 },
		{ -0.24, 0.18, 0.58 },
		{ 0.24, 0.18, 0.58 },
		{ 0, 0.16, 0.6 },
		{ -0.3, -0.06, 0.6 },
		{ 0.3, -0.06, 0.6 },
		{ -0.1, -0.12, 0.66 },
		{ 0.12, -0.14, 0.66 },
		{ 0, -0.32, 0.76 },
	},
}

local starterPick = 0 -- index into the epics the player lacks, for the starter pack

-- One pass or the starter pack in the offers strip: art on the left, two lines, a green R$ button.
local function offer(
	strip: Frame,
	name: string,
	title: string,
	line: string,
	robux: number,
	color: Color3,
	x: number,
	w: number,
	h: number,
	onBuy: () -> ()
): Frame
	local tile = Theme.card(strip, UDim2.fromOffset(w, h), UDim2.fromOffset(x, 0), color, Theme.BG, 16)
	tile.Name = name
	local bw = math.clamp(math.floor(w * 0.26), 80, 110)
	local tx = 74 -- art (the epic ball, VIP, 2X) is 64 wide on the left
	local tw = w - tx - bw - 18
	-- the line goes on two rows when one would not fit at the minimum text (a narrow PC tile)
	local two0 = (utf8.len(line) or #line) * 0.62 * Theme.MIN_TEXT > tw
	Theme.label(tile, title, Theme.fit(title, 26, tw, 30), UDim2.fromOffset(tw, 28), UDim2.fromOffset(tx, if two0 then 3 else 8), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW_TXT,
		stroke = 3,
	}).Name =
		"Title"
	local two = two0 -- "EPIC +3K / COINS"
	local ly = if two then 30 else 36
	local lh = if two then h - ly - 2 else 22
	Theme.label(tile, line, if two then Theme.MIN_TEXT else Theme.fit(line, 18, tw, 22), UDim2.fromOffset(tw, lh), UDim2.fromOffset(tx, ly), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.TEXT,
		bold = true,
		wrap = two,
	}).Name =
		"Line"
	local buy = Theme.button(
		tile,
		`R${robux}`,
		UDim2.fromOffset(bw, h - 10),
		UDim2.fromOffset(w - 6 - bw, 5),
		ROBUX_COL,
		nil,
		26
	)
	buy.Name = "PayRobux"
	buy.Activated:Connect(onBuy)
	return tile
end

-- COINS tab: six packs (Economy.COIN_PACKS) as bright cards with growing piles, the best value marked,
-- and under them the offers strip: starter pack, VIP, 2x match coins (only what the server still offers).
function Shop.packs(body: Frame, v: Net.ProfileView, ctx: Ctx, w: number, h: number)
	local packs = Economy.COIN_PACKS :: { { coins: number, robux: number, best: boolean? } }
	local base = packs[1].coins / packs[1].robux
	local offers = v.passOffer or {}
	local owned: { [number]: boolean } = {}
	for _, e in v.balls do
		owned[e] = true
	end
	local epics: { number } = {}
	for _, e in (Economy.TIERS :: any).epic do
		if not owned[e] then
			table.insert(epics, e)
		end
	end
	local list: { string } = {}
	if not v.starterBought and #epics > 0 and Economy.STARTER then
		table.insert(list, "starter")
	end
	for _, k in { "vip", "coins2x" } do
		if offers[k] then
			table.insert(list, k)
		end
	end
	local stripH = 80
	local showStrip = #list > 0 and h - stripH - GAP >= 170
	local packH = if showStrip then h - stripH - GAP else h
	packH = math.min(packH, 400)

	-- six in a row when each is at least 130 wide, else two rows of three
	local cols = if (w - GAP * 5) / 6 >= 130 then 6 else 3
	local rows = math.ceil(#packs / cols)
	local cw = math.floor((w - GAP * (cols - 1)) / cols)
	local ch = math.floor((packH - GAP * (rows - 1)) / rows)
	for i, pk in packs do
		local c = (i - 1) % cols
		local r = (i - 1) // cols
		local best = pk.best == true
		local tint = Money.COIN_DARK:Lerp(Theme.ORANGE, (i - 1) / (#packs - 1) * 0.6)
		local card = Theme.card(
			body,
			UDim2.fromOffset(cw, ch),
			UDim2.fromOffset(c * (cw + GAP), r * (ch + GAP)),
			tint,
			Theme.SLOT:Lerp(tint, 0.25),
			18
		)
		card.Name = `Pack{i}`
		local edge = card:FindFirstChild("Edge") :: UIStroke
		if best then
			edge.Color = Theme.YELLOW
			edge.Thickness = 5
		end
		Theme.pattern(card, Color3.new(1, 1, 1), 0.9, 34)
		local bh = 62
		local by = ch - 8 - bh
		local amountY = by - 4 - 34
		local topY = if best then 32 else 10
		local pileH = amountY - topY - 2
		local d = math.clamp(math.floor(math.min(pileH, cw - 20) * 0.62), 26, 96)
		local cx, cy = cw / 2, topY + pileH / 2
		Theme.glow(card, math.floor(d * (1.6 + i * 0.12)), Money.COIN, UDim2.fromOffset(cx, cy), 4, 0.8)
		if i >= 5 then
			Theme.rays(
				card,
				10,
				math.floor(d * 2.6),
				20,
				UDim2.fromOffset(cx, cy),
				Color3.new(1, 1, 1),
				Money.COIN,
				0.7
			)
		end
		local pileW = cw - 12
		local pile = Theme.clear(card, UDim2.fromOffset(pileW, pileH), UDim2.fromOffset(cx, cy), MID)
		pile.Name = "Pile"
		local spot = PILES[i] or PILES[#PILES]
		-- the widest heap spans 1.4 coin sizes each way: keep it inside the pile box
		local pd = math.floor(math.min(pileW / 1.5, pileH / 1.5, 120))
		for k, p in spot do
			local g = Money.icon(
				pile,
				"coins",
				math.floor(pd * p[3]),
				UDim2.fromOffset(pileW / 2 + p[1] * pd, pileH / 2 + p[2] * pd)
			)
			g.ZIndex = 2 + k
		end
		Theme.label(card, Money.fmt(pk.coins), 34, UDim2.fromOffset(cw - 12, 34), UDim2.fromOffset(cw / 2, amountY), {
			anchor = V2(0.5, 0),
			color = Money.COIN:Lerp(Color3.new(1, 1, 1), 0.4),
			stroke = 4,
		}).Name =
			"Amount"
		-- honest bonus: coins per Robux against the smallest pack
		local more = math.floor((pk.coins / pk.robux / base - 1) * 100 + 0.5)
		if more > 0 then
			local chip = Theme.ribbon(card, `+{more}%`, Theme.ORANGE, UDim2.fromOffset(cw - 6, topY), 24, V2(1, 0))
			chip.Name = "More"
			chip.ZIndex = 6
		end
		if best then
			local rb = Theme.ribbon(card, "BEST VALUE", Theme.BAD, UDim2.fromOffset(cw / 2, 6), 26, V2(0.5, 0))
			rb.Name = "Best"
			rb.ZIndex = 7
			for _, o in rb:GetDescendants() do
				if o:IsA("GuiObject") then
					o.ZIndex = 8
				end
			end
		end
		local buy = Theme.button(
			card,
			`R${pk.robux}`,
			UDim2.fromOffset(cw - 16, bh),
			UDim2.fromOffset(8, by),
			ROBUX_COL,
			nil,
			28
		)
		buy.Name = "PayRobux"
		buy:SetAttribute("Pack", i)
		buy.Activated:Connect(function()
			ctx.act(Net.Action.pay, i, "pack")
		end)
		Theme.rise(card, 0.06 + 0.05 * i)
	end

	if not showStrip then
		return
	end
	local strip = Theme.clear(body, UDim2.fromOffset(w, stripH), UDim2.fromOffset(0, h - stripH))
	strip.Name = "Offers"
	local tw = math.floor((w - GAP * (#list - 1)) / #list)
	for i, k in list do
		local x = (i - 1) * (tw + GAP)
		if k == "starter" then
			local S = Economy.STARTER
			starterPick = (starterPick % #epics)
			local e = epics[starterPick + 1]
			local tile = offer(
				strip,
				"OfferStarter",
				"STARTER",
				if S.coins % 1000 == 0 then `EPIC +{S.coins // 1000}K COINS` else `EPIC +{S.coins}`,
				S.robux,
				Theme.ORANGE:Lerp(Theme.BG, 0.25),
				x,
				tw,
				stripH,
				function()
					ctx.act(Net.Action.pay, e, "starter")
				end
			)
			-- the epic is the player's choice: tap the ball for the next one
			local pick = Instance.new("TextButton")
			pick.Name = "PickEpic"
			pick.Text = ""
			pick.BackgroundTransparency = 1
			pick.Size = UDim2.fromOffset(64, stripH - 6)
			pick.Position = UDim2.fromOffset(2, 3)
			pick.Parent = tile
			Theme.ball(pick, e, 58, UDim2.fromScale(0.5, 0.5), MID).Name = "Icon"
			pick:SetAttribute("E", e)
			pick.Activated:Connect(function()
				starterPick += 1
				ctx.setTab("packs")
			end)
		else
			local P = (Economy.PASSES :: any)[k]
			local isVip = k == "vip"
			local tile = offer(
				strip,
				if isVip then "OfferVip" else "OfferCoins2x",
				if isVip then "VIP" else "2X COINS",
				if isVip then "+QUEST" else "IN MATCHES",
				P.robux,
				(if isVip then Theme.YELLOW else Theme.GOOD):Lerp(Theme.BG, 0.45),
				x,
				tw,
				stripH,
				function()
					ctx.act(Net.Action.pay, nil, `pass_{k}`)
				end
			)
			Theme.label(
				tile,
				if isVip then "VIP" else "2X",
				30,
				UDim2.fromOffset(62, stripH - 10),
				UDim2.fromOffset(36, stripH / 2),
				{
					anchor = MID,
					color = Theme.YELLOW,
					stroke = 4,
				}
			).Name =
				"Art"
		end
	end
end

function Shop.build(parent: Frame, v: Net.ProfileView, ctx: Ctx)
	parent:ClearAllChildren()
	local cv = ctx.canvas
	-- paid random restricted (PolicyService): no SPIN tab, no Fast Spin; the cosmetics stay
	local spinOk = v.spin ~= nil and v.spin.ok
	local tab: Tab = ctx.tab or "balls"
	if tab == "spin" and not spinOk then
		tab = "balls"
	end
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
	-- almost the whole screen, under the Roblox buttons (Theme.topbar, the phone rule of MOB-1)
	local top = math.max(topClear(cv), Theme.topbar.Y + 4)
	local pw = math.min(cv.X - 20, 1180)
	local ph = cv.Y - top - 8
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

	-- header, one row: tabs | coin pill, "+", close
	local close = Theme.button(
		panel,
		"X",
		UDim2.fromOffset(HEAD_H, HEAD_H),
		UDim2.fromOffset(pw - 12 - HEAD_H, HEAD_Y),
		Theme.BAD,
		nil,
		36
	)
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	-- the "+" on the coin pill opens the coin packs (62 design px: 44 px on a phone)
	local addX = pw - 12 - HEAD_H - 12 - 62
	local add = Theme.button(
		panel,
		"+",
		UDim2.fromOffset(62, 62),
		UDim2.fromOffset(addX, HEAD_Y + (HEAD_H - 62) / 2),
		ROBUX_COL,
		nil,
		40
	)
	add.Name = "AddCoins"
	add.ZIndex = 5
	add.Activated:Connect(function()
		if tab ~= "packs" then
			ctx.setTab("packs")
		end
	end)
	local pillW = 160
	local coinsX = addX - 8 - pillW
	Theme.purse(
		panel,
		"coins",
		Money.fmt(v.coins or 0),
		pillW,
		UDim2.fromOffset(coinsX, HEAD_Y + (HEAD_H - 44) / 2),
		Theme.YELLOW,
		iconFn
	)

	-- tabs: each in its own colour; the open one is bright with the yellow edge
	local tabGap = 10
	local order: { Tab } = { "balls" }
	if spinOk then
		table.insert(order, "spin")
	end
	table.insert(order, "skins")
	table.insert(order, "packs")
	local tabsW = coinsX - 26 - 16
	local tabW = math.floor((tabsW - tabGap * (#order - 1)) / #order)
	local tabName = { balls = "TabBalls", spin = "TabSpin", skins = "TabSkins", packs = "TabPacks" }
	local tabWord = { balls = "BALLS", spin = "SPIN", skins = "SKINS", packs = "COINS" }
	local tabCol = { balls = Theme.YELLOW, spin = Theme.ORANGE, skins = Theme.PURPLE, packs = ROBUX_COL }
	for i, id in order do
		local x = 16 + (i - 1) * (tabW + tabGap)
		local on = tab == id
		local col = if on then tabCol[id] else tabCol[id]:Lerp(Theme.SLOT, 0.62)
		local word = tabWord[id]
		local b = Theme.button(
			panel,
			word,
			UDim2.fromOffset(tabW, HEAD_H),
			UDim2.fromOffset(x, HEAD_Y),
			col,
			nil,
			Theme.fit(word, 32, tabW - 16, HEAD_H - 14)
		)
		b.Name = tabName[id]
		Theme.select(b, on)
		if not on then
			local l = b:FindFirstChild("Label") :: TextLabel?
			if l then
				l.TextColor3 = Theme.DIM
			end
		end
		-- the missing ball count rides on BALLS
		if id == "balls" and missingN > 0 then
			local bd = Theme.badge(b, tostring(missingN), Theme.BAD, "Left")
			bd.Position = UDim2.new(1, -18, 0, 14)
		end
		local target: Tab = id
		b.Activated:Connect(function()
			if not on then
				ctx.setTab(target)
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
			return deal.coins
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
		-- the number shares the button with the icon: fit it into what is left
		local l = b:FindFirstChild("Label") :: TextLabel?
		if l then
			local d = math.min(34, bh - math.clamp(math.floor(bh * 0.1 + 0.5), 4, 9) - 12)
			l.TextSize = Theme.fit(l.Text, l.TextSize, bw - d - 24, bh - 12)
		end
		b:SetAttribute("E", e)
		b:SetAttribute("Cur", cur)
		b.Activated:Connect(function()
			ctx.act(Net.Action.buy, e, cur)
		end)
		return b
	end

	if tab == "packs" then
		Shop.packs(body, v, ctx, bodyW, bodyH)
		GuiService.SelectedObject = close
	elseif tab == "spin" then
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
		-- one scrolling ribbon: the ball of the day as a banner on top, then the cards
		local scrollW = 12
		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Position = UDim2.fromOffset(0, 0)
		list.Size = UDim2.fromOffset(bodyW, bodyH)
		list.CanvasSize = UDim2.fromOffset(0, 0)
		list.ScrollBarThickness = 8
		list.ScrollBarImageColor3 = Theme.YELLOW
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ElasticBehavior = Enum.ElasticBehavior.Never
		list.Active = true
		list.Parent = body
		local listW = bodyW - scrollW

		local y0 = 0
		local todayCoin: TextButton? = nil
		if deal then
			local card, coins, ends = banner(list, deal, listW, BANNER_H, ctx, pay)
			Theme.rise(card, 0.08)
			todayCoin = coins
			y0 = BANNER_H + GAP
			local d = deal
			local function upd()
				ends.Text = `ENDS {left(d.endsAt - workspace:GetServerTimeNow())}`
			end
			upd()
			table.insert(ctx.frames, function()
				if ends.Parent then
					upd()
				end
			end)
		else
			-- no deal: keep an empty Ends so the old screens find it
			local ends = Theme.label(body, "", 20, UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0))
			ends.Name = "Ends"
			ends.Visible = false
		end

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
				UDim2.fromOffset(listW / 2, y0 + 60),
				{
					anchor = MID,
					color = Theme.GOOD_TXT,
					stroke = 4,
				}
			).Name =
				"Empty"
		end

		-- phone: two big cards a row; a PC canvas fits three or more (each at least 280 wide)
		local phone = phoneLike(cv)
		local cols = if phone then 2 else math.max(2, math.floor((listW + GAP) / (280 + GAP)))
		local cardW = math.floor((listW - GAP * (cols - 1)) / cols)
		local cardH = if phone then 176 else 156
		for i, e in missing do
			local col = (i - 1) % cols
			local rowI = (i - 1) // cols
			local c = shelfCard(list, e, cardW, cardH, col * (cardW + GAP), y0 + rowI * (cardH + GAP), pay)
			if i <= cols * 3 then
				Theme.rise(c, 0.14 + 0.05 * i)
			end
		end
		local rowsN = math.ceil(#missing / cols)
		list.CanvasSize = UDim2.fromOffset(0, math.max(y0 + rowsN * (cardH + GAP) - GAP, 1))
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
