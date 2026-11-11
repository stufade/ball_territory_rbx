--!strict
-- Login reward and daily quests (M3.1, docs/economy.md «Возврат и социальное»), pure. Days are UTC days:
-- os.time() // 86400, so everything resets at 00:00 UTC for everyone.
-- Login: one claim per UTC day; the n-th claim pays DAILY[(n - 1) % 7 + 1]; missed days never reset the count.
-- The 7th claim of the first cycle is VOID (LATER_DAY7 when VOID is owned already, and on later cycles).
-- The first time loginDays lands on an Economy.MILE day, that chest is paid once on the same claim.
-- Quests: one of each tier a day from QUESTS.pool, progress only from matches where the player was not AFK,
-- each pays its tier, all of the day pay allDone more.
local Wallet = require("./Wallet")

local Daily = {}

local DAY = 86400
local TIERS = { "easy", "mid", "hard" }

export type Gift = { coins: number?, crystals: number?, ball: number?, trials: number? }
export type MilePay = { day: number, coins: number, crystals: number? }
export type Claim = { n: number, pos: number, cycle: number, gift: Gift, mile: MilePay? }
-- one finished, not AFK match for the quests
export type QMatch =
	{ mode: string, win: boolean, kills: number, rx: number, kinds: { [string]: number }, rare: boolean }
export type QDone = { id: string, text: string, coins: number }

function Daily.day(now: number): number
	return now // DAY
end

-- Seconds until the next 00:00 UTC.
function Daily.left(now: number): number
	return (Daily.day(now) + 1) * DAY - now
end

local function owns(d: any, e: number): boolean
	return table.find(d.balls, e) ~= nil
end

-- What the n-th claim gives (1-based), its day in the cycle and the cycle.
function Daily.gift(d: any, n: number, E: any): (Gift, number, number)
	local pos = (n - 1) % 7 + 1
	local cycle = (n - 1) // 7 + 1
	local g: Gift = E.DAILY[pos]
	if g.ball and (cycle > 1 or owns(d, g.ball)) then
		g = E.LATER_DAY7
	end
	return table.clone(g), pos, cycle
end

function Daily.ready(d: any, now: number): boolean
	return d.dailyClaimed < Daily.day(now)
end

-- Claims today's login reward. nil when claimed today already.
function Daily.claim(d: any, now: number, E: any, log: { Wallet.Flow }?): Claim?
	if not Daily.ready(d, now) then
		return nil
	end
	local n = d.loginDays + 1
	local g, pos, cycle = Daily.gift(d, n, E)
	d.loginDays = n
	d.dailyClaimed = Daily.day(now)
	local why = `login_d{pos}`
	Wallet.gift(d, g, why, "TimedReward", log)
	if g.ball and not owns(d, g.ball) then
		table.insert(d.balls, g.ball)
	end
	if g.trials then
		d.trialBonus += g.trials
	end
	-- Once per login-day number. A later claim has a higher n, so day 42 cannot pay day 14 again.
	local mile: MilePay? = nil
	local miles = E.MILE
	if type(miles) == "table" then
		for _, m in miles do
			if m.day == n then
				local pay = { coins = m.coins, crystals = m.crystals }
				mile = { day = m.day, coins = pay.coins, crystals = pay.crystals }
				Wallet.gift(d, pay, `mile_d{m.day}`, "TimedReward", log)
				break
			end
		end
	end
	return { n = n, pos = pos, cycle = cycle, gift = g, mile = mile }
end

-- The 7 cards of the cycle the next claim belongs to (or of today's claim when it is taken).
function Daily.cards(d: any, now: number, E: any): ({ { [string]: any } }, number, boolean)
	local ready = Daily.ready(d, now)
	local cur = if ready then d.loginDays + 1 else math.max(1, d.loginDays)
	local first = (cur - 1) // 7 * 7 + 1
	local cards = {}
	for n = first, first + 6 do
		local g = Daily.gift(d, n, E) :: any
		if n == 7 and n <= d.loginDays then
			-- the first 7th day was VOID (the card would read LATER_DAY7 now that VOID is owned)
			g = table.clone(E.DAILY[7])
		end
		g.got = n <= d.loginDays
		g.today = n == cur
		table.insert(cards, g)
	end
	return cards, (cur - 1) % 7 + 1, ready
end

local function def(E: any, id: string): any
	for _, q in E.QUESTS.pool do
		if q.id == id then
			return q
		end
	end
	return nil
end

-- Today's quests: drawn at the first look of the day, one of each tier (QUESTS.perDay of them).
function Daily.quests(d: any, now: number, E: any, rand: () -> number)
	local today = Daily.day(now)
	if d.quests.day == today then
		return
	end
	local list = {}
	for i = 1, math.min(E.QUESTS.perDay, #TIERS) do
		local of = {}
		for _, q in E.QUESTS.pool do
			if q.tier == TIERS[i] then
				table.insert(of, q)
			end
		end
		if #of > 0 then
			local q = of[math.floor(rand() * #of) + 1]
			table.insert(list, { id = q.id, n = 0, done = false })
		end
	end
	d.quests = { day = today, list = list, all = false }
end

local function count(q: any, m: QMatch): number
	local k = q.kind
	if k == "play" then
		return 1
	elseif k == "win" then
		return if m.win then 1 else 0
	elseif k == "duelWin" then
		return if m.win and m.mode == "duel" then 1 else 0
	elseif k == "ffaTop" then
		return if m.win and m.mode == "ffa" then 1 else 0
	elseif k == "rx" then
		return m.rx
	elseif k == "rxk" then
		return m.kinds[q.k] or 0
	elseif k == "ko" then
		return m.kills
	elseif k == "rareWin" then
		return if m.win and m.rare then 1 else 0
	end
	return 0
end

-- A not AFK match: quest progress, coins for the quests it finishes and for all of the day.
function Daily.progress(d: any, m: QMatch, now: number, E: any, rand: () -> number, log: { Wallet.Flow }?): { QDone }
	Daily.quests(d, now, E, rand)
	local done = {}
	local all = #d.quests.list > 0
	for _, r in d.quests.list do
		local q = def(E, r.id)
		if q and not r.done then
			r.n = math.min(q.goal, r.n + math.max(0, math.floor(count(q, m))))
			if r.n >= q.goal then
				r.done = true
				local c = Wallet.add(d, "coins", E.QUESTS[q.tier], `quest_{q.id}`, "Gameplay", log)
				table.insert(done, { id = q.id, text = q.text, coins = c })
			end
		end
		all = all and r.done
	end
	if all and not d.quests.all then
		d.quests.all = true
		local c = Wallet.add(d, "coins", E.QUESTS.allDone, "quest_all", "Gameplay", log)
		table.insert(done, { id = "all", text = "ALL QUESTS", coins = c })
	end
	return done
end

-- The quests for the client: text, progress, pay.
function Daily.questView(d: any, E: any): { { [string]: any } }
	local out = {}
	for _, r in d.quests.list do
		local q = def(E, r.id)
		if q then
			table.insert(
				out,
				{ id = q.id, text = q.text, n = r.n, goal = q.goal, coins = E.QUESTS[q.tier], done = r.done }
			)
		end
	end
	return out
end

return Daily
