--!strict
-- Plaza spin screen. Personal odds and the guarantee counter come from the server (Profile.spin) and are on
-- screen before the tap. A tap sends Action "spin" with only the currency. The reel is drawn to the ball the
-- server already chose (Profile.spinResult); the tiles beside the stop are the fixed tier cycle, not a near miss.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)

local Spin = {}

Spin.TIME = 1.1

local CYCLE = { "common", "rare", "epic", "legendary", "refund" }

local function labelOf(tier: string): string
	if tier == "common" then
		return "COMMON"
	elseif tier == "rare" then
		return "RARE"
	elseif tier == "epic" then
		return "EPIC"
	elseif tier == "legendary" then
		return "LEGENDARY"
	end
	return "REFUND"
end

local function shareOf(odds: Net.SpinOdds, tier: string): number
	if tier == "common" then
		return odds.common
	elseif tier == "rare" then
		return odds.rare
	elseif tier == "epic" then
		return odds.epic
	elseif tier == "legendary" then
		return odds.legendary
	end
	return odds.refund
end

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
}

-- Sixth icon of the plaza row. Same row when it clears the coin pills; otherwise the first free cell under the row.
function Spin.iconPos(L: Theme.PlazaLayout, shop: UDim2): UDim2
	local step = L.icon + L.gap
	local function free(px: number, py: number): boolean
		if py == L.rowY and px + L.icon > L.right - L.moneyW - L.gap then
			return false
		end
		if px + L.icon > L.right - L.playW - 8 and py + L.icon > L.playY then
			return false
		end
		local sx, sy = shop.X.Offset, shop.Y.Offset
		if px < sx + L.icon and sx < px + L.icon and py < sy + L.icon and sy < py + L.icon then
			return false
		end
		return px >= 0 and py >= 0
	end
	local x = L.rowX + 5 * step
	if free(x, L.rowY) then
		return UDim2.fromOffset(x, L.rowY)
	end
	local y = L.rowY + step
	for slot = 0, 5 do
		local sx = L.rowX + slot * step
		if free(sx, y) then
			return UDim2.fromOffset(sx, y)
		end
	end
	return UDim2.fromOffset(L.rowX, y + step)
end

local function prize(hit: Net.SpinHit): string
	if hit.tier == "refund" then
		return `REFUND +{Money.fmt(hit.back)}`
	end
	local name = if hit.e then Rules.Config.TITLE[hit.e] else "?"
	return `{labelOf(hit.tier)} · {name}`
end

