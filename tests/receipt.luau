--!strict
-- Developer products without the network: one PurchaseId grants once, the same id again adds nothing.
-- Product ids of the live game are the zeros in src/server/Products.luau. The numbers below are test fixtures.
-- lune run tests/receipt
local process = require("@lune/process")
local Economy = require("../src/shared/Economy")
local Products = require("../src/server/Products")
local Progress = require("../src/server/Logic/Progress")
local Receipt = require("../src/server/Logic/Receipt")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local E = Economy
local USER = 42

local function fresh(): Progress.Data
	return Progress.new()
end

local function receipt(productId: number, purchaseId: string, playerId: number?): any
	return { PlayerId = playerId or USER, ProductId = productId, PurchaseId = purchaseId }
end

-- Live table: every id is a real asset id, none repeats, and each one is indexed for a receipt.
do
	check(#Products.crystals == #E.CRYSTAL_PACKS, "one id per crystal pack")
	local seen: { [number]: boolean } = {}
	local count = 0
	local function live(id: number, what: string)
		check(id > 0, `{what} has a product id`)
		check(not seen[id], `{what} id is not reused`)
		seen[id] = true
		count += 1
	end
	for i, id in Products.crystals do
		live(id, `crystal pack {i}`)
	end
	for tier in E.PRICE.robux do
		live(Products.ball[tier] or 0, `ball {tier}`)
	end
	live(Products.starter, "starter")
	for _, look in E.LOOKS do
		live(Products.looks[look.id] or 0, `look {look.id}`)
	end
	for pass in E.PASSES do
		check((Products.passes[pass] or 0) > 0, `pass {pass} has a pass id`)
	end
	local index = Receipt.index(E, Products)
	local n = 0
	for _ in index do
		n += 1
	end
	check(n == count, "every live product id is indexed")
	local d = fresh()
	check(Receipt.apply(d, receipt(0, "live-0"), USER, index, E, {}) == "later", "product 0 is refused")
	check(d.crystals == 0 and #d.receipts == 0, "refused product 0 changes nothing")
end

-- Test fixtures. Not asset ids.
local FIX = {
	crystals = { 9001, 9002, 9003, 9004, 9005, 9006 },
	ball = { common = 9101, rare = 9102, epic = 9103, legendary = 9104 },
	starter = 9201,
	looks = { frame_wood = 9301 },
}
for _, look in E.LOOKS do
	if FIX.looks[look.id] == nil then
		FIX.looks[look.id] = 0
	end
end
local cat = Receipt.index(E, FIX :: any)
local PACK = E.CRYSTAL_PACKS[1].crystals
local EPIC = E.TIERS.epic[1]

do
	local d = fresh()
	local log = {}
	local first = Receipt.apply(d, receipt(9001, "rcpt-1"), USER, cat, E, log)
	check(first == "granted" and d.crystals == PACK and #log == 1, "one receipt grants the crystal pack once")
	local crystals = d.crystals
	local second = Receipt.apply(d, receipt(9001, "rcpt-1"), USER, cat, E, {})
	check(second == "already" and d.crystals == crystals and #d.receipts == 1, "the same receipt id adds nothing")
	local again = Receipt.apply(d, receipt(9001, "rcpt-2"), USER, cat, E, {})
	check(again == "granted" and d.crystals == crystals + PACK, "a new receipt of the same pack grants again")
end

do
	local d = fresh()
	local before = d.crystals
	check(
		Receipt.apply(d, receipt(9001, "other", 99), USER, cat, E, {}) == "later",
		"a receipt for another player is refused"
	)
	check(d.crystals == before and #d.receipts == 0, "another player changes nothing")
	check(Receipt.apply(d, receipt(123456, "unknown"), USER, cat, E, {}) == "later", "an unknown product is refused")
	check(d.crystals == before and #d.receipts == 0, "an unknown product is not acknowledged")
end

do
	local d = fresh()
	check(
		Receipt.apply(d, receipt(9101, "ball-none"), USER, cat, E, {}) == "granted",
		"a ball with no choice is acknowledged (never hangs)"
	)
	check(
		#d.balls == 0 and d.crystals == E.PRICE.crystals.common and #d.receipts == 1,
		"a ball with no choice pays the tier's crystal price"
	)
	check(not Receipt.choose(d, "ball", 99, E), "a ball id outside the roster is refused")
	check(Receipt.choose(d, "ball", 0, E) and d.robuxBall == 0, "the server remembers the chosen ball")
	local c0 = d.crystals
	check(
		Receipt.apply(d, receipt(9104, "ball-wrong-tier"), USER, cat, E, {}) == "granted",
		"the wrong tier is acknowledged"
	)
	check(
		#d.balls == 0 and d.robuxBall == 0 and d.crystals == c0 + E.PRICE.crystals.legendary,
		"the wrong tier pays its crystals and keeps the other tier's choice"
	)
	check(
		Receipt.apply(d, receipt(9101, "ball-1"), USER, cat, E, {}) == "granted" and Progress.owns(d, 0),
		"the chosen ball is granted"
	)
	check(d.robuxBall == -1, "the choice is cleared after the grant")
	check(
		Receipt.apply(d, receipt(9101, "ball-1"), USER, cat, E, {}) == "already" and #d.balls == 1,
		"the same ball receipt adds nothing"
	)
end

do
	local d = fresh()
	check(Receipt.choose(d, "epic", 0, E) == false, "a common ball is not a starter epic")
	check(Receipt.choose(d, "epic", EPIC, E), "the server remembers the starter epic")
	local coins, crystals = d.coins, d.crystals
	check(Receipt.apply(d, receipt(9201, "st-1"), USER, cat, E, {}) == "granted", "the starter pack is granted once")
	check(
		d.starterBought
			and Progress.owns(d, EPIC)
			and d.coins == coins + E.STARTER.coins
			and d.crystals == crystals + E.STARTER.crystals,
		"starter pays the epic, the coins, and the crystals from Economy"
	)
	check(
		Receipt.apply(d, receipt(9201, "st-1"), USER, cat, E, {}) == "already",
		"the same starter receipt adds nothing"
	)
	local after = d.crystals
	check(
		Receipt.apply(d, receipt(9201, "st-2"), USER, cat, E, {}) == "granted",
		"a second starter purchase is accepted"
	)
	local back = math.floor(E.STARTER.robux * E.CRYSTAL_PACKS[1].crystals / E.CRYSTAL_PACKS[1].robux)
	check(
		d.crystals == after + back and d.coins == coins + E.STARTER.coins and #d.balls == 1,
		"a second starter purchase gives its Robux back as crystals, not a second pack"
	)
end

do
	local d = fresh()
	table.insert(d.balls, 0)
	local coins = d.coins
	check(Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "granted", "one ball grants the look")
	check(
		d.looks[1] == "frame_wood" and d.coins == coins and #d.receipts == 1 and #d.balls == 1,
		"the grant owns the look and spends no coins"
	)
	check(
		Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "already",
		"the same cosmetic receipt adds nothing"
	)
	local c1 = d.crystals
	check(
		Receipt.apply(d, receipt(9301, "look-2"), USER, cat, E, {}) == "granted" and #d.looks == 1,
		"a second purchase of an owned look is acknowledged once"
	)
	check(d.crystals == c1 + 50, "an owned look's Robux (49) come back as 50 crystals")
end

-- The chosen ball came meanwhile (spin, level, VOID): crystals of the tier, the receipt is granted once.
do
	local d = fresh()
	local RARE = E.TIERS.rare[1]
	check(Receipt.choose(d, "ball", RARE, E), "rare chosen")
	table.insert(d.balls, RARE)
	local r = Receipt.apply(d, receipt(9102, "late-1"), USER, cat, E, {})
	check(r == "granted" and d.crystals == E.PRICE.crystals.rare and d.robuxBall == -1, "owned ball -> rare crystals")
	check(#d.balls == 1, "no second copy of the ball")
	check(
		Receipt.apply(d, receipt(9102, "late-1"), USER, cat, E, {}) == "already" and d.crystals == E.PRICE.crystals.rare,
		"the retried receipt pays nothing more"
	)
end

-- Starter whose chosen epic came meanwhile: the pack is paid, the epic as its crystal price.
do
	local d = fresh()
	check(Receipt.choose(d, "epic", EPIC, E), "epic chosen")
	table.insert(d.balls, EPIC)
	check(Receipt.apply(d, receipt(9201, "st-late"), USER, cat, E, {}) == "granted", "late starter granted")
	check(
		d.starterBought and d.crystals == E.STARTER.crystals + E.PRICE.crystals.epic and #d.balls == 1,
		"late starter: pack crystals plus the epic's crystal price"
	)
end

do
	local d = fresh()
	d.receipts = { "rcpt-1" }
	d.starterBought = true
	d.robuxBall = 4
	local again = Progress.migrate(d)
	check(
		again.receipts[1] == "rcpt-1" and again.starterBought and again.robuxBall == 4 and again.robuxEpic == -1,
		"receipt fields survive a save"
	)
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("RECEIPT OK")
