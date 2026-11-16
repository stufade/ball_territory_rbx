--!strict
-- Skins tab of the shop (docs/ui.md «Магазин»): filter chips on top (ALL, SKINS, TRAILS, FORCES, FRAMES, EXTRA),
-- then a grid of whole-row cards in the BALLS style: tier gradient and stripe, a preview well with the tier ribbon,
-- the name and kind, a green coin price (E4: coins only); an owned look reads OWNED with EQUIP.
-- Every preview is drawn inside its well: a skin is a ball in its material on a glow (dark skins on a light one),
-- a trail is the player's ball with its tail, a force is the ball in a ring and flash of its colour, a frame is a
-- portrait of the ball in that frame.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local HEX = Color3.fromHex
local WHITE = Color3.new(1, 1, 1)
local BALL_SPAN = 1.14 -- Theme.ball image side per visible diameter

local Shelf = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
}

-- Sizes (design px). Chips and price buttons are 62 high: 44 px on a 844x390 phone (scale 0.72).
local CHIP_H = 62
local BTN_H = 62
local GAP = 8
local CARD_NAT = 236

local TIER_COL = {
	common = HEX("#3d6bff"),
	rare = HEX("#14a4ff"),
	epic = HEX("#c044ff"),
	legendary = HEX("#ffd63c"),
}
local TIER_WORD = { common = "COMMON", rare = "RARE", epic = "EPIC", legendary = "LEGENDARY" }

type Filter = "all" | "SKIN" | "TRAIL" | "FORCE" | "FRAME" | "EXTRA"
local CHIPS: { { key: Filter, word: string } } = {
	{ key = "all", word = "ALL" },
	{ key = "SKIN", word = "SKINS" },
	{ key = "TRAIL", word = "TRAILS" },
	{ key = "FORCE", word = "FORCES" },
	{ key = "FRAME", word = "FRAMES" },
	{ key = "EXTRA", word = "EXTRA" },
}
local filter: Filter = "all"

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

local function groupOf(id: string): Filter
	local k = kindOf(id)
	if k == "LOBBY" or k == "CARD" then
		return "EXTRA"
	end
	return k :: Filter
end

