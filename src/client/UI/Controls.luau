--!strict
-- Roblox's own controls vs ours. The touch STICK / JUMP sit over the power button, the draft and the windows, and
-- the Roblox player list sits over the window close buttons. So the character is only controllable on the plaza
-- with no window open, and the player list hides while a window is open. Both only act on a change.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Controls = {}

local walkable: boolean? = nil
local listShown: boolean? = nil
local module: any = nil
local loading = false

local function withModule(fn: (any) -> ())
	if module then
		fn(module)
		return
	end
	if loading then
		return
	end
	loading = true
	task.spawn(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
		local ok, m = pcall(function()
			return require(scripts:WaitForChild("PlayerModule") :: ModuleScript)
		end)
		loading = false
		if ok then
			module = m
			-- the state may have changed while the module loaded
			if walkable ~= nil then
				local want = walkable
				walkable = nil
				Controls.walk(want)
			end
		end
	end)
end

-- Character movement (keyboard, stick, jump button) on or off.
function Controls.walk(on: boolean)
	if walkable == on then
		return
	end
	walkable = on
	GuiService.TouchControlsEnabled = on
	withModule(function(m)
		local c = m:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

function Controls.playerList(on: boolean)
	if listShown == on then
		return
	end
	listShown = on
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, on)
	end)
end

-- plaza: the player stands on the plaza (lobby or queue); window: a shop / reward / book / quests window is open.
function Controls.update(plaza: boolean, window: boolean)
	Controls.walk(plaza and not window)
	Controls.playerList(not window)
end

return Controls
