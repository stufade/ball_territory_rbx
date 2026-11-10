--!strict
-- M3.1 plaza UI on a GUI stand-in (tests/Gui): coin and crystal counters roll up, the login screen opens by itself
-- once a day (not before the first match), CLAIM sends Action daily, the claimed card pops; quests panel, reaction
-- book (42 cells, found coloured, the rest "???"), result coins line; layout on the phone (1168x540 canvas) and
-- PC (960x540): inside the screen, clear of PLAY's column, the stick and the jump button.
-- lune run tests/ui
local process = require("@lune/process")
local Gui = require("./Gui")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local world = Gui.world()
local load = Gui.loader(world)
local Wallet = load("src/client/UI/Wallet.luau")
local Money = load("src/client/UI/Money.luau")
local Plaza = load("src/client/UI/Plaza.luau")
local Level = load("src/client/UI/Level.luau")
local Rules = load("src/shared/Rules/init.luau")
local V2 = function(x: number, y: number): any
	return { X = x, Y = y }
end

local function cards(pos: number, ready: boolean): { any }
	local list = {}
	local gifts = { { coins = 50 }, { coins = 75 }, { crystals = 15 }, { coins = 100 }, { coins = 150, trials = 1 } }
	gifts[6] = { coins = 200 }
	gifts[7] = { ball = 13 }
	for i, g in gifts do
		local c = table.clone(g) :: any
		c.got = i < pos or (i == pos and not ready)
		c.today = i == pos
		list[i] = c
	end
	return list
end

local function view(coins: number, crystals: number, ready: boolean, n: number): any
	return {
		level = 3,
		xp = 40,
		need = 350,
		balls = { 0, 1, 2, 3, 17 },
		total = 27,
		boostMult = 2,
		levelBalls = 9,
		coins = coins,
		crystals = crystals,
		daily = {
			n = n,
			pos = if ready then n + 1 else n,
			ready = ready,
			cards = cards(if ready then n + 1 else n, ready),
		},
		quests = {
			list = {
				{ id = "play3", text = "PLAY 3 MATCHES", n = 1, goal = 3, coins = 60, done = false },
				{ id = "wild3", text = "MAKE 3 WILDFIRE", n = 3, goal = 3, coins = 80, done = true },
				{ id = "duel3", text = "WIN 3 DUELS", n = 0, goal = 3, coins = 120, done = false },
			},
			all = false,
			allCoins = 50,
			endsAt = 3600 * 5,
		},
		book = { "WILDFIRE", "STEAM", "BOOM" },
		bookTotal = 42,
		streak = 0,
	}
end

local function find(root: any, name: string): any
	return root:FindFirstChild(name, true)
end

local function overlap(a: { number }, b: { number }): boolean
	return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
end

local function rectOf(o: any): { number }
	local x, y, w, h = Gui.rect(o)
	return { x, y, w, h }
end

local function step(w: any, seconds: number)
	local dt = 1 / 30
	for _ = 1, math.floor(seconds / dt + 0.5) do
		Gui.advance(dt)
		Wallet.step(w, dt)
	end
end

local function make(cv: any): (any, any, { any }, { busy: boolean })
	Gui.canvas = cv
	local canvas = Gui.new("Frame")
	canvas.Name = "Canvas"
	canvas.Size = { X = { Scale = 0, Offset = cv.X }, Y = { Scale = 0, Offset = cv.Y } }
	local acts = {}
	local flags = { busy = false }
	local ctx = {
		act = function(verb: string, arg: number?)
			table.insert(acts, { verb, arg })
		end,
		canvas = cv,
		topbar = V2(354, 86),
		busy = function()
			return flags.busy
		end,
	}
	return Wallet.new(canvas, ctx), canvas, acts, flags
end

