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

local function scaleOf(o: GuiObject): UIScale
	local s = o:FindFirstChildOfClass("UIScale")
	if s then
		return s
	end
	local n = Instance.new("UIScale")
	n.Parent = o
	return n
end

-- Pop in: UIScale from `from` to 1 with an overshoot, after `delay` seconds.
function Theme.pop(o: GuiObject, delay: number?, from: number?)
	if Theme.reduced() then
		return
	end
	local s = scaleOf(o)
	s.Scale = from or 0.4
	local tw = TweenService:Create(
		s,
		TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay or 0),
		{ Scale = 1 }
	)
	tw:Play()
end

-- Press feedback: shrink while held, spring back on release.
function Theme.press(b: GuiButton)
	local s = scaleOf(b)
	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if
			not Theme.reduced()
			and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
			and b.Active
		then
			TweenService:Create(s, TweenInfo.new(0.08), { Scale = 0.9 }):Play()
		end
	end)
	b.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				:Play()
		end
	end)
end

-- Flat web button with a darker bottom lip, ink outline and press feedback.
function Theme.button(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2?,
	color: Color3?,
	textColor: Color3?,
	textSize: number?,
	anchor: Vector2?
): TextButton
	local bg = color or Theme.SLOT
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = bg
	b.BorderSizePixel = 0
	b.Size = size
	if pos then
		b.Position = pos
	end
	if anchor then
		b.AnchorPoint = anchor
	end
	Theme.round(b, 12)
	Theme.stroke(b, 3, Theme.INK)
	local lip = Theme.frame(b, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -10), bg:Lerp(Color3.new(0, 0, 0), 0.35))
	Theme.round(lip, 12)
	lip.ZIndex = 1
	local shine = Theme.frame(b, UDim2.new(1, -16, 0, 6), UDim2.fromOffset(8, 6), Color3.new(1, 1, 1))
	shine.BackgroundTransparency = 0.8
	Theme.round(shine, 3)
	if text ~= "" then
		local tc = textColor or Theme.TEXT
		local dark = tc.R + tc.G + tc.B < 1
		local l = Theme.text(
			b,
			text,
			textSize or 40,
			UDim2.new(1, -24, 1, -18),
			UDim2.new(0.5, 0, 0.5, -3),
			{ anchor = Vector2.new(0.5, 0.5), color = tc, stroke = if dark then 0 else nil, z = 3 }
		)
		l.Name = "Label"
	end
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

return Theme
