--!strict
-- Snapshot codec: round trip on real bot matches, packet sizes and KB/s per client (M1-7).
-- lune run tests/net [matches per mode]
local process = require("@lune/process")
local Rules = require("@rules")
local Snap = require("../src/shared/Net/Snap")

local R = tonumber(process.args[1]) or 6
local STEPS_PER_SNAP = 2 -- 30 steps/s, 15 snapshots/s
local SNAP_HZ = 15

local function check(cond: boolean, msg: string)
	if not cond then
		print("FAIL: " .. msg)
		process.exit(1)
	end
end

local function q(v: number): number
	return math.min(65.535, math.max(0, math.floor(v * 1000 + 0.5) / 1000))
end

-- Expected arena cells straight from the state, same packing as the encoder.
local function truth(enc: Snap.Encoder, S: Rules.State): { number }
	local probe = Snap.newEncoder(S, 0)
	local k = Snap.keyframe(probe, S)
	local out = {}
	for c = 0, enc.n - 1 do
		out[c + 1] = buffer.readu16(k, 6 + c * 2)
	end
	return out
end

local function run(mode: string, seed: number, lose: number)
	local S
	if mode == "duel" then
		S = Rules.newMatch(
			{ { e = 0 }, { e = 6 } },
			{ layout = "duel", round = 30, pace = Rules.Config.DUEL_PACE, seed = seed }
		)
	else
		S = Rules.newMatch({ { e = 0 }, { e = 13 }, { e = 14 }, { e = 24 } }, { layout = "ffa", seed = seed })
	end
	Rules.launch(S)
	local enc = Snap.newEncoder(S, seed)
	local dec = Snap.newDecoder()
	check(Snap.applyKey(dec, Snap.keyframe(enc, S)), "key")
	local rnd = Rules.Rng.new(seed)
	local bytes, packets, snaps, maxPacket, maxSnap = 0, 0, 0, 0, 0
	local lost = 0
	while not S.done do
		for _ = 1, STEPS_PER_SNAP do
			if not S.done then
				Rules.step(S)
			end
		end
		Rules.drain(S)
		local list = Snap.encode(enc, S)
		snaps += 1
		local sz = 0
		for _, p in list do
			local n = buffer.len(p)
			check(n <= Snap.MAX, `packet {n} > {Snap.MAX}`)
			maxPacket = math.max(maxPacket, n)
			sz += n
			packets += 1
			if rnd() < lose then
				lost += 1
			else
				local f = Snap.decode(dec, p)
				if buffer.readu8(p, 0) == Snap.FRAME and f then
					check(#f.balls == #S.balls, "ball count")
					for i, b in S.balls do
						local fb = f.balls[i]
						check(fb.e == b.e and fb.x == q(b.x) and fb.y == q(b.y), "ball position")
						check(fb.alive == b.alive and fb.cnt == S.counts[b.e], "ball state")
					end
				end
			end
		end
		bytes += sz
		maxSnap = math.max(maxSnap, sz)
		-- with no loss every snapshot must leave the client exact
		if lose == 0 then
			local want = truth(enc, S)
			for c = 1, enc.n do
				check(dec.cells[c] == want[c], `cell {c - 1} after snap {snaps}`)
			end
		end
	end
	-- with loss: a few clean snapshots must heal everything (refresh + history)
	if lose > 0 then
		for _ = 1, Snap.REFRESH do
			for _, p in Snap.encode(enc, S) do
				Snap.decode(dec, p)
			end
		end
		local want = truth(enc, S)
		for c = 1, enc.n do
			check(dec.cells[c] == want[c], `healed cell {c - 1}`)
		end
	end
	return bytes / snaps, maxSnap, maxPacket, packets / snaps, lost
end

-- stale and foreign packets are dropped
do
	local S = Rules.newMatch({ { e = 0 }, { e = 1 } }, { layout = "duel", seed = 1 })
	local enc = Snap.newEncoder(S, 7)
	local dec = Snap.newDecoder()
	Snap.applyKey(dec, Snap.keyframe(enc, S))
	local a = Snap.encode(enc, S)[1]
	local b = Snap.encode(enc, S)[1]
	check(Snap.decode(dec, b) ~= nil, "fresh packet")
	check(Snap.decode(dec, a) == nil, "stale packet dropped")
	local other = Snap.newEncoder(S, 8)
	check(Snap.decode(dec, Snap.encode(other, S)[1]) == nil, "foreign ep dropped")
	check(Snap.decode(dec, buffer.create(3)) == nil, "short buffer")
	check(Snap.decode(dec, nil :: any) == nil, "nil")
	check(Snap.fresh(2, 65534) and not Snap.fresh(65534, 2), "seq wrap")
end

for _, mode in { "duel", "ffa" } do
	local avg, mx, mp, ppf, total = 0, 0, 0, 0, 0
	for i = 1, R do
		local a, m, p, pp = run(mode, 100 + i, 0)
		avg += a
		mx = math.max(mx, m)
		mp = math.max(mp, p)
		ppf = math.max(ppf, pp)
		total += 1
	end
	avg /= total
	local _, _, _, _, lost = run(mode, 999, 0.2)
	print(
		string.format(
			"%s: snapshot avg %d B, max %d B, max packet %d B, packets/snap max %.2f -> %.1f KB/s avg, %.1f KB/s peak (lossy run dropped %d packets, healed)",
			mode,
			avg,
			mx,
			mp,
			ppf,
			avg * SNAP_HZ / 1000,
			mx * SNAP_HZ / 1000,
			lost
		)
	)
	check(avg * SNAP_HZ / 1000 < 20, "budget 20 KB/s")
end
print("NET OK")
