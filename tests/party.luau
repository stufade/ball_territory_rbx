--!strict
-- M1.6 party and spectators: pure party rules, then the whole server on the mocked Roblox with fake players:
-- create / invite / accept / kick / host leaves, host-only start, duel each other (no bots), 4 players together,
-- search cancel, friend invite link (same server and teleport), junk input, plaza spectators by distance.
-- lune run tests/party
local process = require("@lune/process")
local serde = require("@lune/serde")
local Mock = require("./Mock")
local Parties = require("../src/server/Logic/Parties")
local Queue = require("../src/server/Logic/Queue")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- 1. Pure rules -------------------------------------------------------------------------------------------------
do
	local b = Parties.new(4, 30, 3, 6)
	local p = Parties.create(b, 1)
	check(p.host == 1 and #p.members == 1, "create: host alone")
	check(Parties.create(b, 1) == p, "create twice keeps the party")
	check(Parties.invite(b, 1, 2, 0), "invite")
	check(not Parties.invite(b, 1, 2, 1), "invite again too fast")
	check(not Parties.invite(b, 1, 1, 5), "no self invite")
	check(Parties.accept(b, 2, 1, 2) == p and #p.members == 2, "accept")
	check(Parties.accept(b, 3, 1, 2) == nil, "accept without invite")
	Parties.invite(b, 1, 3, 10)
	check(Parties.accept(b, 3, 1, 41) == nil, "invite expires")
	check(Parties.kick(b, 2, 1) == nil, "member cannot kick")
	check(Parties.kick(b, 1, 2) == p and Parties.of(b, 2) == nil, "host kicks")
	Parties.invite(b, 1, 2, 50)
	Parties.accept(b, 2, 1, 50)
	Parties.leave(b, 1)
	check(p.host == 2 and #p.members == 1, "host leaves: next member hosts")
	Parties.leave(b, 2)
	check(b.byId[p.id] == nil, "empty party is gone")
	local q = Parties.create(b, 10)
	for id = 11, 13 do
		Parties.invite(b, 10, id, 100)
		Parties.accept(b, id, 10, 100)
	end
	check(#q.members == 4, "four members")
	local ok, err = Parties.invite(b, 10, 14, 100)
	check(not ok and err == "party is full", "full party")
	check(Parties.joinHost(b, 14, 10) == nil, "link join into a full party refused")
	Parties.remove(b, 12)
	check(#q.members == 3 and Parties.of(b, 12) == nil, "leaving the server leaves the party")
	-- negative Studio ids
	local s = Parties.create(b, -1)
	Parties.invite(b, -1, -2, 200)
	Parties.accept(b, -2, -1, 200)
	Parties.remove(b, -2)
	check(#s.members == 1 and next(b.sentAt) ~= nil, "negative ids")
end

-- Queue groups
do
	local q = Queue.new(5, { duel = 2, ffa = 4 })
	check(not Queue.join(q, { 1, 2, 3 }, "duel", 0), "group bigger than the seats")
	check(Queue.join(q, { 1, 2 }, "duel", 0), "pair joins the duel queue")
	local g = Queue.poll(q, 0, { duel = 1 })
	check(#g == 1 and #g[1].ids == 2 and g[1].ids[2] == 2, "pair starts at once (no bots, no strangers)")
	Queue.join(q, 9, "ffa", 0)
	Queue.join(q, { 1, 2, 3 }, "ffa", 1)
	Queue.join(q, { 4, 5 }, "ffa", 2)
	check(Queue.count(q, "ffa") == 6, "count people")
	g = Queue.poll(q, 2, { ffa = 1 })
	check(#g == 1 and #g[1].ids == 4 and g[1].ids[1] == 9 and g[1].ids[4] == 3, "1 + party of 3 fill 4 seats")
	check(Queue.mode(q, 4) == "ffa", "the party of 2 waits for the next match")
	local ids = Queue.leave(q, 5)
	check(
		ids ~= nil and #(ids :: { number }) == 2 and Queue.mode(q, 4) == nil,
		"one member cancels: the whole party leaves"
	)
end

-- 2. Server on the mock -----------------------------------------------------------------------------------------
local world = Mock.world()
local logs, warns = {}, {}
local load = Mock.loader(world, logs, warns)
load("src/server/init.server.luau")
local Remotes = load("src/shared/Net/Remotes.luau")
local S = world.services
local DT = 1 / 30

type Client = {
	p: any,
	id: number,
	st: any,
	answered: any,
	party: any,
	notes: { string },
	matchId: number?,
	seats: any,
	viewing: number?,
	viewStarts: number,
	unviews: number,
	viewBytes: number,
	gone: boolean,
}
local clients: { Client } = {}

local function action(c: Client, verb: any, arg: any)
	for _, fn in Remotes.Action.OnServerEvent.fns do
		fn(c.p, verb, arg)
	end
end

local function drive(c: Client)
	local inbox = c.p._inbox
	for _, m in inbox do
		local a = m.args
		if m.remote == "State" then
			c.st = a[1]
		elseif m.remote == "Party" then
			c.party = a[1]
			if a[1].note then
				table.insert(c.notes, a[1].note)
			end
		elseif m.remote == "Match" then
			local kind, data = a[1], a[2]
			if kind == "start" then
				if data.view then
					c.viewing = data.id
					c.viewStarts += 1
				else
					c.matchId = data.id
					c.seats = data.seats
				end
			elseif kind == "unview" then
				if c.viewing == data.id then
					c.viewing = nil
				end
				c.unviews += 1
			end
		elseif m.remote == "Snap" and c.viewing then
			c.viewBytes += buffer.len(a[1])
		end
	end
	table.clear(inbox)
	local st = c.st
	if not st or c.answered == st then
		return
	end
	if st.ph == "pick" then
		c.answered = st
		action(c, "pick", st.options[1])
	elseif st.ph == "draft" and st.turn == st.me and st.offer and #st.offer > 0 then
		c.answered = st
		action(c, "draft", st.offer[1])
	elseif st.ph == "choose" and (st.keep or -1) < 0 and #st.left > 0 then
		c.answered = st
		action(c, "choose", st.left[1])
	end
end

local function run(seconds: number)
	for _ = 1, math.max(1, math.floor(seconds / DT)) do
		Mock.advance(DT)
		S.RunService.Heartbeat:Fire(DT)
		for _, c in clients do
			if not c.gone then
				drive(c)
			end
		end
	end
end

local function runUntil(limit: number, cond: () -> boolean): boolean
	local t = Mock.now()
	while Mock.now() - t < limit do
		if cond() then
			return true
		end
		run(0.5)
	end
	return cond()
end

local function join(id: number, name: string, joinData: any?, friends: { number }?): Client
	local p = Mock.player(world, id, name)
	if joinData then
		p._join = joinData
	end
	local list: { number } = friends or {}
	for _, f in list do
		p._friends[f] = true
	end
	local c: Client = {
		p = p,
		id = id,
		st = nil,
		answered = nil,
		party = nil,
		notes = {},
		matchId = nil,
		seats = nil,
		viewing = nil,
		viewStarts = 0,
		unviews = 0,
		viewBytes = 0,
		gone = false,
	}
	p.Parent = S.Players
	S.Players.PlayerAdded:Fire(p)
	action(c, "hello", nil)
	table.insert(clients, c)
	return c
end

local function leave(c: Client)
	c.gone = true
	S.Players.PlayerRemoving:Fire(c.p)
	c.p.Parent = nil
end

local function inLobby(...: Client): boolean
	for _, c in { ... } do
		if not c.st or c.st.ph ~= "lobby" then
			return false
		end
	end
	return true
end

local function members(c: Client): number
	return if c.party and c.party.id then #c.party.members else 0
end

local function noted(c: Client, text: string): boolean
	for _, n in c.notes do
		if string.find(n, text, 1, true) then
			return true
		end
	end
	return false
end

local function noWarnings(what: string)
	for _, w in warns do
		print("WARN: " .. w)
	end
	check(#warns == 0, what .. ": no warnings")
	table.clear(warns)
end

-- First entry of both (intro round against a weak bot), then the plaza.
local ann = join(100, "Ann")
local bob = join(101, "Bob")
check(
	runUntil(240, function()
		return inLobby(ann, bob)
	end),
	"both finish the first round"
)
check(ann.p.Character.Humanoid.WalkSpeed == 26, "plaza walk speed 26")

-- Party: create, invite, accept, host-only start ----------------------------------------------------------------
action(ann, "pcreate")
run(0.1)
check(ann.party and ann.party.host == 100 and members(ann) == 1, "Ann hosts a party")
action(ann, "pinvite", 101)
run(0.1)
check(bob.party and #bob.party.invites == 1 and bob.party.invites[1].from == 100, "Bob sees the invite")
check(bob.party.invites[1].name == "Ann", "invite shows the host name")
run(0.6)
action(ann, "pinvite", 101)
run(0.1)
check(noted(ann, "Can't invite"), "second invite within 3 s refused")
action(bob, "paccept", 100)
run(0.1)
check(members(ann) == 2 and members(bob) == 2 and bob.party.host == 100, "Bob joins Ann's party")
check(#bob.party.invites == 0, "the accepted invite is gone")

action(bob, "queue", 1)
run(0.1)
check(noted(bob, "host starts") and bob.st.ph == "lobby", "a member cannot start the search")

-- Duel each other: both in one duel, no bots
ann.matchId, bob.matchId = nil, nil
action(ann, "pplay", 1)
check(
	runUntil(3, function()
		return ann.matchId ~= nil and bob.matchId ~= nil
	end),
	"party duel starts"
)
check(ann.matchId == bob.matchId, "same duel")
local humans = 0
for _, seat in ann.seats or {} do
	if seat.userId ~= 0 then
		humans += 1
	end
end
check(humans == 2, "duel each other: no bots")
run(1)
check(ann.party.members[2].busy == true, "members are busy in the match")
check(
	runUntil(400, function()
		return inLobby(ann, bob)
	end),
	"party duel ends, both back on the plaza"
)
check(members(ann) == 2 and ann.party.members[2].busy == false, "party kept after the match")
noWarnings("party duel")

-- 4 players together: one entry in the ffa queue, bots after 5 s
ann.matchId, bob.matchId = nil, nil
action(ann, "pplay", 2)
run(0.2)
check(ann.st.ph == "queue" and bob.st.ph == "queue" and ann.st.humans == 2, "both search 4 PLAYERS together")
action(bob, "cancel")
run(0.2)
check(inLobby(ann, bob), "a member cancels: the party stops searching")
run(1)
action(ann, "pplay", 2)
check(
	runUntil(8, function()
		return ann.matchId ~= nil and bob.matchId ~= nil
	end),
	"4 players together starts"
)
check(ann.matchId == bob.matchId and #ann.seats == 4, "same 4-player match")
-- the host cannot start while a member plays
check(
	runUntil(200, function()
		return inLobby(ann, bob)
	end),
	"ffa ends"
)
noWarnings("party ffa")

-- Third member: duel refused; kick; host leaves ------------------------------------------------------------------
local cid = join(102, "Cid")
check(
	runUntil(240, function()
		return inLobby(cid)
	end),
	"Cid finishes the first round"
)
action(ann, "pinvite", 102)
run(0.1)
action(cid, "paccept", 100)
run(0.1)
check(members(ann) == 3, "three in the party")
action(ann, "pplay", 1)
run(0.1)
check(noted(ann, "duel is for 2") and ann.st.ph == "lobby", "duel each other needs exactly 2")
action(bob, "pkick", 102)
run(0.1)
check(members(ann) == 3, "a member cannot kick")
action(ann, "pkick", 102)
run(0.1)
check(members(ann) == 2 and cid.party.id == nil and noted(cid, "left the party"), "host kicks Cid")
action(ann, "pleave")
run(0.1)
check(ann.party.id == nil and bob.party.host == 101 and members(bob) == 1, "host leaves: Bob hosts")
-- a party member leaving the server mid-search
action(bob, "pinvite", 102)
run(0.1)
action(cid, "paccept", 101)
action(bob, "pplay", 2)
run(0.1)
check(cid.st.ph == "queue", "Cid searches with Bob")
leave(bob)
run(0.2)
check(cid.st.ph == "lobby" and cid.party.host == 102 and noted(cid, "Bob left"), "host leaves the server: search stops")
noWarnings("kick and leave")

-- Friend invite link --------------------------------------------------------------------------------------------
action(ann, "pcreate")
action(ann, "pfriends")
run(0.1)
local link = serde.encode("json", { h = 100, j = "job-here" })
local dan = join(103, "Dan", { LaunchData = link }, { 100 })
run(0.1)
check(members(ann) == 2 and dan.party and dan.party.host == 100, "friend by link joins the host's party")
local eve = join(104, "Eve", { LaunchData = link }, {})
run(0.1)
check(members(ann) == 2 and noted(eve, "Only friends"), "a stranger with the link is refused")
local fay = join(105, "Fay", { LaunchData = serde.encode("json", { h = 100, j = "other-job" }) }, { 100 })
run(0.1)
local tp = world.teleports[#world.teleports]
check(
	tp and tp.players[1] == fay.p and tp.options.ServerInstanceId == "other-job",
	"friend on another server is teleported to the host's server"
)
local gus = join(106, "Gus", { TeleportData = { btParty = { h = 100, j = "third-job" } } }, { 100 })
run(0.1)
check(#world.teleports == 1 and noted(gus, "Couldn't reach"), "no second teleport after one")
S.TeleportService.TeleportInitFailed:Fire(fay.p, { Name = "GameFull" }, "full")
run(0.1)
check(#fay.notes > 0, "a failed teleport is reported")
check(#warns == 1 and string.find(warns[1], "teleport", 1, true), "failed teleport logged")
table.clear(warns)
local hal = join(107, "Hal", { LaunchData = "{broken" }, { 100 })
run(0.1)
check(hal.party == nil or hal.party.id == nil, "broken launch data ignored")

-- Junk party input
local junkList: { any } = { 0 / 0, math.huge, "x", {}, 1.5, -0, 2 ^ 60 }
for _, junk in junkList do
	for _, verb in { "pinvite", "paccept", "pdecline", "pkick", "pplay" } do
		action(eve, verb, junk)
	end
end
for _ = 1, 40 do
	action(eve, "pinvite", 100)
end
run(0.2)
check(ann.party and #ann.party.invites == 0, "junk invites go nowhere")
noWarnings("links and junk")

-- Spectators on the plaza ---------------------------------------------------------------------------------------
check(
	runUntil(240, function()
		return inLobby(dan, eve, fay, gus, hal)
	end),
	"everybody on the plaza"
)
S.ServerScriptService:SetAttribute("DebugBotMatches", true)
run(1)
local duel1 = world.arenas[1]
local focus = duel1.Stand1.Position
local function at(c: Client, x: number, z: number)
	c.p.Character.HumanoidRootPart.Position = focus + Mock.Vector3.new(x, 0, z)
end
local watchers = { ann, cid, dan, eve, fay, gus, hal }
for i, c in watchers do
	at(c, i, 40)
end
-- the duel draft of the bots comes first; the viewers get the match at its first round
run(12)
local n = 0
for _, c in watchers do
	if c.viewing then
		n += 1
	end
end
check(n == 6, `6 viewers at most on one arena (got {n})`)
-- the cap leaves one of the seven out (server order); follow one who watches
local v: Client = ann
for _, c in watchers do
	if c.viewing then
		v = c
		break
	end
end
check(v.viewing ~= nil, "a person near Duel1 watches it")
local t0, b0 = Mock.now(), v.viewBytes
run(30)
local rate = (v.viewBytes - b0) / (Mock.now() - t0) / 1024
check(rate > 0.2 and rate < 20, string.format("viewer traffic %.1f KB/s under 20 KB/s", rate))
at(v, 0, 200)
run(1)
check(v.viewing == nil and v.unviews >= 1, "walking away stops watching")
check(
	runUntil(15, function()
		local k = 0
		for _, c in watchers do
			k += if c.viewing then 1 else 0
		end
		return k == 6
	end),
	"the freed viewer slot goes to the person waiting near the arena"
)
for _, c in watchers do
	if c ~= v then
		at(c, 0, 300)
	end
end
at(v, 0, 40)
check(
	runUntil(15, function()
		return v.viewing ~= nil
	end),
	"coming back watches again (from the next round if the arena is in its draft)"
)
noWarnings("spectators")

print(`{passed} checks passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("PARTY OK")
