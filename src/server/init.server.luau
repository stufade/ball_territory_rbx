--!strict
-- Server of M1: matches on tagged arenas, queue with bots, first-entry round, input checks. Protocol: docs/net.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Analytics = require("@self/Analytics")
local Arenas = require("@self/Arenas")
local Avatars = require("@self/Avatars")
local Config = require("@self/Config")
local Guard = require("@self/Logic/Guard")
local Lobby = require("@self/Lobby")
local Modes = require("@self/Modes")
local Net = require(ReplicatedStorage.Shared.Net)
local Party = require("@self/Party")
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Roster = require("@self/Roster")
local Runner = require("@self/Runner")
local Session = require("@self/Session")
local Watch = require("@self/Watch")

print("[BT] server boot")
Arenas.init()
Party.start()

local function onPlayer(player: Player)
	local r = Roster.add(player)
	Avatars.home(player)
	local function spawned(ch: Model)
		local hrp = ch:WaitForChild("HumanoidRootPart", 10)
		local s = r.session
		if hrp and s and not s.closed then
			Session.place(s, r)
		elseif hrp then
			Avatars.spawned(player)
		end
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
	Lobby.join(r)
	Party.joined(r)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayer, p)
end

Players.PlayerRemoving:Connect(function(player)
	local r = Roster.get(player)
	if r then
		Lobby.leave(r, Roster.now())
		Roster.remove(player)
	end
	Analytics.forget(player)
end)

Remotes.Action.OnServerEvent:Connect(function(player, verb, arg)
	local r = Roster.get(player)
	if not r or not Guard.take(r.action, os.clock()) then
		return
	end
	local v, a = Guard.action(verb, arg, Net.Action)
	if v then
		Lobby.action(r, v, a, Roster.now())
	end
end)

Remotes.Input.OnServerEvent:Connect(function(player, kind, dx, dy)
	local r = Roster.get(player)
	if not r or not Guard.take(r.input, os.clock()) then
		return
	end
	local k, x, y = Guard.input(kind, dx, dy, Net.Limits.dirMax)
	local s = r.session
	if k and s and s.runner and s.st == "round" then
		Runner.input(s.runner, r, k, x, y)
	end
end)

-- Stats for M1-6 with DebugBotMatches: rules steps per second of each round in play (30 at normal speed, less in
-- slow motion after a new reaction), frames that hit the catch-up cap, server time per frame.
local stat = { at = os.clock(), frames = 0, busy = 0, worst = 0, base = {} :: { [any]: { number } } }

local function report()
	local now = os.clock()
	local span = now - stat.at
	if span < Config.STAT_EVERY then
		return
	end
	local rates, base = {}, {}
	for _, s in Session.active() do
		local r = s.runner
		if r and s.st == "round" and r.phase == "play" then
			local b = stat.base[r]
			if b then
				table.insert(
					rates,
					string.format("%s %.1f/s capped %d", s.arena.name, (r.steps - b[1]) / span, r.capped - b[2])
				)
			end
			base[r] = { r.steps, r.capped }
		end
	end
	if ServerScriptService:GetAttribute("DebugBotMatches") == true then
		print(
			string.format(
				"[BT] stats: %d sessions, steps [%s], server frame avg %.2f ms, max %.2f ms",
				#Session.active(),
				table.concat(rates, "; "),
				stat.busy / math.max(1, stat.frames) * 1000,
				stat.worst * 1000
			)
		)
	end
	stat.at, stat.frames, stat.busy, stat.worst, stat.base = now, 0, 0, 0, base
end

RunService.Heartbeat:Connect(function(dt)
	local t0 = os.clock()
	local now = Roster.now()
	Lobby.tick(now)
	Watch.tick(dt)
	for _, s in table.clone(Session.active()) do
		if s.closed then
			continue
		end
		if Session.empty(s) then
			Session.close(s)
			continue
		end
		local ok, err = (pcall :: any)(Modes[s.mode].tick, s, dt, now)
		if not ok then
			warn(`[BT] session {s.id} ({s.mode}, {s.arena.name}) failed: {err}`)
			Session.close(s)
		end
	end
	local busy = os.clock() - t0
	stat.frames += 1
	stat.busy += busy
	stat.worst = math.max(stat.worst, busy)
	report()
end)
