--!strict
-- M3.1 on the plaza, compact at the right edge so the avatar can run (stick bottom left, jump bottom right stay free):
-- coin and crystal counters above PLAY (numbers roll up when something pays, "+25" floats up), and a row of three
-- small buttons under HOW TO PLAY: DAILY (red "!" when the login reward waits), QUESTS (done/3), BOOK (found),
-- SHOP (balls still missing) and SPIN when the server allows paid random. They open Daily, Quests, Book, Shop and Spin.
-- Short toasts at the top middle: a new reaction, a quest done. Data: the Profile remote (Net.ProfileView).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Book = require("./Book")
local Cheer = require("./Cheer")
local Daily = require("./Daily")
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Quests = require("./Quests")
local Shop = require("./Shop")
local Spin = require("./Spin")
local Theme = require("./Theme")

local V2 = Vector2.new
local RIGHT = V2(1, 0)
local TOP_MID = V2(0.5, 0)

export type Ctx = {
	act: (verb: string, arg: number?, cur: string?) -> (),
	canvas: Vector2,
	topbar: Vector2,
	-- another popup (NEW BALL!) is on screen: the login screen waits
	busy: () -> boolean,
}

type Toast = { text: string, color: Color3 }

export type Wallet = {
	root: Frame,
	pop: Frame,
	ctx: Ctx,
	fx: Cheer.Ctx,
	view: Net.ProfileView?,
	st: Net.State?,
	coins: Money.Roll?,
	gems: Money.Roll?,
	open: string?,
	-- which shop tab is showing: balls, spin, skins
	tab: Shop.Tab,
	-- login claims count the screen opened by itself for (once per day per client)
	autoFor: number?,
	lobbyAt: number,
	fresh: { [string]: boolean },
	toasts: { Toast },
	live: { { f: TextLabel, t: number } },
	floats: { { f: TextLabel, t: number, y: number } },
	-- gains that came off the plaza (on the result screen): their "+n" floats up when the plaza shows
	owed: { [string]: number },
}

local ROBUX_COL = Color3.fromHex("#1c9e6a")

local Wallet = {}

local function onPlaza(w: Wallet): boolean
	local st = w.st
	return st ~= nil and (st.ph == "lobby" or st.ph == "queue")
end

local function layout(w: Wallet): Theme.PlazaLayout
	return Theme.plaza(w.ctx.canvas, w.ctx.topbar)
end

-- Coin / crystal counter at the top right.
local function pill(w: Wallet, layer: Frame, cur: string, y: number, roll: Money.Roll)
	local L = layout(w)
	local box =
		Theme.frame(layer, UDim2.fromOffset(L.moneyW, L.moneyH), UDim2.fromOffset(L.right, y), Theme.PANEL, RIGHT)
	box.Name = if cur == "coins" then "Coins" else "Crystals"
	box.BackgroundTransparency = 0.1
	Theme.round(box, L.moneyH / 2)
	Theme.stroke(box, 3, Theme.INK)
	Instance.new("UIScale").Parent = box
	Money.icon(box, cur, 40, UDim2.fromOffset(20, L.moneyH / 2)).ZIndex = 3
	local t = Theme.label(
		box,
		Money.fmt(roll.shown + 0.5),
		28,
		UDim2.fromOffset(L.moneyW - 54, 30),
		UDim2.new(1, -14, 0.5, 0),
		{
			anchor = V2(1, 0.5),
			align = Enum.TextXAlignment.Right,
			color = if cur == "coins" then Money.COIN else Money.GEM,
		}
	)
	t.Name = "Value"
	roll.label, roll.box = t, box
end

-- Icon of the top-left row (slot 0..2; Plaza puts HELP in slot 3). "Sub" is the count badge.
local function small(
	w: Wallet,
	layer: Frame,
	name: string,
	icon: string,
	caption: string,
	slot: number,
	color: Color3
): TextButton
	local L = layout(w)
	local b = Theme.iconButton(
		layer,
		icon,
		caption,
		L.icon,
		UDim2.fromOffset(L.rowX + slot * (L.icon + L.gap), L.rowY),
		color
	)
	b.Name = name
	return b
end

-- SHOP uses the same icon button. The fifth slot stays on the row when it clears the coin pills;
-- otherwise it wraps under the row, in the rightmost column that stays clear of PLAY.
local function shopPos(L: Theme.PlazaLayout): UDim2
	local step = L.icon + L.gap
	local x = L.rowX + 4 * step
	if x + L.icon <= L.right - L.moneyW - L.gap then
		return UDim2.fromOffset(x, L.rowY)
	end
	local y = L.rowY + L.icon + L.gap
	local playLeft = L.right - L.playW
	for slot = 3, 0, -1 do
		local sx = L.rowX + slot * step
		local overPlay = sx + L.icon > playLeft - 8 and y + L.icon > L.playY
		if not overPlay then
			return UDim2.fromOffset(sx, y)
		end
	end
	return UDim2.fromOffset(L.rowX, y)
