--!strict
-- 1v1 duel: draft 1-2-2-1 of 3 balls each, then 30 s rounds on the small arena.
-- Before a round the side without a ball picks one: first both blind, then the loser, seeing the winner's ball.
-- The round winner stays, a draw knocks out both. A side out of balls loses the duel.
local Config = require("./Config")
local Grid = require("./Grid")
local Match = require("./Match")
local Rng = require("./Rng")
local Types = require("./Types")

type State = Types.State

local NEL, DSTRONG, DWEAK = Config.NEL, Config.DSTRONG, Config.DWEAK

local Duel = {}

local function has(list: { number }, e: number): boolean
	return table.find(list, e) ~= nil
end

export type Draft = {
	order: { number },
	i: number,
	teams: { { number } },
}

-- first = true: side 1 picks first. Sides are 0 and 1.
function Duel.newDraft(first: boolean): Draft
	return {
		order = if first then { 1, 0, 0, 1, 1, 0 } else { 0, 1, 1, 0, 0, 1 },
		i = 0,
		teams = { {}, {} },
	}
end

function Duel.draftTurn(d: Draft): number
	return if d.i < #d.order then d.order[d.i + 1] else -1
end

function Duel.draftDone(d: Draft): boolean
	return d.i >= #d.order
end

function Duel.draftFree(d: Draft, e: number): boolean
	return e >= 0 and e < NEL and e % 1 == 0 and not has(d.teams[1], e) and not has(d.teams[2], e)
end

function Duel.draftPick(d: Draft, side: number, e: number): boolean
	if side ~= Duel.draftTurn(d) or not Duel.draftFree(d, e) then
		return false
	end
	table.insert(d.teams[side + 1], e)
	d.i += 1
	return true
end

export type RoundLog = { a: number, b: number, win: number, pa: number, pb: number }
export type DuelState = {
	teams: { { number } },
	ctls: { string? },
	lost: { { number } },
	cur: { number },
	round: number,
	log: { RoundLog },
	done: boolean,
	winner: number,
	game: State?,
}

function Duel.new(teams: { { number } }, ctls: { string? }): DuelState
	local t = {}
	for i = 1, 2 do
		t[i] = table.move(teams[i], 1, math.min(#teams[i], Config.DUEL_SIZE), 1, {})
	end
	return {
		teams = t,
		ctls = { ctls[1], ctls[2] },
		lost = { {}, {} },
		cur = { -1, -1 },
		round = 0,
		log = {},
		done = false,
		winner = -1,
		game = nil,
	}
end

function Duel.left(d: DuelState, side: number): { number }
	local out = {}
	for _, e in d.teams[side + 1] do
		if not has(d.lost[side + 1], e) then
			table.insert(out, e)
		end
	end
	return out
end

-- Sides that still have to choose a ball for the next round.
function Duel.need(d: DuelState): { number }
	local out = {}
	if d.done then
		return out
	end
	for side = 0, 1 do
		if d.cur[side + 1] < 0 then
			table.insert(out, side)
		end
	end
	return out
end

function Duel.choose(d: DuelState, side: number, e: number): boolean
	if d.done or d.cur[side + 1] >= 0 or not has(Duel.left(d, side), e) then
		return false
	end
	d.cur[side + 1] = e
	return true
end

-- opts may set layout ("duel" by default), seed or rand.
function Duel.newRound(d: DuelState, opts: Match.Options?): State
	d.round += 1
	local o: Match.Options = {
		layout = "duel",
		round = Config.DUEL_ROUND,
		pace = Config.DUEL_PACE,
	}
	if opts then
		for k, v in opts :: any do
			(o :: any)[k] = v
		end
	end
	local S = Match.new({ { e = d.cur[1], ctl = d.ctls[1] }, { e = d.cur[2], ctl = d.ctls[2] } }, o)
	d.game = S
	return S
end

-- Returns the round winner side, or -1 on a draw.
function Duel.endRound(d: DuelState): number
	local S = d.game :: State
	local a, b = d.cur[1], d.cur[2]
	local ca, cb = S.counts[a], S.counts[b]
	local win = if ca > cb then 0 elseif cb > ca then 1 else -1
	table.insert(d.log, { a = a, b = b, win = win, pa = Grid.r2(ca / S.area * 100), pb = Grid.r2(cb / S.area * 100) })
	for side = 0, 1 do
		if win ~= side then
			table.insert(d.lost[side + 1], d.cur[side + 1])
			d.cur[side + 1] = -1
		end
	end
	local outA, outB = #Duel.left(d, 0) == 0, #Duel.left(d, 1) == 0
	if outA or outB then
		d.done = true
		d.winner = if outA and outB then -1 elseif outA then 1 else 0
	end
	return win
end

local function duelScore(e: number, rivals: { number }): number
	local s = 0
	for _, o in rivals do
		s += (if has(DSTRONG[e], o) then 2 else 0) - (if has(DWEAK[e], o) then 2 else 0)
	end
	return s
end
Duel.duelScore = duelScore

local defaultRand = Rng.new()

-- Bot draft pick: counters to what the rival already took, with some noise.
function Duel.botDraft(d: Draft, side: number, rand: Rng.Rand?): number
	local r = rand or defaultRand
	local opp = d.teams[2 - side]
	local best, be = -math.huge, -1
	for e = 0, NEL - 1 do
		if Duel.draftFree(d, e) then
			local s = duelScore(e, opp) + r() * 2.5
			if s > best then
				best, be = s, e
			end
		end
	end
	return be
end

-- Bot ball for the next round: counter to the winner's ball.
function Duel.botChoose(d: DuelState, side: number, rand: Rng.Rand?): number
	local r = rand or defaultRand
	local o = d.cur[2 - side]
	local rivals = if o >= 0 then { o } else {}
	local best, be = -math.huge, -1
	for _, e in Duel.left(d, side) do
		local s = duelScore(e, rivals) + r() * 1.5
		if s > best then
			best, be = s, e
		end
	end
	return be
end

-- Random bot element: no repeats and no pair of similar colours.
function Duel.pickFree(used: { number }, rand: Rng.Rand?): number
	local r = rand or defaultRand
	local opts = {}
	for e = 0, NEL - 1 do
		if has(used, e) then
			continue
		end
		local bad = false
		for _, pair in Config.CLASH do
			local a, c = pair[1], pair[2]
			if (a == e and has(used, c)) or (c == e and has(used, a)) then
				bad = true
				break
			end
		end
		if not bad then
			table.insert(opts, e)
		end
	end
	if #opts == 0 then
		for e = 0, NEL - 1 do
			if not has(used, e) then
				table.insert(opts, e)
			end
		end
	end
	return opts[math.floor(r() * #opts) + 1]
end

return Duel
