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
local ROW = 84

local Shop = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
}

local function tierOf(e: number): string?
	for tier, list in Economy.TIERS do
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
		if not owned[e] and tierOf(e) then
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

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(76, 76), UDim2.new(1, -12, 0, 10), Theme.BAD, nil, 36, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local ends = Theme.text(panel, "", 22, UDim2.fromOffset(220, 28), UDim2.new(1, -110, 0, 34), {
		anchor = V2(1, 0),
		align = Enum.TextXAlignment.Right,
		color = Theme.YELLOW_TXT,
		bold = true,
	})
	ends.Name = "Ends"
	if deal then
		table.insert(ctx.frames, function()
			if ends.Parent then
				ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
			end
		end)
		ends.Text = `ENDS {left(deal.endsAt - workspace:GetServerTimeNow())}`
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 92)
	list.Size = UDim2.new(1, -24, 1, -104)
	list.CanvasSize = UDim2.fromOffset(0, math.max(#missing, 1) * ROW)
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

	local function pay(row: Frame, e: number, cur: string, x: number)
		local n = priceOf(e, cur)
		local color = if cur == "coins" then Theme.YELLOW else Theme.SLOT
		Money.icon(row, cur, 28, UDim2.fromOffset(x, 38))
		local b =
			Theme.button(row, Money.fmt(n), UDim2.fromOffset(128, 64), UDim2.fromOffset(x + 32, 6), color, nil, 26)
		b.Name = if cur == "coins" then "PayCoins" else "PayGems"
		b:SetAttribute("E", e)
		b:SetAttribute("Cur", cur)
		b.Activated:Connect(function()
			ctx.act(Net.Action.buy, e, cur)
		end)
	end

	local rowW = pw - 40
	for i, e in missing do
		local row = Theme.frame(list, UDim2.fromOffset(rowW, ROW - 8), UDim2.fromOffset(0, (i - 1) * ROW), Theme.SLOT)
		row.Name = `Row{e}`
		Theme.round(row, 14)
		local today = deal ~= nil and e == deal.e
		if today then
			row.BackgroundColor3 = Theme.SLOT:Lerp(Theme.YELLOW, 0.22)
			Theme.stroke(row, 3, Theme.YELLOW)
		end
		Theme.ball(row, e, 52, UDim2.fromOffset(34, (ROW - 8) / 2), MID)
		local title = Rules.Config.TITLE[e] or "?"
		Theme.text(row, title, 22, UDim2.fromOffset(200, 28), UDim2.fromOffset(68, if today then 8 else 22), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.nameColor(e),
		}).Name =
			"Name"
		if today then
			Theme.text(row, "TODAY -30%", 20, UDim2.fromOffset(200, 24), UDim2.fromOffset(68, 38), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = Theme.YELLOW_TXT,
				bold = true,
			}).Name =
				"Deal"
		end
		-- icon 28 + button 128, crystals at the right edge, coins just left of them
		pay(row, e, "crystals", rowW - 8 - 32 - 128)
		pay(row, e, "coins", rowW - 8 - (32 + 128) * 2 - 12)
	end

	GuiService.SelectedObject = close
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
