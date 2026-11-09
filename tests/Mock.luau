--!strict
--# selene: allow(shadowing, incorrect_standard_library_use)
-- Minimal Roblox stand-in for running src/server in lune (tests/flow). Only what the server touches.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Mock = {}

local T = 1000 -- fake clock, seconds
function Mock.now(): number
	return T
end
function Mock.advance(dt: number)
	T += dt
end

-- Signals ----------------------------------------------------------------------
local function signal()
	local s = { fns = {} :: { any } }
	function s.Connect(self: any, fn: any)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s.Fire(self: any, ...: any)
		for _, fn in self.fns do
			fn(...)
		end
	end
	return s
end
Mock.signal = signal

-- Vector3 / CFrame ---------------------------------------------------------------
local V3 = {}
local V3MT = {}
local function v3(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, V3MT)
end
V3MT.__add = function(a: any, b: any)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3MT.__sub = function(a: any, b: any)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.new = function(x: number?, y: number?, z: number?)
	return v3(x or 0, y or 0, z or 0)
end
V3.zero = v3(0, 0, 0)
V3.zAxis = v3(0, 0, 1)
Mock.Vector3 = V3
local CF = {
	new = function(p: any)
		return { Position = p }
	end,
	lookAt = function(p: any, _at: any)
		return { Position = p }
	end,
}

-- Instances --------------------------------------------------------------------
local Inst = {}
local InstMT = {}
InstMT.__index = function(self: any, k: string)
	local m = Inst[k]
	if m then
		return m
	end
	local p = rawget(self, "_p")
	if p[k] ~= nil then
		return p[k]
	end
	for _, c in rawget(self, "_c") do
		if c.Name == k then
			return c
		end
	end
	error(`{k} is not a valid member of {p.Name}`)
end
InstMT.__newindex = function(self: any, k: string, v: any)
	local p = rawget(self, "_p")
	if k == "Parent" then
		local old = p.Parent
		if old then
			local list = rawget(old, "_c")
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		p.Parent = v
		if v then
			table.insert(rawget(v, "_c"), self)
		end
	else
		p[k] = v
	end
end

local function new(className: string, name: string?, props: { [string]: any }?): any
	local o = setmetatable(
		{ _p = { ClassName = className, Name = name or className, Parent = nil }, _c = {}, _a = {} },
		InstMT
	)
	for k, v in props or {} do
		(o :: any)[k] = v
	end
	if className == "RemoteEvent" or className == "UnreliableRemoteEvent" then
		o.OnServerEvent = signal()
	end
	return o
end
Mock.new = new

function Inst.FindFirstChild(self: any, name: string)
	for _, c in rawget(self, "_c") do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function Inst.WaitForChild(self: any, name: string)
	return Inst.FindFirstChild(self, name) or error("WaitForChild " .. name)
end
function Inst.FindFirstChildOfClass(self: any, cls: string)
	for _, c in rawget(self, "_c") do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst.GetChildren(self: any)
	return table.clone(rawget(self, "_c"))
end
function Inst.IsA(self: any, cls: string)
	local c = self.ClassName
	return c == cls or cls == "Instance" or (cls == "BasePart" and c == "Part")
end
function Inst.GetAttribute(self: any, k: string)
	return rawget(self, "_a")[k]
end
function Inst.SetAttribute(self: any, k: string, v: any)
	rawget(self, "_a")[k] = v
end
function Inst.GetFullName(self: any)
	return self.Name
end
function Inst.PivotTo(self: any, cf: any)
	self._pivot = cf
end
function Inst.Move(_self: any, _v: any) end
function Inst.GetJoinData(self: any)
	return self._join
end
function Inst.IsFriendsWithAsync(self: any, id: number)
	return self._friends[id] == true
end
function Inst.SetTeleportData(self: any, data: any)
	self._teleportData = data
end
-- Remotes record what the server sends.
function Inst.FireClient(self: any, player: any, ...: any)
	table.insert(player._inbox, { remote = self.Name, args = table.pack(...) })