for _, cv in { V2(1168, 540), V2(960, 540) } do
	local tag = `{cv.X}x{cv.Y}`
	local w, canvas, acts, flags = make(cv)
	-- after the tutorial (PLAY lit): no login popup yet
	Wallet.setState(w, { ph = "lobby", glow = "play" })
	Wallet.setProfile(w, view(0, 0, true, 0))
	step(w, 3)
	check(w.root.Visible and not w.pop.Visible, `{tag}: counters on the plaza, no popup before the first match`)
	local coins, gems = find(w.root, "Coins"), find(w.root, "Crystals")
	check(coins and gems and find(coins, "Value").Text == "0", `{tag}: coin and crystal pills`)
	local dailyBtn = find(w.root, "DailyBtn")
	check(dailyBtn and find(dailyBtn, "Dot") and find(dailyBtn, "Sub").Text == "1/7", `{tag}: DAILY with "!"`)
	check(find(find(w.root, "QuestsBtn"), "Sub").Text == "1/3", `{tag}: QUESTS 1/3`)
	check(find(find(w.root, "BookBtn"), "Sub").Text == "3", `{tag}: BOOK 3`)
	-- layout: inside the canvas, clear of PLAY (x >= cv.X - 190, y 96..298), the stick and the jump button
	local play = { cv.X - 14 - 176, 96, 176, 202 }
	local stick = { 83, 298, 166, 166 }
	local jump = { cv.X - 131, 415, 97, 97 }
	for _, name in { "Coins", "Crystals", "DailyBtn", "QuestsBtn", "BookBtn" } do
		local r = rectOf(find(w.root, name))
		check(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= cv.X and r[2] + r[4] <= cv.Y, `{tag}: {name} on screen`)
		check(not overlap(r, play), `{tag}: {name} clear of PLAY/PARTY/HOW TO PLAY`)
		check(not overlap(r, stick) and not overlap(r, jump), `{tag}: {name} clear of the stick and jump`)
		check(r[1] > cv.X - 14 - 176 - 1, `{tag}: {name} in the right column`)
	end
	-- NEW BALL! on screen: the login screen waits
	Wallet.setState(w, { ph = "result", win = true })
	Wallet.setState(w, { ph = "lobby" })
	flags.busy = true
	step(w, 2)
	check(not w.pop.Visible, `{tag}: no login popup over NEW BALL!`)
	flags.busy = false
	step(w, 0.2)
	check(w.pop.Visible and w.open == "daily", `{tag}: the login screen opens by itself`)
	local panel = find(w.pop, "DailyPanel")
	check(panel ~= nil, `{tag}: daily panel`)
	local r = rectOf(panel)
	check(r[1] >= 0 and r[1] + r[3] <= cv.X and r[2] >= 0 and r[2] + r[4] <= cv.Y, `{tag}: daily panel on screen`)
	for i = 1, 7 do
		check(find(panel, `Day{i}`) ~= nil, `{tag}: card day {i}`)
	end
	check(find(find(panel, "Day7"), "TextLabel") ~= nil, `{tag}: day 7 card`)
	local hasVoid = false
	for _, t in Gui.texts(find(panel, "Day7")) do
		hasVoid = hasVoid or t == Rules.Config.TITLE[13]
	end
	check(hasVoid, `{tag}: day 7 shows VOID`)
	find(panel, "Claim").Activated:Fire()
	find(panel, "Claim").Activated:Fire()
	check(#acts == 1 and acts[1][1] == "daily", `{tag}: CLAIM sends Action daily once`)
	-- the server pays: the card pops, counters roll 0 -> 50
	local v = view(50, 0, false, 1)
	v.claim = { n = 1, pos = 1, cycle = 1, gift = { coins = 50 } }
	v.gains = { { cur = "coins", n = 50, why = "login_d1" } }
	Wallet.setProfile(w, v)
	check(find(w.pop, "Taken") ~= nil and find(find(w.pop, "Day1"), "Got") ~= nil, `{tag}: TAKEN!, day 1 ticked`)
	check(find(w.pop, "Next") ~= nil and find(w.pop, "Ok") ~= nil, `{tag}: next reward timer`)
	step(w, 0.3)
	local mid = tonumber((find(w.root, "Coins"):FindFirstChild("Value", true).Text:gsub(",", "")))
	check(mid and mid > 0 and mid < 50, `{tag}: coins roll ({mid})`)
	check(find(canvas, "Float") ~= nil, `{tag}: "+50" floats up`)
	step(w, 1)
	check(find(w.root, "Coins"):FindFirstChild("Value", true).Text == "50", `{tag}: coins 50 after the roll`)
	check(find(canvas, "Float") == nil, `{tag}: the float is gone`)
	find(w.pop, "Ok").Activated:Fire()
	check(not w.pop.Visible and w.open == nil, `{tag}: OK closes`)
	step(w, 3)
	check(not w.pop.Visible, `{tag}: opens by itself only once`)
	-- quests panel
	find(w.root, "QuestsBtn").Activated:Fire()
	local qp = find(w.pop, "QuestPanel")
	check(qp and w.open == "quests", `{tag}: quests panel`)
	local qr = rectOf(qp)
	check(qr[1] >= 0 and qr[1] + qr[3] <= cv.X - 14 - 176 and qr[2] + qr[4] <= cv.Y, `{tag}: quests left of PLAY`)
	check(not overlap(qr, stick) and not overlap(qr, jump), `{tag}: quests clear of the stick and jump`)
	check(find(find(qp, "Quest2"), "Done") ~= nil and find(find(qp, "Quest1"), "Count").Text == "1/3", `{tag}: rows`)
	check(find(qp, "Reset").Text == "NEW IN 4h 59m", `{tag}: reset timer ({find(qp, "Reset").Text})`)
	find(w.root, "QuestsBtn").Activated:Fire()
	check(not w.pop.Visible, `{tag}: QUESTS again closes`)
	-- a match finds a reaction: toast, book dot, NEW! in the book
	local v2 = view(75, 0, false, 1)
	v2.book = { "WILDFIRE", "STEAM", "BOOM", "FROST" }
	v2.found = { "FROST" }
	v2.gains = { { cur = "coins", n = 25, why = "book_new" } }
	Wallet.setState(w, { ph = "result", win = false })
	Wallet.setProfile(w, v2)
	check(not w.root.Visible, `{tag}: no counters on the result screen`)
	step(w, 0.1)
	check(find(canvas, "Toast") == nil, `{tag}: the toast waits for the plaza`)
	Wallet.setState(w, { ph = "lobby" })
	step(w, 0.1)
	local toast = find(canvas, "Toast")
	check(toast and toast.Text == "NEW REACTION! FROST  +25", `{tag}: toast on the plaza`)
	check(find(find(w.root, "BookBtn"), "Dot") ~= nil, `{tag}: book "!"`)
	find(w.root, "BookBtn").Activated:Fire()
	local bp = find(w.pop, "BookPanel")
	check(bp and find(bp, "Head").Text == "REACTION BOOK 4/42", `{tag}: book head`)
	local br = rectOf(bp)
	check(br[1] >= 0 and br[1] + br[3] <= cv.X and br[2] >= 0 and br[2] + br[4] <= cv.Y, `{tag}: book on screen`)
	local open, shut, total = 0, 0, 0
	for _, c in find(bp, "Grid"):GetChildren() do
		total += 1
		if c:GetAttribute("Open") then
			open += 1
		elseif find(c, "Name").Text == "???" then
			shut += 1
		end
	end
	check(total == 42 and open == 4 and shut == 38, `{tag}: 42 cells, 4 open, 38 "???" ({total}/{open}/{shut})`)
	check(find(find(bp, "FROST"), "New") ~= nil and find(find(bp, "STEAM"), "New") == nil, `{tag}: NEW! on FROST`)
	-- a match starts: everything closes
	Wallet.setState(w, { ph = "match", mode = "duel" })
	check(not w.pop.Visible and not w.root.Visible, `{tag}: hidden in a match`)
	-- the search: counters stay, the buttons go
	Wallet.setState(w, { ph = "queue", mode = "duel" })
	check(w.root.Visible and find(w.root, "Coins") and find(w.root, "DailyBtn") == nil, `{tag}: search: counters only`)
end

-- level 10: a toast with its coins and crystals
do
	local w = make(V2(1168, 540))
	Wallet.setState(w, { ph = "lobby" })
	local v = view(150, 15, false, 1)
	v.news = { { level = 10, coins = 150, crystals = 15 } }
	Wallet.setProfile(w, v)
	step(w, 0.1)
	local t = w.root.Parent:FindFirstChild("Toast", true)
	check(t and t.Text == "LEVEL 10!  +150 COINS  +15 CRYSTALS", `level 10 toast ({t and t.Text})`)
end

-- an older server (no economy fields): nothing shows
do
	local w = make(V2(1168, 540))
	Wallet.setState(w, { ph = "lobby" })
	Wallet.setProfile(w, { level = 1, xp = 0, need = 150, balls = {}, total = 27, boostMult = 2, levelBalls = 9 })
	step(w, 2)
	check(not w.root.Visible and not w.pop.Visible, "old profile view: no counters, no popup")
end

-- result line
do
	local root = Gui.new("Frame")
	root.Size = { X = { Scale = 0, Offset = 960 }, Y = { Scale = 0, Offset = 540 } }
	Money.result(root, { coins = 64, friend = true, streak = 3 }, 300, 468)
	local texts = table.concat(Gui.texts(root), "|")
	check(texts == "+64|FRIEND +25%  ·  3 WINS IN A ROW!", `result: coins line ({texts})`)
	local r = rectOf(find(root, "Coins"))
	check(r[2] + r[4] <= 506, "result: coins line above the lobby countdown")
	local a = Gui.new("Frame")
	Money.result(a, { afk = true, coins = 0 }, 300, 468)
	check(find(a, "Afk") ~= nil and find(a, "Coins") == nil, "result: AFK line")
	check(Money.fmt(1234567) == "1,234,567" and Money.fmt(12) == "12" and Money.fmt(100) == "100", "fmt")
end

-- HOW TO PLAY asks first; the dev button only when the server says so; the next level ball on the level bar --------
do
	local cv = V2(1168, 540)
	Gui.canvas = cv
	local canvas = Gui.new("Frame")
	canvas.Size = { X = { Scale = 0, Offset = cv.X }, Y = { Scale = 0, Offset = cv.Y } }
	local acts = {}
	local ctx = {
		act = function(verb: string, arg: number?)
			table.insert(acts, { verb, arg })
		end,
		canvas = cv,
		topbar = V2(354, 86),
	}
	local function btn(root: any, text: string): any
		for _, d in root:GetDescendants() do
			if d._p.ClassName == "TextButton" then
				for _, t in Gui.texts(d) do
					if t == text then
						return d
					end
				end
			end
		end
		return nil
	end
	local noSignal = { Connect = function() end }
	world.services.Players.PlayerAdded, world.services.Players.PlayerRemoving = noSignal, noSignal
	local p = Plaza.new(canvas, ctx)
	Plaza.setState(p, { ph = "lobby" })
	check(find(p.root, "TutorConfirm") == nil and find(p.root, "DevBalls") == nil, "plaza: no dialog, no dev button")
	local how = btn(p.root, "HOW TO PLAY")
	check(how ~= nil, "plaza: HOW TO PLAY button")
	how.Activated:Fire()
	check(#acts == 0, "HOW TO PLAY alone sends nothing")
	local box = find(p.root, "TutorConfirm")
	check(
		box ~= nil and table.find(Gui.texts(box), "PLAY TUTORIAL AGAIN?") ~= nil,
		"HOW TO PLAY asks PLAY TUTORIAL AGAIN?"
	)
	find(p.root, "No").Activated:Fire()
	check(#acts == 0 and find(p.root, "TutorConfirm") == nil, "NO: closed, nothing sent")
	btn(p.root, "HOW TO PLAY").Activated:Fire()
	find(p.root, "Yes").Activated:Fire()
	check(#acts == 1 and acts[1][1] == "tutor", "YES: the tutor action goes out once")
	btn(p.root, "HOW TO PLAY").Activated:Fire()
	Plaza.setState(p, { ph = "match" })
	Plaza.setState(p, { ph = "lobby" })
	check(find(p.root, "TutorConfirm") == nil, "a match closes the dialog")
	Plaza.setDev(p, true)
	local dev = find(p.root, "DevBalls")
	check(dev ~= nil, "dev flag: DEV: ALL BALLS shown")
	dev.Activated:Fire()
	check(acts[#acts][1] == "devballs", "dev button sends devballs")
	Plaza.setDev(p, false)
	check(find(p.root, "DevBalls") == nil, "no dev flag: no button")

	local l = Level.new(canvas, { canvas = cv, topbar = V2(354, 86) })
	Level.setState(l, { ph = "lobby" })
	Level.setProfile(
		l,
		{ level = 3, xp = 10, need = 350, balls = { 0 }, total = 27, boostMult = 2, levelBalls = 9, nextBall = 13 }
	)
	local nb = find(l.root, "NextBall")
	check(nb ~= nil and nb:GetAttribute("Ball") == 13, "level bar: icon of the next ball")
	check(find(l.root, "NextWord") ~= nil and table.find(Gui.texts(l.root), "NEXT") ~= nil, "level bar: NEXT")
	Level.setProfile(l, { level = 9, xp = 10, need = 350, balls = { 0 }, total = 27, boostMult = 2, levelBalls = 9 })
	check(find(l.root, "NextBall") == nil and find(l.root, "NextWord") == nil, "no next ball: hidden")
end

print(`{passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
print("UI OK")
