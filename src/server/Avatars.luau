--!strict
-- Avatars stand still on their arena's Stand during a session, then go back to the lobby pad.
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

function Avatars.release(player: Player)
	local hrp, hum = root(player)
	if not hrp then
		return
	end
	hrp.Anchored = false
	local lobby = workspace:FindFirstChild("Lobby")
	local pad = lobby and lobby:FindFirstChild("Pad")
	if pad and pad:IsA("BasePart") then
		local off = Vector3.new(math.random(-3, 3), pad.Size.Y / 2 + standHeight(hrp, hum), math.random(-3, 3))
		local ch = player.Character :: Model
		ch:PivotTo(CFrame.new(pad.Position + off))
	end
end

return Avatars
