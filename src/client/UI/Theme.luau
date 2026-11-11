--!strict
-- Web look for every screen (ball_territory_web/public/index.html: BG, PANEL, btn, big/txt, ballArt, crownArt):
-- dark blue panels, heavy font with an ink outline, ball icons from the art atlas, press/pop feedback. Spec: docs/ui.md.
-- Sizes are design px of the 960x540 canvas that init.luau scales to the screen (0.72 on a 844x390 phone).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Art = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Art"))
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))

local Theme = {}

local hex = Color3.fromHex
Theme.BG = hex("#11132a")
Theme.GLOW = hex("#2a2062")
Theme.PANEL = hex("#1f2244")
Theme.PANEL_HI = hex("#3a3a70")
Theme.SLOT = hex("#2a2e5a")
Theme.RING = hex("#464a78")
Theme.TEXT = Color3.new(1, 1, 1)
Theme.DIM = hex("#c8cdf5")
Theme.MUTED = hex("#8c90b8")
Theme.GOOD = hex("#00e66e")
Theme.GOOD_TXT = hex("#5af096")
Theme.BAD = hex("#ff3c46")
Theme.BAD_TXT = hex("#ff7878")
Theme.YELLOW = hex("#ffd63c")
Theme.YELLOW_TXT = hex("#ffe65a")
Theme.INK = Look.INK
Theme.FRAME = Look.FRAME
Theme.HEART = hex("#ff3355")
-- buttons: main action green (Ball vs Ball Play), duel purple, cancel red, quiet slot blue
Theme.GO = hex("#2ed068")
Theme.PURPLE = hex("#b04cff")
Theme.ORANGE = hex("#ff542c")
Theme.MEDAL = { hex("#ffd63c"), hex("#dfe6f5"), hex("#e8a060"), hex("#8c90b8") }

-- Seat colours (plate ring, name): duel side 0 blue, side 1 red; ffa by side.
Theme.SEAT = { hex("#40baff"), hex("#ff5a5a"), hex("#5af096"), hex("#ffd63c") }

Theme.FONT = Look.FONT
Theme.BOLD = Look.BOLD

-- Minimum touch height: 80 px on a 390 px phone (scale 0.72) -> 112 design px. Text never under 20 (14 px).
Theme.BTN_H = 112
Theme.MIN_TEXT = 20

function Theme.reduced(): boolean
	return GuiService.ReducedMotionEnabled
end

export type TextOpts = {
	color: Color3?,
	bold: boolean?, -- small body font (Arimo Bold) instead of the heavy title font
	stroke: number?, -- outline thickness, 0 = none
	align: Enum.TextXAlignment?,
	anchor: Vector2?,
	z: number?,
	wrap: boolean?,
}

