--!strict
-- Avatars stand still on their arena's Stand during a session, then run on the lobby plaza (faster than default).
local Config = require("./Config")

local Avatars = {}

local function root(player: Player): (BasePart?, Humanoid?)
	local ch = player.Character
	if not ch then
		return nil, nil
	end
	return ch:FindFirstChild("HumanoidRootPart") :: BasePart?, ch:FindFirstChildOfClass("Humanoid")
end

local function standHeight(hrp: BasePart, hum: Humanoid?): number
	return (if hum then hum.HipHeight else 2) + hrp.Size.Y / 2
end

-- Stands face the camera (+Z, docs/scene.md).
function Avatars.place(player: Player, stand: BasePart?)
	local hrp, hum = root(player)
	if not hrp or not stand then
		return
	end
	local pos = stand.Position + Vector3.new(0, stand.Size.Y / 2 + standHeight(hrp, hum), 0)
	hrp.Anchored = true
	local ch = player.Character :: Model
	ch:PivotTo(CFrame.lookAt(pos, pos + Vector3.zAxis))
	if hum then
		hum:Move(Vector3.zero)
	end
end

-- A spot on the lobby plaza near the spawn (scene: Workspace.Lobby.Spawn, else Lobby.Pad).
local function lobbySpot(): Vector3?
	local lobby = workspace:FindFirstChild("Lobby")
	local at = lobby and (lobby:FindFirstChild("Spawn") or lobby:FindFirstChild("Pad"))
	if at and at:IsA("BasePart") then
		return at.Position + Vector3.new(math.random(-6, 6), at.Size.Y / 2, math.random(-4, 4))
	end
	return nil
end

-- Plaza walk speed (faster than the Roblox default).
function Avatars.walk(player: Player)
	local _, hum = root(player)
	if hum then
		hum.WalkSpeed = Config.LOBBY_WALK
	end
end

-- After a match: free to run on the plaza again.
function Avatars.release(player: Player)
	local hrp, hum = root(player)
	if not hrp then
		return
	end
	hrp.Anchored = false
	local spot = lobbySpot()
	if spot then
		local ch = player.Character :: Model
		ch:PivotTo(CFrame.new(spot + Vector3.new(0, standHeight(hrp, hum), 0)))
	end
	Avatars.walk(player)
end

-- New character outside a match: plaza speed; a spawn off the plaza (old SpawnLocation) is moved onto it.
function Avatars.spawned(player: Player)
	local hrp = root(player)
	local lobby = workspace:FindFirstChild("Lobby")
	local spawn = lobby and lobby:FindFirstChild("Spawn")
	if hrp and spawn and spawn:IsA("BasePart") and (hrp.Position - spawn.Position).Magnitude > 120 then
		Avatars.release(player)
	else
		Avatars.walk(player)
	end
end

-- Characters respawn on the plaza spawn of the scene.
function Avatars.home(player: Player)
	local lobby = workspace:FindFirstChild("Lobby")
	local spawn = lobby and lobby:FindFirstChild("Spawn")
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
end

return Avatars
