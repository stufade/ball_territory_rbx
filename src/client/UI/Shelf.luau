--!strict
-- Skins tab of the shop. Every Economy.LOOKS row is a card: a picture in a tier frame, the name,
-- and the price on the card. A skin is the player's ball in that colour and pattern, a trail is a
-- stripe, a force is a flash, a frame is a portrait.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local HEX = Color3.fromHex

local Shelf = {}

export type Ctx = {
	canvas: Vector2,
	frames: { (dt: number) -> () },
	close: () -> (),
	act: (verb: string, arg: number?, cur: string?) -> (),
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

local function frameOf(coins: number): Color3
	if coins >= 12000 then
		return HEX("#ffd63c")
	elseif coins >= 8000 then
		return HEX("#c044ff")
	elseif coins >= 4000 then
		return HEX("#14a4ff")
	end
	return HEX("#3d6bff")
end

type Paint = { base: Color3, accent: Color3, pat: string }

local PAINT: { [string]: Paint } = {
	skin_ink = { base = HEX("#1a1a28"), accent = HEX("#8a8ab0"), pat = "ink" },
	skin_chalk = { base = HEX("#f4f0e4"), accent = HEX("#c8c0a8"), pat = "chalk" },
	skin_stripe = { base = HEX("#ff4d6a"), accent = HEX("#ffe15a"), pat = "stripe" },
	skin_speckle = { base = HEX("#3d6bff"), accent = HEX("#ffffff"), pat = "speckle" },
	skin_marble = { base = HEX("#ece8f4"), accent = HEX("#9a94b4"), pat = "marble" },
	skin_candy = { base = HEX("#ff78d2"), accent = HEX("#7af6ff"), pat = "stripe" },
	skin_chrome = { base = HEX("#d5dde8"), accent = HEX("#ffffff"), pat = "shine" },
	skin_glass = { base = HEX("#c4f0ff"), accent = HEX("#ffffff"), pat = "glass" },
	skin_neon = { base = HEX("#10141c"), accent = HEX("#39ffb0"), pat = "neon" },
	skin_galaxy = { base = HEX("#140e2c"), accent = HEX("#d2b0ff"), pat = "stars" },
	skin_prism = { base = HEX("#f4f4ff"), accent = HEX("#ff6ad5"), pat = "prism" },
	skin_crown = { base = HEX("#ffd24a"), accent = HEX("#fff6c2"), pat = "crown" },
	trail_dust = { base = HEX("#e0c48a"), accent = HEX("#fff2cc"), pat = "dust" },
	trail_sparks = { base = HEX("#ffb03a"), accent = HEX("#fff1a0"), pat = "sparks" },
	trail_ribbon = { base = HEX("#ff6ad5"), accent = HEX("#ffffff"), pat = "ribbon" },
	trail_comet = { base = HEX("#7ecbff"), accent = HEX("#ffffff"), pat = "comet" },
	trail_rainbow = { base = HEX("#ff5a7a"), accent = HEX("#7af6ff"), pat = "rainbow" },
	trail_void = { base = HEX("#7a3cff"), accent = HEX("#1a1028"), pat = "void" },
	trail_eclipse = { base = HEX("#1a1028"), accent = HEX("#ffd63c"), pat = "eclipse" },
	force_pulse = { base = HEX("#ffd63c"), accent = HEX("#fff6c0"), pat = "flash" },
	force_ring = { base = HEX("#7ad0ff"), accent = HEX("#ffffff"), pat = "ring" },
	force_burst = { base = HEX("#ff542c"), accent = HEX("#ffe15a"), pat = "flash" },
	force_nova = { base = HEX("#fff1a8"), accent = HEX("#ffffff"), pat = "flash" },
	frame_wood = { base = HEX("#c4844a"), accent = HEX("#8a5528"), pat = "portrait" },
	frame_iron = { base = HEX("#a8b0c0"), accent = HEX("#5c6478"), pat = "portrait" },
	frame_gold = { base = HEX("#ffd63c"), accent = HEX("#e09a14"), pat = "portrait" },
	frame_myth = { base = HEX("#c06cff"), accent = HEX("#6a28a8"), pat = "portrait" },
	frame_champion = { base = HEX("#ffe08a"), accent = HEX("#ffd63c"), pat = "portrait" },
	podium_spot = { base = HEX("#b04cff"), accent = HEX("#ffd63c"), pat = "stage" },
	ko_card = { base = HEX("#ff3c46"), accent = HEX("#ffd63c"), pat = "ko" },
}

local function paintOf(id: string): Paint
	return PAINT[id] or { base = HEX("#b04cff"), accent = HEX("#ffffff"), pat = "flash" }
end

local function bars(parent: Instance, cx: number, cy: number, d: number, colors: { Color3 })
	local n = #colors
	local h = math.max(6, math.floor(d / (n + 2)))
	for i, color in colors do
		local y = cy - d * 0.22 + (i - 1) * (h + 3)
		local band = Theme.frame(parent, UDim2.fromOffset(math.floor(d * 0.72), h), UDim2.fromOffset(cx, y), color, MID)
		band.BackgroundTransparency = 0.15
		band.ZIndex = 4
		Theme.round(band, 4)
	end
end

local function dots(parent: Instance, cx: number, cy: number, d: number, color: Color3, n: number)
	for i = 1, n do
		local ang = (i / n) * math.pi * 2
		local r = d * (0.16 + (i % 3) * 0.08)
		local p = Theme.disc(
			parent,
			math.max(6, d * 0.1),
			color,
			UDim2.fromOffset(cx + math.cos(ang) * r, cy + math.sin(ang) * r),
			0.1
		)
		p.ZIndex = 4
	end
end

-- Picture inside the tier frame. `e` is the player's ball, worn by a skin.
local function picture(box: Frame, id: string, e: number, w: number, h: number)
	local paint = paintOf(id)
	local kind = kindOf(id)
	local cx, cy = w / 2, h / 2
	box.BackgroundColor3 = paint.base
	if kind == "SKIN" then
		cy = math.floor(h * 0.4)
		local d = math.floor(h * 0.62)
		local ball = Theme.ball(box, e, d, UDim2.fromScale(0.5, 0.4), MID)
		ball.Name = "Ball"
		ball.ImageColor3 = paint.base:Lerp(
			Color3.new(1, 1, 1),
			if paint.pat == "ink" or paint.pat == "neon" or paint.pat == "stars" then 0.12 else 0.45
		)
		ball.ZIndex = 3
		local ring = Theme.ring(box, d, Theme.INK, 4, UDim2.fromOffset(cx, cy))
		ring.ZIndex = 6
		if paint.pat == "stripe" then
			bars(box, cx, cy, d, { paint.accent, paint.base:Lerp(Color3.new(1, 1, 1), 0.7) })
		elseif paint.pat == "prism" then
			bars(box, cx, cy, d, { HEX("#ff5a7a"), HEX("#ffd63c"), HEX("#5af0ff"), HEX("#b06cff") })
		elseif paint.pat == "speckle" or paint.pat == "chalk" then
			dots(box, cx, cy, d, paint.accent, 8)
		elseif paint.pat == "marble" or paint.pat == "shine" then
			local band = Theme.frame(
				box,
				UDim2.fromOffset(math.floor(d * 0.22), math.floor(d * 0.9)),
				UDim2.fromOffset(cx, cy),
				paint.accent,
				MID
			)
			band.Rotation = -28
			band.BackgroundTransparency = 0.35
			band.ZIndex = 4
		elseif paint.pat == "glass" then
			Theme.disc(
				box,
				math.floor(d * 0.55),
				Color3.new(1, 1, 1),
				UDim2.fromOffset(cx - d * 0.08, cy - d * 0.08),
				0.55
			).ZIndex =
				4
		elseif paint.pat == "neon" then
			local glow = Theme.ring(box, math.floor(d * 0.72), paint.accent, 4, UDim2.fromOffset(cx, cy))
			glow.ZIndex = 5
		elseif paint.pat == "stars" then
			dots(box, cx, cy, d, paint.accent, 7)
		elseif paint.pat == "ink" then
			local drip = Theme.frame(
				box,
				UDim2.fromOffset(10, math.floor(d * 0.28)),
				UDim2.fromOffset(cx + d * 0.12, cy + d * 0.1),
				paint.accent,
				MID
			)
			drip.ZIndex = 4
			Theme.round(drip, 6)
			Theme.disc(
				box,
				math.floor(d * 0.18),
				Color3.new(1, 1, 1),
				UDim2.fromOffset(cx - d * 0.16, cy - d * 0.16),
				0.45
			).ZIndex =
				5
		elseif paint.pat == "crown" then
			Theme.crown(box, math.floor(d * 0.42), UDim2.fromOffset(cx, cy - d * 0.28)).ZIndex = 6
		end
	elseif kind == "TRAIL" then
		local bandH = math.max(22, math.floor(h * 0.28))
		local bandY = math.floor(h * 0.4)
		local band = Theme.frame(box, UDim2.fromOffset(w - 10, bandH), UDim2.fromOffset(cx, bandY), paint.accent, MID)
		band.Name = "Stripe"
		band.ZIndex = 3
		Theme.round(band, math.floor(bandH / 2))
		Theme.stroke(band, 4, Theme.INK)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.45, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = band
		if paint.pat == "rainbow" then
			fade.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, HEX("#ff5a7a")),
				ColorSequenceKeypoint.new(0.35, HEX("#ffd63c")),
				ColorSequenceKeypoint.new(0.7, HEX("#5af096")),
				ColorSequenceKeypoint.new(1, HEX("#7ad0ff")),
			})
		end
		for i = 1, 4 do
			local dot = Theme.disc(
				box,
				math.max(8, math.floor(h * 0.16)),
				paint.base,
				UDim2.fromOffset(w * 0.16 + i * (w * 0.12), bandY - bandH * 0.2),
				0.1
			)
			dot.ZIndex = 4
		end
		local head = Theme.ball(box, e, math.floor(h * 0.42), UDim2.fromOffset(w * 0.78, bandY), MID)
		head.Name = "Ball"
		head.ZIndex = 5
	elseif kind == "FORCE" then
		local reach = math.floor(math.max(w, h) * 0.98)
		local thick = math.max(12, math.floor(math.min(w, h) * 0.16))
		for i = 1, 12 do
			local ray = Theme.frame(box, UDim2.fromOffset(thick, reach), UDim2.fromOffset(cx, cy), paint.accent, MID)
			ray.Rotation = (i - 1) * 15
			ray.BackgroundTransparency = 0.08
			ray.ZIndex = 2
			ray.Name = "Flash"
		end
		if paint.pat == "ring" then
			Theme.ring(box, math.floor(math.min(w, h) * 0.72), paint.accent, 6, UDim2.fromOffset(cx, cy)).ZIndex = 4
		end
		Theme.disc(box, math.floor(math.min(w, h) * 0.46), paint.base, UDim2.fromOffset(cx, cy), 0.05).ZIndex = 4
		local core =
			Theme.disc(box, math.floor(math.min(w, h) * 0.28), Color3.new(1, 1, 1), UDim2.fromOffset(cx, cy), 0.02)
		core.Name = "Flash"
		core.ZIndex = 5
	elseif kind == "FRAME" or kind == "CARD" then
		local mat = paint.base
		box.BackgroundColor3 = mat
		local margin = 8
		local inner = Theme.frame(
			box,
			UDim2.fromOffset(w - margin * 2, h - margin * 2),
			UDim2.fromOffset(cx, cy),
			paint.accent:Lerp(Theme.BG, 0.55),
			MID
		)
		inner.ZIndex = 2
		Theme.round(inner, 10)
		Theme.stroke(inner, 4, paint.accent)
		local d = math.floor(math.min(w, h) * 0.7)
		local ball = Theme.ball(inner, e, d, UDim2.fromScale(0.5, 0.38), MID)
		ball.Name = "Ball"
		ball.ZIndex = 3
		if id == "frame_champion" or paint.pat == "crown" then
			Theme.crown(inner, math.floor(d * 0.4), UDim2.fromScale(0.5, 0.16)).ZIndex = 4
		end
		if kind == "CARD" then
			Theme.label(inner, "KO", 22, UDim2.fromOffset(48, 24), UDim2.new(0.5, 0, 1, -4), {
				anchor = V2(0.5, 1),
				color = paint.accent,
				z = 5,
			})
		end
	else
		local stage = Theme.frame(
			box,
			UDim2.fromOffset(math.floor(w * 0.7), 16),
			UDim2.fromOffset(cx, h * 0.72),
			paint.accent,
			MID
		)
		stage.Name = "Stage"
		stage.ZIndex = 3
		Theme.round(stage, 4)
		Theme.stroke(stage, 3, Theme.INK)
		local ball = Theme.ball(box, e, math.floor(h * 0.42), UDim2.fromOffset(cx, h * 0.46), MID)
		ball.Name = "Ball"
		ball.ZIndex = 4
	end
