--!strict
-- Developer products without the network: one PurchaseId grants once, the same id again adds nothing.
-- E4: coin packs (the former crystal pack ids) and the starter pack are sold; ball and look receipts bought before
-- the update still grant what was paid for.
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
	check(#Products.packs == #E.COIN_PACKS, "one id per coin pack")
	check(Products.packs[1] == 3732004217 and Products.packs[6] == 3732004535, "coin packs keep the crystal pack ids")
	local seen: { [number]: boolean } = {}
	local count = 0
	local function live(id: number, what: string)
		check(id > 0, `{what} has a product id`)
		check(not seen[id], `{what} id is not reused`)
		seen[id] = true
		count += 1
	end
	for i, id in Products.packs do
		live(id, `coin pack {i}`)
	end
	for tier in E.PRICE.coins do
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
	check(d.coins == 0 and #d.receipts == 0, "refused product 0 changes nothing")
end

-- Test fixtures. Not asset ids.
local FIX = {
	packs = { 9001, 9002, 9003, 9004, 9005, 9006 },
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
local PACK = E.COIN_PACKS[1].coins
local EPIC = E.TIERS.epic[1]

do
	local d = fresh()
	local log = {}
	local first = Receipt.apply(d, receipt(9001, "rcpt-1"), USER, cat, E, log)
	check(first == "granted" and d.coins == PACK and #log == 1, "one receipt grants the coin pack once")
	check(log[1].cur == "coins" and log[1].kind == "IAP" and log[1].why == `pack_{PACK}`, "pack flow: IAP coins")
	local coins = d.coins
	local second = Receipt.apply(d, receipt(9001, "rcpt-1"), USER, cat, E, {})
	check(second == "already" and d.coins == coins and #d.receipts == 1, "the same receipt id adds nothing")
	local again = Receipt.apply(d, receipt(9001, "rcpt-2"), USER, cat, E, {})
	check(again == "granted" and d.coins == coins + PACK, "a new receipt of the same pack grants again")
	-- every pack pays its COIN_PACKS coins (= the old crystals * 20)
	for i, pk in E.COIN_PACKS do
		local p = fresh()
		check(
			Receipt.apply(p, receipt(9000 + i, `pk-{i}`), USER, cat, E, {}) == "granted" and p.coins == pk.coins,
			`pack {i}: {pk.coins} coins`
		)
	end
	check(E.COIN_PACKS[6].coins == 75000 and E.COIN_PACKS[6].best, "biggest pack: 75 000, best value")
end

do
	local d = fresh()
	local before = d.coins
	check(
		Receipt.apply(d, receipt(9001, "other", 99), USER, cat, E, {}) == "later",
		"a receipt for another player is refused"
	)
	check(d.coins == before and #d.receipts == 0, "another player changes nothing")
	check(Receipt.apply(d, receipt(123456, "unknown"), USER, cat, E, {}) == "later", "an unknown product is refused")
	check(d.coins == before and #d.receipts == 0, "an unknown product is not acknowledged")
end

do
	local d = fresh()
	check(
		Receipt.apply(d, receipt(9101, "ball-none"), USER, cat, E, {}) == "granted",
		"a ball with no choice is acknowledged (never hangs)"
	)
	check(
		#d.balls == 0 and d.coins == E.PRICE.coins.common and #d.receipts == 1,
		"an old ball receipt with no choice pays the tier's coin price"
	)
	check(not Receipt.choose(d, "ball", 99, E), "a ball id outside the roster is refused")
	check(Receipt.choose(d, "ball", 0, E) and d.robuxBall == 0, "the server remembers the chosen ball")
	local c0 = d.coins
	check(
		Receipt.apply(d, receipt(9104, "ball-wrong-tier"), USER, cat, E, {}) == "granted",
		"the wrong tier is acknowledged"
	)
	check(
		#d.balls == 0 and d.robuxBall == 0 and d.coins == c0 + E.PRICE.coins.legendary,
		"the wrong tier pays its coins and keeps the other tier's choice"
	)
	check(
		Receipt.apply(d, receipt(9101, "ball-1"), USER, cat, E, {}) == "granted" and Progress.owns(d, 0),
		"an old ball receipt grants the chosen ball"
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
	local coins = d.coins
	check(Receipt.apply(d, receipt(9201, "st-1"), USER, cat, E, {}) == "granted", "the starter pack is granted once")
	check(
		d.starterBought and Progress.owns(d, EPIC) and d.coins == coins + E.STARTER.coins and E.STARTER.coins == 3000,
		"starter pays the epic and 3 000 coins from Economy"
	)
	check(
		Receipt.apply(d, receipt(9201, "st-1"), USER, cat, E, {}) == "already",
		"the same starter receipt adds nothing"
	)
	local after = d.coins
	check(
		Receipt.apply(d, receipt(9201, "st-2"), USER, cat, E, {}) == "granted",
		"a second starter purchase is accepted"
	)
	local back = math.floor(E.STARTER.robux * E.COIN_PACKS[1].coins / E.COIN_PACKS[1].robux)
	check(
		d.coins == after + back and back == 2020 and #d.balls == 1,
		"a second starter purchase gives its Robux back as coins at the 49 R$ pack rate, not a second pack"
	)
end

do
	local d = fresh()
	table.insert(d.balls, 0)
	local coins = d.coins
	check(
		Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "granted",
		"an old look receipt grants the look"
	)
	check(
		d.looks[1] == "frame_wood" and d.coins == coins and #d.receipts == 1 and #d.balls == 1,
		"the grant owns the look and spends no coins"
	)
	check(
		Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "already",
		"the same cosmetic receipt adds nothing"
	)
	local c1 = d.coins
	check(
		Receipt.apply(d, receipt(9301, "look-2"), USER, cat, E, {}) == "granted" and #d.looks == 1,
		"a second purchase of an owned look is acknowledged once"
	)
	check(d.coins == c1 + E.LOOKS[1].coins, "an owned look's coin price comes back")
end

-- The chosen ball came meanwhile (spin, level, VOID): coins of the tier, the receipt is granted once.
do
	local d = fresh()
	local RARE = E.TIERS.rare[1]
	check(Receipt.choose(d, "ball", RARE, E), "rare chosen")
	table.insert(d.balls, RARE)
	local r = Receipt.apply(d, receipt(9102, "late-1"), USER, cat, E, {})
	check(r == "granted" and d.coins == E.PRICE.coins.rare and d.robuxBall == -1, "owned ball -> rare coins")
	check(#d.balls == 1, "no second copy of the ball")
	check(
		Receipt.apply(d, receipt(9102, "late-1"), USER, cat, E, {}) == "already" and d.coins == E.PRICE.coins.rare,
		"the retried receipt pays nothing more"
	)
end

-- Starter whose chosen epic came meanwhile: the pack is paid, the epic as its coin price.
do
	local d = fresh()
	check(Receipt.choose(d, "epic", EPIC, E), "epic chosen")
	table.insert(d.balls, EPIC)
	check(Receipt.apply(d, receipt(9201, "st-late"), USER, cat, E, {}) == "granted", "late starter granted")
	check(
		d.starterBought and d.coins == E.STARTER.coins + E.PRICE.coins.epic and #d.balls == 1,
		"late starter: pack coins plus the epic's coin price"
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
