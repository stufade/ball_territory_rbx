--!strict
-- Snapshot interpolation buffer, pure (runs in lune). Frames carry match time t (s), which does not run in real time
-- (slow motion), so playback follows the newest frame with a proportional controller: the play head stays `delay`
-- (match seconds) behind and speeds up or slows down by the gap, never going backwards.

local Smooth = {}
Smooth.__index = Smooth

export type Entry = { t: number, frame: any }
export type Buffer = typeof(setmetatable(
	{} :: { delay: number, entries: { Entry }, head: number?, newest: number, maxRate: number },
	Smooth
))

function Smooth.new(delay: number?): Buffer
	return setmetatable({ delay = delay or 0.1, entries = {}, head = nil, newest = -1, maxRate = 2 }, Smooth)
end

function Smooth.reset(self: Buffer)
	self.entries = {}
	self.head = nil
	self.newest = -1
end

-- Frames arrive in seq order; one with t not newer than the last is dropped.
function Smooth.push(self: Buffer, t: number, frame: any)
	if t <= self.newest then
		return
	end
	self.newest = t
	table.insert(self.entries, { t = t, frame = frame })
	if #self.entries > 12 then
		table.remove(self.entries, 1)
	end
	if self.head == nil then
		self.head = t - self.delay
	end
end

-- Advance the play head by dt real seconds, returns its match time (nil before the first frame).
function Smooth.update(self: Buffer, dt: number): number?
	local head = self.head
	if head == nil then
		return nil
	end
	local lag = self.newest - head
	if lag > self.delay * 6 or lag < 0 then
		head = self.newest - self.delay -- far behind (hitch) or ahead (clock reset): jump
	else
		head += dt * math.clamp(lag / self.delay, 0, self.maxRate)
	end
	self.head = head
	return head
end

-- Entries around match time `at`: a, b, alpha 0-1. Before the first frame a = b; after the last b = a (hold).
function Smooth.sample(self: Buffer, at: number): (any?, any?, number)
	local list = self.entries
	local n = #list
	if n == 0 then
		return nil, nil, 0
	end
	if at <= list[1].t then
		return list[1].frame, list[1].frame, 0
	end
	for i = n, 2, -1 do
		local a, b = list[i - 1], list[i]
		if at >= a.t then
			if at >= b.t then
				return b.frame, b.frame, 0
			end
			return a.frame, b.frame, (at - a.t) / (b.t - a.t)
		end
	end
	return list[1].frame, list[1].frame, 0
end

return Smooth
