--!strict
-- Logic/Pay: the server opens a Robux prompt only for something it can still deliver.
-- lune run tests/pay
local process = require("@lune/process")
local Economy = require("../src/shared/Economy")
local Pay = require("../src/server/Logic/Pay")
local Products = require("../src/server/Products")
local Progress = require("../src/server/Logic/Progress")

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
local none: { [string]: boolean } = {}
local EPIC = E.TIERS.epic[1]
local RARE = E.TIERS.rare[1]

do
	local d = Progress.new()
	local o = Pay.offer(d, "pack", 6, E, Products, false, none)
	check(o and o.product == Products.crystals[6], "a crystal pack opens its product")
	check(Pay.offer(d, "pack", 7, E, Products, false, none) == nil, "no 7th pack")
	check(Pay.offer(d, "pack", 0 / 0, E, Products, false, none) == nil, "NaN pack refused")
	check(Pay.offer(d, 5, 1, E, Products, false, none) == nil, "a non-string key is refused")
	check(Pay.offer(d, string.rep("x", 40), 1, E, Products, false, none) == nil, "a long key is refused")
end

do
	local d = Progress.new()
	local o = Pay.offer(d, "ball", RARE, E, Products, false, none)
	check(o and o.product == Products.ball.rare and d.robuxBall == RARE, "a missing ball opens its tier, choice kept")
	table.insert(d.balls, RARE)
	local no, why = Pay.offer(d, "ball", RARE, E, Products, false, none)
	check(no == nil and why == "owned", "an owned ball opens nothing")
	check(Pay.offer(d, "ball", 27, E, Products, false, none) == nil, "ball 27 refused")
end

do
	local d = Progress.new()
	check(Pay.offer(d, "starter", RARE, E, Products, false, none) == nil, "the starter epic must be an epic")
	local o = Pay.offer(d, "starter", EPIC, E, Products, false, none)
	check(o and o.product == Products.starter and d.robuxEpic == EPIC, "starter opens with its epic")
	d.starterBought = true
	local no, why = Pay.offer(d, "starter", EPIC, E, Products, false, none)
	check(no == nil and why == "owned", "a second starter pack opens nothing")
end

do
	local d = Progress.new()
	local o = Pay.offer(d, "skin_ink", nil, E, Products, false, none)
	check(o and o.product == Products.looks.skin_ink, "a look opens its product")
	table.insert(d.looks, "skin_ink")
	local no, why = Pay.offer(d, "skin_ink", nil, E, Products, false, none)
	check(no == nil and why == "owned", "an owned look opens nothing")
	check(Pay.offer(d, "not_a_look", nil, E, Products, false, none) == nil, "an unknown look opens nothing")
end

do
	local d = Progress.new()
	local o = Pay.offer(d, "pass_coins2x", nil, E, Products, false, none)
	check(o and o.pass == Products.passes.coins2x and o.product == nil, "a pass opens the pass prompt")
	local no, why = Pay.offer(d, "pass_coins2x", nil, E, Products, false, { coins2x = true })
	check(no == nil and why == "owned", "an owned pass opens nothing")
	local fs = Pay.offer(d, "pass_fastSpin", nil, E, Products, false, none)
	check(fs and fs.pass == Products.passes.fastSpin, "Fast Spin is offered where paid random is allowed")
	local blocked, bwhy = Pay.offer(d, "pass_fastSpin", nil, E, Products, true, none)
	check(blocked == nil and bwhy == "policy", "Fast Spin is not offered under a paid-random ban")
	check(Pay.offer(d, "pass_nope", nil, E, Products, false, none) == nil, "an unknown pass opens nothing")
	local list = Pay.passOffers(E, Products, true, { vip = true })
	check(list.coins2x and not list.vip and not list.fastSpin, "pass offers: not owned, no Fast Spin when blocked")
	local open = Pay.passOffers(E, Products, false, none)
	check(open.coins2x and open.vip and open.fastSpin, "pass offers: all three when allowed")
end

do
	local best, rate = 0, 0
	for i, p in E.CRYSTAL_PACKS do
		if p.crystals / p.robux > rate then
			best, rate = i, p.crystals / p.robux
		end
	end
	for i, p in E.CRYSTAL_PACKS do
		check((p.best == true) == (i == best), `best value badge only on the most crystals per Robux (pack {i})`)
	end
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("PAY OK")
