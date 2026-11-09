--!strict
-- The board as a canvas: one SurfaceGui on a thin part in front of the arena Board, CELL px per cell, so the web
-- drawing (index.html drawField) maps one to one. Layers bottom-up: frame, cells, under (holes, aim, things),
-- balls, fx, tint; `root` shakes and zooms like the web field, `calls` (big words) stay still above it.
local Board = require(script.Parent.Board)
local Gui = require(script.Parent.Gui)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Look = require(ReplicatedStorage.Shared.Look)

local MARGIN = 1 -- cells of dark border around the field inside the canvas

export type Field = {
	board: Board.Board,
	part: Part,
	gui: SurfaceGui,
	root: Frame,
	scale: UIScale,
	cells: Frame,
	under: Frame,
	balls: Frame,
	fx: Frame,
	tint: Frame,
	calls: Frame,
	w: number, -- canvas px
	h: number,
	fw: number, -- field px
	fh: number,
}

local Field = {}

local function layer(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	f.Parent = parent
	return f
end

function Field.new(board: Board.Board): Field
	local C = Gui.CELL
	local cs = board.cs
	local wc, hc = board.gw + 2 * MARGIN, board.gh + 2 * MARGIN
	local part = Instance.new("Part")
	part.Name = "Screen"
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(wc * cs, hc * cs, 0.05)
	-- centre of the field in Origin space, a hair towards the camera (+Z) over the Board face
	part.CFrame = board.origin * CFrame.new(board.gw * cs / 2, -board.gh * cs / 2, 0.08)
	part.Parent = board.folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Back -- +Z, towards the camera
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = C / cs
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Adornee = part
	local bg = Instance.new("Frame")
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.fromHex("#0b0c22")
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = gui
	local w, h = wc * C, hc * C
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(w, h)
	root.ZIndex = 2
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local fw, fh = board.gw * C, board.gh * C
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Look.FRAME
	frame.Position = UDim2.fromOffset(MARGIN * C - 5, MARGIN * C - 5)
	frame.Size = UDim2.fromOffset(fw + 10, fh + 10)
	frame.Parent = root
	local cells = layer(root, "Cells", 2)
	cells.Position = UDim2.fromOffset(MARGIN * C, MARGIN * C)
	cells.Size = UDim2.fromOffset(fw, fh)
	local under = layer(root, "Under", 3)
	local balls = layer(root, "Balls", 4)
	local fx = layer(root, "Fx", 5)
	local tint = Instance.new("Frame")
	tint.BorderSizePixel = 0
	tint.Position = cells.Position
	tint.Size = cells.Size
	tint.BackgroundTransparency = 1
	tint.ZIndex = 6
	tint.Parent = root
	local calls = layer(gui, "Calls", 10)
	gui.Parent = board.folder
	return {
		board = board,
		part = part,
		gui = gui,
		root = root,
		scale = scale,
		cells = cells,
		under = under,
		balls = balls,
		fx = fx,
		tint = tint,
		calls = calls,
		w = w,
		h = h,
		fw = fw,
		fh = fh,
	}
end

-- Field-rule coordinates (cells, fractional) to canvas px.
function Field.px(self: Field, x: number): number
	return (MARGIN + x - self.board.ox) * Gui.CELL
end
function Field.py(self: Field, y: number): number
	return (MARGIN + y - self.board.oy) * Gui.CELL
end
function Field.at(self: Field, x: number, y: number): UDim2
	return UDim2.fromOffset((MARGIN + x - self.board.ox) * Gui.CELL, (MARGIN + y - self.board.oy) * Gui.CELL)
end

-- Field rect in canvas px: x0, y0, x1, y1.
function Field.rect(self: Field): (number, number, number, number)
	local C = Gui.CELL
	return MARGIN * C, MARGIN * C, MARGIN * C + self.fw, MARGIN * C + self.fh
end

-- Shake offset (px) and zoom around a canvas point.
function Field.view(self: Field, ox: number, oy: number, zoom: number, fx: number, fy: number)
	local ax, ay = fx / self.w, fy / self.h
	self.root.AnchorPoint = Vector2.new(ax, ay)
	self.root.Position = UDim2.fromOffset(fx + ox, fy + oy)
	self.scale.Scale = 1 + zoom
end

function Field.destroy(self: Field)
	self.part:Destroy()
	self.gui:Destroy()
end

return Field
