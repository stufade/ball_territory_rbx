--!strict
-- People outside matches: first-entry starter pick, mode queue (alone or as a party), and starting sessions on free
-- arenas. Watching from the plaza: Watch.luau; party rules: Party.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("./Analytics")
local Arenas = require("./Arenas")
local Collection = require("./Collection")
local Config = require("./Config")
local Guard = require("./Logic/Guard")
local Modes = require("./Modes")
local Net = require(ReplicatedStorage.Shared.Net)
local Party = require("./Party")
local Profiles = require("./Profiles")
local Queue = require("./Logic/Queue")
local Roster = require("./Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("./Runner")
local Session = require("./Session")
local Tutorial = require("./Tutorial")
local Watch = require("./Watch")

local A = Net.Action
local NEL = Rules.Config.NEL
-- the starter pick waits this long for the client's hello before its own timer starts
local HELLO_WAIT = 20
local MODE_OF = { [Net.Mode.duel] = "duel", [Net.Mode.ffa] = "ffa" }

local Lobby = {}

local queue = Queue.new(Config.QUEUE_WAIT, { duel = Config.SEATS.duel, ffa = Config.SEATS.ffa })
local byId: { [number]: Roster.Rec } = {}

local function sendIntroPick(r: Roster.Rec)
	local p = r.introPick
	if p then
		Roster.send(
			r,
			{ ph = "pick", mode = "intro", options = Collection.starters(), taken = {}, endsAt = p.endsAt },
			true
		)
	end
end

-- A person already past the first entry (debug fake friend): no starter pick.
function Lobby.adopt(r: Roster.Rec)
	byId[r.id] = r
end

function Lobby.join(r: Roster.Rec)
	byId[r.id] = r
	Analytics.step(r.player, Analytics.Step.Join)
	if not Config.TUTORIAL then
		r.introPick = { endsAt = r.joinedAt + HELLO_WAIT + Config.INTRO_PICK }
		sendIntroPick(r)
	elseif Tutorial.isDone(r.player) then
		-- tutorial done (re-join on this server, or a saved profile of T2.2): straight to the plaza
		r.first = false
		if not Profiles.played(r.player) then
			r.glow = "play"
		end
		Roster.lobby(r)
	else
		-- the tutorial starts once the profile is loaded (Tutorial.ready); a saved "done" cancels it (Lobby.loaded)
		r.tutor = true
	end
end

-- T2.2: the profile came (it may come after Lobby.join): a finished tutorial goes straight to the plaza.
function Lobby.loaded(r: Roster.Rec)
	if not Config.TUTORIAL or not Tutorial.isDone(r.player) or r.session or not r.tutor then
		return
	end
	r.tutor = nil
	r.first = false
	r.glow = if Profiles.played(r.player) then nil else "play"
	Roster.lobby(r)
	Party.refresh(r)
end

-- T2.2: the tutorial is won. The first time the reward screen comes after the victory screen (Roster.lobby shows it
-- until the client claims it, or REWARD_MAX s).
function Lobby.tutorialDone(r: Roster.Rec, now: number)
	local rw = Profiles.tutorialDone(r.player)
	if rw then
		r.reward = {
			ph = "reward",
			balls = rw.balls,
			legend = rw.legend,
			pool = rw.pool,
			boost = rw.boost,
			endsAt = now + Config.REWARD_MAX,
		}
	end
end

local function claim(r: Roster.Rec)
	if r.reward then
		r.reward = nil
		r.glow = if Profiles.played(r.player) then nil else "play"
		Roster.lobby(r)
		Party.refresh(r)
	end
end

-- Takes the person's whole queue entry out (a party leaves together); everyone of it goes back to the lobby.
local function unqueue(r: Roster.Rec)
	local ids: { number } = Queue.leave(queue, r.id) or {}
	for _, id in ids do
		local m = byId[id]
		if m then
			Roster.lobby(m)
		end
	end
end

function Lobby.leave(r: Roster.Rec, now: number)
	unqueue(r)
	Watch.stop(r)
	local s = r.session
	if s and not s.closed then
		Modes[s.mode].leave(s, r, now)
	end
	Party.removed(r)
	byId[r.id] = nil
end

-- One person or a party joins the queue of `mode` as one entry.
local function queueJoin(recs: { Roster.Rec }, mode: string, now: number)
	local ids = {}
	for _, r in recs do
		table.insert(ids, r.id)
	end
	if not Queue.join(queue, ids, mode, now) then
		return
	end
	for _, r in recs do
		r.queuedAt = now
		r.glow = nil
		Profiles.setPlayed(r.player)
		Roster.send(r, {
			ph = "queue",
			mode = mode :: any,
			endsAt = Queue.deadline(queue, r.id),
			humans = Queue.count(queue, mode),
		}, true)
	end
end

Party.init({
	queue = queueJoin,
	unqueue = unqueue,
	queued = function(r)
		return Queue.mode(queue, r.id) ~= nil
	end,
})

local function hello(r: Roster.Rec, now: number)
	if not r.readyAt then
		r.readyAt = now
		if r.introPick then
			r.introPick.endsAt = now + Config.INTRO_PICK
		end
	end
	if r.introPick then
		sendIntroPick(r)
	elseif r.state then
		Roster.send(r, r.state, true)
	end
	local s = r.session or r.watching
	if s and s.runner and s.st == "round" then
		Runner.join(s.runner, r.player)
		local mode = Modes[s.mode] :: any
		if r.session == s and mode.hello then
			mode.hello(s, r)
		end
	end
	Party.send(r)
end

function Lobby.action(r: Roster.Rec, verb: string, arg: number?, now: number)
	if verb == A.hello then
		hello(r, now)
		Profiles.send(r.player)
		return
	end
	if verb == A.claim then
		claim(r)
		return
	end
	if verb == A.daily then
		Profiles.claimDaily(r.player)
		return
	end
	-- (works anywhere, the server checks who)
	if verb == A.devballs then
		-- TODO(REMOVE BEFORE LAUNCH): dev button
		Profiles.devAllBalls(r.player)
		return
	end
	-- party verbs work anywhere (in a match too); a queue request of a party member is the host's party search
	if verb ~= A.queue and Party.action(r, verb, arg, now) then
		return
	end
	local s = r.session
	if s then
		if verb == A.leave and s.st == "result" then
			Session.detach(s, r)
		else
			Modes[s.mode].action(s, r, verb, arg, now)
		end
		return
	end
	if r.introPick then
		local e = Guard.element(arg, NEL)
		if verb == A.pick and e ~= nil and table.find(Collection.starters(), e) then
			r.introE = e
			r.introPick = nil
		end
		return
	end
	if r.introE or r.tutor or r.reward or (verb == A.queue and Party.action(r, verb, arg, now)) then
		return
	end
	if verb == A.tutor then
		-- HOW TO PLAY on the plaza: the tutorial again
		unqueue(r)
		Watch.stop(r)
		r.glow = nil
		r.tutor = true
		return
	end
	if verb == A.queue then
		local mode = MODE_OF[arg :: any]
		if mode then
			queueJoin({ r }, mode, now)
		end
	elseif verb == A.cancel then
		unqueue(r)
	elseif verb == A.watch then
		-- debug: watch an arena from anywhere until the plaza check (Watch.tick) picks by distance again
		local a = Arenas.byId(Guard.int(arg, 1, 255) or 0)
		if a and a.session then
			Watch.start(r, a.session)
		end
	elseif verb == A.leave then
		Watch.stop(r)
	end
end

local function startSession(mode: Net.ModeName, arena: Arenas.Arena, recs: { Roster.Rec }, debug: boolean, now: number)
	for _, r in recs do
		Watch.stop(r)
	end
	local s = Session.new(mode, arena, recs, debug)
	Modes[mode].start(s, now)
	for _, r in recs do
		Party.refresh(r)
	end
end

-- Starts what can start: tutorials and first rounds, then queue groups, then debug bot matches.
function Lobby.tick(now: number)
	for _, r in Roster.all() do
		local rw = r.reward
		if rw and not r.session and now >= (rw.endsAt or 0) then
			claim(r)
		end
		-- the tutorial starts once the client listens (hello), so it sees the first scene from its start
		local listening = r.readyAt ~= nil or now - r.joinedAt >= Config.TUT.helloWait
		if r.tutor and not r.session and listening and Tutorial.ready(r.player) then
			local arena = Arenas.free("duel")[1]
			if arena then
				r.tutor = nil
				startSession("tutor", arena, { r }, false, now)
			elseif not r.state or r.state.ph ~= "wait" then
				Roster.send(r, { ph = "wait", mode = "tutor" })
			end
		end
		local p = r.introPick
		if p and now >= p.endsAt then
			local starters = Collection.starters()
			r.introE = starters[math.random(1, #starters)]
			r.introPick = nil
		end
		if r.introE and not r.session then
			local arena = Arenas.free("duel")[1]
			if arena then
				startSession("intro", arena, { r }, false, now)
				r.introE = nil
			elseif not r.state or r.state.ph ~= "wait" then
				Roster.send(r, { ph = "wait", mode = "intro" })
			end
		end
	end

	local free = { duel = #Arenas.free("duel"), ffa = #Arenas.free("ffa") }
	for _, g in Queue.poll(queue, now, free) do
		local arena = Arenas.free(g.mode)[1]
		local recs = {}
		for _, id in g.ids do
			local r = byId[id]
			if r then
				Analytics.custom(r.player, "QueueWait", math.floor(now - (r.queuedAt or now)), g.mode)
				table.insert(recs, r)
			end
		end
		if arena and #recs > 0 then
			startSession(g.mode :: any, arena, recs, false, now)
		end
	end
	for _, r in Roster.all() do
		local mode = Queue.mode(queue, r.id)
		if mode then
			local deadline = Queue.deadline(queue, r.id) :: number
			local humans = Queue.count(queue, mode)
			local old = r.state
			if now >= deadline then
				if not old or old.ph ~= "wait" then
					Roster.send(r, { ph = "wait", mode = mode :: any })
				end
			elseif not old or old.ph ~= "queue" or old.humans ~= humans or old.endsAt ~= deadline then
				Roster.send(r, { ph = "queue", mode = mode :: any, endsAt = deadline, humans = humans })
			end
		end
	end

	if ServerScriptService:GetAttribute("DebugBotMatches") == true then
		for _, a in Arenas.all() do
			if a.session == nil and a.model.Parent then
				startSession(a.mode :: any, a, {}, true, now)
			end
		end
	end
end

return Lobby
