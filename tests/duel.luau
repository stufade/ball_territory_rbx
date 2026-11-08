--!strict
-- M1-2: full bot duels on the 16x14 arena: draft 1-2-2-1, bot ball choice, rounds until one side is out.
-- lune run tests/duel [duels] [pair reps]   (1000 duels; the who-beats-whom table plays every pair `reps` times, 10 by default, 0 to skip)
-- Passes when every element wins 40-60% of its rounds (a draw counts half) and there are no errors.
local process = require("@lune/process")
local Rules = require("@rules")
local Sim = require("./Sim")

local Config = Rules.Config
local NEL = Config.NEL
local R = tonumber(process.args[1]) or 1000
local REPS = tonumber(process.args[2]) or 10

local st, rounds = Sim.duels(R, Config.DUEL_PACE, 4242)

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
