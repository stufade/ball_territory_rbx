--!strict
-- Profile v2 fields of M3 (docs/economy.md «Что делать luau-coder» 2), pure: defaults and a checked read of a stored
-- record. Progress.new / Progress.migrate call these; v1 records have none of the fields and get the defaults.
local Meta = {}

local function int(v: any, lo: number, hi: number, def: number): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return def
	end
	return math.clamp(math.floor(v), lo, hi)
end
Meta.int = int

local function str(v: any, max: number): string?
	if type(v) ~= "string" or #v == 0 or #v > max then
		return nil
	end
	return v
end

export type QuestRec = { id: string, n: number, done: boolean }
export type Quests = { day: number, list: { QuestRec }, all: boolean }
export type DayCount = { day: number, n: number }
export type DailyBall = { day: number, e: number, recent: { number } }

-- The v2 part of a profile, merged into Progress.Data.
function Meta.fresh(): { [string]: any }
	return {
		coins = 0,
		crystals = 0,
		-- UTC day number (os.time() // 86400) of the first load, -1 = not set yet
		born = -1,
		-- login reward: days claimed so far (never reset), UTC day of the last claim (-1 = never)
		loginDays = 0,
		dailyClaimed = -1,
		quests = { day = -1, list = {}, all = false } :: Quests,
		-- reaction names found (the book), in the order found
		book = {} :: { string },
		-- spins since the last pity tier (M3.2)
		pity = { coins = 0, crystals = 0 },
		-- duel wins in a row
		streak = 0,
		-- starter pack (M3.2): first shown at os.time(), offer ends at os.time() (0 = not shown)
		starterSeen = 0,
		starterUntil = 0,
		-- draft trials used today, extra trials from the login reward (M3.2)
		trialsUsed = { day = -1, n = 0 } :: DayCount,
		trialBonus = 0,
		-- ball of the day (M3.2): its UTC day, the ball, balls offered in the last days
		dailyBall = { day = -1, e = -1, recent = {} } :: DailyBall,
		-- friend bonus matches today (anti-farm limit)
		friend = { day = -1, n = 0 } :: DayCount,
	}
end

local function dayCount(v: any): DayCount
	if type(v) ~= "table" then
		return { day = -1, n = 0 }
	end
	return { day = int(v.day, -1, 1e7, -1), n = int(v.n, 0, 1e6, 0) }
end

-- Reads the v2 fields of `raw` into `d` (already fresh). Anything malformed keeps the default.
function Meta.read(d: any, raw: { [string]: any })
	d.coins = int(raw.coins, 0, 1e9, 0)
	d.crystals = int(raw.crystals, 0, 1e9, 0)
	d.born = int(raw.born, -1, 1e7, -1)
	d.loginDays = int(raw.loginDays, 0, 1e6, 0)
	d.dailyClaimed = int(raw.dailyClaimed, -1, 1e7, -1)
	local q = raw.quests
	if type(q) == "table" and type(q.list) == "table" then
		local list = {}
		for _, r in q.list do
			local id = if type(r) == "table" then str(r.id, 32) else nil
			if id and #list < 8 then
				table.insert(list, { id = id, n = int(r.n, 0, 1e6, 0), done = r.done == true })
			end
		end
		d.quests = { day = int(q.day, -1, 1e7, -1), list = list, all = q.all == true }
	end
	if type(raw.book) == "table" then
		local seen = {}
		for _, k in raw.book do
			local s = str(k, 32)
			if s and not seen[s] then
				seen[s] = true
				table.insert(d.book, s)
			end
		end
	end
	if type(raw.pity) == "table" then
		d.pity = { coins = int(raw.pity.coins, 0, 1e6, 0), crystals = int(raw.pity.crystals, 0, 1e6, 0) }
	end
	d.streak = int(raw.streak, 0, 1e6, 0)
	d.starterSeen = int(raw.starterSeen, 0, 2 ^ 40, 0)
	d.starterUntil = int(raw.starterUntil, 0, 2 ^ 40, 0)
	d.trialsUsed = dayCount(raw.trialsUsed)
	d.trialBonus = int(raw.trialBonus, 0, 1e6, 0)
	local b = raw.dailyBall
	if type(b) == "table" then
		local recent = {}
		if type(b.recent) == "table" then
			for _, e in b.recent do
				local x = int(e, -1, 26, -1)
				if x >= 0 and x == e and #recent < 16 then
					table.insert(recent, x)
				end
			end
		end
		d.dailyBall = { day = int(b.day, -1, 1e7, -1), e = int(b.e, -1, 26, -1), recent = recent }
	end
	d.friend = dayCount(raw.friend)
end

-- With the config: drops book names that are not reactions and quests that are not in the pool.
function Meta.repair(d: any, reactions: { string }, pool: { { id: string } })
	local ok = {}
	for _, k in reactions do
		ok[k] = true
	end
	for i = #d.book, 1, -1 do
		if not ok[d.book[i]] then
			table.remove(d.book, i)
		end
	end
	local ids = {}
	for _, q in pool do
		ids[q.id] = true
	end
	for i = #d.quests.list, 1, -1 do
		if not ids[d.quests.list[i].id] then
			table.remove(d.quests.list, i)
		end
	end
end

return Meta
