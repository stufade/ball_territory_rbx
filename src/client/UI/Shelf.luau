--!strict
-- Cosmetic shelf, opened from the shop. Coin buy and equip are live at any ball count.
-- Coin buy and equip send Action "look" / "wear". Robux stays grey only while the product id is 0.
-- A real asset id prompts a developer product; the grant is the same Looks.grant the receipt calls.
-- Prices are Economy.LOOKS. The N/27 line is the collection size, not a lock.
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local ROW = 96

local Shelf = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
	shop: () -> (),
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

function Shelf.build(parent: Frame, v: Net.ProfileView, ctx: Ctx)
	parent:ClearAllChildren()
	local cv = ctx.canvas
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

	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local pw = math.min(cv.X - 40, 920)
	local ph = math.min(cv.Y - 28, 500)
	local panel = Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "ShelfPanel"
	panel.Active = true
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)

	Theme.text(panel, "LOOKS", 36, UDim2.fromOffset(180, 40), UDim2.fromOffset(20, 10), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 4,
	}).Name =
		"Head"
	local count = Theme.text(panel, `{n}/{need}`, 28, UDim2.fromOffset(140, 32), UDim2.fromOffset(20, 50), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.TEXT,
		bold = true,
	})
	count.Name = "Count"

	local back = Theme.button(panel, "SHOP", UDim2.fromOffset(140, 72), UDim2.fromOffset(330, 10), Theme.SLOT, nil, 22)
	back.Name = "Back"
	back.Activated:Connect(ctx.shop)
	local close =
		Theme.button(panel, "X", UDim2.fromOffset(76, 76), UDim2.new(1, -12, 0, 10), Theme.BAD, nil, 36, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local looks = Economy.LOOKS
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 92)
	list.Size = UDim2.new(1, -24, 1, -104)
	list.CanvasSize = UDim2.fromOffset(0, #looks * ROW)
	list.ScrollBarThickness = 10
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Active = true
	list.Parent = panel

	local rowW = pw - 40
	for i, look in looks do
		local id = look.id
		local mine = have[id] == true
		local row = Theme.frame(list, UDim2.fromOffset(rowW, ROW - 8), UDim2.fromOffset(0, (i - 1) * ROW), Theme.SLOT)
		row.Name = `R_{id}`
		Theme.round(row, 14)
		Theme.text(row, title(id), 22, UDim2.fromOffset(280, 28), UDim2.fromOffset(14, 10), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.TEXT,
		}).Name =
			"Name"
		Theme.text(row, kindOf(id), 20, UDim2.fromOffset(160, 24), UDim2.fromOffset(14, 42), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.DIM,
			bold = true,
		}).Name =
			"Kind"
		local function priceButton(text: string, x: number, wide: number, color: Color3, name: string): TextButton
			local b = Theme.button(row, text, UDim2.fromOffset(wide, 72), UDim2.fromOffset(x, 8), color, nil, 22)
			b.Name = name
			return b
		end
		if mine then
			Theme.text(row, "YOURS", 22, UDim2.fromOffset(140, 32), UDim2.fromOffset(rowW - 280, 28), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Right,
				color = Theme.GOOD_TXT,
				bold = true,
			}).Name =
				"Own"
			local wear = priceButton(if wearing(id) then "ON" else "WEAR", rowW - 128, 116, Theme.GO, "Wear")
			if wearing(id) then
				Theme.disable(wear, "ON")
			else
				wear.Active = true
				wear.Activated:Connect(function()
					local ball = if kindOf(id) == "SKIN"
						then (if on and on.ball >= 0 then on.ball else v.balls[1])
						else nil
					ctx.act(Net.Action.wear, ball, id)
				end)
			end
		else
			local coins = priceButton(Money.fmt(look.coins), rowW - 300, 156, Theme.YELLOW, "PayCoins")
			local pid = robux[id]
			local live = type(pid) == "number" and pid > 0
			local pay = priceButton(`{look.robux} R$`, rowW - 136, 124, Theme.SLOT, "PayRobux")
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

return Shelf
