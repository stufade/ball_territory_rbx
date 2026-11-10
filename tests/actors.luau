--!strict
-- Own ball and aim across duel rounds (F1): every round the sides play other balls, so ball id e changes owner.
-- Before the fix the board kept round 1's "you": the rival who took your old ball got the YOU tag and your aim line,
-- your own new ball had none, and taps aimed from the old ball's spot. Actors on the GUI stand-in (tests/Gui).
-- lune run tests/actors
local process = require("@lune/process")
local Gui = require("./Gui")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local world = Gui.world()
local load = Gui.loader(world)
local Actors = load("src/client/Render/Actors.luau")

local function newFrame(): any
	return Gui.new("Frame")
end
local field = {
	board = { ox = 0, oy = 0, gw = 16, gh = 14, cs = 1.25 },
	under = newFrame(),
	balls = newFrame(),
}

local function ball(e: number, x: number, y: number): any
	return { e = e, x = x, y = y, ang = 0, alive = true, charge = 0, flags = 0, hp = 100, hole = 0, sx = 0, sy = 0 }
end
local function snap(list: { any }): any
	return { balls = list, clones = {}, bubbles = {}, bombs = {} }
end
local function aimShown(a: any, e: number): boolean
	local v = a.balls[e]
	return v ~= nil and v.aimOut.Visible == true
end
local function tagOf(a: any, e: number): string?
	local v = a.balls[e]
	return v and v.tag and v.tag.Text
end

-- round 1: you play ball 8 at (3, 7), the bot ball 9 at (12, 7)
local a = Actors.new(field, 8, { [9] = "FRIEND" })
a.aim = { 1, 0 }
local f1 = snap({ ball(8, 3, 7), ball(9, 12, 7) })
Actors.update(a, f1, f1, 0, 0, true)
check(aimShown(a, 8), "round 1: own aim drawn on ball 8")
check(not aimShown(a, 9), "round 1: rival aim hidden")
check(tagOf(a, 8) == "YOU", "round 1: YOU over ball 8")

-- round 2: you take ball 9 at (3, 7), the rival takes your old ball 8 at (12, 7)
Actors.reset(a, 9, { [8] = "FRIEND" })
a.aim = { 0, 1 }
local f2 = snap({ ball(9, 3, 7), ball(8, 12, 7) })
Actors.update(a, f2, f2, 0, 0, true)
check(aimShown(a, 9), "round 2: own aim drawn on the new own ball 9")
check(not aimShown(a, 8), "round 2: no aim on the rival's ball 8 (was yours in round 1)")
check(tagOf(a, 9) == "YOU", "round 2: YOU over ball 9")
check(tagOf(a, 8) == "FRIEND", "round 2: rival name over ball 8")
local x, y = Actors.ballPos(a, 9)
check(x == 3 and y == 7, "round 2: taps aim from the own new ball")

print(`actors: {passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
