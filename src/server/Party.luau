--!strict
-- Party on the server: actions from the Action remote (who is host, who is in, rate limits), the Party view to each
-- member, friend invites by link (launch data: host and JobId) and the teleport to the host's server.
-- Rules of membership: Logic/Parties. Queueing a party goes through Lobby (hooks set by Lobby.init).
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require("./Config")
local Guard = require("./Logic/Guard")
local Net = require(ReplicatedStorage.Shared.Net)
local Parties = require("./Logic/Parties")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Roster = require("./Roster")

local A = Net.Action
local L = Net.Limits

local Party = {}

local book = Parties.new(L.partyMax, L.inviteTtl, L.inviteGap, L.invitesMax)
Party.book = book

export type Hooks = {
	-- the group joins the queue of `mode` ("duel"|"ffa") together
	queue: (recs: { Roster.Rec }, mode: string, now: number) -> (),
	-- takes the person's queue entry out (the whole party entry), back to the lobby screen
	unqueue: (r: Roster.Rec) -> (),
	queued: (r: Roster.Rec) -> boolean,
}
local hooks: Hooks? = nil

function Party.init(h: Hooks)
	hooks = h
end

local function view(r: Roster.Rec, note: string?): Net.PartyView
	local now = Roster.now()
	local v: Net.PartyView = { members = {}, invites = {}, note = note }
	local p = Parties.of(book, r.id)
	if p then
		v.id = p.id
		v.host = p.host
		for _, uid in p.members do
			local m = Roster.find(uid)
			table.insert(v.members, {
				userId = uid,
				name = if m then m.name else "?",
				busy = m == nil or Roster.busy(m),
			})
		end
	end
	for _, inv in Parties.invitesFor(book, r.id, now) do
		local from = Roster.find(inv.from)
		if from then
			table.insert(v.invites, { from = inv.from, name = from.name, endsAt = inv.endsAt })
		end
	end
	return v
end

function Party.send(r: Roster.Rec, note: string?)
	if r.player.Parent then
		Remotes.Party:FireClient(r.player, view(r, note))
	end
end

function Party.note(r: Roster.Rec, note: string)
	Party.send(r, note)
end

local function sendAll(p: Parties.Party?, note: string?)
	if not p then
		return
	end
	for _, uid in p.members do
		local m = Roster.find(uid)
		if m then
			Party.send(m, note)
		end
	end
end

-- A party in the queue together stops searching when its people change.
local function stopSearch(p: Parties.Party?, note: string)
	if not p or not hooks then
		return
	end
	for _, uid in p.members do
		local m = Roster.find(uid)
		if m and hooks.queued(m) then
			hooks.unqueue(m)
			sendAll(p, note)
			return
		end
	end
end

-- Leaves the party (button, kick or leaving the server); the rest of the party is told.
local function leaveParty(r: Roster.Rec, gone: boolean)
	local before = Parties.of(book, r.id)
	if before then
		stopSearch(before, "Search stopped: party changed")
	end
	local p = if gone then Parties.remove(book, r.id) else Parties.leave(book, r.id)
	if p and #p.members > 0 then
		sendAll(p, if gone then `{r.name} left` else nil)
	end
	if not gone then
		Party.send(r)
	end
end

-- Host starts: "duel" = the two members against each other, "ffa" = all members in one 4-player match.
local function play(r: Roster.Rec, mode: string, now: number)
	local p = Parties.of(book, r.id)
	if not p or p.host ~= r.id or not hooks then
		return
	end
	if mode == "duel" and #p.members > 2 then
		Party.note(r, "A duel is for 2: use 4 PLAYERS")
		return
	end
	local recs = {}
	for _, uid in p.members do
		local m = Roster.find(uid)
		if not m then
			return
		end
		if Roster.busy(m) then
			Party.note(r, `Wait for {m.name}: in a match`)
			return
		end
		table.insert(recs, m)
	end
	hooks.queue(recs, mode, now)
end

local MODE_OF = { [Net.Mode.duel] = "duel", [Net.Mode.ffa] = "ffa" }

