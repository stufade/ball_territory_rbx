--!strict
-- One plaza shop, three tabs: BALLS, SPIN, SKINS. The ball of the day is a featured banner.
-- The rest of the shelf is a grid of cards. SPIN on the plaza opens this same panel on the spin tab.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Shelf = require("./Shelf")
local Spin = require("./Spin")
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local NEL = 27
local GEM = Color3.fromHex("#7a3cff")

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
	Theme.pop(panel, 0, 0.92)

	Theme.label(panel, "SHOP", 34, UDim2.fromOffset(150, 36), UDim2.fromOffset(16, 12), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
	}).Name =
		"Head"

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(72, 72), UDim2.fromOffset(pw - 16 - 72, 10), Theme.BAD, nil, 34)
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local pillW = 142
	local gemsX = pw - 16 - 72 - 12 - pillW
	local coinsX = gemsX - 8 - pillW
	local function bal(cur: string, x: number, n: number)
		local box = Theme.frame(panel, UDim2.fromOffset(pillW, 40), UDim2.fromOffset(x, 26), Theme.BG)
		box.Name = if cur == "coins" then "BalCoins" else "BalGems"
		Theme.round(box, 20)
		Theme.stroke(box, 2, Theme.INK)
		Money.icon(box, cur, 28, UDim2.fromOffset(18, 20))
		Theme.label(box, Money.fmt(n), 22, UDim2.fromOffset(pillW - 44, 26), UDim2.new(1, -10, 0.5, 0), {
			anchor = V2(1, 0.5),
			align = Enum.TextXAlignment.Right,
			color = if cur == "coins" then Theme.YELLOW else GEM,
		})
	end
	bal("coins", coinsX, v.coins or 0)
	bal("crystals", gemsX, v.crystals or 0)

	local missingN = 0
	for e = 0, NEL - 1 do
		if not owned[e] and tierOf(e) and not (deal ~= nil and e == deal.e) then
			missingN += 1
		end
	end
	Theme.label(panel, `{missingN} LEFT`, 20, UDim2.fromOffset(140, 22), UDim2.fromOffset(16, 50), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.DIM,
	}).Name =
		"Left"

	local tabY, tabH = 90, 48
	local tabGap = 8
	local tabW = math.floor((pw - 32 - tabGap * 2) / 3)
	local tabs: { { Tab } } = { { "balls" :: Tab }, { "spin" :: Tab }, { "skins" :: Tab } }
	local tabName = { balls = "TabBalls", spin = "TabSpin", skins = "TabSkins" }
	local tabWord = { balls = "BALLS", spin = "SPIN", skins = "SKINS" }
	local tabCol = { balls = Theme.YELLOW, spin = Theme.ORANGE, skins = Theme.PURPLE }
	for i, wrap in tabs do
		local id = wrap[1]
		local x = 16 + (i - 1) * (tabW + tabGap)
		local on = tab == id
		local b = Theme.button(
			panel,
			tabWord[id],
			UDim2.fromOffset(tabW, tabH),
			UDim2.fromOffset(x, tabY),
			if on then tabCol[id] else Theme.SLOT,
			nil,
			22
		)
		b.Name = tabName[id]
		Theme.select(b, on)
		b.Activated:Connect(function()
			if tab ~= id then
				ctx.setTab(id)
			end
		end)
	end

	local bodyY = tabY + tabH + 8
	local bodyW, bodyH = pw - 24, ph - bodyY - 12
	local body = Theme.clear(panel, UDim2.fromOffset(bodyW, bodyH), UDim2.fromOffset(12, bodyY))
	body.Name = "Body"
	body.ClipsDescendants = true

	local function priceOf(e: number, cur: string): number
		if deal and e == deal.e then
			return if cur == "coins" then deal.coins else deal.crystals
		end
		return fullPrice(e, cur)
	end

	local function pay(row: Frame, e: number, cur: string, x: number, y: number, bw: number, bh: number): TextButton
		local n = priceOf(e, cur)
		local color = if cur == "coins" then Theme.YELLOW else GEM
		local b = Theme.button(row, Money.fmt(n), UDim2.fromOffset(bw, bh), UDim2.fromOffset(x, y), color, nil, 22)
		b.Name = if cur == "coins" then "PayCoins" else "PayGems"
		b.ClipsDescendants = true
		b:SetAttribute("E", e)
		b:SetAttribute("Cur", cur)
		local icon = Money.icon(b, cur, math.min(28, bh - 28), UDim2.fromOffset(18, bh / 2))
		icon.ZIndex = 4
		local label = b:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Position = UDim2.new(0.5, 10, 0, 0)
		end
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
		local listTop = 0
		local todayCoin: TextButton? = nil
		local endsParent: Instance = panel
		if deal then
			local tier = tierOf(deal.e) or "common"
			local tint = TIER_COL[tier] or Theme.YELLOW
			local cardH = math.clamp(math.floor(bodyH * 0.48), 188, 228)
			local card = Theme.frame(body, UDim2.fromOffset(bodyW, cardH), UDim2.fromOffset(0, 0), tint)
			card.Name = "Today"
			card.ClipsDescendants = true
			Theme.round(card, 18)
			Theme.stroke(card, 5, tint:Lerp(Color3.new(1, 1, 1), 0.35))
			local wash = Instance.new("UIGradient")
			wash.Rotation = 16
			wash.Color = ColorSequence.new(tint:Lerp(Color3.new(1, 1, 1), 0.12), tint:Lerp(Theme.BG, 0.55))
			wash.Parent = card
			endsParent = card
			local ballD = math.floor(cardH * 0.74)
			local span = math.ceil(ballD / 0.88)
			local bx, byc = 10 + span / 2, cardH / 2
			local rayLen = math.floor((bodyW - bx) * 2.2)
			local glowCol = Color3.fromHex("#ffd24a")
			for i = 1, 14 do
				local ray = Theme.frame(
					card,
					UDim2.fromOffset(18, rayLen),
					UDim2.fromOffset(bx, byc),
					if i % 2 == 0 then glowCol else Color3.new(1, 1, 1),
					MID
				)
				ray.Rotation = 8 + (i - 1) * (164 / 13)
				ray.BackgroundTransparency = 0.22
				ray.ZIndex = 1
			end
			local glow = Theme.disc(card, math.floor(span * 1.45), glowCol, UDim2.fromOffset(bx, byc), 0.28)
			glow.ZIndex = 2
			local icon = Theme.ball(card, deal.e, ballD, UDim2.fromOffset(bx, byc), MID)
			icon.Name = "Icon"
			icon.ZIndex = 4
			local bw, bh = 156, 68
			local gemX = bodyW - 14 - bw
			local coinX = gemX - 8 - bw
			local textX = math.floor(10 + span + 14)
			local textW = math.max(80, coinX - 12 - textX)
			local title = Rules.Config.TITLE[deal.e] or "?"
			local metaY = cardH - 30
			local nameH = metaY - 36
			local namePx = Theme.fit(title, 96, textW, nameH)
			Theme.label(card, "BALL OF THE DAY", 22, UDim2.fromOffset(textW, 24), UDim2.fromOffset(textX, 6), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.YELLOW,
			})
			Theme.label(card, title, namePx, UDim2.fromOffset(textW, nameH), UDim2.fromOffset(textX, 30), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.nameColor(deal.e),
			}).Name =
				"Name"
			local tierW = math.floor(textW * 0.28)
			Theme.label(
				card,
				TIER_WORD[tier] or "COMMON",
				20,
				UDim2.fromOffset(tierW, 22),
				UDim2.fromOffset(textX, metaY),
				{
					anchor = V2(0, 0),
					align = Enum.TextXAlignment.Left,
					color = tint:Lerp(Color3.new(1, 1, 1), 0.35),
				}
			).Name =
				"Tier"
			Theme.label(
				card,
				"TODAY -30%",
				20,
				UDim2.fromOffset(math.floor(textW * 0.34), 22),
				UDim2.fromOffset(textX + tierW, metaY),
				{
					anchor = V2(0, 0),
					align = Enum.TextXAlignment.Left,
					color = Theme.YELLOW_TXT,
				}
			).Name =
				"Deal"
			local by = math.floor((cardH - bh) / 2)
			local gems = pay(card, deal.e, "crystals", gemX, by, bw, bh)
			local coins = pay(card, deal.e, "coins", coinX, by, bw, bh)
			coins.NextSelectionRight = gems
			gems.NextSelectionLeft = coins
			todayCoin = coins
			listTop = cardH + 8
		end

		local ends = Theme.label(endsParent, "", 22, UDim2.fromOffset(220, 24), UDim2.fromOffset(16, 16), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.YELLOW_TXT,
		})
		ends.Name = "Ends"
		if not deal then
			ends.Visible = false
			ends.Position = UDim2.fromOffset(0, 0)
			ends.Size = UDim2.fromOffset(1, 1)
		else
			local bannerH = math.clamp(math.floor(bodyH * 0.48), 188, 228)
			local textX = math.floor(10 + math.ceil(math.floor(bannerH * 0.74) / 0.88) + 14)
			local coinX = bodyW - 14 - 156 - 8 - 156
			local textW = math.max(80, coinX - 12 - textX)
			ends.Position = UDim2.fromOffset(textX + math.floor(textW * 0.62), bannerH - 30)
			ends.Size = UDim2.fromOffset(math.max(80, math.floor(textW * 0.38)), 22)
		end
		if deal then
			table.insert(ctx.frames, function()
				if ends.Parent and deal then
					ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
				end
			end)
			ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
		end

		local list = Instance.new("ScrollingFrame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Position = UDim2.fromOffset(0, listTop)
		list.Size = UDim2.fromOffset(bodyW, math.max(40, bodyH - listTop))
		list.CanvasSize = UDim2.fromOffset(0, 0)
		list.ScrollBarThickness = 8
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
			Theme.label(list, "ALL YOURS", 28, UDim2.fromOffset(bodyW - 16, 40), UDim2.fromOffset(0, 12), {
				anchor = V2(0, 0),
				color = Theme.GOOD_TXT,
			}).Name =
				"Empty"
		end

		local gap = 8
		local cols = if bodyW >= 680 then 3 else 2
		local cardW = math.floor((bodyW - 12 - gap * (cols - 1)) / cols)
		local room = math.max(40, bodyH - listTop)
		local natural = 168
		local fit = math.max(1, math.floor((room + gap) / (natural + gap)))
		local cardH = math.min(natural, math.floor((room - gap * (fit - 1)) / fit))
		local shown = fit * cardH + gap * (fit - 1)
		if shown > room then
			fit = 1
			cardH = math.min(natural, room)
			shown = cardH
		end
		list.Size = UDim2.fromOffset(bodyW, shown)
		for i, e in missing do
			local tier = tierOf(e) or "common"
			local tint = TIER_COL[tier] or Theme.SLOT
			local col = (i - 1) % cols
			local rowI = (i - 1) // cols
			local row = Theme.frame(
				list,
				UDim2.fromOffset(cardW, cardH),
				UDim2.fromOffset(col * (cardW + gap), rowI * (cardH + gap)),
				Theme.SLOT:Lerp(tint, 0.5)
			)
			row.Name = `Row{e}`
			row.ClipsDescendants = true
			Theme.round(row, 16)
			Theme.stroke(row, if tier == "legendary" then 4 else 3, tint)
			local ballD = 58
			Theme.disc(row, ballD + 14, tint, UDim2.fromOffset(cardW / 2, 36), 0.5)
			local icon = Theme.ball(row, e, ballD, UDim2.fromOffset(cardW / 2, 36), MID)
			icon.Name = "Icon"
			Theme.label(
				row,
				Rules.Config.TITLE[e] or "?",
				20,
				UDim2.fromOffset(cardW - 12, 22),
				UDim2.fromOffset(6, 66),
				{
					color = Theme.nameColor(e),
				}
			).Name =
				"Name"
			Theme.label(
				row,
				TIER_WORD[tier] or "COMMON",
				20,
				UDim2.fromOffset(cardW - 12, 20),
				UDim2.fromOffset(6, 88),
				{
					color = tint:Lerp(Color3.new(1, 1, 1), 0.45),
				}
			).Name =
				"Tier"
			local bh = 44
			local by = cardH - 8 - bh
			local bw = math.floor((cardW - 16 - 6) / 2)
			pay(row, e, "crystals", cardW - 8 - bw, by, bw, bh)
			pay(row, e, "coins", 8, by, bw, bh)
		end
		local rowsN = math.ceil(#missing / cols)
		list.CanvasSize = UDim2.fromOffset(0, math.max(rowsN * (cardH + gap), 1))
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
