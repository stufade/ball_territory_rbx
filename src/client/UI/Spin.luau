--!strict
-- Plaza spin. The reel is on screen as soon as SPIN opens: one currency at a time, odds of that
-- currency before the tap, one big button with the price. A tap sends Action "spin" with only the
-- currency. The strip is the fixed tier cycle and lands on the ball the server already chose
-- (Profile.spinResult). Neighbours are the previous and next labels of that cycle, not a near miss.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local GEM = Color3.fromHex("#7a3cff")

local Spin = {}

Spin.TIME = 1.1

local CYCLE = { "common", "rare", "epic", "legendary", "refund" }

-- Wider and taller as the tier gets rarer, so the stop reads before the word does.
local SPEC: { [string]: { w: number, h: number, color: Color3 } } = {
	common = { w = 132, h = 68, color = Color3.fromHex("#3d6bff") },
	rare = { w = 158, h = 86, color = Color3.fromHex("#14a4ff") },
	epic = { w = 186, h = 104, color = Color3.fromHex("#c044ff") },
	legendary = { w = 224, h = 118, color = Color3.fromHex("#ffd63c") },
	refund = { w = 148, h = 68, color = Color3.fromHex("#2ed068") },
}

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
	local pw = math.min(cv.X - 40, 920)
	local ph = math.min(cv.Y - 28, 500)
	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local panel = Theme.frame(parent, UDim2.fromOffset(pw, ph), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "SpinPanel"
	panel.Active = true
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)

	Theme.text(panel, "SPIN", 36, UDim2.fromOffset(200, 40), UDim2.fromOffset(20, 8), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 4,
	}).Name =
		"Head"

	local close =
		Theme.button(panel, "X", UDim2.fromOffset(76, 76), UDim2.new(1, -12, 0, 8), Theme.BAD, nil, 36, V2(1, 0))
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

	local lines: { [string]: Net.SpinLine } = { coins = board.coins, crystals = board.crystals }
	local cur = if hit and lines[hit.cur] then hit.cur else "coins"

	local function prefix(c: string): string
		return if c == "coins" then "Coin" else "Gem"
	end

	-- Odds of both currencies exist before the tap. Only the selected mode is shown.
	local raw = { common = 3, rare = 3.4, epic = 3.8, legendary = 4.6, refund = 3.2 }
	local units = 0
	for _, tier in CYCLE do
		units += raw[tier]
	end
	local gap = 8
	local inner = pw - 32 - gap * (#CYCLE - 1)
	local chipW: { [string]: number } = {}
	local acc = 0
	for _, tier in CYCLE do
		local a = math.floor(inner * acc / units + 0.5)
		acc += raw[tier]
		local b = math.floor(inner * acc / units + 0.5)
		chipW[tier] = math.max(64, b - a)
	end
	local chipH: { [string]: number } = { common = 46, rare = 52, epic = 56, legendary = 62, refund = 50 }
	-- Below the close button: two mode tabs, then the odds of the selected mode.
	local oddsY, oddsH = 148, 64

	local function chips(c: string, line: Net.SpinLine)
		local box = Theme.clear(panel, UDim2.fromOffset(pw - 32, oddsH), UDim2.fromOffset(16, oddsY))
		box.Name = if c == "coins" then "OddsCoins" else "OddsGems"
		local x = 0
		for _, tier in CYCLE do
			local w, h = chipW[tier], chipH[tier]
			local color = SPEC[tier].color
			local row = Theme.frame(box, UDim2.fromOffset(w, h), UDim2.fromOffset(x, oddsH - h), color)
			row.Name = `{prefix(c)}_{tier}`
			row.ClipsDescendants = true
			Theme.round(row, 12)
			Theme.stroke(row, if tier == "legendary" then 3 else 2, Theme.INK)
			local ink = Theme.onColor(color)
			local word = labelOf(tier)
			if tier == "refund" then
				word = `+{Money.fmt(line.refund)}`
			end
			Theme.text(row, word, if tier == "legendary" then 22 else 20, UDim2.fromOffset(w - 8, 24), UDim2.fromOffset(4, 2), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
				color = ink,
				bold = true,
				stroke = 2,
			})
			Theme.text(row, `{shareOf(line.odds, tier)}%`, 22, UDim2.fromOffset(w - 8, 22), UDim2.fromOffset(4, h - 24), {
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Right,
				color = ink,
				bold = true,
				stroke = 2,
			}).Name =
				"Pct"
			x += w + gap
		end
		local left = line.every - line.pity
		local pityName = if line.tier == "legendary" then "LEGENDARY" else "EPIC+"
		local pity = Theme.text(
			panel,
			`{pityName}  {line.pity}/{line.every} · {left} LEFT`,
			20,
			UDim2.fromOffset(pw - 40, 24),
			UDim2.fromOffset(20, oddsY + oddsH + 2),
			{ anchor = V2(0, 0), align = Enum.TextXAlignment.Left, color = Theme.YELLOW_TXT, bold = true }
		)
		pity.Name = if c == "coins" then "PityCoins" else "PityGems"
	end

	chips("coins", board.coins)
	chips("crystals", board.crystals)

	local tabW = math.floor((pw - 32 - 12) / 2)
	local tabY = 88
	local modeCoins =
		Theme.button(panel, "COINS", UDim2.fromOffset(tabW, 52), UDim2.fromOffset(16, tabY), Theme.YELLOW, nil, 24)
	modeCoins.Name = "ModeCoins"
	local modeGems = Theme.button(
		panel,
		"CRYSTALS",
		UDim2.fromOffset(tabW, 52),
		UDim2.fromOffset(16 + tabW + 12, tabY),
		GEM,
		nil,
		24
	)
	modeGems.Name = "ModeGems"

	local reelY, reelH = 242, 120
	local window = Theme.frame(panel, UDim2.fromOffset(pw - 32, reelH), UDim2.fromOffset(16, reelY), Theme.BG)
	window.Name = "Reel"
	window.ClipsDescendants = true
	Theme.round(window, 16)
	Theme.stroke(window, 3, Theme.YELLOW)

	local viewW = pw - 32
	local copies = 6
	local tiles = copies * #CYCLE
	local xs: { number } = {}
	local cursor = 0
	for i = 1, tiles do
		xs[i] = cursor
		cursor += SPEC[CYCLE[((i - 1) % #CYCLE) + 1]].w
	end
	local strip = Theme.clear(window, UDim2.fromOffset(cursor, reelH), UDim2.fromOffset(0, 0))
	strip.Name = "Strip"
	for i = 1, tiles do
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		local spec = SPEC[tier]
		local cell = Theme.text(
			strip,
			labelOf(tier),
			if tier == "legendary" then 28 else 22,
			UDim2.fromOffset(spec.w - 8, spec.h - 8),
			UDim2.fromOffset(xs[i] + 4, math.floor((reelH - spec.h) / 2) + 4),
			{ anchor = V2(0, 0), color = Theme.onColor(spec.color), bold = true, stroke = 3 }
		)
		cell.Name = `Tile{i}`
		cell.BackgroundColor3 = spec.color
		cell.BackgroundTransparency = 0
		Theme.round(cell, 12)
		Theme.stroke(cell, if tier == "legendary" then 4 else 2, Theme.INK)
	end

	local function at(i: number): number
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		return viewW / 2 - (xs[i] + SPEC[tier].w / 2)
	end

	local marker = Theme.frame(window, UDim2.fromOffset(6, reelH), UDim2.new(0.5, 0, 0, 0), Theme.YELLOW, V2(0.5, 0))
	marker.Name = "Marker"
	marker.ZIndex = 6
	Theme.stroke(marker, 2, Theme.INK)

	local result = Theme.text(panel, "", 32, UDim2.fromOffset(pw - 48, 40), UDim2.fromOffset(pw / 2, reelY + reelH - 4), {
		anchor = V2(0.5, 1),
		color = Theme.YELLOW,
		stroke = 4,
		z = 8,
	})
	result.Name = "Result"

	local go = Theme.button(
		panel,
		`SPIN {Money.fmt(lines[cur].price)}`,
		UDim2.fromOffset(pw - 32, Theme.BTN_H),
		UDim2.fromOffset(16, ph - 14 - Theme.BTN_H),
		if cur == "coins" then Theme.YELLOW else GEM,
		nil,
		36
	)
	go.Name = "SpinGo"

	local hold = false
	local function paint(c: string)
		if panel:GetAttribute("SpinPhase") == "spinning" and c ~= cur then
			return
		end
		cur = c
		panel:SetAttribute("SpinCur", c)
		local coinOn = c == "coins"
		local oddsC = panel:FindFirstChild("OddsCoins") :: GuiObject?
		local oddsG = panel:FindFirstChild("OddsGems") :: GuiObject?
		local pityC = panel:FindFirstChild("PityCoins") :: GuiObject?
		local pityG = panel:FindFirstChild("PityGems") :: GuiObject?
		if oddsC then
			oddsC.Visible = coinOn
		end
		if oddsG then
			oddsG.Visible = not coinOn
		end
		if pityC then
			pityC.Visible = coinOn
		end
		if pityG then
			pityG.Visible = not coinOn
		end
		Theme.select(modeCoins, coinOn)
		Theme.select(modeGems, not coinOn)
		local price = lines[c].price
		local bal = if c == "coins" then v.coins or 0 else v.crystals or 0
		local afford = bal >= price
		local label = go:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = `SPIN {Money.fmt(price)}`
			label.TextColor3 = if afford then Theme.TEXT else Theme.DIM
		end
		go.Active = afford and panel:GetAttribute("SpinPhase") ~= "spinning"
		go.BackgroundColor3 = if afford then (if c == "coins" then Theme.YELLOW else GEM) else Theme.PANEL_HI
	end

	modeCoins.Activated:Connect(function()
		paint("coins")
	end)
	modeGems.Activated:Connect(function()
		paint("crystals")
	end)
	go.Activated:Connect(function()
		if hold or panel:GetAttribute("SpinPhase") ~= "odds" then
			return
		end
		local line = lines[cur]
		local now = if cur == "coins" then v.coins or 0 else v.crystals or 0
		if now < line.price then
			return
		end
		hold = true
		ctx.act(Net.Action.spin, nil, cur)
	end)
	paint(cur)

	local span = 0
	for _, tier in CYCLE do
		span += SPEC[tier].w
	end

	if hit then
		local idx = table.find(CYCLE, hit.tier) or #CYCLE
		-- Copy 4 of the fixed cycle. Neighbours are the previous and next labels in that cycle.
		local land = (4 - 1) * #CYCLE + idx
		local x0, x1 = at(3), at(land)
		strip.Position = UDim2.fromOffset(x0, 0)
		local prizeTile = strip:FindFirstChild(`Tile{land}`) :: TextLabel?
		local t = 0
		local done = false
		local function stop()
			if done then
				return
			end
			done = true
			strip.Position = UDim2.fromOffset(x1, 0)
			if prizeTile then
				prizeTile.ZIndex = 5
				Theme.scaleOf(prizeTile).Scale = 1.12
			end
			Theme.scaleOf(marker).Scale = 1.2
			if hit.e then
				marker.BackgroundColor3 = Theme.nameColor(hit.e)
			end
			panel:SetAttribute("SpinOn", hit.tier)
			panel:SetAttribute("SpinPhase", "odds")
			local bal = if cur == "coins" then v.coins or 0 else v.crystals or 0
			go.Active = bal >= lines[cur].price
			result.Text = prize(hit)
			result.TextColor3 = if hit.e then Theme.nameColor(hit.e) else Theme.YELLOW
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
				local k = 1 - (1 - u) ^ 4
				strip.Position = UDim2.fromOffset(x0 + (x1 - x0) * k, 0)
				if prizeTile and u > 0.82 then
					Theme.scaleOf(prizeTile).Scale = 1 + 0.12 * (u - 0.82) / 0.18
				end
				if t >= Spin.TIME then
					stop()
				end
			end)
		end
	else
		strip.Position = UDim2.fromOffset(at(3), 0)
		if not Theme.reduced() then
			local x = at(3)
			local base = x
			table.insert(ctx.frames, function(dt)
				if not strip.Parent or panel:GetAttribute("SpinPhase") == "spinning" then
					return
				end
				x -= 70 * dt
				if x < base - span then
					x += span
				end
				strip.Position = UDim2.fromOffset(x, 0)
			end)
		end
	end

	if not Theme.reduced() then
		local sc = Theme.scaleOf(go)
		local age = 0
		table.insert(ctx.frames, function(dt)
			if not go.Parent then
				return
			end
			if panel:GetAttribute("SpinPhase") == "spinning" or not go.Active then
				sc.Scale = 1
				return
			end
			age += dt
			sc.Scale = 1 + 0.035 * math.sin(age * 3)
		end)
	end

	GuiService.SelectedObject = if go.Active then go else close
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
