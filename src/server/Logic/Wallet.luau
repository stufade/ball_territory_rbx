--!strict
-- Coins and crystals of a profile (M3.1), pure. Every change goes through add/spend with a reason, and lands in
-- `log` as a Flow: Profiles sends the flows to AnalyticsService (LogEconomyEvent) and to the client (counters).
local Wallet = {}

export type Purse = { coins: number, crystals: number }

-- cur: "coins" | "crystals"; n > 0; sink = spent; kind = AnalyticsEconomyTransactionType name; why = item SKU
-- (what for: "match_duel", "login_d3", "quest_win2", "book_new"...); bal = balance after.
export type Flow = { cur: string, n: number, sink: boolean, kind: string, why: string, bal: number }

local MAX = 1e9

local function amount(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

function Wallet.add(d: Purse, cur: string, n: number, why: string, kind: string, log: { Flow }?): number
	n = amount(n)
	if n <= 0 or (cur ~= "coins" and cur ~= "crystals") then
		return 0
	end
	local t = d :: any
	t[cur] = math.min(MAX, t[cur] + n)
	if log then
		table.insert(log, { cur = cur :: any, n = n, sink = false, kind = kind, why = why, bal = t[cur] })
	end
	return n
end

-- Spends n when the balance allows; false and nothing changed otherwise (M3.2 shop, draft).
function Wallet.spend(d: Purse, cur: string, n: number, why: string, kind: string, log: { Flow }?): boolean
	n = amount(n)
	local t = d :: any
	if n <= 0 or (cur ~= "coins" and cur ~= "crystals") or t[cur] < n then
		return false
	end
	t[cur] -= n
	if log then
		table.insert(log, { cur = cur :: any, n = n, sink = true, kind = kind, why = why, bal = t[cur] })
	end
	return true
end

-- A gift table {coins?, crystals?} paid at once.
function Wallet.gift(d: Purse, g: { coins: number?, crystals: number? }, why: string, kind: string, log: { Flow }?)
	if g.coins then
		Wallet.add(d, "coins", g.coins, why, kind, log)
	end
	if g.crystals then
		Wallet.add(d, "crystals", g.crystals, why, kind, log)
	end
end

return Wallet
