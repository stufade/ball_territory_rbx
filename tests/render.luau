--!strict
-- Pure parts of the client renderer: cell/world conversion, smoothing buffer, cell value decoding, slots, FOV fit.
-- lune run tests/render
local Rules = require("@rules")
local Geo = require("../src/client/Render/Geo")
local Smooth = require("../src/client/Render/Smooth")
local Snap = require("../src/shared/Net/Snap")
local Art = require("../src/shared/Art")

local fails = 0
local function check(cond: boolean, msg: string)
	if not cond then
		fails += 1
		print("FAIL: " .. msg)
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-9)
end

-- cell <-> local <-> field
local cs = 1.5
for _, c in { { 0, 0 }, { 15, 13 }, { 7, 3 } } do
	local lx, ly, lz = Geo.cellCenter(c[1], c[2], cs, 0.1)
	check(lz == 0.1, "lift")
	local i, j = Geo.pointToCell(lx, ly, cs, 16, 14)
	check(i == c[1] and j == c[2], "cell round trip " .. c[1] .. "," .. c[2])
end
check(Geo.pointToCell(-0.01, -0.5, cs, 16, 14) == nil, "left of field")
check(Geo.pointToCell(0.5, 0.01, cs, 16, 14) == nil, "above field")
check(Geo.pointToCell(16 * cs + 0.01, -1, cs, 16, 14) == nil, "right of field")
check(Geo.pointToCell(1, -14 * cs - 0.01, cs, 16, 14) == nil, "below field")
local lx, ly = Geo.fieldToLocal(6.5, 5.25, 4, 3, cs)
local fx, fy = Geo.localToField(lx, ly, 4, 3, cs)
check(near(fx, 6.5) and near(fy, 5.25), "field round trip")
local i, j = Geo.pointToCell(lx, ly, cs, 16, 14)
check(i == 2 and j == 2, "field point is in cell (2,2)")

-- ray against the board plane (camera at +Z looking to -Z)
local px, py = Geo.rayToPlane(1, -2, 10, 0.1, -0.2, -1)
check(px ~= nil and py ~= nil and near(px :: number, 2) and near(py :: number, -4), "ray hits the plane")
check(Geo.rayToPlane(0, 0, 10, 0, 0, 1) == nil, "ray away from plane")
check(Geo.rayToPlane(0, 0, 10, 1, 0, 0) == nil, "ray parallel to plane")

-- direction
local dx, dy = Geo.dirToCell(5, 5, 7, 5, 4, 3)
check(dx ~= nil and dy ~= nil and near(dx :: number, 11.5 - 5) and near(dy :: number, 8.5 - 5), "dir to cell centre")
check(Geo.dirToCell(7.5, 8.5, 3, 5, 4, 3) == nil, "tap on the ball")

-- cell value decoding against the Snap helpers
local TOP = Rules.Config.TOP
for _, v in { 0, 1, 5, 27, 32 + 3, 12 * 32 + 1, 9 * 512 + 7 * 32 + 20, 4095 } do
	local o, l, f = Geo.decodeCell(v, TOP)
	check(o == Snap.owner(v), "owner of " .. v)
	check(l == Snap.layerName(v), "layer of " .. v)
	check(f == Snap.fade(v), "fade of " .. v)
end
local o, l, f = Geo.decodeCell(9 * 512 + 2 * 32 + 6, TOP)
check(o == 5 and l == TOP[2] and f == 9, "decode example")
check(select(1, Geo.decodeCell(0, TOP)) == -1, "no owner")

-- slots: viewer first, always colour 1
local sl = Geo.slots({ { e = 3 }, { e = 0 }, { e = 7 } }, 0)
check(sl[0] == 1 and sl[3] == 2 and sl[7] == 3, "slots viewer first")
check(Geo.slots({ { e = 4 }, { e = 9 } }, nil)[4] == 1, "slots without viewer")

