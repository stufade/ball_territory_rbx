--!strict
-- Duel 1v1: draft 1-2-2-1 with offers (15 s a pick), ball choice before each round (10 s), 30 s rounds,
-- the round winner stays, a side out of balls loses.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Collection = require("../Collection")
local Config = require("../Config")
local Guard = require("../Logic/Guard")
local Net = require(ReplicatedStorage.Shared.Net)
local Offers = require("../Logic/Offers")
local Roster = require("../Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("../Runner")
local Session = require("../Session")

local D = Rules.Duel
local NEL = Rules.Config.NEL
local rand = Rules.Rng.new()

local Duel = {}

local function isBot(s: Session.Session, side: number): boolean
	return s.members[side + 1].rec == nil
end

local function copy(t: { { number } }): { { number } }
	return { table.clone(t[1]), table.clone(t[2]) }
end

local function sendDraft(s: Session.Session)
	local o = s.data.offers
	local turn = Offers.turn(o)
	Session.each(s, function(m)
		return {
			ph = "draft",
			mode = "duel",
			me = m.side,
			turn = turn,
			teams = copy(Offers.teams(o)),
			offer = Offers.offerFor(o, m.side),
			any = Offers.canAny(o, m.side),
			anyLeft = o.anyLeft[m.side + 1],
			own = s.data.own[m.side + 1],
			names = Session.names(s),
			endsAt = s.endsAt,
		}
	end)
end

local function sendChoose(s: Session.Session)
	local d = s.data.duel
	Session.each(s, function(m)
		-- the round winner stays with its ball: it only watches the loser choose
		local keep = d.cur[m.side + 1]
		return {
			ph = "choose",
			mode = "duel",
			me = m.side,
			keep = keep,
			left = if keep < 0 then D.left(d, m.side) else {},
			rival = if s.data.blind then -1 else d.cur[2 - m.side],
			blind = s.data.blind,
			teams = copy(d.teams),
			lost = copy(d.lost),
			names = Session.names(s),
			endsAt = s.endsAt,
		}
	end)
end

local function startRound(s: Session.Session)
	local d = s.data.duel
	local S = D.newRound(d)
	local seats = {}
	for side = 0, 1 do
		local m = s.members[side + 1]
		table.insert(seats, { side = side, rec = m.rec, e = d.cur[side + 1], name = m.name, userId = m.userId })
	end
	s.runner = Runner.new(s, S, seats, Config.AIM_TIME, false)
	s.st = "round"
	Session.each(s, function(_)
		return { ph = "match", mode = "duel", arena = s.arena.name }
	end)
end

local function enterChoose(s: Session.Session, now: number)
	local d = s.data.duel
	s.st = "choose"
	local need = D.need(d)
	s.data.blind = #need == 2
	for _, side in need do
		if isBot(s, side) then
			D.choose(d, side, D.botChoose(d, side, rand))
		end
	end
	if #D.need(d) == 0 then
		startRound(s)
		return
	end
	s.endsAt = now + Config.CHOOSE_TIME
	sendChoose(s)
end

local function afterPick(s: Session.Session, now: number)
	local o = s.data.offers
	if Offers.done(o) then
		local ctls: { string? } = {}
		for side = 0, 1 do
			local m = s.members[side + 1]
			ctls[side + 1] = if m.rec then tostring(m.userId) else nil
		end
		s.data.duel = D.new(Offers.teams(o), ctls)
		enterChoose(s, now)
	else
		s.data.turnAt = now
		s.endsAt = now + Config.DRAFT_TURN
		sendDraft(s)
	end
end

function Duel.start(s: Session.Session, now: number)
	-- each person drafts from the own collection (T2.2), bots from every ball
	local own, any = {}, {}
	for side = 1, 2 do
		local rec = s.members[side].rec
		local player = if rec then rec.player else nil
		own[side] = Collection.owned(player)
		any[side] = Collection.anyFree(player)
	end
	s.data.own = own
	s.data.offers = Offers.new(Rules, rand() < 0.5, Config.OFFER, any, rand, own)
	s.data.score = { 0, 0 }
	s.st = "draft"
	s.data.turnAt = now
	s.endsAt = now + Config.DRAFT_TURN
	sendDraft(s)
end

local function roundOver(s: Session.Session, now: number)
	local d = s.data.duel
	local win = D.endRound(d)
	if win >= 0 then
		s.data.score[win + 1] += 1
	end
	local log = d.log[#d.log]
	Session.fire(s, Net.MatchKind.round, {
		win = win,
		a = log.a,
		b = log.b,
		pa = log.pa,
		pb = log.pb,
		lost = copy(d.lost),
		score = table.clone(s.data.score),
	})
	s.st = "rend"
	s.endsAt = now + Config.ROUND_PAUSE
	Session.fire(s, Net.MatchKind.phase, { ph = "rend", endsAt = s.endsAt })
end

function Duel.tick(s: Session.Session, dt: number, now: number)
	local st = s.st
	if st == "draft" then
		local o = s.data.offers
		local side = Offers.turn(o)
		if isBot(s, side) and now - s.data.turnAt >= Config.BOT_THINK then
			Offers.bot(o)
			afterPick(s, now)
		elseif now >= s.endsAt then
			Offers.timeout(o)
			afterPick(s, now)
		end
	elseif st == "choose" then
		if now >= s.endsAt then
			local d = s.data.duel
			for _, side in D.need(d) do
				local left = D.left(d, side)
				D.choose(d, side, left[math.floor(rand() * #left) + 1])
			end
			startRound(s)
		end
	elseif st == "round" then
		if Runner.tick(s.runner :: Runner.Runner, dt, now) then
			roundOver(s, now)
		end
	elseif st == "rend" then
		if now >= s.endsAt then
			local d = s.data.duel
			if d.done then
				local runner = s.runner :: Runner.Runner
				Session.finish(s, d.winner, Runner.places(runner), function(m)
					return m.side == d.winner
				end)
			else
				enterChoose(s, now)
			end
		end
	elseif st == "result" and now >= s.endsAt then
		Session.close(s)
	end
end

function Duel.action(s: Session.Session, rec: Roster.Rec, verb: string, arg: number?, now: number)
	local m = Session.member(s, rec)
	if not m then
		return
	end
	if s.st == "draft" and (verb == Net.Action.draft or verb == Net.Action.any) then
		local e = Guard.element(arg, NEL)
		if e == nil then
			return
		end
		local o = s.data.offers
		local ok = if verb == Net.Action.draft then Offers.pick(o, m.side, e) else Offers.any(o, m.side, e)
		if ok then
			afterPick(s, now)
		end
	elseif s.st == "choose" and verb == Net.Action.choose then
		local e = Guard.element(arg, NEL)
		local d = s.data.duel
		if e ~= nil and D.choose(d, m.side, e) then
			if #D.need(d) == 0 then
				startRound(s)
			else
				sendChoose(s)
			end
		end
	end
end

-- A person left the server: the side becomes a bot and plays on.
function Duel.leave(s: Session.Session, rec: Roster.Rec, now: number)
	local m = Session.member(s, rec)
	if not m then
		return
	end
	local side = m.side
	Session.vacate(s, rec)
	local d = s.data.duel
	if d then
		d.ctls[side + 1] = nil
		if s.st == "choose" and d.cur[side + 1] < 0 then
			D.choose(d, side, D.botChoose(d, side, rand))
			if #D.need(d) == 0 then
				startRound(s)
			end
		end
	end
	if s.st == "draft" then
		s.data.turnAt = math.min(s.data.turnAt, now)
	end
end

return Duel
