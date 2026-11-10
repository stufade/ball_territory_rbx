--!strict
-- Player profiles of T2.2: load with a session lock (Store), the tutorial flag and reward, collection, level, XP,
-- the 2x boost; saves on leave, every PROFILE.autosave s, soon after a reward, and at BindToClose.
-- The client gets its view by the Profile remote (docs/net.md). Pure rules: Logic/Progress.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require("./Config")
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require("./Logic/Progress")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules)
local Store = require("./Store")
local Tutorial = require("./Tutorial")

local P = Config.PROFILE
local rand = Rules.Rng.new()

local Profiles = {}

export type Profile = {
	player: Player,
	key: string,
	data: Progress.Data,
	-- loaded and usable
	ready: boolean,
	-- never written (DataStore failed on load, or DebugFreshProfile): saving it could wipe the real record
	temp: boolean,
	dirty: boolean,
	savedAt: number,
	-- a write is due as soon as the per-key gap allows
	soon: boolean,
	saving: boolean,
	gone: boolean,
}

local profiles: { [Player]: Profile } = {}
local loadedFns: { (Player) -> () } = {}
local store: Store.Store

local function clock(): number
	return os.time()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function Profiles.get(player: Player): Profile?
	local p = profiles[player]
	return if p and p.ready then p else nil
end

-- The client's view: level bar, boost badge, collection; `news` = level ups to show now.
function Profiles.send(player: Player, news: { Progress.LevelUp }?)
	local p = profiles[player]
	if not p or not p.ready or not player.Parent then
		return
	end
	local d = p.data
	local left = Progress.boostLeft(d, clock())
	local view: Net.ProfileView = {
		level = d.level,
		xp = d.xp,
		need = Progress.need(d.level, Config :: any),
		balls = table.clone(d.balls),
		total = Rules.Config.NEL,
		boostEnds = if left > 0 then serverNow() + left else nil,
		boostMult = Config.XP.boost,
		levelBalls = Config.LEVEL_BALLS,
		news = news,
	}
	Remotes.Profile:FireClient(player, view)
end

