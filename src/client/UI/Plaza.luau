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
local MID = V2(0.5, 0.5)

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
	-- HOW TO PLAY asks "PLAY TUTORIAL AGAIN?" first
	confirm: boolean,
	-- the server says this person may use the developer button (TODO(REMOVE BEFORE LAUNCH): dev button)
	dev: boolean,
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

-- After the tutorial (State lobby glow = "play"): PLAY pulses inside a yellow ring and a hand points at it.
-- The pulse scales the wrapper, the press scales the button: they multiply and never fight over one UIScale.
local function glow(layer: Frame, wrap: Frame, L: Theme.PlazaLayout)
	local ring = Theme.frame(wrap, UDim2.new(1, 18, 1, 18), UDim2.fromScale(0.5, 0.5), Theme.YELLOW, MID)
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	Theme.round(ring, 24)
	Theme.stroke(ring, 6, Theme.YELLOW)
	local cy = L.playY + L.playH / 2
	local hx = L.right - L.playW - 14
	local hand = Theme.label(layer, "👉", 72, UDim2.fromOffset(90, 90), UDim2.fromOffset(hx, cy), {
		anchor = V2(1, 0.5),
		stroke = 0,
	})
	if Theme.reduced() then
		return
	end
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(Theme.scaleOf(wrap), info, { Scale = 1.06 }):Play()
	TweenService:Create(hand, info, { Position = UDim2.fromOffset(hx + 14, cy) }):Play()
end

-- PLAY (the biggest, green) and PARTY under it at the right edge, above the jump button; PLAY opens its choices
-- to the left. The help button ("?") sits in the icon row at the top left (Wallet draws DAILY / QUESTS / BOOK).
local function buttons(p: Plaza, layer: Frame)
	local act = p.ctx.act
	local L = Theme.plaza(p.ctx.canvas, p.ctx.topbar)
	local party = inParty(p)
	local host = isHost(p)
	local wrap = Theme.clear(
		layer,
		UDim2.fromOffset(L.playW, L.playH),
		UDim2.fromOffset(L.right - L.playW / 2, L.playY + L.playH / 2),
		MID
	)
	wrap.Name = "PlayWrap"
	local play = Theme.button(wrap, "PLAY", UDim2.fromScale(1, 1), nil, Theme.GO, nil, 52)
	play.Name = "Play"
	local st = p.st
	if st and st.glow == "play" and not p.playOpen and not p.pressed then
		glow(layer, wrap, L)
		wrap.Name = "PlayLit"
	end
	play.Activated:Connect(function()
		if not play.Active then
			return
		end
		p.pressed = true
		p.playOpen = not p.playOpen
		Plaza.render(p)
	end)
	if party and not host then
		Theme.disable(play, "HOST STARTS")
		p.playOpen = false
	end
	if p.playOpen then
		Theme.select(play, true)
		local cx = L.right - L.playW - 12
		local duelText = if party then "DUEL EACH OTHER" else "DUEL"
		local ffaText = if party then "4 PLAYERS TOGETHER" else "4 PLAYERS"
		local w = if party then 300 else 230
		local duel = Theme.button(
			layer,
			duelText,
			UDim2.fromOffset(w, 66),
			UDim2.fromOffset(cx, L.playY - 18),
			Theme.GO,
			nil,
			32,
			RIGHT
		)
		local ffa = Theme.button(
			layer,
			ffaText,
			UDim2.fromOffset(w, 66),
			UDim2.fromOffset(cx, L.playY + 56),
			Theme.PURPLE,
			nil,
			32,
			RIGHT
		)
		duel.Name, ffa.Name = "Duel", "Ffa"
		local two = not party or #(p.party :: Net.PartyView).members == 2
		if not two then
			Theme.disable(duel)
		end
		Theme.pop(duel, 0)
		Theme.pop(ffa, 0.04)
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
	local partyBtn = Theme.button(
		layer,
		if n > 0 then `PARTY {n}/4` else "PARTY +",
		UDim2.fromOffset(L.playW, L.partyH),
		UDim2.fromOffset(L.right, L.partyY),
		Theme.PURPLE,
		nil,
		34,
		RIGHT
	)
	partyBtn.Name = "PartyBtn"
	Theme.select(partyBtn, p.panel.open)
	-- 4th icon of the top-left row: HOW TO PLAY
	local how = Theme.iconButton(
		layer,
		"❓",
		"HELP",
		L.icon,
		UDim2.fromOffset(L.rowX + 3 * (L.icon + L.gap), L.rowY),
		Theme.SLOT
	)
	how.Name = "HowTo"
	how.Activated:Connect(function()
		p.playOpen = false
		p.confirm = true
		Plaza.render(p)
	end)
	partyBtn.Activated:Connect(function()
		if n == 0 then
			act(Net.Action.pcreate)
			PartyPanel.open(p.panel, true)
		else
			PartyPanel.open(p.panel, not p.panel.open)
		end
		Plaza.render(p)
	end)
