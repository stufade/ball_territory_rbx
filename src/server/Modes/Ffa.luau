--!strict
-- 4-player match: each person picks a ball (10 s, no two alike), bots take the empty seats, one 60 s round.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require("../Config")
local Guard = require("../Logic/Guard")
local Net = require(ReplicatedStorage.Shared.Net)
local Roster = require("../Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("../Runner")
local Session = require("../Session")

local NEL = Rules.Config.NEL
local rand = Rules.Rng.new()

local Ffa = {}

local function taken(s: Session.Session): { number }
	local out = {}
	for _, e in s.data.picks do
		table.insert(out, e)
	end
	return out
end

local function free(s: Session.Session): { number }
	local used = taken(s)
	local out = {}
	for e = 0, NEL - 1 do
		if not table.find(used, e) then
			table.insert(out, e)
		end
	end
	return out
end

local function sendPick(s: Session.Session)
	local options, used = free(s), taken(s)
	Session.each(s, function(_)
		return { ph = "pick", mode = "ffa", options = options, taken = used, endsAt = s.endsAt }
	end)
end

local function startRound(s: Session.Session)
	local picks = s.data.picks
	for _, m in s.members do
		if picks[m.side] == nil then
			if m.rec then
				local f = free(s)
				picks[m.side] = f[math.floor(rand() * #f) + 1]
			else
				picks[m.side] = Rules.Duel.pickFree(taken(s), rand)
			end
		end
	end
	local seats, list = {}, {}
	for _, m in s.members do
		local e = picks[m.side]
		table.insert(seats, { side = m.side, rec = m.rec, e = e, name = m.name, userId = m.userId })
		table.insert(list, { e = e, ctl = if m.rec then tostring(m.userId) else nil })
	end
	local S = Rules.newMatch(list, { layout = "ffa", round = Rules.Config.ROUND })
	s.runner = Runner.new(s, S, seats, Config.AIM_TIME, false)
	s.st = "round"
	Session.each(s, function(_)
		return { ph = "match", mode = "ffa", arena = s.arena.name }
	end)
end

local function allPicked(s: Session.Session): boolean
	for _, m in Session.humans(s) do
		if s.data.picks[m.side] == nil then
			return false
		end
	end
	return true
end

function Ffa.start(s: Session.Session, now: number)
	s.data.picks = {}
	if #Session.humans(s) == 0 then
		startRound(s)
		return
	end
	s.st = "pick"
	s.endsAt = now + Config.FFA_PICK
	sendPick(s)
end

function Ffa.tick(s: Session.Session, dt: number, now: number)
	if s.st == "pick" then
		if now >= s.endsAt or allPicked(s) then
			startRound(s)
		end
	elseif s.st == "round" then
		local runner = s.runner :: Runner.Runner
		if Runner.tick(runner, dt, now) then
			local winner = Rules.leader(runner.S)
			local picks = s.data.picks
			Session.finish(s, winner, Runner.places(runner), function(m)
				return picks[m.side] == winner
			end)
		end
	elseif s.st == "result" and now >= s.endsAt then
		Session.close(s)
	end
end

function Ffa.action(s: Session.Session, rec: Roster.Rec, verb: string, arg: number?, _now: number)
	local m = Session.member(s, rec)
	if not m or s.st ~= "pick" or verb ~= Net.Action.pick or s.data.picks[m.side] ~= nil then
		return
	end
	local e = Guard.element(arg, NEL)
	if e == nil or table.find(taken(s), e) then
		return
	end
	s.data.picks[m.side] = e
	if allPicked(s) then
		startRound(s)
	else
		sendPick(s)
	end
end

function Ffa.leave(s: Session.Session, rec: Roster.Rec, _now: number)
	local m = Session.member(s, rec)
	if m and s.st == "pick" then
		-- the bot picks its own ball at the start
		s.data.picks[m.side] = nil
	end
	Session.vacate(s, rec)
end

return Ffa
