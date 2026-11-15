--!strict
-- Spin page inside the shop, in the day-7 family (Daily, BALLS): one orange scene card. On top a dark
-- reel well: a drum of tier cards (a ball on its glow and shadow, the tier word) drifting slowly under a gold
-- slot. Under it the odds as tier chips (ball + percent) and the guarantee as a bar ("EPIC+ IN 7"). At the
-- bottom the currency switch and one big 3D SPIN button. The server picks the prize before the reel moves;
-- the reel only shows it. The reveal grows with the tier: common pops, rare glows, epic adds rays and a
-- burst, legendary flashes the window white, shakes it and throws confetti.
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
local WHITE = Color3.new(1, 1, 1)
local VOID = 13

local Spin = {}

-- Reel run time (s). Long enough to read the tiers going by, short enough to spin again.
Spin.TIME = 2

local CYCLE = { "common", "rare", "epic", "legendary", "refund" }

local TIER_COL: { [string]: Color3 } = {
	common = Color3.fromHex("#3d8bff"),
	rare = Color3.fromHex("#14c4ff"),
	epic = Color3.fromHex("#c044ff"),
	legendary = Color3.fromHex("#ffc21a"),
	refund = Color3.fromHex("#2ed068"),
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
	local ok, mod: any = pcall(function(): any
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

-- Every GuiObject under o (and o) gets ZIndex z: a whole piece drawn above its siblings.
local function lift(o: GuiObject, z: number)
	o.ZIndex = z
	for _, c in o:GetDescendants() do
		if c:IsA("GuiObject") then
			c.ZIndex = z
		end
	end
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
	-- reduced motion, or the Fast Spin pass (server-owned, v.passes): the result shows without the reel run
	local still = Theme.reduced() or (v.passes ~= nil and v.passes.fastSpin == true)

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

	-- layout: reel well on top, chips + guarantee row, then the buttons. Buttons >= 64 design px
	-- (44 px on a 390 px tall phone).
	local pad = 12
	local gap = 10
	local btnH = 66
	local rowH = math.clamp(math.floor(h * 0.19), 52, 66)
	local reelH = math.max(112, h - pad * 2 - gap * 2 - rowH - btnH)
	local reelY = pad
	local rowY = reelY + reelH + gap
	local btnY = rowY + rowH + gap
	local innerW = w - pad * 2

	local card = Theme.card(host, UDim2.fromOffset(w, h), UDim2.fromOffset(0, 0), Theme.ORANGE, Theme.BG, 20)
	card.Name = "SpinCard"
	local edge = card:FindFirstChild("Edge") :: UIStroke
	edge.Thickness = 5
	edge.Color = Theme.YELLOW
	Theme.pattern(card, WHITE, 0.92, 40)

	-- the reel well: dark inset with a faint tier wash, clips the drum
	local window = Theme.frame(card, UDim2.fromOffset(innerW, reelH), UDim2.fromOffset(pad, reelY), Theme.BG)
	window.Name = "Reel"
	window.ClipsDescendants = true
	Theme.round(window, 16)
	Theme.stroke(window, 4, Theme.INK)
	Theme.gradient(window, Theme.GLOW, Theme.BG)
	Theme.pattern(window, Theme.GLOW:Lerp(WHITE, 0.25), 0.78, 44)

	local tileH = reelH - 20
	local tileW = math.floor(tileH * 0.86)
	local slotW = tileW + 8
	local viewW = innerW
	local copies = 6
	local tilesN = copies * #CYCLE
	local strip = Theme.clear(window, UDim2.fromOffset(slotW * tilesN, reelH), UDim2.fromOffset(0, 0))
	strip.Name = "Strip"
	strip.ZIndex = 3

	local refundTiles: { Frame } = {}
	local ballD = math.floor(tileH * 0.52)
	for i = 1, tilesN do
		local tier = CYCLE[((i - 1) % #CYCLE) + 1]
		local col = TIER_COL[tier]
		local cell = Theme.card(
			strip,
			UDim2.fromOffset(tileW, tileH),
			UDim2.fromOffset((i - 1) * slotW + 4, 10),
			col:Lerp(WHITE, 0.08),
			col:Lerp(Theme.BG, 0.62),
			14
		)
		cell.Name = `Tile{i}`
		cell:SetAttribute("Tier", tier)
		local cEdge = cell:FindFirstChild("Edge") :: UIStroke
		if tier == "legendary" then
			cEdge.Thickness = 4
			cEdge.Color = Theme.YELLOW
		end
		local by = math.floor(tileH * 0.42)
		Theme.glow(cell, math.floor(ballD * 1.7), col:Lerp(WHITE, 0.3), UDim2.fromOffset(tileW / 2, by), 4, 0.8)
		Theme.shadow(cell, math.floor(ballD * 0.7), UDim2.fromOffset(tileW / 2, by + ballD / 2 + 2))
		if tier == "refund" then
			table.insert(refundTiles, cell)
		else
			local e = face[tier]
			cell:SetAttribute("Ball", e)
			local icon = Theme.ball(cell, e, ballD, UDim2.fromOffset(tileW / 2, by), MID)
			icon.Name = "Icon"
			if tier == "legendary" then
				local cr = Theme.crown(cell, math.floor(ballD * 0.5), UDim2.fromOffset(tileW / 2, by - ballD * 0.52))
				cr.Name = "Crown"
			end
		end
		local word = Theme.label(
			cell,
			labelOf(tier),
			Theme.fit(labelOf(tier), 20, tileW - 8, 22),
			UDim2.fromOffset(tileW - 6, 22),
			UDim2.fromOffset(tileW / 2, tileH - 8),
			{ anchor = V2(0.5, 1), stroke = 2 }
		)
		word.Name = "Word"
	end

	local function at(i: number): number
		return viewW / 2 - ((i - 1) * slotW + slotW / 2)
	end

	-- dark fades at both ends so the drum reads as round
	for side = 0, 1 do
		local fade = Theme.frame(
			window,
			UDim2.fromOffset(math.floor(viewW * 0.22), reelH),
			UDim2.fromScale(side, 0),
			Theme.BG,
			V2(side, 0)
		)
		fade.Name = "Fade"
		fade.ZIndex = 5
		local g = Instance.new("UIGradient")
		g.Rotation = if side == 0 then 0 else 180
		g.Transparency = NumberSequence.new(0.05, 1)
		g.Parent = fade
	end

	-- the gold slot: outline round the middle tile and two pointers biting into the well
	local marker = Theme.clear(window, UDim2.fromOffset(slotW + 4, reelH - 6), UDim2.fromScale(0.5, 0.5), MID)
	marker.Name = "Marker"
	marker.ZIndex = 6
	Theme.round(marker, 16)
	local mEdge = Theme.stroke(marker, 5, Theme.YELLOW)
	mEdge.Name = "Edge"
	for k = 0, 1 do
		local tip = Theme.frame(window, UDim2.fromOffset(26, 26), UDim2.fromScale(0.5, k), Theme.YELLOW, MID)
		tip.Name = "Pointer"
		tip.Rotation = 45
		tip.ZIndex = 7
		Theme.stroke(tip, 3, Theme.INK)
	end

	-- header pieces over the well: the ribbon and the top prize
	local ribbon = Theme.ribbon(card, "LUCKY SPIN", Theme.ORANGE, UDim2.fromOffset(pad + 14, reelY + 8), 30)
	lift(ribbon, 9)
	local topName = Rules.Config.TITLE[face.legendary] or "VOID"
	local prizeName = Theme.label(
		card,
		`TOP PRIZE: {topName}`,
		22,
		UDim2.fromOffset(math.floor(innerW * 0.34), 28),
		UDim2.fromOffset(pad + innerW - 16, reelY + 9),
		{ anchor = V2(1, 0), align = Enum.TextXAlignment.Right, color = Theme.YELLOW_TXT, stroke = 3, z = 9 }
	)
	prizeName.Name = "Prize"

	-- the prize banner, shown when the reel stops
	local resultBox = Theme.frame(window, UDim2.fromOffset(360, 40), UDim2.new(0.5, 0, 1, -8), Theme.YELLOW, V2(0.5, 1))
	resultBox.Name = "ResultBox"
	resultBox.Visible = false
	Theme.round(resultBox, 12)
	Theme.stroke(resultBox, 3, Theme.INK)
	Theme.gradient(resultBox, WHITE, Color3.fromRGB(200, 200, 200))
	local result = Theme.label(resultBox, "", 26, UDim2.new(1, -12, 1, 0), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		stroke = 3,
	})
	result.Name = "Result"
	lift(resultBox, 12)

	local function prefix(c: string): string
		return if c == "coins" then "Coin" else "Gem"
	end

	-- odds: one chip per tier, left of the guarantee
	local pityW = math.clamp(math.floor(innerW * 0.34), 240, 340)
	local oddsW = innerW - pityW - gap
	local function chips(c: string, line: Net.SpinLine)
		local box = Theme.clear(card, UDim2.fromOffset(oddsW, rowH), UDim2.fromOffset(pad, rowY))
		box.Name = if c == "coins" then "OddsCoins" else "OddsGems"
		local weight = { common = 1, rare = 1, epic = 1, legendary = 1.25, refund = 1 }
		local sum = 0
		for _, tier in CYCLE do
			sum += weight[tier]
		end
		local cg = 6
		local free = oddsW - cg * (#CYCLE - 1)
		local x = 0
		for i, tier in CYCLE do
			local col = TIER_COL[tier]
			local chipW = if i == #CYCLE then oddsW - x else math.floor(free * weight[tier] / sum)
			local legend = tier == "legendary"
			local chip = Theme.card(
				box,
				UDim2.fromOffset(chipW, rowH),
				UDim2.fromOffset(x, 0),
				col:Lerp(WHITE, 0.05),
				col:Lerp(Theme.BG, 0.55),
				14
			)
			chip.Name = `{prefix(c)}_{tier}`
			if legend then
				local ce = chip:FindFirstChild("Edge") :: UIStroke
				ce.Thickness = 4
				ce.Color = Theme.YELLOW
			end
			local d = rowH - 14
			local ix = 6 + d / 2
			if tier == "refund" then
				Money.icon(chip, c, math.floor(d * 0.86), UDim2.fromOffset(ix, rowH / 2))
			else
				local icon =
					Theme.ball(chip, if legend then VOID else face[tier], d, UDim2.fromOffset(ix, rowH / 2), MID)
				icon.Name = "Icon"
			end
			local pctText = `{shareOf(line.odds, tier)}%`
			local tw = chipW - d - 14
			Theme.label(
				chip,
				pctText,
				Theme.fit(pctText, if legend then 30 else 28, tw, rowH - 8),
				UDim2.fromOffset(tw, rowH - 8),
				UDim2.fromOffset(d + 10 + tw / 2, rowH / 2),
				{ anchor = MID, stroke = 3 }
			).Name =
				"Pct"
			x += chipW + cg
		end
	end
	chips("coins", board.coins)
	chips("crystals", board.crystals)

	-- guarantee: the tier it promises, how many spins left, a filling bar
	local function pityBox(c: string, line: Net.SpinLine)
		local legend = line.tier == "legendary"
		local col = if legend then TIER_COL.legendary else TIER_COL.epic
		local box = Theme.card(
			card,
			UDim2.fromOffset(pityW, rowH),
			UDim2.fromOffset(pad + oddsW + gap, rowY),
			Theme.SLOT:Lerp(col, 0.3),
			Theme.BG,
			14
		)
		box.Name = if c == "coins" then "PityBoxCoins" else "PityBoxGems"
		local be = box:FindFirstChild("Edge") :: UIStroke
		be.Color = col
		local d = rowH - 12
		local icon = Theme.ball(box, if legend then VOID else face.epic, d, UDim2.fromOffset(6 + d / 2, rowH / 2), MID)
		icon.Name = "Icon"
		local left = math.max(0, line.every - line.pity)
		local head = if left <= 1
			then `{if legend then "LEGENDARY" else "EPIC+"} NEXT SPIN!`
			else `{if legend then "LEGENDARY" else "EPIC+"} IN {left}`
		local tx = d + 14
		local tw = pityW - tx - 10
		local barH = math.floor(rowH * 0.32)
		local headH = rowH - barH - 14
		Theme.label(
			box,
			head,
			Theme.fit(head, 24, tw, headH),
			UDim2.fromOffset(tw, headH),
			UDim2.fromOffset(tx, 4),
			{ align = Enum.TextXAlignment.Left, color = Theme.YELLOW_TXT, stroke = 3 }
		).Name =
			"Head"
		local bar = Theme.frame(box, UDim2.fromOffset(tw, barH), UDim2.fromOffset(tx, rowH - barH - 8), Theme.INK)
		bar.Name = "Bar"
		Theme.round(bar, barH / 2)
		local u = math.clamp(line.pity / math.max(1, line.every), 0, 1)
		if u > 0 then
			local fill = Theme.frame(bar, UDim2.fromScale(u, 1), nil, col)
			fill.Name = "Fill"
			Theme.round(fill, barH / 2)
			Theme.gradient(fill, col:Lerp(WHITE, 0.35), col)
		end
		local count = Theme.label(
			bar,
			`{line.pity}/{line.every}`,
			math.max(Theme.MIN_TEXT, barH),
			UDim2.fromScale(1, 1),
			UDim2.fromScale(0.5, 0.5),
			{ anchor = MID, stroke = 2, z = 4 }
		)
		count.Name = if c == "coins" then "PityCoins" else "PityGems"
	end
	pityBox("coins", board.coins)
	pityBox("crystals", board.crystals)

	-- buttons: the currency switch (coin / crystal pills) and the big SPIN
	local iconFn = function(parent: Instance, c: string, d: number, pos: UDim2): GuiObject
		return Money.icon(parent, c, d, pos)
	end
	local modeW = math.clamp(math.floor(innerW * 0.19), 150, 190)
	local modeCoins =
		Theme.price(card, "COINS", UDim2.fromOffset(modeW, btnH), UDim2.fromOffset(pad, btnY), "coins", iconFn, 24)
	modeCoins.Name = "ModeCoins"
	local modeGems = Theme.price(
		card,
		"CRYSTALS",
		UDim2.fromOffset(modeW, btnH),
		UDim2.fromOffset(pad + modeW + 8, btnY),
		"crystals",
		iconFn,
		24
	)
	modeGems.Name = "ModeGems"
	local goX = pad + modeW * 2 + 18
	local goW = innerW + pad - goX
	local go = Theme.button(
		card,
		`SPIN {Money.fmt(lines[cur].price)}`,
		UDim2.fromOffset(goW, btnH),
		UDim2.fromOffset(goX, btnY),
		Theme.PRICE_COIN,
		nil,
		34
	)
	go.Name = "SpinGo"
	local goLip = math.clamp(math.floor(btnH * 0.1 + 0.5), 4, 9)
	local goLabel = go:FindFirstChild("Label") :: TextLabel?
	modeCoins.NextSelectionRight = modeGems
	modeGems.NextSelectionLeft = modeCoins
	modeGems.NextSelectionRight = go
	go.NextSelectionLeft = modeGems

	local hold = false
	local function paint(c: string)
		if panel:GetAttribute("SpinPhase") == "spinning" and c ~= cur then
			return
		end
		cur = c
		panel:SetAttribute("SpinCur", c)
		local coinOn = c == "coins"
		local show: { [string]: boolean } =
			{ OddsCoins = coinOn, OddsGems = not coinOn, PityBoxCoins = coinOn, PityBoxGems = not coinOn }
		for name, on in show do
			local o = card:FindFirstChild(name) :: GuiObject?
			if o then
				o.Visible = on
			end
		end
		for _, cell in refundTiles do
			local old = cell:FindFirstChild("Coin") or cell:FindFirstChild("Gem")
			if old then
				old:Destroy()
			end
			Money.icon(cell, c, math.floor(ballD * 0.82), UDim2.fromOffset(tileW / 2, math.floor(tileH * 0.42)))
		end
		for b, on in { [modeCoins] = coinOn, [modeGems] = not coinOn } do
			local base = if b == modeCoins then Theme.PRICE_COIN else Theme.PRICE_GEM
			b.BackgroundColor3 = if on then base else base:Lerp(Theme.SLOT, 0.6)
			Theme.select(b, on)
			local l = b:FindFirstChild("Label") :: TextLabel?
			if l then
				l.TextColor3 = if on then Theme.TEXT else Theme.DIM
			end
		end
		local price = lines[c].price
		local bal = if coinOn then v.coins or 0 else v.crystals or 0
		local afford = bal >= price
		local text = `SPIN {Money.fmt(price)}`
		local old = go:FindFirstChild("Coin") or go:FindFirstChild("Gem")
		if old then
			old:Destroy()
		end
		if goLabel then
			goLabel.Text = text
			goLabel.TextColor3 = if afford then Theme.TEXT else Theme.DIM
			-- the currency icon sits just left of the centred text
			local d = math.min(40, btnH - goLip - 16)
			local tw = math.min(goW - d - 40, goLabel.TextSize * 0.6 * #text)
			goLabel.Size = UDim2.fromOffset(tw + 8, btnH - goLip)
			goLabel.Position = UDim2.fromOffset(goW / 2 + (d + 10) / 2, 0)
			local ic =
				Money.icon(go, c, d, UDim2.fromOffset(goW / 2 - tw / 2 - 10 - d / 2 + (d + 10) / 2, (btnH - goLip) / 2))
			lift(ic, 4)
		end
		go.Active = afford and panel:GetAttribute("SpinPhase") ~= "spinning"
		go.BackgroundColor3 = if afford then (if coinOn then Theme.PRICE_COIN else Theme.PRICE_GEM) else Theme.PANEL_HI
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

	-- the reveal, stronger with the tier
	local function celebrate(tier: string, tile: Frame?)
		local sound = if tier == "legendary"
			then "legend"
			elseif tier == "epic" then "epic"
			elseif tier == "rare" then "rare"
			else "hit"
		playSfx(sound)
		if tile then
			Theme.scaleOf(tile).Scale = if tier == "legendary"
				then 1.12
				elseif tier == "epic" then 1.08
				elseif tier == "rare" then 1.05
				else 1.02
		end
		resultBox.BackgroundColor3 = TIER_COL[tier]
		local rw = math.min(viewW - 40, math.floor(26 * 0.62 * #result.Text) + 40)
		resultBox.Size = UDim2.fromOffset(rw, 40)
		resultBox.Visible = true
		if still then
			return
		end
		Theme.pop(resultBox, 0.05, 0.4)
		local col = TIER_COL[tier]
		local cx, cy = viewW / 2, reelH / 2
		local spinRays: Frame? = nil
		-- rare+: a soft glow over the slot; epic+: turning rays and a dim around the slot
		if tier ~= "common" and tier ~= "refund" then
			local glow =
				Theme.glow(window, math.floor(tileH * 1.7), col:Lerp(WHITE, 0.35), UDim2.fromOffset(cx, cy), 5, 0.7)
			lift(glow, 4)
			Theme.pop(glow, 0, 0.3)
		end
		if tier == "epic" or tier == "legendary" then
			local dim = Theme.frame(window, UDim2.fromScale(1, 1), nil, Theme.INK)
			dim.Name = "Dim"
			dim.BackgroundTransparency = 0.45
			dim.ZIndex = 4
			local r = Theme.rays(
				window,
				if tier == "legendary" then 16 else 10,
				math.floor(viewW * 0.9),
				if tier == "legendary" then 34 else 22,
				UDim2.fromOffset(cx, cy),
				col,
				WHITE,
				0.35
			)
			lift(r, 4)
			spinRays = r
			-- the prize itself, big, above the dim and the rays
			if hit and hit.e then
				local big = Theme.ball(window, hit.e, math.floor(tileH * 0.84), UDim2.fromOffset(cx, cy - 6), MID)
				big.Name = "Big"
				big.ZIndex = 8
				Theme.pop(big, 0, 0.3)
			end
		end
		local flash = Theme.frame(panel, UDim2.fromScale(1, 1), nil, if tier == "legendary" then WHITE else col)
		flash.Name = "Flash"
		flash.BackgroundTransparency = if tier == "legendary"
			then 0.15
			elseif tier == "epic" then 0.4
			elseif tier == "rare" then 0.65
			else 0.85
		flash.ZIndex = 20
		local flashA = flash.BackgroundTransparency
		if tier == "legendary" or tier == "epic" then
			local e = if hit and hit.e then hit.e else VOID
			local px, py = panel.Size.X.Offset / 2, panel.Size.Y.Offset / 2
			Cheer.burst(panel, ctx, e, px, py)
			if tier == "legendary" then
				local rays = Cheer.rays(panel, ctx, e, px, py, 860)
				rays.ZIndex = 8
				Cheer.confetti(panel, ctx)
			end
		end
		-- sparks out of the slot
		local bits = if tier == "legendary" then 40 elseif tier == "epic" then 18 elseif tier == "rare" then 8 else 0
		local motes: { { f: Frame, x: number, y: number, vx: number, vy: number } } = {}
		for i = 1, bits do
			local ang = (i / bits) * math.pi * 2
			local speed = if tier == "legendary" then 340 else 170
			local d = Theme.disc(
				window,
				if tier == "legendary" then 14 else 10,
				col:Lerp(WHITE, 0.3),
				UDim2.fromOffset(cx, cy),
				0
			)
			d.ZIndex = 11
			table.insert(motes, { f = d, x = cx, y = cy, vx = math.cos(ang) * speed, vy = math.sin(ang) * speed * 0.7 })
		end
		local amp = if tier == "legendary" then 16 elseif tier == "epic" then 7 elseif tier == "rare" then 2 else 0
		local ox, oy = panel.Position.X.Offset, panel.Position.Y.Offset
		local life = 0
		local dur = if tier == "legendary" then 1 elseif tier == "epic" then 0.6 else 0.3
		table.insert(ctx.frames, function(dt)
			if not window.Parent then
				return
			end
			life += dt
			local u = math.clamp(life / dur, 0, 1)
			if spinRays then
				spinRays.Rotation = life * 30
			end
			if flash.Parent then
				flash.BackgroundTransparency = 1 - (1 - flashA) * math.max(0, 1 - u * 1.4)
			end
			if amp > 0 and panel.Parent and life <= dur then
				local damp = (1 - u) * (1 - u)
				panel.Position = UDim2.fromOffset(
					ox + math.sin(life * 52) * amp * damp,
					oy + math.cos(life * 47) * amp * 0.45 * damp
				)
			end
			for _, m in motes do
				if m.f.Parent then
					m.x += m.vx * dt
					m.y += m.vy * dt
					m.vy += 360 * dt
					m.f.Position = UDim2.fromOffset(m.x, m.y)
					m.f.BackgroundTransparency = u
				end
			end
			if life >= dur then
				if panel.Parent and amp > 0 then
					panel.Position = UDim2.fromOffset(ox, oy)
					amp = 0
				end
				if flash.Parent then
					flash:Destroy()
				end
				for _, m in motes do
					if m.f.Parent then
						m.f:Destroy()
					end
				end
			end
		end)
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
		local lastTile = 3
		local lastTick = 0
		local function stop()
			if done then
				return
			end
			done = true
			strip.Position = UDim2.fromOffset(x1, 0)
			Theme.scaleOf(marker).Scale = if hit.tier == "legendary" then 1.08 else 1.04
			mEdge.Color = TIER_COL[hit.tier]:Lerp(WHITE, 0.2)
			panel:SetAttribute("SpinOn", hit.tier)
			panel:SetAttribute("SpinPhase", "odds")
			local bal = if cur == "coins" then v.coins or 0 else v.crystals or 0
			go.Active = bal >= lines[cur].price
			result.Text = prize(hit)
			celebrate(hit.tier, prizeTile)
		end
		if still then
			stop()
		else
			table.insert(ctx.frames, function(dt)
				if done or not strip.Parent then
					return
				end
				t = math.min(Spin.TIME, t + dt)
				local u = t / Spin.TIME
				-- fast start, long slow end: the last tiers crawl past the slot
				local k = 1 - (1 - u) ^ 4
				local x = x0 + (x1 - x0) * k
				strip.Position = UDim2.fromOffset(x, 0)
				local under = 3 + math.floor((x0 - x) / slotW + 0.5)
				if under ~= lastTile and t - lastTick > 0.07 then
					lastTile = under
					lastTick = t
					playSfx("hit")
					Theme.scaleOf(marker).Scale = 1.05
				end
				local ms = Theme.scaleOf(marker)
				ms.Scale = 1 + ((ms.Scale or 1) - 1) * math.max(0, 1 - dt * 12)
				if t >= Spin.TIME then
					stop()
				end
			end)
		end
	else
		-- idle: the drum drifts so the tiers go by, the slot breathes
		strip.Position = UDim2.fromOffset(at(3), 0)
		if not still then
			local age = 0
			local span = slotW * #CYCLE
			local ms = Theme.scaleOf(marker)
			table.insert(ctx.frames, function(dt)
				if not strip.Parent or panel:GetAttribute("SpinPhase") == "spinning" then
					return
				end
				age += dt
				strip.Position = UDim2.fromOffset(at(3) - (age * 34) % span, 0)
				ms.Scale = 1 + 0.02 * math.sin(age * 3)
			end)
		end
	end

	if not still then
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
			sc.Scale = 1 + 0.025 * math.sin(age * 3)
		end)
	end

	GuiService.SelectedObject = if go.Active then go else modeCoins
end

return Spin
