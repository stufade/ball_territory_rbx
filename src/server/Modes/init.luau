--!strict
-- Mode logic by session mode: start, tick, action, leave.
local Duel = require("@self/Duel")
local Ffa = require("@self/Ffa")
local Intro = require("@self/Intro")

export type Mode = {
	start: (any, number) -> (),
	tick: (any, number, number) -> (),
	action: (any, any, string, number?, number) -> (),
	leave: (any, any, number) -> (),
}

local Modes: { [string]: Mode } = {
	duel = Duel :: any,
	ffa = Ffa :: any,
	intro = Intro :: any,
}

return Modes
