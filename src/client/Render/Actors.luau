--!strict
-- Balls, spikes, HP labels, clones, bombs, bubbles and black holes, drawn from interpolated snapshots.
local Board = require(script.Parent.Board)
local Geo = require(script.Parent.Geo)
local Palette = require(script.Parent.Palette)

local BALL_R = 0.85 -- cells, Config.P.ballR
local ORBIT_R = 2 -- Config.P.orbitR
local HEAD_R = 0.6 -- Config.P.headR
local SNAP_JUMP = 3 -- cells: a longer step is a teleport, not interpolated
local MAX_THINGS = 40

local F_BIG, F_INVULN, F_PHASE, F_STUN = 2, 4, 16, 1

type BallView = {
	sphere: Part,
	spikes: { Part },
	label: TextLabel,
	arrow: Part,
	neon: boolean,
	hp: number,
	shown: boolean,
}

export type Actors = {
	board: Board.Board,
	slots: { [number]: number },
	you: number?,
	balls: { [number]: BallView },
	clones: { Part },
	bombs: { Part },
	bubbles: { Part },
	holes: { [number]: Part },
	root: Folder,
}

local Actors = {}

local function part(shape: Enum.PartType, parent: Instance): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function newBall(self: Actors, e: number): BallView
	local slot = self.slots[e]
	local s = part(Enum.PartType.Ball, self.root)
	s.Name = "Ball" .. e
	s.Color = Palette.elementColor(e)
	local spikes = {}
	for i = 1, 2 do
		local sp = part(Enum.PartType.Ball, self.root)
		sp.Color = Color3.fromRGB(235, 235, 240)
		sp.Material = Enum.Material.Metal
		sp.Name = "Spike" .. e .. "_" .. i
		spikes[i] = sp
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(64, 32)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = s
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = if slot then Palette.owner[slot] else Color3.new(0, 0, 0)
	l.Parent = gui
	gui.Parent = s
	local arrow = part(Enum.PartType.Block, self.root)
	arrow.Name = "Arrow" .. e
	arrow.Material = Enum.Material.Neon
	arrow.Color = if slot then Palette.owner[slot] else Color3.new(1, 1, 1)
	arrow.Transparency = 0.25
	return { sphere = s, spikes = spikes, label = l, arrow = arrow, neon = false, hp = -1, shown = true }
end

function Actors.new(board: Board.Board, slots: { [number]: number }, you: number?): Actors
	local root = Instance.new("Folder")
	root.Name = "Actors"
	root.Parent = board.folder
	return {
		board = board,
		slots = slots,
		you = you,
		balls = {},
		clones = {},
		bombs = {},
		bubbles = {},
		holes = {},
		root = root,
	}
end

local function setShown(v: BallView, on: boolean)
	if v.shown == on then
		return
	end
	v.shown = on
	local off = CFrame.new(0, -10000, 0)
	if not on then
		v.sphere.CFrame, v.arrow.CFrame = off, off
		v.spikes[1].CFrame, v.spikes[2].CFrame = off, off
	end
	v.label.Visible = on
end

-- Position of ball e on the interpolated frame, in field cells (for the tap direction).
function Actors.ballPos(self: Actors, e: number): (number?, number?)
	local v = self.balls[e]
	if not v or not v.shown then
		return nil, nil
	end
	local o = self.board.origin:PointToObjectSpace(v.sphere.Position)
	return Geo.localToField(o.X, o.Y, self.board.ox, self.board.oy, self.board.cs)
end

local function lerpBall(a: any, b: any, t: number): (number, number, number)
	if Geo.dist2(a.x, a.y, b.x, b.y) > SNAP_JUMP then
		return b.x, b.y, b.ang
	end
	return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, Geo.angleLerp(a.ang, b.ang, t)
end

