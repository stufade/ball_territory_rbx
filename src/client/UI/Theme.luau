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

-- Phone rule (MOB-1): a screen under 500 real px tall (a phone in landscape) gets text never under 22 design px
-- (15.8 px at scale 0.72 instead of 14.4), the plaza HUD in one row (no room kept for the Roblox player list,
-- which a phone does not show) and windows placed under the Roblox buttons. UI/init calls setPhone on every fit;
-- `topbar` is the corner to keep clear (design px), set there too.
Theme.phone = false
Theme.topbar = Vector2.new(354, 80)
function Theme.setPhone(on: boolean)
	Theme.phone = on
	Theme.MIN_TEXT = if on then 22 else 20
end

-- Centre y of a window `h` tall on canvas `cv`: below the Roblox buttons when the screen has the room, never off
-- the bottom edge (6 px margin); a window taller than that keeps as much of the topbar clear as it can.
function Theme.windowY(cv: Vector2, h: number): number
	local top = Theme.topbar.Y + 4
	return math.max(math.min(math.max(cv.Y / 2, top + h / 2), cv.Y - 6 - h / 2), h / 2)
end

function Theme.reduced(): boolean
	return GuiService.ReducedMotionEnabled
end

-- Gamepad focus on `obj`. The engine warns "invalid GuiObject" when the target is not in the live GUI tree yet (a window
-- that is still being built) or was destroyed by a rebuild, so the pick waits one frame and re-checks.
function Theme.focus(obj: GuiObject?)
	if obj == nil then
		return
	end
	task.defer(function()
		if obj.Parent ~= nil and obj.Selectable and obj:IsDescendantOf(game) then
			GuiService.SelectedObject = obj
		end
	end)
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

-- Soft pop of a window, card or badge: UIScale `from` (0.85) -> 1, 0.2 s, Quint Out (no overshoot, no bounce: P-1),
-- after `delay` seconds. One curve for every popup; big rewards pass a lower `from` for a stronger pop.
function Theme.pop(o: GuiObject, delay: number?, from: number?)
	if Theme.reduced() then
		return
	end
	local s = scaleOf(o)
	s.Scale = from or 0.85
	local tw = TweenService:Create(
		s,
		TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, delay or 0),
		{ Scale = 1 }
	)
	tw:Play()
end

local HOVER, PRESSED = 1.04, 0.93
local EASE_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EASE_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Press and hover: the whole button scales as one piece (its UIScale), smoothly, no bounce; the text has a fixed
-- size so nothing inside moves on its own.
-- Plays a Render/Sfx cue; silent if the module is not there (tests, early boot).
local sfxMod: any = nil
function Theme.sfx(name: string)
	if sfxMod == nil then
		local ok, mod: any = pcall(function(): any
			local render = script.Parent.Parent:FindFirstChild("Render")
			local sfx = render and render:FindFirstChild("Sfx")
			return if sfx then (require :: any)(sfx) else false
		end)
		sfxMod = if ok then mod else false
	end
	if sfxMod then
		pcall(sfxMod.play, name)
	end
end

function Theme.press(b: GuiButton)
	local s = scaleOf(b)
	b.Activated:Connect(function()
		Theme.sfx("click")
	end)
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
	local cap = b:FindFirstChild("Caption") :: TextLabel?
	if cap and not body then
		cap.TextColor3 = if on then Theme.YELLOW_TXT else Theme.TEXT
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

