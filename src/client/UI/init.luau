--!strict
-- Client UI entry: ScreenGui with menus (by State.ph) and the match HUD. Call UI.start() once from the client bootstrap.
-- Layout is designed on a 960x540 canvas that is scaled to the screen (phone landscape first). Spec: docs/ui.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"))
local Hud = require("@self/Hud")
local Menus = require("@self/Menus")
local Theme = require("@self/Theme")

local UI = {}

local DESIGN_W, DESIGN_H = 960, 540

local started = false

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
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Canvas keeps a 960x540 design area at least; UIScale fits it to the real screen.
	local canvas = Instance.new("Frame")
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = canvas
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local s = math.min(size.X / DESIGN_W, size.Y / DESIGN_H)
		scale.Scale = s
		canvas.Size = UDim2.fromOffset(size.X / s, size.Y / s)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local menu = Theme.frame(canvas, UDim2.fromScale(1, 1), nil, Theme.BG)
	menu.Name = "Menu"
	menu.Visible = false

	local ctx: Menus.Ctx = {
		act = function(verb, arg)
			Remotes.Action:FireServer(verb, arg)
		end,
		timeLeft = function(endsAt)
			return if endsAt then math.max(0, endsAt - workspace:GetServerTimeNow()) else 0
		end,
		tickers = {},
		seats = {},
		you = nil,
		mySide = 0,
		score = { 0, 0 },
		lastEnd = nil,
	}

	local hud: Hud.Hud? = nil
	local matchId = -1
	local dec = Net.Snap.newDecoder()
	local lost: { { number } } = { {}, {} }

	local function clearHud()
		if hud then
			Hud.destroy(hud)
			hud = nil
		end
		matchId = -1
	end

	Remotes.State.OnClientEvent:Connect(function(st: Net.State)
		if typeof(st) ~= "table" then
			return
		end
		table.clear(ctx.tickers)
		menu:ClearAllChildren()
		if st.ph == "match" then
			menu.Visible = false
			return
		end
		clearHud()
		if st.ph == "queue" or st.ph == "lobby" then
			ctx.score = { 0, 0 }
			lost = { {}, {} }
			ctx.lastEnd = nil
		elseif st.ph == "choose" and st.lost then
			lost = st.lost
		end
		menu.Visible = true
		Menus.build(menu, st, ctx)
	end)

	Remotes.Match.OnClientEvent:Connect(function(kind: string, data: any)
		if typeof(data) ~= "table" then
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
			hud = Hud.new(canvas, data, lost, function(k, dx, dy)
				Remotes.Input:FireServer(k, dx, dy)
			end)
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
				lost = data.lost
				if hud then
					Hud.setLost(hud, lost)
				end
			end
			if hud then
				local w = if data.win == ctx.mySide then "ROUND WON" elseif data.win < 0 then "DRAW" else "ROUND LOST"
				Hud.showBanner(hud, w, 2.5)
			end
		elseif kind == Net.MatchKind.finish then
			ctx.lastEnd = data
		end
	end)

	Remotes.Snap.OnClientEvent:Connect(function(buf: buffer)
		local f = Net.Snap.decode(dec, buf)
		if f and hud then
			Hud.onFrame(hud, f)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for _, t in ctx.tickers do
			t()
		end
	end)
end

return UI
