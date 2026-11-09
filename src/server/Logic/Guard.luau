--!strict
-- Client input checks, pure: types, NaN and infinities, enums, token-bucket rate limits, final tap spacing.
-- Every check returns nil/false for bad input; nothing here throws.
local Guard = {}

export type Bucket = { rate: number, burst: number, tokens: number, at: number }

function Guard.bucket(rate: number, burst: number, now: number): Bucket
	return { rate = rate, burst = burst, tokens = burst, at = now }
end

function Guard.take(b: Bucket, now: number): boolean
	local dt = now - b.at
	if dt > 0 then
		b.tokens = math.min(b.burst, b.tokens + dt * b.rate)
	end
	b.at = math.max(b.at, now)
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function Guard.finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Direction component: finite number clamped to +-max, else nil.
function Guard.num(v: any, max: number): number?
	if not Guard.finite(v) then
		return nil
	end
	return math.clamp(v, -max, max)
end

-- Integer in [lo, hi], else nil.
function Guard.int(v: any, lo: number, hi: number): number?
	if not Guard.finite(v) or v % 1 ~= 0 or v < lo or v > hi then
		return nil
	end
	return v
end

-- Input remote: kind 1 aim, 2 launch, 3 dir, 4 power. Returns kind, dx, dy or nil.
-- Launch may come without a direction; aim and dir need one; a zero direction is rejected.
function Guard.input(kind: any, dx: any, dy: any, max: number): (number?, number?, number?)
	local k = Guard.int(kind, 1, 4)
	if not k then
		return nil
	end
	if k == 4 then
		return k, nil, nil
	end
	local x, y = Guard.num(dx, max), Guard.num(dy, max)
	if k == 2 and dx == nil and dy == nil then
		return k, nil, nil
	end
	if not x or not y or (x == 0 and y == 0) then
		return nil
	end
	return k, x, y
end

-- Action remote: verb from the allowed set, optional finite argument. Returns verb, arg or nil.
function Guard.action(verb: any, arg: any, verbs: { [string]: string }): (string?, number?)
	if type(verb) ~= "string" or #verb > 16 or verbs[verb] ~= verb then
		return nil
	end
	if arg ~= nil and not Guard.finite(arg) then
		return nil
	end
	return verb, arg
end

-- Roblox UserId (Studio test players are negative): a non-zero integer.
function Guard.userId(v: any): number?
	local id = Guard.int(v, -2 ^ 53, 2 ^ 53)
	return if id and id ~= 0 then id else nil
end

-- At most one call per `gap` seconds for each key of `last` (key -> time of the last allowed call).
function Guard.cooldown(last: { [any]: number }, key: any, now: number, gap: number): boolean
	local t = last[key]
	if t and now - t < gap then
		return false
	end
	last[key] = now
	return true
end

-- Element id 0..nel-1.
function Guard.element(v: any, nel: number): number?
	return Guard.int(v, 0, nel - 1)
end

-- Final-phase direction taps: at most one per `gap` real seconds. `last` is the time of the last accepted tap.
function Guard.tapOk(last: number?, now: number, gap: number): boolean
	return last == nil or now - last >= gap - 1e-6
end

return Guard
