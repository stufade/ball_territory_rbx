--!strict
-- Saved records with a session lock (T2.2), on one DataStore through UpdateAsync only. No Roblox globals inside:
-- the DataStore, clock and wait come in, so tests/profile runs it in lune.
-- Record: {data = <profile>, lock = {s = session id, t = os.time()} | nil, saved = os.time()}.
-- Load takes the lock: a lock of another live session is waited for `lockWait` s, then taken over; a lock older than
-- `lockTtl` is a dead server's. Save writes only while the lock is ours (a taken-over session stops writing).
-- Without DataStore access (Studio with API access off, an unpublished place) it works in memory and warns once.
local Store = {}

export type Cfg = { lockTtl: number, lockWait: number, retries: number }

export type Store = {
	ds: any?,
	session: string,
	cfg: Cfg,
	now: () -> number,
	wait: (number) -> (),
	warn: (string) -> (),
	mem: { [string]: any },
	memory: boolean,
}

-- Errors that retrying will not fix: the place cannot reach DataStore at all.
local FATAL = { "Studio", "publish", "403", "not allowed", "InsufficientPermission" }

local function fatal(err: any): boolean
	local s = tostring(err)
	for _, k in FATAL do
		if string.find(s, k, 1, true) then
			return true
		end
	end
	return false
end

function Store.new(
	ds: any?,
	session: string,
	cfg: Cfg,
	now: () -> number,
	wait: (number) -> (),
	warn: (string) -> ()
): Store
	local st: Store = {
		ds = ds,
		session = session,
		cfg = cfg,
		now = now,
		wait = wait,
		warn = warn,
		mem = {},
		memory = ds == nil,
	}
	if ds == nil then
		warn("[BT] profiles: no DataStore, profiles live in this server's memory and are lost when it stops")
	end
	return st
end

local function toMemory(st: Store, err: any)
	if not st.memory then
		st.memory = true
		st.warn(
			`[BT] profiles: DataStore unavailable ({err}). Profiles live in this server's memory now and are lost when it `
				.. "stops. Studio: File > Game Settings > Security > Enable Studio Access to API Services."
		)
	end
end

-- UpdateAsync with retries. In memory mode the same transform runs on the memory table.
local function update(st: Store, key: string, fn: (any) -> any): (boolean, any)
	if not st.memory then
		for attempt = 1, st.cfg.retries do
			local ok, res = pcall(function()
				return (st.ds :: any):UpdateAsync(key, fn)
			end)
			if ok then
				return true, res
			end
			if fatal(res) then
				toMemory(st, res)
				break
			end
			st.warn(`[BT] profiles: {key} attempt {attempt} failed: {res}`)
			if attempt == st.cfg.retries then
				return false, res
			end
			st.wait(math.min(8, 0.5 * 2 ^ attempt))
		end
	end
	local out = fn(st.mem[key])
	if out ~= nil then
		st.mem[key] = out
	end
	return true, out
end

-- Old records saved without the wrapper are taken as the data itself.
local function record(old: any): { [string]: any }
	if type(old) ~= "table" then
		return {}
	end
	if old.data == nil and old.lock == nil and old.saved == nil then
		return { data = old }
	end
	return old
end

-- Takes the lock and returns the stored data (nil for a new player). ok = false: DataStore failed after retries.
function Store.load(st: Store, key: string): (boolean, any)
	local deadline = st.now() + st.cfg.lockWait
	while true do
		local busy = false
		local ok, res = update(st, key, function(old)
			local rec = record(old)
			local lock = rec.lock
			local now = st.now()
			busy = false
			if
				type(lock) == "table"
				and lock.s ~= st.session
				and now - (tonumber(lock.t) or 0) < st.cfg.lockTtl
				and now < deadline
			then
				busy = true
				return nil
			end
			rec.lock = { s = st.session, t = now }
			return rec
		end)
		if not ok then
			return false, nil
		end
		if not busy then
			return true, if type(res) == "table" then res.data else nil
		end
		st.wait(2)
	end
end

-- Writes data while the lock is ours. release = true lets the lock go (the player left). Returns ok, lost (the lock
-- was taken by another session: nothing written).
function Store.save(st: Store, key: string, data: any, release: boolean): (boolean, boolean)
	local lost = false
	local ok = update(st, key, function(old)
		local rec = record(old)
		local lock = rec.lock
		if type(lock) == "table" and lock.s ~= st.session then
			lost = true
			return nil
		end
		return {
			data = data,
			lock = if release then nil else { s = st.session, t = st.now() },
			saved = st.now(),
		}
	end)
	return ok, lost
end

return Store
