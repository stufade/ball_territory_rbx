--!strict
-- Pure board geometry and cell-value decoding, no Roblox types (runs in lune). Spec: docs/scene.md, docs/net.md.
-- "Local" = object space of the arena Origin: x right, y up (rows go down, so y = -row), z towards the camera.

local floor, max, min, atan, tan, deg, rad, sqrt =
	math.floor, math.max, math.min, math.atan, math.tan, math.deg, math.rad, math.sqrt

local Geo = {}

-- Cell value (docs/net.md): bits 0-4 owner + 1 (0 none), 5-8 top layer index in Config.TOP (0 none), 9-12 fade 0-9.
function Geo.decodeCell(v: number, top: { string }): (number, string?, number)
	local owner = bit32.band(v, 31) - 1
	local li = bit32.band(bit32.rshift(v, 5), 15)
	local fade = bit32.band(bit32.rshift(v, 9), 15)
	return owner, if li > 0 then top[li] else nil, fade
end

-- Centre of arena cell (i, j) in Origin space; lift is the offset towards the camera.
function Geo.cellCenter(i: number, j: number, cs: number, lift: number): (number, number, number)
	return (i + 0.5) * cs, -(j + 0.5) * cs, lift
end

-- Field-rule coordinates (cells, fractional) to Origin space. ox, oy come from Match "start".
function Geo.fieldToLocal(x: number, y: number, ox: number, oy: number, cs: number): (number, number)
	return (x - ox) * cs, -(y - oy) * cs
end

function Geo.localToField(lx: number, ly: number, ox: number, oy: number, cs: number): (number, number)
	return lx / cs + ox, -ly / cs + oy
end

-- Origin-space point on the board to arena cell (0-based), nil outside the field.
function Geo.pointToCell(lx: number, ly: number, cs: number, gw: number, gh: number): (number?, number?)
	local i, j = floor(lx / cs), floor(-ly / cs)
	if i < 0 or j < 0 or i >= gw or j >= gh then
		return nil, nil
	end
	return i, j
end

-- Ray (origin + t * dir) against the plane through the Origin with normal +Z of Origin space; all in Origin space.
-- Returns the hit point on the plane, nil if the ray is parallel or points away.
function Geo.rayToPlane(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): (number?, number?)
	if math.abs(dz) < 1e-6 then
		return nil, nil
	end
	local t = -oz / dz
	if t < 0 then
		return nil, nil
	end
	return ox + dx * t, oy + dy * t
end

-- Direction from a ball to a tapped arena cell centre in field coordinates. nil if the tap is on the ball.
function Geo.dirToCell(bx: number, by: number, i: number, j: number, ox: number, oy: number): (number?, number?)
	local dx, dy = ox + i + 0.5 - bx, oy + j + 0.5 - by
	if dx * dx + dy * dy < 0.0025 then
		return nil, nil
	end
	return dx, dy
end

-- Colour slots of owners: 1 is the viewer (always the same colour), then the others in seat order.
function Geo.slots(seats: { any }, you: number?): { [number]: number }
	local out: { [number]: number } = {}
	local n = 0
	if you then
		out[you] = 1
		n = 1
	end
	for _, s in seats do
		local e: number = s.e
		if out[e] == nil then
			n += 1
			out[e] = min(n, 4)
		end
	end
	return out
end

-- Vertical FOV in degrees so a board of half size hw x hh at distance dist fits with margin; never below minFov.
function Geo.fitFov(hw: number, hh: number, dist: number, aspect: number, margin: number, minFov: number): number
	local v = atan(hh * margin / dist)
	local h = atan(hw * margin / dist)
	local vFromH = atan(tan(h) / max(0.1, aspect))
	return max(minFov, deg(2 * max(v, vFromH)))
end

function Geo.dist2(ax: number, ay: number, bx: number, by: number): number
	local dx, dy = ax - bx, ay - by
	return sqrt(dx * dx + dy * dy)
end

-- Shortest signed angle step from a to b (radians).
function Geo.angleLerp(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

Geo.rad = rad

return Geo
