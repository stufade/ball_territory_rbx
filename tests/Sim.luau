--!strict
-- Bot simulations shared by balance, duel, tune and parity tests.
local Rules = require("@rules")

local Config = Rules.Config
local NEL = Config.NEL

local Sim = {}

export type Stats = {
	matches: number,
	errors: number,
	firstError: string?,
	steps: number,
	stepTime: number,
	maxStep: number,
	reactions: number,
	powers: number,
	kos: number,
	firstPower: number,
	firstPowerN: number,
	wins: { number },
	games: { number },
	above: { { number } },
	met: { { number } },
	rx: { [string]: number },
}

local function grid(): { { number } }
	local t = {}
	for a = 1, NEL do
		t[a] = table.create(NEL, 0)
	end
	return t
end

function Sim.newStats(): Stats
	return {
		matches = 0,
		errors = 0,
		firstError = nil,
		steps = 0,
		stepTime = 0,
		maxStep = 0,
		reactions = 0,
		powers = 0,
		kos = 0,
		firstPower = 0,
		firstPowerN = 0,
		wins = table.create(NEL, 0),
		games = table.create(NEL, 0),
		above = grid(),
		met = grid(),
		rx = {},
	}
end

-- Plays one bot match to the end and adds it to st. Returns the final state.
function Sim.play(st: Stats, els: { number }, opts: Rules.Options): Rules.State?
	local ok, res = pcall(function(): Rules.State
		local seats = {}
		for _, e in els do
			table.insert(seats, { e = e })
		end
		local S = Rules.newMatch(seats, opts)
		Rules.launch(S)
		Rules.drain(S)
		local fp = -1
		local clock = os.clock
		local n = 0
		local total, worst = 0, 0
		while not S.done do
			local t0 = clock()
			Rules.step(S)
			local dt = clock() - t0
			total += dt
			if dt > worst then
				worst = dt
			end
			n += 1
			for _, ev in Rules.drain(S) do
				if ev.kind == "power" then
					st.powers += 1
					if fp < 0 then
						fp = S.t
					end
				elseif ev.kind == "ko" then
					st.kos += 1
				end
			end
		end
		st.stepTime += total
		st.maxStep = math.max(st.maxStep, worst)
		st.steps += n
		if fp >= 0 then
			st.firstPower += fp
			st.firstPowerN += 1
		end
		return S
	end)
	st.matches += 1
	if not ok then
		st.errors += 1
		st.firstError = st.firstError or tostring(res)
		return nil
	end
	local S = res
	st.reactions += S.reactions
	for k, v in S.rxCount do
		st.rx[k] = (st.rx[k] or 0) + v
	end
	local c = S.counts
	for _, a in els do
		st.games[a + 1] += 1
		for _, b in els do
			if a ~= b then
				st.met[a + 1][b + 1] += 1
				if c[a] > c[b] then
					st.above[a + 1][b + 1] += 1
				elseif c[a] == c[b] and #els == 2 then
					-- a duel draw counts half, like test/duel-table.mjs
					st.above[a + 1][b + 1] += 0.5
				end
			end
		end
	end
	if #els == 2 then
		local a, b = els[1], els[2]
		if c[a] > c[b] then
			st.wins[a + 1] += 1
		elseif c[b] > c[a] then
			st.wins[b + 1] += 1
		else
			st.wins[a + 1] += 0.5
			st.wins[b + 1] += 0.5
		end
	else
		st.wins[Rules.leader(S) + 1] += 1
	end
	return S
end

-- R four-player bot matches with random elements (no repeats, no clashing colours).
function Sim.ffa(R: number, layout: string, pace: { [number]: number }, seed: number): Stats
	local st = Sim.newStats()
	local pickRand = Rules.Rng.new(seed)
	for r = 1, R do
		local used = {}
		for _ = 1, 4 do
			table.insert(used, Rules.Duel.pickFree(used, pickRand))
		end
		Sim.play(st, used, { layout = layout, pace = pace, seed = seed * 7919 + r })
	end
	return st
end

-- Every pair of elements meets `reps` times in a duel round.
function Sim.pairs(reps: number, layout: string, pace: { [number]: number }, seed: number): Stats
	local st = Sim.newStats()
	local n = 0
	for a = 0, NEL - 1 do
		for b = a + 1, NEL - 1 do
			for _ = 1, reps do
				n += 1
				Sim.play(
					st,
					{ a, b },
					{ layout = layout, pace = pace, round = Config.DUEL_ROUND, seed = seed * 7919 + n }
				)
			end
		end
	end
	return st
