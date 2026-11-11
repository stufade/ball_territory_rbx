--!strict
-- M3.1 economy, pure: profile v1 -> v2 migration, XP cap and level 10+ pay, match coins (AFK, friend limit, x2,
-- streak), login reward by UTC days (no reset on a missed day, VOID on the 7th), daily quests (reset at 00:00 UTC,
-- all-done bonus once), the reaction book (no duplicates, crystals every 10, all 42), analytics flows.
-- lune run tests/economy
local process = require("@lune/process")
local Mock = require("./Mock")
local Award = require("../src/server/Logic/Award")
local Book = require("../src/server/Logic/Book")
local Daily = require("../src/server/Logic/Daily")
local Earn = require("../src/server/Logic/Earn")
local Progress = require("../src/server/Logic/Progress")
local Wallet = require("../src/server/Logic/Wallet")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local load = Mock.loader(Mock.world(), {}, {})
local cfg: any = load("src/server/Config.luau")
local Rules = load("src/shared/Rules/init.luau")
local E = cfg.ECON
local NAMES: { string } = Rules.Config.REACTIONS

local function rng(seed: number): () -> number
	local x = seed * 7919 + 17
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

local DAY = 86400
-- 2026-11-10 12:00 UTC
local NOW = 20402 * DAY + 12 * 3600

local function sum(log: { Wallet.Flow }, cur: string): number
	local n = 0
	for _, f in log do
		if f.cur == cur then
			n += if f.sink then -f.n else f.n
		end
	end
	return n
end

