--!strict
-- Arena of the running match: attributes, Origin and world conversion (docs/scene.md).
local CollectionService = game:GetService("CollectionService")

local Geo = require(script.Parent.Geo)

export type Board = {
	model: Model,
	origin: CFrame,
	camera: BasePart?,
	cs: number,
	gw: number,
	gh: number,
	ox: number, -- field offset from Match "start"
	oy: number,
	folder: Folder,
}

local Board = {}

function Board.find(name: string): Model?
	for _, m in CollectionService:GetTagged("Arena") do
		if m.Name == name and m:IsA("Model") then
			return m
		end
	end
	return nil
end

-- Waits a few seconds for streaming; nil if the arena or its Origin never appears.
function Board.open(name: string, ox: number, oy: number, w: number, h: number): Board?
	local deadline = os.clock() + 5
	local model = Board.find(name)
	while not model and os.clock() < deadline do
		task.wait(0.2)
		model = Board.find(name)
	end
	if not model then
		return nil
	end
	local board = model:WaitForChild("Board", 5)
	local originAtt = board and board:WaitForChild("Origin", 5)
	if not (originAtt and originAtt:IsA("Attachment")) then
		return nil
	end
	local cs = model:GetAttribute("CellSize")
	local folder = Instance.new("Folder")
	folder.Name = "BTRender"
	folder.Parent = workspace
	local cam = model:FindFirstChild("Camera")
	return {
		model = model,
		origin = originAtt.WorldCFrame,
		camera = if cam and cam:IsA("BasePart") then cam else nil,
		cs = if type(cs) == "number" then cs else 1.25,
		gw = w,
		gh = h,
		ox = ox,
		oy = oy,
		folder = folder,
	}
end

function Board.close(b: Board)
	b.folder:Destroy()
end

-- Field coordinates (cells, fractional) and lift towards the camera (in cells) to a world CFrame.
function Board.cframe(b: Board, x: number, y: number, lift: number): CFrame
	local lx, ly = Geo.fieldToLocal(x, y, b.ox, b.oy, b.cs)
	return b.origin * CFrame.new(lx, ly, lift * b.cs)
end

function Board.cellCFrame(b: Board, c: number, lift: number): CFrame
	local i, j = c % b.gw, c // b.gw
	local lx, ly, lz = Geo.cellCenter(i, j, b.cs, lift)
	return b.origin * CFrame.new(lx, ly, lz)
end

return Board
