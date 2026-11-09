--!strict
-- Signs over the arena boards on the plaza: the mode and who plays whom (arena attribute "Live" set by the server),
-- or "FREE ARENA". Hidden while the local player is in an own match (the match camera frames the board).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage.Shared.Look)

local Signs = {}

local GOLD = Color3.fromHex("#ffd63c")
local LIVE = Color3.fromHex("#ff4f6a")
local signs: { [Model]: BillboardGui } = {}
local hidden = false

local function label(parent: Instance, name: string, y: number, h: number, color: Color3, font: Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, h)
	t.Position = UDim2.fromScale(0, y)
	t.TextScaled = true
	t.FontFace = font
	t.TextColor3 = color
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Look.INK
	s.Parent = t
	t.Parent = parent
	return t
end

local function refresh(model: Model, gui: BillboardGui)
	local live = model:GetAttribute("Live")
	local top = gui:FindFirstChild("Top") :: TextLabel?
	local who = gui:FindFirstChild("Who") :: TextLabel?
	local mode = if model:GetAttribute("Mode") == "ffa" then "4 PLAYERS" else "DUEL"
	if top and who then
		if type(live) == "string" and live ~= "" then
			top.Text = `● LIVE · {mode}`
			top.TextColor3 = LIVE
			who.Text = string.upper(live)
		else
			top.Text = mode
			top.TextColor3 = GOLD
			who.Text = "FREE ARENA"
		end
	end
end

local function add(inst: Instance)
	if not inst:IsA("Model") or signs[inst] then
		return
	end
	local board = inst:WaitForChild("Board", 10)
	if not board or not board:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BTSign"
	gui.Adornee = board
	gui.Size = UDim2.fromScale(30, 5.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, board.Size.Y / 2 + 4, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.ResetOnSpawn = false
	gui.Enabled = not hidden
	label(gui, "Top", 0, 0.42, GOLD, Look.FONT)
	label(gui, "Who", 0.45, 0.55, Color3.new(1, 1, 1), Look.FONT)
	signs[inst] = gui
	refresh(inst, gui)
	inst:GetAttributeChangedSignal("Live"):Connect(function()
		refresh(inst, gui)
	end)
	gui.Parent = board
end

-- true while the local player plays a match: signs off.
function Signs.inMatch(on: boolean)
	hidden = on
	for _, gui in signs do
		gui.Enabled = not on
	end
end

function Signs.start()
	for _, inst in CollectionService:GetTagged("Arena") do
		task.spawn(add, inst)
	end
	CollectionService:GetInstanceAddedSignal("Arena"):Connect(function(inst)
		task.spawn(add, inst)
	end)
	CollectionService:GetInstanceRemovedSignal("Arena"):Connect(function(inst)
		local gui = signs[inst :: Model]
		if gui then
			gui:Destroy()
			signs[inst :: Model] = nil
		end
	end)
end

return Signs
