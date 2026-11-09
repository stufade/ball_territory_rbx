--!strict
-- Full-screen menus by State.ph: lobby, queue, pick, draft, choose, wait, result. Gray prototype, see docs/ui.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Theme = require("./Theme")

local Menus = {}

export type Ctx = {
	act: (verb: string, arg: number?) -> (),
	timeLeft: (endsAt: number?) -> number,
	tickers: { () -> () },
	seats: { [number]: Net.Seat }, -- by element id, last match
	you: number?,
	mySide: number,
	score: { number }, -- duel rounds won {side0, side1}
	lastEnd: Net.MatchEnd?,
}

local TITLE, WORD, ABOUT = Config.TITLE, Config.WORD, Config.ABOUT

local function name(e: number): string
	return TITLE[e] or "?"
end

local function has(list: { number }?, e: number): boolean
	return list ~= nil and table.find(list, e) ~= nil
end

-- Matchup of element e against foes: lines "Beats X" (green) and "Weak to X" (red), border color.
local function matchup(e: number, foes: { number }): (string, string, Color3?)
	local good, bad = {}, {}
	for _, f in foes do
		if has(Config.DSTRONG[e], f) then
			table.insert(good, name(f))
		elseif has(Config.DWEAK[e], f) then
			table.insert(bad, name(f))
		end
	end
	local border: Color3? = nil
	if #good > #bad then
		border = Theme.GOOD
	elseif #bad > #good then
		border = Theme.BAD
	end
	return if #good > 0 then "Beats " .. table.concat(good, ", ") else "",
		if #bad > 0 then "Weak to " .. table.concat(bad, ", ") else "",
		border
end

local function countdown(ctx: Ctx, l: TextLabel, endsAt: number?, fmt: string?)
	table.insert(ctx.tickers, function()
		local t = math.ceil(ctx.timeLeft(endsAt))
		l.Text = if fmt then string.format(fmt, t) else tostring(t)
	end)
end

local function row(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2?, pad: number?): Frame
	local f = Theme.frame(parent, size, pos, Color3.new(), anchor)
	f.BackgroundTransparency = 1
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, pad or 16)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	return f
end

-- Big card: icon, name, power word, one-line about, matchup lines. `foes` colors the border.
local function card(parent: Instance, e: number, size: UDim2, foes: { number }, onPick: (() -> ())?): TextButton
	local b = Theme.button(parent, "", size, nil, Theme.PANEL, nil)
	b.AutoButtonColor = onPick ~= nil
	local good, bad, border = matchup(e, foes)
	if border then
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = border
			s.Thickness = 6
		end
	end
	Theme.ballIcon(b, e, name(e), 64, UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	Theme.label(b, name(e), 28, UDim2.new(1, -12, 0, 34), UDim2.fromOffset(6, 80), { title = true })
	Theme.label(b, WORD[e] or "", 22, UDim2.new(1, -12, 0, 26), UDim2.fromOffset(6, 114), { color = Theme.ACCENT })
	Theme.label(
		b,
		ABOUT[e] or "",
		18,
		UDim2.new(1, -16, 0, 60),
		UDim2.fromOffset(8, 142),
		{ color = Theme.DIM, outline = false }
	)
	if good ~= "" then
		Theme.label(b, good, 18, UDim2.new(1, -12, 0, 22), UDim2.new(0, 6, 1, -48), { color = Theme.GOOD })
	end
	if bad ~= "" then
		Theme.label(b, bad, 18, UDim2.new(1, -12, 0, 22), UDim2.new(0, 6, 1, -26), { color = Theme.BAD })
	end
	if onPick then
		b.Activated:Connect(onPick)
	end
	return b
end

-- Compact grid of cards in a scrolling frame (ffa pick, "Any ball").
local function grid(
	parent: Instance,
	elems: { number },
	foes: { number },
	size: UDim2,
	pos: UDim2,
	onPick: (number) -> ()
)
	local sf = Instance.new("ScrollingFrame")
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Size = size
	sf.Position = pos
	sf.CanvasSize = UDim2.new()
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ScrollBarThickness = 8
	sf.Parent = parent
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.fromOffset(200, 120)
	g.CellPadding = UDim2.fromOffset(10, 10)
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = sf
	for _, e in elems do
		local b = Theme.button(sf, "", UDim2.new(), nil, Theme.PANEL)
		local _, _, border = matchup(e, foes)
		if border then
			local s = b:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = border
				s.Thickness = 6
			end
		end
		Theme.ballIcon(b, e, name(e), 56, UDim2.fromOffset(8, 8))
		Theme.label(
			b,
			name(e),
			24,
			UDim2.new(1, -76, 0, 56),
			UDim2.fromOffset(68, 8),
			{ title = true, align = Enum.TextXAlignment.Left }
		)
		Theme.label(b, WORD[e] or "", 20, UDim2.new(1, -12, 0, 30), UDim2.new(0, 6, 1, -40), { color = Theme.ACCENT })
		b.Activated:Connect(function()
			onPick(e)
		end)
	end
end

local function header(root: Instance, text: string, sub: string?)
	Theme.label(root, text, 56, UDim2.new(1, 0, 0, 70), UDim2.fromOffset(0, 12), { title = true })
	if sub then
		Theme.label(root, sub, 26, UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 80), { color = Theme.DIM })
	end
