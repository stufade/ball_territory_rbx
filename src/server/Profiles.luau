--!strict
-- Player profiles of T2.2: load with a session lock (Store), the tutorial flag and reward, collection, level, XP,
-- the 2x boost; saves on leave, every PROFILE.autosave s, soon after a reward, and at BindToClose.
-- The client gets its view by the Profile remote (docs/net.md). Pure rules: Logic/Progress.
-- M3.1: coins and crystals, match coins, login reward, daily quests, reaction book (Logic/Award, Daily), analytics.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("./Analytics")
local Award = require("./Logic/Award")
local Config = require("./Config")
local Daily = require("./Logic/Daily")
local Net = require(ReplicatedStorage.Shared.Net)
local Progress = require("./Logic/Progress")
local Receipt = require("./Logic/Receipt")
local Shop = require("./Logic/Shop")
local Spin = require("./Logic/Spin")
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
	-- the UTC day the quests were last looked at (a new day refreshes the view)
	day: number,
}

local profiles: { [Player]: Profile } = {}
local loadedFns: { (Player) -> () } = {}
local store: Store.Store
-- true when PolicyService said paid random is restricted. Nil until the first answer (a failed read stays allowed).
local paidRandomBlocked: { [Player]: boolean } = {}

local shiftDays: () -> number

local function clock(): number
	return os.time() + shiftDays()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

function Profiles.get(player: Player): Profile?
	local p = profiles[player]
	return if p and p.ready then p else nil
end

local NAMES = Rules.Config.REACTIONS

-- TODO(REMOVE BEFORE LAUNCH): dev button. Studio, the place owner, or Config.DEV_USERS.
function Profiles.isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	local id = player.UserId
	if id <= 0 then
		return false
	end
	return (game.CreatorType.Name == "User" and id == game.CreatorId) or table.find(Config.DEV_USERS, id) ~= nil
end

