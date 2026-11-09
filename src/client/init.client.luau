--!strict
print("[BT] client boot")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Render = require(script:WaitForChild("Render"))

Render.start()

-- UI belongs to another module; boot without it if it is absent or broken.
local uiModule = script:FindFirstChild("UI")
if uiModule and uiModule:IsA("ModuleScript") then
	local ok, ui = pcall(require, uiModule)
	if ok and type(ui) == "table" and type((ui :: any).start) == "function" then
		local started, err = pcall((ui :: any).start)
		if not started then
			warn("[BT] UI start failed: " .. tostring(err))
		end
	elseif not ok then
		warn("[BT] UI failed to load: " .. tostring(ui))
	end
end

-- Render and UI listen now: the server repeats the current State and starts the first-ball timer.
Remotes.Action:FireServer(Net.Action.hello)
