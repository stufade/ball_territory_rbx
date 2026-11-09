--!strict
-- Art atlases exported from the web build by tools/art/export.mjs (same canvas functions: ballArt, terrain,
-- terrainIcon, crownArt) and uploaded to Roblox. Layout: assets/art/layout.json.
local Art = {}

Art.BALLS = "rbxassetid://86612121809764" -- 8x5 of 128 px: 0-26 ballArt(e), 27-38 terrainIcon(Config.TOP[i]), 39 crown
Art.TERRAIN = "rbxassetid://100271603934584" -- 64 px tiles: row = index in Config.TOP, col = chk * 8 + frame
Art.ICONS = "rbxassetid://99476412749060" -- 8x4 of 128 px: white icon(e)

Art.BALL = 128
Art.BALL_R = 128 * 0.44 -- ball radius inside a tile; the dark outline reaches 1.12 of it
Art.TILE = 64
Art.FRAMES = 8
Art.CROWN = 39

-- Animated layers: loop period in seconds (8 frames per loop), as in the web terrain() time terms.
Art.PERIOD = {
	water = math.pi / 2,
	burn = math.pi / 8,
	toxic = 1 / 0.6,
	lava = math.pi * 2,
	gas = math.pi,
} :: { [string]: number }

-- Pixel offset of slot n (0-based) in the 128 px balls atlas.
function Art.ballXY(n: number): (number, number)
	return (n % 8) * Art.BALL, (n // 8) * Art.BALL
end
function Art.ballRect(n: number): Vector2
	return Vector2.new(Art.ballXY(n))
end

-- Pixel offset of a terrain tile: layer row (1-based TOP index), checker 0/1, frame 0-7.
function Art.tileXY(row: number, chk: number, frame: number): (number, number)
	return (chk * 8 + frame) * Art.TILE, (row - 1) * Art.TILE
end
function Art.tileRect(row: number, chk: number, frame: number): Vector2
	return Vector2.new(Art.tileXY(row, chk, frame))
end

return Art
