--!strict
-- TODO(REMOVE BEFORE LAUNCH): Studio-only switches for the tester, set as attributes on ServerScriptService:
--   DebugNoPasses = true               the server treats the player as owning no game pass
--   DebugPaidRandomRestricted = true   PolicyService is treated as if it restricted paid random items
-- Ignored outside Studio (RunService:IsStudio() is false in a live server).
local Debug = {}

export type Env = { studio: () -> boolean, attr: (string) -> any }

local function real(): Env
	return {
		studio = function()
			return game:GetService("RunService"):IsStudio()
		end,
		attr = function(name: string)
			return game:GetService("ServerScriptService"):GetAttribute(name)
		end,
	}
end

function Debug.flag(name: string, env: Env?): boolean
	local e = env or real()
	return e.studio() and e.attr(name) == true
end

function Debug.noPasses(env: Env?): boolean
	return Debug.flag("DebugNoPasses", env)
end

function Debug.paidRandomRestricted(env: Env?): boolean
	return Debug.flag("DebugPaidRandomRestricted", env)
end

return Debug