end
function Inst.GetServerTimeNow(_self: any)
	return T
end

-- World: arenas, lobby, services --------------------------------------------------
local function part(name: string, pos: any, size: any): any
	return new("Part", name, { Position = pos, Size = size, Anchored = false })
end

local function arena(name: string, mode: string, stands: number, x: number): any
	local m = new("Model", name)
	m:SetAttribute("Mode", mode)
	m:SetAttribute("GridW", if mode == "duel" then 16 else 24)
	m:SetAttribute("GridH", if mode == "duel" then 14 else 20)
	for i = 1, stands do
		part(`Stand{i}`, V3.new(x + i * 10, 200, 0), V3.new(4, 1, 4)).Parent = m
	end
	return m
end

function Mock.world(): any
	local workspace = new("Workspace", "Workspace")
	local arenas = new("Folder", "Arenas")
	arenas.Parent = workspace
	local list = {}
	for i, a in { { "Duel1", "duel", 2 }, { "Duel2", "duel", 2 }, { "Duel3", "duel", 2 }, { "FFA1", "ffa", 4 } } do
		local m = arena(a[1], a[2], a[3], i * 300)
		m.Parent = arenas
		table.insert(list, m)
	end
	local lobby = new("Folder", "Lobby")
	lobby.Parent = workspace
	part("Pad", V3.new(0, 10, 0), V3.new(20, 1, 20)).Parent = lobby

	local ReplicatedStorage = new("ReplicatedStorage", "ReplicatedStorage")
	-- ReplicatedStorage.Shared.X resolves to src/shared/X for require()
	local function pathProxy(path: string): any
		return setmetatable({ __modpath = path }, {
			__index = function(_, k)
				return pathProxy(path .. "/" .. k)
			end,
		})
	end
	rawget(ReplicatedStorage, "_p").Shared = pathProxy("src/shared")

	local Players = new("Players", "Players")
	Players.PlayerAdded = signal()
	Players.PlayerRemoving = signal()
	function Players.GetPlayers(self: any)
		return self:GetChildren()
	end

	local analytics = { steps = {} :: { any }, custom = {} :: { any } }
	local AnalyticsService = new("AnalyticsService")
	function AnalyticsService.LogOnboardingFunnelStepEvent(_self: any, player: any, n: number, name: string)
		table.insert(analytics.steps, { player = player.Name, n = n, name = name })
	end
	function AnalyticsService.LogCustomEvent(_self: any, player: any, name: string, value: number, fields: any)
		table.insert(analytics.custom, { player = player.Name, name = name, value = value, fields = fields })
	end

	local RunService = new("RunService")
	RunService.Heartbeat = signal()
	function RunService.IsServer(_self: any)
		return true
	end

	local CollectionService = new("CollectionService")
	function CollectionService.GetTagged(_self: any, tag: string)
		return if tag == "Arena" then table.clone(list) else {}
	end
	function CollectionService.GetInstanceAddedSignal(_self: any)
		return signal()
	end
	function CollectionService.GetInstanceRemovedSignal(_self: any)
		return signal()
	end

	local ServerScriptService = new("ServerScriptService")
	local HttpService = new("HttpService")
	function HttpService.JSONDecode(_self: any, s: string)
		return (require("@lune/serde") :: any).decode("json", s)
	end
	function HttpService.JSONEncode(_self: any, v: any)
		return (require("@lune/serde") :: any).encode("json", v)
	end
	local teleports = {} :: { any }
	local TeleportService = new("TeleportService")
	TeleportService.TeleportInitFailed = signal()
	function TeleportService.TeleportAsync(_self: any, placeId: number, players: { any }, options: any)
		table.insert(teleports, { placeId = placeId, players = players, options = options })
	end
	local services = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		RunService = RunService,
		ServerScriptService = ServerScriptService,
		CollectionService = CollectionService,
		AnalyticsService = AnalyticsService,
		HttpService = HttpService,
		TeleportService = TeleportService,
	}
	local game = new("DataModel", "game", { PlaceId = 96446158283661, JobId = "job-here" })
	function game.GetService(_self: any, name: string)
		return services[name] or error("no service " .. name)
	end
	return {
		game = game,
		workspace = workspace,
		services = services,
		analytics = analytics,
		arenas = list,
		teleports = teleports,
	}
