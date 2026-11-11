--!strict
-- Plaza shop (M3.2): balls the player does not own yet, each with the coin price and the crystal price.
-- The ball of the day (Profile.dailyBall) is marked and shown at the server's discounted prices.
-- A tap sends Action "buy" (verb, element id, "coins"|"crystals"). The server prices it and refuses an owned ball.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local NEL = 27
local GEM = Color3.fromHex("#7a3cff")
local TIER_H: { [string]: number } = { common = 78, rare = 94, epic = 110, legendary = 128 }
local TIER_COL: { [string]: Color3 } = {
	common = Color3.fromHex("#3d6bff"),
	rare = Color3.fromHex("#14a4ff"),
	epic = Color3.fromHex("#c044ff"),
	legendary = Color3.fromHex("#ffd63c"),
}

local Shop = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
	shelf: () -> (),
}

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
	local owned: { [number]: boolean } = {}
	for _, e in v.balls do
		owned[e] = true
	end
	local deal = v.dailyBall
	if deal and owned[deal.e] then
		deal = nil
	end
	local missing = {}
	for e = 0, NEL - 1 do
		if not owned[e] and tierOf(e) and not (deal ~= nil and e == deal.e) then
			table.insert(missing, e)
		end
	end
	table.sort(missing, function(a: number, b: number)
		local ad, bd = deal ~= nil and a == deal.e, deal ~= nil and b == deal.e
		if ad ~= bd then
			return ad
		end
		local pa, pb = fullPrice(a, "coins"), fullPrice(b, "coins")
		if deal then
			if a == deal.e then
				pa = deal.coins
			end
			if b == deal.e then
				pb = deal.coins
			end
		end
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)

	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local pw = math.min(cv.X - 40, 920)
	local ph = math.min(cv.Y - 28, 500)
	local panel = Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "ShopPanel"
	panel.Active = true
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)

	Theme.text(panel, "SHOP", 36, UDim2.fromOffset(180, 40), UDim2.fromOffset(20, 10), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 4,
	}).Name =
		"Head"
	Theme.text(panel, `{#missing} LEFT`, 22, UDim2.fromOffset(160, 28), UDim2.fromOffset(20, 48), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.DIM,
		bold = true,
	}).Name =
		"Left"

	local looks =
		Theme.button(panel, "LOOKS", UDim2.fromOffset(150, 64), UDim2.fromOffset(210, 12), Theme.PURPLE, nil, 22)
	looks.Name = "LooksBtn"
	looks.Activated:Connect(ctx.shelf)

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(76, 76), UDim2.new(1, -12, 0, 10), Theme.BAD, nil, 36, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local ends = Theme.text(panel, "", 22, UDim2.fromOffset(240, 28), UDim2.fromOffset(212, 214), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW_TXT,
		bold = true,
	})
	ends.Name = "Ends"

	local listTop = 92
	local todayCoin: TextButton? = nil
	if deal then
		local cardH = 206
		local card = Theme.frame(panel, UDim2.fromOffset(pw - 32, cardH), UDim2.fromOffset(16, 92), Theme.PANEL)
		card.Name = "Today"
		card.ClipsDescendants = true
		Theme.round(card, 18)
		Theme.stroke(card, 4, Theme.YELLOW)
		local wash = Instance.new("UIGradient")
		wash.Rotation = 16
		wash.Color = ColorSequence.new(Color3.fromHex("#2a2410"), Theme.nameColor(deal.e):Lerp(Color3.fromHex("#1a1408"), 0.25))
		wash.Parent = card
		Theme.ball(card, deal.e, 150, UDim2.fromOffset(108, cardH / 2 + 8), MID)
		Theme.text(card, "BALL OF THE DAY", 20, UDim2.fromOffset(250, 24), UDim2.fromOffset(196, 18), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.YELLOW,
			bold = true,
		})
		Theme.text(card, Rules.Config.TITLE[deal.e] or "?", 36, UDim2.fromOffset(210, 42), UDim2.fromOffset(196, 46), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.nameColor(deal.e),
			stroke = 4,
		}).Name =
			"Name"
		Theme.text(card, "TODAY -30%", 22, UDim2.fromOffset(210, 26), UDim2.fromOffset(196, 94), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.YELLOW_TXT,
			bold = true,
		}).Name =
			"Deal"
		ends.Position = UDim2.fromOffset(212, 216)
		table.insert(ctx.frames, function()
			if ends.Parent then
				ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
			end
		end)
		ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
		if not Theme.reduced() then
			local sc = Theme.scaleOf(card)
			local age = 0
			table.insert(ctx.frames, function(dt)
				if not card.Parent then
					return
				end
				age += dt
				sc.Scale = 1 + 0.02 * math.sin(age * 2.2)
			end)
		end
		listTop = 92 + cardH + 8
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, listTop)
	list.Size = UDim2.new(1, -24, 1, -(listTop + 12))
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ScrollBarThickness = 10
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Active = true
	list.Parent = panel

	if #missing == 0 then
		Theme.text(list, "ALL YOURS", 32, UDim2.fromOffset(pw - 48, 48), UDim2.fromOffset(0, 24), {
			anchor = V2(0, 0),
			color = Theme.GOOD_TXT,
		}).Name =
			"Empty"
	end

	local function priceOf(e: number, cur: string): number
		if deal and e == deal.e then
			return if cur == "coins" then deal.coins else deal.crystals
		end
		return fullPrice(e, cur)
	end

	local function pay(row: Frame, e: number, cur: string, x: number, y: number, bw: number, bh: number, iconD: number?): TextButton
		local n = priceOf(e, cur)
		local color = if cur == "coins" then Theme.YELLOW else GEM
		local d = iconD or math.clamp(bh - 36, 26, 36)
		local shift = if iconD then math.floor(d / 2) + 12 else 34
		Money.icon(row, cur, d, UDim2.fromOffset(x, y + bh / 2))
		local b = Theme.button(row, Money.fmt(n), UDim2.fromOffset(bw, bh), UDim2.fromOffset(x + shift, y), color, nil, 26)
		b.Name = if cur == "coins" then "PayCoins" else "PayGems"
		b:SetAttribute("E", e)
		b:SetAttribute("Cur", cur)
		b.Activated:Connect(function()
			ctx.act(Net.Action.buy, e, cur)
		end)
		return b
	end

	if deal then
		local card = panel:FindFirstChild("Today") :: Frame
		local cardW = pw - 32
		local bw, bh, iconD = 148, 80, 44
		local shift = math.floor(iconD / 2) + 12
		local gemBtn = cardW - 18 - bw
		local coinBtn = gemBtn - (iconD + 28) - bw
		local y = (206 - bh) / 2 + 10
		local gems = pay(card, deal.e, "crystals", gemBtn - shift, y, bw, bh, iconD)
		local coins = pay(card, deal.e, "coins", coinBtn - shift, y, bw, bh, iconD)
		coins.NextSelectionRight = gems
		gems.NextSelectionLeft = coins
		todayCoin = coins
	end

	local rowW = pw - 40
	local y = 0
	for _, e in missing do
		local tier = tierOf(e) or "common"
		local h = TIER_H[tier] or 78
		local tint = TIER_COL[tier] or Theme.SLOT
		local row = Theme.frame(list, UDim2.fromOffset(rowW, h), UDim2.fromOffset(0, y), Theme.SLOT:Lerp(tint, 0.5))
		row.Name = `Row{e}`
		Theme.round(row, 14)
		Theme.stroke(row, if tier == "legendary" then 3 else 2, if tier == "legendary" then Theme.YELLOW else Theme.INK)
		local ballD = if tier == "legendary" then 84 elseif tier == "epic" then 68 elseif tier == "rare" then 58 else 48
		Theme.ball(row, e, ballD, UDim2.fromOffset(52, h / 2), MID)
		local title = Rules.Config.TITLE[e] or "?"
		local nameY = if h >= 94 then 14 else (h - 28) / 2
		Theme.text(row, title, if tier == "legendary" then 26 else 22, UDim2.fromOffset(220, 28), UDim2.fromOffset(104, nameY), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.nameColor(e),
		}).Name =
			"Name"
		if h >= 94 then
			Theme.text(row, string.upper(tier), 20, UDim2.fromOffset(220, 22), UDim2.fromOffset(104, nameY + 30), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = tint:Lerp(Color3.new(1, 1, 1), 0.35),
				bold = true,
			})
		end
		local bh = 64
		local by = (h - bh) / 2
		local gemX = rowW - 8 - 34 - 128
		local coinX = gemX - 12 - 34 - 128
		pay(row, e, "crystals", gemX, by, 128, bh)
		pay(row, e, "coins", coinX, by, 128, bh)
		y += h + 8
	end
	list.CanvasSize = UDim2.fromOffset(0, math.max(y, 1))

	GuiService.SelectedObject = todayCoin or close
	UserInputService.InputBegan:Connect(function(input)
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