-- The name without its kind prefix: skin_ink -> INK, podium_spot -> PODIUM SPOT.
local function title(id: string): string
	local k = kindOf(id)
	local rest = id
	if k ~= "LOBBY" and k ~= "CARD" then
		rest = string.sub(id, #k + 2)
	end
	return string.upper((string.gsub(rest, "_", " ")))
end

local function tierOf(coins: number): string
	if coins >= 12000 then
		return "legendary"
	elseif coins >= 8000 then
		return "epic"
	elseif coins >= 4000 then
		return "rare"
	end
	return "common"
end

type Paint = { base: Color3, accent: Color3, pat: string }

local PAINT: { [string]: Paint } = {
	skin_ink = { base = HEX("#1a1a28"), accent = HEX("#6a6aff"), pat = "ink" },
	skin_chalk = { base = HEX("#f4f0e4"), accent = HEX("#b4aa90"), pat = "chalk" },
	skin_stripe = { base = HEX("#ff4d6a"), accent = HEX("#ffe15a"), pat = "stripe" },
	skin_speckle = { base = HEX("#3d6bff"), accent = HEX("#ffffff"), pat = "speckle" },
	skin_marble = { base = HEX("#ece8f4"), accent = HEX("#8a84a8"), pat = "marble" },
	skin_candy = { base = HEX("#ff78d2"), accent = HEX("#7af6ff"), pat = "stripe" },
	skin_chrome = { base = HEX("#d5dde8"), accent = HEX("#6c7890"), pat = "chrome" },
	skin_glass = { base = HEX("#9ee6ff"), accent = HEX("#ffffff"), pat = "glass" },
	skin_neon = { base = HEX("#10141c"), accent = HEX("#39ffb0"), pat = "neon" },
	skin_galaxy = { base = HEX("#1c1240"), accent = HEX("#d2b0ff"), pat = "stars" },
	skin_prism = { base = HEX("#f4f4ff"), accent = HEX("#ff6ad5"), pat = "prism" },
	skin_crown = { base = HEX("#ffd24a"), accent = HEX("#e09a14"), pat = "crown" },
	trail_dust = { base = HEX("#e0c48a"), accent = HEX("#fff2cc"), pat = "dust" },
	trail_sparks = { base = HEX("#ffb03a"), accent = HEX("#fff1a0"), pat = "sparks" },
	trail_ribbon = { base = HEX("#ff6ad5"), accent = HEX("#ffffff"), pat = "ribbon" },
	trail_comet = { base = HEX("#7ecbff"), accent = HEX("#ffffff"), pat = "comet" },
	trail_rainbow = { base = HEX("#ff5a7a"), accent = HEX("#7af6ff"), pat = "rainbow" },
	trail_void = { base = HEX("#7a3cff"), accent = HEX("#2a1050"), pat = "void" },
	trail_eclipse = { base = HEX("#ffd63c"), accent = HEX("#1a1028"), pat = "eclipse" },
	force_pulse = { base = HEX("#ffd63c"), accent = HEX("#fff6c0"), pat = "pulse" },
	force_ring = { base = HEX("#7ad0ff"), accent = HEX("#ffffff"), pat = "ring" },
	force_burst = { base = HEX("#ff542c"), accent = HEX("#ffe15a"), pat = "burst" },
	force_nova = { base = HEX("#fff1a8"), accent = HEX("#ff9a3c"), pat = "nova" },
	frame_wood = { base = HEX("#c4844a"), accent = HEX("#7a4520"), pat = "wood" },
	frame_iron = { base = HEX("#b8c0d0"), accent = HEX("#5c6478"), pat = "iron" },
	frame_gold = { base = HEX("#ffe066"), accent = HEX("#d08a10"), pat = "gold" },
	frame_myth = { base = HEX("#d08cff"), accent = HEX("#6a28a8"), pat = "myth" },
	frame_champion = { base = HEX("#fff0a0"), accent = HEX("#ff9a1c"), pat = "champion" },
	podium_spot = { base = HEX("#b04cff"), accent = HEX("#ffd63c"), pat = "stage" },
	ko_card = { base = HEX("#ff3c46"), accent = HEX("#ffd63c"), pat = "ko" },
}

local function paintOf(id: string): Paint
	return PAINT[id] or { base = HEX("#b04cff"), accent = HEX("#ffffff"), pat = "flash" }
end

local function lum(c: Color3): number
	return 0.3 * c.R + 0.59 * c.G + 0.11 * c.B
end

-- Hard-edged bands of colours (stripes) as a colour sequence.
local function bands(colors: { Color3 }, n: number): ColorSequence
	local keys = {}
	for i = 0, n - 1 do
		local c = colors[i % #colors + 1]
		local a, b = i / n, (i + 1) / n
		table.insert(keys, ColorSequenceKeypoint.new(a, c))
		table.insert(keys, ColorSequenceKeypoint.new(if i == n - 1 then 1 else b - 0.001, c))
	end
	return ColorSequence.new(keys)
end

local function seq(colors: { Color3 }): ColorSequence
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

local function grad(o: Instance, cs: ColorSequence, rotation: number): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = cs
	g.Rotation = rotation
	g.Parent = o
	return g
end

-- Small discs on a ball (speckles, stars, ink splats), all within 0.3 d of its centre.
local function specks(ball: Frame, d: number, color: Color3, n: number, size: number, alpha: number?)
	for i = 1, n do
		local ang = i * 2.4
		local r = d * (0.08 + 0.24 * ((i * 7) % n) / math.max(1, n - 1))
		local s = Theme.disc(
			ball,
			math.max(4, math.floor(d * size)),
			color,
			UDim2.fromOffset(d / 2 + math.cos(ang) * r, d / 2 + math.sin(ang) * r),
			alpha
		)
		s.ZIndex = 4
	end
end

-- A skin: the ball as a disc of its material with its pattern, a shine and an ink outline, on a glow.
local function skinPreview(box: Frame, paint: Paint, w: number, h: number)
	local m = math.min(w, h)
	local dark = lum(paint.base) < 0.3
	local cx, cy = w / 2, h / 2
	if paint.pat == "crown" then
		cy = h / 2 + m * 0.08
	end
	box.BackgroundColor3 = if dark then HEX("#d8d2ff") else Theme.SLOT:Lerp(paint.base, 0.18)
	local glowCol = if dark then WHITE else paint.base:Lerp(WHITE, 0.35)
	Theme.glow(box, math.floor(m * 0.98), glowCol, UDim2.fromOffset(w / 2, h / 2), 5, if dark then 0.6 else 0.8).ZIndex =
		2
	local d = math.floor(m * (if paint.pat == "crown" then 0.6 else 0.74))
	Theme.shadow(box, math.floor(d * 0.7), UDim2.fromOffset(cx, math.min(h - 6, cy + d / 2))).ZIndex = 2
	local ball = Theme.disc(box, d, paint.base, UDim2.fromOffset(cx, cy))
	ball.Name = "Ball"
	ball.ZIndex = 3
	Theme.stroke(ball, 3, Theme.INK)
	local pat = paint.pat
	if pat == "stripe" then
		grad(ball, bands({ paint.base, paint.accent }, 6), 35)
	elseif pat == "prism" then
		grad(ball, seq({ HEX("#ff5a7a"), HEX("#ffd63c"), HEX("#5af096"), HEX("#5ac8ff"), HEX("#b06cff") }), 45)
	elseif pat == "marble" then
		grad(ball, seq({ paint.base, paint.accent, paint.base, WHITE, paint.accent:Lerp(WHITE, 0.4), paint.base }), 60)
	elseif pat == "chrome" then
		grad(ball, seq({ WHITE, paint.base, paint.accent, WHITE, paint.base }), 90)
	elseif pat == "glass" then
		local g = grad(ball, seq({ WHITE, paint.base }), 120)
		g.Transparency = NumberSequence.new(0.05, 0.35)
		local rim = Theme.ring(ball, math.floor(d * 0.78), WHITE, 2, UDim2.fromScale(0.5, 0.5))
		rim.ZIndex = 4
	elseif pat == "neon" then
		Theme.glow(box, math.floor(m * 0.9), paint.accent, UDim2.fromOffset(w / 2, h / 2), 4, 0.85).ZIndex = 2
		local ring = Theme.ring(ball, math.floor(d * 0.66), paint.accent, 4, UDim2.fromScale(0.5, 0.5))
		ring.ZIndex = 4
		local edge = ball:FindFirstChildOfClass("UIStroke") :: UIStroke
		edge.Color = paint.accent
		edge.Thickness = 4
		local core = Theme.disc(ball, math.floor(d * 0.22), paint.accent, UDim2.fromScale(0.5, 0.5))
		core.ZIndex = 4
	elseif pat == "stars" then
		grad(ball, seq({ HEX("#7a4ae0"), HEX("#2a1a6a"), HEX("#ff6ad5"):Lerp(paint.base, 0.6), HEX("#0a0618") }), 50)
		specks(ball, d, paint.accent, 7, 0.09)
		specks(ball, d, WHITE, 4, 0.04)
	elseif pat == "ink" then
		grad(ball, seq({ HEX("#3a3a64"), paint.base }), 70)
		specks(ball, d, paint.accent, 5, 0.12, 0.1)
	elseif pat == "chalk" then
		specks(ball, d, paint.accent, 9, 0.07, 0.2)
	elseif pat == "speckle" then
		specks(ball, d, paint.accent, 10, 0.08)
	elseif pat == "crown" then
		grad(ball, seq({ HEX("#fff3a0"), paint.base, paint.accent }), 90)
		local cw = math.floor(d * 0.62)
		-- the crown image is a square tile; its top stays inside the well
		local crown = Theme.crown(box, cw, UDim2.fromOffset(cx, math.max(cw / 2 + 2, cy - d * 0.5)))
		crown.ZIndex = 6
	end
	-- shine, upper left
	local shine =
		Theme.disc(ball, math.floor(d * 0.24), WHITE, UDim2.fromOffset(d * 0.32, d * 0.3), if dark then 0.5 else 0.45)
	shine.Name = "Shine"
	shine.ZIndex = 5
end

-- A trail: the player's ball on the right, the tail fanning out to the left and fading.
local function trailPreview(box: Frame, paint: Paint, e: number, w: number, h: number)
	local cy = h / 2
	box.BackgroundColor3 = if paint.pat == "eclipse" or paint.pat == "void" then HEX("#2c2450") else Theme.SLOT
	local d = math.floor(math.min(h * 0.62, w * 0.34) / BALL_SPAN)
	local span = math.ceil(d * BALL_SPAN)
	local bx = w - 6 - span / 2
	local tailW = math.floor(bx - 8)
	local bandH = math.floor(d * 0.78)
	local band = Theme.frame(box, UDim2.fromOffset(tailW, bandH), UDim2.fromOffset(8, cy - bandH / 2), paint.base)
	band.Name = "Stripe"
	band.ZIndex = 2
	Theme.round(band, math.floor(bandH / 2))
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	if paint.pat == "rainbow" then
		fade.Color = seq({ HEX("#b06cff"), HEX("#5ac8ff"), HEX("#5af096"), HEX("#ffd63c"), HEX("#ff5a7a") })
	elseif paint.pat == "ribbon" then
		fade.Color = bands({ paint.base, paint.accent }, 5)
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0.1)
	else
		fade.Color = seq({ paint.accent, paint.base })
	end
	fade.Parent = band
	-- puffs along the tail: smaller and fainter further back
	for i = 1, 5 do
		local t = i / 6
		local pd = math.max(6, math.floor(d * (0.75 - t * 0.55)))
		local px = bx - span * 0.4 - t * (tailW - 10)
		local col = if paint.pat == "eclipse" then paint.base else paint.base:Lerp(paint.accent, t * 0.6)
		if paint.pat == "rainbow" then
			col = ({ HEX("#ff5a7a"), HEX("#ffd63c"), HEX("#5af096"), HEX("#5ac8ff"), HEX("#b06cff") })[i]
		end
		local p = Theme.disc(box, pd, col, UDim2.fromOffset(math.max(8 + pd / 2, px), cy), 0.1 + t * 0.5)
		p.ZIndex = 3
	end
	if paint.pat == "sparks" or paint.pat == "dust" or paint.pat == "comet" or paint.pat == "eclipse" then
		for i = 1, 6 do
			local sx = 14 + (i - 1) * (tailW - 20) / 5
			local sy = cy + (if i % 2 == 0 then -1 else 1) * bandH * (0.45 + (i % 3) * 0.08)
			local sd = if paint.pat == "dust" then 7 else 6
			local s = Theme.disc(box, sd, paint.accent:Lerp(WHITE, 0.3), UDim2.fromOffset(sx, sy), 0.15)
			s.ZIndex = 3
		end
	end
	if paint.pat == "eclipse" or paint.pat == "void" then
		local halo = Theme.ring(box, math.floor(d * 1.05), paint.base, 4, UDim2.fromOffset(bx, cy))
		halo.ZIndex = 4
	end
	Theme.shadow(box, math.floor(d * 0.6), UDim2.fromOffset(bx, math.min(h - 6, cy + d / 2 + 2))).ZIndex = 4
	local ball = Theme.ball(box, e, d, UDim2.fromOffset(bx, cy), MID)
	ball.Name = "Ball"
	ball.ZIndex = 5
end

-- A force: the ball in the middle of a ring and a flash of the effect colour.
local function forcePreview(box: Frame, paint: Paint, e: number, w: number, h: number)
	local m = math.min(w, h)
	local cx, cy = w / 2, h / 2
	box.BackgroundColor3 = Theme.BG:Lerp(paint.base, 0.12)
	local pat = paint.pat
	Theme.glow(box, math.floor(m * 0.96), paint.base, UDim2.fromOffset(cx, cy), 5, if pat == "nova" then 0.7 else 0.82).ZIndex =
		2
	if pat == "burst" or pat == "nova" or pat == "pulse" then
		local n = if pat == "burst" then 8 else 6
		local rays = Theme.rays(
			box,
			n,
			math.floor(m * 0.96),
			if pat == "burst" then 12 else 9,
			UDim2.fromOffset(cx, cy),
			paint.base,
			paint.accent,
			0.05
		)
		rays.ZIndex = 2
		for _, r in rays:GetChildren() do
			if r:IsA("GuiObject") then
				r.ZIndex = 2
			end
		end
	end
	local ringD = math.floor(m * 0.8)
	local ring = Theme.ring(box, ringD, paint.base, if pat == "ring" then 7 else 5, UDim2.fromOffset(cx, cy))
	ring.Name = "Flash"
	ring.ZIndex = 3
	if pat == "ring" or pat == "pulse" then
		Theme.ring(box, math.floor(m * 0.62), paint.accent, 3, UDim2.fromOffset(cx, cy)).ZIndex = 3
	end
	local d = math.floor(m * 0.44 / BALL_SPAN)
	local ball = Theme.ball(box, e, d, UDim2.fromOffset(cx, cy), MID)
	ball.Name = "Ball"
	ball.ZIndex = 4
end

-- A frame: a portrait of the player's ball inside a square of the frame's material.
local function framePreview(box: Frame, paint: Paint, e: number, w: number, h: number)
	local side = math.floor(math.min(w, h) - 8)
	local cx, cy = w / 2, h / 2
	box.BackgroundColor3 = Theme.SLOT
	local pat = paint.pat
	if pat == "myth" or pat == "champion" or pat == "gold" then
		Theme.glow(box, math.min(w, h), paint.base, UDim2.fromOffset(cx, cy), 4, 0.84).ZIndex = 2
	end
	local outer = Theme.frame(box, UDim2.fromOffset(side, side), UDim2.fromOffset(cx, cy), WHITE, MID)
	outer.Name = "Portrait"
	outer.ZIndex = 3
	Theme.round(outer, math.floor(side * 0.12))
	Theme.stroke(outer, 3, Theme.INK)
	grad(outer, seq({ paint.base, paint.accent, paint.base:Lerp(WHITE, 0.2), paint.accent }), 45)
	local border = math.max(8, math.floor(side * 0.13))
	local inner = Theme.frame(
		outer,
		UDim2.fromOffset(side - border * 2, side - border * 2),
		UDim2.fromScale(0.5, 0.5),
		WHITE,
		MID
	)
	inner.ZIndex = 4
	Theme.round(inner, math.floor(side * 0.07))
	Theme.stroke(inner, 2, Theme.INK)
	Theme.gradient(inner, Theme.GLOW:Lerp(paint.base, 0.25), Theme.BG)
	local id = side - border * 2
	local d = math.floor(id * 0.7 / BALL_SPAN)
	Theme.shadow(inner, math.floor(d * 0.7), UDim2.fromOffset(id / 2, id / 2 + d / 2 + 1)).ZIndex = 5
	local ball = Theme.ball(inner, e, d, UDim2.fromOffset(id / 2, id / 2 - 2), MID)
	ball.Name = "Ball"
	ball.ZIndex = 6
	if pat == "iron" then
		for _, p in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
			local r = Theme.disc(
				outer,
				math.max(5, math.floor(border * 0.5)),
				paint.accent,
				UDim2.fromOffset(border / 2 + p[1] * (side - border), border / 2 + p[2] * (side - border))
			)
			r.ZIndex = 5
		end
	elseif pat == "champion" then
		local cw = math.floor(border * 2.2)
		Theme.crown(outer, cw, UDim2.fromOffset(side / 2, cw / 2)).ZIndex = 7
	elseif pat == "myth" then
		for _, p in { { 0.5, 0 }, { 0.5, 1 }, { 0, 0.5 }, { 1, 0.5 } } do
			local gem = Theme.frame(
				outer,
				UDim2.fromOffset(border, border),
				UDim2.fromOffset(border / 2 + p[1] * (side - border), border / 2 + p[2] * (side - border)),
				paint.base:Lerp(WHITE, 0.5),
				MID
			)
			gem.Rotation = 45
			gem.Size = UDim2.fromOffset(math.floor(border * 0.62), math.floor(border * 0.62))
			gem.ZIndex = 5
			Theme.stroke(gem, 2, Theme.INK)
		end
	end
end

local function extraPreview(box: Frame, paint: Paint, id: string, e: number, w: number, h: number)
	local cx, cy = w / 2, h / 2
	box.BackgroundColor3 = Theme.SLOT:Lerp(paint.base, 0.2)
	Theme.glow(box, math.min(w, h), paint.base, UDim2.fromOffset(cx, cy), 4, 0.82).ZIndex = 2
	if id == "ko_card" then
		local ch = math.floor(h * 0.8)
		local cw = math.floor(ch * 0.72)
		local card = Theme.frame(box, UDim2.fromOffset(cw, ch), UDim2.fromOffset(cx, cy), WHITE, MID)
		card.Name = "Card"
		card.Rotation = -6
		card.ZIndex = 3
		Theme.round(card, 10)
		Theme.stroke(card, 3, Theme.INK)
		Theme.gradient(card, paint.base, paint.base:Lerp(Theme.INK, 0.4))
		local d = math.floor(cw * 0.56 / BALL_SPAN)
		local ball = Theme.ball(card, e, d, UDim2.fromOffset(cw / 2, ch * 0.38), MID)
		ball.Name = "Ball"
		ball.ZIndex = 4
		Theme.label(card, "KO!", 24, UDim2.fromOffset(cw - 8, 26), UDim2.new(0.5, 0, 1, -6), {
			anchor = V2(0.5, 1),
			color = paint.accent,
			stroke = 3,
			z = 5,
		})
	else
		local sw = math.floor(w * 0.62)
		local sh = math.max(14, math.floor(h * 0.2))
		local stage = Theme.frame(box, UDim2.fromOffset(sw, sh), UDim2.fromOffset(cx, h - 8 - sh / 2), WHITE, MID)
		stage.Name = "Stage"
		stage.ZIndex = 3
		Theme.round(stage, 6)
		Theme.stroke(stage, 3, Theme.INK)
		Theme.gradient(stage, paint.accent, paint.accent:Lerp(Theme.INK, 0.35))
		local room = h - 8 - sh - 6
		local d = math.floor(math.min(room, w * 0.5) / BALL_SPAN)
		local span = d * BALL_SPAN
		local ball = Theme.ball(box, e, d, UDim2.fromOffset(cx, h - 8 - sh - span / 2 + 4), MID)
		ball.Name = "Ball"
		ball.ZIndex = 4
	end
end

local function picture(box: Frame, id: string, e: number, w: number, h: number)
	local paint = paintOf(id)
	local kind = kindOf(id)
	if kind == "SKIN" then
		skinPreview(box, paint, w, h)
	elseif kind == "TRAIL" then
		trailPreview(box, paint, e, w, h)
	elseif kind == "FORCE" then
		forcePreview(box, paint, e, w, h)
	elseif kind == "FRAME" then
		framePreview(box, paint, e, w, h)
	else
		extraPreview(box, paint, id, e, w, h)
	end
end

local function iconFn(parent: Instance, cur: string, d: number, pos: UDim2): GuiObject
	return Money.icon(parent, cur, d, pos)
end

-- host is the shop body. Chips on top, then whole rows of cards in a scroller.
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
	local worn = if on and on.ball >= 0 then on.ball else (v.balls[1] or 0)

	-- chips and the ball counter
	local countW = 96
	local count = Theme.label(host, `{n}/{need}`, 24, UDim2.fromOffset(countW, 30), UDim2.new(1, -4, 0, CHIP_H / 2), {
		anchor = V2(1, 0.5),
		align = Enum.TextXAlignment.Right,
		color = Theme.DIM,
		stroke = 3,
	})
	count.Name = "Count"
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 20
	cap.MaxTextSize = 28
	cap.Parent = count
	-- chips scroll sideways: each keeps a readable width (>= 140) on any screen
	local chipsW = w - countW - 8
	local chipW = math.max(140, math.floor((chipsW - GAP * (#CHIPS - 1)) / #CHIPS))
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Chips"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Position = UDim2.fromOffset(0, 0)
	strip.Size = UDim2.fromOffset(chipsW, CHIP_H + 8)
	strip.CanvasSize = UDim2.fromOffset(#CHIPS * (chipW + GAP) - GAP, CHIP_H)
	strip.ScrollBarThickness = 4
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ElasticBehavior = Enum.ElasticBehavior.Never
	strip.Active = true
	strip.Parent = host
	for i, c in CHIPS do
		local sel = filter == c.key
		local col = if sel then Theme.PURPLE else Theme.PURPLE:Lerp(Theme.SLOT, 0.7)
		local b = Theme.button(
			strip,
			c.word,
			UDim2.fromOffset(chipW, CHIP_H),
			UDim2.fromOffset((i - 1) * (chipW + GAP), 0),
			col,
			nil,
			Theme.fit(c.word, 26, chipW - 14, CHIP_H - 14)
		)
		b.Name = `Chip_{c.key}`
		Theme.select(b, sel)
		if not sel then
			local l = b:FindFirstChild("Label") :: TextLabel?
			if l then
				l.TextColor3 = Theme.DIM
			end
		end
		b.Activated:Connect(function()
			if filter ~= c.key then
				filter = c.key
				host:ClearAllChildren()
				Shelf.fill(host, v, ctx, w, h)
			end
		end)
	end

	local listTop = CHIP_H + 14
	local listH = math.max(80, h - listTop)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Looks"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, listTop)
	list.Size = UDim2.fromOffset(w, listH)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ScrollBarThickness = 8
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.Active = true
	list.Parent = host

	local shown = {}
	for _, look in Economy.LOOKS do
		if filter == "all" or groupOf(look.id) == filter then
			table.insert(shown, look)
		end
	end

	local cols = if w >= 820 then 4 else 3
	local cardW = math.floor((w - 12 - GAP * (cols - 1)) / cols)
	local rows = math.max(1, math.floor((listH + GAP) / (CARD_NAT + GAP)))
	local cardH = math.floor((listH - GAP * (rows - 1)) / rows)

	for i, look in shown do
		local id = look.id
		local mine = have[id] == true
		local tier = tierOf(look.coins)
		local tint = TIER_COL[tier]
		local col = (i - 1) % cols
		local rowI = (i - 1) // cols
		local card = Theme.card(
			list,
			UDim2.fromOffset(cardW, cardH),
			UDim2.fromOffset(col * (cardW + GAP), rowI * (cardH + GAP)),
			Theme.SLOT:Lerp(tint, 0.3),
			Theme.SLOT,
			16
		)
		card.Name = `R_{id}`
		card:SetAttribute("Tier", tier)
		if tier == "epic" or tier == "legendary" then
			local edge = card:FindFirstChild("Edge") :: UIStroke
			edge.Color = tint
			edge.Thickness = 4
		end
		local stripe = Theme.frame(card, UDim2.new(1, 0, 0, 6), nil, tint)
		stripe.Name = "TierStripe"

		-- preview well
		local pad = 10
		local nameH = 28
		local by = cardH - pad - BTN_H
		local previewY = 14
		local previewW = cardW - pad * 2
		local previewH = math.max(60, by - 6 - nameH - 4 - previewY)
		local icon = Theme.frame(card, UDim2.fromOffset(previewW, previewH), UDim2.fromOffset(pad, previewY), Theme.BG)
		icon.Name = "Icon"
		icon.ClipsDescendants = true
		icon.ZIndex = 2
		Theme.round(icon, 12)
		Theme.stroke(icon, 3, Theme.INK)
		picture(icon, id, worn, previewW, previewH)
		-- a short well (phone) keeps the picture: the tier then reads from the card colour and the kind text
		local roomy = previewH >= 100
		if roomy then
			local chip = Theme.ribbon(icon, TIER_WORD[tier], tint, UDim2.fromOffset(4, 4), 24)
			chip.Name = "Tier"
			chip.ZIndex = 8
			for _, c in chip:GetDescendants() do
				if c:IsA("GuiObject") then
					c.ZIndex = 9
				end
			end
		end
		if mine then
			local tick = Theme.disc(icon, 30, Theme.GOOD, UDim2.new(1, -19, 0, 19))
			tick.Name = "Tick"
			tick.ZIndex = 8
			Theme.stroke(tick, 3, Theme.INK)
			Theme.label(tick, "✓", 22, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), {
				anchor = MID,
				stroke = 2,
				z = 9,
			})
		end

		-- name and kind
		local nameY = previewY + previewH + 4
		local kind = kindOf(id)
		local kindW = math.ceil(5 * 0.7 * Theme.MIN_TEXT) + 8 -- FRAME / TRAIL / FORCE at the minimum text
		local nm = title(id)
		Theme.label(
			card,
			nm,
			Theme.fit(nm, 26, previewW - kindW - 4, nameH),
			UDim2.fromOffset(previewW - kindW - 4, nameH),
			UDim2.fromOffset(pad, nameY),
			{
				align = Enum.TextXAlignment.Left,
				color = if tier == "legendary" then Theme.YELLOW_TXT else Theme.TEXT,
				stroke = 3,
				z = 3,
			}
		).Name =
			"Name"
		Theme.label(card, kind, 20, UDim2.fromOffset(kindW, nameH), UDim2.fromOffset(cardW - pad - kindW, nameY), {
			align = Enum.TextXAlignment.Right,
			color = if roomy then Theme.DIM else tint:Lerp(Color3.new(1, 1, 1), 0.35),
			bold = true,
			z = 3,
		}).Name =
			"Kind"

		-- price or equip
		if mine then
			local wearW = math.floor(previewW * 0.56)
			Theme.label(card, "OWNED", 22, UDim2.fromOffset(previewW - wearW - 6, BTN_H), UDim2.fromOffset(pad, by), {
				align = Enum.TextXAlignment.Left,
				color = Theme.GOOD_TXT,
				stroke = 3,
				z = 3,
			}).Name =
				"Own"
			local onNow = wearing(id)
			local wear = Theme.button(
				card,
				if onNow then "ON" else "EQUIP",
				UDim2.fromOffset(wearW, BTN_H),
				UDim2.fromOffset(cardW - pad - wearW, by),
				Theme.GO,
				nil,
				24
			)
			wear.Name = "Wear"
			wear.ZIndex = 10
			if onNow then
				Theme.disable(wear, "ON")
			else
				wear.Active = true
				wear.Activated:Connect(function()
					local ball = if kind == "SKIN" then worn else nil
					ctx.act(Net.Action.wear, ball, id)
				end)
			end
		else
			local coinW = previewW
			local coins = Theme.price(
				card,
				Money.fmt(look.coins),
				UDim2.fromOffset(coinW, BTN_H),
				UDim2.fromOffset(pad, by),
				"coins",
				iconFn,
				22
			)
			coins.Name = "PayCoins"
			coins.ZIndex = 10
			coins.Active = true
			coins.Activated:Connect(function()
				ctx.act(Net.Action.look, nil, id)
			end)
		end
	end
	local rowsN = math.ceil(#shown / cols)
	list.CanvasSize = UDim2.fromOffset(0, math.max(rowsN * (cardH + GAP) - GAP, 1))
end

-- Tests and a re-opened shop start on ALL.
function Shelf.reset()
	filter = "all"
end

return Shelf
