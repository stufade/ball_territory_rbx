--!strict
-- One plaza shop, three tabs: BALLS, SPIN, SKINS. The ball of the day is a large offer.
-- Every price button is laid out inside its card. SPIN on the plaza opens this panel on the spin tab.
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

local TIER_H: { [string]: number } = { common = 86, rare = 98, epic = 110, legendary = 124 }
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
	local pw = math.min(cv.X - 32, 900)
	local ph = math.min(cv.Y - 32, 508)
	local panel = Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
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
	}).Name = "Head"

	local close = Theme.button(panel, "X", UDim2.fromOffset(72, 72), UDim2.fromOffset(pw - 16 - 72, 10), Theme.BAD, nil, 34)
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
		Theme.label(
			box,
			Money.fmt(n),
			22,
			UDim2.fromOffset(pillW - 44, 26),
			UDim2.new(1, -10, 0.5, 0),
			{
				anchor = V2(1, 0.5),
				align = Enum.TextXAlignment.Right,
				color = if cur == "coins" then Theme.YELLOW else GEM,
			}
		)
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
	}).Name = "Left"

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
			local cardH = 168
			local card = Theme.frame(body, UDim2.fromOffset(bodyW, cardH), UDim2.fromOffset(0, 0), Theme.PANEL)
			card.Name = "Today"
			card.ClipsDescendants = true
			Theme.round(card, 16)
			Theme.stroke(card, 4, tint)
			endsParent = card
			local ballD = 96
			Theme.ball(card, deal.e, ballD, UDim2.fromOffset(78, cardH / 2), MID).Name = "Icon"
			local textX = 150
			Theme.label(card, "BALL OF THE DAY", 20, UDim2.fromOffset(280, 22), UDim2.fromOffset(textX, 16), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.YELLOW,
			})
			Theme.label(card, Rules.Config.TITLE[deal.e] or "?", 32, UDim2.fromOffset(240, 36), UDim2.fromOffset(textX, 40), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.nameColor(deal.e),
			}).Name = "Name"
			Theme.label(card, TIER_WORD[tier] or "COMMON", 20, UDim2.fromOffset(200, 22), UDim2.fromOffset(textX, 80), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = tint:Lerp(Color3.new(1, 1, 1), 0.35),
			}).Name = "Tier"
			Theme.label(card, "TODAY -30%", 20, UDim2.fromOffset(200, 22), UDim2.fromOffset(textX, 106), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.YELLOW_TXT,
			}).Name = "Deal"
			local bw, bh = 148, 64
			local gemX = bodyW - 12 - bw
			local coinX = gemX - 8 - bw
			local by = math.floor((cardH - bh) / 2)
			local gems = pay(card, deal.e, "crystals", gemX, by, bw, bh)
			local coins = pay(card, deal.e, "coins", coinX, by, bw, bh)
			coins.NextSelectionRight = gems
			gems.NextSelectionLeft = coins
			todayCoin = coins
			listTop = cardH + 8
		end

		local ends = Theme.label(endsParent, "", 20, UDim2.fromOffset(220, 22), UDim2.fromOffset(150, 132), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.YELLOW_TXT,
		})
		ends.Name = "Ends"
		if not deal then
			ends.Visible = false
			ends.Position = UDim2.fromOffset(0, 0)
			ends.Size = UDim2.fromOffset(1, 1)
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
			}).Name = "Empty"
		end

		local rowW = bodyW - 16
		local y = 0
		for _, e in missing do
			local tier = tierOf(e) or "common"
			local rh = TIER_H[tier] or 86
			local tint = TIER_COL[tier] or Theme.SLOT
			local row = Theme.frame(list, UDim2.fromOffset(rowW, rh), UDim2.fromOffset(0, y), Theme.SLOT:Lerp(tint, 0.45))
			row.Name = `Row{e}`
			row.ClipsDescendants = true
			Theme.round(row, 14)
			Theme.stroke(row, if tier == "legendary" then 4 else 3, tint)
			local visual = rh - 20
			local ballD = math.floor(visual / 1.14)
			local icon = Theme.ball(row, e, ballD, UDim2.fromOffset(10 + visual / 2, rh / 2), MID)
			icon.Name = "Icon"
			local bh, bw = 60, 132
			local by = math.floor((rh - bh) / 2)
			local gemX = rowW - 8 - bw
			local coinX = gemX - 8 - bw
			local textX = 16 + visual
			local textW = math.max(80, coinX - 8 - textX)
			Theme.label(row, Rules.Config.TITLE[e] or "?", 22, UDim2.fromOffset(textW, 24), UDim2.fromOffset(textX, 14), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.nameColor(e),
			}).Name = "Name"
			Theme.label(row, TIER_WORD[tier] or "COMMON", 20, UDim2.fromOffset(textW, 22), UDim2.fromOffset(textX, 42), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = tint:Lerp(Color3.new(1, 1, 1), 0.4),
			}).Name = "Tier"
			pay(row, e, "crystals", gemX, by, bw, bh)
			pay(row, e, "coins", coinX, by, bw, bh)
			y += rh + 8
		end
		list.CanvasSize = UDim2.fromOffset(0, math.max(y, 1))
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
