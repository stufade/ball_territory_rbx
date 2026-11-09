--!strict
-- Pure server modules: queue, draft offers, input guard, weak bot. lune run tests/server
local process = require("@lune/process")
local Rules = require("@rules")
local Guard = require("../src/server/Logic/Guard")
local Offers = require("../src/server/Logic/Offers")
local Queue = require("../src/server/Logic/Queue")
local WeakBot = require("../src/server/Logic/WeakBot")
local Net = require("../src/shared/Net")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

-- Queue -----------------------------------------------------------------------
do
	local q = Queue.new(5, { duel = 2, ffa = 4 })
	check(not Queue.join(q, 1, "solo", 0), "unknown mode")
	check(Queue.join(q, 1, "duel", 0), "join duel")
	check(#Queue.poll(q, 1, { duel = 3, ffa = 1 }) == 0, "alone, waiting")
	check(Queue.deadline(q, 1) == 5, "deadline")
	Queue.join(q, 2, "duel", 2)
	local g = Queue.poll(q, 2, { duel = 3, ffa = 1 })
	check(#g == 1 and g[1].mode == "duel" and #g[1].ids == 2 and g[1].ids[1] == 1, "two people pair at once")
	check(Queue.mode(q, 1) == nil, "left queue after group")

	Queue.join(q, 3, "duel", 10)
	check(#Queue.poll(q, 14.9, { duel = 1 }) == 0, "before 5 s")
	local free = { duel = 0 }
	check(#Queue.poll(q, 15, free) == 0, "no free arena, keep waiting")
	free = { duel = 1 }
	g = Queue.poll(q, 15.1, free)
	check(#g == 1 and #g[1].ids == 1 and free.duel == 0, "after 5 s alone, bot fills")

	for id = 10, 15 do
		Queue.join(q, id, "ffa", 20)
	end
	g = Queue.poll(q, 20, { ffa = 1 })
	check(#g == 1 and #g[1].ids == 4, "ffa full group of 4")
	check(Queue.count(q, "ffa") == 2, "two left in ffa")
	check(#Queue.poll(q, 21, { ffa = 1 }) == 0, "2 of 4, still waiting")
	check(#Queue.poll(q, 25, { ffa = 1 })[1].ids == 2, "ffa with bots after 5 s")

	Queue.join(q, 30, "duel", 30)
	Queue.join(q, 30, "ffa", 31)
	check(Queue.mode(q, 30) == "ffa" and Queue.count(q, "duel") == 0, "switching mode leaves the old queue")
	check(Queue.leave(q, 30) and not Queue.leave(q, 30), "cancel once")
end

-- Draft offers ----------------------------------------------------------------
do
	local rand = Rules.Rng.new(5)
	local seenOffer = {}
	for run = 1, 200 do
		local o = Offers.new(Rules, run % 2 == 0, 3, 1, rand)
		local order = {}
		local usedAny = { false, false }
		while not Offers.done(o) do
			local side = Offers.turn(o)
			table.insert(order, side)
			local offer = Offers.offerFor(o, side)
			check(#offer == 3, "3 balls offered")
			check(#Offers.offerFor(o, 1 - side) == 0, "no offer off turn")
			for _, e in offer do
				seenOffer[e] = true
				check(Rules.Duel.draftFree(o.draft, e), "offer is free")
			end
			check(offer[1] ~= offer[2] and offer[2] ~= offer[3] and offer[1] ~= offer[3], "offer has no repeats")
			check(not Offers.pick(o, 1 - side, offer[1]), "pick off turn refused")
			local r = run % 4
			if r == 0 then
				Offers.bot(o)
			elseif r == 1 then
				Offers.timeout(o)
			elseif r == 2 and not usedAny[side + 1] then
				-- any free ball outside the offer
				local e = -1
				for x = 0, 26 do
					if Rules.Duel.draftFree(o.draft, x) and not table.find(offer, x) then
						e = x
						break
					end
				end
				check(Offers.any(o, side, e), "any ball")
				usedAny[side + 1] = true
				check(not Offers.canAny(o, side), "any used up")
			else
				local free = -1
				for x = 0, 26 do
					if Rules.Duel.draftFree(o.draft, x) and not table.find(offer, x) then
						free = x
						break
					end
				end
				check(not Offers.pick(o, side, free), "ball outside the offer refused")
				check(not Offers.pick(o, side, 0 / 0), "NaN refused")
				check(Offers.pick(o, side, offer[2]), "pick from offer")
			end
		end
		local first = if run % 2 == 0 then 1 else 0
		local want = { first, 1 - first, 1 - first, first, first, 1 - first }
		check(table.concat(order, ",") == table.concat(want, ","), "order 1-2-2-1")
		local teams = Offers.teams(o)
		check(#teams[1] == 3 and #teams[2] == 3, "3 balls each")
		local all = {}
		for _, t in teams do
			for _, e in t do
				check(not all[e], "no ball twice")
				all[e] = true
			end
		end
		local d = Rules.Duel.new(teams, { "1", nil })
		check(#Rules.Duel.need(d) == 2, "duel starts with both choosing")
	end
	local n = 0
	for _ in seenOffer do
		n += 1
	end
	check(n == 27, "every ball shows up in offers")
end

-- Guard -----------------------------------------------------------------------
do
	local nan, inf = 0 / 0, math.huge
	local M = Net.Limits.dirMax
	check(Guard.input(1, 1, 0, M) == 1, "aim ok")
	check(Guard.input(1, nan, 0, M) == nil, "NaN dx")
	check(Guard.input(3, 0, inf, M) == nil, "inf dy")
	check(Guard.input(3, 0, 0, M) == nil, "zero direction")
	check(Guard.input(3, "1", 0, M) == nil, "string dx")
	check(Guard.input(3, {}, 0, M) == nil, "table dx")
	check(Guard.input(5, 1, 1, M) == nil, "unknown kind")
	check(Guard.input(1.5, 1, 1, M) == nil, "fractional kind")
	check(Guard.input(nil, 1, 1, M) == nil, "nil kind")
	check(Guard.input(4, nan, nil, M) == 4, "power ignores args")
	check(Guard.input(2, nil, nil, M) == 2, "launch without direction")
	local _, x, y = Guard.input(3, 1e9, -1e9, M)
	check(x == M and y == -M, "clamped")
	check(Guard.action("queue", 1, Net.Action) == "queue", "verb ok")
	check(Guard.action("hack", 1, Net.Action) == nil, "unknown verb")
	check(Guard.action("pick", nan, Net.Action) == nil, "NaN arg")
	check(Guard.action(5, 1, Net.Action) == nil, "number verb")
	check(Guard.action(string.rep("q", 100), 1, Net.Action) == nil, "long verb")
	check(Guard.element(26, 27) == 26 and Guard.element(27, 27) == nil, "element range")
	check(Guard.element(-1, 27) == nil and Guard.element(2.5, 27) == nil, "element integer")

	-- 20/s with burst 10: spam of 100 in 1 s lets through about 30
	local b = Guard.bucket(Net.Limits.inputRate, Net.Limits.inputBurst, 0)
	local ok = 0
	for i = 0, 99 do
		if Guard.take(b, i / 100) then
			ok += 1
		end
	end
	check(ok >= 28 and ok <= 31, `bucket spam passed {ok}`)
	ok = 0
	for i = 1, 40 do
		if Guard.take(b, 10 + i * 0.05) then
			ok += 1
		end
	end
	check(ok == 40, "20/s steady passes")
	check(not Guard.tapOk(1.0, 1.19, 0.2) and Guard.tapOk(1.0, 1.2, 0.2) and Guard.tapOk(nil, 0, 0.2), "final tap gap")
end

-- Weak bot --------------------------------------------------------------------
do
	-- normal bot on Fire against a weak bot on a ball Fire beats: the normal bot wins most rounds
	local wins, rounds = 0, 60
	local rand = Rules.Rng.new(3)
	for i = 1, rounds do
		local e = Rules.Config.FIRE
		local rival = Rules.Config.DSTRONG[e][(i % #Rules.Config.DSTRONG[e]) + 1]
		local S = Rules.newMatch({ { e = e }, { e = rival, ctl = "weak" } }, {
			layout = "duel",
			round = Rules.Config.DUEL_ROUND,
			pace = Rules.Config.DUEL_PACE,
			seed = i,
		})
		S.by[rival].prompts = false
		local w = WeakBot.new(rival, rand, { 2.5, 5 }, { 1.2, 2.4 })
		Rules.launch(S)
		local steps = 0
		while not S.done do
			Rules.step(S)
			WeakBot.step(w, Rules, S)
			steps += 1
		end
		check(S.by[rival].powers > 0, "weak bot still uses power")
		if Rules.leader(S) == e then
			wins += 1
		end
	end
	print(`weak bot: normal bot won {wins} of {rounds}`)
	check(wins >= rounds * 0.6, "weak bot is weaker")
end

print(`{passed} checks passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("SERVER OK")