end

local function timerBadge(root: Instance, ctx: Ctx, endsAt: number?)
	local l = Theme.label(
		root,
		"",
		56,
		UDim2.fromOffset(120, 70),
		UDim2.new(1, -16, 0, 12),
		{ title = true, anchor = Vector2.new(1, 0), color = Theme.ACCENT }
	)
	countdown(ctx, l, endsAt)
end

local function lobby(root: Frame, ctx: Ctx)
	Theme.label(root, "BALL TERRITORY", 72, UDim2.new(1, 0, 0, 90), UDim2.fromScale(0, 0.12), { title = true })
	local duel = Theme.button(
		root,
		"DUEL",
		UDim2.fromOffset(460, Theme.BIG_H),
		UDim2.fromScale(0.5, 0.52),
		Theme.MAIN,
		64,
		Vector2.new(0.5, 0.5)
	)
	Theme.label(
		root,
		"1 vs 1 · draft 3 balls",
		22,
		UDim2.fromOffset(460, 28),
		UDim2.new(0.5, 0, 0.52, Theme.BIG_H / 2 + 8),
		{ color = Theme.DIM, anchor = Vector2.new(0.5, 0) }
	)
	local ffa = Theme.button(
		root,
		"4 PLAYERS",
		UDim2.fromOffset(320, Theme.BTN_H),
		UDim2.new(0.5, 0, 0.52, Theme.BIG_H / 2 + 80),
		Theme.PANEL_LIGHT,
		40,
		Vector2.new(0.5, 0)
	)
	duel.Activated:Connect(function()
		ctx.act(Net.Action.queue, Net.Mode.duel)
	end)
	ffa.Activated:Connect(function()
		ctx.act(Net.Action.queue, Net.Mode.ffa)
	end)
end

local function queue(root: Frame, st: Net.State, ctx: Ctx)
	Theme.label(root, "Searching…", 64, UDim2.new(1, 0, 0, 80), UDim2.fromScale(0, 0.18), { title = true })
	local n = st.humans or 1
	Theme.label(
		root,
		string.format("%d player%s", n, if n == 1 then "" else "s"),
		40,
		UDim2.new(1, 0, 0, 50),
		UDim2.fromScale(0, 0.38)
	)
	local t = Theme.label(root, "", 32, UDim2.new(1, 0, 0, 40), UDim2.fromScale(0, 0.5), { color = Theme.DIM })
	countdown(ctx, t, st.endsAt, "Bots join in %ds")
	local cancel = Theme.button(
		root,
		"CANCEL",
		UDim2.fromOffset(300, Theme.BTN_H),
		UDim2.fromScale(0.5, 0.72),
		Theme.BAD,
		40,
		Vector2.new(0.5, 0)
	)
	cancel.Activated:Connect(function()
		ctx.act(Net.Action.cancel)
	end)
end

local function pick(root: Frame, st: Net.State, ctx: Ctx)
	local options: { number } = st.options or {}
	header(root, "Choose your element", if st.mode == "intro" then "Your first ball. More come later." else nil)
	timerBadge(root, ctx, st.endsAt)
	local taken: { number } = st.taken or {}
	local function send(e: number)
		ctx.act(Net.Action.pick, e)
	end
	if #options <= 4 then
		local r = row(root, UDim2.new(1, 0, 0, 290), UDim2.fromOffset(0, 160), nil, 14)
		for i, e in options do
			local c = card(r, e, UDim2.fromOffset(212, 280), {}, function()
				send(e)
			end)
			c.LayoutOrder = i
			if has(taken, e) then
				c.Active = false
				c.BackgroundTransparency = 0.6
			end
		end
	else
		local free = {}
		for _, e in options do
			if not has(taken, e) then
				table.insert(free, e)
			end
		end
		grid(root, free, {}, UDim2.new(1, -20, 1, -170), UDim2.fromOffset(10, 150), send)
	end
end

