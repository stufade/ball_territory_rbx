--!strict
-- Skins tab of the shop. Every Economy.LOOKS row is on the list: icon, name, kind, price, buy.
-- Coin buy and equip send Action "look" / "wear". Robux stays grey only while the product id is 0.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new

local Shelf = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
}

local KIND_COL: { [string]: Color3 } = {
	SKIN = Color3.fromHex("#ff7ad1"),
	TRAIL = Color3.fromHex("#7ad0ff"),
	FORCE = Color3.fromHex("#ffd63c"),
	FRAME = Color3.fromHex("#e0a060"),
	LOBBY = Color3.fromHex("#b04cff"),
	CARD = Color3.fromHex("#5af096"),
}

local function title(id: string): string
	return string.upper((string.gsub(id, "_", " ")))
end

local function kindOf(id: string): string
	if string.sub(id, 1, 5) == "skin_" then
		return "SKIN"
	elseif string.sub(id, 1, 6) == "trail_" then
		return "TRAIL"
	elseif string.sub(id, 1, 6) == "force_" then
		return "FORCE"
	elseif string.sub(id, 1, 6) == "frame_" then
		return "FRAME"
	elseif id == "podium_spot" then
		return "LOBBY"
	end
	return "CARD"
end

local function prompt(productId: number)
	local player = Players.LocalPlayer
	if player and type(MarketplaceService.PromptProductPurchase) == "function" then
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end
end

-- host is the shop body. One card per look, buttons inside the card.
function Shelf.fill(host: Frame, v: Net.ProfileView, ctx: Ctx, w: number, h: number)
	local shelf = v.shelf
	local n = if shelf then shelf.n else #v.balls
	local need = if shelf then shelf.need else (v.total or 27)
	local have: { [string]: boolean } = {}
	if shelf then
		for _, id in shelf.owned do
			have[id] = true
		end
	end
	local on = if shelf then shelf.on else nil
	local robux: { [string]: number } = if shelf then shelf.robux else {}
	local function wearing(id: string): boolean
		if not on then
			return false
		end
		return on.skin == id
			or on.trail == id
			or on.force == id
			or on.frame == id
			or (id == "podium_spot" and on.podium)
			or (id == "ko_card" and on.ko)
	end

	local count = Theme.label(host, `{n}/{need}`, 28, UDim2.fromOffset(160, 32), UDim2.fromOffset(8, 2), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.TEXT,
	})
	count.Name = "Count"
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 20
	cap.MaxTextSize = 28
	cap.Parent = count

	local listTop = 40
	local list = Instance.new("ScrollingFrame")
	list.Name = "Looks"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, listTop)
	list.Size = UDim2.fromOffset(w, math.max(40, h - listTop))
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ScrollBarThickness = 8
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.Active = true
	list.Parent = host

	local looks = Economy.LOOKS
	local rowW = w - 16
	local rowH = 92
	local step = 100
	for i, look in looks do
		local id = look.id
		local mine = have[id] == true
		local kind = kindOf(id)
		local row = Theme.frame(list, UDim2.fromOffset(rowW, rowH), UDim2.fromOffset(0, (i - 1) * step), Theme.SLOT)
		row.Name = `R_{id}`
		row.ClipsDescendants = true
		Theme.round(row, 14)
		Theme.stroke(row, 2, KIND_COL[kind] or Theme.INK)
		local icon = Theme.frame(row, UDim2.fromOffset(56, 56), UDim2.fromOffset(12, 18), KIND_COL[kind] or Theme.PURPLE)
		icon.Name = "Icon"
		Theme.round(icon, 14)
		Theme.stroke(icon, 2, Theme.INK)
		Theme.label(icon, string.sub(kind, 1, 1), 26, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), {
			anchor = V2(0.5, 0.5),
			color = Theme.INK,
		})
		local nameW = math.max(100, rowW - 380)
		Theme.label(row, title(id), 22, UDim2.fromOffset(nameW, 26), UDim2.fromOffset(80, 16), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.TEXT,
		}).Name = "Name"
		Theme.label(row, kind, 20, UDim2.fromOffset(nameW, 22), UDim2.fromOffset(80, 48), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.DIM,
		}).Name = "Kind"

		local bh = 72
		local by = math.floor((rowH - bh) / 2)
		local function priceButton(text: string, x: number, wide: number, color: Color3, bname: string): TextButton
			local b = Theme.button(row, text, UDim2.fromOffset(wide, bh), UDim2.fromOffset(x, by), color, nil, 22)
			b.Name = bname
			return b
		end
		if mine then
			local wearW = 116
			local wearX = rowW - 10 - wearW
			Theme.label(row, "YOURS", 22, UDim2.fromOffset(120, 28), UDim2.fromOffset(wearX - 128, 32), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Right,
				color = Theme.GOOD_TXT,
			}).Name = "Own"
			local wear = priceButton(if wearing(id) then "ON" else "WEAR", wearX, wearW, Theme.GO, "Wear")
			if wearing(id) then
				Theme.disable(wear, "ON")
			else
				wear.Active = true
				wear.Activated:Connect(function()
					local ball = if kind == "SKIN"
						then (if on and on.ball >= 0 then on.ball else v.balls[1])
						else nil
					ctx.act(Net.Action.wear, ball, id)
				end)
			end
		else
			local coinW, gemW = 148, 118
			local gemX = rowW - 10 - gemW
			local coinX = gemX - 8 - coinW
			local coins = priceButton(Money.fmt(look.coins), coinX, coinW, Theme.YELLOW, "PayCoins")
			local pid = robux[id]
			local live = type(pid) == "number" and pid > 0
			local pay = priceButton(`{look.robux} R$`, gemX, gemW, Theme.SLOT, "PayRobux")
			coins.Active = true
			coins.Activated:Connect(function()
				ctx.act(Net.Action.look, nil, id)
			end)
			if live then
				pay.Active = true
				pay.Activated:Connect(function()
					prompt(pid :: number)
				end)
			else
				Theme.disable(pay)
			end
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, math.max(#looks * step, 1))
end

return Shelf
