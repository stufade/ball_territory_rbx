-- Step-by-step comparison with the web build on its 20x24 field (same seed, same elements).
-- lune run tests/trace <seed> ffa|duel <elements...> > l.txt; node tests/web/trace.mjs <same args> > j.txt
-- Lines are: tick, owner hash, layer hash, reactions, then x,y,charge,hp of every ball.
local Rules = require("@rules")
local process = require("@lune/process")
local seed, mode = tonumber(process.args[1]), process.args[2]
local els = {}
for i = 3, #process.args do
	table.insert(els, { e = tonumber(process.args[i]) :: number })
end
local S = if mode == "duel"
	then Rules.newMatch(els, { layout = "webDuel", round = 30, pace = Rules.Config.WEB_DUEL_PACE, seed = seed })
	else Rules.newMatch(els, { layout = "web", pace = Rules.Config.WEB_PACE, seed = seed })
Rules.launch(S)
local out = {}
local function f(v)
	return string.format("%.17g", v)
end
local LN = { "water", "ice", "bush", "burn", "toxic", "sand", "lava", "slime", "rock", "glass", "shock", "gas" }
local function dump()
	local h = 0
	for k = 1, S.N do
		h = (h * 31 + S.owner[k] + 2) % 1000000007
	end
	local lh = 0
	for _, n in LN do
		for k = 1, S.N do
			lh = (lh * 7 + (if S.L[n][k] > 0 then 1 else 0)) % 1000000007
		end
	end
	local bs = {}
	for _, b in S.balls do
		table.insert(bs, f(b.x) .. "," .. f(b.y) .. "," .. f(b.charge) .. "," .. f(b.hp))
	end
	table.insert(out, `{S.tick} {h} {lh} {S.reactions} ` .. table.concat(bs, " "))
end
dump()
while not S.done do
	Rules.step(S)
	Rules.drain(S)
	dump()
end
print(table.concat(out, "\n"))
