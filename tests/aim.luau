--!strict
-- A finger aim stays on the finger, including almost horizontal and almost vertical.
-- The web axis dead-zone (~17°) is not applied to player aim, launch or redirect.
-- lune run tests/aim
local process = require("@lune/process")
local Rules = require("@rules")

local LIMIT = 3 -- degrees; the old dead-zone sat near 17

local function check(cond: boolean, msg: string)
	if not cond then
		print("FAIL: " .. msg)
		process.exit(1)
	end
end

local function gap(ax: number, ay: number, bx: number, by: number): number
	local d = math.deg(math.atan2(by, bx) - math.atan2(ay, ax))
	d = (d + 180) % 360 - 180
	return math.abs(d)
end

-- axes, a few degrees off each axis, and diagonals
local fingers = {
	{ 1, 0 },
	{ 0, 1 },
	{ -1, 0 },
	{ 0, -1 },
	{ 1, 0.04 },
	{ 0.04, 1 },
	{ -1, 0.02 },
	{ 0.03, -1 },
	{ 1, 1 },
	{ -0.7, 0.9 },
	{ 2.5, 0.08 },
}

for _, f in fingers do
	local ax, ay = Rules.aimDir(f[1], f[2])
	check(ax ~= nil and ay ~= nil, `aimDir nil for {f[1]}, {f[2]}`)
	local g = gap(f[1], f[2], ax :: number, ay :: number)
	check(g < LIMIT, `aimDir off by {string.format("%.2f", g)}° for {f[1]}, {f[2]}`)
end

-- Same path as the server: aimDir, then aim, then launch.
local function launched(e: number, dx: number, dy: number, layout: string, seed: number): number
	local ax, ay = Rules.aimDir(dx, dy)
	check(ax ~= nil and ay ~= nil, "aimDir nil before launch")
	local opts: Rules.Options = { layout = layout, seed = seed }
	local S = Rules.newMatch({ { e = e, ctl = "1" }, { e = e + 1 } }, opts)
	check(Rules.aim(S, e, ax :: number, ay :: number), "aim rejected")
	Rules.launch(S)
	local b = S.by[e]
	return gap(dx, dy, b.dx, b.dy)
end

local near = launched(0, 1, 0.05, "duel", 7)
check(near < LIMIT, `near-axis launch off by {string.format("%.2f", near)}°`)
local diag = launched(3, -1, -1.2, "ffa", 3)
check(diag < LIMIT, `diagonal launch off by {string.format("%.2f", diag)}°`)

local S = Rules.newMatch({ { e = 0, ctl = "1" }, { e = 2 } }, { layout = "duel", seed = 1 })
Rules.launch(S)
S.promptUntil = S.t + 5
check(Rules.redirect(S, 0, 0.02, 1), "redirect rejected")
local red = gap(0.02, 1, S.by[0].dx, S.by[0].dy)
check(red < LIMIT, `redirect off by {string.format("%.2f", red)}°`)

print("AIM OK")