local function attrs(p: Profile)
	local d = p.data
	p.player:SetAttribute("Level", d.level)
	p.player:SetAttribute("Balls", #d.balls)
end

local function save(p: Profile, release: boolean)
	if p.temp or p.saving then
		return
	end
	p.saving = true
	p.soon = false
	p.savedAt = clock()
	local data = table.clone(p.data)
	data.balls = table.clone(p.data.balls)
	local ok, lost = Store.save(store, p.key, data, release)
	p.saving = false
	if ok and not lost then
		p.dirty = false
	elseif lost then
		-- another server took the profile over: this copy is stale, never write it again
		p.temp = true
		warn(`[BT] profiles: {p.player.Name} is now loaded on another server, this copy stops saving`)
	end
end

local function saveSoon(p: Profile)
	p.dirty = true
	p.soon = true
end

-- Debug: ServerScriptService attribute DebugFreshProfile = true gives joining people a new-player profile that is
-- never saved (the first minutes again, with saving on in Studio).
local function fresh(): boolean
	return ServerScriptService:GetAttribute("DebugFreshProfile") == true
end

function Profiles.join(player: Player)
	local p: Profile = {
		player = player,
		key = "u" .. player.UserId,
		data = Progress.new(),
		ready = false,
		temp = false,
		dirty = false,
		savedAt = 0,
		soon = false,
		saving = false,
		gone = false,
	}
	profiles[player] = p
	task.spawn(function()
		local ok, raw = true, nil
		if fresh() then
			p.temp = true
		else
			ok, raw = Store.load(store, p.key)
		end
		if p.gone then
			-- left while loading: let the lock go
			if ok and not p.temp then
				Store.save(store, p.key, raw, true)
			end
			return
		end
		if not ok then
			p.temp = true
			warn(`[BT] profiles: {player.Name} could not be loaded, playing on a new profile that will not be saved`)
		end
		p.savedAt = clock()
		p.data = Progress.migrate(raw)
		Progress.repair(p.data, Config :: any)
		p.ready = true
		if p.data.tut then
			Tutorial.setDone(player, true)
		end
		attrs(p)
		print(
			string.format(
				"[BT] profile %s: level %d, %d balls, tutorial %s%s%s",
				player.Name,
				p.data.level,
				#p.data.balls,
				if p.data.tut then "done" else "not done",
				if store.memory then " (memory)" else "",
				if p.temp then " (not saved)" else ""
			)
		)
		Profiles.send(player)
		for _, fn in table.clone(loadedFns) do
			task.spawn(fn, player)
		end
	end)
end

function Profiles.leave(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	p.gone = true
	profiles[player] = nil
	if p.ready then
		task.spawn(save, p, true)
	end
end

function Profiles.onLoaded(fn: (Player) -> ())
	table.insert(loadedFns, fn)
end

-- Owned balls. A profile still loading has the starters (the debug switch for all 27: Collection).
function Profiles.balls(player: Player): { number }
	local p = profiles[player]
	if p and p.ready then
		return table.clone(p.data.balls)
	end
	return table.clone(Config.BASE_BALLS)
end

function Profiles.played(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p.ready and p.data.played
end

-- The first real search: the PLAY glow is off for good.
function Profiles.setPlayed(player: Player)
	local p = Profiles.get(player)
	if p and not p.data.played then
		p.data.played = true
		p.dirty = true
	end
end

export type Reward = { balls: { number }, legend: number, pool: { number }, boost: number }

-- The tutorial is won: the reward once per profile (nil on a replay). Saved soon: it is the most valuable moment.
function Profiles.tutorialDone(player: Player): Reward?
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local r = Progress.tutorialReward(p.data, clock(), Config :: any, rand)
	saveSoon(p)
	attrs(p)
	Profiles.send(player)
	if not r then
		return nil
	end
	print(`[BT] T2.2 reward of {player.Name}: 4 balls, legendary {Rules.Config.TITLE[r.legend]}, 2x XP {r.boost} s`)
	return { balls = r.balls, legend = r.legend, pool = table.clone(Config.SPIN_POOL), boost = r.boost }
end

-- A real match is over: XP (boosted), level ups with their balls. Returns what the result screen shows.
function Profiles.award(player: Player, stats: Progress.Stats): Progress.Gain?
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local g = Progress.award(p.data, stats, clock(), Config :: any, rand)
	p.dirty = true
	if #g.ups > 0 then
		saveSoon(p)
	end
	attrs(p)
	Profiles.send(player, if #g.ups > 0 then g.ups else nil)
	return g
end

-- Debug: ServerScriptService attribute DebugXp = n gives every loaded person n XP once (the NEW BALL! screen).
local function debugXp()
	local n = ServerScriptService:GetAttribute("DebugXp")
	if type(n) ~= "number" or n ~= n or n <= 0 then
		return
	end
	ServerScriptService:SetAttribute("DebugXp", nil)
	for player, p in profiles do
		if p.ready then
			local ups = Progress.addXp(p.data, n, Config :: any, rand)
			p.dirty = true
			attrs(p)
			Profiles.send(player, if #ups > 0 then ups else nil)
		end
	end
end

-- Heartbeat: due saves (one write per key per writeGap s), autosave.
function Profiles.tick()
	local now = clock()
	for _, p in profiles do
		if p.ready and not p.temp and not p.saving then
			local age = now - p.savedAt
			if (p.soon and age >= P.writeGap) or age >= P.autosave then
				task.spawn(save, p, false)
			end
		end
	end
end

function Profiles.start()
	local ds = nil
	local ok, err = pcall(function()
		ds = DataStoreService:GetDataStore(P.store)
	end)
	if not ok then
		warn(`[BT] profiles: GetDataStore failed: {err}`)
	end
	local session = if game.JobId ~= "" then game.JobId else `studio-{math.random(1, 2 ^ 30)}-{os.time()}`
	store = Store.new(ds, session, P :: any, clock, function(s)
		task.wait(s)
	end, warn)
	Tutorial.ready = function(player)
		local p = profiles[player]
		return p ~= nil and p.ready
	end
	ServerScriptService:GetAttributeChangedSignal("DebugXp"):Connect(debugXp)
	game:BindToClose(function()
		local left = 0
		for _, p in profiles do
			if p.ready and not p.temp then
				left += 1
				task.spawn(function()
					p.saving = false
					save(p, true)
					left -= 1
				end)
			end
		end
		local t0 = os.clock()
		while left > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end

return Profiles
