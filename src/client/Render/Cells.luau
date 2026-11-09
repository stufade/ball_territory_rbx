--!strict
-- Field cells on the board canvas, as the web drawCell: element colour of the owner on a checker, dark navy when
-- free, terrain tile of the top layer from the web atlas (animated ones loop), fading cells pulse, captured cells
-- flash white. Instances are made once per session; only changed cells are touched.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Art = require(ReplicatedStorage.Shared.Art)
local Look = require(ReplicatedStorage.Shared.Look)
local Field = require(script.Parent.Field)
local Geo = require(script.Parent.Geo)
local Gui = require(script.Parent.Gui)

local FREE = { Color3.fromHex("#2e325c"), Color3.fromHex("#282c50") } -- by chk 0/1
local FREE_IN = { Color3.fromHex("#33386a"), Color3.fromHex("#2b2f55") }
local FADE = Color3.fromRGB(70, 74, 120)
local WHITE = Color3.new(1, 1, 1)

type View = { base: Frame, inner: Frame, tile: ImageLabel, over: Frame }

export type Cells = {
	field: Field.Field,
	top: { string },
	row: { [string]: number },
	views: { View },
	value: { number },
	anim: { [number]: string }, -- cell -> animated layer
	fade: { [number]: number }, -- cell -> fade 1-9
	flash: { [number]: number }, -- cell -> 0-1
	frameOf: { [number]: number },
	layerOf: { [number]: string }, -- cell -> top layer
	captured: number,
}

local Cells = {}

function Cells.new(field: Field.Field, top: { string }): Cells
	local C = Gui.CELL
	local gw, gh = field.board.gw, field.board.gh
	local views = table.create(gw * gh)
	local row = {}
	for i, n in top do
		row[n] = i
	end
	for c = 0, gw * gh - 1 do
		local i, j = c % gw, c // gw
		local chk = (i + j) % 2
		local base = Instance.new("Frame")
		base.BorderSizePixel = 0
		base.Position = UDim2.fromOffset(i * C, j * C)
		base.Size = UDim2.fromOffset(C, C)
		base.BackgroundColor3 = FREE[chk + 1]
		local inner = Instance.new("Frame")
		inner.BorderSizePixel = 0
		inner.Position = UDim2.fromOffset(2, 2)
		inner.Size = UDim2.fromOffset(C - 4, C - 4)
		inner.BackgroundColor3 = FREE_IN[chk + 1]
		inner.Parent = base
		local tile = Instance.new("ImageLabel")
		tile.BackgroundTransparency = 1
		tile.Position = UDim2.fromOffset(3, 3)
		tile.Size = UDim2.fromOffset(C - 6, C - 6)
		tile.Image = Art.TERRAIN
		tile.ImageRectSize = Vector2.new(Art.TILE, Art.TILE)
		tile.Visible = false
		tile.Parent = base
		local over = Instance.new("Frame")
		over.BorderSizePixel = 0
		over.Size = UDim2.fromScale(1, 1)
		over.BackgroundTransparency = 1
		over.Parent = base
		base.Parent = field.cells
		views[c + 1] = { base = base, inner = inner, tile = tile, over = over }
	end
	return {
		field = field,
		top = top,
		row = row,
		views = views,
		value = table.create(gw * gh, -1),
		anim = {},
		fade = {},
		flash = {},
		frameOf = {},
		layerOf = {},
		captured = 0,
	}
end

-- Applies a decoded cell value. `animate`: flash when the owner changed.
function Cells.set(self: Cells, c: number, v: number, animate: boolean)
	local old = self.value[c + 1]
	if old == v then
		return
	end
	self.value[c + 1] = v
	local view = self.views[c + 1]
	if not view then
		return
	end
	local gw = self.field.board.gw
	local chk = (c % gw + c // gw) % 2
	local owner, layer, fade = Geo.decodeCell(v, self.top)
	local oldOwner = if old >= 0 then Geo.decodeCell(old, self.top) else -1
	if owner ~= oldOwner or old < 0 then
		if owner >= 0 then
			view.base.BackgroundColor3 = Look.cell(owner, chk)
			view.inner.BackgroundColor3 = if chk == 1 then Color3.new(0, 0, 0) else WHITE
			view.inner.BackgroundTransparency = if chk == 1 then 0.95 else 0.9
		else
			view.base.BackgroundColor3 = FREE[chk + 1]
			view.inner.BackgroundColor3 = FREE_IN[chk + 1]
			view.inner.BackgroundTransparency = 0
		end
		if animate and owner >= 0 then
			self.captured += 1
			self.flash[c] = 1
		end
	end
	self.layerOf[c] = layer :: any
	local r = if layer then self.row[layer] else nil
	if r and layer then
		view.tile.Visible = true
		if Art.PERIOD[layer] then
			self.anim[c] = layer
			self.frameOf[c] = -1
		else
			self.anim[c] = nil
			view.tile.ImageRectOffset = Art.tileRect(r, chk, 0)
		end
	else
		view.tile.Visible = false
		self.anim[c] = nil
	end
	self.fade[c] = if fade > 0 then fade else nil :: any
	if fade == 0 and not self.flash[c] then
		view.over.BackgroundTransparency = 1
	end
end

function Cells.takeCaptured(self: Cells): number
	local n = self.captured
	self.captured = 0
	return n
end

function Cells.update(self: Cells, dt: number, now: number)
	local gw = self.field.board.gw
	for c, layer in self.anim do
		local period = Art.PERIOD[layer]
		local f = math.floor((now / period + (c * 0.618) % 1) * Art.FRAMES) % Art.FRAMES
		if self.frameOf[c] ~= f then
			self.frameOf[c] = f
			local view = self.views[c + 1]
			view.tile.ImageRectOffset = Art.tileRect(self.row[layer], (c % gw + c // gw) % 2, f)
		end
	end
	local decay = 0.74 ^ (dt * 30)
	for c, k in self.flash do
		k *= decay
		local view = self.views[c + 1]
		if k <= 0.04 then
			self.flash[c] = nil
			view.over.BackgroundTransparency = 1
		else
			self.flash[c] = k
			view.over.BackgroundColor3 = WHITE
			view.over.BackgroundTransparency = 1 - k * 0.55
		end
	end
	local pulse = 0.72 + 0.14 * math.sin(now * 12)
	for c, f in self.fade do
		if not self.flash[c] then
			local view = self.views[c + 1]
			view.over.BackgroundColor3 = FADE
			view.over.BackgroundTransparency = 1 - math.min(1, f / 9) * pulse
		end
	end
end

return Cells
