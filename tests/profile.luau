--!strict
-- T2.2 profile: schema and migration, XP and levels, level balls only not owned, the spin gives only legendaries of
-- the list, the boost runs out, the store's lock and retries, then the whole server on the mocked Roblox: tutorial ->
-- reward -> plaza, XP of a duel, a server restart (new world, same DataStore) goes straight to the plaza.
-- lune run tests/profile
local process = require("@lune/process")
local Mock = require("./Mock")
local Progress = require("../src/server/Logic/Progress")
local Store = require("../src/server/Store")
local Offers = require("../src/server/Logic/Offers")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- Config.luau is a plain table: load it with the mock loader (no Roblox inside)
local world0 = Mock.world()
local load0 = Mock.loader(world0, {}, {})
local Config = load0("src/server/Config.luau")
local cfg: any = Config
local Rules = load0("src/shared/Rules/init.luau")

local function rng(seed: number): () -> number
	local x = seed * 7919 + 17
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

-- 1. Schema and migration ----------------------------------------------------------------------------------------
do
	local d = Progress.migrate(nil)
	check(d.v == Progress.VERSION and d.level == 1 and d.xp == 0 and #d.balls == 0 and not d.tut, "nil -> new")
	d = Progress.migrate("junk")
	check(d.level == 1 and not d.tut, "junk -> new")
	d = Progress.migrate({
		v = 1,
		tut = true,
		rewarded = true,
		balls = { 0, 1, 1, 99, -3, 2.5, "x", 17 },
		level = 0 / 0,
		xp = -5,
		boostUntil = 123,
		junk = 1,
	})
	check(#d.balls == 3 and d.balls[3] == 17, "balls: duplicates, out of range, non-integers dropped")
	check(d.level == 1 and d.xp == 0 and d.boostUntil == 123, "NaN level and negative xp fixed")
	check((d :: any).junk == nil, "unknown keys dropped")
	d = Progress.migrate({ done = true, owned = { 5 }, level = 3 })
	check(d.v == Progress.VERSION and d.tut and d.rewarded and d.level == 3 and d.balls[1] == 5, "v0 record migrates")
	Progress.repair(d, cfg)
	check(Progress.owns(d, 0) and Progress.owns(d, 2) and #d.balls == 5, "repair: done tutorial has the starters")
	d = Progress.migrate({ v = 7, tut = true, level = 4, newField = {} })
	check(d.tut and d.level == 4 and d.v == Progress.VERSION, "newer schema read field by field")
	local s = Progress.migrate(Progress.new())
	check(s.level == 1 and s.v == Progress.VERSION, "new survives a round trip")
end

-- 2. XP and levels ------------------------------------------------------------------------------------------------
do
	local X = cfg.XP
	check(Progress.matchXp({ win = false, kills = 0, rx = 0 }, cfg) == X.play, "taking part")
	check(Progress.matchXp({ win = true, kills = 0, rx = 0 }, cfg) == X.play + X.win, "win")
	check(Progress.matchXp({ win = false, kills = 100, rx = 100 }, cfg) == X.play + X.koMax + X.reactMax, "caps")
	check(Progress.need(1, cfg) == X.base and Progress.need(3, cfg) == X.base + 2 * X.step, "need per level")
	-- matches to level 2 with the boost: wins half the time, 3 reactions and 1 KO a match
	local counts = {}
	for seed = 1, 200 do
		local r = rng(seed)
		local d = Progress.new()
		Progress.tutorialReward(d, 1000, cfg, r)
		local n = 0
		while d.level < 2 do
			n += 1
			Progress.award(
				d,
				{ win = r() < 0.5, kills = if r() < 0.5 then 1 else 0, rx = math.floor(r() * 6) },
				1000 + n * 120,
				cfg,
				r
			)
		end
		counts[n] = (counts[n] or 0) + 1
	end
	local parts = {}
	for n = 1, 6 do
		if counts[n] then
			table.insert(parts, `{n}: {counts[n]}`)
		end
	end
	print("matches to level 2 with 2x XP (of 200): " .. table.concat(parts, ", "))
	check((counts[2] or 0) + (counts[3] or 0) >= 180 and not counts[1], "level 2 after 2-3 matches")
	-- without the boost
	local d = Progress.new()
	local n = 0
	while d.level < 2 do
		n += 1
		Progress.award(d, { win = n % 2 == 0, kills = 1, rx = 3 }, 0, cfg, rng(1))
	end
	print(`matches to level 2 without the boost: {n}`)
	check(n >= 3 and n <= 6, "without the boost level 2 takes longer")
end

-- 3. Levels give only balls not owned yet -------------------------------------------------------------------------
do
	local allowed = {}
	for _, t in cfg.LEVEL_TIERS do
		for _, e in cfg.TIERS[t] do
			allowed[e] = true
		end
	end
	local bad = 0
	for seed = 1, 300 do
		local r = rng(seed)
		local d = Progress.new()
		local rw = Progress.tutorialReward(d, 0, cfg, r) :: any
		local before = #d.balls
		local got = {}
		for _ = 1, 40 do
			local ups = Progress.addXp(d, 300 + math.floor(r() * 400), cfg, r)
			for _, u in ups do
				if u.e then
					if got[u.e] or table.find(cfg.BASE_BALLS, u.e) or u.e == rw.legend or not allowed[u.e] then
						bad += 1
					end
					got[u.e] = true
				end
				if u.level <= cfg.LEVEL_BALLS and u.e == nil then
					bad += 1
				end
				if u.level > cfg.LEVEL_BALLS and u.e ~= nil then
					bad += 1
				end
			end
		end
		local seen = {}
		for _, e in d.balls do
			if seen[e] then
				bad += 1
			end
			seen[e] = true
		end
		if #d.balls ~= before + cfg.LEVEL_BALLS - 1 then
			bad += 1
		end
	end
	check(bad == 0, `levels 2-{cfg.LEVEL_BALLS}: one new ball each, never owned, never legendary ({bad} bad)`)
	-- a full collection of level tiers: the level gives nothing
	local d = Progress.new()
	for _, t in cfg.LEVEL_TIERS do
		for _, e in cfg.TIERS[t] do
			table.insert(d.balls, e)
		end
	end
	local ups = Progress.addXp(d, Progress.need(1, cfg), cfg, rng(3))
	check(#ups == 1 and ups[1].level == 2 and ups[1].e == nil, "nothing left to give: level without a ball")
	local tiers = 0
	for _, list in cfg.TIERS do
		tiers += #list
	end
	check(tiers == Rules.Config.NEL, "tiers cover all 27 balls")
end

-- 4. The spin gives only legendaries of the list, once ------------------------------------------------------------
do
	local hits = {}
	local bad = 0
	local r = rng(7)
	for _ = 1, 8000 do
		local d = Progress.new()
		local rw = Progress.tutorialReward(d, 0, cfg, r)
		if
			not rw
			or not table.find(cfg.SPIN_POOL, rw.legend)
			or not Progress.owns(d, rw.legend)
			or not table.find(cfg.TIERS.legendary, rw.legend)
		then
			bad += 1
		else
			hits[rw.legend] = (hits[rw.legend] or 0) + 1
		end
	end
	check(bad == 0, "spin: only balls of SPIN_POOL, all legendary")
	local fair = true
	for _, e in cfg.SPIN_POOL do
		local k = (hits[e] or 0) / 8000
		if k < 0.22 or k > 0.28 then
			fair = false
		end
	end
	check(fair, "spin: each legendary about 1 in 4")
	check(not table.find(cfg.SPIN_POOL, 13), "Void is not in the spin (7th day)")
	local d = Progress.new()
	local first = Progress.tutorialReward(d, 0, cfg, r)
	check(first and #d.balls == 5, "reward: 4 starters + 1 legendary")
	check(Progress.tutorialReward(d, 10, cfg, r) == nil and #d.balls == 5, "reward only once")
	local owned = Progress.new()
	owned.balls = { 17, 16, 20 }
	check(Progress.spin(owned, cfg, r) == 25, "spin prefers a legendary not owned")
end

-- 5. The boost runs out ------------------------------------------------------------------------------------------
do
	local d = Progress.new()
	Progress.tutorialReward(d, 1000, cfg, rng(1))
	check(Progress.boostLeft(d, 1000) == cfg.XP.boostTime, "15 min of boost")
	check(Progress.mult(d, 1000 + 899, cfg) == 2, "2x before the end")
	check(Progress.mult(d, 1000 + 900, cfg) == 1 and Progress.boostLeft(d, 1900) == 0, "1x after 15 min")
	local s = { win = true, kills = 0, rx = 0 }
	local a = Progress.award(d, s, 1100, cfg, rng(1))
	local b = Progress.award(d, s, 2000, cfg, rng(1))
	check(a.xp == 2 * b.xp and a.mult == 2 and b.mult == 1, "XP doubled while boosted")
end

-- 6. Store: lock, take over, retries, memory fallback -------------------------------------------------------------
do
	local t = 0
	local function now()
		return t
	end
	local function wait(s: number)
		t += s
	end
	local warns = {}
	local function warn(s: string)
		table.insert(warns, s)
	end
	local ds = world0.game:GetService("DataStoreService"):GetDataStore("T")
	local scfg = { lockTtl = 600, lockWait = 15, retries = 4 }
	local A = Store.new(ds, "A", scfg, now, wait, warn)
	local B = Store.new(ds, "B", scfg, now, wait, warn)
	local ok, data = Store.load(A, "u1")
	check(ok and data == nil, "new key: nothing stored")
	check(Store.save(A, "u1", { level = 2 }, false), "save")
	t = 100
	local ok2, data2 = Store.load(B, "u1")
	check(ok2 and data2 and data2.level == 2, "B takes over after waiting")
	check(t >= 100 + 15, "B waited for A's lock")
	local okA, lost = Store.save(A, "u1", { level = 1 }, false)
	check(okA and lost, "A lost the lock: nothing written")
	check(ds.data.u1.data.level == 2, "A's stale data did not overwrite")
	Store.save(B, "u1", { level = 3 }, true)
	check(ds.data.u1.lock == nil, "release lets the lock go")
	local t0 = t
	local ok3, d3 = Store.load(A, "u1")
	check(ok3 and d3.level == 3 and t == t0, "released: loads at once")
	-- a dead server's lock
	ds.data.u2 = { data = { level = 5 }, lock = { s = "dead", t = t - 700 }, saved = 0 }
	t0 = t
	local ok4, d4 = Store.load(A, "u2")
	check(ok4 and d4.level == 5 and t == t0, "a lock older than lockTtl is taken at once")
	-- retries
	ds.failNext = 2
	check(Store.save(A, "u2", { level = 6 }, false) and ds.data.u2.data.level == 6, "2 failures then saved")
	ds.failNext = 10
	local okF = Store.save(A, "u2", { level = 7 }, false)
	check(not okF and ds.data.u2.data.level == 6, "gives up after retries, nothing written")
	ds.failNext = 0
	-- legacy record without the wrapper
	ds.data.u3 = { v = 1, tut = true, level = 4 }
	local ok5, d5 = Store.load(A, "u3")
	check(ok5 and d5.level == 4 and d5.tut, "old record without the wrapper")
	-- Studio without API access: memory, one warning
	local studio = {
		UpdateAsync = function()
			error(
				"502: API Services rejected request with error. Error code: 0 Reason: Studio access to APIs is not allowed."
			)
		end,
	}
	table.clear(warns)
	local M = Store.new(studio, "M", scfg, now, wait, warn)
	check(Store.save(M, "u9", { level = 8 }, true), "memory save")
	local ok6, d6 = Store.load(M, "u9")
	check(ok6 and d6.level == 8 and M.memory, "memory load")
	check(#warns == 1 and string.find(warns[1], "Studio Access", 1, true), "one clear warning")
end

-- 7. Offers: a newcomer drafts from the own 5 balls, the bot leaves them alone ------------------------------------
do
	local own = { 0, 1, 3, 2, 17 }
	local bad, topped = 0, 0
	for seed = 1, 300 do
		local r = rng(seed)
		local o = Offers.new(Rules, r() < 0.5, 3, { 1, 3 }, r, { own, nil })
		while not Offers.done(o) do
			local side = Offers.turn(o)
			if side == 0 then
				for _, e in o.offer do
					if not table.find(own, e) then
						bad += 1
					end
				end
				Offers.pick(o, 0, o.offer[1])
			else
				for _, e in o.offer do
					if table.find(own, e) then
						topped += 1
					end
				end
				Offers.bot(o)
			end
		end
		local mine = Offers.teams(o)[1]
		check(#mine == 3, "three picks")
	end
	check(bad == 0, "the newcomer is offered only own balls")
	check(topped == 0, "the bot never takes the newcomer's balls")
	local o = Offers.new(Rules, false, 3, { 1, 1 }, rng(2), { own, nil })
	check(not Offers.any(o, 0, 9), "any ball: not a ball outside the collection")
	check(Offers.any(o, 0, 17), "any ball: one of the collection")
	-- two newcomers with the same 5: the side short of own balls gets the rest from all
	local b = Offers.new(Rules, false, 3, { 1, 1 }, rng(4), { own, own })
	local short = 0
	while not Offers.done(b) do
		local side = Offers.turn(b)
		check(#b.offer == 3, "an offer of 3 even when short")
		if not table.find(own, b.offer[1]) then
			short += 1
		end
		Offers.pick(b, side, b.offer[1])
	end
	check(short > 0, "short side gets balls from all")
end

-- 7b. The next level ball is chosen ahead: shown = given, saved, none after the last level ball --------------------
do
	local allowed = {}
	for _, t in cfg.LEVEL_TIERS do
		for _, e in cfg.TIERS[t] do
			allowed[e] = true
		end
	end
	local d0 = Progress.migrate({ v = 2, nextBall = 99 })
	check(d0.nextBall == nil, "nextBall out of range is dropped")
	d0 = Progress.migrate({ v = 2, nextBall = 2.5 })
	check(d0.nextBall == nil, "nextBall fractional is dropped")
	d0 = Progress.migrate({ v = 1, level = 3 })
	check(d0.nextBall == nil, "an older record has no nextBall until planned")
	local bad, shown = 0, {}
	for seed = 1, 200 do
		local r = rng(seed)
		local d = Progress.new()
		Progress.tutorialReward(d, 0, cfg, r)
		local seen = {}
		for lv = 2, cfg.LEVEL_BALLS do
			local nb = d.nextBall
			if nb == nil or Progress.owns(d, nb) or not allowed[nb] then
				bad += 1
			end
			-- saved and loaded between two level ups: the same ball comes
			if seed % 2 == 0 then
				local copy = Progress.migrate(Progress.migrate(d))
				if copy.nextBall ~= nb then
					bad += 1
				end
				d = copy
			end
			local ups = Progress.addXp(d, Progress.need(d.level, cfg), cfg, r)
			if #ups ~= 1 or ups[1].e ~= nb or not Progress.owns(d, nb :: number) or seen[nb :: number] then
				bad += 1
			end
			seen[nb :: number] = true
			shown[nb :: number] = true
		end
		if d.nextBall ~= nil then
			bad += 1
		end
		-- levels after the last level ball: still none, and coins instead
		Progress.addXp(d, Progress.need(d.level, cfg), cfg, r)
		if d.nextBall ~= nil then
			bad += 1
		end
	end
	check(bad == 0, `level ball: given = shown ahead, never owned, saved, nil after level {cfg.LEVEL_BALLS} ({bad})`)
	local n = 0
	for _ in shown do
		n += 1
	end
	check(n >= 15, `different players get different balls over seeds ({n} distinct)`)
	-- several level ups in one go: each gets its own planned ball, in order
	local r = rng(5)
	local d = Progress.new()
	Progress.tutorialReward(d, 0, cfg, r)
	local first = d.nextBall
	local ups = Progress.addXp(d, 100000, cfg, r)
	check(#ups >= 8 and ups[1].e == first, "a big XP gain: the first level gives the shown ball")
	check(d.level > cfg.LEVEL_BALLS and d.nextBall == nil, "past the last level ball the field is empty")
	-- a ball that became owned by other ways is not promised any more
	local d2 = Progress.new()
	Progress.tutorialReward(d2, 0, cfg, rng(9))
	local was = d2.nextBall :: number
	table.insert(d2.balls, was)
	Progress.plan(d2, cfg, rng(10))
	check(d2.nextBall ~= nil and d2.nextBall ~= was and not Progress.owns(d2, d2.nextBall), "owned pick is replaced")
	Progress.giveAll(d2, cfg, rng(11))
	check(#d2.balls == 27 and d2.nextBall == nil, "giveAll: 27 balls, nothing left to show")
end

-- 8. The whole server: tutorial -> reward -> plaza -> duel XP -> restart -> plaza --------------------------------
type Client = { p: any, st: any, prof: any, profs: number, news: { any }, answered: any, afk: boolean? }

local function server(stores: any?)
	local world = Mock.world()
	if stores then
		for name, st in stores do
			local live = world.game:GetService("DataStoreService"):GetDataStore(name)
			live.data = st.data
		end
	end
	local logs, warns = {}, {}
	local load = Mock.loader(world, logs, warns)
	load("src/server/init.server.luau")
	local Remotes = load("src/shared/Net/Remotes.luau")
	local clients: { Client } = {}
	local DT = 1 / 30
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
	local function drive(c: Client)
		for _, m in c.p._inbox do
			local a = m.args
			if m.remote == "State" then
				c.st = a[1]
			elseif m.remote == "Profile" then
				c.prof = a[1]
				c.profs += 1
				if a[1].news then
					table.insert(c.news, a[1].news)
				end
			elseif m.remote == "Match" and a[1] == "start" and a[2].mode ~= "tutor" and not a[2].view and not c.afk then
				-- a real player: LAUNCH in every round (no input in a round = AFK, no XP or coins)
				input(c, 2)
			elseif m.remote == "Match" and a[1] == "tut" and a[2].wait then
				local d = a[2]
				if d.k == "tap" then
					action(c, "tut", d.n)
				elseif d.k == "power" then
					input(c, 4)
				elseif d.k == "dir" then
					input(c, 3, d.x - d.fx, d.y - d.fy)
				end
			end
		end
		table.clear(c.p._inbox)
		local st = c.st
		if not st or c.answered == st then
			return
		end
		if st.ph == "draft" and st.turn == st.me and st.offer and #st.offer > 0 then
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
			world.services.RunService.Heartbeat:Fire(DT)
			for _, c in clients do
				drive(c)
			end
		end
	end
	local function join(id: number, name: string): Client
		local p = Mock.player(world, id, name)
		local c: Client = { p = p, st = nil, prof = nil, profs = 0, news = {}, answered = nil }
		p.Parent = world.services.Players
		world.services.Players.PlayerAdded:Fire(p)
		action(c, "hello", nil)
		table.insert(clients, c)
		return c
	end
	local function leave(c: Client)
		world.services.Players.PlayerRemoving:Fire(c.p)
		c.p.Parent = nil
		local i = table.find(clients, c)
		if i then
			table.remove(clients, i)
		end
	end
	return {
		config = load("src/server/Config.luau"),
		world = world,
		logs = logs,
		warns = warns,
		join = join,
		leave = leave,
		run = run,
		action = action,
	}
end

do
	local s1 = server(nil)
	local c = s1.join(701, "Neo")
	s1.run(1)
	check(c.prof and c.prof.level == 1 and #c.prof.balls == 0, "new player: level 1, no balls yet")
	check(c.st and c.st.ph == "match" and c.st.mode == "tutor", "new player: the tutorial")
	local i = 0
	while (not c.st or c.st.ph ~= "reward") and i < 150 do
		s1.run(1)
		i += 1
	end
	check(c.st and c.st.ph == "reward", "the reward screen after the tutorial")
	check(c.prof and #c.prof.balls == 5 and c.prof.boostEnds ~= nil, "profile: 5 balls and the boost")
	local legend = c.st and c.st.legend
	check(legend and table.find(c.prof.balls, legend), "the legendary of the spin is owned")
	s1.action(c, "claim")
	s1.run(0.5)
	check(c.st and c.st.ph == "lobby" and c.st.glow == "play", "plaza with PLAY lit")
	local ds = s1.world.stores[cfg.PROFILE.store]
	s1.run(cfg.PROFILE.writeGap + 1)
	local rec = ds and ds.data["u701"]
	check(rec and rec.data.tut and #rec.data.balls == 5, "reward saved soon (before leaving)")
	-- a duel against a bot: draft from own balls, XP on the result screen
	s1.action(c, "queue", 1)
	s1.run(0.5)
	check(c.st and c.st.ph == "queue" and c.st.glow == nil, "search")
	local own = true
	local xp = nil
	-- a duel lasts until one side loses all 3 balls: 3..5 rounds of up to ~50 s each, decided by unseeded random.
	-- A 5-round duel ends after ~250 s, so the old 200 s budget flaked; 600 s covers the longest duel.
	i = 0
	while i < 1200 do
		s1.run(0.5)
		i += 1
		local st = c.st
		if st and st.ph == "draft" then
			if not st.own or #st.own ~= 5 then
				own = false
			end
			for _, e in st.offer or {} do
				if not table.find(c.prof.balls, e) then
					own = false
				end
			end
		end
		if st and st.ph == "result" then
			xp = st.xp
			break
		end
	end
	check(own, "draft: own field and offers from the 5 balls")
	check(xp and xp >= 2 * cfg.XP.play and c.st.xpMult == 2, `result: boosted XP ({xp})`)
	check(c.prof and (c.prof.xp > 0 or c.prof.level > 1), "profile XP grew")
	-- M3.1: coins of the duel on the result and in the profile, analytics flows
	local won = c.st.win
	local coins = c.st.coins
	check(coins and coins >= (if won then 50 else 25), `result: duel coins ({coins})`)
	-- the profile also has the book's coins (new reactions) and quests done
	local extra = 25 * #(c.prof.book or {})
	for _, q in c.prof.quests.list do
		extra += if q.done then q.coins else 0
	end
	check(c.prof.coins == coins + extra and c.p:GetAttribute("Coins") == c.prof.coins, "profile coins: match + book")
	local eco = s1.world.analytics.economy
	check(
		#eco > 0 and eco[1].flow == "Source" and eco[1].cur == "Coins" and eco[1].sku == "match_duel",
		"economy event"
	)
	check(c.prof.quests and #c.prof.quests.list == 3 and c.prof.daily and c.prof.daily.ready, "view: quests, daily")
	-- the login reward: Action daily, once
	local before = c.prof.coins
	s1.action(c, "daily")
	s1.run(0.1)
	check(c.prof.coins == before + 50 and c.prof.claim and c.prof.claim.pos == 1, "daily: day 1, +50 coins")
	check(not c.prof.daily.ready and c.prof.daily.n == 1, "daily: claimed today")
	s1.action(c, "daily")
	s1.run(0.1)
	check(c.prof.coins == before + 50, "daily: twice a day pays once")
	local login = false
	for _, e in s1.world.analytics.custom do
		login = login or (e.name == "LoginDay" and e.value == 1)
	end
	check(login, "analytics LoginDay")
	-- AFK in a 4-player match: no coins, no XP
	s1.run(cfg.RESULT_TIME + 2)
	c.afk = true
	local xpBefore, lvBefore, coinsBefore = c.prof.xp, c.prof.level, c.prof.coins
	s1.action(c, "queue", 2)
	i = 0
	local afkSt = nil
	while i < 800 do
		s1.run(0.5)
		i += 1
		if c.st and c.st.ph == "result" then
			afkSt = c.st
			break
		end
	end
	check(afkSt and afkSt.afk == true and afkSt.coins == 0 and afkSt.xp == 0, "AFK match: no coins, no XP")
	check(c.prof.coins == coinsBefore and c.prof.xp == xpBefore and c.prof.level == lvBefore, "AFK: profile same")
	c.afk = false
	-- debug XP: level 2 gives a new ball
	local shownBall = c.prof.nextBall
	check(shownBall ~= nil and not table.find(c.prof.balls, shownBall), "the profile view shows a next ball not owned")
	s1.world.services.ServerScriptService:SetAttribute("DebugXp", 400)
	s1.run(0.2)
	local news = c.news[#c.news]
	check(news and news[1].e == shownBall, "server: the ball given at level 2 is the one shown before")
	check(c.prof.nextBall ~= nil and c.prof.nextBall ~= shownBall, "server: after the level up the next one is shown")
	check(news and news[1].level == 2 and news[1].e ~= nil, "level 2: NEW BALL news")
	check(c.prof and #c.prof.balls >= 6, "6 balls after level 2")
	-- next ball: the server shows it, level 2 gives exactly it (shown = given), then a new one is shown
	-- (checked on a fresh profile in the dev test below; here the profile is past level 2)
	check(c.prof and (c.prof.nextBall == nil or not table.find(c.prof.balls, c.prof.nextBall)), "nextBall not owned")
	-- DEV: ALL BALLS: refused on a live server for a stranger, allowed for the owner, a listed id, and in Studio
	local rs = s1.world.services.RunService
	rs.studio = false
	check(c.prof.dev == nil, "a stranger gets no dev flag")
	s1.action(c, "devballs", nil)
	s1.run(0.2)
	check(#c.prof.balls < 27, "dev request of a stranger is refused")
	table.insert(s1.config.DEV_USERS, 701)
	s1.action(c, "devballs", nil)
	s1.run(0.2)
	check(#c.prof.balls == 27 and c.prof.dev == true and c.prof.nextBall == nil, "DEV_USERS: all 27 balls, flag set")
	table.remove(s1.config.DEV_USERS)
	do
		local s3 = server()
		local owner = s3.join(900001, "Owner")
		s3.run(1)
		check(owner.prof and owner.prof.dev == true, "the place owner gets the dev flag")
		local other = s3.join(702, "Other")
		s3.run(1)
		s3.action(other, "devballs", nil)
		s3.run(0.2)
		check(other.prof and other.prof.dev == nil and #other.prof.balls < 27, "others: no flag, request refused")
		s3.world.services.RunService.studio = true
		s3.action(other, "devballs", nil)
		s3.run(0.2)
		check(#other.prof.balls == 27, "Studio: allowed")
	end
	local level, balls = c.prof.level, #c.prof.balls
	s1.run(cfg.RESULT_TIME + 2)
	s1.leave(c)
	s1.run(0.5)
	local saved = ds.data["u701"]
	check(saved and saved.lock == nil and saved.data.level == level, "saved and released on leave")

	-- server restart: same DataStore, a new world
	local s2 = server(s1.world.stores)
	local c2 = s2.join(701, "Neo")
	s2.run(1)
	check(c2.st and c2.st.ph == "lobby" and c2.st.glow == nil, "re-join: straight to the plaza, PLAY not lit (played)")
	check(c2.prof and c2.prof.level == level and #c2.prof.balls == balls, "level and collection survive")
	check(c2.prof and c2.prof.boostEnds ~= nil, "boost survives")
	-- BindToClose saves
	s2.world.services.ServerScriptService:SetAttribute("DebugXp", 10)
	s2.run(0.1)
	for _, fn in s2.world.closers do
		fn()
	end
	local after = s2.world.stores[cfg.PROFILE.store].data["u701"]
	check(after and after.data.xp == c2.prof.xp, "BindToClose saved the last XP")
	for _, w in s1.warns do
		print("warn: " .. w)
	end
	check(#s1.warns == 0 and #s2.warns == 0, "no warnings")
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("PROFILE OK")
