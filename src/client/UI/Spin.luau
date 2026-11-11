--!strict
-- Spin page inside the shop. The reel is on screen as soon as the SPIN tab opens: one currency at a
-- time, odds of that currency before the tap, the price directly under the odds. A tap sends Action
-- "spin" with only the currency. Tiles are real ball icons. Neighbours are the previous and next
-- balls of the fixed cycle, not a near miss. The stop is the ball the server already chose.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
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

local SPEC: { [string]: { w: number, color: Color3 } } = {
	common = { w = 150, color = Color3.fromHex("#3d6bff") },
	rare = { w = 166, color = Color3.fromHex("#14a4ff") },
	epic = { w = 184, color = Color3.fromHex("#c044ff") },
	legendary = { w = 214, color = Color3.fromHex("#ffd63c") },
	refund = { w = 150, color = Color3.fromHex("#2ed068") },
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

local function playSfx(name: string)
	local ok, mod = pcall(function()
		local ui = script.Parent
		local client = ui.Parent
		local render = client:FindFirstChild("Render")
		if not render then
			return nil
		end
		local sfx = render:FindFirstChild("Sfx")
		if not sfx then
			return nil
		end
		return require(sfx)
	end)
	if ok and type(mod) == "table" then
		local play = (mod :: any).play
		if type(play) == "function" then
			pcall(play, name)
		end
	end
end

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
	panel: Frame,
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

local function heightOf(tier: string, reelH: number): number
	local mul = if tier == "legendary" then 1 elseif tier == "epic" then 0.9 elseif tier == "rare" then 0.82 else 0.74
	return math.max(64, math.floor((reelH - 14) * mul))
end

-- host is the shop body. w and h are its pixel size. Everything clickable stays inside host.
function Spin.fill(host: Frame, v: Net.ProfileView, ctx: Ctx, w: number, h: number)
	local board = v.spin
	local panel = ctx.panel
	if not board or not board.ok then
		Theme.label(host, "SPIN IS OFF", 28, UDim2.fromOffset(w - 24, 40), UDim2.fromOffset(12, 24), {
			color = Theme.DIM,
		})
		return
	end

	local hit = v.spinResult
	if hit then
		panel:SetAttribute("Decided", hit.tier)
		if hit.e then
			panel:SetAttribute("DecidedBall", hit.e)
		end
	end
	panel:SetAttribute("SpinPhase", if hit then "spinning" else "odds")

	local owned: { [number]: boolean } = {}
	for _, e in v.balls do
		owned[e] = true
	end
	local function sample(tier: string): number
		local list = (Economy.TIERS :: { [string]: { number } })[tier]
		for _, e in list do
			if not owned[e] then
				return e
			end
		end
		return list[1]
	end
	local face: { [string]: number } = {
		common = sample("common"),
		rare = sample("rare"),
		epic = sample("epic"),
		legendary = sample("legendary"),
	}

	local lines: { [string]: Net.SpinLine } = { coins = board.coins, crystals = board.crystals }
	local cur = if hit and lines[hit.cur] then hit.cur else "coins"

	local gap = 6
	local modeH, oddsH, pityH, btnH = 44, 66, 22, 58
	local chrome = modeH + oddsH + pityH + btnH + gap * 4
	local reelH = h - chrome
	if reelH < 108 then
		oddsH, btnH = 58, 52
		chrome = modeH + oddsH + pityH + btnH + gap * 4
		reelH = math.max(88, h - chrome)
	end
	reelH = math.min(reelH, 188)

	local function prefix(c: string): string
		return if c == "coins" then "Coin" else "Gem"
	end

	local y = 0
	local tabW = math.floor((w - 16 - 8) / 2)
	local modeCoins = Theme.button(host, "COINS", UDim2.fromOffset(tabW, modeH), UDim2.fromOffset(8, y), Theme.YELLOW, nil, 22)
	modeCoins.Name = "ModeCoins"
	local modeGems =
		Theme.button(host, "CRYSTALS", UDim2.fromOffset(tabW, modeH), UDim2.fromOffset(8 + tabW + 8, y), GEM, nil, 22)
	modeGems.Name = "ModeGems"
	y += modeH + gap

	local chipW = math.floor((w - 16 - 8 * (#CYCLE - 1)) / #CYCLE)
	local function chips(c: string, line: Net.SpinLine)
		local box = Theme.clear(host, UDim2.fromOffset(w - 16, oddsH), UDim2.fromOffset(8, y))
		box.Name = if c == "coins" then "OddsCoins" else "OddsGems"
		local x = 0
		for _, tier in CYCLE do
			local color = SPEC[tier].color
			local row = Theme.frame(box, UDim2.fromOffset(chipW, oddsH), UDim2.fromOffset(x, 0), Theme.SLOT)
			row.Name = `{prefix(c)}_{tier}`
			row.ClipsDescendants = true
			Theme.round(row, 12)
			Theme.stroke(row, if tier == "legendary" then 3 else 2, color)
			if tier == "refund" then
				Money.icon(row, c, 32, UDim2.fromOffset(chipW / 2, 24))
			else
				local icon = Theme.ball(row, face[tier], 34, UDim2.fromOffset(chipW / 2, 26), MID)
				icon.Name = "Icon"
			end
			Theme.label(row, `{shareOf(line.odds, tier)}%`, 20, UDim2.fromOffset(chipW - 8, 22), UDim2.fromOffset(4, oddsH - 24), {
				color = Theme.TEXT,
			}).Name = "Pct"
			x += chipW + 8
		end
	end
	chips("coins", board.coins)
	chips("crystals", board.crystals)
	y += oddsH + 2

	local function pityLine(c: string, line: Net.SpinLine)
		local left = line.every - line.pity
		local pityName = if line.tier == "legendary" then "LEGENDARY" else "EPIC+"
		local pity = Theme.label(
			host,
			`{pityName}  {line.pity}/{line.every} · {left} LEFT`,
			20,
			UDim2.fromOffset(w - 20, pityH),
			UDim2.fromOffset(10, y),
			{ align = Enum.TextXAlignment.Left, color = Theme.YELLOW_TXT }
		)
		pity.Name = if c == "coins" then "PityCoins" else "PityGems"
	end
	pityLine("coins", board.coins)
	pityLine("crystals", board.crystals)
	y += pityH + gap

	local go = Theme.button(
		host,
		`SPIN {Money.fmt(lines[cur].price)}`,
		UDim2.fromOffset(w - 24, btnH),
		UDim2.fromOffset(12, y),
		if cur == "coins" then Theme.YELLOW else GEM,
		nil,
		28
	)
	go.Name = "SpinGo"
	y += btnH + gap

	local window = Theme.frame(host, UDim2.fromOffset(w - 16, reelH), UDim2.fromOffset(8, y), Theme.BG)
	window.Name = "Reel"
	window.ClipsDescendants = true
	Theme.round(window, 16)
	Theme.stroke(window, 3, Theme.YELLOW)

	local viewW = w - 16
	local copies = 6
	local tilesN = copies * #CYCLE
	local xs: { number } = {}
	local cursor = 0
	for i = 1, tilesN do
		xs[i] = cursor
		cursor += SPEC[CYCLE[((i - 1) % #CYCLE) + 1]].w
	end
	local strip = Theme.clear(window, UDim2.fromOffset(cursor, reelH), UDim2.fromOffset(0, 0))
	strip.Name = "Strip"

	local refundTiles: { Frame } = {}
	for i = 1, tilesN do
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		local spec = SPEC[tier]
		local th = heightOf(tier, reelH)
		local cell = Theme.frame(
			strip,
			UDim2.fromOffset(spec.w - 10, th),
			UDim2.fromOffset(xs[i] + 5, math.floor((reelH - th) / 2)),
			Theme.BG:Lerp(spec.color, 0.22)
		)
		cell.Name = `Tile{i}`
		cell.ClipsDescendants = true
		cell.ZIndex = 3
		cell:SetAttribute("Tier", tier)
		Theme.round(cell, 14)
		Theme.stroke(cell, if tier == "legendary" then 4 else 2, spec.color)
		local glow = Theme.disc(cell, math.floor(th * 0.72), spec.color, UDim2.fromScale(0.5, 0.4), 0.62)
		glow.Name = "Glow"
		glow.ZIndex = 3
		if tier == "refund" then
			table.insert(refundTiles, cell)
			Theme.label(cell, "REFUND", 20, UDim2.fromOffset(spec.w - 16, 22), UDim2.new(0.5, 0, 1, -6), {
				anchor = V2(0.5, 1),
				color = Theme.TEXT,
				z = 5,
			}).Name = "Caption"
		else
			local e = face[tier]
			cell:SetAttribute("Ball", e)
			local icon = Theme.ball(cell, e, math.floor(th * 0.46), UDim2.fromScale(0.5, 0.4), MID)
			icon.Name = "Icon"
			icon.ZIndex = 4
			local nm = Theme.label(
				cell,
				Rules.Config.TITLE[e] or "?",
				20,
				UDim2.fromOffset(spec.w - 16, 22),
				UDim2.new(0.5, 0, 1, -6),
				{ anchor = V2(0.5, 1), color = Theme.nameColor(e), z = 5 }
			)
			nm.Name = "Caption"
		end
	end

	local function at(i: number): number
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		return viewW / 2 - (xs[i] + SPEC[tier].w / 2)
	end

	local marker = Theme.frame(window, UDim2.fromOffset(6, reelH), UDim2.new(0.5, 0, 0, 0), Theme.YELLOW, V2(0.5, 0))
	marker.Name = "Marker"
	marker.ZIndex = 6
	Theme.stroke(marker, 2, Theme.INK)
	Theme.label(window, "▼", 22, UDim2.fromOffset(36, 24), UDim2.new(0.5, 0, 0, 0), {
		anchor = V2(0.5, 0),
		color = Theme.YELLOW,
		z = 8,
	})
	Theme.label(window, "▲", 22, UDim2.fromOffset(36, 24), UDim2.new(0.5, 0, 1, 0), {
		anchor = V2(0.5, 1),
		color = Theme.YELLOW,
		z = 8,
	})

	local result = Theme.label(window, "", 26, UDim2.fromOffset(viewW - 24, 32), UDim2.new(0.5, 0, 1, -8), {
		anchor = V2(0.5, 1),
		color = Theme.YELLOW,
		z = 9,
	})
	result.Name = "Result"

	local hold = false
	local function paint(c: string)
		if panel:GetAttribute("SpinPhase") == "spinning" and c ~= cur then
			return
		end
		cur = c
		panel:SetAttribute("SpinCur", c)
		local coinOn = c == "coins"
		local oddsC = host:FindFirstChild("OddsCoins") :: GuiObject?
		local oddsG = host:FindFirstChild("OddsGems") :: GuiObject?
		local pityC = host:FindFirstChild("PityCoins") :: GuiObject?
		local pityG = host:FindFirstChild("PityGems") :: GuiObject?
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
		for _, cell in refundTiles do
			local old = cell:FindFirstChild("Coin") or cell:FindFirstChild("Gem")
			if old then
				old:Destroy()
			end
			local icon = Money.icon(cell, c, 36, UDim2.fromScale(0.5, 0.38))
			icon.ZIndex = 4
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

	local function celebrate(tier: string, tile: GuiObject?)
		local sound = if tier == "legendary"
			then "legend"
			elseif tier == "epic" then "epic"
			elseif tier == "rare" then "rare"
			else "hit"
		playSfx(sound)
		if Theme.reduced() then
			return
		end
		local amp = if tier == "legendary" then 8 elseif tier == "epic" then 4 elseif tier == "rare" then 2 else 0
		local bits = if tier == "legendary" then 16 elseif tier == "epic" then 9 elseif tier == "rare" then 5 else 0
		local color = SPEC[tier].color
		local flash = Theme.frame(window, UDim2.fromScale(1, 1), nil, color)
		flash.Name = "Flash"
		flash.BackgroundTransparency = if tier == "common" or tier == "refund" then 0.72 else 0.45
		flash.ZIndex = 7
		local born: { { f: Frame, x: number, y: number, vx: number, vy: number } } = {}
		local cx, cy = viewW / 2, reelH / 2
		for i = 1, bits do
			local ang = (i / bits) * math.pi * 2
			local d = Theme.disc(window, if tier == "legendary" then 14 else 10, color, UDim2.fromOffset(cx, cy), 0.1)
			d.ZIndex = 8
			table.insert(born, {
				f = d,
				x = cx,
				y = cy,
				vx = math.cos(ang) * (if tier == "legendary" then 220 else 140),
				vy = math.sin(ang) * (if tier == "legendary" then 160 else 100),
			})
		end
		local ox = panel.Position.X.Offset
		local oy = panel.Position.Y.Offset
		local life = 0
		local dur = if tier == "legendary" then 0.55 elseif tier == "epic" then 0.4 else 0.28
		table.insert(ctx.frames, function(dt)
			if not window.Parent then
				return
			end
			life += dt
			local u = math.clamp(life / dur, 0, 1)
			flash.BackgroundTransparency = flash.BackgroundTransparency + (1 - flash.BackgroundTransparency) * math.min(1, dt * 6)
			if amp > 0 and panel.Parent then
				local damp = (1 - u) * (1 - u)
				local k = math.sin(life * 48) * amp * damp
				panel.Position = UDim2.fromOffset(ox + k, oy)
			end
			for _, bit in born do
				if bit.f.Parent then
					bit.x += bit.vx * dt
					bit.y += bit.vy * dt
					bit.vy += 280 * dt
					bit.f.Position = UDim2.fromOffset(bit.x, bit.y)
					bit.f.BackgroundTransparency = u
				end
			end
			if life >= dur then
				if panel.Parent then
					panel.Position = UDim2.fromOffset(ox, oy)
				end
				flash:Destroy()
				for _, bit in born do
					if bit.f.Parent then
						bit.f:Destroy()
					end
				end
			end
		end)
		if tile then
			local pop = if tier == "legendary" then 1.16 elseif tier == "epic" then 1.1 elseif tier == "rare" then 1.06 else 1.03
			Theme.scaleOf(tile).Scale = pop
		end
	end

	if hit then
		local idx = table.find(CYCLE, hit.tier) or #CYCLE
		local land = (4 - 1) * #CYCLE + idx
		local prizeTile = strip:FindFirstChild(`Tile{land}`) :: Frame?
		if prizeTile and hit.e and hit.tier ~= "refund" then
			prizeTile:SetAttribute("Ball", hit.e)
			local icon = prizeTile:FindFirstChild("Icon") :: ImageLabel?
			if icon then
				local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
				icon.Image = Art.BALLS
				icon.ImageRectOffset = Art.ballRect(hit.e)
			end
			local cap = prizeTile:FindFirstChild("Caption") :: TextLabel?
			if cap then
				cap.Text = Rules.Config.TITLE[hit.e] or "?"
				cap.TextColor3 = Theme.nameColor(hit.e)
			end
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
			if prizeTile then
				prizeTile.ZIndex = 5
			end
			Theme.scaleOf(marker).Scale = if hit.tier == "legendary" then 1.3 else 1.15
			if hit.e then
				marker.BackgroundColor3 = Theme.nameColor(hit.e)
			end
			panel:SetAttribute("SpinOn", hit.tier)
			panel:SetAttribute("SpinPhase", "odds")
			local bal = if cur == "coins" then v.coins or 0 else v.crystals or 0
			go.Active = bal >= lines[cur].price
			result.Text = prize(hit)
			result.TextColor3 = if hit.e then Theme.nameColor(hit.e) else Theme.YELLOW
			celebrate(hit.tier, prizeTile)
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
				if prizeTile and u > 0.86 then
					Theme.scaleOf(prizeTile).Scale = 1 + 0.08 * (u - 0.86) / 0.14
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
				x -= 80 * dt
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
			sc.Scale = 1 + 0.02 * math.sin(age * 3)
		end)
	end

	GuiService.SelectedObject = if go.Active then go else modeCoins
end

return Spin