end

function Mock.player(_world: any, id: number, name: string): any
	local p = new("Player", name, { UserId = id, DisplayName = name })
	rawget(p, "_p")._inbox = {}
	p.CharacterAdded = signal()
	-- join data of an invite link or teleport; friends of this player (by UserId)
	rawget(p, "_p")._join = {}
	rawget(p, "_p")._friends = {}
	local ch = new("Model", name .. "Char")
	part("HumanoidRootPart", V3.zero, V3.new(2, 2, 1)).Parent = ch
	new("Humanoid", "Humanoid", { HipHeight = 2 }).Parent = ch
	p.Character = ch
	return p
end

-- Module loader -----------------------------------------------------------------
local function exists(p: string): boolean
	return fs.isFile(p)
end

local function fileOf(p: string): string
	if exists(p .. ".luau") then
		return p .. ".luau"
	elseif exists(p .. "/init.luau") then
		return p .. "/init.luau"
	elseif exists(p .. "/init.server.luau") then
		return p .. "/init.server.luau"
	end
	error("cannot resolve " .. p)
end

local function dirname(p: string): string
	return (string.match(p, "^(.*)/[^/]*$") or ".")
end

local function normalize(p: string): string
	local out = {}
	for part in string.gmatch(p, "[^/]+") do
		if part == ".." then
			table.remove(out)
		elseif part ~= "." then
			table.insert(out, part)
		end
	end
	return table.concat(out, "/")
end

local function isInit(file: string): boolean
	return string.match(file, "/init%.luau$") ~= nil or string.match(file, "/init%.server%.luau$") ~= nil
end

function Mock.loader(world: any, logs: { string }, warns: { string })
	local cache: { [string]: any } = {}
	local load: (string) -> any
	local base = getfenv(0)
	local fakeOs = setmetatable({ clock = Mock.now }, { __index = os })
	local task = {
		spawn = function(f: any, ...: any)
			f(...)
		end,
		defer = function(f: any, ...: any)
			f(...)
		end,
		-- delays run at once (the flow tests do not wait for them)
		delay = function(_t: number, f: any, ...: any)
			f(...)
		end,
	}
	local Enum = setmetatable({}, {
		__index = function(_, a)
			return setmetatable({}, {
				__index = function(_, b)
					return { Name = b, EnumType = a }
				end,
			})
		end,
	})
	local function envFor(file: string): any
		local function req(arg: any): any
			local path
			if type(arg) == "table" then
				path = arg.__modpath
			else
				local selfDir = if isInit(file) then dirname(file) else string.gsub(file, "%.luau$", "")
				local parent = if isInit(file) then dirname(dirname(file)) else dirname(file)
				if string.sub(arg, 1, 6) == "@self/" then
					path = selfDir .. "/" .. string.sub(arg, 7)
				elseif string.sub(arg, 1, 2) == "./" or string.sub(arg, 1, 3) == "../" then
					path = parent .. "/" .. arg
				else
					error("require " .. tostring(arg))
				end
			end
			return load(fileOf(normalize(path)))
		end
		return setmetatable({
			require = req,
			game = world.game,
			workspace = world.workspace,
			Enum = Enum,
			Vector3 = V3,
			CFrame = CF,
			Instance = { new = new },
			os = fakeOs,
			task = task,
			print = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(logs, table.concat(parts, " "))
			end,
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(warns, table.concat(parts, " "))
			end,
		}, { __index = base })
	end
	load = function(file: string): any
		if cache[file] ~= nil then
			return cache[file]
		end
		local src = fs.readFile(file)
		local f = luau.load(src, { debugName = file, environment = envFor(file) })
		local v = f()
		cache[file] = if v == nil then true else v
		return v
	end
	return load
end

return Mock
