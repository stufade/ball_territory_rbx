--!strict
-- Per-player server memory of M1 (no DataStore): first entry, match count, current session, rate buckets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guard = require("./Logic/Guard")
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local Roster = {}

export type Rec = {
	player: Player,
	id: number,
	name: string,
	joinedAt: number,
	-- client said hello (UI ready); the first-entry timers start then
	readyAt: number?,
	-- true until the first round (intro) is over
	first: boolean,
	matches: number,
	-- intro starter pick before an arena is free
	introPick: { endsAt: number }?,
	introE: number?,
	session: any?,
	watching: any?,
	queuedAt: number?,
	input: Guard.Bucket,
	action: Guard.Bucket,
	lastTap: number?,
	state: Net.State?,
	-- M1.6: arena session watched from the lobby (proximity), party cooldowns
	cool: { [string]: number },
}

local recs: { [Player]: Rec } = {}

function Roster.now(): number
	return workspace:GetServerTimeNow()
end

function Roster.add(player: Player): Rec
	local now = Roster.now()
	local L = Net.Limits
	local r: Rec = {
		player = player,
		id = player.UserId,
		name = player.DisplayName,
		joinedAt = now,
		readyAt = nil,
		first = true,
		matches = 0,
		introPick = nil,
		introE = nil,
		session = nil,
		watching = nil,
		queuedAt = nil,
		input = Guard.bucket(L.inputRate, L.inputBurst, os.clock()),
		action = Guard.bucket(L.actionRate, L.actionBurst, os.clock()),
		lastTap = nil,
		state = nil,
		cool = {},
	}
	recs[player] = r
	return r
end

function Roster.get(player: Player): Rec?
	return recs[player]
end

function Roster.remove(player: Player)
	recs[player] = nil
end

function Roster.find(userId: number): Rec?
	for _, r in recs do
		if r.id == userId then
			return r
		end
	end
	return nil
end

-- Busy: in a match or in the first-entry pick; party play waits for such members.
function Roster.busy(r: Rec): boolean
	return r.session ~= nil or r.introPick ~= nil or r.introE ~= nil
end

function Roster.all(): { [Player]: Rec }
	return recs
end

-- Sends a State screen. `force` resends even when the screen did not change.
function Roster.send(r: Rec, st: Net.State, force: boolean?)
	local old = r.state
	if not force and old and old.ph == st.ph and st.ph == "lobby" and old.first == st.first then
		return
	end
	r.state = st
	if r.player.Parent then
		Remotes.State:FireClient(r.player, st)
	end
end

function Roster.lobby(r: Rec)
	Roster.send(r, { ph = "lobby", first = r.first })
end

return Roster