function Theme.frame(parent: Instance, size: UDim2, pos: UDim2?, color: Color3?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or Theme.PANEL
	f.BorderSizePixel = 0
	f.Size = size
	if pos then
		f.Position = pos
	end
	if anchor then
		f.AnchorPoint = anchor
	end
	f.Parent = parent
	return f
end

function Theme.clear(parent: Instance, size: UDim2, pos: UDim2?, anchor: Vector2?): Frame
	local f = Theme.frame(parent, size, pos, nil, anchor)
	f.BackgroundTransparency = 1
	return f
end

function Theme.round(o: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = if radius and radius >= 999 then UDim.new(1, 0) else UDim.new(0, radius or 10)
	c.Parent = o
	return c
end

function Theme.stroke(o: Instance, thickness: number?, color: Color3?, contextual: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Theme.INK
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

-- Text like the web big()/txt(): heavy font, ink outline, fits its box (shrinks down to 70%, never under MIN_TEXT).
function Theme.text(parent: Instance, text: string, size: number, box: UDim2, pos: UDim2?, opts: TextOpts?): TextLabel
	local o: TextOpts = opts or {}
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.FontFace = if o.bold then Theme.BOLD else Theme.FONT
	t.TextColor3 = o.color or Theme.TEXT
	t.TextXAlignment = o.align or Enum.TextXAlignment.Center
	t.TextWrapped = o.wrap == true
	t.TextScaled = true
	t.Size = box
	if pos then
		t.Position = pos
	end
	if o.anchor then
		t.AnchorPoint = o.anchor
	end
	if o.z then
		t.ZIndex = o.z
	end
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.MinTextSize = math.max(Theme.MIN_TEXT, math.floor(size * 0.7))
	c.Parent = t
	local st = o.stroke or math.max(2, math.floor(size / 12))
	if st > 0 then
		Theme.stroke(t, st, Theme.INK, true)
	end
	t.Parent = parent
	return t
end

-- Ball art from the atlas (ballArt of the web, with its dark outline) with the given visible diameter.
function Theme.ball(parent: Instance, e: number, d: number, pos: UDim2?, anchor: Vector2?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = Art.BALLS
	i.ImageRectSize = Vector2.new(Art.BALL, Art.BALL)
	i.ImageRectOffset = Art.ballRect(e)
	local s = Art.BALL * (d / 2) / Art.BALL_R
	i.Size = UDim2.fromOffset(s, s)
	i.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	if pos then
		i.Position = pos
	end
	i.Parent = parent
	return i
end

-- Crown (web crownArt) from the atlas; `w` is its width.
function Theme.crown(parent: Instance, w: number, pos: UDim2?, anchor: Vector2?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = Art.BALLS
	i.ImageRectSize = Vector2.new(Art.BALL, Art.BALL)
	i.ImageRectOffset = Art.ballRect(Art.CROWN)
	i.Size = UDim2.fromOffset(w, w)
	i.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	if pos then
		i.Position = pos
	end
	i.Parent = parent
	return i
end

-- Ring (circle outline) of diameter d.
function Theme.ring(parent: Instance, d: number, color: Color3, thick: number, pos: UDim2?): Frame
	local f = Theme.clear(parent, UDim2.fromOffset(d, d), pos, Vector2.new(0.5, 0.5))
	Theme.round(f, 999)
	Theme.stroke(f, thick, color)
	return f
end

function Theme.disc(parent: Instance, d: number, color: Color3, pos: UDim2?, alpha: number?): Frame
	local f = Theme.frame(parent, UDim2.fromOffset(d, d), pos, color, Vector2.new(0.5, 0.5))
	f.BackgroundTransparency = alpha or 0
	Theme.round(f, 999)
	return f
end

function Theme.scaleOf(o: GuiObject): UIScale
	local s = o:FindFirstChildOfClass("UIScale")
	if s then
		return s
	end
	local n = Instance.new("UIScale")
	n.Parent = o
	return n
end
local scaleOf = Theme.scaleOf

-- Text with a fixed size (no TextScaled): stays still while its button or window scales. Use it inside anything
-- that animates; Theme.text (TextScaled) re-fits on every frame of a UIScale tween and its glyphs jump.
function Theme.label(parent: Instance, text: string, size: number, box: UDim2, pos: UDim2?, opts: TextOpts?): TextLabel
	local t = Theme.text(parent, text, size, box, pos, opts)
	t.TextScaled = false
	t.TextSize = math.max(Theme.MIN_TEXT, size)
	local c = t:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c:Destroy()
	end
	return t
end

-- Heavy-font size that fits `text` on one line into w x h (rough glyph width 0.7 em), never under MIN_TEXT.
function Theme.fit(text: string, size: number, w: number, h: number): number
	local n = math.max(1, utf8.len(text) or #text)
	return math.max(Theme.MIN_TEXT, math.floor(math.min(size, w / (n * 0.7), h * 0.72)))
end

-- Soft pop of a window, card or badge: UIScale `from` (0.85) -> 1, 0.28 s, small overshoot, after `delay` seconds.
-- One curve for every popup; big rewards pass a lower `from` for a stronger pop.
function Theme.pop(o: GuiObject, delay: number?, from: number?)
	if Theme.reduced() then
		return
	end
	local s = scaleOf(o)
	s.Scale = from or 0.85
	local tw = TweenService:Create(
		s,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay or 0),
		{ Scale = 1 }
	)
	tw:Play()
end

local HOVER, PRESSED = 1.04, 0.93
local EASE_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EASE_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Press and hover: the whole button scales as one piece (its UIScale), smoothly, no bounce; the text has a fixed
-- size so nothing inside moves on its own.
function Theme.press(b: GuiButton)
	local s = scaleOf(b)
	local over, down = false, false
	local function go(info: TweenInfo)
		if Theme.reduced() then
			s.Scale = 1
			return
		end
		local k = if down and b.Active then PRESSED elseif over and b.Active then HOVER else 1
		TweenService:Create(s, info, { Scale = k }):Play()
	end
	b.MouseEnter:Connect(function()
		over = true
		go(EASE_OUT)
	end)
	b.MouseLeave:Connect(function()
		over, down = false, false
		go(EASE_OUT)
	end)
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			down = true
			go(EASE_IN)
		end
	end)
	b.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			down = false
			if t == Enum.UserInputType.Touch then
				over = false
			end
			go(EASE_OUT)
		end
	end)
end

local function lipOf(c: Color3): Color3
	return c:Lerp(Color3.new(0, 0, 0), 0.38)
end

-- The one button of the game. Layers (all inside the button, so a UIScale moves them together):
--   Body  - full size, the darker lip colour, rounded, ink outline around the whole shape (the lip never covers it)
--   Face  - the fill, LIP px shorter, so the lip shows under it; a light-to-dark gradient and a soft shine on top
--   Label - fixed-size white text with an ink outline, centred on the face (one text colour on every button)
-- Colour: set button.BackgroundColor3 (it stays transparent; Face and Body follow). Disabled: Theme.disable.
function Theme.button(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2?,
	color: Color3?,
	_textColor: Color3?, -- kept for old calls: every button now has white text
	textSize: number?,
	anchor: Vector2?
): TextButton
	local bg = color or Theme.SLOT
	local h = if size.Y.Scale == 0 then size.Y.Offset else 60
	local w = if size.X.Scale == 0 then size.X.Offset else 0
	local lip = math.clamp(math.floor(h * 0.1 + 0.5), 4, 9)
	local radius = math.min(16, math.floor(h * 0.3))
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = bg
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Size = size
	if pos then
		b.Position = pos
	end
	if anchor then
		b.AnchorPoint = anchor
	end
	local body = Theme.frame(b, UDim2.fromScale(1, 1), nil, lipOf(bg))
	body.Name = "Body"
	Theme.round(body, radius)
	local edge = Theme.stroke(body, 3, Theme.INK)
	edge.Name = "Edge"
	local face = Theme.frame(body, UDim2.new(1, 0, 1, -lip), nil, bg)
	face.Name = "Face"
	Theme.round(face, radius)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(214, 214, 214))
	g.Parent = face
	local shine =
		Theme.frame(face, UDim2.new(1, -2 * radius, 0, math.max(4, math.floor(h * 0.12))), nil, Color3.new(1, 1, 1))
	shine.Name = "Shine"
	shine.Position = UDim2.fromOffset(radius, math.max(3, math.floor(h * 0.08)))
	shine.BackgroundTransparency = 0.72
	Theme.round(shine, 999)
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		face.BackgroundColor3 = b.BackgroundColor3
		body.BackgroundColor3 = lipOf(b.BackgroundColor3)
	end)
	if text ~= "" then
		local ts = textSize or 40
		if w > 0 then
			ts = Theme.fit(text, ts, w - 20, h - lip)
		end
		local l = Theme.label(
			b,
			text,
			ts,
			UDim2.new(1, -16, 1, -lip),
			UDim2.fromScale(0.5, 0),
			{ anchor = Vector2.new(0.5, 0), z = 3, stroke = math.max(2, math.floor(ts / 10)) }
		)
		l.Name = "Label"
	end
	b.Parent = parent
	Theme.press(b)
	return b
end

-- Grey, inactive button (HOST STARTS, a mode that needs two).
function Theme.disable(b: TextButton, text: string?)
	b.BackgroundColor3 = Theme.PANEL_HI
	b.Active = false
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.TextColor3 = Theme.DIM
		if text then
			l.Text = text
		end
	end
end

-- Outline of a button: yellow while its window is open.
function Theme.select(b: TextButton, on: boolean)
	local body = b:FindFirstChild("Body")
	local edge = body and body:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Color = if on then Theme.YELLOW else Theme.INK
		edge.Thickness = if on then 4 else 3
	end
end

-- Small count or "!" pill on the top right corner of a button or icon.
function Theme.badge(parent: GuiObject, text: string, color: Color3?, name: string?): Frame
	local w = math.max(30, 14 + 11 * (utf8.len(text) or #text))
	-- centred on the corner: sticks out of the button instead of covering its icon
	local d =
		Theme.frame(parent, UDim2.fromOffset(w, 30), UDim2.new(1, -4, 0, 2), color or Theme.BAD, Vector2.new(0.5, 0.5))
	d.Name = name or "Badge"
	d.ZIndex = 6
	Theme.round(d, 999)
	Theme.stroke(d, 2.5, Theme.INK)
	local t = Theme.label(d, text, 20, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), {
		anchor = Vector2.new(0.5, 0.5),
		z = 7,
		stroke = 2,
	})
	t.Name = "Text"
	return d
end

-- Plaza layout (docs/ui.md «Площадка»), design px of the canvas; shared by Plaza, Wallet and Level.
--   top left, right of the Roblox buttons: icon row DAILY / QUESTS / BOOK / HELP (secondary, opened now and then)
--   top right: coins and crystals
--   right edge, above the jump button: PLAY (biggest) and PARTY under it - the only main actions
--   bottom middle, between the stick and the jump button: level, XP bar, next ball; the 2x XP icon right of it
export type PlazaLayout = {
	right: number,
	playW: number,
	playY: number,
	playH: number,
	partyY: number,
	partyH: number,
	rowX: number,
	rowY: number,
	icon: number,
	gap: number,
	moneyW: number,
	moneyH: number,
	moneyY: { number },
	barW: number,
	barH: number,
	barX: number,
	barY: number,
}

function Theme.plaza(cv: Vector2, topbar: Vector2): PlazaLayout
	local barW = 430
	local playY = 138
	local moneyH = 42
	local moneyGap = 6
	-- Coins and crystals stay on the right, above PLAY. On a wide screen the Roblox
	-- player list covers that corner, so drop the stack under the top bar. topbar.Y
	-- is already the GuiInset in design px (one pad included). Use it once. A phone
	-- safe area is much taller than the gap above PLAY; applying it would open a hole
	-- on the right and cover PLAY, so that case keeps the compact top.
	local playGap = 8
	local maxTop = playY - playGap - moneyH * 2 - moneyGap
	local moneyTop = 12
	if topbar.Y > moneyTop and topbar.Y <= maxTop + 16 then
		moneyTop = math.min(topbar.Y, maxTop)
	end
	return {
		right = cv.X - 14,
		playW = 230,
		playY = playY,
		playH = 104,
		partyY = 254,
		partyH = 66,
		rowX = topbar.X + 6,
		rowY = 16,
		icon = 80,
		gap = 10,
		moneyW = 180,
		moneyH = moneyH,
		moneyY = { moneyTop, moneyTop + moneyH + moneyGap },
		barW = barW,
		barH = 64,
		barX = cv.X / 2,
		barY = cv.Y - 14 - 64,
	}
end

-- Square icon button of the plaza row: an emoji icon, a caption under it, room for a badge on the corner.
function Theme.iconButton(
	parent: Instance,
	icon: string,
	caption: string,
	size: number,
	pos: UDim2,
	color: Color3
): TextButton
	local b = Theme.button(parent, "", UDim2.fromOffset(size, size), pos, color)
	Theme.label(b, icon, 38, UDim2.fromOffset(size, 42), UDim2.new(0.5, 0, 0, 7), {
		anchor = Vector2.new(0.5, 0),
		stroke = 0,
		z = 3,
	}).Name =
		"Icon"
	local c = Theme.label(b, caption, 20, UDim2.fromOffset(size, 22), UDim2.new(0.5, 0, 0, 48), {
		anchor = Vector2.new(0.5, 0),
		bold = true,
		stroke = 2,
		z = 3,
	})
	c.Name = "Caption"
	return b
end

-- Ball name colour (web NAMECOL), lifted to the light tint when it is too dark to read on the navy panels.
function Theme.nameColor(e: number): Color3
	local c = Look.NAMECOL[e + 1] or Theme.TEXT
	local l = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return if l < 0.4 then Look.light(e) else c
end

-- Readable text colour on a ball-coloured button (web ON_COL).
function Theme.onColor(c: Color3): Color3
	local l = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return if l > 0.62 then Theme.INK else Theme.TEXT
end

-- Web backdrop(): BG with a soft purple glow in the middle (stacked translucent discs stand in for the radial).
function Theme.backdrop(root: Instance, alpha: number?): Frame
	local f = Theme.frame(root, UDim2.fromScale(1, 1), nil, Theme.BG)
	f.Name = "Backdrop"
	f.BackgroundTransparency = alpha or 0
	f.ClipsDescendants = true
	f.ZIndex = 0
	for i = 1, 6 do
		local d = Theme.frame(f, UDim2.fromScale(1.5 - i * 0.2, 2.2 - i * 0.3), UDim2.fromScale(0.5, 0.62), Theme.GLOW)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BackgroundTransparency = 0.82
		d.ZIndex = 0
		Theme.round(d, 999)
	end
	return f
end

-- Shrinking timer bar (web: yellow on #2a2e5a); returns the fill to resize.
function Theme.timeBar(parent: Instance, w: number, h: number, pos: UDim2, anchor: Vector2?): Frame
	local bar = Theme.frame(parent, UDim2.fromOffset(w, h), pos, Theme.SLOT, anchor)
	Theme.round(bar, h)
	local fill = Theme.frame(bar, UDim2.fromScale(1, 1), nil, Theme.YELLOW)
	Theme.round(fill, h)
	return fill
end

function Theme.heart(parent: Instance, size: number, pos: UDim2?, on: boolean): TextLabel
	local t = Theme.text(parent, "♥", size, UDim2.fromOffset(size, size), pos, {
		color = if on then Theme.HEART else Theme.RING,
		bold = true,
		stroke = 2,
	})
	return t
end

return Theme
