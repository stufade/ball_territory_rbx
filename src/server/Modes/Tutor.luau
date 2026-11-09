--!strict
-- Tutorial cartoon of the first entry (T2.1) on the real field and rules. Four scenes, each a fresh rules State set up
-- by Logic/Stage, then run by the unchanged rules:
--   A elements react: fire flies through a gas cloud (BOOM) into grass (WILDFIRE); tap to go on;
--   B power grabs land: time stands still until the player taps POWER (IGNITE);
--   C choose a direction: the CHOOSE DIRECTION window stands still until a tap at the stunned enemy, KO, land stolen;
--     a miss repeats the scene;
--   D the final, played alone: 15 s of FINAL vs a rookie bot (Logic/TutorBot), the player starts with more land.
-- Overlay cues go as Match "tut" (docs/net.md); the end is the usual result screen and Tutorial.complete (T2.2 hook).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("../Analytics")
local Config = require("../Config")
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Roster = require("../Roster")
local Rules = require(ReplicatedStorage.Shared.Rules)
local Runner = require("../Runner")
local Session = require("../Session")
local Stage = require("../Logic/Stage")
local TutorBot = require("../Logic/TutorBot")
local Tutorial = require("../Tutorial")

local C = Rules.Config
local T = Config.TUT
local IN = Net.Input
local FIRE, BOT = C.FIRE, C.ICE
-- scenes A-C never reach their end or the final
local LONG = 600

local Tutor = {}

Tutor.FIRE = FIRE
Tutor.BOT = BOT

export type Data = {
	scene: string,
	step: string,
	at: number,
	t0: number,
	-- cue counter, the cue number a "tut" tap must answer (0 = none)
	n: number,
	wait: number,
	next: string,
	misses: number,
	wildAt: number?,
	first: boolean,
	evs: { Net.RulesEvent },
	-- tutorial time (real time times the debug speed); scene timers run on it
	clock: number,
	last: { [string]: any }?,
}

local SETUP: { [string]: (S: Rules.State) -> () } = {}

function SETUP.A(S)
	Stage.clear(S)
	Stage.ball(S, FIRE, 6, 11.5, 1, -0.35)
	Stage.land(S, FIRE, 6, 11.5, 1.6)
	-- the fire's path crosses the cloud, then the grass (the rules turn a flat course to at least 0.3 of a side)
	Stage.patch(S, "toxic", 8, 9, 10, 11)
	Stage.patch(S, "bush", 12, 6, 16, 10)
	Stage.ball(S, BOT, 18, 5, -1, 1, { alive = false })
end

function SETUP.B(S)
	Stage.clear(S)
	Stage.ball(S, FIRE, 12, 10, 0.8, 0.6, { charge = 1 })
	Stage.land(S, FIRE, 12, 10, 1.6)
	Stage.ball(S, BOT, 18, 5, -1, 1, { alive = false })
end

function SETUP.C(S)
	Stage.clear(S)
	Stage.ball(S, FIRE, 7.5, 12.5, -0.6, 0.8)
	Stage.land(S, FIRE, 7.5, 12.5, 2.2)
	-- stunned (slow) and nearly out of health: one hit is a KO
	Stage.ball(S, BOT, 14, 8.5, 0.6, -0.8, { hp = C.P.damage, stun = 6 })
	Stage.land(S, BOT, 14, 8.5, 2.8)
end

function SETUP.D(S)
	-- the real map of a round; the player's head start is a bigger patch of land, the whole round is the FINAL
	local b = S.by[FIRE]
	Stage.land(S, FIRE, b.x, b.y, T.land)
	S.finalAt = 0
end

-- Exposed for tests/tutor: the staged rules State of a scene.
function Tutor.stage(name: string, seed: number?): Rules.State
	local S = Rules.newMatch(
		{ { e = FIRE, ctl = "1" }, { e = BOT, ctl = "stage" } },
		{ layout = "duel", round = if name == "D" then T.final else LONG, pace = C.DUEL_PACE, seed = seed }
	)
	SETUP[name](S)
	Rules.recount(S)
	return S
end

local function cue(s: Session.Session, k: string, extra: { [string]: any }?, wait: boolean?)
	local d: Data = s.data
	d.n += 1
	local data: { [string]: any } = { s = d.scene, k = k, n = d.n, wait = wait == true }
	if extra then
		for key, v in extra do
			data[key] = v
		end
	end
	d.wait = if wait then d.n else 0
	d.last = data
	Session.fire(s, Net.MatchKind.tut, table.clone(data))
end

local function run(s: Session.Session): Runner.Runner
	return s.runner :: Runner.Runner
end

