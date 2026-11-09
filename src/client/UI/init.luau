--!strict
-- Client UI entry: ScreenGui with menus (by State.ph) and the match HUD. Call UI.start() once from the client bootstrap.
-- Layout is designed on a 960x540 canvas that is scaled to the screen (phone landscape first). Spec: docs/ui.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))
local Screen = require("./Screen")
local Hud = require("@self/Hud")
local Menus = require("@self/Menus")
local Plaza = require("@self/Plaza")
local Theme = require("@self/Theme")

local UI = {}

local started = false

-- Debug emulation overlay: black bars outside the band and grey stand-ins of the Roblox topbar buttons.
local function emulationOverlay(player: Player): () -> ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BTEmulate"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")
	return function()
		gui:ClearAllChildren()
		local e = Screen.emulated()
		if not e then
			return
		end
		local off, size = Screen.band()
		local k = Screen.k()
		local function bar(x: number, y: number, w: number, h: number)
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.BackgroundColor3 = Color3.new(0, 0, 0)
			f.Position = UDim2.fromOffset(x, y)
			f.Size = UDim2.fromOffset(w, h)
			f.Parent = gui
		end
		local vp = (workspace.CurrentCamera :: Camera).ViewportSize
		bar(0, 0, vp.X, off.Y)
		bar(0, off.Y + size.Y, vp.X, vp.Y - off.Y - size.Y)
		bar(0, 0, off.X, vp.Y)
		bar(off.X + size.X, 0, vp.X - off.X - size.X, vp.Y)
		for _, r in { { 70, 39 }, { 116, 84 }, { 209, 38 } } do
			local b = Instance.new("Frame")
			b.BackgroundColor3 = Color3.fromRGB(25, 27, 32)
			b.BackgroundTransparency = 0.2
			b.Position = UDim2.fromOffset(off.X + r[1] * k, off.Y + 11 * k)
			b.Size = UDim2.fromOffset(r[2] * k, 38 * k)
			Theme.round(b, 999)
			b.Parent = gui
		end
	end
end

