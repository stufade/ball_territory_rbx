--!strict
-- Spin page inside the shop. One featured card: a banner of the ball of the day (or VOID), a row of
-- real balls with the server percent on each, and the pack buttons inside that card. The reel spins
-- the balls. A legendary stop is a flash, a shake and a burst stronger than the tutorial reward.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local Cheer = require("./Cheer")
local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local GEM = Color3.fromHex("#7a3cff")
local VOID = 13

local Spin = {}

Spin.TIME = 1.1

local CYCLE = { "common", "rare", "epic", "legendary", "refund" }

local SPEC: { [string]: { w: number, color: Color3 } } = {
	common = { w = 128, color = Color3.fromHex("#3d6bff") },
	rare = { w = 144, color = Color3.fromHex("#14a4ff") },
	epic = { w = 168, color = Color3.fromHex("#c044ff") },
	legendary = { w = 268, color = Color3.fromHex("#ffd63c") },
	refund = { w = 128, color = Color3.fromHex("#2ed068") },
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

local function tierOf(e: number): string?
	for tier, list in Economy.TIERS :: { [string]: { number } } do
		if table.find(list, e) then
			return tier
		end
	end
	return nil
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
	local deal = v.dailyBall
	local featured = if deal and not owned[deal.e] then deal.e else face.legendary or VOID
	local featuredTier = tierOf(featured) or "legendary"

	local lines: { [string]: Net.SpinLine } = { coins = board.coins, crystals = board.crystals }
	local cur = if hit and lines[hit.cur] then hit.cur else "coins"

	local pad = 10
	local btnH = if h < 300 then 52 else 58
	local pityH = 22
	local oddsH = math.clamp(math.floor(h * 0.24), 72, 112)
	local btnY = h - pad - btnH
	local pityY = btnY - 4 - pityH
	local oddsY = pityY - 4 - oddsH
	local reelY = pad
	local reelH = oddsY - 6 - reelY
	if reelH < 108 then
		oddsH = 68
		oddsY = pityY - 4 - oddsH
		reelH = math.max(96, oddsY - 6 - reelY)
	end

	local card = Theme.frame(host, UDim2.fromOffset(w, h), UDim2.fromOffset(0, 0), Theme.BG)
	card.Name = "SpinCard"
	card.ClipsDescendants = true
	Theme.round(card, 18)
	Theme.stroke(card, 4, SPEC[featuredTier].color)

	local function prefix(c: string): string
		return if c == "coins" then "Coin" else "Gem"
	end

	local innerW = w - pad * 2
	local window = Theme.frame(card, UDim2.fromOffset(innerW, reelH), UDim2.fromOffset(pad, reelY), Theme.BG)
	window.Name = "Reel"
	window.ClipsDescendants = true
	Theme.round(window, 16)
	Theme.stroke(window, 3, SPEC[featuredTier].color)
	local wash = Instance.new("UIGradient")
	wash.Rotation = 90
	wash.Color = ColorSequence.new(SPEC[featuredTier].color:Lerp(Theme.BG, 0.35), Theme.BG)
	wash.Parent = window

	local viewW = innerW
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
		local th = reelH - 42
		local cell = Theme.clear(strip, UDim2.fromOffset(spec.w - 8, th), UDim2.fromOffset(xs[i] + 4, 4))
		cell.Name = `Tile{i}`
		cell.ZIndex = 3
		cell:SetAttribute("Tier", tier)
		local d = math.floor(th * (if tier == "legendary" then 0.86 elseif tier == "epic" then 0.72 else 0.62))
		local glow = Theme.disc(cell, math.floor(d * 1.15), spec.color, UDim2.fromScale(0.5, 0.46), 0.62)
		glow.Name = "Glow"
		glow.ZIndex = 3
		if tier == "refund" then
			table.insert(refundTiles, cell)
		else
			local e = face[tier]
			cell:SetAttribute("Ball", e)
			local icon = Theme.ball(cell, e, d, UDim2.fromScale(0.5, 0.46), MID)
			icon.Name = "Icon"
			icon.ZIndex = 4
		end
	end

	local function at(i: number): number
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		return viewW / 2 - (xs[i] + SPEC[tier].w / 2)
	end

	local marker =
		Theme.frame(window, UDim2.fromOffset(4, reelH - 32), UDim2.fromScale(0.5, 0), Theme.YELLOW, V2(0.5, 0))
	marker.Name = "Marker"
	marker.ZIndex = 6
	marker.BackgroundTransparency = 0.15

	local cap = Theme.frame(window, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 1, -34), Theme.INK)
	cap.BackgroundTransparency = 0.28
	cap.ZIndex = 10
	local kicker = if deal and featured == deal.e then "BALL OF THE DAY" else "FEATURED"
	local prizeName = Theme.label(
		cap,
		`{kicker}  ·  {Rules.Config.TITLE[featured] or "?"}  ·  {labelOf(featuredTier)}`,
		20,
		UDim2.new(1, -16, 1, 0),
		UDim2.fromScale(0.5, 0.5),
		{ anchor = MID, color = Theme.nameColor(featured), z = 11 }
	)
	prizeName.Name = "Prize"

	local result = Theme.label(window, "", 22, UDim2.fromOffset(viewW - 24, 24), UDim2.fromOffset(12, 4), {
		align = Enum.TextXAlignment.Right,
		color = Theme.YELLOW,
		z = 12,
	})
	result.Name = "Result"

	local function chips(c: string, line: Net.SpinLine)
		local box = Theme.clear(card, UDim2.fromOffset(innerW, oddsH), UDim2.fromOffset(pad, oddsY))
		box.Name = if c == "coins" then "OddsCoins" else "OddsGems"
		local chipW = math.floor((innerW - 8 * (#CYCLE - 1)) / #CYCLE)
		local x = 0
		for _, tier in CYCLE do
			local color = SPEC[tier].color
			local row =
				Theme.frame(box, UDim2.fromOffset(chipW, oddsH), UDim2.fromOffset(x, 0), Theme.BG:Lerp(color, 0.28))
			row.Name = `{prefix(c)}_{tier}`
			row.ClipsDescendants = true
			Theme.round(row, 12)
			Theme.stroke(row, if tier == "legendary" then 4 else 2, color)
			local ballD = math.floor(oddsH * 0.52)
			if tier == "refund" then
				Money.icon(row, c, ballD, UDim2.fromOffset(chipW / 2, ballD / 2 + 8))
			else
				local icon = Theme.ball(row, face[tier], ballD, UDim2.fromOffset(chipW / 2, ballD / 2 + 8), MID)
				icon.Name = "Icon"
			end
			local badge = Theme.frame(row, UDim2.fromOffset(chipW - 10, 24), UDim2.fromOffset(5, oddsH - 28), Theme.INK)
			badge.BackgroundTransparency = 0.2
			badge.ZIndex = 4
			Theme.round(badge, 8)
			Theme.label(badge, `{shareOf(line.odds, tier)}%`, 20, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), {
				anchor = MID,
				color = Theme.TEXT,
				z = 5,
			}).Name =
				"Pct"
			x += chipW + 8
		end
	end
	chips("coins", board.coins)
	chips("crystals", board.crystals)

	local function pityLine(c: string, line: Net.SpinLine)
		local left = line.every - line.pity
		local pityName = if line.tier == "legendary" then "LEGENDARY" else "EPIC+"
		local pity = Theme.label(
			card,
			`{pityName}  {line.pity}/{line.every} · {left} LEFT`,
			18,
			UDim2.fromOffset(innerW, pityH),
			UDim2.fromOffset(pad, pityY),
			{ align = Enum.TextXAlignment.Left, color = Theme.YELLOW_TXT }
		)
		pity.Name = if c == "coins" then "PityCoins" else "PityGems"
	end
	pityLine("coins", board.coins)
	pityLine("crystals", board.crystals)

	local modeW = math.clamp(math.floor(innerW * 0.2), 100, 148)
	local modeCoins =
		Theme.button(card, "COINS", UDim2.fromOffset(modeW, btnH), UDim2.fromOffset(pad, btnY), Theme.YELLOW, nil, 20)
	modeCoins.Name = "ModeCoins"
	local modeGems = Theme.button(
		card,
		"CRYSTALS",
		UDim2.fromOffset(modeW, btnH),
		UDim2.fromOffset(pad + modeW + 8, btnY),
		GEM,
		nil,
		20
	)
	modeGems.Name = "ModeGems"
	local goW = innerW - modeW * 2 - 16
	local go = Theme.button(
		card,
		`SPIN {Money.fmt(lines[cur].price)}`,
		UDim2.fromOffset(goW, btnH),
		UDim2.fromOffset(pad + modeW * 2 + 16, btnY),
		if cur == "coins" then Theme.YELLOW else GEM,
		nil,
		24
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
		local oddsC = card:FindFirstChild("OddsCoins") :: GuiObject?
		local oddsG = card:FindFirstChild("OddsGems") :: GuiObject?
		local pityC = card:FindFirstChild("PityCoins") :: GuiObject?
		local pityG = card:FindFirstChild("PityGems") :: GuiObject?
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
			local icon = Money.icon(cell, c, math.floor(reelH * 0.36), UDim2.fromScale(0.5, 0.46))
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
		local color = SPEC[tier].color
		local amp = if tier == "legendary" then 18 elseif tier == "epic" then 8 elseif tier == "rare" then 3 else 0
		local bits = if tier == "legendary" then 48 elseif tier == "epic" then 18 elseif tier == "rare" then 8 else 0
		local flash =
			Theme.frame(panel, UDim2.fromScale(1, 1), nil, if tier == "legendary" then Color3.new(1, 1, 1) else color)
		flash.Name = "Flash"
		flash.BackgroundTransparency = if tier == "legendary" then 0.25 elseif tier == "epic" then 0.4 else 0.62
		flash.ZIndex = 20
		if tier == "legendary" or tier == "epic" then
			local e = if hit and hit.e then hit.e else featured
			local px, py = panel.Size.X.Offset / 2, panel.Size.Y.Offset / 2
			local rays = Cheer.rays(panel, ctx, e, px, py, if tier == "legendary" then 860 else 420)
			rays.ZIndex = 8
			Cheer.burst(panel, ctx, e, px, py)
			if tier == "legendary" then
				Cheer.confetti(panel, ctx)
			end
		end
		local born: { { f: Frame, x: number, y: number, vx: number, vy: number } } = {}
		local cx, cy = viewW / 2, reelH / 2
		for i = 1, bits do
			local ang = (i / bits) * math.pi * 2
			local speed = if tier == "legendary" then 340 else 160
			local d = Theme.disc(window, if tier == "legendary" then 16 else 10, color, UDim2.fromOffset(cx, cy), 0.05)
			d.ZIndex = 14
			table.insert(born, {
				f = d,
				x = cx,
				y = cy,
				vx = math.cos(ang) * speed,
				vy = math.sin(ang) * speed * 0.75,
			})
		end
		local ox = panel.Position.X.Offset
		local oy = panel.Position.Y.Offset
		local life = 0
		local dur = if tier == "legendary" then 0.95 elseif tier == "epic" then 0.5 else 0.28
		table.insert(ctx.frames, function(dt)
			if not window.Parent then
				return
			end
			life += dt
			local u = math.clamp(life / dur, 0, 1)
			if flash.Parent then
				flash.BackgroundTransparency = flash.BackgroundTransparency
					+ (1 - flash.BackgroundTransparency) * math.min(1, dt * 4)
			end
			if amp > 0 and panel.Parent then
				local damp = (1 - u) * (1 - u)
				local k = math.sin(life * 52) * amp * damp
				panel.Position = UDim2.fromOffset(ox + k, oy + math.cos(life * 47) * amp * 0.45 * damp)
			end
			for _, bit in born do
				if bit.f.Parent then
					bit.x += bit.vx * dt
					bit.y += bit.vy * dt
					bit.vy += 360 * dt
					bit.f.Position = UDim2.fromOffset(bit.x, bit.y)
					bit.f.BackgroundTransparency = u
				end
			end
			if life >= dur then
				if panel.Parent then
					panel.Position = UDim2.fromOffset(ox, oy)
				end
				if flash.Parent then
					flash:Destroy()
				end
				for _, bit in born do
					if bit.f.Parent then
						bit.f:Destroy()
					end
				end
			end
		end)
		if tile then
			local pop = if tier == "legendary"
				then 1.34
				elseif tier == "epic" then 1.16
				elseif tier == "rare" then 1.08
				else 1.03
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
				icon.Image = Art.BALLS
				icon.ImageRectOffset = Art.ballRect(hit.e)
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
			Theme.scaleOf(marker).Scale = if hit.tier == "legendary" then 1.4 else 1.15
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
					Theme.scaleOf(prizeTile).Scale = 1 + 0.12 * (u - 0.86) / 0.14
				end
				if t >= Spin.TIME then
					stop()
				end
			end)
		end
	else
		local hero = strip:FindFirstChild("Tile4") :: Frame?
		if hero then
			hero:SetAttribute("Ball", featured)
			local icon = hero:FindFirstChild("Icon") :: ImageLabel?
			if icon then
				icon.Image = Art.BALLS
				icon.ImageRectOffset = Art.ballRect(featured)
			end
		end
		strip.Position = UDim2.fromOffset(at(4), 0)
		if not Theme.reduced() and hero then
			local sc = Theme.scaleOf(hero)
			local age = 0
			table.insert(ctx.frames, function(dt)
				if not hero.Parent or panel:GetAttribute("SpinPhase") == "spinning" then
					return
				end
				age += dt
				sc.Scale = 1 + 0.04 * math.sin(age * 2.4)
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