end

local function prompt(productId: number)
	local player = Players.LocalPlayer
	if player and type(MarketplaceService.PromptProductPurchase) == "function" then
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end
end

-- host is the shop body. Cards in a grid. Buttons stay inside each card.
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
	local worn = if on and on.ball >= 0 then on.ball else (v.balls[1] or 0)

	local count = Theme.label(host, `{n}/{need}`, 22, UDim2.fromOffset(160, 26), UDim2.fromOffset(8, 0), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.TEXT,
	})
	count.Name = "Count"
	local cap = Instance.new("UITextSizeConstraint")
	cap.MinTextSize = 20
	cap.MaxTextSize = 28
	cap.Parent = count

	local listTop = 28
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
	local gap = 8
	local cols = if w >= 680 then 3 else 2
	local cardW = math.floor((w - 12 - gap * (cols - 1)) / cols)
	local room = math.max(80, h - listTop)
	local cardH = math.floor((room - gap - 8) / 2)
	local shown = cardH * 2 + gap
	list.Size = UDim2.fromOffset(w, shown)
	local bh = 72
	for i, look in looks do
		local id = look.id
		local mine = have[id] == true
		local kind = kindOf(id)
		local tint = frameOf(look.coins)
		local col = (i - 1) % cols
		local rowI = (i - 1) // cols
		local row = Theme.frame(
			list,
			UDim2.fromOffset(cardW, cardH),
			UDim2.fromOffset(col * (cardW + gap), rowI * (cardH + gap)),
			Theme.SLOT
		)
		row.Name = `R_{id}`
		row.ClipsDescendants = true
		Theme.round(row, 16)
		Theme.stroke(row, if look.coins >= 12000 then 4 else 3, tint)

		local icon = Theme.frame(row, UDim2.fromOffset(cardW - 12, cardH - 12), UDim2.fromOffset(6, 6), Theme.BG)
		icon.Name = "Icon"
		icon.ClipsDescendants = true
		Theme.round(icon, 12)
		Theme.stroke(icon, 4, tint)
		picture(icon, id, worn, cardW - 12, cardH - 12)

		local scrim = Theme.frame(row, UDim2.fromOffset(cardW - 16, 28), UDim2.fromOffset(8, 6), Theme.INK)
		scrim.BackgroundTransparency = 0.28
		scrim.ZIndex = 7
		Theme.round(scrim, 8)
		local nameY = 8
		Theme.label(row, title(id), 20, UDim2.fromOffset(cardW - 96, 22), UDim2.fromOffset(8, nameY), {
			align = Enum.TextXAlignment.Left,
			color = Theme.TEXT,
			z = 8,
		}).Name =
			"Name"
		Theme.label(row, kind, 20, UDim2.fromOffset(80, 22), UDim2.fromOffset(cardW - 88, nameY), {
			align = Enum.TextXAlignment.Right,
			color = Color3.new(1, 1, 1),
			z = 8,
		}).Name =
			"Kind"

		local by = cardH - 8 - bh
		local function priceButton(text: string, x: number, wide: number, color: Color3, bname: string): TextButton
			local b = Theme.button(row, text, UDim2.fromOffset(wide, bh), UDim2.fromOffset(x, by), color, nil, 20)
			b.Name = bname
			b.ZIndex = 10
			b.ClipsDescendants = true
			return b
		end
		if mine then
			local wearW = math.min(140, cardW - 16)
			local wearX = cardW - 8 - wearW
			Theme.label(
				row,
				"YOURS",
				20,
				UDim2.fromOffset(math.max(40, wearX - 12), 22),
				UDim2.fromOffset(8, by + 24),
				{
					align = Enum.TextXAlignment.Left,
					color = Theme.GOOD_TXT,
					z = 10,
				}
			).Name =
				"Own"
			local wear = priceButton(if wearing(id) then "ON" else "WEAR", wearX, wearW, Theme.GO, "Wear")
			if wearing(id) then
				Theme.disable(wear, "ON")
			else
				wear.Active = true
				wear.Activated:Connect(function()
					local ball = if kind == "SKIN" then worn else nil
					ctx.act(Net.Action.wear, ball, id)
				end)
			end
		else
			local gemW = math.floor((cardW - 22) * 0.4)
			local coinW = cardW - 16 - 6 - gemW
			local coins = priceButton(Money.fmt(look.coins), 8, coinW, Theme.YELLOW, "PayCoins")
			local pid = robux[id]
			local live = type(pid) == "number" and pid > 0
			local pay = priceButton(`{look.robux} R$`, 8 + coinW + 6, gemW, Theme.SLOT, "PayRobux")
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
	local rowsN = math.ceil(#looks / cols)
	list.CanvasSize = UDim2.fromOffset(0, math.max(rowsN * (cardH + gap), 1))
end

return Shelf