-- FOV fit: never below the base, grows for a narrow screen
check(Geo.fitFov(12, 10.5, 40, 2.2, 1.1, 70) == 70, "wide screen keeps base fov")
check(Geo.fitFov(15, 12.5, 20, 1.0, 1.1, 70) > 70, "square screen widens fov")
local fov = Geo.fitFov(15, 12.5, 30, 1.0, 1.0, 10)
check(near(fov, math.deg(2 * math.atan(15 / 30)), 1e-6), "fov exact on width")

-- smoothing: 15 Hz frames with jitter, match time slows to 1/3 in the middle
do
	local sm = Smooth.new(0.1)
	check(sm:update(0.016) == nil, "no head before a frame")
	local t = 0
	local prevHead = -1
	local worstLag, minLag = 0, 1e9
	local dtReal = 1 / 60
	local clock = 0
	local nextArrive = 0
	local rng = 7
	local function jitter(): number
		rng = (rng * 1103515245 + 12345) % 2147483648
		return rng / 2147483648 * 0.06 -- up to 60 ms
	end
	local queue: { { at: number, t: number } } = {}
	local matchRate = 1
	for step = 1, 60 * 20 do
		clock += dtReal
		matchRate = if clock > 8 and clock < 12 then 1 / 3 else 1
		t += dtReal * matchRate
		if clock >= nextArrive then
			nextArrive += 1 / 15
			table.insert(queue, { at = clock + jitter(), t = t })
		end
		table.sort(queue, function(a, b)
			return a.at < b.at
		end)
		while queue[1] and queue[1].at <= clock do
			sm:push(queue[1].t, { t = queue[1].t })
			table.remove(queue, 1)
		end
		local head = sm:update(dtReal)
		if head then
			check(head >= prevHead, "play head never goes back")
			prevHead = head
			local a, b, al = sm:sample(head)
			check(a ~= nil and b ~= nil, "sample exists")
			check(al >= 0 and al <= 1, "alpha in range")
			if a and b then
				check(a.t <= head + 1e-9 and head <= b.t + 1e-9 or a == b, "head between samples")
			end
			if step > 120 then
				local lag = sm.newest - head
				worstLag = math.max(worstLag, lag)
				minLag = math.min(minLag, lag)
			end
		end
	end
	check(minLag >= 0, "head never ahead of the newest frame")
	check(worstLag < 0.5, "lag bounded: " .. worstLag)
end

-- stale and duplicate frames are dropped, sample clamps
do
	local sm = Smooth.new(0.1)
	sm:push(1, "a")
	sm:push(1, "dup")
	sm:push(0.5, "old")
	sm:push(2, "b")
	check(#sm.entries == 2, "stale and duplicate frames dropped")
	local a, b, t = sm:sample(1.5)
	check(a == "a" and b == "b" and near(t, 0.5), "mid sample")
	a, b = sm:sample(5)
	check(a == "b" and b == "b", "hold after last")
	a, b = sm:sample(-5)
	check(a == "a" and b == "a", "hold before first")
	sm:reset()
	check(sm:update(1) == nil and #sm.entries == 0, "reset")
end

-- angle interpolation takes the short way
check(near(Geo.angleLerp(6.2, 0.1, 0.5), 6.2 + ((0.1 - 6.2 + math.pi) % (2 * math.pi) - math.pi) * 0.5), "angle lerp")

-- art atlases (assets/art/layout.json): ball slots 8 per row, terrain row per Config.TOP layer
do
	local x, y = Art.ballXY(0)
	check(x == 0 and y == 0, "ball slot 0")
	x, y = Art.ballXY(26)
	check(x == 2 * 128 and y == 3 * 128, "ball slot 26 (candy)")
	x, y = Art.ballXY(Art.CROWN)
	check(x == 7 * 128 and y == 4 * 128, "crown slot")
	x, y = Art.tileXY(#TOP, 1, 7)
	check(x == 15 * 64 and y == (#TOP - 1) * 64, "last terrain tile")
	for name in Art.PERIOD do
		check(table.find(TOP, name) ~= nil, "animated layer " .. name .. " is a TOP layer")
	end
end

if fails > 0 then
	print(fails .. " checks failed")
	error("render tests failed")
end
print("render tests ok")