local function updateBall(self: Actors, e: number, a: any, b: any, t: number)
	local v = self.balls[e]
	if not v then
		v = newBall(self, e)
		self.balls[e] = v
	end
	if not b.alive then
		setShown(v, false)
		return
	end
	v.shown = true
	v.label.Visible = true
	local bd = self.board
	local x, y, ang = lerpBall(a, b, t)
	local r = BALL_R * bd.cs * (if bit32.btest(b.flags, F_BIG) then 1.5 else 1)
	local transp = if bit32.btest(b.flags, F_PHASE) then 0.6 elseif bit32.btest(b.flags, F_INVULN) then 0.35 else 0
	v.sphere.Size = Vector3.new(r * 2, r * 2, r * 2)
	v.sphere.Transparency = transp
	v.sphere.CFrame = Board.cframe(bd, x, y, BALL_R)
	v.sphere.Color = if bit32.btest(b.flags, F_STUN)
		then Palette.elementColor(e):Lerp(Color3.new(0.3, 0.3, 0.3), 0.6)
		else Palette.elementColor(e)
	local neon = b.charge >= 1
	if neon ~= v.neon then
		v.neon = neon
		v.sphere.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if v.hp ~= b.hp then
		v.hp = b.hp
		v.label.Text = tostring(b.hp)
	end
	for i, sp in v.spikes do
		local an = ang + (i - 1) * math.pi
		local sx, sy = x + math.cos(an) * ORBIT_R, y + math.sin(an) * ORBIT_R
		local hr = HEAD_R * bd.cs * 2
		sp.Size = Vector3.new(hr, hr, hr)
		sp.CFrame = Board.cframe(bd, sx, sy, BALL_R)
		sp.Transparency = transp
	end
	-- Own aim arrow: from the ball along its heading.
	if e == self.you then
		local len = 2.2 * bd.cs
		local dx, dy = b.dx, b.dy
		local m = math.sqrt(dx * dx + dy * dy)
		if m > 0.05 then
			dx, dy = dx / m, dy / m
			local cx, cy = x + dx * (BALL_R + 1.1), y + dy * (BALL_R + 1.1)
			v.arrow.Size = Vector3.new(0.18 * bd.cs, len, 0.1 * bd.cs)
			v.arrow.CFrame = Board.cframe(bd, cx, cy, BALL_R * 0.5)
				* CFrame.Angles(0, 0, math.atan2(-dy, dx) - math.pi / 2)
			v.arrow.Transparency = 0.25
		else
			v.arrow.Transparency = 1
		end
	else
		v.arrow.Transparency = 1
	end
end

local function things(
	self: Actors,
	pool: { Part },
	la: { any },
	lb: { any },
	t: number,
	style: (Part, any, number) -> ()
)
	local n = math.min(#lb, MAX_THINGS)
	for i = 1, n do
		local p = pool[i]
		if not p then
			p = part(Enum.PartType.Ball, self.root)
			pool[i] = p
		end
		local b = lb[i]
		local a = la[i]
		local x, y = b[1], b[2]
		if a and Geo.dist2(a[1], a[2], b[1], b[2]) < SNAP_JUMP then
			x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
		end
		p.CFrame = Board.cframe(self.board, x, y, 0.5)
		style(p, b, os.clock())
	end
	for i = n + 1, #pool do
		pool[i].CFrame = CFrame.new(0, -10000, 0)
	end
end

local function styleClone(self: Actors): (Part, any, number) -> ()
	return function(p, b)
		local s = BALL_R * self.board.cs * 1.4
		p.Size = Vector3.new(s, s, s)
		p.Color = Palette.elementColor(b[3])
		p.Transparency = 0.4
	end
end

local function newHole(self: Actors, e: number): Part
	local h = part(Enum.PartType.Ball, self.root)
	h.Color = Color3.fromRGB(15, 5, 30)
	h.Name = "Hole" .. e
	self.holes[e] = h
	return h
end

function Actors.update(self: Actors, a: any, b: any, t: number)
	local seen: { [number]: boolean } = {}
	local prev: { [number]: any } = {}
	for _, ba in a.balls do
		prev[ba.e] = ba
	end
	for _, bb in b.balls do
		seen[bb.e] = true
		updateBall(self, bb.e, prev[bb.e] or bb, bb, t)
		local hole: Part? = self.holes[bb.e]
		if bb.hole > 0 and bb.alive then
			local h = hole or newHole(self, bb.e)
			local s = self.board.cs * (1.5 + math.sin(os.clock() * 8) * 0.15)
			h.Size = Vector3.new(s, s, s * 0.4)
			h.CFrame = Board.cframe(self.board, bb.hx, bb.hy, 0.35)
		elseif hole then
			hole.CFrame = CFrame.new(0, -10000, 0)
		end
	end
	for e, v in self.balls do
		if not seen[e] then
			setShown(v, false)
		end
	end
	things(self, self.clones, a.clones, b.clones, t, styleClone(self))
	things(self, self.bombs, a.bombs, b.bombs, t, function(p, q, now)
		local s = self.board.cs * (0.9 + 0.25 * math.sin(now * (6 + 14 / math.max(0.2, q[3]))))
		p.Size = Vector3.new(s, s, s)
		p.Color = Color3.fromRGB(60, 60, 70):Lerp(Color3.fromRGB(255, 60, 40), if q[3] < 0.8 then 0.8 else 0.2)
		p.Transparency = 0
	end)
	things(self, self.bubbles, a.bubbles, b.bubbles, t, function(p, q)
		local s = self.board.cs * 1.7
		p.Size = Vector3.new(s, s, s)
		p.Color = Palette.elementColor(q[3])
		p.Transparency = 0.55
	end)
end

function Actors.destroy(self: Actors)
	self.root:Destroy()
end

return Actors
