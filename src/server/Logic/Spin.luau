--!strict
-- Paid spins (docs/economy.md «Рулетки»). Personal odds are the `odds` function in tools/econ/sim.luau:
-- a tier the player owns fully moves its share DOWN to the nearest lower tier that still has a missing ball,
-- or to "refund" when nothing lower is open. Shares never move up, so a late spin is not a cheap legendary.
-- The client sends only the currency. The ball (or the refund) is chosen here, before any reel.
-- `blocked` is PolicyService ArePaidRandomItemsRestricted: both wheels refuse, and nothing is spent.

local Wallet = require("./Wallet")

local Spin = {}

export type Odds = { common: number, rare: number, epic: number, legendary: number, refund: number }

export type Line = {
	price: number,
	refund: number,
	pity: number,
	every: number,
	tier: string,
	odds: Odds,
}

export type Board = { ok: boolean, coins: Line, crystals: Line }

export type Hit = {
	cur: string,
	tier: string,
	e: number?,
	back: number,
	pity: number,
	price: number,
}

local function ownedSet(balls: { number }): { [number]: boolean }
	local have: { [number]: boolean } = {}
	for _, e in balls do
		have[e] = true
	end
	return have
end

function Spin.missing(balls: { number }, tier: string, E: any): { number }
	local have = ownedSet(balls)
	local out = {}
	for _, e in E.TIERS[tier] do
		if not have[e] then
			table.insert(out, e)
		end
	end
	return out
end

local function indexOf(order: { string }, tier: string): number
	return table.find(order, tier) or 0
end

local function addShare(out: Odds, key: string, n: number)
	if key == "common" then
		out.common += n
	elseif key == "rare" then
		out.rare += n
	elseif key == "epic" then
		out.epic += n
	elseif key == "legendary" then
		out.legendary += n
	else
		out.refund += n
	end
end

-- Tier -> percent, plus refund. Same walk as tools/econ/sim.luau `odds`.
function Spin.odds(balls: { number }, spin: any, E: any): Odds
	local order: { string } = E.TIER_ORDER
	local out: Odds = { common = 0, rare = 0, epic = 0, legendary = 0, refund = 0 }
	for i, tier in order do
		local share = spin.odds[tier]
		local j = i
		while j >= 1 and #Spin.missing(balls, order[j], E) == 0 do
			j -= 1
		end
		addShare(out, if j >= 1 then order[j] else "refund", share)
	end
	return out
end

local function line(d: any, cur: string, E: any): Line
	local spin = E.SPIN[cur]
	local pity = if type(d.pity) == "table" then d.pity[cur] or 0 else 0
	return {
		price = spin.price,
		refund = spin.refund,
		pity = pity,
		every = spin.pity.every,
		tier = spin.pity.tier,
		odds = Spin.odds(d.balls, spin, E),
	}
end

-- What the spin screen shows before the player taps. `ok` is false when paid random is restricted.
function Spin.board(d: any, E: any, ok: boolean): Board
	return { ok = ok, coins = line(d, "coins", E), crystals = line(d, "crystals", E) }
end

-- One spin. Nil, and the wallet untouched, when the currency is wrong, the balance is short, or `blocked`.
function Spin.roll(d: any, cur: any, E: any, rng: () -> number, log: { Wallet.Flow }?, blocked: boolean?): Hit?
	if blocked or (cur ~= "coins" and cur ~= "crystals") then
		return nil
	end
	local spin = E.SPIN[cur]
	if not spin then
		return nil
	end
	if not Wallet.spend(d, cur, spin.price, `spin_{cur}`, "Shop", log) then
		return nil
	end
	local order: { string } = E.TIER_ORDER
	local o = Spin.odds(d.balls, spin, E)
	local pityTier = spin.pity.tier
	local pityAt = indexOf(order, pityTier)
	if type(d.pity) ~= "table" then
		d.pity = { coins = 0, crystals = 0 }
	end
	local count = (d.pity[cur] or 0) + 1
	local canPity = false
	for i = pityAt, #order do
		if #Spin.missing(d.balls, order[i], E) > 0 then
			canPity = true
			break
		end
	end
	local result: string
	if canPity and count >= spin.pity.every then
		result = "refund"
		for i = pityAt, #order do
			if #Spin.missing(d.balls, order[i], E) > 0 then
				result = order[i]
				break
			end
		end
	else
		local r = rng() * 100
		result = "refund"
		for _, tier in order do
			local share = if tier == "common"
				then o.common
				elseif tier == "rare" then o.rare
				elseif tier == "epic" then o.epic
				elseif tier == "legendary" then o.legendary
				else o.refund
			if r < share then
				result = tier
				break
			end
			r -= share
		end
	end
	if result ~= "refund" and indexOf(order, result) >= pityAt then
		count = 0
	end
	d.pity[cur] = count
	local currency = cur :: string
	if result == "refund" then
		local back = Wallet.add(d, currency, spin.refund, "spin_refund", "Shop", log)
		local refunded: Hit = { cur = currency, tier = "refund", back = back, pity = count, price = spin.price }
		return refunded
	end
	local pool = Spin.missing(d.balls, result, E)
	local e = pool[math.floor(rng() * #pool) + 1]
	table.insert(d.balls, e)
	local given: Hit = { cur = currency, tier = result, e = e, back = 0, pity = count, price = spin.price }
	return given
end

return Spin