-- 1. Migration v1 -> v2 --------------------------------------------------------------------------------------------
do
	local v1 = {
		v = 1,
		tut = true,
		rewarded = true,
		played = true,
		balls = { 0, 1, 3, 2, 17, 23 },
		level = 6,
		xp = 120,
		boostUntil = 5000,
		matches = 14,
		wins = 8,
	}
	local d = Progress.migrate(v1)
	check(d.v == 2 and Progress.VERSION == 2, "v1 -> v2: version")
	check(d.level == 6 and d.xp == 120 and #d.balls == 6 and d.matches == 14 and d.wins == 8, "v1 -> v2: M2 kept")
	check(d.tut and d.rewarded and d.played and d.boostUntil == 5000, "v1 -> v2: flags kept")
	check(d.coins == 0 and d.crystals == 0 and d.loginDays == 0 and d.dailyClaimed == -1, "v1 -> v2: wallet, login")
	check(d.streak == 0 and #d.book == 0 and d.quests.day == -1 and #d.quests.list == 0, "v1 -> v2: quests, book")
	check(d.pity.coins == 0 and d.pity.crystals == 0 and d.starterSeen == 0 and d.starterUntil == 0, "v1 -> v2: pity")
	check(d.trialsUsed.n == 0 and d.trialBonus == 0 and d.dailyBall.e == -1 and d.friend.n == 0, "v1 -> v2: rest")
	-- a v2 record round trip, and junk in v2 fields
	d.coins, d.crystals, d.loginDays, d.dailyClaimed, d.streak = 1234, 56, 9, 20400, 4
	d.book = { "WILDFIRE", "STEAM" }
	d.quests = { day = 20402, list = { { id = "play3", n = 2, done = false } }, all = false }
	d.friend = { day = 20402, n = 3 }
	local back = Progress.migrate(d)
	check(back.coins == 1234 and back.crystals == 56 and back.loginDays == 9 and back.dailyClaimed == 20400, "v2 trip")
	check(#back.book == 2 and back.quests.list[1].n == 2 and back.friend.n == 3 and back.streak == 4, "v2 trip: rest")
	local junk = Progress.migrate({
		v = 2,
		coins = -5,
		crystals = 0 / 0,
		book = { "WILDFIRE", "WILDFIRE", 7, "NOT A REACTION" },
		quests = { day = "x", list = { { id = "nope", n = 3 }, "x", { id = "rx10", n = -1 } } },
		pity = "x",
		streak = math.huge,
	})
	check(junk.coins == 0 and junk.crystals == 0 and junk.streak == 0 and junk.pity.coins == 0, "v2 junk: numbers")
	check(#junk.book == 2, "v2 junk: book duplicates and non-strings dropped")
	Progress.repair(junk, cfg, NAMES)
	check(#junk.book == 1 and junk.book[1] == "WILDFIRE", "repair: unknown reactions dropped")
	check(#junk.quests.list == 1 and junk.quests.list[1].id == "rx10" and junk.quests.list[1].n == 0, "repair: quests")
end

-- 2. XP cap and levels 10+ -----------------------------------------------------------------------------------------
do
	check(Progress.need(1, cfg) == 150 and Progress.need(9, cfg) == 950, "need: 150 + 100 (L - 1)")
	check(Progress.need(10, cfg) == 1050 and Progress.need(11, cfg) == 1100, "need: 10 -> 1050, 11 -> cap")
	check(Progress.need(50, cfg) == E.XP_CAP, "need: flat at the cap")
	local total = 0
	for l = 1, 19 do
		total += Progress.need(l, cfg)
	end
	check(total == 15900, `XP to level 20 = 15 900 (docs/economy.md), got {total}`)
	local d = Progress.new()
	d.level = cfg.LEVEL_BALLS
	local log = {}
	local ups = Progress.addXp(d, Progress.need(9, cfg), cfg, rng(1), log)
	check(#ups == 1 and ups[1].level == 10 and ups[1].e == nil and ups[1].coins == 150, "level 10: 150 coins")
	check(ups[1].crystals == 15 and d.crystals == 15, "level 10: every 5th also 15 crystals")
	ups = Progress.addXp(d, Progress.need(10, cfg), cfg, rng(1), log)
	check(ups[1].level == 11 and ups[1].coins == 150 and ups[1].crystals == nil, "level 11: coins only")
	check(d.coins == 300 and sum(log, "coins") == 300 and log[1].why == "level_10", "level pay in the log")
	-- many levels at once
	local x = 0
	for l = 11, 19 do
		x += Progress.need(l, cfg)
	end
	ups = Progress.addXp(d, x, cfg, rng(1), log)
	check(#ups == 9 and d.level == 20 and d.coins == 300 + 9 * 150 and d.crystals == 45, "levels 12..20 at once")
end

-- 3. Match coins: modes, caps, AFK, friend limit, x2, streak -----------------------------------------------------------
do
	local C = E.COINS
	local function m(mode: string, win: boolean, kills: number, rx: number): Earn.Match
		return { mode = mode, win = win, kills = kills, rx = rx, afk = false, friend = false, pass2x = false }
	end
	check(Earn.base(m("duel", false, 0, 0), C) == 25 and Earn.base(m("duel", true, 0, 0), C) == 50, "duel 25 +25")
	check(Earn.base(m("ffa", false, 0, 0), C) == 11 and Earn.base(m("ffa", true, 0, 0), C) == 26, "ffa 11 +15")
	check(Earn.base(m("duel", false, 1, 2), C) == 25 + 3 + 4, "KO 3, reaction 2")
	check(Earn.base(m("duel", false, 100, 100), C) == 25 + 9 + 10, "caps: KO 9, reactions 10")
	local d = Progress.new()
	local log = {}
	local afk = m("duel", true, 3, 5)
	afk.afk = true
	d.streak = 2
	local c = Earn.match(d, afk, NOW, E, log)
	check(c.coins == 0 and c.afk and d.coins == 0 and #log == 0, "AFK: no coins")
	check(d.streak == 2, "AFK: the streak stays")
	-- friend: +25 %, first 20 matches of the UTC day
	local f = m("duel", false, 0, 0)
	f.friend = true
	local paid = 0
	for _ = 1, 25 do
		local r = Earn.match(d, f, NOW, E, log)
		if r.friend then
			paid += 1
			check(r.coins == 31, "friend: 25 * 1.25 = 31")
		end
	end
	check(paid == E.FRIEND.daily, `friend bonus: {E.FRIEND.daily} matches a day, got {paid}`)
	check(Earn.match(d, f, NOW + 12 * 3600, E, log).friend, "friend bonus again after 00:00 UTC")
	local x2 = m("ffa", true, 0, 0)
	x2.pass2x = true
	check(Earn.match(d, x2, NOW, E, log).coins == 52, "x2 pass: 26 * 2")
	-- streak 3 / 5 / 10, once per step of the streak; a loss resets
	d = Progress.new()
	log = {}
	local streak = {}
	for i = 1, 11 do
		local r = Earn.match(d, m("duel", true, 0, 0), NOW, E, log)
		streak[i] = r.streakCoins
	end
	check(streak[3] == 50 and streak[5] == 100 and streak[10] == 300, "streak pays 50 / 100 / 300")
	check(streak[1] == 0 and streak[4] == 0 and streak[11] == 0, "streak pays only at the steps")
	check(d.streak == 11 and d.coins == 11 * 50 + 450, "streak coins added")
	Earn.match(d, m("duel", false, 0, 0), NOW, E, log)
	check(d.streak == 0, "a lost duel resets the streak")
	local r = Earn.match(d, m("ffa", true, 0, 0), NOW, E, log)
	check(d.streak == 0 and r.streakCoins == 0, "4-player wins do not count for the streak")
	for _ = 1, 3 do
		r = Earn.match(d, m("duel", true, 0, 0), NOW, E, log)
	end
	check(r.streakCoins == 50, "a new streak pays the 3rd win again")
end

-- 4. Login reward: UTC days, no reset, VOID on the 7th ---------------------------------------------------------------
do
	local d = Progress.new()
	local log = {}
	local midnight = (NOW // DAY + 1) * DAY
	check(Daily.ready(d, NOW), "new profile: the login reward is ready")
	local c = Daily.claim(d, NOW, E, log) :: Daily.Claim
	check(c and c.pos == 1 and d.coins == 50, "day 1: 50 coins")
	check(Daily.claim(d, NOW + 3600, E, log) == nil, "one claim a day")
	check(Daily.claim(d, midnight - 1, E, log) == nil, "23:59:59 UTC: still today")
	c = Daily.claim(d, midnight, E, log) :: Daily.Claim
	check(c and c.pos == 2 and d.coins == 125, "00:00 UTC: day 2, 75 coins")
	-- three days missed: the count goes on
	c = Daily.claim(d, midnight + 4 * DAY, E, log) :: Daily.Claim
	check(c and c.pos == 3 and d.crystals == 15, "missed days do not reset: day 3 = 15 crystals")
	for i = 4, 6 do
		c = Daily.claim(d, midnight + (i + 1) * DAY, E, log) :: Daily.Claim
	end
	check(c.pos == 6 and d.trialBonus == 1 and d.coins == 125 + 100 + 150 + 200, "days 4-6, the trial of day 5")
	check(not Progress.owns(d, 13), "no VOID before day 7")
	c = Daily.claim(d, midnight + 8 * DAY, E, log) :: Daily.Claim
	check(c.pos == 7 and c.cycle == 1 and c.gift.ball == 13 and Progress.owns(d, 13), "day 7: VOID")
	local cards, pos, ready = Daily.cards(d, midnight + 8 * DAY, E)
	check(#cards == 7 and pos == 7 and not ready and cards[7].ball == 13 and cards[7].got, "cards after day 7")
	local coins = d.coins
	for i = 8, 14 do
		c = Daily.claim(d, midnight + (i + 1) * DAY, E, log) :: Daily.Claim
	end
	check(c.pos == 7 and c.cycle == 2 and c.gift.ball == nil, "cycle 2 day 7: no ball")
	check(
		d.coins - coins == 50 + 75 + 100 + 150 + 200 + 300 + 4000,
		"cycle 2: coins of the days + 300 on the 7th + the day-14 milestone"
	)
	check(
		c.mile and c.mile.day == 14 and c.mile.coins == 4000 and c.mile.crystals == nil,
		"day 14 milestone on that claim"
	)
	check(d.crystals == 15 + 15 + 10 and d.loginDays == 14, "cycle 2: 15 on day 3, 10 on day 7")
	cards, pos, ready = Daily.cards(d, midnight + 16 * DAY, E)
	check(ready and pos == 1 and cards[1].today and not cards[1].got and not cards[7].ball, "cycle 3 cards")
	-- VOID owned before the 7th day: the 7th gives the later prize
	local o = Progress.new()
	table.insert(o.balls, 13)
	o.loginDays = 6
	c = Daily.claim(o, NOW, E, {}) :: Daily.Claim
	check(c.pos == 7 and c.gift.ball == nil and o.coins == 300 and o.crystals == 10, "VOID owned: 300 + 10 instead")
	check(c.mile == nil, "day 7 is not a milestone")
	check(log[1].kind == "TimedReward" and log[1].why == "login_d1", "login flows: TimedReward, login_d1")
end

-- 4b. Login milestones d14–d42: each pays once, day 13 pays none, day 42 does not repay day 14 -----------------
do
	local sumC, sumX = 0, 0
	check(#E.MILE == 5 and #E.LOOKS == 30, "MILE and LOOKS copied into Economy")
	check(
		E.LOOKS[1].id == "frame_wood" and E.LOOKS[1].coins == 2000 and E.LOOKS[1].robux == 49,
		"LOOKS starts at frame_wood"
	)
	check(
		E.LOOKS[30].id == "frame_champion" and E.LOOKS[30].coins == 36000 and E.LOOKS[30].robux == 499,
		"LOOKS ends at frame_champion"
	)
	for _, m in E.MILE do
		sumC += m.coins
		sumX += m.crystals or 0
	end
	check(sumC == 28000 and sumX == 100, "milestones total 28 000 coins and 100 crystals")

	local function dailyCoins(gift: any): number
		return gift.coins or 0
	end
	local function dailyCrystals(gift: any): number
		return gift.crystals or 0
	end

	local d = Progress.new()
	local hits: { [number]: number } = {}
	for n = 1, 42 do
		local beforeC, beforeX = d.coins, d.crystals
		local log = {}
		local c = Daily.claim(d, NOW + (n - 1) * DAY, E, log) :: Daily.Claim
		check(c ~= nil and c.n == n, `claim {n}`)
		check(Daily.claim(d, NOW + (n - 1) * DAY + 3600, E, log) == nil, `day {n}: same day pays nothing again`)
		local mile = nil
		for _, m in E.MILE do
			if m.day == n then
				mile = m
			end
		end
		if n == 13 then
			check(c.mile == nil, "day 13 pays no milestone")
		end
		if mile then
			hits[n] = (hits[n] or 0) + 1
			check(
				c.mile and c.mile.day == mile.day and c.mile.coins == mile.coins and c.mile.crystals == mile.crystals,
				`day {n}: claim.mile is that chest`
			)
			check(
				d.coins - beforeC == dailyCoins(c.gift) + mile.coins,
				`day {n}: coins are the daily plus that chest once`
			)
			check(
				d.crystals - beforeX == dailyCrystals(c.gift) + (mile.crystals or 0),
				`day {n}: crystals are the daily plus that chest once`
			)
			local saw = false
			for _, f in log do
				if f.why == `mile_d{n}` and f.cur == "coins" and f.n == mile.coins and not f.sink then
					saw = true
				end
			end
			check(saw, `day {n}: a mile_d flow for the counters`)
		else
			check(c.mile == nil, `day {n}: no milestone`)
			check(d.coins - beforeC == dailyCoins(c.gift), `day {n}: coins are only the daily`)
		end
	end
	check(hits[14] == 1 and hits[21] == 1 and hits[28] == 1 and hits[35] == 1 and hits[42] == 1, "each milestone once")
	-- the day-42 delta above is daily + 8 000, so day 14's 4 000 was not paid again
	local after = d.coins
	local later = Daily.claim(d, NOW + 42 * DAY, E, {}) :: Daily.Claim
	check(later and later.n == 43 and later.mile == nil, "the day after 42 pays no earlier milestone")
	check(d.coins - after == dailyCoins(later.gift), "day 43 adds no milestone coins")

	-- a skipped calendar day does not reset the count or skip the chest
	local s = Progress.new()
	check(Daily.claim(s, NOW, E, {}) ~= nil, "skip: day 1")
	local skipped = Daily.claim(s, NOW + 10 * DAY, E, {}) :: Daily.Claim
	check(
		skipped and skipped.n == 2 and skipped.mile == nil and s.loginDays == 2,
		"a missed week does not reset login days"
	)
	s.loginDays = 13
	s.dailyClaimed = Daily.day(NOW + 10 * DAY)
	local before = s.coins
	local hit = Daily.claim(s, NOW + 11 * DAY, E, {}) :: Daily.Claim
	local purse = before + (hit.gift.coins or 0) + 4000
	check(
		hit and hit.n == 14 and hit.mile and hit.mile.coins == 4000 and s.coins == purse,
		"login day 14 pays 4 000 once"
	)
	check(
		Daily.claim(s, NOW + 11 * DAY + 100, E, {}) == nil and s.coins == purse,
		"rejoin the same day does not pay again"
	)
	local nextDay = Daily.claim(s, NOW + 12 * DAY, E, {}) :: Daily.Claim
	check(nextDay and nextDay.n == 15 and nextDay.mile == nil, "the next login does not pay day 14 again")
end

-- 5. Daily quests: one per tier, reset at 00:00 UTC, all-done once ------------------------------------------------
do
	local d = Progress.new()
	local r = rng(5)
	Daily.quests(d, NOW, E, r)
	local tiers = {}
	for _, q in d.quests.list do
		for _, p in E.QUESTS.pool do
			if p.id == q.id then
				tiers[p.tier] = true
			end
		end
	end
	check(#d.quests.list == 3 and tiers.easy and tiers.mid and tiers.hard, "3 quests: easy, mid, hard")
	local first = d.quests.list[1].id
	-- force a known set
	d.quests.list = {
		{ id = "play3", n = 0, done = false },
		{ id = "wild3", n = 0, done = false },
		{ id = "duel3", n = 0, done = false },
	}
	local log = {}
	local function win(kinds: { [string]: number }): Daily.QMatch
		return { mode = "duel", win = true, kills = 0, rx = 0, kinds = kinds, rare = false }
	end
	local done = Daily.progress(d, win({ WILDFIRE = 2 }), NOW, E, r, log)
	check(#done == 0 and d.quests.list[1].n == 1 and d.quests.list[2].n == 2, "quest progress")
	Daily.progress(d, win({}), NOW, E, r, log)
	done = Daily.progress(d, win({ WILDFIRE = 5 }), NOW, E, r, log)
	check(#done == 4 and d.coins == 60 + 80 + 120 + 50, "all three done: 60 + 80 + 120 + 50")
	check(d.quests.list[2].n == 3 and d.quests.all, "progress capped at the goal")
	done = Daily.progress(d, win({ WILDFIRE = 5 }), NOW, E, r, log)
	check(#done == 0 and d.coins == 310, "done quests pay once")
	-- 23:59:59 the same day, 00:00 a new set
	Daily.quests(d, (NOW // DAY + 1) * DAY - 1, E, r)
	check(d.quests.all and d.quests.list[1].n == 3, "23:59:59 UTC: same quests")
	Daily.quests(d, (NOW // DAY + 1) * DAY, E, r)
	check(not d.quests.all and #d.quests.list == 3 and d.quests.list[1].n == 0, "00:00 UTC: new quests")
	check(d.quests.day == NOW // DAY + 1, "quests of the new day")
	local _ = first
	local view = Daily.questView(d, E)
	check(#view == 3 and view[1].goal > 0 and view[1].coins == 60 and view[1].text ~= "", "quest view")
end

-- 6. Reaction book ------------------------------------------------------------------------------------------------
do
	check(#NAMES == 42, "42 reactions")
	local d = Progress.new()
	local log = {}
	local f = Book.add(d, { WILDFIRE = 3, STEAM = 1, NOTHING = 2 }, NAMES, E.BOOK, log)
	check(#f.new == 2 and d.coins == 50 and #d.book == 2, "2 new: 25 each, unknown names ignored")
	f = Book.add(d, { WILDFIRE = 9 }, NAMES, E.BOOK, log)
	check(#f.new == 0 and d.coins == 50 and #d.book == 2, "no duplicates")
	local all = {}
	for _, k in NAMES do
		all[k] = 1
	end
	f = Book.add(d, all, NAMES, E.BOOK, log)
	check(#f.new == 40 and #d.book == 42 and f.all, "the rest: 40 new, the book is full")
	check(d.crystals == 4 * 10, "10 crystals at 10, 20, 30, 40")
	check(d.coins == 42 * 25 + 1000, "25 a reaction + 1000 for all 42")
	local seen = {}
	local dup = false
	for _, k in d.book do
		dup = dup or seen[k] == true
		seen[k] = true
	end
	check(not dup, "book without duplicates")
end

-- 7. A whole match: AFK gets nothing; flows sum to the wallet ----------------------------------------------------------
do
	local d = Progress.new()
	Progress.tutorialReward(d, NOW, cfg, rng(2))
	Daily.quests(d, NOW, E, rng(2))
	local info: Award.Info = {
		mode = "duel",
		win = true,
		kills = 2,
		rx = 4,
		kinds = { WILDFIRE = 3, STEAM = 1 },
		balls = { 0, 17 },
		afk = true,
		friend = true,
		pass2x = false,
	}
	local log = {}
	local res = Award.match(d, info, NOW, cfg, rng(2), NAMES, log)
	check(res.gain.xp == 0 and res.coins.coins == 0 and #res.quests == 0 and #res.book.new == 0, "AFK: nothing")
	check(d.coins == 0 and #d.book == 0 and d.friend.n == 0 and #log == 0, "AFK: no coins, book, friend match")
	info.afk = false
	res = Award.match(d, info, NOW, cfg, rng(2), NAMES, log)
	check(res.coins.friend and res.coins.coins == math.floor((50 + 6 + 8) * 1.25 + 0.5), "active: coins with friend")
	check(res.gain.mult == cfg.XP.boost * E.FRIEND.xp, "friend XP x1.5 on top of the boost")
	check(#res.book.new == 2 and d.friend.n == 1, "active: book")
	check(sum(log, "coins") == d.coins and sum(log, "crystals") == d.crystals, "flows add up to the wallet")
	local v = Award.view(d, NOW, 5000, cfg, #NAMES)
	check(v.coins == d.coins and v.daily.ready and v.daily.pos == 1 and #v.daily.cards == 7, "view: wallet, daily")
	check(#v.quests.list == 3 and v.quests.endsAt == 5000 + 12 * 3600, "view: quests, reset at 00:00 UTC")
	check(#v.book == 2 and v.bookTotal == 42, "view: book")
	-- spend (M3.2 shop): never below zero
	check(not Wallet.spend(d, "coins", d.coins + 1, "x", "Shop", log), "spend: not more than the balance")
	check(Wallet.spend(d, "coins", 10, "x", "Shop", log) and log[#log].sink, "spend: a sink flow")
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("ECONOMY OK")
