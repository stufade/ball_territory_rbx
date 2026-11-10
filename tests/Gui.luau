--!strict
--# selene: allow(shadowing, incorrect_standard_library_use, roblox_manual_fromscale_or_fromoffset)
-- Minimal Roblox GUI stand-in for running src/client/UI modules in lune (tests/ui): Instances with children,
-- properties and signals, UDim2 / Vector2 / Color3 / sequences, TweenService (tweens finish at once), GuiService,
-- ReplicatedStorage.Shared mapped to src/shared. Layout: Gui.rect(o) adds Offset positions and anchors up the tree
-- (scale parts use the parent's size), enough for the plaza widgets built in canvas px.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Gui = {}

local T = 0
function Gui.advance(dt: number)
	T += dt
end

local function signal()
	local s = { fns = {} :: { any } }
	function s.Connect(self: any, fn: any)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s.Fire(self: any, ...: any)
		for _, fn in table.clone(self.fns) do
			fn(...)
		end
	end
	return s
end
Gui.signal = signal

-- Datatypes -------------------------------------------------------------------------------------------------------
local Vector2 = {}
Vector2.__index = Vector2
function Vector2.new(x: number?, y: number?): any
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end
Vector2.__eq = function(a: any, b: any)
	return a.X == b.X and a.Y == b.Y
end
Vector2.zero = Vector2.new(0, 0)

local UDim = {}
function UDim.new(s: number?, o: number?): any
	return { Scale = s or 0, Offset = o or 0 }
end

local UDim2 = {}
function UDim2.new(xs: number?, xo: number?, ys: number?, yo: number?): any
	return { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }
end
function UDim2.fromOffset(x: number?, y: number?): any
	return UDim2.new(0, x, 0, y)
end
function UDim2.fromScale(x: number?, y: number?): any
	return UDim2.new(x, 0, y, 0)
end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r: number?, g: number?, b: number?): any
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r: number, g: number, b: number): any
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHex(h: string): any
	h = h:gsub("#", "")
	return Color3.fromRGB(
		tonumber(h:sub(1, 2), 16) :: number,
		tonumber(h:sub(3, 4), 16) :: number,
		tonumber(h:sub(5, 6), 16) :: number
	)
end
function Color3.Lerp(a: any, b: any, t: number): any
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function ctor(): any
	return {
		new = function(...)
			return { ... }
		end,
	}
end

local Enum = setmetatable({}, {
	__index = function(_, a)
		return setmetatable({}, {
			__index = function(_, b)
				return { Name = b, EnumType = a }
			end,
		})
	end,
})

-- Instances -------------------------------------------------------------------------------------------------------
local Inst = {}
local MT = {}
local SIGNALS = { Activated = true, InputBegan = true, InputEnded = true, MouseButton1Click = true, Event = true }

local function new(class: string): any
	local o = { _p = { ClassName = class, Name = class, Visible = true, ZIndex = 1 }, _c = {}, _a = {} }
	return setmetatable(o, MT)
end

MT.__index = function(self: any, k: string)
	local m = Inst[k]
	if m then
		return m
	end
	local p = rawget(self, "_p")
	local v = p[k]
	if v ~= nil then
		return v
	end
	if SIGNALS[k] then
		local s = signal()
		p[k] = s
		return s
	end
	for _, c in rawget(self, "_c") do
		if c._p.Name == k then
			return c
		end
	end
	return nil
end
MT.__newindex = function(self: any, k: string, v: any)
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
		if v then
			table.insert(rawget(v, "_c"), self)
		end
	end
	p[k] = v
end

function Inst.GetChildren(self: any)
	return table.clone(rawget(self, "_c"))
end
function Inst.GetDescendants(self: any)
	local out = {}
	local function walk(o: any)
		for _, c in rawget(o, "_c") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Inst.ClearAllChildren(self: any)
	for _, c in table.clone(rawget(self, "_c")) do
		c:Destroy()
	end
end
function Inst.Destroy(self: any)
	self.Parent = nil
	for _, c in table.clone(rawget(self, "_c")) do
		c:Destroy()
	end
end
function Inst.FindFirstChild(self: any, name: string, deep: boolean?)
	for _, c in rawget(self, "_c") do
		if c._p.Name == name then
			return c
		end
	end
	if deep then
		for _, c in rawget(self, "_c") do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst.FindFirstChildOfClass(self: any, cls: string)
	for _, c in rawget(self, "_c") do
		if c._p.ClassName == cls then
			return c
		end
	end
	return nil
end
function Inst.IsA(self: any, cls: string)
	return self._p.ClassName == cls
end
function Inst.SetAttribute(self: any, k: string, v: any)
	rawget(self, "_a")[k] = v
end
function Inst.GetAttribute(self: any, k: string)
	return rawget(self, "_a")[k]
end
function Inst.GetPropertyChangedSignal(_self: any, _k: string)
	return signal()
end
function Inst.GetAttributeChangedSignal(_self: any, _k: string)
	return signal()
end

