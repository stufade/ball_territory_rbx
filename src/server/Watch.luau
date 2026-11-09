--!strict
-- Spectators on the lobby plaza: a person near a live arena gets its match (start, snapshots, events) as a viewer
-- and stops getting it on walking away. One arena per person, WATCH_MAX viewers per arena (traffic: docs/net.md).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arenas = require("./Arenas")
local Config = require("./Config")
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Roster = require("./Roster")
local Runner = require("./Runner")

local Watch = {}

local acc = 0

local function viewers(s: any): number
	local n = 0
	for _ in s.viewers do
		n += 1
	end
	return n
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Watch.stop(r: Roster.Rec)
	local s = r.watching
	if not s then
		return
	end
	s.viewers[r] = nil
	r.watching = nil
	if r.player.Parent then
		Remotes.Match:FireClient(r.player, Net.MatchKind.unview, { id = s.id })
	end
end

function Watch.start(r: Roster.Rec, s: any)
	if r.watching == s then
		return
	end
	Watch.stop(r)
	s.viewers[r] = true
	r.watching = s
	if s.runner then
		Runner.join(s.runner, r.player)
	end
end

local function position(r: Roster.Rec): Vector3?
	local ch = r.player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
end

-- Nearest live arena for a person at `pos`: the current one is kept up to WATCH_LEAVE.
function Watch.pick(pos: Vector3, current: any): any
	local best, bestD = nil, math.huge
	for _, a in Arenas.all() do
		local s = a.session
		if not s or s.closed then
			continue
		end
		local d = flat(pos, a.focus)
		if s == current and d <= Config.WATCH_LEAVE then
			-- a little stickiness so walking between two arenas does not flip every check
			d -= 8
		elseif d > Config.WATCH_ENTER or viewers(s) >= Config.WATCH_MAX then
			continue
		end
		if d < bestD then
			best, bestD = s, d
		end
	end
	return best
end

function Watch.tick(dt: number)
	acc += dt
	if acc < Config.WATCH_EVERY then
		return
	end
	acc = 0
	for _, r in Roster.all() do
		local cur = r.watching
		if cur and cur.closed then
			Watch.stop(r)
			cur = nil
		end
		local pos = position(r)
		if Roster.busy(r) or not pos or not r.readyAt then
			Watch.stop(r)
			continue
		end
		local s = Watch.pick(pos, cur)
		if s ~= cur then
			if s then
				Watch.start(r, s)
			else
				Watch.stop(r)
			end
		end
	end
end

return Watch
