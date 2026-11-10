--!strict
-- T2.1 tutorial: the staged scenes on the real rules and the whole cartoon through the server on a mocked Roblox.
-- 1. Scenes A-C (20 seeds each): A gives BOOM then WILDFIRE, B's power grabs land, C's tap at the enemy is a KO.
-- 2. Final D: 50 runs with random player input (plus idle, chasing, wall-hugging players) -> the player wins all.
-- 3. Server: a new player goes through the cartoon by its cues, wins, lands on the plaza with PLAY lit; the flag and
--    the T2.2 hook; re-join on the same server -> plaza; HOW TO PLAY -> the tutorial again; an AFK player still ends.
-- lune run tests/tutor [final runs, 50 by default]
local process = require("@lune/process")
local Mock = require("./Mock")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local world = Mock.world()
local logs, warns = {}, {}
local load = Mock.loader(world, logs, warns)
load("src/server/init.server.luau")
local Rules = load("src/shared/Rules/init.luau")
local Net = load("src/shared/Net/init.luau")
local Remotes = load("src/shared/Net/Remotes.luau")
local Tutor = load("src/server/Modes/Tutor.luau")
local TutorBot = load("src/server/Logic/TutorBot.luau")
local Tutorial = load("src/server/Tutorial.luau")
local Config = load("src/server/Config.luau")
local Snap = Net.Snap
local S_ = world.services
local T = Config.TUT
local FIRE, BOT = Tutor.FIRE, Tutor.BOT
local DT = Rules.Config.DT

-- 1. Scenes A-C -------------------------------------------------------------------------------------------------
local function events(S: any, seconds: number, each: ((ev: any) -> ())?)
	for _ = 1, math.floor(seconds / DT) do
		Rules.step(S)
		for _, ev in Rules.drain(S) do
			if each then
				each(ev)
			end
		end
		if S.done then
			break
		end
	end
end

local boomAt, wildAt = {}, {}
for seed = 1, 20 do
	local S = Tutor.stage("A", seed)
	Rules.launch(S)
	Rules.drain(S)
	local boom, wild
	events(S, T.watchMax, function(ev)
		if ev.kind == "rx" and ev.d.k == "BOOM" then
			boom = boom or S.t
		elseif ev.kind == "rx" and ev.d.k == "WILDFIRE" then
			wild = wild or S.t
		end
	end)
	check(boom and wild and boom < wild, `A seed {seed}: BOOM then WILDFIRE ({boom}, {wild})`)
	table.insert(boomAt, boom or 99)
	table.insert(wildAt, wild or 99)
end
table.sort(boomAt)
table.sort(wildAt)
print(
	string.format(
		"A: BOOM at %.2f-%.2f s, WILDFIRE at %.2f-%.2f s of match time",
		boomAt[1],
		boomAt[20],
		wildAt[1],
		wildAt[20]
	)
)

local gains = {}
for seed = 1, 20 do
	local S = Tutor.stage("B", seed)
	Rules.launch(S)
	local before = S.counts[FIRE]
	check(Rules.press(S, FIRE), `B seed {seed}: power fires`)
	events(S, T.grab)
	local gain = (S.counts[FIRE] - before) / S.area * 100
	table.insert(gains, gain)
	check(gain >= 15, `B seed {seed}: land jumps ({string.format("%.0f", gain)}%)`)
