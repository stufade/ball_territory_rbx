--!strict
-- Balls a person may take (T2.2): the profile's collection. Bots take any ball. The debug switch
-- Config.TEST_ALL_BALLS, or the ServerScriptService attribute DebugAllBalls = true, gives everybody all 27.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require("./Config")
local Net = require(ReplicatedStorage.Shared.Net)
local Profiles = require("./Profiles")
local Rules = require(ReplicatedStorage.Shared.Rules)

local Collection = {}

local ALL = {}
for e = 0, Rules.Config.NEL - 1 do
	table.insert(ALL, e)
end

function Collection.allBalls(): boolean
	return Config.TEST_ALL_BALLS or ServerScriptService:GetAttribute("DebugAllBalls") == true
end

-- Own balls of a person; nil = every ball (a bot, or the debug switch).
function Collection.owned(player: Player?): { number }?
	if not player or Collection.allBalls() then
		return nil
	end
	return Profiles.balls(player)
end

-- Options of the first-entry starter pick (Config.TUTORIAL = false).
function Collection.starters(): { number }
	return table.clone(if Collection.allBalls() then ALL else Net.STARTERS)
end

-- Free "any ball" picks per side in a duel draft: with all balls owned, any ball on every pick.
function Collection.anyFree(player: Player?): number
	return if player == nil or Collection.allBalls() then Rules.Config.DUEL_SIZE else Config.ANY_FREE
end

return Collection
