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
}

Net.SNAP_HZ = 15
Net.SNAP_MAX = Snap.MAX

export type ModeName = "duel" | "ffa" | "intro"

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

-- State remote: one table per screen, `ph` tells which.
export type State = {
	ph: "lobby" | "queue" | "pick" | "draft" | "choose" | "match" | "wait" | "result",
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
	arena: string?,
	win: boolean?,
}

return Net
