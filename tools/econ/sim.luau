--!strict
-- E3.2 economy simulation. Reads the live game values (src/shared/Economy.luau, including MILE and LOOKS, and
-- src/server/Config.luau XP). Plays many players of each kind day by day: matches,
-- XP and levels, coins, quests, login days, reaction book, spins, direct buys, then looks once the 27 balls
-- are owned. Prints days to 50% / 100% of the balls, the first coin purchase, coins on hand, the empty-middle
-- gaps, and how fast the cosmetic sink drains coins.
-- lune run tools/econ/sim [players]      (default 400 per kind)
--
-- MILE and LOOKS live in Economy.luau. This sim reads those tables so the numbers cannot drift.
local process = require("@lune/process")
local E = require("../../src/shared/Economy")
-- Config reads Economy through ReplicatedStorage (M3.1): load it with the test loader that maps Roblox paths
local Mock = require("../../tests/Mock")
local Config = Mock.loader(Mock.world(), {}, {})("src/server/Config.luau")
local XP = Config.XP

-- Assumptions of play (not game values): minutes per match with queue, draft, rounds, result and the walk on the
-- plaza; share of duels; win rates vs mixed bots/people; reactions and KOs per match.
local A = {
	duelMin = 4.0,
	ffaMin = 1.8,
	duelShare = 0.6,
	duelWin = 0.5,
	ffaWin = 0.25,
	rx = { duel = { 2, 9 }, ffa = { 1, 5 } }, -- uniform int range
	ko = { duel = { 0, 3 }, ffa = { 0, 2 } },
	-- chance that a reaction event is a new book entry = bookHit * missing / 42 (some need balls/terrain the
	-- player doesn't meet often)
	bookHit = 0.35,
	tutorialMin = 3,
	-- quests finish after this many matches of the day (they progress in parallel)
	questAt = { 3, 5, 8 },
	vipQuestAt = 6,
	days = 120,
}

-- Same tables Economy pays and the shop will sell.
local MILE = E.MILE
local LOOKS = E.LOOKS

local NB = 27
local REACTIONS = 42

local rngState = 12345
local function rand(): number
	rngState = (rngState * 1103515245 + 12345) % 2147483648
	return rngState / 2147483648
end
local function irange(lo: number, hi: number): number
	return lo + math.floor(rand() * (hi - lo + 1))
end

local tierOf: { [number]: string } = {}
for tier, list in E.TIERS do
	for _, e in list do
		tierOf[e] = tier
	end
end
local ORDER = E.TIER_ORDER

type P = {
	kind: any,
	owned: { [number]: boolean },
	n: number,
	level: number,
	xp: number,
	coins: number,
	crystals: number,
	freeCr: number,
	book: number,
	loginDay: number,
	pityC: number,
	pityX: number,
	streak: number,
	minutes: number,
	boostLeft: number,
	firstBuy: { day: number, min: number }?,
	d50: number?,
	d100: number?,
	hand: { [number]: number },
	earned: number,
	robux: number,
	x2: boolean,
	vip: boolean,
	newBallDays: number, -- days of week 1 with a new ball
	newAnyDays: number, -- days of week 1 with a new ball or a level up
	gotToday: boolean,
	lvlToday: boolean,
	daily: number?,
	rewards: { number },
	ballDays: { number },
	legDays: { number },
	looks: { [string]: boolean },
	lookN: number,
	lookFirst: number?,
	lookAll: number?,
}

local function missing(p: P, tier: string): { number }
	local out = {}
	for _, e in E.TIERS[tier] do
		if not p.owned[e] then
			table.insert(out, e)
		end
	end
	return out
end

local function give(p: P, e: number, day: number)
	if p.owned[e] then
		return
	end
	p.owned[e] = true
	p.n += 1
	p.gotToday = true
	table.insert(p.rewards, day)
	table.insert(p.ballDays, day)
	if tierOf[e] == "legendary" then
		table.insert(p.legDays, day)
	end
	if p.n >= 14 and not p.d50 then
		p.d50 = day
	end
	if p.n >= NB and not p.d100 then
		p.d100 = day
	end
end

-- Personal odds of a spin: tier -> %, plus "refund". Shares move down to the nearest lower tier with a missing ball.
local function odds(p: P, spin: any): { [string]: number }
	local out: { [string]: number } = { refund = 0 }
	for i, tier in ORDER do
		local share = spin.odds[tier]
		local j = i
		while j >= 1 and #missing(p, ORDER[j]) == 0 do
			j -= 1
		end
		local to = if j >= 1 then ORDER[j] else "refund"
		out[to] = (out[to] or 0) + share
	end
	return out
end

local function tierIndex(t: string): number
	return table.find(ORDER, t) or 0
end

-- Value of a spin in its own currency (direct price of what comes out).
local function spinValue(p: P, spin: any, prices: { [string]: number }): number
	local o = odds(p, spin)
	local v = o.refund * spin.refund
	for _, tier in ORDER do
		v += (o[tier] or 0) * prices[tier]
	end
	return v / 100
end

local function doSpin(p: P, spin: any, pityKey: string, day: number): string
	local o = odds(p, spin)
	local pityTier = spin.pity.tier
	local count = (p :: any)[pityKey] + 1
	local result: string
	-- pity: the guaranteed tier (or better) when the counter reaches `every` and such a ball is missing
	local canPity = false
	for i = tierIndex(pityTier), #ORDER do
		if #missing(p, ORDER[i]) > 0 then
			canPity = true
		end
	end
	if canPity and count >= spin.pity.every then
		result = ""
		for i = tierIndex(pityTier), #ORDER do
			if #missing(p, ORDER[i]) > 0 then
				result = ORDER[i]
				break
			end
		end
	else
		local r = rand() * 100
		result = "refund"
		for _, tier in ORDER do
			local s = o[tier] or 0
			if r < s then
				result = tier
				break
			end
			r -= s
		end
	end
	if result ~= "refund" and tierIndex(result) >= tierIndex(pityTier) then
		count = 0
	end
	(p :: any)[pityKey] = count
	if result == "refund" then
		return result
	end
	local pool = missing(p, result)
	give(p, pool[irange(1, #pool)], day)
	return result
end

local function cheapestMissing(p: P): string?
	for _, tier in ORDER do
		if #missing(p, tier) > 0 then
			return tier
		end
	end
	return nil
end

local function markBuy(p: P, day: number)
	if not p.firstBuy then
		p.firstBuy = { day = day, min = p.minutes }
	end
end

-- After the 27 balls, coins buy the cheapest look still missing. Robux looks are not auto-bought:
-- the coin path is what this measures.
local function spendLooks(p: P, day: number)
	if p.n < NB then
		return
	end
	while p.lookN < #LOOKS do
		local best: any = nil
		for _, item in LOOKS do
			if not p.looks[item.id] and (best == nil or item.coins < best.coins) then
				best = item
			end
		end
		if best == nil or p.coins < best.coins then
			return
		end
		p.coins -= best.coins
		p.looks[best.id] = true
		p.lookN += 1
		table.insert(p.rewards, day)
		if not p.lookFirst then
			p.lookFirst = day
		end
		if p.lookN == #LOOKS then
			p.lookAll = day
		end
	end
end

-- Free path: spend coins on what gives the most ball value per coin.
local function spendCoins(p: P, day: number)
	while p.n < NB do
		local best, bestRatio = nil :: string?, 0
		local cp = E.PRICE.coins
		local t = cheapestMissing(p)
		if t and p.coins >= cp[t] then
			best, bestRatio = "direct", 1
		end
		if p.daily and not p.owned[p.daily] then
			local price = math.floor(cp[tierOf[p.daily]] * (1 - E.DAILY_BALL.off))
			local ratio = 1 / (1 - E.DAILY_BALL.off)
			if p.coins >= price and ratio > bestRatio then
				best, bestRatio = "daily", ratio
			end
		end
		local s = E.SPIN.coins
		if p.kind.noSpin then
			-- paid-random policy: both roulettes stay hidden, so this player never spins
		elseif p.coins >= s.price then
			local ratio = spinValue(p, s, cp) / s.price
			if ratio > math.max(bestRatio, 1) then
				best, bestRatio = "spin", ratio
			end
		end
		if best == nil then
			return
		end
		markBuy(p, day)
		if best == "direct" then
			local pool = missing(p, t :: string)
			p.coins -= cp[t :: string]
			give(p, pool[irange(1, #pool)], day)
		elseif best == "daily" then
			p.coins -= math.floor(cp[tierOf[p.daily :: number]] * (1 - E.DAILY_BALL.off))
			give(p, p.daily :: number, day)
		else
			p.coins -= s.price
			if doSpin(p, s, "pityC", day) == "refund" then
				p.coins += s.refund
			end
		end
	end
	spendLooks(p, day)
end

-- Payers put crystals into the collection (upper bound: real payers also spend them in the draft).
local function spendCrystals(p: P, day: number)
	local xp = E.PRICE.crystals
	while p.n < NB and p.kind.crystalsToBalls do
		local s = E.SPIN.crystals
		local ratio = spinValue(p, s, xp) / s.price
		if not p.kind.noSpin and p.crystals >= s.price and ratio >= 1 then
			p.crystals -= s.price
			if doSpin(p, s, "pityX", day) == "refund" then
				p.crystals += s.refund
			end
		else
			-- buy the most expensive missing ball crystals afford (coins cover the cheap ones)
			local bought = false
			for i = #ORDER, 1, -1 do
				local tier = ORDER[i]
				local pool = missing(p, tier)
				if #pool > 0 and p.crystals >= xp[tier] then
					p.crystals -= xp[tier]
					give(p, pool[1], day)
					bought = true
					break
				end
			end
			if not bought then
				return
			end
		end
	end
end

local function addXp(p: P, amount: number, day: number)
	p.xp += amount
	while true do
		local need = math.min(E.XP_CAP, XP.base + XP.step * (p.level - 1))
		if p.xp < need then
			break
		end
		p.xp -= need
		p.level += 1
		p.lvlToday = true
		if p.level <= Config.LEVEL_BALLS then
			local pool = {}
			for _, tier in Config.LEVEL_TIERS do
				for _, e in missing(p, tier) do
					table.insert(pool, e)
				end
			end
			if #pool > 0 then
				give(p, pool[irange(1, #pool)], day)
			end
		else
			p.coins += E.LEVEL_COINS
			p.earned += E.LEVEL_COINS
			if p.level % E.LEVEL_CRYSTALS_EVERY == 0 then
				p.crystals += E.LEVEL_CRYSTALS
				p.freeCr += E.LEVEL_CRYSTALS
			end
		end
	end
end

local function coinsGain(p: P, c: number)
	p.coins += c
	p.earned += c
end

local function playMatch(p: P, day: number, matchesToday: number)
	local duel = rand() < A.duelShare
	local mode = if duel then "duel" else "ffa"
	local len = if duel then A.duelMin else A.ffaMin
	local win = rand() < (if duel then A.duelWin else A.ffaWin)
	local rx = irange(A.rx[mode][1], A.rx[mode][2])
	local ko = irange(A.ko[mode][1], A.ko[mode][2])
	local C = E.COINS
	local c = C[mode].play
		+ (if win then C[mode].win else 0)
		+ math.min(C.reactMax, rx * C.react)
		+ math.min(C.koMax, ko * C.ko)
	if p.x2 then
		c *= E.PASSES.coins2x.mult
	end
	local friend = rand() < p.kind.friendShare and matchesToday <= E.FRIEND.daily
	if friend then
		c = math.floor(c * E.FRIEND.coins)
	end
	coinsGain(p, c)
	-- streak
	if duel then
		if win then
			p.streak += 1
			local bonus = (E.STREAK :: any)[p.streak]
			if bonus then
				coinsGain(p, bonus)
			end
		else
			p.streak = 0
		end
	end
	-- XP
	local x = XP.play
		+ (if win then XP.win else 0)
		+ math.min(XP.reactMax, rx * XP.react)
		+ math.min(XP.koMax, ko * XP.ko)
	if p.boostLeft > 0 then
		x *= XP.boost
		p.boostLeft -= len
	end
	if friend then
		x = math.floor(x * E.FRIEND.xp)
	end
	-- book
	for _ = 1, rx do
		if p.book < REACTIONS and rand() < A.bookHit * (REACTIONS - p.book) / REACTIONS then
			p.book += 1
			coinsGain(p, E.BOOK.coins)
			if p.book % E.BOOK.crystalsEvery == 0 then
				p.crystals += E.BOOK.crystals
				p.freeCr += E.BOOK.crystals
			end
			if p.book == REACTIONS then
				coinsGain(p, E.BOOK.allCoins)
			end
		end
	end
	p.minutes += len
	addXp(p, x, day)
end

local function newPlayer(kind: any): P
	local p: P = {
		kind = kind,
		owned = {},
		n = 0,
		level = 1,
		xp = 0,
		coins = 0,
		crystals = 0,
		freeCr = 0,
		book = 0,
		loginDay = 0,
		pityC = 0,
		pityX = 0,
		streak = 0,
		minutes = 0,
		boostLeft = XP.boostTime / 60,
		hand = {},
		earned = 0,
		robux = 0,
		x2 = false,
		vip = false,
		newBallDays = 0,
		newAnyDays = 0,
		gotToday = false,
		lvlToday = false,
		rewards = {},
		ballDays = {},
		legDays = {},
		looks = {},
		lookN = 0,
	}
	-- tutorial: 4 starters + a legendary from the free spin
	for _, e in Config.BASE_BALLS do
		give(p, e, 1)
	end
	local pool = Config.SPIN_POOL
	give(p, pool[irange(1, #pool)], 1)
	return p
end

local function buy(p: P, day: number)
	local plan = p.kind.buys[day]
	if not plan then
		return
	end
	for _, what in plan do
		if what == "starter" then
			local S = E.STARTER
			p.robux += S.robux
			local pool = missing(p, "epic")
			if #pool > 0 then
				give(p, pool[1], day)
			end
			p.crystals += S.crystals
			coinsGain(p, S.coins)
		elseif what == "x2" then
			p.x2 = true
			p.robux += E.PASSES.coins2x.robux
		elseif what == "vip" then
			p.vip = true
			p.robux += E.PASSES.vip.robux
		elseif type(what) == "number" then
			for _, pack in E.CRYSTAL_PACKS do
				if pack.crystals == what then
					p.crystals += pack.crystals
					p.robux += pack.robux
				end
			end
		end
	end
end

local function day(p: P, d: number)
	p.gotToday, p.lvlToday = false, false
	-- login reward
	p.loginDay += 1
	local i = ((p.loginDay - 1) % 7) + 1
	local r: any = E.DAILY[i]
	if p.loginDay > 7 and i == 7 then
		r = E.LATER_DAY7
	end
	if r.coins then
		coinsGain(p, r.coins)
	end
	if r.crystals then
		p.crystals += r.crystals
		p.freeCr += r.crystals
	end
	if r.ball then
		give(p, r.ball, d)
	end
	for _, m in MILE do
		if p.loginDay == m.day then
			if m.coins then
				coinsGain(p, m.coins)
			end
			if m.crystals then
				p.crystals += m.crystals
				p.freeCr += m.crystals
			end
			table.insert(p.rewards, d)
		end
	end
	-- ball of the day: one missing ball
	local miss = {}
	for e = 0, NB - 1 do
		if not p.owned[e] then
			table.insert(miss, e)
		end
	end
	p.daily = if #miss > 0 then miss[irange(1, #miss)] else nil
	buy(p, d)
	spendCrystals(p, d)
	spendCoins(p, d)
	-- play
	local mins = p.kind.minutes
	if d == 1 then
		mins -= A.tutorialMin
	end
	local played, m = 0, 0
	local Q = E.QUESTS
	local questPay = { Q.easy, Q.mid, Q.hard }
	local qDone = 0
	while played < mins do
		m += 1
		local before = p.minutes
		playMatch(p, d, m)
		played += p.minutes - before
		for qi, at in A.questAt do
			if m == at then
				coinsGain(p, questPay[qi])
				qDone += 1
				if qDone == Q.perDay then
					coinsGain(p, Q.allDone)
				end
			end
		end
		if p.vip and m == A.vipQuestAt then
			coinsGain(p, Q.mid)
		end
		spendCrystals(p, d)
		spendCoins(p, d)
	end
	if d <= 7 then
		if p.gotToday then
			p.newBallDays += 1
		end
		if p.gotToday or p.lvlToday then
			p.newAnyDays += 1
		end
	end
	p.hand[d] = p.coins
end

local function median(t: { number }): number
	table.sort(t)
	return t[math.max(1, math.ceil(#t / 2))]
end
local function pct(t: { number }, q: number): number
	table.sort(t)
	return t[math.max(1, math.ceil(#t * q))]
end

local KINDS = {
	{ name = "free 10 min/day", minutes = 10, friendShare = 0, buys = {} },
	{ name = "free 30 min/day", minutes = 30, friendShare = 0, buys = {} },
	{ name = "policy 30m, no spins", minutes = 30, friendShare = 0, buys = {}, noSpin = true },
	{ name = "free 30 min + friend", minutes = 30, friendShare = 0.3, buys = {} },
	{ name = "free 2 h/day", minutes = 120, friendShare = 0, buys = {} },
	{ name = "free 30m, crystal spins", minutes = 30, friendShare = 0, buys = {}, crystalsToBalls = true },
	{
		name = "starter 30m (99)",
		minutes = 30,
		friendShare = 0,
		buys = { [2] = { "starter" } },
		crystalsToBalls = true,
	},
	{
		name = "dolphin 30m (~850)",
		minutes = 30,
		friendShare = 0,
		buys = { [2] = { "starter" }, [3] = { "x2" }, [5] = { 650 } },
		crystalsToBalls = true,
	},
	{ name = "x2 only 30m (249)", minutes = 30, friendShare = 0, buys = { [1] = { "x2" } } },
	{
		name = "whale 30m (1400/wk)",
		minutes = 30,
		friendShare = 0,
		buys = { [1] = { "x2", "vip", 1400 }, [2] = { "starter" }, [8] = { 1400 }, [15] = { 1400 } },
		crystalsToBalls = true,
	},
}

-- Longest quiet stretch inside [lo, hi] between events. The tail after the last event is not counted:
-- once the 27th ball lands, "no new ball" is the cosmetic phase, not an empty collection.
local function maxGap(marks: { number }, lo: number, hi: number): number
	local seq = {}
	for _, d in marks do
		if d >= lo and d <= hi then
			table.insert(seq, d)
		end
	end
	table.sort(seq)
	local gap, prev = 0, lo
	for _, d in seq do
		if d ~= prev then
			gap = math.max(gap, d - prev)
			prev = d
		end
	end
	return gap
end

-- Longest wait between legendary balls from the 7th login day (VOID) onward.
local function legGap(days: { number }): number
	local seq = {}
	for _, d in days do
		if d >= 7 then
			table.insert(seq, d)
		end
	end
	table.sort(seq)
	local gap = 0
	for i = 2, #seq do
		gap = math.max(gap, seq[i] - seq[i - 1])
	end
	return gap
end

local N = tonumber(process.args[1]) or 400
print(("E3.2 economy sim, %d players per kind, %d days, %d looks"):format(N, A.days, #LOOKS))
print(
	"kind                    | 1st coin buy   | 50% day      | 100% day       | coins on hand d1/3/7/14/30   | wk1 days new ball/any | R$"
)
for _, kind in KINDS do
	local fb, fbm, d50, d100 = {}, {}, {}, {}
	local hands = { [1] = {}, [3] = {}, [7] = {}, [14] = {}, [30] = {}, [60] = {}, [120] = {} }
	local nb, na, rbx, n7, n14, n28 = {}, {}, {}, {}, {}, {}
	local n21, n35, n42, n48 = {}, {}, {}, {}
	local gapR, gapB, gapL = {}, {}, {}
	local leg3, leg4, leg5 = {}, {}, {}
	local look30, look60, look120, lookFirst, lookAll = {}, {}, {}, {}, {}
	local lv7, lv30, earn30, cr7, cr30 = {}, {}, {}, {}, {}
	local never = 0
	for _ = 1, N do
		local p = newPlayer(kind)
		local balls: { [number]: number } = {}
		for d = 1, A.days do
			day(p, d)
			balls[d] = p.n
			if d == 7 then
				table.insert(lv7, p.level)
				table.insert(cr7, p.freeCr)
			elseif d == 30 then
				table.insert(lv30, p.level)
				table.insert(earn30, p.earned / 30)
				table.insert(cr30, p.freeCr)
				table.insert(look30, p.lookN)
			elseif d == 60 then
				table.insert(look60, p.lookN)
			end
		end
		table.insert(fb, if p.firstBuy then p.firstBuy.day else 999)
		table.insert(fbm, if p.firstBuy then p.firstBuy.min else 9999)
		table.insert(d50, p.d50 or 999)
		if p.d100 then
			table.insert(d100, p.d100)
		else
			never += 1
			table.insert(d100, 999)
		end
		for k, t in hands do
			table.insert(t, p.hand[k])
		end
		table.insert(nb, p.newBallDays)
		table.insert(na, p.newAnyDays)
		table.insert(rbx, p.robux)
		table.insert(n7, balls[7])
		table.insert(n14, balls[14])
		table.insert(n21, balls[21])
		table.insert(n28, balls[28])
		table.insert(n35, balls[35])
		table.insert(n42, balls[42])
		table.insert(n48, balls[48])
		table.insert(gapR, maxGap(p.rewards, 14, 48))
		table.insert(gapB, maxGap(p.ballDays, 14, 48))
		table.insert(gapL, legGap(p.legDays))
		local legs = table.clone(p.legDays)
		table.sort(legs)
		table.insert(leg3, legs[3] or 999)
		table.insert(leg4, legs[4] or 999)
		table.insert(leg5, legs[5] or 999)
		table.insert(look120, p.lookN)
		table.insert(lookFirst, p.lookFirst or 999)
		table.insert(lookAll, p.lookAll or 999)
	end
	print(
		("%-23s | d%-2d %4.0f min | d%-3d (%d-%d) | d%-3d (%d-%d) %s| %5d %5d %5d %5d %5d | %d / %d | %d"):format(
			kind.name,
			median(fb),
			median(fbm),
			median(d50),
			pct(d50, 0.1),
			pct(d50, 0.9),
			median(d100),
			pct(d100, 0.1),
			pct(d100, 0.9),
			if never > 0 then ("never %d "):format(never) else "",
			median(hands[1]),
			median(hands[3]),
			median(hands[7]),
			median(hands[14]),
			median(hands[30]),
			median(nb),
			median(na),
			median(rbx)
		)
	)
	print(
		("%-23s   balls d7/14/28: %d / %d / %d, level d7/d30: %d / %d, coins/day (d1-30): %d, free crystals d7/d30: %d / %d"):format(
			"",
			median(n7),
			median(n14),
			median(n28),
			median(lv7),
			median(lv30),
			median(earn30),
			median(cr7),
			median(cr30)
		)
	)
	print(
		("%-23s   d14-48 gap reward/ball/legendary: %d / %d / %d days, balls 14/21/28/35/42/48: %d %d %d %d %d %d"):format(
			"",
			median(gapR),
			median(gapB),
			median(gapL),
			median(n14),
			median(n21),
			median(n28),
			median(n35),
			median(n42),
			median(n48)
		)
	)
	print(
		("%-23s   legendary ball 3/4/5 on day %d / %d / %d (1 and 2 are the tutorial spin and VOID)"):format(
			"",
			median(leg3),
			median(leg4),
			median(leg5)
		)
	)
	print(
		("%-23s   looks d30/60/120: %d / %d / %d of %d, first d%d, all d%d, coins d60/d120: %d / %d"):format(
			"",
			median(look30),
			median(look60),
			median(look120),
			#LOOKS,
			median(lookFirst),
			median(lookAll),
			median(hands[60]),
			median(hands[120])
		)
	)
end
