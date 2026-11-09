--!strict
-- Flag "tutorial done" (T2.1) and the hook for T2.2. Kept in the player attribute TutorialDone and in this server's
-- memory by UserId (re-join on the same server goes straight to the plaza). Saving is T2.2's job:
--   * Tutorial.ready = function(player) return profileLoaded end -- the tutorial waits until it says true
--   * Tutorial.setDone(player, true) after loading a profile that has it
--   * Tutorial.onDone(function(player, info) ... end) -- the final is won: show the reward, save the flag
local Tutorial = {}

Tutorial.ATTR = "TutorialDone"

export type Info = {
	-- first time (false when replayed with HOW TO PLAY)
	first: boolean,
	-- seconds from the first scene to the final whistle
	seconds: number,
}

local done: { [number]: boolean } = {}
local handlers: { (Player, Info) -> () } = {}

-- T2.2 replaces it: false holds the first tutorial (the player waits on the plaza screen) until the profile is loaded.
Tutorial.ready = function(_player: Player): boolean
	return true
end

function Tutorial.isDone(player: Player): boolean
	return player:GetAttribute(Tutorial.ATTR) == true or done[player.UserId] == true
end

function Tutorial.setDone(player: Player, v: boolean)
	if v then
		done[player.UserId] = true
	else
		done[player.UserId] = nil
	end
	player:SetAttribute(Tutorial.ATTR, v == true)
end

-- Returns a function that removes the handler.
function Tutorial.onDone(fn: (Player, Info) -> ()): () -> ()
	table.insert(handlers, fn)
	return function()
		local i = table.find(handlers, fn)
		if i then
			table.remove(handlers, i)
		end
	end
end

-- Called by Modes/Tutor when the final is over.
function Tutorial.complete(player: Player, info: Info)
	Tutorial.setDone(player, true)
	for _, fn in table.clone(handlers) do
		task.spawn(fn, player, info)
	end
end

return Tutorial
