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

-- Live table: placeholders only. A receipt against it grants nothing.
do
	check(#Products.crystals == #E.CRYSTAL_PACKS, "one placeholder id per crystal pack")
	for _, id in Products.crystals do
		check(id == 0, "crystal product id is not a live asset id")
	end
	for _, id in Products.ball do
		check(id == 0, "ball product id is not a live asset id")
	end
	check(Products.starter == 0, "starter product id is not a live asset id")
	for _, look in E.LOOKS do
		check(Products.looks[look.id] == 0, `look {look.id} product id is not a live asset id`)
	end
	local live = Receipt.index(E, Products)
	local n = 0
	for _ in live do
		n += 1
	end
	check(n == 0, "placeholder ids are not for sale")
	local d = fresh()
	check(Receipt.apply(d, receipt(0, "live-0"), USER, live, E, {}) == "later", "product 0 is refused")
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
	check(Receipt.apply(d, receipt(9101, "ball-none"), USER, cat, E, {}) == "later", "a ball with no choice is refused")
	check(#d.balls == 0 and #d.receipts == 0, "a ball with no choice is not acknowledged")
	check(not Receipt.choose(d, "ball", 99, E), "a ball id outside the roster is refused")
	check(Receipt.choose(d, "ball", 0, E) and d.robuxBall == 0, "the server remembers the chosen ball")
	check(Receipt.apply(d, receipt(9104, "ball-wrong-tier"), USER, cat, E, {}) == "later", "the wrong tier is refused")
	check(#d.balls == 0 and d.robuxBall == 0, "the wrong tier keeps the choice")
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
	check(Receipt.apply(d, receipt(9201, "st-none"), USER, cat, E, {}) == "later", "a starter with no epic is refused")
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
	check(d.crystals == after and d.coins == coins + E.STARTER.coins, "a second starter purchase adds nothing")
end

do
	local d = fresh()
	check(
		Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "later",
		"a cosmetic waits until all 27 balls are owned"
	)
	check(#d.receipts == 0 and #d.looks == 0, "a locked cosmetic receipt is not acknowledged")
	for e = 0, 26 do
		table.insert(d.balls, e)
	end
	local coins = d.coins
	check(Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "granted", "a full collection grants the look")
	check(
		d.looks[1] == "frame_wood" and d.coins == coins and #d.receipts == 1,
		"the grant owns the look and spends no coins"
	)
	check(
		Receipt.apply(d, receipt(9301, "look-1"), USER, cat, E, {}) == "already",
		"the same cosmetic receipt adds nothing"
	)
	check(
		Receipt.apply(d, receipt(9301, "look-2"), USER, cat, E, {}) == "granted" and #d.looks == 1,
		"a second purchase of an owned look is acknowledged once"
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
