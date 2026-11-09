--!strict
-- Debug (Studio has one person): ServerScriptService attribute DebugFakeFriend = true adds a fake second person
-- "FAKE FRIEND" (UserId -999, no character, no client). It accepts every party invite at once and sits in matches
-- like an idle person (its draft and ball choice time out). false removes it. Not for live servers.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Lobby = require("./Lobby")
local Parties = require("./Logic/Parties")
local Party = require("./Party")
local Roster = require("./Roster")

local FakeFriend = {}

local ID = -999
local fake: Roster.Rec? = nil

function FakeFriend.tick(now: number)
	local on = ServerScriptService:GetAttribute("DebugFakeFriend") == true
	if on and not fake and #Players:GetPlayers() > 0 then
		local player = { UserId = ID, DisplayName = "FAKE FRIEND", Name = "FakeFriend", Parent = nil, Character = nil }
		local r = Roster.add(player :: any)
		r.readyAt = now
		r.first = false
		Lobby.adopt(r)
		fake = r
		print("[BT] debug: FAKE FRIEND joined (UserId -999)")
	elseif not on and fake then
		Lobby.leave(fake, now)
		Roster.remove(fake.player)
		fake = nil
		print("[BT] debug: FAKE FRIEND left")
	end
	local r = fake
	if r then
		for _, inv in Parties.invitesFor(Party.book, r.id, now) do
			Party.action(r, "paccept", inv.from, now)
		end
	end
end

return FakeFriend