-- Plaza layout (docs/ui.md «Площадка»), design px of the canvas; shared by Plaza, Wallet and Level (P-1):
--   top left, right of the Roblox buttons: one row of four picture icons DAILY / QUESTS / BOOK / SHOP (a PC, where the
--   Roblox player list covers the top right, puts the row under the Roblox buttons); no HELP, no SPIN (the spin is a
--   shop tab)
--   bottom left, under the stick: the big coin counter with "+" (coin packs)
--   right edge, above the jump button: PLAY (biggest) and PARTY under it - the only main actions; the dev button small
--   under PARTY
--   bottom middle, between the stick and the jump button: level, XP bar, next ball; the 2x XP icon right of it
export type PlazaLayout = {
	right: number,
	-- right edge of what the top of the screen may use: left of the Roblox player list on a PC
	listX: number,
	-- right edge of the coin counter (its left edge is walletX - moneyW)
	walletX: number,
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

-- Roblox player list (top right, real px incl. margin) and the UI scale (real px per design px, set by UI/init).
Theme.LIST_PX = 190
Theme.scale = 1

-- HUD pictures (own SVG art, tools/art/hud; docs/licenses/assets.md).
Theme.HUD_ICON = {
	daily = "rbxassetid://79399567920096",
	quests = "rbxassetid://134446016241479",
	book = "rbxassetid://107518731338758",
	shop = "rbxassetid://115317288173478",
	coins = "rbxassetid://96009887810654",
}

function Theme.plaza(cv: Vector2, topbar: Vector2): PlazaLayout
	local barW = 430
	local icon, gap = 88, 8
	local listX = if Theme.phone then cv.X - 14 else cv.X - 14 - math.ceil(Theme.LIST_PX / math.max(Theme.scale, 0.1))
	local rowX, rowY = topbar.X + 6, 18
	if rowX + 4 * (icon + gap) - gap > listX - 10 then
		rowX, rowY = 14, topbar.Y + 6
	end
	-- the coin counter fills the free corner under the stick, up to the level bar
	local moneyH = 60
	local moneyW = math.clamp(math.floor(cv.X / 2 - barW / 2 - 14 - 16), 220, 330)
	return {
		right = cv.X - 14,
		listX = listX,
		walletX = 14 + moneyW,
		playW = 230,
		playY = 138,
		playH = 104,
		partyY = 254,
		partyH = 66,
		rowX = rowX,
		rowY = rowY,
		icon = icon,
		gap = gap,
		moneyW = moneyW,
		moneyH = moneyH,
		moneyY = { cv.Y - 12 - moneyH },
		barW = barW,
		barH = 64,
		barX = cv.X / 2,
		barY = cv.Y - 14 - 64,
	}
end

-- Picture icon of the plaza row (P-1): the picture fills the button, the caption sits on its lower edge, a badge
-- fits on the corner. No frame: the picture carries its own ink outline. Theme.select turns the caption yellow.
function Theme.hudIcon(parent: Instance, image: string, caption: string, size: number, pos: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromOffset(size, size)
	b.Position = pos
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image
	i.ScaleType = Enum.ScaleType.Fit
	i.AnchorPoint = Vector2.new(0.5, 0)
	i.Size = UDim2.fromOffset(size - 8, size - 8)
	i.Position = UDim2.fromScale(0.5, 0)
	i.ZIndex = 2
	i.Parent = b
	local c = Theme.label(b, caption, 22, UDim2.fromOffset(size + 16, 26), UDim2.new(0.5, 0, 1, 2), {
		anchor = Vector2.new(0.5, 1),
		stroke = 3,
		z = 3,
	})
	c.Name = "Caption"
	b.Parent = parent
	Theme.press(b)
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

-- Shared look of the Daily family (Daily day 7, Shop, Spin, Shelf): scene cards with depth, ribbons, sale badges,
-- price buttons and wallet pills. Spec: docs/ui.md «Магазин».

-- Vertical (rotation 90) two-colour gradient on a frame; returns it.
function Theme.gradient(o: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = o
	return g
end

-- Soft glow: stacked translucent discs stand in for a radial gradient (as the VOID hole of day 7).
function Theme.glow(parent: Instance, d: number, color: Color3, pos: UDim2, layers: number?, alpha: number?): Frame
	local box = Theme.clear(parent, UDim2.fromOffset(d, d), pos, Vector2.new(0.5, 0.5))
	box.Name = "Glow"
	local n = layers or 6
	for k = 0, n - 1 do
		Theme.disc(box, d * (1 - k / (n + 1)), color, UDim2.fromScale(0.5, 0.5), alpha or 0.86)
	end
	return box
end

-- Light rays fanning out of a centre: a holder (turn it with .Rotation) with `n` thin bars, every other one tinted.
function Theme.rays(
	parent: Instance,
	n: number,
	len: number,
	w: number,
	pos: UDim2,
	a: Color3,
	b: Color3,
	alpha: number
): Frame
	local box = Theme.clear(parent, UDim2.fromOffset(len, len), pos, Vector2.new(0.5, 0.5))
	box.Name = "Rays"
	for i = 1, n do
		local r = Theme.frame(box, UDim2.fromOffset(w, len), UDim2.fromScale(0.5, 0.5), if i % 2 == 0 then a else b)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Rotation = (i - 1) * 180 / n
		r.BackgroundTransparency = alpha
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = r
	end
	return box
end

-- Flat ink ellipse under a ball: it stands on the floor of the scene.
function Theme.shadow(parent: Instance, w: number, pos: UDim2): Frame
	local s = Theme.frame(parent, UDim2.fromOffset(w, math.max(6, math.floor(w * 0.22))), pos, Theme.INK)
	s.Name = "Shadow"
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.BackgroundTransparency = 0.45
	Theme.round(s, 999)
	return s
end

-- Faint diamond pattern over a frame (the shop background, scene floors). Clips to the frame.
function Theme.pattern(f: Frame, color: Color3, alpha: number, step: number?)
	local st = step or 46
	local box = Theme.clear(f, UDim2.fromScale(1, 1))
	box.Name = "Pattern"
	box.ClipsDescendants = true
	-- offsets of the frame (pattern frames have offset sizes); 960x540 if it is sized by scale
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	if w < 1 or h < 1 then
		w, h = 960, 540
	end
	local cols, rows = math.ceil(w / st) + 1, math.ceil(h / st) + 1
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = c * st + (if r % 2 == 1 then st / 2 else 0)
			local d = Theme.frame(box, UDim2.fromOffset(st * 0.22, st * 0.22), UDim2.fromOffset(x, r * st * 0.6), color)
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Rotation = 45
			d.BackgroundTransparency = alpha
		end
	end
	return box
end

-- Ribbon chip ("BALL OF THE DAY", "LIMITED", tier): coloured pill, ink outline, white heavy text.
function Theme.ribbon(parent: Instance, text: string, color: Color3, pos: UDim2, h: number?, anchor: Vector2?): Frame
	local hh = h or 28
	local size = math.max(Theme.MIN_TEXT, math.floor(hh * 0.72))
	local w = math.floor(size * 0.62 * (utf8.len(text) or #text) + hh)
	local r = Theme.frame(parent, UDim2.fromOffset(w, hh), pos, color, anchor)
	r.Name = "Ribbon"
	Theme.round(r, 8)
	Theme.stroke(r, 3, Theme.INK)
	Theme.gradient(r, Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	local t = Theme.label(r, text, size, UDim2.new(1, -8, 1, 0), UDim2.fromScale(0.5, 0.5), {
		anchor = Vector2.new(0.5, 0.5),
		stroke = 2,
	})
	t.Name = "Text"
	return r
end

-- Sale badge: a red star (two turned squares) with white text, tilted.
function Theme.burst(parent: Instance, text: string, d: number, pos: UDim2, color: Color3?): Frame
	local box = Theme.clear(parent, UDim2.fromOffset(d, d), pos, Vector2.new(0.5, 0.5))
	box.Name = "Burst"
	box.Rotation = -12
	local col = color or Theme.BAD
	for k = 0, 1 do
		local sq = Theme.frame(box, UDim2.fromScale(0.74, 0.74), UDim2.fromScale(0.5, 0.5), col, Vector2.new(0.5, 0.5))
		sq.Rotation = k * 45
		Theme.round(sq, 6)
		Theme.stroke(sq, 3, Theme.INK)
	end
	local core = Theme.disc(box, d * 0.7, col, UDim2.fromScale(0.5, 0.5))
	Theme.gradient(core, col:Lerp(Color3.new(1, 1, 1), 0.25), col)
	local t = Theme.label(box, text, math.floor(d * 0.32), UDim2.fromScale(0.9, 0.5), UDim2.fromScale(0.5, 0.5), {
		anchor = Vector2.new(0.5, 0.5),
		stroke = 3,
		z = 3,
	})
	t.Name = "Text"
	return box
end

-- Scene card: rounded, ink outline, a top-to-bottom gradient of `color` (light top, deep bottom) - the day 7 card.
function Theme.card(parent: Instance, size: UDim2, pos: UDim2?, color: Color3, deep: Color3?, radius: number?): Frame
	local f = Theme.frame(parent, size, pos, Color3.new(1, 1, 1))
	f.ClipsDescendants = true
	Theme.round(f, radius or 18)
	Theme.gradient(f, color, deep or color:Lerp(Theme.BG, 0.7))
	Theme.stroke(f, 3, Theme.INK).Name = "Edge"
	return f
end

-- Slide up 26 px while it pops (the opening stagger of Daily).
function Theme.rise(o: GuiObject, delay: number)
	if Theme.reduced() then
		return
	end
	local p = o.Position
	o.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + 26)
	TweenService:Create(o, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, delay), {
		Position = p,
	}):Play()
	Theme.pop(o, delay, 0.9)
end

Theme.PRICE_COIN = hex("#2ed068")

-- Price button (Ball vs Ball green): coins green; the currency icon on the left, the amount
-- right of it. `icon` draws the currency (Money.icon) - passed in, Money requires Theme.
function Theme.price(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2?,
	cur: string,
	icon: (parent: Instance, cur: string, d: number, pos: UDim2) -> GuiObject,
	textSize: number?
): TextButton
	local h = size.Y.Offset
	local color = Theme.PRICE_COIN
	local b = Theme.button(parent, text, size, pos, color, nil, textSize or 24)
	b.Name = "PayCoins"
	local lip = math.clamp(math.floor(h * 0.1 + 0.5), 4, 9)
	local d = math.min(34, h - lip - 12)
	local ic = icon(b, cur, d, UDim2.fromOffset(8 + d / 2, (h - lip) / 2))
	ic.ZIndex = 4
	for _, c in ic:GetDescendants() do
		if c:IsA("GuiObject") then
			c.ZIndex = 4
		end
	end
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Size = UDim2.new(1, -(d + 18), 1, -lip)
		l.Position = UDim2.new(0, d + 12, 0, 0)
		l.AnchorPoint = Vector2.new(0, 0)
	end
	return b
end

-- Wallet pill of a window header: dark pill with a big icon sticking out on the left, the amount on the right.
function Theme.purse(
	parent: Instance,
	cur: string,
	text: string,
	w: number,
	pos: UDim2,
	color: Color3,
	icon: (parent: Instance, cur: string, d: number, pos: UDim2) -> GuiObject
): Frame
	local h = 44
	local box = Theme.frame(parent, UDim2.fromOffset(w, h), pos, Theme.BG)
	box.Name = "BalCoins"
	Theme.round(box, h / 2)
	Theme.stroke(box, 3, Theme.INK)
	Theme.gradient(box, Theme.SLOT, Theme.BG)
	icon(box, cur, 40, UDim2.fromOffset(6, h / 2))
	local t = Theme.label(box, text, 26, UDim2.fromOffset(w - 40, 30), UDim2.new(1, -12, 0.5, 0), {
		anchor = Vector2.new(1, 0.5),
		align = Enum.TextXAlignment.Right,
		color = color,
		stroke = 3,
	})
	t.Name = "Value"
	return box
end

return Theme
