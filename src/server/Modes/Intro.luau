--!strict
-- First entry: one duel round against a weak bot, no draft, with the 4 hints (aim, power, reaction, FINAL).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Analytics = require("../Analytics")
local Config = require("../Config")
local Roster = require("../Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("../Runner")
local Session = require("../Session")

local C = Rules.Config

local Intro = {}

-- The bot gets a ball the starter beats in duels (DSTRONG), so the first round is friendly.
local function botBall(e: number): number
	local strong: { number } = (C.DSTRONG :: any)[e] or {}
	for _, x in strong do
		if x ~= e then
			return x
		end
	end
	return Rules.Duel.pickFree({ e })
end

function Intro.start(s: Session.Session, now: number)
	local m = s.members[1]
	local rec = m.rec :: Roster.Rec
	local e = rec.introE or 0
	local bot = botBall(e)
	local S = Rules.newMatch(
		{ { e = e, ctl = tostring(m.userId) }, { e = bot } },
		{ layout = "duel", round = C.DUEL_ROUND, pace = C.DUEL_PACE }
	)
	local seats: { Runner.Seat } = {
		{ side = 0, rec = rec, e = e, name = m.name, userId = m.userId },
		{ side = 1, rec = nil, e = bot, name = "BOT", userId = 0, weak = true },
	}
	s.runner = Runner.new(s, S, seats, Config.INTRO_AIM, true)
	s.st = "round"
	Roster.send(rec, { ph = "match", mode = "intro", arena = s.arena.name }, true)
	Analytics.step(rec.player, Analytics.Step.FirstRoundStart)
	print(
		string.format(
			"[BT] M1-4 first round for %s: %.1f s after hello, %.1f s after join",
			rec.name,
			now - (rec.readyAt or rec.joinedAt),
			now - rec.joinedAt
		)
	)
end

function Intro.tick(s: Session.Session, dt: number, now: number)
	if s.st == "round" then
		local runner = s.runner :: Runner.Runner
		if Runner.tick(runner, dt, now) then
			local winner = Rules.leader(runner.S)
			for _, m in Session.humans(s) do
				local rec = m.rec :: Roster.Rec
				rec.first = false
				Analytics.step(rec.player, Analytics.Step.FirstRoundEnd)
			end
			Session.finish(s, winner, Runner.places(runner), function(m)
				return m.side == 0 and winner == runner.seats[1].e
			end)
		end
	elseif s.st == "result" and now >= s.endsAt then
		Session.close(s)
	end
end

function Intro.action(_s: Session.Session, _rec: Roster.Rec, _verb: string, _arg: number?, _now: number) end

function Intro.leave(s: Session.Session, rec: Roster.Rec, _now: number)
	Session.vacate(s, rec)
end

return Intro
