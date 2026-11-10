--!strict
-- Plaza HUD (M1.6): small buttons at the right edge instead of the full-screen lobby, so the avatar can run (stick
-- bottom left, jump bottom right stay free). PLAY opens DUEL / 4 PLAYERS (in a party: the host's party modes),
-- PARTY creates or opens the party (PartyPanel). Search is a small pill at the top. Spec: docs/ui.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local PartyPanel = require("./PartyPanel")
local Theme = require("./Theme")

local V2 = Vector2.new
local RIGHT = V2(1, 0)
local TOP_MID = V2(0.5, 0)

export type Ctx = {
	act: (verb: string, arg: number?) -> (),
	canvas: Vector2,
	topbar: Vector2,
}

export type Plaza = {
	root: Frame,
	ctx: Ctx,
	st: Net.State?,
	party: Net.PartyView?,
	playOpen: boolean,
	panel: PartyPanel.Panel,
	tick: (() -> ())?,
	note: string?,
	noteUntil: number,
	-- T2.2: PLAY was pressed once: no more glow on this client
	pressed: boolean,
}

local Plaza = {}

local function inParty(p: Plaza): boolean
	local v = p.party
	return v ~= nil and v.id ~= nil and #v.members >= 2
end

local function isHost(p: Plaza): boolean
	local v = p.party
	return v ~= nil and v.id ~= nil and v.host == game:GetService("Players").LocalPlayer.UserId
end

local function small(parent: Instance, text: string, w: number, h: number, x: number, y: number, color: Color3)
	return Theme.button(parent, text, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), color, nil, 28, RIGHT)
end

-- After the tutorial (State lobby glow = "play"): PLAY pulses inside a yellow ring and a hand points at it.
local function glow(layer: Frame, play: TextButton, x: number, y: number)
	local reduced = Theme.reduced()
	local ring = Theme.frame(layer, UDim2.fromOffset(196, 98), UDim2.fromOffset(x + 10, y - 10), Theme.YELLOW, RIGHT)
	ring.BackgroundTransparency = 1
	Theme.round(ring, 18)
	Theme.stroke(ring, 6, Theme.YELLOW)
	local hand = Theme.text(layer, "👉", 84, UDim2.fromOffset(96, 96), UDim2.fromOffset(x - 186, y + 39), {
		anchor = V2(1, 0.5),
		stroke = 0,
	})
	if reduced then
		return
	end
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	for _, o in { ring :: GuiObject, play } do
		local s = Instance.new("UIScale")
		s.Parent = o
		TweenService:Create(s, info, { Scale = 1.08 }):Play()
	end
	TweenService:Create(hand, info, { Position = UDim2.fromOffset(x - 172, y + 39) }):Play()
end

-- PLAY and its choices, PARTY under it (right edge, above the jump button).
local function buttons(p: Plaza, layer: Frame)
	local cv, act = p.ctx.canvas, p.ctx.act
	local x = cv.X - 14
	local y = math.max(p.ctx.topbar.Y, 96)
	local party = inParty(p)
	local host = isHost(p)
	local play =
		Theme.button(layer, "PLAY", UDim2.fromOffset(176, 78), UDim2.fromOffset(x, y), Theme.GO, Theme.INK, 44, RIGHT)
	local st = p.st
	if st and st.glow == "play" and not p.playOpen and not p.pressed then
		glow(layer, play, x, y)
		play.Name = "PlayLit"
	end
	play.Activated:Connect(function()
		p.pressed = true
		p.playOpen = not p.playOpen
		Plaza.render(p)
	end)
	if party and not host then
		local l = play:FindFirstChild("Label") :: TextLabel?
		if l then
			l.Text = "HOST STARTS"
		end
		play.BackgroundColor3 = Theme.PANEL_HI
		play.Active = false
		p.playOpen = false
	end
	if p.playOpen then
		local cx = x - 176 - 10
		local duelText = if party then "DUEL EACH OTHER" else "DUEL"
		local ffaText = if party then "4 PLAYERS TOGETHER" else "4 PLAYERS"
		local duel = small(layer, duelText, 230, 62, cx, y - 24, Theme.GO)
		local ffa = small(layer, ffaText, 230, 62, cx, y + 46, Theme.PURPLE)
		local two = not party or #(p.party :: Net.PartyView).members == 2
		if not two then
			duel.BackgroundColor3 = Theme.PANEL_HI
			duel.Active = false
		end
		Theme.pop(duel, 0, 0.6)
		Theme.pop(ffa, 0.05, 0.6)
		duel.Activated:Connect(function()
			if two then
				p.playOpen = false
				act(if party then Net.Action.pplay else Net.Action.queue, Net.Mode.duel)
			end
		end)
		ffa.Activated:Connect(function()
			p.playOpen = false
			act(if party then Net.Action.pplay else Net.Action.queue, Net.Mode.ffa)
		end)
	end
	local v = p.party
	local n = if v and v.id then #v.members else 0
	local partyBtn = small(layer, if n > 0 then `PARTY {n}/4` else "PARTY +", 176, 56, x, y + 88, Theme.PURPLE)
	local how = small(layer, "HOW TO PLAY", 176, 50, x, y + 152, Theme.SLOT)
	how.Activated:Connect(function()
		p.playOpen = false
		act(Net.Action.tutor)
	end)
	partyBtn.Activated:Connect(function()
		if n == 0 then
			act(Net.Action.pcreate)
			PartyPanel.open(p.panel, true)
		else
			PartyPanel.open(p.panel, not p.panel.open)
		end
	end)
