--!strict
-- Whole server (src/server) on a mocked Roblox in lune: first entry, duel with two people and with a bot, 4-player
-- match with a leaver, junk input, debug bot matches, and real snapshot traffic per client.
-- lune run tests/flow
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
local Net = load("src/shared/Net/init.luau")
local Snap = Net.Snap
local Remotes = load("src/shared/Net/Remotes.luau")
local S = world.services

local DT = 1 / 60
local nan = 0 / 0

-- Fake clients -------------------------------------------------------------------
type Client = {
	p: any,
	plan: { string },
	st: any,
	dec: any,
	match: any,
	ends: number,
	starts: number,
	hints: { [string]: boolean },
	bytes: number,
	snaps: number,
	window: { [number]: number },
	joinedAt: number,
	firstMatchAt: number?,
	usedAny: boolean,
	gone: boolean,
	leaveAt: number?,
	results: number,
	frames: number,
	loserChose: boolean,
	duelWith: { [string]: boolean },
	leftInMatch: boolean,
	-- W3: own aim vector, the server echo, the first launched frame of the round, hidden frames before launch
	aim: { number },
	echo: { number }?,
	launchSeen: boolean,
	launchOk: number,
	launchBad: number,
	hiddenOk: number,
	hiddenBad: number,
	lastRound: any,
	keepSeen: number,
	keepBad: number,
	keptBall: number?,
	keptOk: number,
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

local nextId = 1
local function join(name: string, plan: { string }, leaveAt: number?): Client
	local p = Mock.player(world, nextId, name)
	nextId += 1
	local c: Client = {
		p = p,
		plan = plan,
		st = nil,
		dec = Snap.newDecoder(),
		match = nil,
		ends = 0,
		starts = 0,
		hints = {},
		bytes = 0,
		snaps = 0,
		window = {},
		joinedAt = Mock.now(),
		firstMatchAt = nil,
		usedAny = false,
		gone = false,
		leaveAt = leaveAt,
		results = 0,
		frames = 0,
		loserChose = false,
		duelWith = {},
		leftInMatch = false,
		aim = if name == "Ann" then { -1, 0.6 } elseif name == "Bob" then { 0.5, 1 } else { 1, 0.5 },
		echo = nil,
		launchSeen = false,
		launchOk = 0,
		launchBad = 0,
		hiddenOk = 0,
		hiddenBad = 0,
		lastRound = nil,
		keepSeen = 0,
		keepBad = 0,
		keptBall = nil,
		keptOk = 0,
	}
	p.Parent = S.Players
	S.Players.PlayerAdded:Fire(p)
	action(c, "hello", nil)
	table.insert(clients, c)
	return c
end

local function leave(c: Client)
	c.leftInMatch = c.st and c.st.ph == "match"
	c.gone = true
	S.Players.PlayerRemoving:Fire(c.p)
	c.p.Parent = nil
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
			end
		elseif m.remote == "Match" then
			local kind, data = a[1], a[2]
			if kind == "start" then
				c.starts += 1
				c.match = data
				check(Snap.applyKey(c.dec, data.key), "key applies")
				check(#c.dec.cells == data.w * data.h, "key size = arena")
				c.firstMatchAt = c.firstMatchAt or Mock.now()
				c.echo = nil
				c.launchSeen = false
				if data.you and data.mode ~= "tutor" then
					check(type(data.aim) == "table" and #data.aim == 2, "start carries own aim")
				end
				if c.keptBall then
					local mine
					for _, seat in data.seats do
						if seat.name == c.p.DisplayName then
							mine = seat.e
						end
					end
					if mine == c.keptBall then
						c.keptOk += 1
					end
					c.keptBall = nil
				end
				if data.mode == "duel" then
					for _, seat in data.seats do
						c.duelWith[seat.name] = true
					end
				end
			elseif kind == "aim" then
				check(c.match and data.id == c.match.id, "aim echo of own match")
				c.echo = { data.dx, data.dy }
			elseif kind == "round" then
				c.lastRound = data
			elseif kind == "hint" then
				c.hints[data.k] = true
			elseif kind == "tut" then
				-- T2.1 tutorial cues; a waiting "tap" cue is answered (POWER and the direction come from the
				-- clicks below)
				c.hints[data.s .. ":" .. data.k] = true
				if data.wait and data.k == "tap" then
					action(c, "tut", data.n)
				end
			elseif kind == "end" then
				c.ends += 1
			end
		elseif m.remote == "Snap" then
			local b = a[1]
			c.bytes += buffer.len(b)
			local sec = math.floor(Mock.now())
			c.window[sec] = (c.window[sec] or 0) + buffer.len(b)
			if buffer.readu8(b, 0) == Snap.FRAME then
				c.snaps += 1
			end
			local f = Snap.decode(c.dec, b)
			if f and c.match then
				if not f.launched then
					local hidden = true
					for _, ball in f.balls do
						if ball.dx ~= 0 or ball.dy ~= 0 then
							hidden = false
						end
					end
					if hidden then
						c.hiddenOk += 1
					else
						c.hiddenBad += 1
					end
				elseif not c.launchSeen and c.match.you and c.echo then
					c.launchSeen = true
					local echo = c.echo :: { number }
					for _, ball in f.balls do
						if ball.e == c.match.you then
							local ok = math.abs(ball.dx - echo[1]) < 0.02 and math.abs(ball.dy - echo[2]) < 0.02
							if ok then
								c.launchOk += 1
							else
								c.launchBad += 1
								print(`launch {c.p.DisplayName}: flies {ball.dx},{ball.dy}, aimed {echo[1]},{echo[2]}`)
							end
						end
					end
				end
			end
		end
	end
	c.frames += 1
	local st = c.st
	if not st then
		return
	end
	local ph = st.ph
	-- junk every frame: the server must drop it silently
	-- (sparse enough to leave room in the rate limits for the real clicks)
	if c.frames % 30 == 0 then
		input(c, nan, nan, nan)
		input(c, 3, nan, 1)
		input(c, 3, "x", {})
		input(c, 99, 1, 1)
	end
	if c.frames % 120 == 0 then
		action(c, "draft", nan)
		action(c, { 1 }, 1)
		action(c, "choose", 99)
	end
	if ph == "pick" and c.frames % 20 == 0 then
		if st.mode == "intro" then
			action(c, "pick", Net.STARTERS[(c.p.UserId % 4) + 1])
		else
			action(c, "pick", st.options[1])
		end
	elseif ph == "draft" and st.turn == st.me and c.frames % 20 == 0 then
		if not c.usedAny and st.any then
			c.usedAny = true
			-- any ball outside the offer
			for e = 0, 26 do
				if
					not table.find(st.offer, e)
					and not table.find(st.teams[1], e)
					and not table.find(st.teams[2], e)
				then
					action(c, "any", e)
					break
				end
			end
		else
			action(c, "draft", st.offer[1])
		end
	elseif ph == "choose" and st.keep and st.keep >= 0 and c.frames % 30 == 0 then
		-- the round winner keeps its ball and has nothing to choose; a choose from it is refused
		c.keepSeen += 1
		local lr = c.lastRound
		local won = lr and lr.win == st.me and st.keep == (if st.me == 0 then lr.a else lr.b)
		if #st.left > 0 or not won then
			c.keepBad += 1
		end
		c.keptBall = st.keep
		for _, e in st.teams[st.me + 1] do
			if e ~= st.keep then
				action(c, "choose", e)
			end
		end
	elseif ph == "choose" and #st.left > 0 and c.frames % 30 == 0 then
		if not st.blind and st.rival >= 0 then
			c.loserChose = true
		end
		action(c, "choose", st.left[1])
	elseif ph == "lobby" and #c.plan > 0 and c.frames % 30 == 0 then
		local mode = table.remove(c.plan, 1)
		action(c, "queue", if mode == "duel" then 1 else 2)
	elseif ph == "match" then
		if c.frames % 10 == 0 then
			input(c, 1, c.aim[1], c.aim[2])
		end
		if c.frames % 40 == 0 then
			input(c, 2, c.aim[1], c.aim[2])
		end
		if c.frames % 3 == 0 then
			input(c, 3, math.cos(c.frames), math.sin(c.frames))
		end
		if c.frames % 5 == 0 then
			input(c, 4)
		end
	end
end

local function run(seconds: number, each: (() -> ())?)
	for _ = 1, math.floor(seconds / DT) do
		Mock.advance(DT)
		S.RunService.Heartbeat:Fire(DT)
		for _, c in clients do
			if not c.gone then
				if c.leaveAt and Mock.now() >= c.leaveAt then
					leave(c)
				else
					client(c)
				end
			end
		end
		if each then
			each()
		end
	end
end

-- Runs until cond() or the time limit; returns the seconds it took.
local function runUntil(limit: number, cond: () -> boolean): number
	local t = Mock.now()
	while Mock.now() - t < limit and not cond() do
		run(1)
	end
	return Mock.now() - t
end

local function noErrors(what: string)
	for _, w in warns do
		print("WARN: " .. w)
	end
	check(#warns == 0, what .. ": no warnings")
	table.clear(warns)
end

-- 1. First entry ----------------------------------------------------------------
local t0 = Mock.now()
local a = join("Ann", { "duel", "ffa" })
local b = join("Bob", { "duel" })
run(16)
check(
	a.firstMatchAt and a.firstMatchAt - t0 <= 15,
	`Ann in the first round within 15 s ({a.firstMatchAt and a.firstMatchAt - t0})`
)
check(a.match and a.match.mode == "tutor" and a.match.w == 16 and a.match.h == 14, "tutorial on a 16x14 duel arena")
check(a.hints["A:react"], "tutorial scene A")
run(60)
check(a.hints["B:grab"] and a.hints["C:ko"] and a.hints["D:final"], "tutorial scenes B (power), C (KO), D (final)")
check(a.ends >= 1 and b.ends >= 1, "tutorials ended")
local steps = {}
for _, s in world.analytics.steps do
	if s.player == "Ann" then
		steps[s.n] = true
	end
end
check(steps[1] and steps[2] and steps[3] and steps[4] and steps[6] and steps[7], "funnel steps 1-4, 6, 7")
noErrors("tutorial")

-- 2. Duel of two people (they queued together after the intro) -------------------
local took = runUntil(400, function()
	return a.ends >= 2 and b.ends >= 2
end)
print(`duel took {math.floor(took)} s`)
check(a.ends >= 2 and b.ends >= 2, `duel finished (Ann {a.ends}, Bob {b.ends})`)
check(a.starts >= 3, "duel had rounds")
check(a.duelWith.Bob and b.duelWith.Ann, "Ann and Bob in one duel (M1-9 with a person)")
check(a.loserChose or b.loserChose, "the loser chose a ball seeing the winner's ball")
check(a.keepSeen + b.keepSeen > 0, "the round winner got the keep screen")
check(a.keepBad + b.keepBad == 0, "keep screen only for the round winner, with its own ball and nothing to choose")
check(a.keptOk + b.keptOk > 0, "the winner played the next round with the kept ball (its choose was refused)")
for _, c in { a, b } do
	check(c.hiddenOk > 0 and c.hiddenBad == 0, `{c.p.DisplayName}: no aim directions in frames before launch`)
	check(c.launchOk > 0 and c.launchBad == 0, `{c.p.DisplayName}: the ball launches where the echoed aim points`)
end
check(steps[8] or (function()
	for _, s in world.analytics.steps do
		if s.player == "Ann" and s.n == 8 then
			return true
		end
	end
	return false
end)(), "funnel step SecondMatch")
noErrors("duel")

-- 3. 4-player match: Ann plus a leaver plus bots; Cid leaves mid-match --------------
local cid = join("Cid", { "ffa" })
runUntil(120, function()
	return cid.st and cid.st.ph == "match" and cid.match and cid.match.mode == "ffa"
end)
run(20)
leave(cid)
runUntil(120, function()
	return a.ends >= 3
end)
check(cid.gone and cid.leftInMatch, "Cid left in the middle of the match")
check(a.ends >= 3, `ffa finished for Ann after Cid left (ends {a.ends})`)
noErrors("ffa with a leaver")

-- 4. Duel of one person against a bot --------------------------------------------
local dan = join("Dan", { "duel" })
runUntil(450, function()
	return dan.ends >= 2
end)
check(dan.ends >= 2, `Dan's duel with a bot finished ({dan.ends})`)
check(dan.duelWith.BOT, "Dan played a bot")
noErrors("duel vs bot")

-- bandwidth seen by clients
local peak, avg, n = 0, 0, 0
for _, c in clients do
	for _, bytes in c.window do
		peak = math.max(peak, bytes)
		avg += bytes
		n += 1
	end
end
print(
	string.format(
		"snap traffic per client: avg %.1f KB/s over active seconds, peak %.1f KB/s",
		avg / math.max(1, n) / 1000,
		peak / 1000
	)
)
check(peak < 20000, "M1-7 under 20 KB/s")

-- 5. Debug bot matches on every arena -------------------------------------------
for _, c in clients do
	if not c.gone then
		leave(c)
	end
end
run(10)
S.ServerScriptService:SetAttribute("DebugBotMatches", true)
local busyMax = 0
run(200, function()
	local busy = #load("src/server/Session.luau").active()
	busyMax = math.max(busyMax, busy)
end)
check(busyMax == 4, `all 4 arenas busy with bot matches ({busyMax})`)
local stats = 0
for _, l in logs do
	if string.find(l, "[BT] stats", 1, true) then
		stats += 1
		if stats <= 3 then
			print(l)
		end
	end
end
check(stats > 0, "stats printed")
noErrors("debug bot matches")

for _, l in logs do
	if string.find(l, "M1-4", 1, true) then
		print(l)
	end
end
print(`{passed} checks passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("FLOW OK")