end

-- R full bot duels: draft 1-2-2-1, bot ball choice, rounds until one side is out. Returns stats and round count.
function Sim.duels(R: number, pace: { [number]: number }, seed: number): (Stats, number)
	local Duel = Rules.Duel
	local st = Sim.newStats()
	local rounds = 0
	local rand = Rules.Rng.new(seed)
	for r = 1, R do
		local ok, err = pcall(function()
			local d = Duel.newDraft(rand() < 0.5)
			while not Duel.draftDone(d) do
				local side = Duel.draftTurn(d)
				assert(Duel.draftPick(d, side, Duel.botDraft(d, side, rand)), "bad draft pick")
			end
			local duel = Duel.new(d.teams, { nil, nil })
			while not duel.done do
				for _, side in Duel.need(duel) do
					assert(Duel.choose(duel, side, Duel.botChoose(duel, side, rand)), "bad choice")
				end
				local els = { duel.cur[1], duel.cur[2] }
				local S = Sim.play(st, els, {
					layout = "duel",
					pace = pace,
					round = Config.DUEL_ROUND,
					seed = seed * 7919 + r * 16 + duel.round,
				})
				assert(S, "round failed")
				duel.round += 1
				duel.game = S
				Duel.endRound(duel)
				rounds += 1
				assert(duel.round < 10, "duel too long")
			end
		end)
		if not ok then
			st.errors += 1
			st.firstError = st.firstError or tostring(err)
		end
	end
	return st, rounds
end

function Sim.rates(st: Stats): { number }
	local out = {}
	for e = 1, NEL do
		out[e] = if st.games[e] > 0 then 100 * st.wins[e] / st.games[e] else 0
	end
	return out
end

function Sim.rxKinds(st: Stats): (number, { string })
	local n, missing = 0, {}
	for _, k in Config.REACTIONS do
		if (st.rx[k] or 0) > 0 then
			n += 1
		else
			table.insert(missing, k)
		end
	end
	return n, missing
end

function Sim.ratesLine(rates: { number }): string
	local parts = {}
	for e = 0, NEL - 1 do
		table.insert(parts, string.format("%s %.1f", Config.TITLE[e], rates[e + 1]))
	end
	return table.concat(parts, "  ")
end

-- "Who beats whom": top 3 rivals finished above at >= hi %, and below at <= lo %.
function Sim.table(st: Stats, hi: number, lo: number, minMet: number): ({ { number } }, { { number } })
	local strong, weak = {}, {}
	for a = 1, NEL do
		local rows = {}
		for b = 1, NEL do
			if b ~= a and st.met[a][b] > minMet then
				table.insert(rows, { b - 1, 100 * st.above[a][b] / st.met[a][b] })
			end
		end
		local s, w = {}, {}
		for _, r in rows do
			if r[2] >= hi then
				table.insert(s, r)
			elseif r[2] <= lo then
				table.insert(w, r)
			end
		end
		table.sort(s, function(x, y)
			return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1])
		end)
		table.sort(w, function(x, y)
			return x[2] < y[2] or (x[2] == y[2] and x[1] < y[1])
		end)
		local so, wo = {}, {}
		for i = 1, math.min(3, #s) do
			table.insert(so, s[i][1])
		end
		for i = 1, math.min(3, #w) do
			table.insert(wo, w[i][1])
		end
		strong[a] = so
		weak[a] = wo
	end
	return strong, weak
end

function Sim.luaTable(name: string, t: { { number } }): string
	local parts = {}
	for _, row in t do
		local items = {}
		for _, v in row do
			table.insert(items, tostring(v))
		end
		table.insert(parts, "{" .. table.concat(items, ",") .. "}")
	end
	return "Config." .. name .. " = { [0] = " .. table.concat(parts, ",") .. " }"
end

function Sim.summary(st: Stats): string
	local R = st.matches
	return string.format(
		"matches %d  errors %d  reactions/match %.2f  powers/match %.2f  KOs/match %.2f  first power %.2f s  step %.3f ms (max %.2f ms)",
		R,
		st.errors,
		st.reactions / R,
		st.powers / R,
		st.kos / R,
		st.firstPower / math.max(1, st.firstPowerN),
		1000 * st.stepTime / math.max(1, st.steps),
		1000 * st.maxStep
	)
end

return Sim