-- PolicyService. A failed or missing read does not hide the wheels (Studio can still spin). A true
-- ArePaidRandomItemsRestricted hides both and Spin.roll refuses. Cached for the session.
local function paidRandom(player: Player): boolean
	local known = paidRandomBlocked[player]
	if known ~= nil then
		return known
	end
	local ok, info = pcall(function()
		local PolicyService = game:GetService("PolicyService")
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local flag = false
	if ok and type(info) == "table" then
		flag = info.ArePaidRandomItemsRestricted == true
		Analytics.paidRandom(player, flag)
	end
	paidRandomBlocked[player] = flag
	return flag
end

-- The client's view: level bar, boost badge, collection; `news` = level ups to show now; `extra` = one-off fields
-- of this change (gains, found, done, claim).
function Profiles.send(player: Player, news: { Progress.LevelUp }?, extra: { [string]: any }?)
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
		nextBall = d.nextBall,
		dev = if Profiles.isDev(player) then true else nil,
		news = news,
	}
	for k, v in Award.view(d, clock(), serverNow(), Config, #NAMES) do
		(view :: any)[k] = v
	end
	view.spin = Spin.board(d, Config.ECON, not paidRandom(player))
	if extra then
		for k, v in extra do
			(view :: any)[k] = v
		end
	end
	Remotes.Profile:FireClient(player, view)
end

local function attrs(p: Profile)
	local d = p.data
	p.player:SetAttribute("Level", d.level)
	p.player:SetAttribute("Balls", #d.balls)
	p.player:SetAttribute("Coins", d.coins)
	p.player:SetAttribute("Crystals", d.crystals)
end

local function deep(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deep(v)
	end
	return out
end

-- Wallet flows: to analytics, and to the client as "gains" (counters roll, small toasts).
local function gains(player: Player, log: { any }): { any }?
	Analytics.flows(player, log)
	local out = {}
	for _, f in log do
		if not f.sink then
			table.insert(out, { cur = f.cur, n = f.n, why = f.why })
		end
	end
	return if #out > 0 then out else nil
end

local function save(p: Profile, release: boolean)
	if p.temp or p.saving then
		return
	end
	p.saving = true
	p.soon = false
	p.savedAt = clock()
	-- a deep copy: the save yields, the live data keeps changing
	local data = deep(p.data)
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
		day = -1,
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
		Progress.repair(p.data, Config :: any, NAMES)
		local now = clock()
		if p.data.born < 0 then
			p.data.born = Daily.day(now)
		end
		p.day = Daily.day(now)
		Daily.quests(p.data, now, Config.ECON, rand)
		Progress.plan(p.data, Config :: any, rand)
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
		local blocked = paidRandom(player)
		if p.gone then
			return
		end
		if blocked then
			print(`[BT] paid random restricted for {player.Name}: coin and crystal spins hidden`)
		end
		Profiles.send(player)
		Analytics.collection(player, #p.data.balls, Daily.day(now) - p.data.born, #p.data.book)
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
	paidRandomBlocked[player] = nil
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

-- A real match is over: coins, XP (boosted), level ups with their balls, quests, new reactions of the book.
-- Returns what the result screen shows.
function Profiles.award(player: Player, info: Award.Info): Award.Result?
	local p = Profiles.get(player)
	if not p then
		return nil
	end
	local log = {}
	local res = Award.match(p.data, info, clock(), Config, rand, NAMES, log)
	local g = res.gain
	p.dirty = true
	if #g.ups > 0 or #res.quests > 0 or #res.book.new > 0 then
		saveSoon(p)
	end
	attrs(p)
	Profiles.send(player, if #g.ups > 0 then g.ups else nil, {
		gains = gains(player, log),
		found = if #res.book.new > 0 then res.book.new else nil,
		done = if #res.quests > 0 then res.quests else nil,
	})
	return res
end

-- TODO(REMOVE BEFORE LAUNCH): dev button. All 27 balls into the collection; refused for everybody who is not a dev.
function Profiles.devAllBalls(player: Player): boolean
	local p = Profiles.get(player)
	if not p or not Profiles.isDev(player) then
		return false
	end
	Progress.giveAll(p.data, Config :: any, rand)
	p.dirty = true
	attrs(p)
	Profiles.send(player)
	return true
end

-- Action daily: today's login reward (once per UTC day). Saved soon (VOID on the 7th day).
function Profiles.claimDaily(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local log = {}
	local c = Daily.claim(p.data, clock(), Config.ECON, log)
	if not c then
		return
	end
	saveSoon(p)
	attrs(p)
	Analytics.login(player, c.n, c.pos, c.cycle)
	print(`[BT] login reward of {player.Name}: day {c.pos} (claim {c.n})`)
	Profiles.send(player, nil, { gains = gains(player, log), claim = c })
end

-- Action buy: ball `e` for "coins" or "crystals". The price comes from the tier. A refusal spends nothing
-- and sends nothing. A purchase is in the same profile snapshot as the other rewards: `balls`, `coins`,
-- `crystals`, and the ball-of-the-day prices on `dailyBall`. The spend is a Shop sink in the economy log.
function Profiles.buyBall(player: Player, e: any, cur: any)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local log = {}
	local bought = Shop.buy(p.data, e, cur, clock(), Config.ECON, log)
	if not bought then
		return
	end
	Progress.plan(p.data, Config :: any, rand)
	saveSoon(p)
	attrs(p)
	print(`[BT] {player.Name} bought {Rules.Config.TITLE[bought.e]} for {bought.n} {bought.cur}`)
	Profiles.send(player, nil, { gains = gains(player, log) })
end

-- Action spin: currency only. The ball is chosen here, then the profile carries it in spinResult for the reel.
function Profiles.spin(player: Player, cur: any)
	local blocked = paidRandom(player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	if blocked then
		Profiles.send(player)
		return
	end
	local log = {}
	local hit = Spin.roll(p.data, cur, Config.ECON, rand, log, false)
	if not hit then
		-- short balance or a bad currency: nothing was spent; refresh so the buttons match the wallet
		Profiles.send(player)
		return
	end
	Progress.plan(p.data, Config :: any, rand)
	saveSoon(p)
	attrs(p)
	Analytics.spin(player, hit.cur, hit.tier, hit.pity)
	local what = if hit.e then Rules.Config.TITLE[hit.e] else `refund +{hit.back}`
	print(`[BT] {player.Name} spun {hit.cur}: {hit.tier} {what}`)
	Profiles.send(player, nil, { gains = gains(player, log), spinResult = hit })
end

-- Debug: ServerScriptService attribute DebugDay = n shifts this server's profile clock by n days (login and
-- quest resets without waiting for 00:00 UTC). Never set in a live game.
function shiftDays(): number
	local n = ServerScriptService:GetAttribute("DebugDay")
	return if type(n) == "number" and n == n then math.floor(n) * 86400 else 0
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
			local log = {}
			local ups = Progress.addXp(p.data, n, Config :: any, rand, log)
			p.dirty = true
			attrs(p)
			Profiles.send(player, if #ups > 0 then ups else nil, { gains = gains(player, log) })
		end
	end
end

-- Heartbeat: due saves (one write per key per writeGap s), autosave; a new UTC day refreshes quests and login.
function Profiles.tick()
	local now = clock()
	local today = Daily.day(now)
	for player, p in profiles do
		if p.ready and p.day ~= today then
			p.day = today
			Daily.quests(p.data, now, Config.ECON, rand)
			p.dirty = true
			Profiles.send(player)
		end
	end
	for _, p in profiles do
		if p.ready and not p.temp and not p.saving then
			local age = now - p.savedAt
			if (p.soon and age >= P.writeGap) or age >= P.autosave then
				task.spawn(save, p, false)
			end
		end
	end
end

-- Writes the profile now. False when it is not durable yet (still saving, temporary, or the write failed):
-- ProcessReceipt must answer NotProcessedYet in that case.
function Profiles.commit(player: Player): boolean
	local p = profiles[player]
	if not p or not p.ready or p.temp or p.saving then
		return false
	end
	save(p, false)
	return not p.dirty and not p.temp
end

-- The ball (slot "ball") or the starter epic (slot "epic") chosen before the purchase prompt.
function Profiles.chooseRobux(player: Player, slot: string, e: number): boolean
	local p = Profiles.get(player)
	if not p or not Receipt.choose(p.data, slot, e, Config.ECON) then
		return false
	end
	saveSoon(p)
	return true
end

-- A Robux grant is in memory: refresh the next level ball, the attributes, and the client.
function Profiles.showGain(player: Player, log: { any })
	local p = profiles[player]
	if not p or not p.ready then
		return
	end
	Progress.plan(p.data, Config :: any, rand)
	attrs(p)
	local g = gains(player, log)
	Profiles.send(player, nil, if g then { gains = g } else nil)
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