local function slots(parent: Instance, team: { number }, color: Color3, label: string, pos: UDim2, anchor: Vector2)
	local f = Theme.frame(parent, UDim2.fromOffset(300, 120), pos, Theme.PANEL, anchor)
	Theme.round(f)
	Theme.stroke(f, 4, color)
	Theme.label(f, label, 22, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 4), { color = color })
	for i = 1, Config.DUEL_SIZE do
		local x = 12 + (i - 1) * 96
		local e = team[i]
		if e then
			Theme.ballIcon(f, e, name(e), 64, UDim2.fromOffset(x + 8, 34))
			Theme.label(f, name(e), 14, UDim2.fromOffset(92, 20), UDim2.fromOffset(x - 4, 98), { outline = false })
		else
			local s = Theme.frame(f, UDim2.fromOffset(64, 64), UDim2.fromOffset(x + 8, 34), Theme.BG)
			Theme.round(s, 64)
			Theme.label(s, "?", 32, UDim2.fromScale(1, 1), nil, { color = Theme.DIM })
		end
	end
end

local function draft(root: Frame, st: Net.State, ctx: Ctx)
	local me = st.me or 0
	local teams: { { number } } = st.teams or { {}, {} }
	local mine, theirs = teams[me + 1] or {}, teams[2 - me] or {}
	local names: { string } = st.names or {}
	slots(root, mine, Theme.SEAT[me + 1], string.upper(names[me + 1] or "YOU"), UDim2.fromOffset(10, 10), Vector2.zero)
	slots(
		root,
		theirs,
		Theme.SEAT[2 - me],
		string.upper(names[2 - me] or "RIVAL"),
		UDim2.new(1, -10, 0, 10),
		Vector2.new(1, 0)
	)
	local myTurn = st.turn == me
	Theme.label(
		root,
		if myTurn then "YOUR PICK" else "Rival is picking…",
		44,
		UDim2.fromOffset(300, 60),
		UDim2.new(0.5, 0, 0, 14),
		{ title = true, anchor = Vector2.new(0.5, 0), color = if myTurn then Theme.ACCENT else Theme.DIM }
	)
	local t = Theme.label(
		root,
		"",
		48,
		UDim2.fromOffset(120, 56),
		UDim2.new(0.5, 0, 0, 74),
		{ title = true, anchor = Vector2.new(0.5, 0) }
	)
	countdown(ctx, t, st.endsAt)
	if not myTurn then
		return
	end
	local offer: { number } = st.offer or {}
	local r = row(root, UDim2.new(1, 0, 0, 290), UDim2.fromOffset(0, 140), nil, 14)
	for i, e in offer do
		card(r, e, UDim2.fromOffset(212, 280), theirs, function()
			ctx.act(Net.Action.draft, e)
		end).LayoutOrder = i
	end
	if st.any then
		local anyBtn = Theme.button(r, "ANY BALL\nFREE", UDim2.fromOffset(190, 280), nil, Theme.MAIN, 34)
		anyBtn.LayoutOrder = 10
		anyBtn.Activated:Connect(function()
			local used = {}
			for _, team in teams do
				for _, e in team do
					used[e] = true
				end
			end
			local free = {}
			for e = 0, Config.NEL - 1 do
				if not used[e] then
					table.insert(free, e)
				end
			end
			local overlay = Theme.frame(root, UDim2.fromScale(1, 1), nil, Theme.BG)
			overlay.ZIndex = 20
			Theme.label(overlay, "Any ball", 44, UDim2.new(1, 0, 0, 60), UDim2.fromOffset(0, 8), { title = true })
			local back = Theme.button(
				overlay,
				"BACK",
				UDim2.fromOffset(200, Theme.BTN_H),
				UDim2.fromOffset(10, 8),
				Theme.PANEL_LIGHT,
				36
			)
			back.Activated:Connect(function()
				overlay:Destroy()
			end)
			grid(
				overlay,
				free,
				theirs,
				UDim2.new(1, -20, 1, -(Theme.BTN_H + 24)),
				UDim2.fromOffset(10, Theme.BTN_H + 20),
				function(e)
					ctx.act(Net.Action.any, e)
				end
			)
		end)
	end
end

local function choose(root: Frame, st: Net.State, ctx: Ctx)
	header(root, "Choose your ball", nil)
	timerBadge(root, ctx, st.endsAt)
	local rival = st.rival or -1
	local foes = if rival >= 0 then { rival } else {}
	local text = if rival >= 0 and not st.blind then "Winner's ball: " .. name(rival) else "Winner's ball: hidden"
	Theme.label(
		root,
		text,
		30,
		UDim2.new(1, 0, 0, 36),
		UDim2.fromOffset(0, 80),
		{ color = if rival >= 0 then Theme.ACCENT else Theme.DIM }
	)
	local r = row(root, UDim2.new(1, 0, 0, 290), UDim2.fromOffset(0, 130), nil, 14)
	local left: { number } = st.left or {}
	for i, e in left do
		card(r, e, UDim2.fromOffset(212, 280), foes, function()
			ctx.act(Net.Action.choose, e)
		end).LayoutOrder = i
	end
