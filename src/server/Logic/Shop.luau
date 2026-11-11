--!strict
-- Direct buy of one ball (M3.2, docs/economy.md «Тиры и цены» and «Шар дня»). Pure.
-- The client names an element id and "coins" or "crystals"; the price is Economy.PRICE of that ball's tier.
-- The ball of the day is one missing ball per UTC day, 30% off in both currencies (floored). The same ball is
-- not offered again for DAILY_BALL.repeatDays days. Legendaries are in the pool. The choice is a function of
-- the UTC day and the collection (and of the recent offers, which are themselves that function), never of a
-- client claim. A refusal (owned, unknown id, bad currency, short balance) changes nothing and does not spend.
local Daily = require("./Daily")
local Wallet = require("./Wallet")

local Shop = {}

local NEL = 27

export type Deal = { e: number, coins: number, crystals: number }
export type Bought = { e: number, cur: string, n: number, daily: boolean }

local function owns(d: any, e: number): boolean
	return table.find(d.balls, e) ~= nil
end

local function tierOf(E: any, e: number): string?
	for tier, list in E.TIERS do
		if table.find(list, e) then
			return tier
		end
	end
	return nil
end

-- Index into `ids` (already a stable order). Same day and the same list always land on the same row.
local function slot(day: number, ids: { number }): number
	local h = day % 2147483647
	for _, e in ids do
		h = (h * 131 + e + 1) % 2147483647
	end
	return (h % #ids) + 1
end

-- Full tier price, or the ball-of-the-day price when `e` is `sale`.
function Shop.cost(E: any, e: number, cur: string, sale: number): number?
	if cur ~= "coins" and cur ~= "crystals" then
		return nil
	end
	local tier = tierOf(E, e)
	if not tier then
		return nil
	end
	local full = E.PRICE[cur][tier] :: number
	if e == sale then
		return math.floor(full * (1 - E.DAILY_BALL.off))
	end
	return full
end

-- Locks today's offer. A later call the same day keeps it, even after the ball is bought.
function Shop.refresh(d: any, now: number, E: any)
	local today = Daily.day(now)
	local b = d.dailyBall
	if b.day == today then
		return
	end
	local window = E.DAILY_BALL.repeatDays
	local blocked: { [number]: boolean } = {}
	local from = math.max(1, #b.recent - window + 1)
	for i = from, #b.recent do
		blocked[b.recent[i]] = true
	end
	local open, all = {}, {}
	for e = 0, NEL - 1 do
		if not owns(d, e) then
			table.insert(all, e)
			if not blocked[e] then
				table.insert(open, e)
			end
		end
	end
	-- Fewer missing balls than the window: still offer one, or the day would have no ball.
	local pool = if #open > 0 then open else all
	b.day = today
	if #pool == 0 then
		b.e = -1
		return
	end
	local e = pool[slot(today, pool)]
	b.e = e
	table.insert(b.recent, e)
	while #b.recent > window do
		table.remove(b.recent, 1)
	end
end

-- Nil when today's ball is already owned or the collection is complete.
function Shop.offer(d: any, E: any): Deal?
	local e = d.dailyBall.e
	if d.dailyBall.day < 0 or e < 0 or owns(d, e) then
		return nil
	end
	return {
		e = e,
		coins = Shop.cost(E, e, "coins", e) :: number,
		crystals = Shop.cost(E, e, "crystals", e) :: number,
	}
end

local function validId(e: unknown): number?
	if type(e) ~= "number" or e ~= e or e == math.huge or e == -math.huge or e % 1 ~= 0 or e < 0 or e >= NEL then
		return nil
	end
	return e
end

-- Buys `e` for `cur`. Nil, and the wallet and the collection untouched, when it cannot.
function Shop.buy(d: any, e: unknown, cur: unknown, now: number, E: any, log: { Wallet.Flow }?): Bought?
	local id = validId(e)
	if not id or (cur ~= "coins" and cur ~= "crystals") or tierOf(E, id) == nil or owns(d, id) then
		return nil
	end
	Shop.refresh(d, now, E)
	local sale = d.dailyBall.e
	local n = Shop.cost(E, id, cur :: string, sale)
	if
		not n or not Wallet.spend(d, cur :: string, n, if id == sale then `daily_{id}` else `ball_{id}`, "Shop", log)
	then
		return nil
	end
	table.insert(d.balls, id)
	return { e = id, cur = cur :: string, n = n, daily = id == sale }
end

return Shop
