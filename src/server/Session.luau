--!strict
-- A session holds one arena from the first screen of a match (draft, pick) to the result screen.
-- Mode logic lives in Modes/Duel, Modes/Ffa, Modes/Intro; they share the helpers here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("./Analytics")
local Arenas = require("./Arenas")
local Avatars = require("./Avatars")
local Config = require("./Config")
local Friends = require("./Friends")
local Net = require(ReplicatedStorage.Shared.Net)
local Party = require("./Party")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Roster = require("./Roster")
local Runner = require("./Runner")
local Watch = require("./Watch")

local Session = {}

Session.award = nil :: Award?

export type Member = { rec: Roster.Rec?, side: number, name: string, userId: number }

export type Session = {
	id: number,
	mode: Net.ModeName,
	arena: Arenas.Arena,
	members: { Member },
	viewers: { [Roster.Rec]: boolean },
	runner: Runner.Runner?,
	st: string,
	endsAt: number,
	debug: boolean,
	closed: boolean,
	startedAt: number,
	data: any,
	recipients: (Session) -> { Player },
	-- KOs and reactions by side over the rounds (Runner adds each round)
	tally: { [number]: Tally },
}

-- kinds: reactions by name; balls: balls the side played; rounds / active: rounds played and with an input
export type Tally = {
	kills: number,
	rx: number,
	kinds: { [string]: number },
	balls: { number },
	rounds: number,
	active: number,
}

-- T2.2: XP of a finished match for one person, set by the server bootstrap (Profiles.award); M3.1 also coins.
-- afk: some round had no input of the person; friend: an active Roblox friend played this match too.
-- Returns the fields the result screen adds (xp, xpMult, coins, ...).
export type Award = (
	player: Player,
	mode: Net.ModeName,
	win: boolean,
	t: Tally,
	afk: boolean,
	friend: boolean
) -> { [string]: any }?

local nextId = 0
local active: { Session } = {}

local function recipients(s: Session): { Player }
	local out = {}
	for _, m in s.members do
		if m.rec and m.rec.player.Parent then
			table.insert(out, m.rec.player)
		end
	end
	for v in s.viewers do
		if v.player.Parent then
			table.insert(out, v.player)
		end
	end
	return out
end

function Session.active(): { Session }
	return active
end

-- recs: people of the session (side = index - 1); seats beyond them are bots named "BOT".
function Session.new(mode: Net.ModeName, arena: Arenas.Arena, recs: { Roster.Rec }, debug: boolean): Session
	nextId += 1
	local seats = Config.SEATS[mode]
	local members = {}
	-- debug: a lone person takes side 1 (right seat) of a duel, to check the client from both sides
	local shift = if mode == "duel" and #recs == 1 and ServerScriptService:GetAttribute("DebugSide") == 1 then 1 else 0
	for i = 1, seats do
		local r = recs[i - shift]
		members[i] = {
			rec = r,
			side = i - 1,
			name = if r then r.name else "BOT",
			userId = if r then r.id else 0,
		}
	end
	local s: Session = {
		id = nextId,
		mode = mode,
		arena = arena,
		members = members,
		viewers = {},
		runner = nil,
		st = "",
		endsAt = 0,
		debug = debug,
		closed = false,
		startedAt = Roster.now(),
		data = {},
		recipients = recipients,
		tally = {},
	}
	arena.session = s
	table.insert(active, s)
	-- who plays here, for the arena sign on the plaza
	arena.model:SetAttribute("Live", table.concat(Session.names(s), if mode == "ffa" then " · " else " vs "))
	for _, m in members do
		local r = m.rec
		if r then
			r.session = s
			r.matches += 1
			if r.matches == 2 then
				Analytics.step(r.player, Analytics.Step.SecondMatch)
			end
			Analytics.custom(r.player, "MatchStart", 1, mode)
			Session.place(s, r)
		end
	end
	return s
end

function Session.humans(s: Session): { Member }
	local out = {}
	for _, m in s.members do
		if m.rec then
			table.insert(out, m)
		end
	end
	return out
