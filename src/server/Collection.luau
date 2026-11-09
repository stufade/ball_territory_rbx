--!strict
-- Balls a person may take. M1 has no drops: Config.TEST_ALL_BALLS gives everybody all 27 for playtests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require("./Config")
local Net = require(ReplicatedStorage.Shared.Net)
local Rules = require(ReplicatedStorage.Shared.Rules)

local Collection = {}

local ALL = {}
for e = 0, Rules.Config.NEL - 1 do
	table.insert(ALL, e)
end

-- Options of the first-entry starter pick.
function Collection.starters(): { number }
	return table.clone(if Config.TEST_ALL_BALLS then ALL else Net.STARTERS)
end

-- Free "any ball" picks per side in a duel draft: with all balls owned, any ball on every pick.
function Collection.anyFree(): number
	return if Config.TEST_ALL_BALLS then Rules.Config.DUEL_SIZE else Config.ANY_FREE
end

return Collection