function UI.start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BallUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- children always over their parent (overlays with ZIndex)
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Band (the whole screen, or the emulated phone) holds the canvas; UIScale fits 960x540 design px into it.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Parent = gui
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = band
	local scale = Instance.new("UIScale")
	scale.Parent = canvas

	local ctx: Menus.Ctx = {
		act = function(verb, arg)
			Remotes.Action:FireServer(verb, arg)
		end,
		timeLeft = function(endsAt)
			return if endsAt then math.max(0, endsAt - workspace:GetServerTimeNow()) else 0
		end,
		tickers = {},
		frames = {},
		seats = {},
		you = nil,
		mySide = 0,
		score = { 0, 0 },
		rounds = 0,
		lastEnd = nil,
		lastRound = nil,
		teams = { {}, {} },
		lost = { {}, {} },
		names = {},
		topbar = Vector2.new(354, 80),
		canvas = Vector2.new(960, 540),
	}

	local overlay = emulationOverlay(player)
	local hud: Hud.Hud? = nil
	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.fromScale(1, 1)
	menu.Visible = false
	menu.Parent = canvas
	local lastState: Net.State? = nil
	-- lobby and search: compact buttons over the running avatar (M1.6), not a full-screen menu
	local plaza = Plaza.new(canvas, ctx :: any)

	local function rebuild()
		table.clear(ctx.tickers)
		table.clear(ctx.frames)
		menu:ClearAllChildren()
		local st = lastState
		if st then
			Plaza.setState(plaza, st)
		end
		if st and st.ph ~= "match" and st.ph ~= "lobby" and st.ph ~= "queue" then
			menu.Visible = true
			Menus.build(menu, st, ctx)
		else
			menu.Visible = false
		end
	end

	local function fit()
		local off, size
		if Screen.emulated() then
			off, size = Screen.band()
		else
			off, size = Vector2.zero, gui.AbsoluteSize
		end
		if size.X < 1 or size.Y < 1 then
			return
		end
		band.Position = UDim2.fromOffset(off.X, off.Y)
		band.Size = UDim2.fromOffset(size.X, size.Y)
		local s = math.min(size.X / Screen.DESIGN_W, size.Y / Screen.DESIGN_H)
		scale.Scale = s
		ctx.canvas = Vector2.new(size.X / s, size.Y / s)
		canvas.Size = UDim2.fromOffset(ctx.canvas.X, ctx.canvas.Y)
		-- topbar in design px; with safe insets the canvas may start right of the screen edge
		local tb = Screen.topbar()
		ctx.topbar = Vector2.new(math.max(0, tb.X - gui.AbsolutePosition.X) / s + 8, tb.Y / s + 6)
		overlay()
		if hud then
			Hud.layout(hud, ctx.canvas, ctx.topbar)
		end
	end
	local pending = false
	local function refit()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			local before = ctx.canvas
			fit()
			if before ~= ctx.canvas and menu.Visible then
				rebuild()
			elseif before ~= ctx.canvas then
				Plaza.render(plaza)
			end
		end)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	Screen.changed:Connect(refit)
	fit()

	local matchId = -1
	local dec = Net.Snap.newDecoder()

	local function clearHud()
		if hud then
			Hud.destroy(hud)
			hud = nil
		end
		matchId = -1
	end

	local held: Net.State? = nil
	local function onState(st: Net.State)
		if typeof(st) ~= "table" then
			return
		end
		-- debug: workspace attribute BTHold keeps the current screen (for screenshots of short screens)
		if workspace:GetAttribute("BTHold") == true then
			held = st
			return
		end
		lastState = st
		if st.ph == "match" then
			Plaza.setState(plaza, st)
			table.clear(ctx.tickers)
			table.clear(ctx.frames)
			menu:ClearAllChildren()
			menu.Visible = false
			return
		end
		-- the result screen draws over the arena; everything else closes the HUD
		clearHud()
		if st.ph == "queue" or st.ph == "lobby" then
			ctx.score = { 0, 0 }
			ctx.rounds = 0
			ctx.lost = { {}, {} }
			ctx.teams = { {}, {} }
			ctx.lastEnd = nil
			ctx.lastRound = nil
		end
		if st.teams then
			ctx.teams = st.teams
		end
		if st.lost then
			ctx.lost = st.lost
		end
		if st.names then
			ctx.names = st.names
		end
		rebuild()
	end
	Remotes.State.OnClientEvent:Connect(onState)
	-- debug: BallUI.Inject:Fire(st) shows a made-up State locally (screenshots of every screen, docs/ui.md)
	local inject = Instance.new("BindableEvent")
	inject.Name = "Inject"
	inject.Parent = gui
	local onMatch: (kind: string, data: any) -> ()
	inject.Event:Connect(function(kind: string, data: any)
		if kind == "State" then
			local hold = workspace:GetAttribute("BTHold")
			workspace:SetAttribute("BTHold", nil)
			onState(data)
			workspace:SetAttribute("BTHold", hold)
		elseif typeof(data) == "table" then
			data.id = data.id or matchId
			onMatch(kind, data)
		end
	end)
	workspace:GetAttributeChangedSignal("BTHold"):Connect(function()
		local st = held
		if st and workspace:GetAttribute("BTHold") ~= true then
			held = nil
			onState(st)
		end
	end)

	function onMatch(kind: string, data: any)
		-- a match watched from the plaza has no HUD (Render draws its board)
		if typeof(data) ~= "table" or data.view == true or kind == Net.MatchKind.unview then
			return
		end
		if kind == Net.MatchKind.start then
			clearHud()
			matchId = data.id
			dec = Net.Snap.newDecoder()
			Net.Snap.applyKey(dec, data.key)
			ctx.you = data.you
			ctx.seats = {}
			for _, seat in data.seats do
				ctx.seats[seat.e] = seat
				if seat.e == data.you then
					ctx.mySide = seat.side
				end
			end
			menu.Visible = false
			local h = Hud.new(canvas, data, ctx.lost, ctx.score, function(k, dx, dy)
				Remotes.Input:FireServer(k, dx, dy)
			end)
			hud = h
			Hud.layout(h, ctx.canvas, ctx.topbar)
			return
		end
		if data.id ~= matchId then
			return
		end
		if kind == Net.MatchKind.hint and hud then
			Hud.showHint(hud, data.k)
		elseif kind == Net.MatchKind.round then
			local sc: { number }? = data.score
			if sc then
				ctx.score = { sc[1] or 0, sc[2] or 0 }
			end
			if data.lost then
				ctx.lost = data.lost
			end
			ctx.lastRound = data
			ctx.rounds += 1
			if hud then
				Hud.setLost(hud, ctx.lost)
				Hud.roundEnd(hud, data, ctx)
			end
		elseif kind == Net.MatchKind.finish then
			ctx.lastEnd = data
		end
	end
	-- debug hold: the held screen must not be replaced by the next round; replay the events on release
	local heldMatch: { { kind: string, data: any } } = {}
	Remotes.Match.OnClientEvent:Connect(function(kind: string, data: any)
		if workspace:GetAttribute("BTHold") == true then
			table.insert(heldMatch, { kind = kind, data = data })
		else
			onMatch(kind, data)
		end
	end)
	workspace:GetAttributeChangedSignal("BTHold"):Connect(function()
		if workspace:GetAttribute("BTHold") ~= true then
			local list = heldMatch
			heldMatch = {}
			for _, m in list do
				onMatch(m.kind, m.data)
			end
		end
	end)

	Remotes.Party.OnClientEvent:Connect(function(v: Net.PartyView)
		if typeof(v) == "table" and typeof(v.members) == "table" and typeof(v.invites) == "table" then
			Plaza.setParty(plaza, v)
		end
	end)

	Remotes.Snap.OnClientEvent:Connect(function(buf: buffer)
		local f = Net.Snap.decode(dec, buf)
		if f and hud then
			Hud.onFrame(hud, f)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if hud then
			Hud.step(hud, dt)
		end
		for _, f in ctx.frames do
			f(dt)
		end
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for _, t in ctx.tickers do
			t()
		end
		Plaza.step(plaza)
	end)
end

return UI
