--!strict
-- Match camera: Scriptable at arena.Camera, FOV widened so the whole board fits, shake on powers and reactions.
local RunService = game:GetService("RunService")

local Board = require(script.Parent.Board)
local Geo = require(script.Parent.Geo)

local BASE_FOV = 70
local MARGIN = 1.12
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

local function fit(self: Cam)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local b = self.board
	local look = self.base.LookVector
	local dist = math.max(1, (b.origin.Position - self.base.Position):Dot(look))
	local size = cam.ViewportSize
	local aspect = size.X / math.max(1, size.Y)
	cam.FieldOfView = Geo.fitFov(b.gw * b.cs / 2, b.gh * b.cs / 2, dist, aspect, MARGIN, BASE_FOV)
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
	self.sizeConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
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
		cam.CameraType = if self.saved.type == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else self.saved.type
		cam.FieldOfView = self.saved.fov
	end
end

return Cam
