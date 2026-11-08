--!strict
-- Parity with the web build on its own 20x24 field and web PACE: averages per match.
-- lune run tests/parity [ffa matches] [duel rounds]
-- WEB numbers: node one-off script over ball_territory_web/public/game.js, seedRandom(12345),
-- 2000 four-player matches (pickFree) and 1000 duel rounds (pairs a = r % 27, b = (a + 1 + r // 27 % 26) % 27).
local process = require("@lune/process")
local Rules = require("@rules")
local Sim = require("./Sim")

local Config = Rules.Config
local NEL = Config.NEL

local WEB = {
	ffa = { reactions = 15.282, powers = 34.494, kos = 6.68, firstPower = 2.1848, kinds = 42 },
	duel = { reactions = 4.562, powers = 7.644, kos = 0.789, firstPower = 3.5336, kinds = 42 },
}
-- stylua: ignore
local WEB_WINS = {
	ffa = { 26.9, 19.9, 26.8, 27.0, 22.3, 24.3, 25.7, 24.0, 24.5, 28.0, 24.0, 20.8, 27.9, 19.8, 23.7, 33.3, 27.3, 23.2, 25.2, 25.4, 26.2, 26.3, 23.2, 24.4, 26.1, 26.7, 23.9 },
	duel = { 46.7, 54.1, 52.0, 56.8, 43.9, 48.6, 28.4, 64.9, 47.3, 49.3, 50.0, 43.2, 48.0, 36.5, 56.8, 60.8, 48.6, 54.1, 51.4, 54.1, 51.4, 39.9, 53.4, 53.4, 58.8, 50.7, 47.3 },
}

local RF = tonumber(process.args[1]) or 2000
local RD = tonumber(process.args[2]) or 1000

local function duelRounds(R: number): Sim.Stats
	local st = Sim.newStats()
	for r = 0, R - 1 do
		local a = r % NEL
		local b = (a + 1 + (r // NEL) % (NEL - 1)) % NEL
		Sim.play(
			st,
			{ a, b },
			{ layout = "webDuel", pace = Config.WEB_DUEL_PACE, round = Config.DUEL_ROUND, seed = 777 + r }
		)
	end
	return st
end

local failed = false
local function report(name: string, st: Sim.Stats, web: { [string]: number }, webWins: { number })
	local R = st.matches
	local kinds = Sim.rxKinds(st)
	type Row = { name: string, web: number, luau: number }
	local rows: { Row } = {
		{ name = "reactions", web = web.reactions, luau = st.reactions / R },
		{ name = "power presses", web = web.powers, luau = st.powers / R },
		{ name = "KOs", web = web.kos, luau = st.kos / R },
		{ name = "first power, s", web = web.firstPower, luau = st.firstPower / math.max(1, st.firstPowerN) },
		{ name = "reaction kinds", web = web.kinds, luau = kinds },
	}
	print(`\n{name}: {R} matches, errors {st.errors}`)
	print("| metric | web | luau | diff |")
	print("|---|---|---|---|")
	for _, row in rows do
		local d = 100 * (row.luau - row.web) / row.web
		if math.abs(d) > 15 then
			failed = true
		end
		print(string.format("| %s | %.2f | %.2f | %+.1f%% |", row.name, row.web, row.luau, d))
	end
	local rates = Sim.rates(st)
	local maxd = 0
	for e = 1, NEL do
		maxd = math.max(maxd, math.abs(rates[e] - webWins[e]))
	end
	print(string.format("win share: max |luau - web| %.1f points", maxd))
	print("luau " .. Sim.ratesLine(rates))
	if st.errors > 0 then
		failed = true
		print("first error: " .. tostring(st.firstError))
	end
end

report("4 players, 20x24", Sim.ffa(RF, "web", Config.WEB_PACE, 12345), WEB.ffa, WEB_WINS.ffa)
report("duel rounds, 14x16 arena", duelRounds(RD), WEB.duel, WEB_WINS.duel)
if failed then
	print("\nPARITY FAIL: an average differs from the web by more than 15%")
	process.exit(1)
end
print("\nPARITY OK")
