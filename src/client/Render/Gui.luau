--!strict
-- Tiny builders for the canvas-like board GUI: circles, rings, segments, text with outline, atlas images.
-- All sizes are canvas pixels (a cell is CELL px, as in the web build).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(ReplicatedStorage.Shared.Art)
local Look = require(ReplicatedStorage.Shared.Look)

local Gui = {}

Gui.CELL = 34
Gui.OFF = UDim2.fromOffset(-10000, -10000)

function Gui.frame(parent: Instance?, color: Color3?, z: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or Color3.new(1, 1, 1)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

function Gui.round(o: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = o
end

-- Filled circle of radius r centred on its position.
function Gui.circle(parent: Instance?, r: number, color: Color3, z: number?): Frame
	local f = Gui.frame(parent, color, z)
	f.Size = UDim2.fromOffset(r * 2, r * 2)
	Gui.round(f)
	return f
end

-- Ring of radius r (centre of the line) and width w: a transparent circle with an outside stroke.
function Gui.ring(parent: Instance?, r: number, w: number, color: Color3, z: number?): (Frame, UIStroke)
	local f = Gui.frame(parent, color, z)
	f.BackgroundTransparency = 1
	Gui.round(f)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Parent = f
	Gui.setRing(f, s, r, w)
	return f, s
end

function Gui.setRing(f: Frame, s: UIStroke, r: number, w: number)
	local d = math.max(0, 2 * r - w)
	f.Size = UDim2.fromOffset(d, d)
	s.Thickness = math.max(0.5, w)
end

-- Straight line segment with round caps feel: a rotated bar between two points.
function Gui.segment(f: Frame, x0: number, y0: number, x1: number, y1: number, w: number)
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	f.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromOffset(len + w * 0.6, w)
	f.Rotation = math.deg(math.atan2(dy, dx))
end

export type TextOpts = { font: Font?, stroke: number?, scol: Color3?, z: number?, xa: Enum.TextXAlignment? }

-- Text like the web txt(): fill colour, dark outline of `stroke` px.
function Gui.text(parent: Instance?, size: number, color: Color3, opts: TextOpts?): (TextLabel, UIStroke)
	local o: TextOpts = opts or {}
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Size = UDim2.fromOffset(10, 10)
	t.AutomaticSize = Enum.AutomaticSize.XY
	t.FontFace = o.font or Look.FONT
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = o.xa or Enum.TextXAlignment.Center
	t.ZIndex = o.z or 1
	t.Text = ""
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Color = o.scol or Look.INK
	s.Thickness = o.stroke or 0
	s.Enabled = (o.stroke or 0) > 0
	s.Parent = t
	t.Parent = parent
	return t, s
end

-- Ball art of element e (web ballArt) for a ball of radius r.
function Gui.ballImage(parent: Instance?, e: number, r: number, z: number?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Image = Art.BALLS
	i.ImageRectSize = Vector2.new(Art.BALL, Art.BALL)
	i.ZIndex = z or 1
	Gui.setBall(i, e, r)
	i.Parent = parent
	return i
end

function Gui.setBall(i: ImageLabel, slot: number, r: number)
	local s = Art.BALL * r / Art.BALL_R
	i.Size = UDim2.fromOffset(s, s)
	i.ImageRectOffset = Art.ballRect(slot)
end

return Gui
