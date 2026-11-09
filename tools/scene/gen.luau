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
	-- floor slot width: arenas stand side by side in one row facing the plaza (+Z)
	fw: number,
	-- stands: { x offset from cx, z, top y }
	stands: { { number } },
}

local function arena(a: ArenaSpec): Node
	local cx = a.cx
	local bw, bh = a.gw * a.cs + 1.5, a.gh * a.cs + 1.5
	local by = 203 + bh / 2
	local kids: { Node } = {}
	-- floor slot of the arena row (z -20..30) with neon lanes; the plaza continues it in front
	local fw = a.fw
	table.insert(kids, part("Floor", { fw, 1, 50 }, { cx, 199.5, 5 }, NAVY))
	table.insert(kids, neon("LaneFront", { fw, 0.2, 0.8 }, { cx, 200.1, 14 }))
	table.insert(kids, neon("LaneBack", { fw, 0.2, 0.8 }, { cx, 200.1, -14 }, NEON_PINK))
	table.insert(kids, part("Edge", { fw, 1.6, 51 }, { cx, 198.6, 4.5 }, NAVY_DARK))
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

-- Arena row (x): Duel1..3 every 52 studs, FFA1 in a 64-stud slot; all boards face the plaza (+Z).
local ROW = { -78, -26, 26, 84 }
local arenas: Node = { className = "Folder", children = {} }
for i = 1, 3 do
	table.insert(
		arenas.children,
		arena({
			name = `Duel{i}`,
			mode = "duel",
			cx = ROW[i],
			gw = 16,
			gh = 14,
			cs = 1.5,
			camZ = 22,
			fw = 52,
			stands = DUEL_STANDS,
		})
	)
end
table.insert(
	arenas.children,
	arena({
		name = "FFA1",
		mode = "ffa",
		cx = ROW[4],
		gw = 24,
		gh = 20,
		cs = 1.25,
		camZ = 26,
		fw = 64,
		stands = FFA_STANDS,
	})
)

-- Lobby plaza in front of the arena row (y 200, z 30..74, x -104..116). People run here (faster than usual) and
-- watch the boards; an invisible wall at the rail keeps them out of the match cameras (camera z 22..26).
local PX0, PX1, PZ0, PZ1 = -104, 116, 30, 74
local PW, PD = PX1 - PX0, PZ1 - PZ0
local PCX, PCZ = (PX0 + PX1) / 2, (PZ0 + PZ1) / 2
local WALL = { Transparency = 1, CanQuery = false, CanTouch = false, CastShadow = false }
local function wall(name: string, size: { number }, pos: { number }): Node
	return part(name, size, pos, "#ffffff", nil, WALL)
end
local lobbyKids: { Node } = {
	part("Pad", { PW, 1, PD }, { PCX, 199.5, PCZ }, "#1d3a7a"),
	part("PadEdge", { PW, 1.6, PD }, { PCX, 198.6, PCZ }, NAVY_DARK),
	-- rail between the plaza and the arenas
	neon("Rail", { PW, 0.5, 0.5 }, { PCX, 202.2, PZ0 + 0.4 }),
	part("RailBase", { PW, 1.6, 0.8 }, { PCX, 200.8, PZ0 + 0.4 }, PILLAR),
	wall("WallFront", { PW, 16, 1 }, { PCX, 208, PZ0 }),
	wall("WallBack", { PW, 16, 1 }, { PCX, 208, PZ1 + 0.5 }),
	wall("WallW", { 1, 16, PD + 50 }, { PX0 - 0.5, 208, PCZ - 22 }),
	wall("WallE", { 1, 16, PD + 50 }, { PX1 + 0.5, 208, PCZ - 22 }),
	neon("BorderS", { PW, 0.2, 0.8 }, { PCX, 200.1, PZ1 - 0.4 }, NEON_PINK),
	neon("BorderW", { 0.8, 0.2, PD }, { PX0 + 0.4, 200.1, PCZ }),
	neon("BorderE", { 0.8, 0.2, PD }, { PX1 - 0.4, 200.1, PCZ }),
	-- a ring around the spawn and two lanes towards the arenas
	-- thin square ring around the spawn
	neon("SpawnN", { 16, 0.12, 0.4 }, { 0, 200.06, 48 }, NEON_PINK),
	neon("SpawnS", { 16, 0.12, 0.4 }, { 0, 200.06, 64 }, NEON_PINK),
	neon("SpawnW", { 0.4, 0.12, 16 }, { -8, 200.06, 56 }, NEON_PINK),
	neon("SpawnE", { 0.4, 0.12, 16 }, { 8, 200.06, 56 }, NEON_PINK),
	neon("LaneW", { 0.6, 0.12, 22 }, { -40, 200.06, 52 }),
	neon("LaneE", { 0.6, 0.12, 22 }, { 52, 200.06, 52 }),
	-- light pylons at the back corners
	part("PylonW", { 3, 10, 3 }, { PX0 + 4, 205, PZ1 - 4 }, PILLAR),
	neon("PylonWTop", { 3.4, 0.5, 3.4 }, { PX0 + 4, 210.2, PZ1 - 4 }, NEON_PINK),
	part("PylonE", { 3, 10, 3 }, { PX1 - 4, 205, PZ1 - 4 }, PILLAR),
	neon("PylonETop", { 3.4, 0.5, 3.4 }, { PX1 - 4, 210.2, PZ1 - 4 }),
}
-- Spawn: faces the arenas (-Z). Server sets Player.RespawnLocation to it (src/server/Avatars.luau).
local spawn = part("Spawn", { 12, 1, 12 }, { 0, 199.6, 56 }, "#2a4fa8")
spawn.className = "SpawnLocation"
spawn.properties.Neutral = true
spawn.properties.Duration = 0
spawn.properties.CanCollide = true
table.insert(lobbyKids, spawn)
local lobby: Node = { className = "Folder", children = lobbyKids }

local function write(path: string, node: Node)
	fs.writeFile(path, serde.encode("json", node, true) .. "\n")
	print("wrote " .. path)
end
write("scene/Arenas.model.json", arenas)
write("scene/Lobby.model.json", lobby)
