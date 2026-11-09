--!strict
-- Field tiles: one pooled Part per cell, created once per round, updated only for changed cells.
local Board = require(script.Parent.Board)
local Geo = require(script.Parent.Geo)
local Palette = require(script.Parent.Palette)

local BASE_H = 0.1 -- plate height, fraction of CellSize
local GAP = 0.94
local BOUNCE_H = 0.28
local BOUNCE_T = 0.22
local MAX_BOUNCE = 48

export type Cells = {
	board: Board.Board,
	top: { string },
	slots: { [number]: number },
	parts: { Part },
	value: { number },
	thick: { number },
	bounce: { [number]: number }, -- cell -> time left
	nbounce: number,
	captured: number, -- owner changes counted since the last takeCaptured
}

local Cells = {}

function Cells.new(board: Board.Board, top: { string }, slots: { [number]: number }): Cells
	local n = board.gw * board.gh
	local parts = table.create(n)
	local value = table.create(n, -1)
	local thick = table.create(n, 0)
	local size = board.cs * GAP
	local model = Instance.new("Folder")
	model.Name = "Cells"
	for c = 0, n - 1 do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Color = Palette.neutral
		p.Material = Enum.Material.SmoothPlastic
		local t = BASE_H * board.cs
		p.Size = Vector3.new(size, size, t)
		thick[c + 1] = t
		p.CFrame = Board.cellCFrame(board, c, t / 2 / board.cs + 0.02)
		p.Parent = model
		parts[c + 1] = p
	end
	model.Parent = board.folder
	return {
		board = board,
		top = top,
		slots = slots,
		parts = parts,
		value = value,
		thick = thick,
		bounce = {},
		nbounce = 0,
		captured = 0,
	}
end

local function liftOf(self: Cells, c: number): number
	return self.thick[c + 1] / 2 / self.board.cs + 0.02
end

-- Applies a decoded cell value. `animate`: bounce when the owner changed.
function Cells.set(self: Cells, c: number, v: number, animate: boolean)
	local old = self.value[c + 1]
	if old == v then
		return
	end
	self.value[c + 1] = v
	local p = self.parts[c + 1]
	if not p then
		return
	end
	local owner, layer, fade = Geo.decodeCell(v, self.top)
	local oldOwner = if old >= 0 then Geo.decodeCell(old, self.top) else -1
	local look = if layer then Palette.layer[layer] or Palette.plain else Palette.plain
	local base = Palette.neutral
	if owner >= 0 then
		local slot = self.slots[owner]
		base = if slot then Palette.owner[slot] else Palette.unknownOwner
		base = base:Lerp(Palette.neutral, fade / 9 * 0.65)
	end
	p.Color = if layer then base:Lerp(look.color, look.mix) else base
	if p.Material ~= look.material then
		p.Material = look.material
	end
	local t = (BASE_H + look.h) * self.board.cs
	if math.abs(self.thick[c + 1] - t) > 1e-4 then
		self.thick[c + 1] = t
		local s = self.board.cs * GAP
		p.Size = Vector3.new(s, s, t)
		p.CFrame = Board.cellCFrame(self.board, c, liftOf(self, c))
	end
	if animate and owner >= 0 and owner ~= oldOwner then
		self.captured += 1
		if self.bounce[c] == nil and self.nbounce < MAX_BOUNCE then
			self.bounce[c] = BOUNCE_T
			self.nbounce += 1
		end
	end
end

-- Owner changes since the last call, for the capture sound.
function Cells.takeCaptured(self: Cells): number
	local n = self.captured
	self.captured = 0
	return n
end

function Cells.update(self: Cells, dt: number)
	if self.nbounce == 0 then
		return
	end
	for c, left in self.bounce do
		left -= dt
		local p = self.parts[c + 1]
		if left <= 0 then
			self.bounce[c] = nil
			self.nbounce -= 1
			p.CFrame = Board.cellCFrame(self.board, c, liftOf(self, c))
		else
			self.bounce[c] = left
			local k = left / BOUNCE_T
			local up = math.sin((1 - k) * math.pi) * BOUNCE_H
			p.CFrame = Board.cellCFrame(self.board, c, liftOf(self, c) + up)
		end
	end
end

return Cells
