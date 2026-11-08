--!strict
-- Tunes the power charge speed per element, like test/tune.mjs in the web build.
-- lune run tests/tune [matches per try] [tries]        -> PACE: each element wins 20-30% of four-player matches
-- lune run tests/tune duel [pair reps] [tries]         -> DUEL_PACE: each element wins 40-60% of duel rounds, every pair
-- lune run tests/tune duels [duels] [tries]            -> DUEL_PACE on full bot duels with draft and counter-picks (M1-2)
-- Starts from Config values and prints the new table to paste into Config.luau.
local process = require("@lune/process")
local Rules = require("@rules")
local Sim = require("./Sim")

local Config = Rules.Config
local NEL = Config.NEL
local FULL = process.args[1] == "duels"
local DUEL = process.args[1] == "duel" or FULL
local first = if DUEL then 2 else 1
local R = tonumber(process.args[first]) or (if FULL then 2000 elseif DUEL then 4 else 2000)
local TRIES = tonumber(process.args[first + 1]) or 8
local K = table.clone(if DUEL then Config.DUEL_PACE else Config.PACE)
local LO, HI = if DUEL then 40 else 20, if DUEL then 60 else 30
local MID = (LO + HI) / 2

local function line(k: { [number]: number }): string
	local parts = {}
	for e = 0, NEL - 1 do
		table.insert(parts, tostring(k[e]))
	end
	return "{ [0] = " .. table.concat(parts, ",") .. " }"
end

for t = 1, TRIES do
	local st = if FULL
		then (Sim.duels(R, K, 500 + t))
		elseif DUEL then Sim.pairs(R, "duel", K, 500 + t)
		else Sim.ffa(R, "ffa", K, 500 + t)
	local wr = Sim.rates(st)
	local out, lo, hi = 0, math.huge, -math.huge
	for e = 1, NEL do
		lo, hi = math.min(lo, wr[e]), math.max(hi, wr[e])
		if wr[e] < LO or wr[e] > HI then
			out += 1
		end
	end
	print(
		string.format("try %d: outside %d-%d%%: %d  min %.1f  max %.1f  errors %d", t, LO, HI, out, lo, hi, st.errors)
	)
	print("  " .. Sim.ratesLine(wr))
	if out == 0 then
		break
	end
	for e = 0, NEL - 1 do
		local v = wr[e + 1]
		if v >= LO + 1 and v <= HI - 1 then
			continue
		end
		local k = math.max(0.75, math.min(1.35, (MID / math.max(5, v)) ^ (if DUEL then 1.2 else 0.7)))
		K[e] = math.max(0.35, math.min(4, math.floor(K[e] * k * 100 + 0.5) / 100))
	end
	print("  PACE " .. line(K))
end
print(`Config.{if DUEL then "DUEL_PACE" else "PACE"} = ` .. line(K))
