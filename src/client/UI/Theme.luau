--!strict
-- Gray-prototype look: colors, fonts, sizes and tiny widget builders. Spec: docs/ui.md.
-- All sizes are in "design pixels" of a 960x540 canvas that init.luau scales to the screen.

local Theme = {}

Theme.BG = Color3.fromRGB(34, 36, 42)
Theme.PANEL = Color3.fromRGB(58, 61, 70)
Theme.PANEL_LIGHT = Color3.fromRGB(84, 88, 99)
Theme.TEXT = Color3.fromRGB(245, 245, 245)
Theme.DIM = Color3.fromRGB(170, 174, 184)
Theme.GOOD = Color3.fromRGB(80, 200, 110)
Theme.BAD = Color3.fromRGB(230, 80, 80)
Theme.ACCENT = Color3.fromRGB(255, 190, 50)
Theme.MAIN = Color3.fromRGB(70, 150, 255)
Theme.NEUTRAL = Color3.fromRGB(110, 114, 124)
Theme.OUTLINE = Color3.fromRGB(12, 12, 16)

-- Seat colors for the land bar and portraits: duel side 0 blue, side 1 red; ffa by seat index.
Theme.SEAT = {
	Color3.fromRGB(70, 150, 255),
	Color3.fromRGB(235, 80, 80),
	Color3.fromRGB(80, 200, 110),
	Color3.fromRGB(245, 200, 60),
}

Theme.TITLE_FONT = Enum.Font.FredokaOne
Theme.BODY_FONT = Enum.Font.BuilderSansBold

-- Minimum touch height: 80 px on a 390 px high phone at scale 390/540 -> 112 design px.
Theme.BTN_H = 112
Theme.BIG_H = 150

export type LabelOpts = {
	color: Color3?,
	title: boolean?,
	anchor: Vector2?,
	align: Enum.TextXAlignment?,
	outline: boolean?,
}

local function place(o: GuiObject, pos: UDim2?, size: UDim2?, anchor: Vector2?)
	if pos then
		o.Position = pos
	end
	if size then
		o.Size = size
	end
	if anchor then
		o.AnchorPoint = anchor
	end
end

function Theme.frame(parent: Instance, size: UDim2, pos: UDim2?, color: Color3?, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color or Theme.PANEL
	f.BorderSizePixel = 0
	place(f, pos, size, anchor)
	f.Parent = parent
	return f
end

function Theme.round(o: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 14)
	c.Parent = o
end

function Theme.stroke(o: Instance, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Theme.OUTLINE
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
end

function Theme.label(
	parent: Instance,
	text: string,
	textSize: number,
	size: UDim2,
	pos: UDim2?,
	opts: LabelOpts?
): TextLabel
	local o: LabelOpts = opts or {}
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = textSize
	t.TextColor3 = o.color or Theme.TEXT
	t.Font = if o.title then Theme.TITLE_FONT else Theme.BODY_FONT
	t.TextXAlignment = o.align or Enum.TextXAlignment.Center
	t.TextWrapped = true
	t.TextScaled = false
	place(t, pos, size, o.anchor)
	if o.outline ~= false then
		t.TextStrokeTransparency = 0.3
		t.TextStrokeColor3 = Theme.OUTLINE
	end
	t.Parent = parent
	return t
end

-- Rounded text button with outline. Returns the button; use :Activated().
function Theme.button(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2?,
	color: Color3?,
	textSize: number?,
	anchor: Vector2?
): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or Theme.PANEL_LIGHT
	b.BorderSizePixel = 0
	b.Text = text
	b.TextSize = textSize or 40
	b.TextColor3 = Theme.TEXT
	b.Font = Theme.TITLE_FONT
	b.TextStrokeTransparency = 0.3
	b.TextStrokeColor3 = Theme.OUTLINE
	place(b, pos, size, anchor)
	Theme.round(b)
	Theme.stroke(b)
	b.Parent = parent
	return b
end

-- Colored circle with the first letter of an element: stands in for the ball icon until M4.
function Theme.ballIcon(parent: Instance, e: number, title: string, size: number, pos: UDim2?, anchor: Vector2?): Frame
	local f =
		Theme.frame(parent, UDim2.fromOffset(size, size), pos, Color3.fromHSV((e * 0.137) % 1, 0.45, 0.85), anchor)
	Theme.round(f, size)
	Theme.stroke(f, 2)
	Theme.label(f, string.sub(title, 1, 1), math.floor(size * 0.55), UDim2.fromScale(1, 1), nil, { title = true })
	return f
end

return Theme