end

local function count(b: GuiObject, text: string)
	if text ~= "" then
		local d = Theme.badge(b, text, Theme.SLOT, "Count")
		local t = d:FindFirstChild("Text") :: TextLabel
		t.Name = "Sub"
	end
end

local function dot(b: GuiObject)
	local old = b:FindFirstChild("Count")
	if old then
		old:Destroy()
	end
	Theme.badge(b, "!", Theme.BAD, "Dot")
end

local function closePop(w: Wallet)
	w.open = nil
	w.pop:ClearAllChildren()
	w.pop.Visible = false
	table.clear(w.fx.frames)
end

local function openPop(w: Wallet, which: string, claim: any?)
	local v = w.view
	if not v then
		return
	end
	table.clear(w.fx.frames)
	w.open = which
	w.pop.Visible = true
	w.fx.canvas = w.ctx.canvas
	local function close()
		closePop(w)
		Wallet.render(w)
	end
	if which == "daily" then
		Daily.build(
			w.pop,
			v,
			{ canvas = w.ctx.canvas, topbar = w.ctx.topbar, act = w.ctx.act, close = close, fx = w.fx },
			claim
		)
	elseif which == "quests" then
		-- under the icon row, left of PLAY
		local L = layout(w)
		local right = math.min(L.rowX + 430, L.right - L.playW - 12)
		Quests.build(w.pop, v, { frames = w.fx.frames, close = close }, right, L.rowY + L.icon + 12)
	elseif which == "shop" then
		Shop.build(w.pop, v, {
			canvas = w.ctx.canvas,
			frames = w.fx.frames,
			close = close,
			act = w.ctx.act,
			tab = w.tab,
			setTab = function(name: Shop.Tab)
				w.tab = name
				openPop(w, "shop")
			end,
		})
	else
		Book.build(w.pop, v, { canvas = w.ctx.canvas, frames = w.fx.frames, close = close }, w.fresh)
		table.clear(w.fresh)
	end
	Wallet.render(w)
end

-- The plaza shop kiosk uses the same screen as the SHOP button. No-op off the lobby.
function Wallet.show(w: Wallet, which: string)
	if not onPlaza(w) or w.st == nil or w.st.ph ~= "lobby" or w.view == nil then
		return
	end
	-- the kiosk opens the last tab; never the spin tab when paid random is restricted
	local v = w.view :: Net.ProfileView
	if which == "shop" and w.tab == "spin" and not (v.spin and v.spin.ok) then
		w.tab = "balls"
	end
	if w.open == which then
		closePop(w)
		Wallet.render(w)
	else
		openPop(w, which)
	end
end