-- Canvas rect of a GuiObject: offsets and scales of Position and Size up to the root, with AnchorPoint.
function Gui.rect(o: any): (number, number, number, number)
	local p = o._p.Parent
	local px, py, pw, ph = 0, 0, 960, 540
	if p and p._p.Size then
		px, py, pw, ph = Gui.rect(p)
	elseif p and p._p.ClassName ~= "Frame" then
		px, py, pw, ph = 0, 0, Gui.canvas.X, Gui.canvas.Y
	end
	local s = o._p.Size or UDim2.new(0, 0, 0, 0)
	local w = s.X.Scale * pw + s.X.Offset
	local h = s.Y.Scale * ph + s.Y.Offset
	local pos = o._p.Position or UDim2.new(0, 0, 0, 0)
	local a = o._p.AnchorPoint or Vector2.new(0, 0)
	local x = px + pos.X.Scale * pw + pos.X.Offset - a.X * w
	local y = py + pos.Y.Scale * ph + pos.Y.Offset - a.Y * h
	return x, y, w, h
end
Gui.canvas = Vector2.new(960, 540)

-- Every visible TextLabel text under o.
function Gui.texts(o: any): { string }
	local out = {}
	for _, d in o:GetDescendants() do
		if d._p.ClassName == "TextLabel" and d._p.Text ~= nil then
			table.insert(out, d._p.Text)
		end
	end
	return out
end

-- World and loader --------------------------------------------------------------------------------------------------
function Gui.world(): any
	local services: { [string]: any } = {}
	local game = new("DataModel")
	local function service(name: string): any
		local s = services[name]
		if not s then
			s = new(name)
			services[name] = s
		end
		return s
	end
	local tween = service("TweenService")
	function tween.Create(_self: any, obj: any, _info: any, goal: any)
		return {
			Play = function()
				for k, v in goal do
					obj[k] = v
				end
			end,
			Cancel = function() end,
			Completed = signal(),
		}
	end
	service("GuiService").ReducedMotionEnabled = false
	local function shared(path: string): any
		local o = setmetatable({ __modpath = path }, {
			__index = function(t, k)
				if k == "WaitForChild" or k == "FindFirstChild" then
					return function(_, name)
						return shared(path .. "/" .. name)
					end
				end
				return shared(rawget(t, "__modpath") .. "/" .. k)
			end,
		})
		return o
	end
	local rs = service("ReplicatedStorage")
	function rs.WaitForChild(_self: any, name: string)
		return if name == "Shared" then shared("src/shared") else shared("src/shared/" .. name)
	end
	local players = service("Players")
	players.LocalPlayer = new("Player")
	players.LocalPlayer.UserId = 1
	function game.GetService(_self: any, name: string)
		return service(name)
	end
	local workspace = new("Workspace")
	function workspace.GetServerTimeNow(_self: any)
		return T
	end
	return { game = game, workspace = workspace, services = services }
end

local function exists(p: string): boolean
	return fs.isFile(p)
end

local function fileOf(p: string): string
	if exists(p .. ".luau") then
		return p .. ".luau"
	elseif exists(p .. "/init.luau") then
		return p .. "/init.luau"
	end
	error("cannot resolve " .. p)
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

local function dirname(p: string): string
	return (string.match(p, "^(.*)/[^/]*$") or ".")
end

function Gui.loader(world: any): (string) -> any
	local cache: { [string]: any } = {}
	local load: (string) -> any
	local base = getfenv(0)
	local fakeOs = setmetatable({
		clock = function()
			return T
		end,
	}, { __index = os })
	local task = {
		spawn = function(f: any, ...: any)
			f(...)
		end,
		defer = function(f: any, ...: any)
			f(...)
		end,
		delay = function() end,
		wait = function() end,
	}
	local function envFor(file: string): any
		local init = string.match(file, "/init%.luau$") ~= nil
		local function req(arg: any): any
			local path
			if type(arg) == "table" then
				path = rawget(arg, "__modpath")
			else
				local selfDir = if init then dirname(file) else string.gsub(file, "%.luau$", "")
				local parent = if init then dirname(dirname(file)) else dirname(file)
				if string.sub(arg, 1, 6) == "@self/" then
					path = selfDir .. "/" .. string.sub(arg, 7)
				else
					path = parent .. "/" .. arg
				end
			end
			return load(fileOf(normalize(path)))
		end
		return setmetatable({
			require = req,
			game = world.game,
			workspace = world.workspace,
			Enum = Enum,
			Vector2 = Vector2,
			UDim = UDim,
			UDim2 = UDim2,
			Color3 = Color3,
			ColorSequence = ctor(),
			ColorSequenceKeypoint = ctor(),
			NumberSequence = ctor(),
			NumberSequenceKeypoint = ctor(),
			NumberRange = ctor(),
			TweenInfo = ctor(),
			Font = ctor(),
			Instance = { new = new },
			os = fakeOs,
			task = task,
			print = function() end,
		}, { __index = base })
	end
	load = function(file: string): any
		if cache[file] ~= nil then
			return cache[file]
		end
		local f = luau.load(fs.readFile(file), { debugName = file, environment = envFor(file) })
		local v = f()
		cache[file] = if v == nil then true else v
		return v
	end
	return load
end

Gui.new = new

return Gui