end

function Session.member(s: Session, rec: Roster.Rec): Member?
	for _, m in s.members do
		if m.rec == rec then
			return m
		end
	end
	return nil
end

function Session.place(s: Session, rec: Roster.Rec)
	local m = Session.member(s, rec)
	if m then
		Avatars.place(rec.player, s.arena.stands[m.side + 1])
	end
end

function Session.names(s: Session): { string }
	local out = {}
	for _, m in s.members do
		table.insert(out, m.name)
	end
	return out
end

-- Sends a State built per member: build(member) -> State.
function Session.each(s: Session, build: (Member) -> Net.State?)
	for _, m in s.members do
		if m.rec then
			local st = build(m)
			if st then
				Roster.send(m.rec, st, true)
			end
		end
	end
end

function Session.fire(s: Session, kind: string, data: { [string]: any })
	data.id = s.id
	for _, p in recipients(s) do
		Remotes.Match:FireClient(p, kind, data)
	end
end

-- Match over: Match "end", result screens; the session closes after RESULT_TIME.
function Session.finish(s: Session, winner: number, places: { Net.Place }, winOf: (Member) -> boolean)
	Session.fire(s, Net.MatchKind.finish, { mode = s.mode, winner = winner, places = places })
	s.st = "result"
	s.endsAt = Roster.now() + Config.RESULT_TIME
	local afk: { [Member]: boolean } = {}
	for _, m in s.members do
		local t = s.tally[m.side]
		afk[m] = t == nil or t.active < t.rounds
	end
	for _, m in s.members do
		local r = m.rec
		if r then
			local win = winOf(m)
			local t = s.tally[m.side] or { kills = 0, rx = 0, kinds = {}, balls = {}, rounds = 0, active = 0 }
			local award = Session.award
			local st: Net.State = { ph = "result", mode = s.mode, win = win, endsAt = s.endsAt }
			if award and not s.debug then
				local friend = false
				for _, o in s.members do
					local orec = o.rec
					if o ~= m and orec and o.userId > 0 and not afk[o] and Friends.are(r.player, orec.player) then
						friend = true
					end
				end
				local add = award(r.player, s.mode, win, t, afk[m], friend)
				if add then
					for k, v in add do
						(st :: any)[k] = v
					end
				end
			end
			Roster.send(r, st, true)
			Analytics.custom(r.player, "MatchEnd", if win then 1 else 0, s.mode, if win then "win" else "lose")
		end
	end
end

-- Person goes back to the lobby: leaves the session, avatar to the lobby pad.
function Session.detach(s: Session, rec: Roster.Rec)
	if rec.session == s then
		rec.session = nil
		Avatars.release(rec.player)
		Roster.lobby(rec)
		Party.refresh(rec)
	end
	local m = Session.member(s, rec)
	if m then
		m.rec = nil
	end
	s.viewers[rec] = nil
end

function Session.close(s: Session)
	if s.closed then
		return
	end
	s.closed = true
	for _, m in s.members do
		if m.rec then
			Session.detach(s, m.rec)
			m.rec = nil
		end
	end
	for v in table.clone(s.viewers) do
		Watch.stop(v)
	end
	s.viewers = {}
	s.arena.session = nil
	s.arena.model:SetAttribute("Live", nil)
	local i = table.find(active, s)
	if i then
		table.remove(active, i)
	end
end

-- Nobody to play for: no people and no viewers, outside debug mode.
function Session.empty(s: Session): boolean
	return not s.debug and #Session.humans(s) == 0 and next(s.viewers) == nil
end

-- Person left the server mid-session: the seat goes to a bot.
function Session.vacate(s: Session, rec: Roster.Rec)
	local m = Session.member(s, rec)
	if m then
		m.rec = nil
		m.userId = 0
		Analytics.custom(rec.player, "MatchLeave", math.floor(Roster.now() - s.startedAt), s.mode)
	end
	if s.runner then
		Runner.vacate(s.runner, rec)
	end
	s.viewers[rec] = nil
	rec.session = nil
end

return Session
