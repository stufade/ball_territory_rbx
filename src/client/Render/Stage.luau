--!strict
-- Arena stage around the board: stand glows in the seat's ball colour, a local dummy avatar on every bot stand, and
-- avatar reactions (round/match won: cheer; lost: head down). Everything is local to this client.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Look = require(ReplicatedStorage.Shared.Look)
local Net = require(ReplicatedStorage.Shared.Net)
local Board = require(script.Parent.Board)

local NEON = Color3.fromHex("#36d6ff")
-- Roblox default emotes (R15 / R6 cheer) and R15 idle; owned by Roblox, playable in any experience.
local CHEER_R15 = "rbxassetid://507770677"
local CHEER_R6 = "rbxassetid://129423030"
local IDLE_R15 = "rbxassetid://507766388"
local IDLE_R6 = "rbxassetid://180435571"

export type Stage = {
	board: Board.Board,
	seats: { Net.Seat },
	dummies: { [number]: Model }, -- by side
	glows: { [number]: BasePart },
	tracks: { AnimationTrack },
	sagged: { [Motor6D]: CFrame },
	-- own avatar on its stand: the Roblox Animate script is off for the match (F1: it kept the plaza run playing
	-- on the anchored avatar, running in place); our looped idle plays instead
	still: LocalScript?,
	dead: boolean,
}

local Stage = {}

local function standOf(board: Board.Board, side: number): BasePart?
	local s = board.model:FindFirstChild(`Stand{side + 1}`)
	return if s and s:IsA("BasePart") then s else nil
end

local function dummy(stand: BasePart, name: string): Model?
	local d = Instance.new("HumanoidDescription")
	-- blocky bot colours
	d.HeadColor = Color3.fromRGB(245, 205, 48)
	d.LeftArmColor = d.HeadColor
	d.RightArmColor = d.HeadColor
	d.TorsoColor = Color3.fromRGB(13, 105, 172)
	d.LeftLegColor = Color3.fromRGB(40, 127, 71)
	d.RightLegColor = d.LeftLegColor
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if not ok or not m then
		return nil
	end
	m.Name = name
	local hum = m:FindFirstChildOfClass("Humanoid")
	local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp then
		m:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	hrp.Anchored = true
	local top = stand.Position.Y + stand.Size.Y / 2
	local pos = Vector3.new(stand.Position.X, top + hum.HipHeight + hrp.Size.Y / 2, stand.Position.Z)
	m:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
	return m
end

local function animator(model: Model): (Animator?, Humanoid?)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return nil, nil
	end
	local a = hum:FindFirstChildOfClass("Animator")
	if a then
		return a, hum
	end
	local n = Instance.new("Animator")
	n.Parent = hum
	return n, hum
end

local function play(self: Stage, model: Model, id: string, looped: boolean, priority: Enum.AnimationPriority)
	local a = animator(model)
	if not a then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return a:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = looped
		track.Priority = priority
		track:Play(0.15)
		table.insert(self.tracks, track)
	end
end

-- Character of a seat: the person's avatar (placed on the stand by the server) or our bot dummy.
local function character(self: Stage, seat: Net.Seat): Model?
	if seat.userId > 0 then
		local p = Players:GetPlayerByUserId(seat.userId)
		return p and p.Character
	end
	return self.dummies[seat.side]
end

-- Own avatar stands idle on its stand: Animate off, its movement tracks stopped, a looped idle of our own.
local function standStill(self: Stage)
	local ch = Players.LocalPlayer.Character
	local animate = ch and ch:FindFirstChild("Animate")
	local a, hum = animator(ch :: Model)
	if not (ch and a and hum) then
		return
	end
	if animate and animate:IsA("LocalScript") and animate.Enabled then
		animate.Enabled = false
		self.still = animate
	end
	for _, t in a:GetPlayingAnimationTracks() do
		t:Stop(0.2)
	end
	play(
		self,
		ch,
		if hum.RigType == Enum.HumanoidRigType.R6 then IDLE_R6 else IDLE_R15,
		true,
		Enum.AnimationPriority.Idle
	)
end

