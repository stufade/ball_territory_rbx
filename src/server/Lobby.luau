--!strict
-- People outside matches: first-entry starter pick, mode queue, watching, and starting sessions on free arenas.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("./Analytics")
local Arenas = require("./Arenas")
local Collection = require("./Collection")
local Config = require("./Config")
local Guard = require("./Logic/Guard")
local Modes = require("./Modes")
local Net = require(ReplicatedStorage.Shared.Net)
local Queue = require("./Logic/Queue")
local Roster = require("./Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("./Runner")
local Session = require("./Session")

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

function Lobby.join(r: Roster.Rec)
	byId[r.id] = r
	Analytics.step(r.player, Analytics.Step.Join)
	r.introPick = { endsAt = r.joinedAt + HELLO_WAIT + Config.INTRO_PICK }
	sendIntroPick(r)
end

local function unwatch(r: Roster.Rec)
	local s = r.watching
	if s then
		s.viewers[r] = nil
		r.watching = nil
	end
end

function Lobby.leave(r: Roster.Rec, now: number)
	Queue.leave(queue, r.id)
	unwatch(r)
	local s = r.session
	if s and not s.closed then
		Modes[s.mode].leave(s, r, now)
	end
	byId[r.id] = nil
end

local function queueJoin(r: Roster.Rec, mode: string, now: number)
	if Queue.join(queue, r.id, mode, now) then
		r.queuedAt = now
		Roster.send(r, {
			ph = "queue",
			mode = mode :: any,
			endsAt = Queue.deadline(queue, r.id),
			humans = Queue.count(queue, mode),
		}, true)
	end
end

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
	end
end

function Lobby.action(r: Roster.Rec, verb: string, arg: number?, now: number)
	if verb == A.hello then
		hello(r, now)
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
	if r.introE then
		return
	end
	if verb == A.queue then
		local mode = MODE_OF[arg :: any]
		if mode then
			unwatch(r)
			queueJoin(r, mode, now)
		end
	elseif verb == A.cancel then
		if Queue.leave(queue, r.id) then
			Roster.lobby(r)
		end
	elseif verb == A.watch then
		local a = Arenas.byId(Guard.int(arg, 1, 255) or 0)
		local target = a and a.session
		if target and not Queue.mode(queue, r.id) then
			unwatch(r)
			target.viewers[r] = true
			r.watching = target
			if target.runner and target.st == "round" then
				Runner.join(target.runner, r.player)
			end
		end
	elseif verb == A.leave then
		if r.watching then
			unwatch(r)
			Roster.lobby(r)
		end
	end
end

local function startSession(mode: Net.ModeName, arena: Arenas.Arena, recs: { Roster.Rec }, debug: boolean, now: number)
	for _, r in recs do
		unwatch(r)
	end
	local s = Session.new(mode, arena, recs, debug)
	Modes[mode].start(s, now)
end

-- Starts what can start: first rounds, then queue groups, then debug bot matches.
function Lobby.tick(now: number)
	for _, r in Roster.all() do
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
