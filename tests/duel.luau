--!strict
-- M1-2: full bot duels on the 16x14 arena: draft 1-2-2-1, bot ball choice, rounds until one side is out.
-- lune run tests/duel [duels] [pair reps]   (1000 duels; the who-beats-whom table plays every pair `reps` times, 10 by default, 0 to skip)
-- Passes when every element wins 40-60% of its rounds (a draw counts half) and there are no errors.
local process = require("@lune/process")
local Rules = require("@rules")
local Sim = require("./Sim")

local Config, Duel = Rules.Config, Rules.Duel
local NEL = Config.NEL
local R = tonumber(process.args[1]) or 1000
local REPS = tonumber(process.args[2]) or 10

local st = Sim.newStats()
local rounds = 0
local rand = Rules.Rng.new(4242)
for r = 1, R do
	local ok, err = pcall(function()
		local d = Duel.newDraft(rand() < 0.5)
		while not Duel.draftDone(d) do
			local side = Duel.draftTurn(d)
			assert(Duel.draftPick(d, side, Duel.botDraft(d, side, rand)), "bad draft pick")
		end
		local duel = Duel.new(d.teams, { nil, nil })
		local n = 0
		while not duel.done do
			for _, side in Duel.need(duel) do
				assert(Duel.choose(duel, side, Duel.botChoose(duel, side, rand)), "bad choice")
			end
			n += 1
			local els = { duel.cur[1], duel.cur[2] }
			local S = Sim.play(
				st,
				els,
				{ layout = "duel", pace = Config.DUEL_PACE, round = Config.DUEL_ROUND, seed = r * 100 + n }
			)
			assert(S, "round failed")
			duel.round += 1
			duel.game = S
			Duel.endRound(duel)
			rounds += 1
			assert(n < 10, "duel too long")
		end
	end)
	if not ok then
		st.errors += 1
		st.firstError = st.firstError or tostring(err)
	end
end

local rates = Sim.rates(st)
print(`duels {R}, rounds {rounds} ({string.format("%.2f", rounds / R)} per duel)`)
print(Sim.summary(st))
print("round win share " .. Sim.ratesLine(rates))
local lo, hi = math.huge, -math.huge
local outside = {}
for e = 0, NEL - 1 do
	local v = rates[e + 1]
	lo, hi = math.min(lo, v), math.max(hi, v)
	if v < 40 or v > 60 then
		table.insert(outside, string.format("%s %.1f", Config.TITLE[e], v))
	end
end
print(string.format("round win share min %.1f max %.1f, outside 40-60%%: %d", lo, hi, #outside))

if REPS > 0 then
	local ps = Sim.pairs(REPS, "duel", Config.DUEL_PACE, 99)
	print(`who beats whom (every pair x{REPS}): pair round win share ` .. Sim.ratesLine(Sim.rates(ps)))
	local hard = 0
	for a = 1, NEL do
		for b = a + 1, NEL do
			local p = 100 * ps.above[a][b] / ps.met[a][b]
			local q = 100 * ps.above[b][a] / ps.met[a][b]
			if p >= 80 or q >= 80 then
				hard += 1
			end
		end
	end
	print(`pairs 80%+ one-sided: {hard} of {NEL * (NEL - 1) / 2}`)
	local strong, weak = Sim.table(ps, 65, 35, 0)
	print(Sim.luaTable("DSTRONG", strong))
	print(Sim.luaTable("DWEAK", weak))
end

local ok = st.errors == 0 and #outside == 0
if st.errors > 0 then
	print("first error: " .. tostring(st.firstError))
end
if #outside > 0 then
	print("outside: " .. table.concat(outside, ", "))
end
print(if ok then "DUEL OK" else "DUEL FAIL")
if not ok then
	process.exit(1)
end