function Wallet.render(w: Wallet)
	w.root:ClearAllChildren()
	local v = w.view
	local on = v ~= nil and v.coins ~= nil and onPlaza(w)
	w.root.Visible = on
	if not on or not v then
		if w.open and not onPlaza(w) then
			closePop(w)
		end
		return
	end
	local layer = Theme.clear(w.root, UDim2.fromScale(1, 1))
	local coins = w.coins or Money.roll(v.coins or 0)
	local gems = w.gems or Money.roll(v.crystals or 0)
	w.coins, w.gems = coins, gems
	local L = layout(w)
	pill(w, layer, "coins", L.moneyY[1], coins)
	pill(w, layer, "crystals", L.moneyY[2], gems)
	-- shown on the plaza: roll to the new values now
	Money.target(coins, v.coins or 0)
	Money.target(gems, v.crystals or 0)
	if w.st and w.st.ph == "queue" then
		return
	end
	-- "+" at the right end of the crystal counter: the crystal packs. The disc is drawn in the pill; the hit area
	-- is 62 design px (44 px on a phone) and only reaches into the gap above, never down onto PLAY.
	local gemsBox = gems.box
	if gemsBox then
		local value = gemsBox:FindFirstChild("Value") :: TextLabel?
		if value then
			value.Position = UDim2.new(1, -54, 0.5, 0)
			value.Size = UDim2.fromOffset(L.moneyW - 98, 30)
		end
	end
	local add = Instance.new("TextButton")
	add.Name = "AddGems"
	add.Text = ""
	add.AutoButtonColor = false
	add.BackgroundTransparency = 1
	add.Size = UDim2.fromOffset(62, 62)
	add.AnchorPoint = V2(1, 0.5)
	add.Position = UDim2.fromOffset(L.right, L.moneyY[2] + L.moneyH / 2 - 2)
	add.ZIndex = 5
	add.Parent = layer
	local disc = Theme.frame(add, UDim2.fromOffset(36, 36), UDim2.new(1, -4, 0.5, 2), ROBUX_COL, V2(1, 0.5))
	disc.Name = "Disc"
	disc.ZIndex = 6
	Theme.round(disc, 18)
	Theme.stroke(disc, 3, Theme.INK)
	Theme.label(
		disc,
		"+",
		32,
		UDim2.fromScale(1, 1),
		UDim2.fromScale(0.5, 0.45),
		{ anchor = V2(0.5, 0.5), stroke = 3, z = 7 }
	).Name =
		"Plus"
	Theme.press(add)
	add.Activated:Connect(function()
		if w.open == "shop" and w.tab == "packs" then
			closePop(w)
			Wallet.render(w)
		else
			w.tab = "packs"
			openPop(w, "shop")
		end
	end)
	local d = v.daily
	local daily = small(w, layer, "DailyBtn", "🎁", "DAILY", 0, Theme.ORANGE)
	if d and d.ready then
		dot(daily)
	end
	local q = v.quests
	local done = 0
	local list: { Net.QuestView } = if q then q.list else {}
	for _, r in list do
		done += if r.done then 1 else 0
	end
	local quests = small(w, layer, "QuestsBtn", "📜", "QUESTS", 1, Theme.SLOT)
	count(quests, if q then `{done}/{#q.list}` else "")
	local book = small(w, layer, "BookBtn", "📖", "BOOK", 2, Theme.SLOT)
	count(book, tostring(#(v.book or {})))
	if next(w.fresh) then
		dot(book)
	end
	local have: { [number]: boolean } = {}
	for _, e in v.balls do
		have[e] = true
	end
	local missing = 0
	for e = 0, 26 do
		if not have[e] then
			missing += 1
		end
	end
	local shopAt = shopPos(L)
	local shop = Theme.iconButton(layer, "🛒", "SHOP", L.icon, shopAt, Theme.YELLOW)
	shop.Name = "ShopBtn"
	if missing > 0 then
		count(shop, tostring(missing))
	end
	local btns: { [string]: TextButton } = { daily = daily, quests = quests, book = book, shop = shop }
	-- Same row as the other icons. Hidden when PolicyService restricted paid random (no spin field, or ok = false).
	if v.spin and v.spin.ok then
		local spin = Theme.iconButton(layer, "🎰", "SPIN", L.icon, Spin.iconPos(L, shopAt), Theme.ORANGE)
		spin.Name = "SpinBtn"
		btns.spin = spin
	end
	for name, b in btns do
		local lit = (name == "shop" and w.open == "shop") or (name == "spin" and w.open == "shop" and w.tab == "spin")
		Theme.select(b, lit or w.open == name)
		b.Activated:Connect(function()
			if name == "spin" then
				if w.open == "shop" and w.tab == "spin" then
					closePop(w)
					Wallet.render(w)
				else
					w.tab = "spin"
					openPop(w, "shop")
				end
				return
			end
			if name == "shop" then
				if w.open == "shop" and w.tab == "balls" then
					closePop(w)
					Wallet.render(w)
				else
					w.tab = "balls"
					openPop(w, "shop")
				end
				return
			end
			if w.open == name then
				closePop(w)
				Wallet.render(w)
			else
				openPop(w, name)
			end
		end)
	end
end

local function toast(w: Wallet, text: string, color: Color3)
	table.insert(w.toasts, { text = text, color = color })
end

-- "+25" rising from a counter.
local function float(w: Wallet, cur: string, n: number)
	local L = layout(w)
	local x = L.right - L.moneyW
	local y = if cur == "coins" then L.moneyY[1] else L.moneyY[2]
	local f = Theme.label(w.pop.Parent :: Instance, `+{Money.fmt(n)}`, 28, UDim2.fromOffset(120, 32), nil, {
		anchor = V2(1, 0),
		color = if cur == "coins" then Money.COIN else Money.GEM,
	})
	f.Name = "Float"
	f.Position = UDim2.fromOffset(x - 10, y + 4)
	f.ZIndex = 60
	table.insert(w.floats, { f = f, t = 0, y = y + 2 })
end

function Wallet.setProfile(w: Wallet, v: Net.ProfileView)
	w.view = v
	-- levels after the level balls pay coins (and every 5th crystals): no NEW BALL! for them, a toast instead
	local ups: { Net.LevelUp } = v.news or {}
	for _, up in ups do
		if up.coins then
			local gem = if up.crystals then `  +{up.crystals} CRYSTALS` else ""
			toast(w, `LEVEL {up.level}!  +{up.coins} COINS{gem}`, Theme.YELLOW)
		end
	end
	local found: { string } = v.found or {}
	for _, k in found do
		w.fresh[k] = true
		toast(w, `NEW REACTION! {k}  +25`, Theme.YELLOW_TXT)
	end
	local done: { { id: string, text: string, coins: number } } = v.done or {}
	for _, q in done do
		toast(w, if q.id == "all" then `ALL QUESTS DONE!  +{q.coins}` else `QUEST DONE!  +{q.coins}`, Theme.GOOD_TXT)
	end
	local gains: { { cur: string, n: number, why: string } } = v.gains or {}
	for _, g in gains do
		w.owed[g.cur] = (w.owed[g.cur] or 0) + g.n
	end
	if v.claim and w.open == "daily" then
		openPop(w, "daily", v.claim)
	elseif v.spinResult and v.spin and v.spin.ok and onPlaza(w) then
		w.tab = "spin"
		openPop(w, "shop")
	elseif w.open == "shop" and w.tab == "spin" and (not v.spin or not v.spin.ok) then
		closePop(w)
	elseif w.open then
		-- keep the open screen up to date (quest progress, book)
		if w.open ~= "daily" then
			openPop(w, w.open)
		end
	end
	Wallet.render(w)
end

function Wallet.setState(w: Wallet, st: Net.State)
	local was = w.st
	w.st = st
	if st.ph == "lobby" and (not was or was.ph ~= "lobby") then
		w.lobbyAt = os.clock()
	end
	if w.open and st.ph ~= "lobby" and st.ph ~= "queue" then
		closePop(w)
	end
	Wallet.render(w)
end

-- Every frame: counters, floats, toasts, popup effects; the login screen opens itself once a day on the plaza
-- (U2: also right after the tutorial's reward screen; never during the tutorial or over NEW BALL!).
function Wallet.step(w: Wallet, dt: number)
	if w.coins then
		Money.step(w.coins, dt)
	end
	if w.gems then
		Money.step(w.gems, dt)
	end
	for _, f in w.fx.frames do
		f(dt)
	end
	for i = #w.floats, 1, -1 do
		local o = w.floats[i]
		o.t += dt
		if o.t > 1.2 or not o.f.Parent then
			o.f:Destroy()
			table.remove(w.floats, i)
		else
			o.f.Position = UDim2.new(o.f.Position.X, UDim.new(0, o.y + 40 * o.t))
			o.f.TextTransparency = math.max(0, (o.t - 0.6) / 0.6)
		end
	end
	local on = onPlaza(w) and w.root.Visible
	if on then
		for cur, n in w.owed do
			float(w, cur, n)
		end
		table.clear(w.owed)
	end
	for i = #w.live, 1, -1 do
		local o = w.live[i]
		o.t += dt
		if o.t > 2.6 or not o.f.Parent then
			o.f:Destroy()
			table.remove(w.live, i)
		end
	end
	local st0 = w.st
	if on and #w.toasts > 0 and #w.live < 3 then
		local t = table.remove(w.toasts, 1) :: Toast
		local cv = w.ctx.canvas
		local f = Theme.label(w.pop.Parent :: Instance, t.text, 26, UDim2.fromOffset(520, 32), nil, {
			anchor = TOP_MID,
			color = t.color,
		})
		f.Name = "Toast"
		f.ZIndex = 60
		local y = if st0 and st0.ph == "queue" then 150 else 120
		f.Position = UDim2.fromOffset(math.max(cv.X / 2, w.ctx.topbar.X + 270), y + #w.live * 34)
		Theme.pop(f)
		table.insert(w.live, { f = f, t = 0 })
	end
	local v, st = w.view, w.st
	local d = v and v.daily
	if
		d
		and d.ready
		and st
		and st.ph == "lobby"
		and w.autoFor ~= d.n
		and not w.open
		and not w.ctx.busy()
		and os.clock() - w.lobbyAt > 1.2
	then
		w.autoFor = d.n
		openPop(w, "daily")
	end
end

function Wallet.new(parent: Instance, ctx: Ctx): Wallet
	local root = Instance.new("Frame")
	root.Name = "Wallet"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = parent
	local pop = Instance.new("Frame")
	pop.Name = "WalletPop"
	pop.BackgroundTransparency = 1
	pop.Size = UDim2.fromScale(1, 1)
	pop.Visible = false
	pop.ZIndex = 45
	pop.Parent = parent
	return {
		root = root,
		pop = pop,
		ctx = ctx,
		fx = { frames = {}, canvas = ctx.canvas },
		view = nil,
		st = nil,
		coins = nil,
		gems = nil,
		open = nil,
		tab = "balls",
		autoFor = nil,
		lobbyAt = 0,
		fresh = {},
		toasts = {},
		live = {},
		floats = {},
		owed = {},
	}
end

-- The canvas changed size: rebuild what is open.
function Wallet.refit(w: Wallet)
	if w.open then
		openPop(w, w.open)
	else
		Wallet.render(w)
	end
end

return Wallet