end

-- "PLAY TUTORIAL AGAIN?" YES / NO: the tutorial takes the player off the plaza (and out of a search), so it is asked.
local function confirmBox(p: Plaza, layer: Frame)
	local cv = p.ctx.canvas
	local dim = Theme.frame(layer, UDim2.fromScale(1, 1), nil, Theme.BG)
	dim.BackgroundTransparency = 0.45
	dim.Active = true
	dim.ZIndex = 20
	local box = Theme.frame(layer, UDim2.fromOffset(440, 196), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	box.Name = "TutorConfirm"
	box.ZIndex = 21
	Theme.round(box, 24)
	Theme.stroke(box, 4, Theme.INK)
	Theme.label(box, "PLAY TUTORIAL AGAIN?", 32, UDim2.fromOffset(400, 40), UDim2.fromOffset(220, 22), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
	})
	Theme.label(box, "YOU GET NO REWARD THE 2ND TIME", 20, UDim2.fromOffset(400, 24), UDim2.fromOffset(220, 64), {
		anchor = TOP_MID,
		color = Theme.DIM,
		bold = true,
	})
	local yes = Theme.button(box, "YES", UDim2.fromOffset(176, 70), UDim2.fromOffset(30, 104), Theme.GO, nil, 36)
	local no = Theme.button(box, "NO", UDim2.fromOffset(176, 70), UDim2.fromOffset(234, 104), Theme.BAD, nil, 36)
	yes.Name, no.Name = "Yes", "No"
	yes.Activated:Connect(function()
		p.confirm = false
		p.ctx.act(Net.Action.tutor)
		Plaza.render(p)
	end)
	no.Activated:Connect(function()
		p.confirm = false
		Plaza.render(p)
	end)
	Theme.pop(box)
end

-- TODO(REMOVE BEFORE LAUNCH): dev button. Small, in the bottom left corner under the stick (clear of the stick, the
-- jump button and the Roblox buttons); the server decides who gets it and who may use it.
local function devButton(p: Plaza, layer: Frame)
	local b = Theme.button(
		layer,
		"DEV: ALL BALLS",
		UDim2.fromOffset(196, 36),
		UDim2.fromOffset(8, p.ctx.canvas.Y - 6),
		Theme.SLOT,
		nil,
		20,
		V2(0, 1)
	)
	b.Name = "DevBalls"
	b.Activated:Connect(function()
		p.ctx.act(Net.Action.devballs)
	end)
end

-- "SEARCHING... 2 PLAYERS · BOTS IN 4s  [CANCEL]" at the top middle.
local function pill(p: Plaza, layer: Frame, st: Net.State)
	local cv = p.ctx.canvas
	-- between the Roblox buttons (top left) and the coins (top right)
	local L = Theme.plaza(cv, p.ctx.topbar)
	local x0, x1 = L.rowX, L.right - L.moneyW - 10
	local bw = math.min(470, x1 - x0)
	local box = Theme.frame(layer, UDim2.fromOffset(bw, 64), UDim2.fromOffset((x0 + x1) / 2, 12), Theme.PANEL, TOP_MID)
	box.BackgroundTransparency = 0.1
	Theme.round(box, 32)
	Theme.stroke(box, 3, Theme.INK)
	local mode = if st.mode == "ffa" then "4 PLAYERS" else "DUEL"
	local word = Theme.label(box, "", 24, UDim2.fromOffset(bw - 170, 30), UDim2.fromOffset(20, 6), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
	})
	local sub = Theme.label(box, "", 20, UDim2.fromOffset(bw - 170, 22), UDim2.fromOffset(20, 36), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW_TXT,
	})
	local cancel =
		Theme.button(box, "CANCEL", UDim2.fromOffset(140, 50), UDim2.new(1, -8, 0.5, 0), Theme.BAD, nil, 24, V2(1, 0.5))
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
	Theme.pop(box)
end

local function note(p: Plaza, layer: Frame)
	local text = p.note
	if not text or os.clock() > p.noteUntil then
		return
	end
	local cv = p.ctx.canvas
	local t = Theme.text(layer, string.upper(text), 24, UDim2.fromOffset(560, 32), UDim2.fromOffset(cv.X / 2, 102), {
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
		if p.dev then
			devButton(p, layer)
		end
		if p.confirm then
			confirmBox(p, layer)
		end
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
		confirm = false,
		dev = false,
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
		p.confirm = false
	end
	p.st = st
	Plaza.render(p)
end

function Plaza.setDev(p: Plaza, on: boolean)
	if p.dev ~= on then
		p.dev = on
		Plaza.render(p)
	end
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
