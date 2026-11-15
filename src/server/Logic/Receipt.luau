--!strict
-- Developer-product grants (docs/economy.md «Монетизация»). Pure: no MarketplaceService, so tests/receipt
-- runs without the network. "granted" is a new PurchaseId, "already" is the same id again (nothing is added).
-- "later" is NotProcessedYet: the wrong player or an unknown product. "later" does not store the PurchaseId and
-- does not change the wallet, so a retry can still grant. A purchase that cannot be delivered as bought (the ball
-- or the look is owned already, a second starter pack) is still "granted": the Robux come back as crystals, so a
-- receipt never hangs as NotProcessedYet.
-- A cosmetic with a live product id is granted by Looks.grant at any ball count (the same call a coin purchase
-- uses after it has spent). Crystals go through Wallet.add, the ball
-- and the starter epic through Progress.give, starter coins through Wallet.gift.
local Looks = require("./Looks")
local Progress = require("./Progress")
local Wallet = require("./Wallet")

local Receipt = {}

local MAX_IDS = 100
local MAX_LEN = 128
local NEL = 27

export type Ids = {
	crystals: { number },
	ball: { [string]: number },
	starter: number,
	looks: { [string]: number },
}

export type Spec = {
	kind: string,
	n: number?,
	tier: string?,
	id: string?,
	why: string,
}

local function tierOf(E: any, e: number): string?
	for tier, list in E.TIERS do
		if table.find(list, e) then
			return tier
		end
	end
	return nil
end

local function put(map: { [number]: Spec }, id: any, spec: Spec)
	if type(id) ~= "number" or id ~= id or id <= 0 or id % 1 ~= 0 then
		return
	end
	if map[id] then
		warn(`product id {id} is listed twice; the second product is ignored`)
		return
	end
	map[id] = spec
end

-- Ids of 0 are skipped, so the placeholder table in Products.luau grants nothing.
function Receipt.index(E: any, ids: Ids): { [number]: Spec }
	local map: { [number]: Spec } = {}
	for i, id in ids.crystals do
		local pack = E.CRYSTAL_PACKS[i]
		if pack then
			put(map, id, { kind = "crystals", n = pack.crystals, why = `pack_{pack.crystals}` })
		end
	end
	for tier, id in ids.ball do
		if E.PRICE.robux[tier] ~= nil then
			put(map, id, { kind = "ball", tier = tier, why = `ball_{tier}` })
		end
	end
	put(map, ids.starter, { kind = "starter", why = "starter" })
	for _, look in E.LOOKS do
		put(map, ids.looks[look.id], { kind = "look", id = look.id, why = look.id })
	end
	return map
end

-- Remembers the ball (any tier) or the starter epic on the profile until the receipt is granted.
function Receipt.choose(d: Progress.Data, slot: string, e: number, E: any): boolean
	if slot ~= "ball" and slot ~= "epic" then
		return false
	end
	if type(e) ~= "number" or e ~= e or e % 1 ~= 0 or e < 0 or e >= NEL then
		return false
	end
	local tier = tierOf(E, e)
	if not tier or (slot == "epic" and tier ~= "epic") then
		return false
	end
	if slot == "ball" then
		d.robuxBall = e
	else
		d.robuxEpic = e
	end
	return true
end

local function purchaseId(receipt: any): string?
	local id = receipt.PurchaseId
	if type(id) ~= "string" or #id == 0 or #id > MAX_LEN then
		return nil
	end
	return id
end

local function remember(d: Progress.Data, id: string)
	table.insert(d.receipts, id)
	while #d.receipts > MAX_IDS do
		table.remove(d.receipts, 1)
	end
end

local function chosenTier(E: any, e: number): string?
	if type(e) ~= "number" or e ~= e or e % 1 ~= 0 or e < 0 or e >= NEL then
		return nil
	end
	return tierOf(E, e)
end

local function lookOf(E: any, id: string?): any
	for _, look in E.LOOKS do
		if look.id == id then
			return look
		end
	end
	return nil
end

-- Robux of a purchase that cannot be delivered, as crystals at the smallest pack's rate (49 R$ -> 50).
local function back(E: any, robux: number): number
	local pack = E.CRYSTAL_PACKS[1]
	if type(robux) ~= "number" or robux <= 0 or not pack then
		return 0
	end
	return math.floor(robux * pack.crystals / pack.robux)
end

local function compensate(d: Progress.Data, n: number, why: string, log: { Wallet.Flow }?)
	if n > 0 then
		Wallet.add(d, "crystals", n, why, "IAP", log)
	end
end

-- userId is the profile being paid. A receipt for someone else is refused.
function Receipt.apply(
	d: Progress.Data,
	receipt: any,
	userId: number,
	catalog: { [number]: Spec },
	E: any,
	log: { Wallet.Flow }?
): string
	if type(receipt) ~= "table" or type(receipt.PlayerId) ~= "number" or receipt.PlayerId ~= userId then
		return "later"
	end
	local id = purchaseId(receipt)
	if not id then
		return "later"
	end
	if table.find(d.receipts, id) then
		return "already"
	end
	local spec = catalog[receipt.ProductId]
	if not spec then
		return "later"
	end
	if spec.kind == "look" then
		local how = Looks.grant(d, spec.id, E)
		if how == "have" then
			-- already owned (bought for coins while the prompt was open): the Robux come back as crystals
			local look = lookOf(E, spec.id)
			compensate(d, back(E, if look then look.robux else 0), `comp_{spec.why}`, log)
		elseif how ~= "ok" then
			return "later"
		end
	elseif spec.kind == "crystals" then
		local n = Wallet.add(d, "crystals", spec.n or 0, spec.why, "IAP", log)
		if n <= 0 then
			return "later"
		end
	elseif spec.kind == "ball" then
		local e = d.robuxBall
		local tier = spec.tier :: string
		if chosenTier(E, e) == tier and not Progress.owns(d, e) and Progress.give(d, e) then
			d.robuxBall = -1
		else
			-- no valid choice, or the ball came meanwhile (spin, level, VOID): the tier's crystal price instead.
			-- A choice of another tier stays for its own receipt.
			if chosenTier(E, e) == tier then
				d.robuxBall = -1
			end
			compensate(d, E.PRICE.crystals[tier] or 0, `comp_{spec.why}`, log)
		end
	elseif spec.kind == "starter" then
		if d.starterBought then
			compensate(d, back(E, E.STARTER.robux), "comp_starter", log)
		else
			local e = d.robuxEpic
			if not (chosenTier(E, e) == "epic" and not Progress.owns(d, e) and Progress.give(d, e)) then
				compensate(d, E.PRICE.crystals.epic or 0, "comp_starter_epic", log)
			end
			Wallet.gift(d, { coins = E.STARTER.coins, crystals = E.STARTER.crystals }, spec.why, "IAP", log)
			d.starterBought = true
			d.robuxEpic = -1
		end
	else
		return "later"
	end
	remember(d, id)
	return "granted"
end

return Receipt