function Spin.build(parent: Frame, v: Net.ProfileView, ctx: Ctx)
	parent:ClearAllChildren()
	local board = v.spin
	if not board or not board.ok then
		return
	end
	local cv = ctx.canvas
	local pw = math.min(cv.X - 40, 900)
	local ph = math.min(cv.Y - 28, 500)
	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local panel = Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "SpinPanel"
	panel.Active = true
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)

	Theme.text(panel, "SPIN", 36, UDim2.fromOffset(200, 40), UDim2.fromOffset(20, 10), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 4,
	}).Name =
		"Head"

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(76, 76), UDim2.new(1, -12, 0, 10), Theme.BAD, nil, 36, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)

	local hit = v.spinResult
	-- Known before the reel moves. The strip only catches up to this.
	if hit then
		panel:SetAttribute("Decided", hit.tier)
		if hit.e then
			panel:SetAttribute("DecidedBall", hit.e)
		end
	end
	panel:SetAttribute("SpinPhase", if hit then "spinning" else "odds")

	local colW = math.floor((pw - 48) / 2)
	local hold = false
	local function column(cur: string, x: number, line: Net.SpinLine)
		local box = Theme.clear(panel, UDim2.fromOffset(colW, ph - 100), UDim2.fromOffset(x, 72))
		box.Name = if cur == "coins" then "ColCoins" else "ColGems"
		local title = if cur == "coins" then "COINS" else "CRYSTALS"
		Theme.text(box, title, 22, UDim2.fromOffset(colW, 26), UDim2.fromOffset(0, 0), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = if cur == "coins" then Theme.YELLOW else Theme.SLOT,
			bold = true,
		})
		for i, tier in CYCLE do
			local y = 32 + (i - 1) * 36
			local row = Theme.frame(box, UDim2.fromOffset(colW, 32), UDim2.fromOffset(0, y), Theme.SLOT)
			row.Name = `{if cur == "coins" then "Coin" else "Gem"}_{tier}`
			Theme.round(row, 8)
			local share = shareOf(line.odds, tier)
			local word = labelOf(tier)
			if tier == "refund" then
				word = `REFUND +{Money.fmt(line.refund)}`
			end
			Theme.text(row, word, 20, UDim2.fromOffset(colW - 72, 28), UDim2.fromOffset(8, 2), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				bold = true,
			})
			Theme.text(row, `{share}%`, 22, UDim2.fromOffset(64, 28), UDim2.fromOffset(colW - 8, 2), {
				anchor = V2(1, 0),
				align = Enum.TextXAlignment.Right,
				color = Theme.YELLOW_TXT,
				bold = true,
			}).Name =
				"Pct"
		end
		local left = line.every - line.pity
		local pityName = if line.tier == "legendary" then "LEGENDARY" else "EPIC+"
		local pity = Theme.text(
			box,
			`{pityName}  {line.pity}/{line.every} · {left} LEFT`,
			20,
			UDim2.fromOffset(colW, 24),
			UDim2.fromOffset(0, 32 + #CYCLE * 36),
			{ anchor = V2(0, 0), align = Enum.TextXAlignment.Left, color = Theme.DIM, bold = true }
		)
		pity.Name = if cur == "coins" then "PityCoins" else "PityGems"

		local bal = if cur == "coins" then v.coins or 0 else v.crystals or 0
		local b = Theme.button(
			panel,
			`SPIN {Money.fmt(line.price)}`,
			UDim2.fromOffset(colW, Theme.BTN_H),
			UDim2.fromOffset(x, ph - 16 - Theme.BTN_H),
			if cur == "coins" then Theme.YELLOW else Theme.SLOT,
			nil,
			28
		)
		b.Name = if cur == "coins" then "SpinCoins" else "SpinGems"
		if bal < line.price then
			Theme.disable(b)
		end
		b.Activated:Connect(function()
			-- "odds" only: a reel in progress stays on "spinning", and a second tap before the answer is ignored
			if hold or panel:GetAttribute("SpinPhase") ~= "odds" then
				return
			end
			local now = if cur == "coins" then v.coins or 0 else v.crystals or 0
			if now < line.price then
				return
			end
			hold = true
			ctx.act(Net.Action.spin, nil, cur)
		end)
	end

	column("coins", 16, board.coins)
	column("crystals", 32 + colW, board.crystals)

	local result = Theme.text(panel, "", 28, UDim2.fromOffset(pw - 40, 36), UDim2.fromOffset(pw / 2, 64), {
		anchor = MID,
		color = Theme.YELLOW,
		stroke = 4,
		z = 8,
	})
	result.Name = "Result"

	if hit then
		local idx = table.find(CYCLE, hit.tier) or #CYCLE
		-- Copy 4 of the fixed cycle. Neighbours are the previous and next labels in that cycle.
		local land = (4 - 1) * #CYCLE + idx
		local tiles = 6 * #CYCLE
		local tile = 140
		local window =
			Theme.clear(panel, UDim2.fromOffset(pw - 32, 48), UDim2.fromOffset(16, ph - 16 - Theme.BTN_H - 56))
		window.Name = "Reel"
		window.ClipsDescendants = true
		local strip = Theme.clear(window, UDim2.fromOffset(tiles * tile, 48), UDim2.fromOffset(0, 0))
		strip.Name = "Strip"
		for i = 1, tiles do
			local tier = CYCLE[((i - 1) % #CYCLE) + 1]
			local cell = Theme.text(
				strip,
				labelOf(tier),
				20,
				UDim2.fromOffset(tile - 8, 40),
				UDim2.fromOffset((i - 1) * tile + 4, 4),
				{ anchor = V2(0, 0), bold = true }
			)
			cell.Name = `Tile{i}`
		end
		local viewW = pw - 32
		local function at(i: number): number
			return viewW / 2 - ((i - 1) * tile + tile / 2)
		end
		local x0, x1 = at(3), at(land)
		strip.Position = UDim2.fromOffset(x0, 0)
		local t = 0
		local done = false
		local function stop()
			if done then
				return
			end
			done = true
			strip.Position = UDim2.fromOffset(x1, 0)
			panel:SetAttribute("SpinOn", hit.tier)
			panel:SetAttribute("SpinPhase", "odds")
			result.Text = prize(hit)
		end
		if Theme.reduced() then
			stop()
		else
			table.insert(ctx.frames, function(dt)
				if done or not strip.Parent then
					return
				end
				t = math.min(Spin.TIME, t + dt)
				local u = t / Spin.TIME
				local k = 1 - (1 - u) ^ 3
				strip.Position = UDim2.fromOffset(x0 + (x1 - x0) * k, 0)
				if t >= Spin.TIME then
					stop()
				end
			end)
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

return Spin
