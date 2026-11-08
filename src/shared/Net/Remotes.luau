--!strict
-- Remote instances of docs/net.md. The server creates ReplicatedStorage.Remotes, clients wait for it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require("../Net")

local IS_SERVER = RunService:IsServer()

local folder: Instance
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild(Net.FOLDER) or Instance.new("Folder")
	folder.Name = Net.FOLDER
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(Net.FOLDER)
end

local function get(className: string, name: string): any
	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing
		end
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

return {
	Snap = get("UnreliableRemoteEvent", Net.Remote.Snap) :: UnreliableRemoteEvent,
	Match = get("RemoteEvent", Net.Remote.Match) :: RemoteEvent,
	State = get("RemoteEvent", Net.Remote.State) :: RemoteEvent,
	Input = get("RemoteEvent", Net.Remote.Input) :: RemoteEvent,
	Action = get("RemoteEvent", Net.Remote.Action) :: RemoteEvent,
}