-- Party verbs; false when the verb is not a party one. A queue request of a party member goes here too.
function Party.action(r: Roster.Rec, verb: string, arg: number?, now: number): boolean
	if verb == A.pcreate then
		local old = Parties.of(book, r.id)
		if old and old.host ~= r.id then
			leaveParty(r, false)
		end
		Parties.create(book, r.id)
		Party.send(r)
	elseif verb == A.pinvite then
		local uid = Guard.userId(arg)
		local target = uid and Roster.find(uid)
		if not target or not Guard.cooldown(r.cool, "invite", now, 0.5) then
			return true
		end
		if not Parties.of(book, r.id) then
			Parties.create(book, r.id)
		end
		local ok, err = Parties.invite(book, r.id, target.id, now)
		if ok then
			Party.send(target)
			Party.send(r, `Invited {target.name}`)
		else
			Party.note(r, if err == "party is full" then "Party is full" else "Can't invite now")
		end
	elseif verb == A.paccept then
		local from = Guard.userId(arg)
		if not from then
			return true
		end
		local old = Parties.of(book, r.id)
		local p, err = Parties.accept(book, r.id, from, now)
		if p then
			if hooks and hooks.queued(r) then
				hooks.unqueue(r)
			end
			if old and old ~= p then
				stopSearch(old, "Search stopped: party changed")
				sendAll(old)
			end
			stopSearch(p, "Search stopped: party changed")
			sendAll(p)
		else
			Party.note(r, if err == "party is full" then "Party is full" else "Invite expired")
		end
	elseif verb == A.pdecline then
		local from = Guard.userId(arg)
		if from then
			Parties.decline(book, r.id, from)
			Party.send(r)
		end
	elseif verb == A.pleave then
		leaveParty(r, false)
	elseif verb == A.pkick then
		local uid = Guard.userId(arg)
		local target = uid and Roster.find(uid)
		local p = Parties.of(book, r.id)
		if not uid or not p or p.host ~= r.id or Parties.of(book, uid) ~= p then
			return true
		end
		stopSearch(p, "Search stopped: party changed")
		Parties.kick(book, r.id, uid)
		sendAll(p)
		if target then
			Party.send(target, "You left the party")
		end
	elseif verb == A.pplay then
		local mode = MODE_OF[arg :: any]
		if mode then
			play(r, mode, now)
		end
	elseif verb == A.pfriends then
		local p = Parties.of(book, r.id)
		if p and Guard.cooldown(r.cool, "friends", now, L.friendsGap) then
			p.friendsUntil = now + Config.FRIENDS_OPEN
		end
	elseif verb == A.queue then
		-- solo search is closed while in a party of two or more; the host's search is the party's
		local p = Parties.of(book, r.id)
		if not p or #p.members < 2 then
			return false
		end
		if p.host == r.id then
			local mode = MODE_OF[arg :: any]
			if mode then
				play(r, mode, now)
			end
		else
			Party.note(r, "The host starts the game")
		end
	else
		return false
	end
	return true
end

-- Busy flags changed (match start or end): members see who can play.
function Party.refresh(r: Roster.Rec)
	sendAll(Parties.of(book, r.id))
end

function Party.removed(r: Roster.Rec)
	leaveParty(r, true)
end

-- Friend invite link ---------------------------------------------------------------------------------------------

type Link = { h: number, j: string }

local function parse(v: any): Link?
	if type(v) == "string" then
		local ok, t = pcall(function()
			return HttpService:JSONDecode(v)
		end)
		v = if ok then t else nil
	end
	if type(v) ~= "table" then
		return nil
	end
	local h, j = Guard.userId(v.h), v.j
	if not h or type(j) ~= "string" or #j > 64 then
		return nil
	end
	return { h = h, j = j }
end

local function joinHere(r: Roster.Rec, link: Link)
	local host = Roster.find(link.h)
	local p = Parties.of(book, link.h)
	if not host or not p or p.host ~= link.h or p.friendsUntil < Roster.now() then
		Party.note(r, "Your friend's party is gone")
		return
	end
	local ok, friends = pcall(function()
		return r.player:IsFriendsWithAsync(link.h)
	end)
	if not ok or not friends then
		Party.note(r, "Only friends can join by invite")
		return
	end
	local joined, err = Parties.joinHost(book, r.id, link.h)
	if joined then
		stopSearch(joined, "Search stopped: party changed")
		sendAll(joined, `{r.name} joined`)
	else
		Party.note(r, if err == "party is full" then "Party is full" else "Your friend's party is gone")
	end
end

local function teleport(r: Roster.Rec, link: Link)
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = link.j
	options:SetTeleportData({ btParty = { h = link.h, j = link.j } })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { r.player }, options)
	end)
	if not ok then
		warn(`[BT] party teleport of {r.name} failed: {err}`)
		Party.note(r, "Couldn't reach your friend's server")
	end
end

-- On joining the server: came by a friend's invite link (or the teleport after it) → into the host's party.
-- `ready` waits until the client listens (Party.send after hello).
function Party.joined(r: Roster.Rec)
	local ok, data = pcall(function(): any
		return r.player:GetJoinData()
	end)
	if not ok or type(data) ~= "table" then
		return
	end
	local tp = type(data.TeleportData) == "table" and data.TeleportData.btParty
	local link = parse(tp) or parse(data.LaunchData)
	if not link then
		return
	end
	if link.j == "" or link.j == game.JobId then
		-- the host may still be loading: give it a moment
		task.delay(if Roster.find(link.h) then 0 else 5, function()
			if Roster.get(r.player) then
				joinHere(r, link)
			end
		end)
	elseif tp then
		-- already teleported once and still on another server: do not loop
		Party.note(r, "Couldn't reach your friend's server")
	else
		task.spawn(teleport, r, link)
	end
end

function Party.start()
	TeleportService.TeleportInitFailed:Connect(function(player, result, msg)
		local r = Roster.get(player)
		if not r then
			return
		end
		warn(`[BT] party teleport of {r.name}: {result} {msg}`)
		Party.note(
			r,
			if result == Enum.TeleportResult.GameFull
				then "Friend's server is full"
				else "Couldn't reach your friend's server"
		)
	end)
end

return Party
