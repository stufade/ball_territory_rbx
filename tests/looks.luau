--!strict
-- Cosmetic shelf: locked at 26/27, a coin buy at 27/27, a second buy spends nothing.
-- lune run tests/looks
local process = require("@lune/process")
local Economy = require("../src/shared/Economy")
local Looks = require("../src/server/Logic/Looks")
local Progress = require("../src/server/Logic/Progress")
local Products = require("../src/server/Products")

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
local CHEAP = E.LOOKS[1]

local function balls(n: number): Progress.Data
	local d = Progress.new()
	for e = 0, n - 1 do
		table.insert(d.balls, e)
	end
	return d
end

check(CHEAP.id == "frame_wood", "the cheapest look is frame_wood")

do
	local d = balls(26)
	d.coins = 100000
	local before = d.coins
	check(Looks.buy(d, CHEAP.id, E, {}) == nil, "26/27 refuses the coin buy")
	check(d.coins == before and #d.looks == 0, "26/27 spends nothing and owns nothing")
	check(Looks.grant(d, CHEAP.id, E) == "wait", "26/27 does not grant a Robux look")
	check(#d.looks == 0, "a refused grant is not owned")
	-- 27 entries, but one ball twice: still 26 unique
	table.insert(d.balls, 0)
	check(#d.balls == 27 and Looks.count(d) == 26, "a duplicate ball does not complete the set")
	check(Looks.buy(d, CHEAP.id, E, {}) == nil, "26 unique balls still refuse")
end

do
	local d = balls(27)
	check(Looks.count(d) == 27, "27 unique balls open the shelf")
	d.coins = CHEAP.coins - 1
	check(Looks.buy(d, CHEAP.id, E, {}) == nil and d.coins == CHEAP.coins - 1, "a short balance refuses")
	check(#d.looks == 0, "a short balance owns nothing")
	d.coins = CHEAP.coins
	local log = {}
	local hit = Looks.buy(d, CHEAP.id, E, log)
	check(
		hit ~= nil and hit.already == false and hit.n == CHEAP.coins and d.coins == 0 and d.looks[1] == CHEAP.id,
		"27/27 spends the coin price and owns the look"
	)
	check(#log == 1 and log[1].sink and log[1].cur == "coins" and log[1].n == CHEAP.coins, "the spend is one coin sink")
	check(#d.balls == 27, "a look does not change the balls")
	local again = Looks.buy(d, CHEAP.id, E, {})
	check(
		again ~= nil and again.already and again.n == 0 and d.coins == 0 and #d.looks == 1,
		"the same id spends nothing"
	)
	check(Looks.buy(d, "nope", E, {}) == nil and Looks.buy(d, 1, E, {}) == nil, "an unknown id is refused")
	local skin = Looks.buy(d, "skin_ink", E, {})
	check(skin == nil and d.coins == 0, "the next look still needs its own price")
	d.coins = 2500
	check(Looks.buy(d, "skin_ink", E, {}) ~= nil and #d.looks == 2, "a second id spends its own price")
	local ballsBefore = table.clone(d.balls)
	check(
		Looks.wear(d, "skin_ink", 3, E) and d.worn.skin == "skin_ink" and d.worn.ball == 3,
		"a skin equips on an owned ball"
	)
	check(
		Looks.wear(d, CHEAP.id, nil, E) and d.worn.frame == CHEAP.id and d.worn.skin == "skin_ink",
		"a frame does not clear the skin"
	)
	check(not Looks.wear(d, "trail_dust", nil, E), "an unowned look does not equip")
	check(table.concat(d.balls, ",") == table.concat(ballsBefore, ","), "equipping does not change the balls")
	local view = Looks.snapshot(d, E, Products)
	check(view.n == 27 and view.need == 27 and view.owned[1] == CHEAP.id, "the shelf view lists the owned look")
	check(view.robux[CHEAP.id] == nil, "a placeholder product id is not offered")
	local priced = Looks.snapshot(d, E, { looks = { frame_wood = 9301, skin_ink = 0 } })
	check(priced.robux.frame_wood == 9301 and priced.robux.skin_ink == nil, "only a live product id is sent")
end

do
	local saved = balls(27)
	saved.looks = { "frame_wood", "frame_wood", "not_a_look" }
	saved.worn =
		{ skin = "skin_ink", trail = "", force = "", frame = "frame_wood", podium = true, ko = false, ball = 4 }
	saved.coins = 40
	local d = Progress.migrate(saved)
	check(
		d.coins == 40 and d.looks[1] == "frame_wood" and d.looks[2] == "not_a_look" and #d.looks == 2,
		"owned looks survive a save, once"
	)
	check(d.worn.frame == "frame_wood" and d.worn.skin == "skin_ink", "the equipped row survives a save")
	Progress.repair(d, { ECON = E, BASE_BALLS = {}, TIERS = E.TIERS, XP = {} } :: any, nil)
	check(#d.looks == 1 and d.worn.frame == "frame_wood" and d.worn.skin == "", "unknown and unowned looks are cleared")
	check(not d.worn.podium, "an unowned podium is cleared")
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("LOOKS OK")
