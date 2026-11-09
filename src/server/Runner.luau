--!strict
-- One round on one arena: aim phase, the 30 Hz rules clock, 15 Hz snapshots, batched events, first-round hints, input.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("./Analytics")
local Config = require("./Config")
local Guard = require("./Logic/Guard")
local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules)
local WeakBot = require("./Logic/WeakBot")

local Snap = require(ReplicatedStorage.Shared.Net.Snap)
local DT = Rules.Config.DT
local SNAP_DT = 1 / Net.SNAP_HZ
local IN = Net.Input

local Runner = {}

export type Seat = {
	side: number,
	rec: any?,
	e: number,
	name: string,
	userId: number,
	weak: boolean?,
}

export type Runner = {
	session: any,
	mode: string,
	S: Rules.State,
	enc: Snap.Encoder,
	seats: { Seat },
	phase: "aim" | "play" | "done",
	endsAt: number,
	launched: { [number]: boolean },
	acc: number,
	snapAcc: number,
	weak: { WeakBot.WeakBot },
	hints: boolean,
	hinted: { [string]: boolean },
	steps: number,
	-- frames that hit MAX_STEPS: the server could not keep the 30 Hz clock
	capped: number,
	startedAt: number,
}

local function recipients(r: Runner): { Player }
	return r.session.recipients(r.session)
end

local function fire(r: Runner, kind: string, data: { [string]: any })
	data.id = r.session.id
	for _, p in recipients(r) do
		Remotes.Match:FireClient(p, kind, data)
	end
end

local function humans(r: Runner): { Seat }
	local out = {}
	for _, s in r.seats do
		if s.rec then
			table.insert(out, s)
		end
	end
	return out
end

local function startData(r: Runner, you: number?, key: buffer): { [string]: any }
	local seats = {}
	for _, s in r.seats do
		table.insert(seats, { e = s.e, name = s.name, userId = s.userId, side = s.side })
	end
	local arena = r.session.arena
	return {
		arena = arena.name,
		aid = arena.aid,
		mode = r.mode,
		round = r.S.round,
		ox = r.enc.ox,
		oy = r.enc.oy,
		w = r.enc.w,
		h = r.enc.h,
		you = you,
		seats = seats,
		key = key,
	}
end

local function sendStart(r: Runner, p: Player, key: buffer)
	local you
	for _, s in r.seats do
		if s.rec and s.rec.player == p then
			you = s.e
		end
	end
	local data = startData(r, you, key)
	data.id = r.session.id
	Remotes.Match:FireClient(p, Net.MatchKind.start, data)
end

-- seats: e, name, userId (0 = bot), side, rec (nil = bot), weak (first-round bot). opts.aim: seconds to aim.
function Runner.new(session: any, S: Rules.State, seats: { Seat }, aim: number, hints: boolean): Runner
	local now = workspace:GetServerTimeNow()
	local r: Runner = {
		session = session,
		mode = session.mode,
		S = S,
		enc = Snap.newEncoder(S, session.id),
		seats = seats,
		phase = "aim",
		endsAt = now + aim,
		launched = {},
		acc = 0,
		snapAcc = 0,
		weak = {},
		hints = hints,
		hinted = {},
		steps = 0,
		capped = 0,
		startedAt = now,
	}
	for _, s in seats do
		local b = S.by[s.e]
		b.name = s.name
		b.pid = if s.userId ~= 0 then tostring(s.userId) else ""
		if s.weak then
			b.ctl = "weak"
			b.prompts = false
			table.insert(r.weak, WeakBot.new(s.e, S.rand, Config.WEAK_PRESS, Config.WEAK_FINAL_AIM))
		elseif s.rec then
			b.ctl = tostring(s.userId)
		else
			b.ctl = nil
		end
	end
	Rules.drain(S)
	local key = Snap.keyframe(r.enc, S)
	for _, p in recipients(r) do
		sendStart(r, p, key)
	end
	fire(r, Net.MatchKind.phase, { ph = "aim", endsAt = r.endsAt })
	if hints then
		Runner.hint(r, Net.Hint.aim)
	end
	return r
end

-- A viewer or a re-joined client gets the match from now on.
function Runner.join(r: Runner, p: Player)
	local probe = Snap.newEncoder(r.S, r.session.id)
	probe.seq = r.enc.seq
	sendStart(r, p, Snap.keyframe(probe, r.S))
	Remotes.Match:FireClient(
		p,
		Net.MatchKind.phase,
		{ id = r.session.id, ph = if r.phase == "aim" then "aim" else "play", endsAt = r.endsAt }
	)
end

function Runner.hint(r: Runner, k: string)
	if not r.hints or r.hinted[k] then
		return
	end
	r.hinted[k] = true
	fire(r, Net.MatchKind.hint, { k = k })
	for _, s in humans(r) do
		Analytics.hint(s.rec.player, k)
	end
end

local function go(r: Runner, now: number)
	Rules.launch(r.S)
	r.phase = "play"
	r.endsAt = now + r.S.round
	fire(r, Net.MatchKind.phase, { ph = "play", endsAt = r.endsAt })
