--!strict
-- Cosmetic shelf: one ball can buy frame_wood, a second buy spends nothing, a short balance refuses.
-- lune run tests/looks
local process = require("@lune/process")
local Economy = require("../src/shared/Economy")
local Looks = require("../src/server/Logic/Looks")
local Progress = require("../src/server/Logic/Progress")
local Seats = require("../src/server/Logic/Seats")

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
	local d = balls(1)
	check(Looks.count(d) == 1, "one ball is not a full set")
	d.coins = CHEAP.coins
	local log = {}
	local hit = Looks.buy(d, CHEAP.id, E, log)
	check(
		hit ~= nil and hit.already == false and hit.n == CHEAP.coins and d.coins == 0 and d.looks[1] == CHEAP.id,
		"one ball buys frame_wood"
	)
	check(#log == 1 and log[1].sink and log[1].cur == "coins" and log[1].n == CHEAP.coins, "the spend is one coin sink")
	local again = Looks.buy(d, CHEAP.id, E, {})
	check(
		again ~= nil and again.already and again.n == 0 and d.coins == 0 and #d.looks == 1,
		"the same id spends nothing"
	)
	check(Looks.grant(d, CHEAP.id, E) == "have" and #d.looks == 1, "a second grant does not add a copy")

	local poor = balls(1)
	poor.coins = CHEAP.coins - 1
	check(
		Looks.buy(poor, CHEAP.id, E, {}) == nil and poor.coins == CHEAP.coins - 1 and #poor.looks == 0,
		"a short balance refuses"
	)
	check(Looks.grant(poor, CHEAP.id, E) == "ok" and poor.looks[1] == CHEAP.id, "a Robux grant does not need 27 balls")

	local partial = balls(26)
	partial.coins = CHEAP.coins
	table.insert(partial.balls, 0)
	check(#partial.balls == 27 and Looks.count(partial) == 26, "a duplicate ball does not complete the set")
	local bought = Looks.buy(partial, CHEAP.id, E, {})
	check(
		bought ~= nil and bought.already == false and partial.coins == 0 and partial.looks[1] == CHEAP.id,
		"26 unique balls still buy"
	)
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
	local view = Looks.snapshot(d, E)
	check(view.n == 27 and view.need == 27 and view.owned[1] == CHEAP.id, "the shelf view lists the owned look")
	check((view :: any).robux == nil, "E4: looks are coins only, no product ids are sent")
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
	check(
		#d.looks == 2 and d.looks[2] == "not_a_look" and d.worn.frame == "frame_wood" and d.worn.skin == "",
		"a retired id stays owned (maybe bought for Robux); an unowned worn look is cleared"
	)
	check(not d.worn.podium, "an unowned podium is cleared")
	local shelf = Looks.snapshot(d, E)
	check(#shelf.owned == 1 and shelf.owned[1] == "frame_wood", "the shelf only lists ids of the catalog")
end

-- A renamed look keeps its owner and its worn slot.
do
	Looks.RENAMED.frame_old = "frame_wood"
	local saved = balls(27)
	saved.looks = { "frame_old" }
	saved.worn = { skin = "", trail = "", force = "", frame = "frame_old", podium = false, ko = false, ball = -1 }
	local d = Progress.migrate(saved)
	Progress.repair(d, { ECON = E, BASE_BALLS = {}, TIERS = E.TIERS, XP = {} } :: any, nil)
	check(d.looks[1] == "frame_wood" and #d.looks == 1 and d.worn.frame == "frame_wood", "a renamed id migrates")
	saved.looks = { "frame_old", "frame_wood" }
	d = Progress.migrate(saved)
	Progress.repair(d, { ECON = E, BASE_BALLS = {}, TIERS = E.TIERS, XP = {} } :: any, nil)
	check(#d.looks == 1, "old and new id of one look count once")
	Looks.RENAMED.frame_old = nil
end

-- Bug 1 (wave 1116): the worn skin / trail / force / frame reach the match start seat rows; bots get none.
do
	local d = balls(3)
	d.looks = { "skin_ink", "trail_dust", "force_pulse", "frame_wood" }
	check(Looks.match(d, E) == nil, "nothing worn: no seat look")
	check(Looks.wear(d, "skin_ink", 1, E), "wear ink on ball 1")
	Looks.wear(d, "trail_dust", nil, E)
	Looks.wear(d, "force_pulse", nil, E)
	Looks.wear(d, "frame_wood", nil, E)
	local m = Looks.match(d, E)
	check(
		m ~= nil
			and m.skin == "skin_ink"
			and m.ball == 1
			and m.trail == "trail_dust"
			and m.force == "force_pulse"
			and m.frame == "frame_wood",
		"Looks.match carries skin, ball, trail, force, frame"
	)
	local person = { data = d }
	local rows = Seats.rows({
		{ e = 1, name = "Ann", userId = 7, side = 0, rec = person },
		{ e = 4, name = "BOT", userId = 0, side = 1, rec = nil },
	}, function()
		return false
	end, function(rec)
		return Looks.match(rec.data, E)
	end)
	local a, b = rows[1], rows[2]
	check(
		a.look ~= nil
			and a.look.skin == "skin_ink"
			and a.look.trail == "trail_dust"
			and a.look.force == "force_pulse"
			and a.look.frame == "frame_wood"
			and a.look.ball == a.e,
		"the person's seat row carries the worn looks"
	)
	check(b.look == nil and b.vip == nil and b.e == 4, "a bot seat has no look (default ball)")
	-- a worn id that is not owned (a hacked or rolled back profile) is not sent
	d.looks = { "trail_dust" }
	m = Looks.match(d, E)
	check(
		m ~= nil and m.skin == "" and m.ball == -1 and m.force == "" and m.frame == "" and m.trail == "trail_dust",
		"only owned looks"
	)
	d.looks, d.balls = { "skin_ink" }, { 2 }
	d.worn = { skin = "skin_ink", trail = "", force = "", frame = "", podium = false, ko = false, ball = 1 }
	check(Looks.match(d, E) == nil, "a skin on a ball no longer owned is not sent")
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("LOOKS OK")
