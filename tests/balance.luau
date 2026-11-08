--!strict
-- M1-1 and M1-3: four-player bot matches on the 24x20 field.
-- lune run tests/balance [matches]   (2000 by default)
-- Passes when every element wins 18-32%, there are no errors and all 42 reactions happened.
local process = require("@lune/process")
local Rules = require("@rules")
local Sim = require("./Sim")

local Config = Rules.Config
local R = tonumber(process.args[1]) or 2000

local st = Sim.ffa(R, "ffa", Config.PACE, 2026)
local rates = Sim.rates(st)
print(Sim.summary(st))
print("win share " .. Sim.ratesLine(rates))

local lo, hi = math.huge, -math.huge
local outside = {}
for e = 0, Config.NEL - 1 do
	local v = rates[e + 1]
	lo, hi = math.min(lo, v), math.max(hi, v)
	if v < 18 or v > 32 then
		table.insert(outside, string.format("%s %.1f", Config.TITLE[e], v))
	end
end
print(string.format("win share min %.1f max %.1f, outside 18-32%%: %d", lo, hi, #outside))

local kinds, missing = Sim.rxKinds(st)
local counts = {}
for _, k in Config.REACTIONS do
	table.insert(counts, `{k} {st.rx[k] or 0}`)
end
print(`reactions seen: {kinds} of {#Config.REACTIONS}`)
print("  " .. table.concat(counts, ", "))

local strong, weak = Sim.table(st, 60, 40, 20)
print("who beats whom (4 players):")
print(Sim.luaTable("STRONG", strong))
print(Sim.luaTable("WEAK", weak))

local ok = st.errors == 0 and #outside == 0 and #missing == 0
if st.errors > 0 then
	print("first error: " .. tostring(st.firstError))
end
if #outside > 0 then
	print("outside: " .. table.concat(outside, ", "))
end
if #missing > 0 then
	print("missing reactions: " .. table.concat(missing, ", "))
end
print(if ok then "BALANCE OK" else "BALANCE FAIL")
if not ok then
	process.exit(1)
end