local function player(s: Session.Session): Player?
	local rec = s.members[1].rec
	return if rec then rec.player else nil
end

local function hint(s: Session.Session, k: string)
	local p = player(s)
	if p then
		Analytics.hint(p, k)
	end
end

local function seats(s: Session.Session): { Runner.Seat }
	local m = s.members[1]
	return {
		{ side = 0, rec = m.rec, e = FIRE, name = m.name, userId = m.userId },
		{ side = 1, rec = nil, e = BOT, name = "BOT", userId = 0, staged = true },
	}
end

local filter: (s: Session.Session, seat: Runner.Seat, kind: number, dx: number?, dy: number?) -> (boolean, number?, number?)

local function scene(s: Session.Session, name: string, now: number)
	local d: Data = s.data
	d.scene, d.at, d.wait, d.evs = name, now, 0, {}
	local S = Tutor.stage(name)
	local r = Runner.new(s, S, seats(s), 0, false)
	s.runner = r
	r.watch = function(ev)
		table.insert(d.evs, ev)
	end
	r.filter = function(seat, kind, dx, dy)
		return filter(s, seat, kind, dx, dy)
	end
	if name == "A" then
		d.step = "look"
		r.scale = 0
		cue(s, "react")
	elseif name == "B" then
		d.step = "wait"
		r.scale = 0
		cue(s, "power", nil, true)
	elseif name == "C" then
		-- one rules step opens CHOOSE DIRECTION the rules' own way (event "prompt"), then time stands still
		S.nextPrompt = S.t
		Rules.step(S)
		d.step = "wait"
		r.scale = 0
		local b, me = S.by[BOT], S.by[FIRE]
		cue(s, "dir", { e = BOT, x = b.x, y = b.y, fx = me.x, fy = me.y, retry = d.misses > 0 }, true)
	else
		local bot = TutorBot.new(BOT, FIRE, S.rand, T.botAim, T.keep)
		r.extra = function(st)
			TutorBot.step(bot, Rules, st)
		end
		d.step = "play"
		cue(s, "final")
	end
end

-- Next scene behind a fade to black.
local function go(s: Session.Session, next: string, now: number)
	local d: Data = s.data
	d.step = "out"
	d.next = next
	d.at = now
	cue(s, "out")
end

local function grab(s: Session.Session, now: number)
	local d: Data = s.data
	d.step = "run"
	d.at = now
	run(s).scale = 1
	cue(s, "grab")
	hint(s, Net.Hint.power)
end

local function fly(s: Session.Session, now: number)
	local d: Data = s.data
	d.step = "fly"
	d.at = now
	run(s).scale = 1
	cue(s, "go")
	hint(s, Net.Hint.aim)
end

function filter(
	s: Session.Session,
	seat: Runner.Seat,
	kind: number,
	dx: number?,
	dy: number?
): (boolean, number?, number?)
	local d: Data = s.data
	if d.scene == "D" then
		return true
	end
	if seat.rec == nil or d.step == "out" then
		return false
	end
	local now = (s.data :: Data).clock
	if d.scene == "B" then
		if kind == IN.power and d.step == "wait" then
			grab(s, now)
			return true
		end
	elseif d.scene == "C" and kind == IN.dir and d.step == "wait" and dx and dy then
		local tx, ty, off = Stage.offAngle(run(s).S, FIRE, BOT, dx, dy)
		if off <= T.cone or d.misses >= T.misses then
			fly(s, now)
			return true, tx, ty
		end
		d.misses += 1
		d.step = "miss"
		d.at = now
		run(s).scale = 1
		cue(s, "miss")
		return true
	end
	return false
end

local function onEvent(s: Session.Session, ev: Net.RulesEvent, now: number)
	local d: Data = s.data
	if d.scene == "A" and ev.kind == "rx" then
		if ev.d.k == "BOOM" then
			cue(s, "boom", { rx = "BOOM", e = FIRE, l = "toxic" })
			hint(s, Net.Hint.react)
		elseif ev.d.k == "WILDFIRE" and not d.wildAt then
			d.wildAt = now
			cue(s, "wild", { rx = "WILDFIRE", e = FIRE, l = "bush" })
		end
	elseif d.scene == "C" and ev.kind == "ko" and ev.d.e == BOT and (d.step == "fly" or d.step == "miss") then
		d.step = "ko"
		d.at = now
		cue(s, "ko")
	end
end