end

-- "SEARCHING... 2 PLAYERS · BOTS IN 4s  [CANCEL]" at the top middle.
local function pill(p: Plaza, layer: Frame, st: Net.State)
	local cv = p.ctx.canvas
	-- centred, but never over the Roblox topbar buttons at the top left
	local cx = math.max(cv.X / 2, p.ctx.topbar.X + 245)
	local box = Theme.frame(layer, UDim2.fromOffset(470, 64), UDim2.fromOffset(cx, 12), Theme.PANEL, TOP_MID)
	box.BackgroundTransparency = 0.1
	Theme.round(box, 32)
	Theme.stroke(box, 3, Theme.INK)
	local mode = if st.mode == "ffa" then "4 PLAYERS" else "DUEL"
	local word = Theme.text(box, "", 26, UDim2.fromOffset(300, 30), UDim2.fromOffset(20, 6), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
	})
	local sub = Theme.text(box, "", 20, UDim2.fromOffset(300, 22), UDim2.fromOffset(20, 36), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW_TXT,
	})
	local cancel =
		Theme.button(box, "CANCEL", UDim2.fromOffset(134, 48), UDim2.new(1, -8, 0.5, 0), Theme.BAD, nil, 24, V2(1, 0.5))
	cancel.Activated:Connect(function()
		p.ctx.act(Net.Action.cancel)
	end)
	local n = st.humans or 1
	local function tick()
		local dots = string.rep(".", 1 + math.floor(os.clock() * 2) % 3)
		word.Text = `SEARCHING {mode}{dots}`
		local left = if st.endsAt then math.max(0, st.endsAt - workspace:GetServerTimeNow()) else 0
		sub.Text = `{n} PLAYER{if n == 1 then "" else "S"} · `
			.. (if left > 0 then `BOTS IN {math.ceil(left)}s` else "BOTS JOINING")
	end
	p.tick = tick
	tick()
	Theme.pop(box, 0, 0.7)
end

local function note(p: Plaza, layer: Frame)
	local text = p.note
	if not text or os.clock() > p.noteUntil then
		return
	end
	local cv = p.ctx.canvas
	local t = Theme.text(layer, string.upper(text), 24, UDim2.fromOffset(560, 32), UDim2.fromOffset(cv.X / 2, 84), {
		anchor = TOP_MID,
		color = Theme.YELLOW_TXT,
	})
	t.Name = "Note"
end

function Plaza.render(p: Plaza)
	p.root:ClearAllChildren()
	p.tick = nil
	local st = p.st
	local on = st ~= nil and (st.ph == "lobby" or st.ph == "queue")
	p.root.Visible = on
	PartyPanel.show(p.panel, on)
	if not on or not st then
		return
	end
	local layer = Theme.clear(p.root, UDim2.fromScale(1, 1))
	if st.ph == "queue" then
		pill(p, layer, st)
	else
		buttons(p, layer)
	end
	note(p, layer)
end

function Plaza.new(parent: Instance, ctx: Ctx): Plaza
	local root = Instance.new("Frame")
	root.Name = "Plaza"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = parent
	local p: Plaza = {
		root = root,
		ctx = ctx,
		st = nil,
		party = nil,
		playOpen = false,
		panel = nil :: any,
		tick = nil,
		note = nil,
		noteUntil = 0,
		pressed = false,
	}
	p.panel = PartyPanel.new(parent, ctx, function(text)
		Plaza.flash(p, text)
	end)
	return p
end

-- Short message at the top for 3.5 s.
function Plaza.flash(p: Plaza, text: string)
	p.note = text
	p.noteUntil = os.clock() + 3.5
	Plaza.render(p)
	task.delay(3.6, function()
		if os.clock() >= p.noteUntil then
			local n = p.root:FindFirstChild("Note", true)
			if n then
				n:Destroy()
			end
		end
	end)
end

function Plaza.setState(p: Plaza, st: Net.State)
	if st.ph ~= "lobby" then
		p.playOpen = false
	end
	p.st = st
	Plaza.render(p)
end

function Plaza.setParty(p: Plaza, v: Net.PartyView)
	p.party = v
	PartyPanel.set(p.panel, v)
	if v.note then
		Plaza.flash(p, v.note)
	else
		Plaza.render(p)
	end
end

-- 10 times a second (search countdown).
function Plaza.step(p: Plaza)
	if p.tick then
		p.tick()
	end
	PartyPanel.step(p.panel)
end

return Plaza
