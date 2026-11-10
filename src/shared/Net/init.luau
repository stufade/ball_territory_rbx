--!strict
-- Network protocol of M1: remote names, enums, limits and message shapes. Pure, runs in lune. Spec: docs/net.md.
-- Remote instances live in Net.Remotes (Roblox only), the snapshot codec in Net.Snap.

local Snap = require("@self/Snap")

local Net = {}

Net.Snap = Snap

Net.FOLDER = "Remotes"

Net.Remote = {
	Snap = "Snap", -- UnreliableRemoteEvent S->C (buf: buffer)
	Match = "Match", -- RemoteEvent S->C (kind: string, data: table)
	State = "State", -- RemoteEvent S->C (st: State)
	Input = "Input", -- RemoteEvent C->S (kind: number, dx: number?, dy: number?)
	Action = "Action", -- RemoteEvent C->S (verb: string, arg: number?)
	Party = "Party", -- RemoteEvent S->C (view: PartyView), M1.6
	Profile = "Profile", -- RemoteEvent S->C (view: ProfileView), T2.2
}

Net.Input = {
	aim = 1,
	launch = 2,
	dir = 3,
	power = 4,
}

Net.Action = {
	queue = "queue",
	cancel = "cancel",
	pick = "pick",
	draft = "draft",
	any = "any",
	choose = "choose",
	watch = "watch",
	leave = "leave",
	hello = "hello",
	-- party (M1.6): arg is a UserId where one is needed
	pcreate = "pcreate",
	pinvite = "pinvite", -- (userId) invite a player of this server
	paccept = "paccept", -- (host userId) accept an invite
	pdecline = "pdecline", -- (host userId)
	pleave = "pleave",
	pkick = "pkick", -- (userId), host only
	pplay = "pplay", -- (Net.Mode) host starts: duel = the two members against each other, ffa = all together
	pfriends = "pfriends", -- host opened the Roblox friend invite prompt
	-- T2.1 tutorial: "tut" (cue number) = the player tapped through a waiting cue; "tutor" = HOW TO PLAY on the plaza
	tut = "tut",
	tutor = "tutor",
	-- T2.2: the tutorial reward screen is over (State reward -> lobby)
	claim = "claim",
}

-- Action "queue" argument.
Net.Mode = {
	duel = 1,
	ffa = 2,
}

-- Match remote kinds.
Net.MatchKind = {
	start = "start",
	ev = "ev",
	phase = "phase",
	hint = "hint",
	round = "round",
	finish = "end",
	-- own aim before launch, only to its owner: {id, dx, dy}
	aim = "aim",
	-- M1.6: the viewer no longer gets this match (walked away or the arena closed): {id}
	unview = "unview",
	-- T2.1: tutorial cue {id, s (scene "A".."D"), k (cue), n (cue number), ...} (docs/net.md)
	tut = "tut",
}

-- Hints of the first round (Match "hint" k).
Net.Hint = {
	aim = "aim",
	power = "power",
	react = "react",
	final = "final",
}

-- Starter balls of the first entry: Fire, Ice, Lightning, Plant (element ids of Rules.Config).
Net.STARTERS = { 0, 1, 3, 2 }

Net.Limits = {
	-- token buckets: rate per second and burst
	inputRate = 20,
	inputBurst = 10,
	actionRate = 4,
	actionBurst = 6,
	-- real seconds between direction taps in the final
	finalTap = 0.2,
	-- direction components are clamped to this
	dirMax = 50,
	-- party: people per party, seconds an invite lives, seconds between invites to the same person,
	-- seconds between friend invite prompts, invites a party may have pending
	partyMax = 4,
	inviteTtl = 30,
	inviteGap = 3,
	friendsGap = 5,
	invitesMax = 6,
}

Net.SNAP_HZ = 15
Net.SNAP_MAX = Snap.MAX

export type ModeName = "duel" | "ffa" | "intro" | "tutor"

export type Seat = { e: number, name: string, userId: number, side: number }

export type MatchStart = {
	id: number,
	arena: string,
	aid: number,
	mode: ModeName,
	round: number,
	ox: number,
	oy: number,
	w: number,
	h: number,
	you: number?,
	seats: { Seat },
	key: buffer,
	-- own aim direction in the aim phase (rivals' aims are hidden until launch)
	aim: { number }?,
	-- M1.6: true for a viewer near the arena (no seat, no HUD, no camera)
	view: boolean?,
}

-- Party remote (M1.6): the whole party view of one player, sent on every change.
export type PartyMember = { userId: number, name: string, busy: boolean }
export type PartyInvite = { from: number, name: string, endsAt: number }
export type PartyView = {
	-- nil when not in a party
	id: number?,
	host: number?,
	members: { PartyMember },
	invites: { PartyInvite },
	-- short message to show once ("Party is full", "Couldn't reach your friend's server")
	note: string?,
}

export type RulesEvent = { kind: string, d: { [string]: any } }
export type MatchEvents = { id: number, list: { RulesEvent } }
export type MatchPhase = { id: number, ph: "aim" | "play" | "rend", endsAt: number }
export type MatchHint = { id: number, k: string }
export type RoundEnd = {
	id: number,
	win: number,
	-- balls of sides 0 and 1 this round, their land in % of the arena
	a: number,
	b: number,
	pa: number,
	pb: number,
	lost: { { number } },
	-- rounds won by side 0 and side 1
	score: { number },
}
export type Place = { e: number, pct: number, kills: number, powers: number }
export type MatchEnd = { id: number, mode: ModeName, winner: number, places: { Place } }

-- Profile remote (T2.2): level bar, 2x XP badge and collection of one player, sent on every change.
export type LevelUp = { level: number, e: number? }
export type ProfileView = {
	level: number,
	-- XP inside the level and XP the level needs
	xp: number,
	need: number,
	-- owned balls (element ids) and how many balls there are
	balls: { number },
	total: number,
	-- 2x XP ends at this workspace:GetServerTimeNow() (nil = no boost), the multiplier
	boostEnds: number?,
	boostMult: number,
	-- levels up to this one give a ball
	levelBalls: number,
	-- level ups of this change, to show as NEW BALL! (e = the ball, nil = no ball at that level)
	news: { LevelUp }?,
}

-- State remote: one table per screen, `ph` tells which.
export type State = {
	ph: "lobby" | "queue" | "pick" | "draft" | "choose" | "match" | "wait" | "result" | "reward",
	mode: ModeName?,
	endsAt: number?,
	first: boolean?,
	humans: number?,
	options: { number }?,
	taken: { number }?,
	me: number?,
	turn: number?,
	teams: { { number } }?,
	lost: { { number } }?,
	offer: { number }?,
	any: boolean?,
	names: { string }?,
	left: { number }?,
	rival: number?,
	blind: boolean?,
	-- choose: own ball kept from the won round (-1 = must choose); draft: free "any ball" picks left
	keep: number?,
	anyLeft: number?,
	arena: string?,
	win: boolean?,
	-- lobby (T2.1): plaza button to highlight ("play" after the tutorial)
	glow: string?,
	-- T2.2 draft: the side's own balls to draft from (nil = every ball)
	own: { number }?,
	-- T2.2 result: XP of this match (with the boost) and the multiplier
	xp: number?,
	xpMult: number?,
	-- T2.2 reward after the tutorial: the 4 starters, the legendary of the free spin (decided by the server), the
	-- spin strip's balls, seconds of 2x XP
	balls: { number }?,
	legend: number?,
	pool: { number }?,
	boost: number?,
}

return Net