local function step(s: Session.Session, now: number)
	local d: Data = s.data
	local r = s.runner :: Runner.Runner
	local el = now - d.at
	local st = d.step
	if st == "out" then
		if el >= T.fade then
			scene(s, d.next, now)
		end
	elseif d.scene == "A" then
		if st == "look" and el >= T.look then
			d.step, d.at, r.scale = "run", now, 1
		elseif st == "run" and ((d.wildAt and now - d.wildAt >= T.afterWild) or el >= T.watchMax) then
			d.step, d.at, r.scale = "tap", now, 0
			cue(s, "tap", nil, true)
		elseif st == "tap" and el >= T.afk then
			go(s, "B", now)
		end
	elseif d.scene == "B" then
		if st == "wait" and el >= T.afk then
			Rules.press(r.S, FIRE)
			grab(s, now)
		elseif st == "run" and el >= T.grab then
			go(s, "C", now)
		end
	elseif d.scene == "C" then
		if st == "wait" and el >= T.afk then
			local tx, ty = Stage.offAngle(r.S, FIRE, BOT, 1, 0)
			Rules.redirect(r.S, FIRE, tx, ty)
			fly(s, now)
		elseif st == "fly" and el >= T.hitWait then
			d.misses += 1
			go(s, "C", now)
		elseif st == "miss" and el >= T.missShow then
			go(s, "C", now)
		elseif st == "ko" and el >= T.koShow then
			go(s, "D", now)
		end
	end
end

local function finish(s: Session.Session, now: number)
	local d: Data = s.data
	local r = s.runner :: Runner.Runner
	local winner = Rules.leader(r.S)
	Session.finish(s, winner, Runner.places(r), function(m)
		return m.side == 0 and winner == FIRE
	end)
	local rec: Roster.Rec? = s.members[1].rec
	if rec then
		rec.first = false
		rec.glow = "play"
		if d.first then
			Analytics.step(rec.player, Analytics.Step.FirstRoundEnd)
		end
		print(
			string.format(
				"[BT] T2.1 tutorial of %s: %.1f s, %s",
				rec.name,
				now - d.t0,
				if winner == FIRE then "won" else "LOST"
			)
		)
		Tutorial.complete(rec.player, { first = d.first, seconds = now - d.t0 })
	end
end

function Tutor.start(s: Session.Session, now: number)
	local m = s.members[1]
	local rec = m.rec :: Roster.Rec
	local d: Data = {
		scene = "",
		step = "",
		at = now,
		t0 = now,
		n = 0,
		wait = 0,
		next = "",
		misses = 0,
		wildAt = nil,
		first = not Tutorial.isDone(rec.player),
		evs = {},
		clock = now,
		last = nil,
	}
	s.data = d
	s.st = "round"
	Roster.send(rec, { ph = "match", mode = "tutor", arena = s.arena.name }, true)
	if d.first then
		Analytics.step(rec.player, Analytics.Step.FirstRoundStart)
	end
	scene(s, "A", now)
end

-- Debug: ServerScriptService attribute DebugTutorSpeed (0-4, 1 by default) slows or stops the tutorial (screenshots).
local function speed(): number
	local v = ServerScriptService:GetAttribute("DebugTutorSpeed")
	return if type(v) == "number" and v == v then math.clamp(v, 0, 4) else 1
end

function Tutor.tick(s: Session.Session, dt: number, realNow: number)
	if s.st == "round" then
		local d: Data = s.data
		dt *= speed()
		d.clock += dt
		local now = d.clock
		local over = Runner.tick(s.runner :: Runner.Runner, dt, now)
		local evs = d.evs
		d.evs = {}
		for _, ev in evs do
			onEvent(s, ev, now)
		end
		if d.scene == "D" then
			if d.step == "play" then
				d.step = "on"
				hint(s, Net.Hint.final)
			end
			if over then
				finish(s, now)
			end
		else
			step(s, now)
		end
	elseif s.st == "result" and realNow >= s.endsAt then
		Session.close(s)
	end
end

-- "tut" (cue number): the player tapped through the waiting cue.
function Tutor.action(s: Session.Session, _rec: Roster.Rec, verb: string, arg: number?, _now: number)
	local d: Data = s.data
	local now = d.clock
	if verb ~= Net.Action.tut or s.st ~= "round" or d.wait == 0 or arg ~= d.wait then
		return
	end
	if d.scene == "A" and d.step == "tap" then
		d.wait = 0
		go(s, "B", now)
	end
end

-- The client said hello again (UI reloaded): the overlay needs the current cue.
function Tutor.hello(s: Session.Session, rec: Roster.Rec)
	local d: Data = s.data
	if d.last and s.st == "round" then
		local data = table.clone(d.last)
		data.id = s.id
		Remotes.Match:FireClient(rec.player, Net.MatchKind.tut, data)
	end
end

function Tutor.leave(s: Session.Session, rec: Roster.Rec, _now: number)
	Session.vacate(s, rec)
end

return Tutor
