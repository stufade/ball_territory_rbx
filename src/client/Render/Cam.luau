--!strict
-- Match camera: Scriptable at arena.Camera, FOV widened so the whole board fits, shake on powers and reactions.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Board = require(script.Parent.Board)
local Screen = require(script.Parent.Parent.Screen)

local MARGIN = 1.03
local BIND = "BTCamera"

export type Cam = {
	board: Board.Board,
	saved: { type: Enum.CameraType, fov: number, cf: CFrame },
	shake: number,
	base: CFrame,
	conn: RBXScriptConnection?,
	sizeConn: RBXScriptConnection?,
}

local Cam = {}

-- Board in the middle of the screen between the two side columns (Screen.COLUMN of the width: plates, avatars,
-- power button) and under the top strip (land bar, timer). The scene places the stands for this layout.
local function fit(self: Cam)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local b = self.board
	local home = (b.camera :: BasePart).CFrame
	local look = home.LookVector
	local dist = math.max(1, (b.origin.Position - home.Position):Dot(look))
	local _, size = Screen.band()
	local w, h = size.X, math.max(1, size.Y)
	local ui = math.min(w / Screen.DESIGN_W, h / Screen.DESIGN_H)
	local top, pad = Screen.TOP_STRIP * ui, 8 * ui
	local regionW = math.max(1, w * (1 - 2 * Screen.COLUMN))
	local regionH = math.max(1, h - top - pad)
	-- board with its rim and neon edges
	local hw, hh = (b.gw * b.cs + 1.5) / 2 + 1.2, (b.gh * b.cs + 1.5) / 2 + 1.2
	local f = math.min(regionW / (2 * hw), regionH / (2 * hh)) * dist / MARGIN
	local bandFov = math.deg(2 * math.atan(h / 2 / f))
	cam.FieldOfView = Screen.fovFor(bandFov)
	-- move the camera up so the board centres in the region under the top strip
	local down = (top + h - pad) / 2 - h / 2
	self.base = home * CFrame.new(0, down * dist / f, 0)
end

function Cam.start(board: Board.Board): Cam?
	local cam = workspace.CurrentCamera
	if not cam or not board.camera then
		return nil
	end
	local self: Cam = {
		board = board,
		saved = { type = cam.CameraType, fov = cam.FieldOfView, cf = cam.CFrame },
		shake = 0,
		base = board.camera.CFrame,
		conn = nil,
		sizeConn = nil,
	}
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = self.base
	fit(self)
	self.sizeConn = Screen.changed:Connect(function()
		fit(self)
	end)
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local c = workspace.CurrentCamera
		if not c then
			return
		end
		if c.CameraType ~= Enum.CameraType.Scriptable then
			c.CameraType = Enum.CameraType.Scriptable
		end
		local off = CFrame.identity
		if self.shake > 0.01 then
			local m = self.shake * 0.6
			off = CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
			self.shake *= math.exp(-dt * 7)
		else
			self.shake = 0
		end
		c.CFrame = self.base * off
	end)
	return self
end

function Cam.addShake(self: Cam, amount: number)
	self.shake = math.min(1, math.max(self.shake, amount))
end

function Cam.stop(self: Cam)
	RunService:UnbindFromRenderStep(BIND)
	if self.sizeConn then
		self.sizeConn:Disconnect()
	end
	local cam = workspace.CurrentCamera
	if cam then
		-- the first match can start before the character camera is set up (Fixed): always hand back a follow camera
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		local ch = Players.LocalPlayer.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
	end
end

return Cam