end
table.sort(gains)
print(string.format("B: land +%.0f..%.0f%% after IGNITE", gains[1], gains[#gains]))

local koAt = {}
for seed = 1, 20 do
	local S = Tutor.stage("C", seed)
	Rules.launch(S)
	S.nextPrompt = S.t
	Rules.step(S)
	local prompt = false
	for _, ev in Rules.drain(S) do
		prompt = prompt or ev.kind == "prompt"
	end
	check(prompt and S.promptUntil > S.t, `C seed {seed}: CHOOSE DIRECTION is open`)
	-- a tap within the cone flies straight at the enemy (the server's filter)
	local tx, ty = S.by[BOT].x - S.by[FIRE].x, S.by[BOT].y - S.by[FIRE].y
	check(Rules.redirect(S, FIRE, tx, ty), `C seed {seed}: redirect accepted`)
	local ko, stolen
	events(S, T.hitWait, function(ev)
		if ev.kind == "ko" and ev.d.e == BOT then
			ko = ko or S.t
		elseif ev.kind == "steal" and ev.d.e == FIRE then
			stolen = ev.d.n
		end
	end)
	check(ko and (stolen or 0) > 0, `C seed {seed}: KO and land stolen ({ko}, {stolen})`)
	table.insert(koAt, (ko or 99) - DT)
end
table.sort(koAt)
print(string.format("C: KO %.2f-%.2f s of match time after the tap", koAt[1], koAt[#koAt]))

-- 2. Final D: 50 runs ---------------------------------------------------------------------------------------------
type Player = (S: any, rng: any) -> ()
local players: { [string]: Player } = {
	-- taps a random direction every 0.2-1.6 s, presses power 0-3 s after it is ready
	random = function(S, rng)
		local b = S.by[FIRE]
		if rng() < DT / 0.8 then
			local a = rng() * math.pi * 2
			Rules.redirect(S, FIRE, math.cos(a), math.sin(a))
		end
		if b.charge >= 1 and rng() < DT / 1.5 then
			Rules.press(S, FIRE)
		end
	end,
	-- does nothing
	idle = function() end,
	-- chases the bot all the time
	chase = function(S, rng)
		if rng() < DT / 0.3 then
			local p, q = S.by[FIRE], S.by[BOT]
			Rules.redirect(S, FIRE, q.x - p.x, q.y - p.y)
		end
	end,
	-- keeps flying into the nearest wall, never presses
	wall = function(S, rng)
		if rng() < DT / 0.5 then
			local p = S.by[FIRE]
			local dx = if p.x < 12 then -1 else 1
			Rules.redirect(S, FIRE, dx, rng() - 0.5)
		end
	end,
}
local kinds = { "random", "random", "random", "idle", "chase", "wall" }
local wins, runs, margins = 0, 0, {}
local byKind: { [string]: { number } } = {}
local RUNS = tonumber(process.args[1]) or 50
for run = 1, RUNS do
	local kind = kinds[(run - 1) % #kinds + 1]
	local seed = 7000 + run
	local rng = Rules.Rng.new(seed * 7 + 1)
	local S = Tutor.stage("D", seed)
	Rules.launch(S)
	local bot = TutorBot.new(BOT, FIRE, S.rand, T.botAim, T.keep)
	local final = false
	while not S.done do
		Rules.step(S)
		TutorBot.step(bot, Rules, S)
		players[kind](S, rng)
		for _, ev in Rules.drain(S) do
			final = final or ev.kind == "final"
		end
	end
	runs += 1
	local margin = (S.counts[FIRE] - S.counts[BOT]) / S.area * 100
	table.insert(margins, margin)
	byKind[kind] = byKind[kind] or {}
	table.insert(byKind[kind], math.floor(margin + 0.5))
	if Rules.leader(S) == FIRE then
		wins += 1
	else
		print(`D run {run} ({kind}): lost, fire {S.counts[FIRE]} vs bot {S.counts[BOT]}`)
	end
	check(final, `D run {run}: the whole round is the FINAL`)
	check(math.abs(S.t - T.final) < 0.1, `D run {run}: {T.final} s round`)
end
table.sort(margins)
print(
	string.format(
		"D: %d/%d won, land lead %.0f..%.0f%% (median %.0f%%)",
		wins,
		runs,
		margins[1],
		margins[#margins],
		margins[#margins // 2]
	)
)
for k, list in byKind do
	table.sort(list)
	print(`  {k}: lead % {table.concat(list, " ")}`)
end
check(wins == runs, "D: the player wins every final")

-- 3. Through the server ------------------------------------------------------------------------------------------
local hooked = {}
Tutorial.onDone(function(p, info)
	table.insert(hooked, { name = p.Name, info = info })
end)

type Client = {
	p: any,
	dec: any,
	match: any,
	st: any,
	cues: { any },
	pending: { at: number, f: () -> () },
	react: number,
	misses: number,
	afk: boolean,
	ends: number,
	finish: any,
	results: number,
	win: boolean?,
	startAt: number?,
	endAt: number?,
	modes: { [string]: boolean },
	frame: any,
	gone: boolean,
}
local clients: { Client } = {}

local function action(c: Client, verb: any, arg: any)
	for _, fn in Remotes.Action.OnServerEvent.fns do
		fn(c.p, verb, arg)
	end
end
local function input(c: Client, kind: any, dx: any, dy: any)
	for _, fn in Remotes.Input.OnServerEvent.fns do
		fn(c.p, kind, dx, dy)
	end
end

local function join(id: number, name: string, react: number, misses: number, afk: boolean): Client
	local p = Mock.player(world, id, name)
	local c: Client = {
		p = p,
		dec = Snap.newDecoder(),
		match = nil,
		st = nil,
		cues = {},
		pending = {} :: any,
		react = react,
		misses = misses,
		afk = afk,
		ends = 0,
		finish = nil,
		results = 0,
		win = nil,
		startAt = nil,
		endAt = nil,
		modes = {},
		frame = nil,
		gone = false,
	}
	p.Parent = S_.Players
	S_.Players.PlayerAdded:Fire(p)
	action(c, "hello", nil)
	table.insert(clients, c)
	return c
end

local function later(c: Client, dt: number, f: () -> ())
	table.insert(c.pending :: any, { at = Mock.now() + dt, f = f })
end

local function onCue(c: Client, d: any)
	table.insert(c.cues, d)
	if c.afk or not d.wait then
		return
	end
	if d.k == "tap" then
		later(c, c.react, function()
			action(c, "tut", d.n)
		end)
	elseif d.k == "power" then
		later(c, c.react, function()
			input(c, Net.Input.power)
		end)
	elseif d.k == "dir" then
		later(c, c.react, function()
			local f = c.frame
			local me
			for _, b in (if f then f.balls else {}) do
				if b.e == c.match.you then
					me = b
				end
			end
			if not me then
				return
			end
			local dx, dy = d.x - me.x, d.y - me.y
			if c.misses > 0 then
				-- a tap the other way
				c.misses -= 1
				dx, dy = -dx, -dy
			else
				-- a tap a little off the enemy, as a finger would
				dx, dy = dx + 0.6, dy - 0.4
			end
			input(c, Net.Input.dir, dx, dy)
		end)
	end
end

local function client(c: Client)
	local inbox = c.p._inbox
	c.p._inbox = {}
	for _, m in inbox do
		local a = m.args
		if m.remote == "State" then
			c.st = a[1]
			if a[1].ph == "result" then
				c.results += 1
				c.win = a[1].win
			end
		elseif m.remote == "Match" then
			local kind, data = a[1], a[2]
			if kind == "start" then
				c.match = data
				c.modes[data.mode] = true
				Snap.applyKey(c.dec, data.key)
				c.startAt = c.startAt or Mock.now()
			elseif kind == "tut" then
				onCue(c, data)
			elseif kind == "end" then
				c.ends += 1
				c.finish = data
				c.endAt = Mock.now()
			end
		elseif m.remote == "Snap" then
			local f = Snap.decode(c.dec, a[1])
			if f then
				c.frame = f
			end
		end
	end
	local keep = {}
	for _, q in c.pending :: any do
		if Mock.now() >= q.at then
			q.f()
		else
			table.insert(keep, q)
		end
	end
	c.pending = keep :: any
	-- the final: taps now and then, power when ready
	local f = c.frame
	if not c.afk and c.st and c.st.ph == "match" and f and f.final and math.random() < (1 / 60) / 0.7 then
		local a = math.random() * math.pi * 2
		input(c, Net.Input.dir, math.cos(a), math.sin(a))
		input(c, Net.Input.power)
	end
end

local FRAME = 1 / 60
local function run(seconds: number)
	for _ = 1, math.floor(seconds / FRAME) do
		Mock.advance(FRAME)
		S_.RunService.Heartbeat:Fire(FRAME)
		for _, c in clients do
			if not c.gone then
				client(c)
			end
		end
	end
end

local function cueKeys(c: Client): string
	local out = {}
	for _, d in c.cues do
		table.insert(out, d.s .. ":" .. d.k)
	end
	return table.concat(out, " ")
end

local function noWarnings(what: string)
	for _, w in warns do
		print("WARN: " .. w)
	end
	check(#warns == 0, what .. ": no warnings")
	table.clear(warns)
end

-- a normal new player: reacts in 1 s, misses scene C once
local t0 = Mock.now()
local ann = join(501, "Ann", 1, 1, false)
run(1)
check(
	ann.match and ann.match.mode == "tutor" and ann.match.w == 16,
	"first entry: the tutorial on a duel arena at once"
)
check(ann.st and ann.st.ph == "match" and ann.st.mode == "tutor", "no starter pick, no lobby: State match tutor")
local i = 0
while ann.results == 0 and i < 120 do
	run(1)
	i += 1
end
local seconds = (ann.endAt or 999) - t0
print(
	string.format("server: tutorial of a normal player %.1f s (join to final whistle), cues: %s", seconds, cueKeys(ann))
)
check(seconds <= 90, `tutorial within 90 s ({seconds})`)
check(ann.win == true and ann.finish and ann.finish.winner == FIRE, "the final is won, result screen says win")
local keys = cueKeys(ann)
for _, k in
	{ "A:react", "A:boom", "A:wild", "A:tap", "B:power", "B:grab", "C:dir", "C:miss", "C:go", "C:ko", "D:final" }
do
	check(string.find(keys, k, 1, true), `cue {k}`)
end
check(not string.find(keys, "C:go C:out", 1, true), "a good tap in C is a KO the first time")
check(ann.p:GetAttribute("TutorialDone") == true and Tutorial.isDone(ann.p), "flag TutorialDone set")
check(#hooked == 1 and hooked[1].name == "Ann" and hooked[1].info.first == true, "T2.2 hook onDone called once, first")
run(Config.RESULT_TIME + 1)
-- T2.2: the reward screen, then the plaza
local rw = ann.st
check(rw and rw.ph == "reward", "reward screen after the victory")
check(rw and rw.balls and #rw.balls == 4 and table.find(Config.SPIN_POOL, rw.legend), "reward: 4 balls, a legendary")
check(rw and rw.boost == Config.XP.boostTime, "reward: 15 min of 2x XP")
action(ann, "queue", 1)
run(0.5)
check(ann.st and ann.st.ph == "reward", "no search from the reward screen")
action(ann, "claim")
run(0.5)
check(ann.st and ann.st.ph == "lobby" and ann.st.glow == "play" and ann.st.first == false, "plaza with PLAY lit")
local steps = {}
for _, s in world.analytics.steps do
	if s.player == "Ann" then
		steps[s.n] = true
	end
end
check(steps[1] and steps[2] and steps[3] and steps[4] and steps[5] and steps[6] and steps[7], "funnel steps 1-7")
noWarnings("tutorial")

-- re-join on the same server: straight to the plaza
S_.Players.PlayerRemoving:Fire(ann.p)
ann.p.Parent = nil
ann.gone = true
local ann2 = join(501, "Ann", 1, 0, false)
run(2)
check(ann2.st and ann2.st.ph == "lobby" and ann2.match == nil, "re-join: plaza, no tutorial")
-- HOW TO PLAY: the tutorial again, then the plaza
action(ann2, "tutor")
run(1)
check(ann2.match and ann2.match.mode == "tutor", "HOW TO PLAY starts the tutorial")
i = 0
while ann2.results == 0 and i < 120 do
	run(1)
	i += 1
end
check(ann2.win == true, "replay won")
check(#hooked == 2 and hooked[2].info.first == false, "hook on replay, first = false")
run(Config.RESULT_TIME + 1)
check(ann2.st and ann2.st.ph == "lobby", "replay ends on the plaza")
-- the PLAY glow goes once the player queues
action(ann2, "queue", 1)
run(0.5)
action(ann2, "cancel")
run(0.5)
check(ann2.st and ann2.st.ph == "lobby" and ann2.st.glow == nil, "PLAY glow off after the first search")
noWarnings("replay")

-- an AFK player: the cartoon goes on by itself and ends
local afk = join(502, "Idle", 1, 0, true)
i = 0
while afk.results == 0 and i < 200 do
	run(1)
	i += 1
end
check(afk.results == 1, "AFK player: the tutorial ends by itself")
check(afk.win == true, "AFK player still wins the final")
noWarnings("afk")

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