function Stage.new(board: Board.Board, data: Net.MatchStart): Stage
	local self: Stage = {
		board = board,
		seats = data.seats,
		dummies = {},
		glows = {},
		tracks = {},
		sagged = {},
		still = nil,
		dead = false,
	}
	for _, seat in data.seats do
		local g = board.model:FindFirstChild(`Glow{seat.side + 1}`)
		if g and g:IsA("BasePart") then
			self.glows[seat.side] = g
		end
		local stand = standOf(board, seat.side)
		if seat.userId <= 0 and stand then
			-- building the rig loads assets and yields: never hold up the match session for it
			task.spawn(function()
				local m = dummy(stand, seat.name)
				if not m then
					return
				end
				if self.dead then
					m:Destroy()
					return
				end
				m.Parent = board.folder
				self.dummies[seat.side] = m
				play(self, m, IDLE_R15, true, Enum.AnimationPriority.Idle)
			end)
		end
	end
	Stage.setSeats(self, data.seats)
	if data.you ~= nil and data.view ~= true then
		standStill(self)
	end
	return self
end

-- New round: seats carry the balls of this round.
function Stage.setSeats(self: Stage, seats: { Net.Seat })
	self.seats = seats
	for _, seat in seats do
		local g = self.glows[seat.side]
		if g then
			g.Color = Look.bright(seat.e)
		end
	end
	Stage.calm(self)
end

local function sag(self: Stage, model: Model)
	local head = model:FindFirstChild("Head")
	local upper = model:FindFirstChild("UpperTorso")
	local list: { { motor: Motor6D, rot: CFrame } } = {}
	local neck = head and head:FindFirstChild("Neck")
	local waist = upper and upper:FindFirstChild("Waist")
	if neck and neck:IsA("Motor6D") then
		table.insert(list, { motor = neck, rot = CFrame.Angles(math.rad(-30), 0, 0) })
	end
	if waist and waist:IsA("Motor6D") then
		table.insert(list, { motor = waist, rot = CFrame.Angles(math.rad(-14), 0, 0) })
	end
	local torso = model:FindFirstChild("Torso")
	local r6neck = torso and torso:FindFirstChild("Neck")
	if r6neck and r6neck:IsA("Motor6D") then
		table.insert(list, { motor = r6neck, rot = CFrame.Angles(math.rad(25), 0, 0) })
	end
	for _, m in list do
		local motor, rot = m.motor, m.rot
		if not self.sagged[motor] then
			self.sagged[motor] = motor.C0
		end
		TweenService:Create(motor, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { C0 = self.sagged[motor] * rot }):Play()
	end
end

-- Winners cheer, the others hang their heads (a draw: nobody wins).
function Stage.react(self: Stage, isWinner: (Net.Seat) -> boolean)
	for _, seat in self.seats do
		local ch = character(self, seat)
		if ch then
			if isWinner(seat) then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				local r6 = hum and hum.RigType == Enum.HumanoidRigType.R6
				play(self, ch, if r6 then CHEER_R6 else CHEER_R15, false, Enum.AnimationPriority.Action)
			else
				sag(self, ch)
			end
		end
	end
end

-- Back to the neutral pose (next round).
function Stage.calm(self: Stage)
	for motor, c0 in self.sagged do
		if motor.Parent then
			TweenService:Create(motor, TweenInfo.new(0.3), { C0 = c0 }):Play()
		end
	end
	table.clear(self.sagged)
	for i = #self.tracks, 1, -1 do
		local t = self.tracks[i]
		if t.Priority == Enum.AnimationPriority.Action then
			t:Stop(0.2)
			table.remove(self.tracks, i)
		end
	end
end

function Stage.destroy(self: Stage)
	self.dead = true
	for motor, c0 in self.sagged do
		if motor.Parent then
			motor.C0 = c0
		end
	end
	table.clear(self.sagged)
	for _, t in self.tracks do
		t:Stop(0)
	end
	local animate = self.still
	if animate and animate.Parent then
		animate.Enabled = true
	end
	self.still = nil
	for _, g in self.glows do
		g.Color = NEON
	end
	for _, m in self.dummies do
		m:Destroy()
	end
end

return Stage