end

local function ordinal(n: number): string
	return ({ "1ST", "2ND", "3RD", "4TH" })[n] or (n .. "TH")
end

local function crown(parent: Instance, pos: UDim2)
	local c = Theme.frame(parent, UDim2.fromOffset(150, 100), pos, Color3.new(), Vector2.new(0.5, 0))
	c.BackgroundTransparency = 1
	local gold = Color3.fromRGB(255, 205, 60)
	for i = 0, 2 do
		local p =
			Theme.frame(c, UDim2.fromOffset(46, 46), UDim2.fromOffset(52 * i + 24, 22), gold, Vector2.new(0.5, 0.5))
		p.Rotation = 45
		Theme.stroke(p, 3)
	end
	local base = Theme.frame(c, UDim2.fromOffset(150, 46), UDim2.fromOffset(0, 50), gold)
	Theme.stroke(base, 3)
end

local function result(root: Frame, st: Net.State, ctx: Ctx)
	local e = ctx.lastEnd
	local won = st.win == true
	local title = if won then "YOU WIN" else "YOU LOSE"
	local myPlace = 0
	if e and e.mode ~= "duel" then
		for i, p in e.places do
			if p.e == ctx.you then
				myPlace = i
			end
		end
		if e.mode == "ffa" and myPlace > 0 then
			title = ordinal(myPlace) .. " PLACE"
			won = myPlace == 1
		end
	elseif e and e.mode == "duel" and e.winner == -1 then
		title = "DRAW"
	end
	if won then
		crown(root, UDim2.new(0.5, 0, 0, 14))
	end
	Theme.label(
		root,
		title,
		84,
		UDim2.new(1, 0, 0, 100),
		UDim2.fromOffset(0, 116),
		{ title = true, color = if won then Theme.ACCENT else Theme.TEXT }
	)
	if e and e.mode == "duel" then
		Theme.label(
			root,
			string.format("Rounds  %d : %d", ctx.score[ctx.mySide + 1] or 0, ctx.score[2 - ctx.mySide] or 0),
			44,
			UDim2.new(1, 0, 0, 56),
			UDim2.fromOffset(0, 222)
		)
	end
	if e then
		local y = if e.mode == "duel" then 290 else 230
		for i, p in e.places do
			local seat = ctx.seats[p.e]
			local line =
				Theme.frame(root, UDim2.fromOffset(520, 52), UDim2.new(0.5, 0, 0, y), Theme.PANEL, Vector2.new(0.5, 0))
			Theme.round(line, 10)
			Theme.stroke(line, 3, Theme.SEAT[(if e.mode == "duel" and seat then seat.side else i - 1) % 4 + 1])
			Theme.label(line, ordinal(i), 28, UDim2.fromOffset(80, 52), nil, { title = true })
			Theme.label(
				line,
				string.format("%s · %s", seat and seat.name or "?", name(p.e)),
				24,
				UDim2.new(1, -240, 1, 0),
				UDim2.fromOffset(84, 0),
				{ align = Enum.TextXAlignment.Left }
			)
			Theme.label(
				line,
				string.format("%d%%", math.floor(p.pct + 0.5)),
				32,
				UDim2.fromOffset(110, 52),
				UDim2.new(1, -116, 0, 0),
				{ title = true, color = Theme.ACCENT }
			)
			y += 60
		end
	end
	local t = Theme.label(root, "", 26, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 1, -44), { color = Theme.DIM })
	countdown(ctx, t, st.endsAt, "Back to lobby in %ds")
end

function Menus.build(root: Frame, st: Net.State, ctx: Ctx)
	if st.ph == "lobby" then
		lobby(root, ctx)
	elseif st.ph == "queue" then
		queue(root, st, ctx)
	elseif st.ph == "pick" then
		pick(root, st, ctx)
	elseif st.ph == "draft" then
		draft(root, st, ctx)
	elseif st.ph == "choose" then
		choose(root, st, ctx)
	elseif st.ph == "wait" then
		Theme.label(
			root,
			"Waiting for a free arena…",
			56,
			UDim2.fromScale(1, 0.2),
			UDim2.fromScale(0, 0.35),
			{ title = true }
		)
		local c = Theme.button(
			root,
			"BACK",
			UDim2.fromOffset(300, Theme.BTN_H),
			UDim2.fromScale(0.5, 0.7),
			Theme.PANEL_LIGHT,
			40,
			Vector2.new(0.5, 0)
		)
		c.Activated:Connect(function()
			ctx.act(Net.Action.leave)
		end)
	elseif st.ph == "result" then
		result(root, st, ctx)
	end
end

return Menus