end

local function allLaunched(r: Runner): boolean
	for _, s in humans(r) do
		if not r.launched[s.userId] then
			return false
		end
	end
	return true
end

local function flush(r: Runner)
	local S = r.S
	local list = {}
	for _, ev in Rules.drain(S) do
		if ev.kind == "wall" then
			continue
		end
		table.insert(list, { kind = ev.kind, d = ev.d })
		if r.hints then
			if ev.kind == "ready" then
				local b = S.by[ev.d.e]
				if b and b.ctl and b.ctl ~= "weak" then
					Runner.hint(r, Net.Hint.power)
				end
			elseif ev.kind == "rx" then
				Runner.hint(r, Net.Hint.react)
			elseif ev.kind == "final" then
				Runner.hint(r, Net.Hint.final)
			end
		end
	end
	local packets = Snap.encode(r.enc, S)
	local to = recipients(r)
	for _, p in to do
		for _, b in packets do
			Remotes.Snap:FireClient(p, b)
		end
	end
	if #list > 0 then
		for _, p in to do
			Remotes.Match:FireClient(p, Net.MatchKind.ev, { id = r.session.id, list = list })
		end
	end
end

-- Returns true when the round is over (S.done).
function Runner.tick(r: Runner, dt: number, now: number): boolean
	if r.phase == "done" then
		return true
	end
	local S = r.S
	if r.phase == "aim" then
		if now >= r.endsAt or allLaunched(r) then
			go(r, now)
		end
	else
		r.acc += dt * Rules.timeScale(S)
		local n = 0
		while r.acc >= DT and n < Config.MAX_STEPS do
			r.acc -= DT
			n += 1
			if S.slow > 0 then
				S.slow -= DT
			end
			Rules.step(S)
			for _, w in r.weak do
				WeakBot.step(w, Rules, S)
			end
			r.steps += 1
			if S.done then
				break
			end
		end
		if n >= Config.MAX_STEPS then
			r.capped += 1
			r.acc = math.min(r.acc, DT)
		end
	end
	r.snapAcc += dt
	if r.snapAcc >= SNAP_DT or S.done then
		r.snapAcc = math.min(r.snapAcc - SNAP_DT, SNAP_DT)
		flush(r)
	end
	if S.done then
		r.phase = "done"
		return true
	end
	return false
end

local function logInput(msg: string)
	if ServerScriptService:GetAttribute("DebugInputLog") then
		print("[BT] input " .. msg)
	end
end

-- Validated input of a seated person. Bad input is dropped silently.
function Runner.input(r: Runner, rec: any, kind: number, dx: number?, dy: number?)
	local seat
	for _, s in r.seats do
		if s.rec == rec then
			seat = s
		end
	end
	if not seat or r.phase == "done" then
		return
	end
	local S, e = r.S, seat.e
	if kind == IN.aim then
		if r.phase == "aim" and dx and dy then
			Rules.aim(S, e, dx, dy)
		end
	elseif kind == IN.launch then
		if r.phase == "aim" then
			if dx and dy then
				Rules.aim(S, e, dx, dy)
			end
			r.launched[seat.userId] = true
		end
	elseif kind == IN.dir then
		if r.phase ~= "play" or not dx or not dy then
			return
		end
		if S.final then
			local now = os.clock()
			if not Guard.tapOk(rec.lastTap, now, Net.Limits.finalTap) then
				logInput(`{rec.name} final tap dropped: {math.floor((now - (rec.lastTap or 0)) * 1000)} ms`)
				return
			end
			-- лимит считает и отвергнутые правилами тапы, иначе их серия обходит защиту
			rec.lastTap = now
			local ok = Rules.redirect(S, e, dx, dy)
			logInput(`{rec.name} final tap {if ok then "ok" else "refused by rules"} t={S.t}`)
		else
			local ok = Rules.redirect(S, e, dx, dy)
			logInput(`{rec.name} dir {if ok then "ok" else "outside CHOOSE DIRECTION"} t={S.t}`)
		end
	elseif kind == IN.power then
		if r.phase == "play" then
			local ok = Rules.press(S, e)
			logInput(`{rec.name} power {if ok then "fired" else "not charged"}`)
		end
	end
end

-- The person left: a normal bot takes the ball.
function Runner.vacate(r: Runner, rec: any)
	for _, s in r.seats do
		if s.rec == rec then
			s.rec = nil
			s.userId = 0
			local b = r.S.by[s.e]
			if b then
				b.ctl = nil
				b.prompts = false
				b.auto = false
			end
		end
	end
end

-- Final places by land, most first.
function Runner.places(r: Runner): { Net.Place }
	local S = r.S
	local out = {}
	for _, e in S.players do
		local b = S.by[e]
		table.insert(out, {
			e = e,
			pct = math.floor(S.counts[e] / S.area * 1000 + 0.5) / 10,
			kills = b.kills,
			powers = b.powers,
		})
	end
	table.sort(out, function(a, b)
		return a.pct > b.pct
	end)
	return out
end

return Runner
