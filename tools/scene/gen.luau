--!strict
-- Scene generator: writes scene/Arenas.model.json and scene/Lobby.model.json (Rojo models).
-- lune run tools/scene/gen
-- Contract for the client and server: docs/scene.md. Stand positions follow the match camera of
-- src/client/Render/Cam.luau: the board fills the middle 48% of the screen width, each side column (26%) holds the
-- player plate on top, the avatar below it and (right) the power button at the bottom.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

type Node = { [string]: any }

local function hex(h: string): { number }
	local r = tonumber(string.sub(h, 2, 3), 16) :: number
	local g = tonumber(string.sub(h, 4, 5), 16) :: number
	local b = tonumber(string.sub(h, 6, 7), 16) :: number
	return { math.floor(r / 255 * 1e6) / 1e6, math.floor(g / 255 * 1e6) / 1e6, math.floor(b / 255 * 1e6) / 1e6 }
end

local function cf(x: number, y: number, z: number): { number }
	return { x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

local function part(name: string, size: { number }, pos: { number }, color: string, mat: string?, extra: Node?): Node
	local p: Node = {
		Size = size,
		CFrame = cf(pos[1], pos[2], pos[3]),
		Color = hex(color),
		Material = mat or "SmoothPlastic",
		Anchored = true,
		TopSurface = "Smooth",
		BottomSurface = "Smooth",
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return { name = name, className = "Part", properties = p }
end

local NOHIT = { CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }

-- Palette: dark navy arena like Ball vs Ball, cyan neon edges; stand glows take the ball colour in a match.
local NAVY = "#1b2a5c"
local NAVY_DARK = "#121a3a"
local RIM = "#0d1124"
local BOARD = "#181e30"
local PILLAR = "#24357a"
local NEON = "#36d6ff"
local NEON_PINK = "#ff4fd8"

local function neon(name: string, size: { number }, pos: { number }, color: string?): Node
	return part(name, size, pos, color or NEON, "Neon", NOHIT)
end

-- Stand pillar: top face at `top`, standing on the floor (y = 200). Glow ring just under the top face.
local function stand(out: { Node }, i: number, x: number, z: number, top: number)
	local h = top - 200
	local w = 4.6
	table.insert(out, part(`Stand{i}`, { w, h, w }, { x, 200 + h / 2, z }, PILLAR))
	table.insert(out, neon(`Glow{i}`, { w + 0.5, 0.45, w + 0.5 }, { x, top - 0.45, z }))
	table.insert(out, neon(`Base{i}`, { w + 1.2, 0.3, w + 1.2 }, { x, 200.15, z }))
end

type ArenaSpec = {
	name: string,
	mode: string,
	cx: number,
	gw: number,
	gh: number,
	cs: number,
	camZ: number,
	-- stands: { x offset from cx, z, top y }
	stands: { { number } },
}

local function arena(a: ArenaSpec): Node
	local cx = a.cx
	local bw, bh = a.gw * a.cs + 1.5, a.gh * a.cs + 1.5
	local by = 203 + bh / 2
	local kids: { Node } = {}
	-- island floor with neon lanes
	table.insert(kids, part("Floor", { 110, 1, 70 }, { cx, 199.5, -6 }, NAVY))
	table.insert(kids, neon("LaneFront", { 110, 0.2, 0.8 }, { cx, 200.1, 14 }))
	table.insert(kids, neon("LaneBack", { 110, 0.2, 0.8 }, { cx, 200.1, -14 }, NEON_PINK))
	table.insert(kids, part("Edge", { 112, 1.6, 72 }, { cx, 198.6, -6 }, NAVY_DARK))
	-- board with a dark rim and neon edges, on a pedestal
	local board = part("Board", { bw, bh, 1 }, { cx, by, 0 }, BOARD)
	board.children = {
		{
			name = "Origin",
			className = "Attachment",
			properties = { CFrame = cf(-a.gw * a.cs / 2, a.gh * a.cs / 2, 0.5) },
		},
	}
	table.insert(kids, board)
	table.insert(kids, part("Rim", { bw + 2, bh + 2, 1 }, { cx, by, -0.6 }, RIM))
	local ex, ey = bw / 2 + 0.45, bh / 2 + 0.45
	table.insert(kids, neon("EdgeTop", { bw + 1.1, 0.18, 0.2 }, { cx, by + ey, 0.05 }))
	table.insert(kids, neon("EdgeBottom", { bw + 1.1, 0.18, 0.2 }, { cx, by - ey, 0.05 }))
	table.insert(kids, neon("EdgeLeft", { 0.18, bh + 1.1, 0.2 }, { cx - ex, by, 0.05 }))
	table.insert(kids, neon("EdgeRight", { 0.18, bh + 1.1, 0.2 }, { cx + ex, by, 0.05 }))
	table.insert(kids, part("Pedestal", { bw * 0.7, 3, 4 }, { cx, 201.5, -0.5 }, NAVY_DARK))
	table.insert(
		kids,
		part("Field", { a.gw * a.cs, a.gh * a.cs, 0.1 }, { cx, by, 0.55 }, "#e2e5ec", nil, { CanCollide = false })
	)
	for i, s in a.stands do
		stand(kids, i, cx + s[1], s[2], s[3])
	end
	table.insert(
		kids,
		part(
			"Camera",
			{ 1, 1, 1 },
			{ cx, by, a.camZ },
			"#ffffff",
			nil,
			{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
		)
	)
	return {
		name = a.name,
		className = "Model",
		properties = { Tags = { "Arena" } },
		attributes = { Mode = a.mode, GridW = a.gw, GridH = a.gh, CellSize = a.cs },
		children = kids,
	}
end

-- Avatar feet heights and side offsets: see the header. Duel: x = 1.0 * depth from the camera, avatar centre 39 px
-- (844x390 phone) under the screen middle. FFA: front-outer and back-inner, x = 1.2 and 0.84 * depth.
local DUEL_STANDS = { { -14.1, 8, 210.9 }, { 14.1, 8, 210.9 } }
local FFA_STANDS = { { -19.2, 10, 211.0 }, { 19.2, 10, 211.0 }, { -16.8, 6, 210.2 }, { 16.8, 6, 210.2 } }

local arenas: Node = { className = "Folder", children = {} }
for i = 1, 3 do
	table.insert(
		arenas.children,
		arena({
			name = `Duel{i}`,
			mode = "duel",
			cx = (i - 1) * 300,
			gw = 16,
			gh = 14,
			cs = 1.5,
			camZ = 22,
			stands = DUEL_STANDS,
		})
	)
end
table.insert(
	arenas.children,
	arena({ name = "FFA1", mode = "ffa", cx = 900, gw = 24, gh = 20, cs = 1.25, camZ = 26, stands = FFA_STANDS })
)

-- Lobby: blue pad with neon border, two light pylons and a dark display board behind the spawn.
local lobbyKids: { Node } = {
	part("Pad", { 60, 1, 60 }, { 0, 0.25, 0 }, "#1d3a7a"),
	neon("BorderN", { 60, 0.2, 0.8 }, { 0, 0.85, -29.6 }),
	neon("BorderS", { 60, 0.2, 0.8 }, { 0, 0.85, 29.6 }),
	neon("BorderW", { 0.8, 0.2, 60 }, { -29.6, 0.85, 0 }),
	neon("BorderE", { 0.8, 0.2, 60 }, { 29.6, 0.85, 0 }),
	neon("Lane", { 3, 0.12, 50 }, { 0, 0.81, 0 }, NEON_PINK),
	part("Display", { 26, 15, 1 }, { 0, 11, -24 }, BOARD),
	part("DisplayRim", { 28, 17, 1 }, { 0, 11, -24.6 }, RIM),
	neon("DisplayEdge", { 27, 0.3, 0.3 }, { 0, 19.05, -23.45 }),
	part("PylonW", { 3, 10, 3 }, { -22, 5.75, -16 }, PILLAR),
	neon("PylonWTop", { 3.4, 0.5, 3.4 }, { -22, 10.5, -16 }, NEON_PINK),
	part("PylonE", { 3, 10, 3 }, { 22, 5.75, -16 }, PILLAR),
	neon("PylonETop", { 3.4, 0.5, 3.4 }, { 22, 10.5, -16 }),
}
local lobby: Node = { className = "Folder", children = lobbyKids }

local function write(path: string, node: Node)
	fs.writeFile(path, serde.encode("json", node, true) .. "\n")
	print("wrote " .. path)
end
write("scene/Arenas.model.json", arenas)
write("scene/Lobby.model.json", lobby)
