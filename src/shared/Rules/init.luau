--!strict
-- Pure rules of Ball Territory: no Roblox API, runs in Roblox and in lune. Port of the web game.js.
-- Each match is its own State; the server may run many at once. API: docs/rules.md.
local Bots = require("@self/Bots")
local Config = require("@self/Config")
local Core = require("@self/Core")
local Duel = require("@self/Duel")
local Grid = require("@self/Grid")
local Match = require("@self/Match")
local Rng = require("@self/Rng")
local Snapshot = require("@self/Snapshot")
local Types = require("@self/Types")

export type State = Types.State
export type Ball = Types.Ball
export type Event = Types.Event
export type Seat = Match.Seat
export type Options = Match.Options
export type Snapshot = Snapshot.Snapshot
export type Draft = Duel.Draft
export type DuelState = Duel.DuelState

local P = Config.P
local r2 = Grid.r2

local Rules = {}

Rules.VERSION = "1.0.0"
Rules.Config = Config
Rules.Duel = Duel
Rules.Rng = Rng

function Rules.getVersion(): string
	return Rules.VERSION
end

Rules.newMatch = Match.new
Rules.step = Match.step
Rules.recount = Match.recount

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Aim before the start (the drag before launch). Ignored after launch.
function Rules.aim(S: State, e: number, dx: number, dy: number): boolean
	local b = S.by[e]
	if not b or S.launched or not finite(dx) or not finite(dy) then
		return false
	end
	Core.steer(b, dx, dy)
	return true
end

-- Direction a ball really gets from an aim (dx, dy): what Core.steer and Core.turn make of it, nil if too short.
-- The client draws its own aim with it, so the line matches the flight.
function Rules.aimDir(dx: number, dy: number): (number?, number?)
	if not finite(dx) or not finite(dy) then
		return nil, nil
	end
	local probe = { dx = 0, dy = 0 }
	Core.steer(probe :: any, dx, dy)
	if probe.dx == 0 and probe.dy == 0 then
		return nil, nil
	end
	return probe.dx, probe.dy
end

-- Start of play: normalises every direction.
function Rules.launch(S: State)
	S.launched = true
	for _, b in S.balls do
		Core.turn(b, 0)
	end
	Core.ev(S, "launch")
end

-- New direction during play: only inside the CHOOSE DIRECTION window, or in the final at most every 0.2 s.
function Rules.redirect(S: State, e: number, dx: number, dy: number): boolean
	local b = S.by[e]
	if not b or not b.alive or not finite(dx) or not finite(dy) then
		return false
	end
	if S.final then
		if S.t - (b.dirAt or -9) < P.finalDirCd then
			return false
		end
		b.dirAt = S.t
	elseif S.t > S.promptUntil then
		return false
	end
	Core.steer(b, dx, dy)
	local tx, ty = Core.ahead(S, b, 5)
	Core.ev(S, "redirect", { e = b.e, x = r2(b.x), y = r2(b.y), tx = r2(tx), ty = r2(ty) })
	return true
end

-- Power button. Returns true if the power fired.
function Rules.press(S: State, e: number): boolean
	local b = S.by[e]
	if not b or not b.alive or b.charge < 1 then
		return false
	end
	Bots.press(S, b)
	return true
end

-- Events since the last drain (or snapshot).
function Rules.drain(S: State): { Event }
	local ev = S.events
	S.events = {}
	return ev
end

-- Snapshot for clients; drains events into snap.ev.
Rules.snapshot = Snapshot.take

-- How fast the server should run the match clock: 1/3 after the first reaction of a kind,
-- half while a human sees the CHOOSE DIRECTION prompt. The server also lowers S.slow by DT each step.
function Rules.timeScale(S: State): number
	local s = if S.slow > 0 then 1 / 3 else 1
	if S.t < S.promptUntil then
		for _, b in S.balls do
			if b.ctl and b.prompts then
				return s * 0.5
			end
		end
	end
	return s
end

-- Winner element of a finished match (most land, first seat wins ties).
function Rules.leader(S: State): number
	local top = S.players[1]
	for _, e in S.players do
		if S.counts[e] > S.counts[top] then
			top = e
		end
	end
	return top
end

return Rules
