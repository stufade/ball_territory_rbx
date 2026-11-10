--!strict
-- Full-screen menus by State.ph in the web look (drawTitle, drawLobby, drawPick, drawDraft, drawChoose, drawEnd) and
-- the Ball vs Ball card pick. Landscape first: nothing goes into the Roblox topbar corner (ctx.topbar). docs/ui.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Cheer = require("./Cheer")
local Matchup = require("./Matchup")
local Money = require("./Money")
local Reward = require("./Reward")
local Theme = require("./Theme")

local Menus = {}

export type Ctx = {
	act: (verb: string, arg: number?) -> (),
	timeLeft: (endsAt: number?) -> number,
	tickers: { () -> () }, -- 10 times a second
	frames: { (dt: number) -> () }, -- every frame
	seats: { [number]: Net.Seat }, -- by element id, last match
	you: number?,
	mySide: number,
	score: { number }, -- duel rounds won {side0, side1}
	rounds: number, -- duel rounds played
	lastEnd: Net.MatchEnd?,
	lastRound: Net.RoundEnd?,
	teams: { { number } },
	lost: { { number } },
	names: { string },
	topbar: Vector2, -- design px: keep left of x and above y free
	canvas: Vector2, -- design px
}

local TITLE, WORD, ABOUT = Config.TITLE, Config.WORD, Config.ABOUT
local V2 = Vector2.new
local TOP_MID = V2(0.5, 0)
local MID = V2(0.5, 0.5)

local function name(e: number): string
	return TITLE[e] or "?"
end

local function has(list: { number }?, e: number): boolean
	return list ~= nil and table.find(list, e) ~= nil
end

local function cap(s: string): string
	return string.sub(s, 1, 1) .. string.lower(string.sub(s, 2))
end

-- Top y for a box spanning x0.. that must stay clear of the topbar corner.
local function safeY(ctx: Ctx, x0: number, y: number): number
	return if x0 < ctx.topbar.X then math.max(y, ctx.topbar.Y) else y
end

local function sideName(ctx: Ctx, side: number): string
	if side == ctx.mySide then
		return "YOU"
	end
	return string.upper(ctx.names[side + 1] or "RIVAL")
end

local function countdown(ctx: Ctx, endsAt: number?, total: number, set: (left: number, k: number) -> ())
	local function tick()
		local left = ctx.timeLeft(endsAt)
		set(left, math.clamp(left / math.max(0.1, total), 0, 1))
	end
	table.insert(ctx.tickers, tick)
	tick()
end

-- Dots that run after a word: "PICKING", "PICKING.", ...
local function dots(ctx: Ctx, l: TextLabel, base: string)
	table.insert(ctx.tickers, function()
		l.Text = base .. string.rep(".", math.floor(os.clock() * 3) % 4)
	end)
end

local function pulse(ctx: Ctx, o: GuiObject, amount: number, speed: number)
	if Theme.reduced() then
		return
	end
	local s = Instance.new("UIScale")
	s.Parent = o
	table.insert(ctx.frames, function()
		s.Scale = 1 + amount * math.sin(os.clock() * speed)
	end)
end

local function names(list: { number }?): string
	if not list or #list == 0 then
		return "nobody"
	end
	local out = {}
	for _, e in list do
		table.insert(out, cap(name(e)))
	end
	return table.concat(out, ", ")
end

---------------------------------------------------------------- cards (Ball vs Ball pick 1 of 3)

local function card(
	parent: Instance,
	e: number,
	w: number,
	h: number,
	foes: { number },
	onPick: (() -> ())?
): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = Color3.fromHex("#15162e")
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(w, h)
	Theme.round(b, 12)
	local chipText, chipColor = Matchup.chip(e, foes, name)
	local st = Theme.stroke(b, 2.5, Theme.FRAME)
	st.Name = "Border"
	Theme.text(b, name(e), 34, UDim2.new(1, -16, 0, 40), UDim2.fromOffset(8, 12), { color = Theme.nameColor(e) })
	local box = Theme.frame(b, UDim2.fromOffset(112, 112), UDim2.new(0.5, 0, 0, 58), Theme.SLOT, TOP_MID)
	Theme.round(box, 10)
	Theme.stroke(box, 2, Theme.RING)
	local art = Theme.ball(box, e, 90, UDim2.fromScale(0.5, 0.5))
	if not Theme.reduced() then
		local s = Instance.new("UIScale")
		s.Parent = art
		local ph = e * 0.7
		art:SetAttribute("ph", ph)
	end
	Theme.text(b, "POWER: " .. (WORD[e] or ""), 22, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 176), {
		color = Theme.YELLOW_TXT,
	})
	Theme.text(
		b,
		ABOUT[e] or "",
		20,
		UDim2.new(1, -20, 0, h - 206 - (if chipText then 40 else 4)),
		UDim2.fromOffset(10, 204),
		{
			bold = true,
			color = Theme.DIM,
			wrap = true,
			stroke = 0,
		}
	)
	if chipText and chipColor then
		local chip = Theme.frame(b, UDim2.new(1, -12, 0, 36), UDim2.new(0.5, 0, 1, -6), chipColor, V2(0.5, 1))
		Theme.round(chip, 18)
		Theme.stroke(chip, 2, Theme.INK)
		Theme.text(chip, chipText, 22, UDim2.new(1, -12, 1, -4), UDim2.fromScale(0.5, 0.5), {
			anchor = MID,
			color = Theme.INK,
			stroke = 0,
		})
	end
	b.Parent = parent
	if onPick then
		Theme.press(b)
		b.Activated:Connect(onPick)
	end
	return b
end

-- Row of cards centred at y; tapping one marks it (yellow border, others dim) and calls pick(e).
local function cardRow(
	root: Instance,
	ctx: Ctx,
	elems: { number },
	y: number,
	foes: { number },
	pick: (number) -> (),
	disabled: { number }?,
	offText: string?
)
	local n = #elems
	local avail = ctx.canvas.X - 40
	local w = math.min(250, (avail - (n - 1) * 18) / math.max(1, n))
	local h = math.clamp(ctx.canvas.Y - y - 58, 260, 330)
	local total = n * w + (n - 1) * 18
	local x0 = (ctx.canvas.X - total) / 2
	local cards: { TextButton } = {}
	for i, e in elems do
		local off = disabled and has(disabled, e)
		local c: TextButton
		c = card(
			root,
			e,
			w,
			h,
			if off then {} else foes,
			if off
				then nil
				else function()
					for _, o in cards do
						local s = o:FindFirstChild("Border") :: UIStroke?
						if o == c and s then
							s.Color = Theme.YELLOW
							s.Thickness = 6
						else
							o.BackgroundTransparency = 0.5
						end
						o.Active = false
					end
					pick(e)
				end
		)
		c.Position = UDim2.fromOffset(x0 + (i - 1) * (w + 18), y)
		if off then
			c.BackgroundTransparency = 0.6
			for _, d in c:GetDescendants() do
				if d:IsA("ImageLabel") then
					d.ImageTransparency = 0.55
				end
			end
			Theme.text(c, offText or "TAKEN", 34, UDim2.new(1, 0, 0, 40), UDim2.fromScale(0.5, 0.42), {
				anchor = MID,
				color = Theme.MUTED,
			}).Rotation =
				-12
		end
		table.insert(cards, c)
		Theme.pop(c, 0.05 + i * 0.07, 0.5)
	end
	-- gentle bob of the ball art in the cards
	table.insert(ctx.frames, function()
		local t = os.clock()
		for _, c in cards do
			for _, d in c:GetDescendants() do
				local ph = d:GetAttribute("ph")
				if type(ph) == "number" then
					local s = d:FindFirstChildOfClass("UIScale")
					if s then
						s.Scale = 1 + 0.04 * math.sin(t * 4 + ph)
					end
				end
			end
		end
	end)
end

---------------------------------------------------------------- ball grid (web drawGrid)

type GridOpts = {
	x: number,
	y: number,
	w: number,
	h: number,
	cols: number,
	can: (e: number) -> boolean, -- can be picked now
	mark: (e: number) -> (Color3?, number?), -- ring colour and badge number of a taken ball
	foes: { number }, -- matchup tags against these
	onSelect: (e: number) -> (),
}

type Grid = { select: (e: number) -> (), refresh: () -> () }

local function grid(root: Instance, o: GridOpts): Grid
	local rows = math.ceil(Config.NEL / o.cols)
	local cw = math.min(o.w / o.cols, 96)
	local ch = math.min(o.h / rows, 96)
	local d = math.min(cw, ch) - 16
	local area = Theme.clear(
		root,
		UDim2.fromOffset(cw * o.cols, ch * rows),
		UDim2.fromOffset(o.x + (o.w - cw * o.cols) / 2, o.y)
	)
	local selected = -1
	type Cell = { btn: TextButton, art: ImageLabel, ring: Frame, ringStroke: UIStroke, sel: Frame, tags: Frame }
	local cells: { [number]: Cell } = {}
	local function refresh()
		for e, c in cells do
			local col, num = o.mark(e)
			local can = o.can(e)
			c.art.ImageTransparency = if can or (col and num) then 0 else 0.6
			-- the ring only marks a taken ball (whose by colour); matchups are the ▲/▼ pills
			c.ring.Visible = col ~= nil
			c.ringStroke.Color = col or Theme.RING
			c.sel.Visible = e == selected
			c.tags:ClearAllChildren()
			if can then
				Matchup.badges(c.tags, e, o.foes, d)
			end
			local badge = c.btn:FindFirstChild("Badge")
			if badge then
				badge:Destroy()
			end
			if col and num then
				local b = Theme.disc(c.btn, 26, col, UDim2.new(0.5, d * 0.36, 0.5, -d * 0.36))
				b.Name = "Badge"
				b.ZIndex = 5
				Theme.text(b, tostring(num), 20, UDim2.fromScale(1, 1), nil, { color = Theme.INK, stroke = 0, z = 6 })
			end
		end
	end
	for e = 0, Config.NEL - 1 do
		local i = e % o.cols
		local j = e // o.cols
		local btn = Instance.new("TextButton")
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BackgroundTransparency = 1
		btn.Size = UDim2.fromOffset(cw, ch)
		btn.Position = UDim2.fromOffset(i * cw, j * ch)
		btn.Parent = area
		local sel = Theme.disc(btn, d + 22, Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.5), 0.55)
		local ring = Theme.ring(btn, d + 10, Theme.GOOD, 5, UDim2.fromScale(0.5, 0.5))
		local art = Theme.ball(btn, e, d, UDim2.fromScale(0.5, 0.5))
		art.ZIndex = 3
		local tags = Theme.clear(btn, UDim2.fromScale(1, 1))
		tags.ZIndex = 6
		cells[e] = {
			btn = btn,
			art = art,
			tags = tags,
			ring = ring,
			ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke,
			sel = sel,
		}
		Theme.press(btn)
		btn.Activated:Connect(function()
			selected = e
			refresh()
			o.onSelect(e)
		end)
		Theme.pop(btn, 0.02 * e, 0.3)
	end
	refresh()
	return {
		select = function(e: number)
			selected = e
			refresh()
		end,
		refresh = refresh,
	}
end

-- Web drawInfo: ball name, power, about, strong/weak 1v1 lists.
local function info(parent: Instance, x: number, y: number, w: number, h: number, duel: boolean): (number) -> ()
	local f = Theme.frame(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), Theme.PANEL)
	Theme.round(f, 10)
	local function show(e: number)
		f:ClearAllChildren()
		Theme.round(f, 10)
		if e < 0 then
			Theme.text(
				f,
				"Tap a ball to see its power and rivals.",
				22,
				UDim2.new(1, -24, 1, 0),
				UDim2.fromOffset(12, 0),
				{
					bold = true,
					color = Theme.DIM,
					stroke = 0,
				}
			)
			return
		end
		local stripe = Theme.frame(f, UDim2.new(0, 10, 1, 0), nil, Look.bright(e))
		Theme.round(stripe, 5)
		local tx = 26
		Theme.text(f, name(e), 30, UDim2.fromOffset(200, 34), UDim2.fromOffset(tx, 6), {
			color = Theme.nameColor(e),
			align = Enum.TextXAlignment.Left,
		})
		Theme.text(f, "Power: " .. (WORD[e] or ""), 22, UDim2.new(1, -240, 0, 30), UDim2.fromOffset(tx + 210, 9), {
			align = Enum.TextXAlignment.Left,
		})
		Theme.text(f, ABOUT[e] or "", 20, UDim2.new(1, -tx - 12, 0, 46), UDim2.fromOffset(tx, 42), {
			bold = true,
			color = Theme.DIM,
			wrap = true,
			stroke = 0,
			align = Enum.TextXAlignment.Left,
		})
		if not duel then
			return
		end
		Theme.text(
			f,
			"Strong 1v1 vs " .. names(Config.DSTRONG[e]),
			20,
			UDim2.new(1, -tx - 12, 0, 24),
			UDim2.fromOffset(tx, 90),
			{
				bold = true,
				color = Theme.GOOD_TXT,
				stroke = 0,
				align = Enum.TextXAlignment.Left,
			}
		)
		Theme.text(
			f,
			"Weak 1v1 vs " .. names(Config.DWEAK[e]),
			20,
			UDim2.new(1, -tx - 12, 0, 24),
			UDim2.fromOffset(tx, 116),
			{
				bold = true,
				color = Theme.BAD_TXT,
				stroke = 0,
				align = Enum.TextXAlignment.Left,
			}
		)
	end
	show(-1)
	return show
end

---------------------------------------------------------------- screens

local function title(
	root: Instance,
	ctx: Ctx,
	text: string,
	size: number,
	w: number,
	y: number,
	color: Color3?
): TextLabel
	local x0 = (ctx.canvas.X - w) / 2
	local t = Theme.text(root, text, size, UDim2.fromOffset(w, size + 10), UDim2.new(0.5, 0, 0, safeY(ctx, x0, y)), {
		anchor = TOP_MID,
		color = color,
		stroke = math.floor(size / 9),
	})
	Theme.pop(t, 0, 0.5)
	return t
end

-- Header "TEXT - 9" with the live countdown, and a timer bar at the bottom.
local function timedTitle(root: Frame, ctx: Ctx, text: string, endsAt: number?, total: number, y: number)
	local t = title(root, ctx, text, 46, 640, y)
	local fill = Theme.timeBar(root, 420, 10, UDim2.new(0.5, 0, 1, -40), TOP_MID)
	countdown(ctx, endsAt, total, function(left, k)
		t.Text = string.format("%s - %d", text, math.ceil(left))
		fill.Size = UDim2.fromScale(k, 1)
	end)
	return t
end

-- Grid + info + PICK button: the duel draft and the 4-player pick.
local function gridPicker(
	root: Frame,
	ctx: Ctx,
	x: number,
	y: number,
	w: number,
	h: number,
	opts: {
		can: (number) -> boolean,
		mark: (number) -> (Color3?, number?),
		foes: { number },
		send: (number) -> (),
		active: boolean,
		waitText: string?,
		duel: boolean,
	}
): Grid
	local infoH, btnW = if opts.duel then 150 else 100, 250
	local g: Grid
	local show = info(root, x, y + h - infoH, w - btnW - 14, infoH, opts.duel)
	local pickBtn: TextButton? = nil
	local chosen = -1
	local function setBtn()
		local b = pickBtn
		if not b then
			return
		end
		local ok = chosen >= 0 and opts.can(chosen)
		local label = b:FindFirstChild("Label") :: TextLabel?
		b.BackgroundColor3 = if ok then Look.bright(chosen) else Theme.SLOT
		local lip = b:FindFirstChildOfClass("Frame")
		if lip then
			lip.BackgroundColor3 = b.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.35)
		end
		if label then
			label.Text = if ok then "PICK " .. name(chosen) else "TAP A BALL"
			label.TextColor3 = if ok then Theme.onColor(b.BackgroundColor3) else Theme.MUTED
			local s = label:FindFirstChildOfClass("UIStroke")
			if s then
				s.Enabled = label.TextColor3 ~= Theme.INK
			end
		end
	end
	g = grid(root, {
		x = x,
		y = y,
		w = w,
		h = h - infoH - 10,
		cols = 9,
		can = opts.can,
		mark = opts.mark,
		foes = opts.foes,
		onSelect = function(e)
			chosen = e
			show(e)
			setBtn()
		end,
	})
	if opts.active then
		local b = Theme.button(
			root,
			"TAP A BALL",
			UDim2.fromOffset(btnW, Theme.BTN_H),
			UDim2.fromOffset(x + w - btnW, y + h - infoH / 2 - Theme.BTN_H / 2),
			Theme.SLOT,
			nil,
			34
		)
		pickBtn = b
		b.Activated:Connect(function()
			if chosen >= 0 and opts.can(chosen) then
				opts.send(chosen)
				b.Active = false
			end
		end)
		setBtn()
		Theme.pop(b, 0.3, 0.5)
	else
		local wt = Theme.text(
			root,
			opts.waitText or "WAIT",
			30,
			UDim2.fromOffset(btnW, Theme.BTN_H),
			UDim2.fromOffset(x + w - btnW, y + h - infoH / 2 - Theme.BTN_H / 2),
			{
				color = Theme.DIM,
			}
		)
		dots(ctx, wt, opts.waitText or "WAIT")
	end
	return g
end

local function pickStarter(root: Frame, st: Net.State, ctx: Ctx)
	Theme.backdrop(root)
	local t = timedTitle(root, ctx, "CHOOSE YOUR ELEMENT", st.endsAt, 8, 14)
	local y = t.Position.Y.Offset + 60
	Theme.text(root, "Your first ball. More come later.", 22, UDim2.fromOffset(500, 28), UDim2.new(0.5, 0, 0, y), {
		anchor = TOP_MID,
		bold = true,
		color = Theme.DIM,
		stroke = 0,
	})
	local options: { number } = st.options or {}
	if #options > 5 then
		-- TEST_ALL_BALLS: all 27 do not fit as cards, the grid of the 4-player pick takes them
		local w = math.min(ctx.canvas.X - 40, 860)
		gridPicker(root, ctx, (ctx.canvas.X - w) / 2, y + 36, w, ctx.canvas.Y - y - 36 - 50, {
			can = function(e)
				return has(options, e)
			end,
			mark = function(_)
				return nil, nil
			end,
			foes = {},
			send = function(e)
				ctx.act(Net.Action.pick, e)
			end,
			active = true,
			duel = false,
		})
		return
	end
	cardRow(root, ctx, options, y + 40, {}, function(e)
		ctx.act(Net.Action.pick, e)
	end, st.taken)
	Theme.text(
		root,
		"Tap a ball. Time is up: a random one goes.",
		20,
		UDim2.fromOffset(500, 24),
		UDim2.new(0.5, 0, 1, -26),
		{
			anchor = TOP_MID,
			bold = true,
			color = Theme.DIM,
			stroke = 0,
		}
	)
end

local function pickFfa(root: Frame, st: Net.State, ctx: Ctx)
	Theme.backdrop(root)
	local options: { number } = st.options or {}
	local taken: { number } = st.taken or {}
	local t = timedTitle(root, ctx, "CHOOSE YOUR BALL", st.endsAt, 10, 10)
	local y = t.Position.Y.Offset + 54
	local w = math.min(ctx.canvas.X - 40, 860)
	gridPicker(root, ctx, (ctx.canvas.X - w) / 2, y, w, ctx.canvas.Y - y - 50, {
		can = function(e)
			return has(options, e) and not has(taken, e)
		end,
		mark = function(e)
			return if has(taken, e) then Theme.MUTED else nil, nil
		end,
		foes = {},
		send = function(e)
			ctx.act(Net.Action.pick, e)
		end,
		active = true,
		duel = false,
	})
end

-- Team panel of the draft (web drawSides): name and three slots.
local function teamPanel(
	root: Instance,
	ctx: Ctx,
	side: number,
	team: { number },
	lost: { number },
	active: boolean,
	x: number,
	y: number,
	w: number
)
	local mine = side == ctx.mySide
	local f = Theme.frame(
		root,
		UDim2.fromOffset(w, 104),
		UDim2.fromOffset(x, y),
		if active then Theme.PANEL_HI else Theme.PANEL
	)
	Theme.round(f, 12)
	if active then
		Theme.stroke(f, 4, Theme.YELLOW)
	end
	Theme.text(f, sideName(ctx, side), 24, UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 4), {
		color = if mine then Theme.YELLOW_TXT else Theme.TEXT,
	})
	for j = 1, Config.DUEL_SIZE do
		local cx = w / 2 + (j - 2) * 74
		local e = team[j]
		if e then
			local b = Theme.ball(f, e, 52, UDim2.fromOffset(cx, 68))
			if has(lost, e) then
				b.ImageTransparency = 0.6
				for _, rot in { 45, -45 } do
					local l = Theme.frame(b, UDim2.fromOffset(50, 7), UDim2.fromScale(0.5, 0.5), Theme.BAD, MID)
					l.Rotation = rot
				end
			end
		else
			Theme.ring(f, 52, Theme.RING, 4, UDim2.fromOffset(cx, 68))
			Theme.text(f, tostring(j), 24, UDim2.fromOffset(40, 40), UDim2.fromOffset(cx, 68), {
				anchor = MID,
				color = Color3.fromHex("#5a5f94"),
				stroke = 0,
			})
		end
	end
	if active then
		Theme.pop(f, 0, 0.85)
	end
	return f
end

local function draft(root: Frame, st: Net.State, ctx: Ctx)
	Theme.backdrop(root)
	local cv = ctx.canvas
	local me = st.me or 0
	ctx.mySide = me
	local teams: { { number } } = st.teams or { {}, {} }
	local mine, theirs = teams[me + 1] or {}, teams[2 - me] or {}
	local myTurn = st.turn == me
	local offer: { number } = st.offer or {}
	-- T2.2: own balls (nil = all); the offer may hold a ball outside them when the own ones ran out
	local own: { number }? = st.own
	-- TEST_ALL_BALLS gives an "any ball" for every pick: then the whole grid is open from the start
	local anyLeft = st.anyLeft or (if st.any then 1 else 0)
	local picksLeft = Config.DUEL_SIZE - #mine
	local anyAlways = st.any == true and anyLeft > 1 and anyLeft >= picksLeft
	local anyMode = anyAlways
	-- left column: both teams, then the free "any ball"
	local lw = 270
	local ly = math.max(ctx.topbar.Y, 12)
	teamPanel(root, ctx, me, mine, {}, myTurn, 12, ly, lw)
	teamPanel(root, ctx, 1 - me, theirs, {}, not myTurn, 12, ly + 114, lw)
	Theme.text(root, "PICKS 1-2-2-1", 22, UDim2.fromOffset(lw, 26), UDim2.fromOffset(12, ly + 222), {
		bold = true,
		color = Theme.DIM,
		stroke = 0,
	})
	-- right: title, status, grid, info, pick
	local x = lw + 28
	local w = cv.X - x - 14
	local t = Theme.text(root, "DUEL DRAFT", 40, UDim2.fromOffset(360, 46), UDim2.fromOffset(x + w / 2, 8), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
		stroke = 5,
	})
	Theme.pop(t, 0, 0.5)
	local status = Theme.text(root, "", 32, UDim2.fromOffset(w - 40, 38), UDim2.fromOffset(x + w / 2, 54), {
		anchor = TOP_MID,
		color = if myTurn then Theme.YELLOW_TXT else Theme.TEXT,
	})
	if myTurn then
		pulse(ctx, status, 0.05, 8)
	end
	local fill = Theme.timeBar(root, math.min(420, w - 40), 8, UDim2.fromOffset(x + w / 2, 96), TOP_MID)
	local base = if myTurn then "YOUR PICK!" else sideName(ctx, 1 - me) .. " IS PICKING"
	countdown(ctx, st.endsAt, 15, function(left, k)
		fill.Size = UDim2.fromScale(k, 1)
		status.Text = if myTurn
			then string.format("%s  %d", base, math.ceil(left))
			else base .. string.rep(".", math.floor(os.clock() * 3) % 4)
	end)
	local g: Grid
	g = gridPicker(root, ctx, x, 112, w, cv.Y - 112 - 14, {
		can = function(e)
			if not myTurn or has(mine, e) or has(theirs, e) then
				return false
			end
			return has(offer, e) or (anyMode and (own == nil or has(own, e)))
		end,
		mark = function(e)
			local i = table.find(mine, e)
			if i then
				return Theme.YELLOW, i
			end
			local j = table.find(theirs, e)
			if j then
				return Theme.DIM, j
			end
			return nil, nil
		end,
		foes = theirs,
		send = function(e)
			ctx.act(if anyMode and not has(offer, e) then Net.Action.any else Net.Action.draft, e)
		end,
		active = myTurn,
		waitText = "WAIT",
		duel = true,
	})
	local legendY = ly + 270
	if myTurn and st.any and not anyAlways then
		legendY += Theme.BTN_H + 16
		local any = Theme.button(
			root,
			"ANY BALL",
			UDim2.fromOffset(lw, Theme.BTN_H),
			UDim2.fromOffset(12, ly + 270),
			Theme.PURPLE,
			nil,
			36
		)
		local free = Theme.text(any, "FREE · ONCE", 20, UDim2.fromOffset(160, 24), UDim2.new(0.5, 0, 0, -14), {
			anchor = TOP_MID,
			color = Theme.YELLOW_TXT,
			z = 4,
		})
		free.ZIndex = 4
		Theme.pop(any, 0.25, 0.5)
		any.Activated:Connect(function()
			anyMode = not anyMode
			local l = any:FindFirstChild("Label") :: TextLabel?
			if l then
				l.Text = if anyMode then "OFFER ONLY" else "ANY BALL"
			end
			g.refresh()
		end)
	elseif anyAlways then
		Theme.text(root, "TEST: ALL 27 BALLS", 22, UDim2.fromOffset(lw, 26), UDim2.fromOffset(12, legendY), {
			color = Theme.YELLOW_TXT,
		})
		legendY += 36
	end
	if own then
		local mineText = Theme.text(
			root,
			string.format("YOUR BALLS: %d / %d", #own, Config.NEL),
			22,
			UDim2.fromOffset(lw, 26),
			UDim2.fromOffset(12, legendY),
			{ color = Theme.YELLOW_TXT }
		)
		mineText.Name = "OwnCount"
		legendY += 36
	end
	if #theirs > 0 then
		Matchup.legend(root, "", UDim2.fromOffset(12, legendY), Vector2.zero)
		Theme.text(
			root,
			"vs " .. sideName(ctx, 1 - me) .. "'S PICKS",
			20,
			UDim2.fromOffset(lw, 24),
			UDim2.fromOffset(12, legendY + 30),
			{ bold = true, color = Theme.DIM, stroke = 0, align = Enum.TextXAlignment.Left }
		)
	end
end

-- The round winner stays with its ball: nothing to choose, just watch the loser pick.
local function keepScreen(root: Frame, st: Net.State, ctx: Ctx, keep: number)
	Theme.backdrop(root, 0.12)
	local me = st.me or ctx.mySide
	local cv = ctx.canvas
	local top = safeY(ctx, (cv.X - 640) / 2, 24)
	Theme.text(root, "YOU WON THE ROUND", 26, UDim2.fromOffset(400, 32), UDim2.new(0.5, 0, 0, top), {
		anchor = TOP_MID,
		color = Theme.GOOD_TXT,
	})
	local t = Theme.text(
		root,
		"YOU KEEP " .. name(keep),
		54,
		UDim2.fromOffset(700, 62),
		UDim2.new(0.5, 0, 0, top + 34),
		{ anchor = TOP_MID, color = Theme.nameColor(keep), stroke = 6 }
	)
	Theme.pop(t, 0, 0.6)
	local cy = top + 34 + 62 + 100
	Theme.disc(root, 196, Theme.YELLOW, UDim2.fromOffset(cv.X / 2, cy), 0.8)
	local art = Theme.ball(root, keep, 170, UDim2.fromOffset(cv.X / 2, cy))
	Theme.pop(art, 0.1, 0.4)
	pulse(ctx, art, 0.04, 4)
	local wait = Theme.text(root, "", 32, UDim2.fromOffset(700, 40), UDim2.new(0.5, 0, 0, cy + 110), {
		anchor = TOP_MID,
		color = Theme.TEXT,
	})
	local base = sideName(ctx, 1 - me) .. " IS CHOOSING"
	local fill = Theme.timeBar(root, 420, 10, UDim2.new(0.5, 0, 0, cy + 160), TOP_MID)
	countdown(ctx, st.endsAt, 10, function(left, k)
		fill.Size = UDim2.fromScale(k, 1)
		wait.Text = string.format("%s%s  %d", base, string.rep(".", math.floor(os.clock() * 3) % 4), math.ceil(left))
	end)
end

local function choose(root: Frame, st: Net.State, ctx: Ctx)
	local me = st.me or ctx.mySide
	ctx.mySide = me
	local keep = st.keep or -1
	if keep >= 0 and #(st.left or {}) == 0 then
		keepScreen(root, st, ctx, keep)
		return
	end
	Theme.backdrop(root, 0.12)
	local t = timedTitle(root, ctx, "CHOOSE YOUR BALL", st.endsAt, 10, 14)
	local y = t.Position.Y.Offset + 58
	local rival = st.rival or -1
	local foes = if rival >= 0 and not st.blind then { rival } else {}
	local line = Theme.clear(root, UDim2.fromOffset(700, 40), UDim2.new(0.5, 0, 0, y), TOP_MID)
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.Padding = UDim.new(0, 10)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = line
	local function piece(text: string, color: Color3, order: number)
		local l = Theme.text(line, text, 26, UDim2.fromOffset(10, 34), nil, { color = color })
		l.AutomaticSize = Enum.AutomaticSize.X
		l.TextScaled = false
		l.TextSize = 26
		l.LayoutOrder = order
	end
	piece(`ROUND {ctx.rounds + 1}  ·`, Theme.DIM, 1)
	if rival >= 0 and not st.blind then
		piece(sideName(ctx, 1 - me) .. " STAYS WITH", Theme.DIM, 2)
		local holder = Theme.clear(line, UDim2.fromOffset(40, 40))
		holder.LayoutOrder = 3
		Theme.ball(holder, rival, 36, UDim2.fromScale(0.5, 0.5))
		piece(name(rival), Theme.nameColor(rival), 4)
	else
		piece(sideName(ctx, 1 - me) .. "'S BALL IS HIDDEN", Theme.DIM, 2)
	end
	local lost: { number } = (st.lost or ctx.lost)[me + 1] or {}
	local left: { number } = st.left or {}
	local team: { number } = (st.teams or ctx.teams)[me + 1] or {}
	-- show the whole team: lost balls as crossed-out cards
	local all = if #team > 0 then team else left
	cardRow(root, ctx, all, y + 50, foes, function(e)
		ctx.act(Net.Action.choose, e)
	end, lost, "OUT")
	Theme.text(
		root,
		"Tap a ball. Time is up: a random one goes.",
		20,
		UDim2.fromOffset(500, 24),
		UDim2.new(0.5, 0, 1, -26),
		{
			anchor = TOP_MID,
			bold = true,
			color = Theme.DIM,
			stroke = 0,
		}
	)
end

local function waitScreen(root: Frame, ctx: Ctx)
	Theme.backdrop(root)
	local l = Theme.text(
		root,
		"WAITING FOR A FREE ARENA",
		40,
		UDim2.fromOffset(700, 50),
		UDim2.fromScale(0.5, 0.4),
		{ anchor = MID }
	)
	dots(ctx, l, "WAITING FOR A FREE ARENA")
	local c = Theme.button(
		root,
		"BACK",
		UDim2.fromOffset(260, Theme.BTN_H),
		UDim2.new(0.5, 0, 1, -24),
		Theme.SLOT,
		nil,
		38,
		V2(0.5, 1)
	)
	c.Activated:Connect(function()
		ctx.act(Net.Action.leave)
	end)
end

---------------------------------------------------------------- result (web drawEnd)

local function ordinal(n: number): string
	return ({ "1ST", "2ND", "3RD", "4TH" })[n] or (n .. "TH")
end

local rays, burst, confetti = Cheer.rays, Cheer.burst, Cheer.confetti

local function result(root: Frame, st: Net.State, ctx: Ctx)
	local cv = ctx.canvas
	local en = ctx.lastEnd
	local duel = en ~= nil and en.mode == "duel"
	-- winner's ball: the duel side's last round ball, or the first place
	local we = ctx.you or 0
	local winSide = -1
	if en and duel then
		winSide = en.winner
		local r = ctx.lastRound
		if r and winSide >= 0 then
			we = if winSide == 0 then r.a else r.b
		elseif en.places[1] then
			we = en.places[1].e
		end
	elseif en and en.places[1] then
		we = en.places[1].e
	end
	local bg = Theme.frame(root, UDim2.fromScale(1, 1), nil, Theme.BG:Lerp(Look.col(we), 0.2))
	bg.BackgroundTransparency = 1
	TweenService:Create(bg, TweenInfo.new(0.35), { BackgroundTransparency = 0.04 }):Play()
	local cx, cy = math.max(250, cv.X * 0.3), 300
	rays(root, ctx, we, cx, cy, 620)
	local ball = Theme.ball(root, we, 210, UDim2.fromOffset(cx, cy))
	Theme.pop(ball, 0.3, 0)
	task.delay(0.55, function()
		if root.Parent then
			burst(root, ctx, we, cx, cy)
		end
	end)
	local crown = Theme.crown(root, 150, UDim2.fromOffset(cx, -120))
	TweenService:Create(
		crown,
		TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out, 0, false, 1.0),
		{ Position = UDim2.fromOffset(cx, cy - 150) }
	):Play()
	-- headline
	local myPlace = 0
	if en then
		for i, p in en.places do
			if p.e == ctx.you then
				myPlace = i
			end
		end
	end
	local won = st.win == true
	local head = if duel
		then (if winSide < 0 then "DRAW!" elseif won then "DUEL WON!" else "DUEL LOST")
		elseif myPlace == 1 or (myPlace == 0 and won) then "YOU WIN!"
		elseif myPlace > 0 and en and #en.places > 2 then "YOU PLACED " .. ordinal(myPlace)
		else (if won then "YOU WIN!" else "YOU LOSE")
	local happy = won or (not duel and myPlace == 1)
	local rx = cv.X * 0.56
	local rw = cv.X - rx - 20
	local h = title(root, ctx, head, 64, rw, 12, if happy then Theme.YELLOW_TXT else Theme.TEXT)
	h.Position = UDim2.fromOffset(rx + rw / 2, safeY(ctx, rx, 12))
	local champ = Theme.text(
		root,
		if duel then "CHAMPION" else "1ST PLACE",
		72,
		UDim2.fromOffset(rw, 80),
		UDim2.fromOffset(rx + rw / 2, 96),
		{
			anchor = TOP_MID,
			color = Theme.YELLOW,
			stroke = 8,
		}
	)
	Theme.pop(champ, 1.2, 0.3)
	local who = ""
	if en and en.places[1] then
		local seat = ctx.seats[we]
		who = if we == ctx.you
			then "YOU"
			elseif seat and seat.userId <= 0 and not duel then `BOT {seat.side + 1}`
			elseif seat then string.upper(seat.name)
			else ""
	end
	Theme.text(
		root,
		name(we) .. (if who ~= "" then "  ·  " .. who else ""),
		32,
		UDim2.fromOffset(rw, 38),
		UDim2.fromOffset(rx + rw / 2, 176),
		{
			anchor = TOP_MID,
			color = Theme.nameColor(we),
			stroke = 4,
		}
	)
	-- rows: duel sides or ffa places
	local y = 228
	if duel and en then
		for i, side in { 0, 1 } do
			local mine = side == ctx.mySide
			local row = Theme.frame(
				root,
				UDim2.fromOffset(rw, 96),
				UDim2.fromOffset(rx, y),
				if mine then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			)
			row.BackgroundTransparency = if mine then 0.84 else 0.65
			Theme.round(row, 10)
			if mine then
				Theme.stroke(row, 3, Theme.FRAME)
			end
			if en.winner == side then
				Theme.crown(row, 52, UDim2.fromOffset(34, 48))
			end
			Theme.text(row, sideName(ctx, side), 28, UDim2.fromOffset(rw * 0.45, 34), UDim2.fromOffset(66, 12), {
				color = if mine then Theme.YELLOW_TXT else Theme.TEXT,
				align = Enum.TextXAlignment.Left,
			})
			local wins = ctx.score[side + 1] or 0
			Theme.text(
				row,
				string.format("%d ROUND%s WON", wins, if wins == 1 then "" else "S"),
				20,
				UDim2.fromOffset(rw * 0.45, 26),
				UDim2.fromOffset(66, 52),
				{
					color = Theme.DIM,
					align = Enum.TextXAlignment.Left,
				}
			)
			local team: { number } = ctx.teams[side + 1] or {}
			local lost: { number } = ctx.lost[side + 1] or {}
			for j, e in team do
				local b = Theme.ball(row, e, 50, UDim2.new(1, -40 - (#team - j) * 60, 0.5, 0))
				if has(lost, e) then
					b.ImageTransparency = 0.55
					for _, rot in { 45, -45 } do
						local l = Theme.frame(b, UDim2.fromOffset(50, 7), UDim2.fromScale(0.5, 0.5), Theme.BAD, MID)
						l.Rotation = rot
					end
				end
			end
			row.Position = UDim2.fromOffset(cv.X + 20, y)
			TweenService:Create(
				row,
				TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 1.4 + i * 0.15),
				{ Position = UDim2.fromOffset(rx, y) }
			):Play()
			y += 106
		end
	elseif en then
		local top = math.max(1, en.places[1] and en.places[1].pct or 1)
		for i, p in en.places do
			local mine = p.e == ctx.you
			local row = Theme.frame(
				root,
				UDim2.fromOffset(rw, 60),
				UDim2.fromOffset(rx, y),
				if mine then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			)
			row.BackgroundTransparency = if mine then 0.84 else 0.65
			Theme.round(row, 10)
			if mine then
				Theme.stroke(row, 3, Theme.FRAME)
			end
			local m = Theme.disc(row, 40, Theme.MEDAL[i] or Theme.MUTED, UDim2.fromOffset(32, 30))
			Theme.text(m, tostring(i), 26, UDim2.fromScale(1, 1), nil, { color = Theme.INK, stroke = 0 })
			Theme.ball(row, p.e, 42, UDim2.fromOffset(84, 30))
			local bw = math.max(8, (rw - 300) * p.pct / top)
			local bar = Theme.frame(row, UDim2.fromOffset(0, 32), UDim2.fromOffset(114, 14), Look.bright(p.e))
			Theme.round(bar, 6)
			TweenService:Create(
				bar,
				TweenInfo.new(0.6, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 1.6 + i * 0.12),
				{ Size = UDim2.fromOffset(bw, 32) }
			):Play()
			Theme.text(
				row,
				string.format("%d%%", math.floor(p.pct + 0.5)),
				28,
				UDim2.fromOffset(80, 34),
				UDim2.fromOffset(122 + bw, 13),
				{
					align = Enum.TextXAlignment.Left,
				}
			)
			local seat = ctx.seats[p.e]
			Theme.text(
				row,
				if mine
					then "YOU"
					elseif seat and seat.userId <= 0 then `BOT {seat.side + 1}`
					elseif seat then string.upper(seat.name)
					else name(p.e),
				22,
				UDim2.fromOffset(120, 30),
				UDim2.new(1, -12, 0, 15),
				{
					anchor = V2(1, 0),
					color = Theme.DIM,
					align = Enum.TextXAlignment.Right,
				}
			)
			row.Position = UDim2.fromOffset(cv.X + 20, y)
			TweenService:Create(
				row,
				TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, 1.4 + i * 0.12),
				{ Position = UDim2.fromOffset(rx, y) }
			):Play()
			y += 68
		end
	end
	-- my stats
	if en then
		for _, p in en.places do
			if p.e == ctx.you then
				Theme.text(
					root,
					string.format("Powers: %d   KOs: %d", p.powers, p.kills),
					22,
					UDim2.fromOffset(rw, 28),
					UDim2.fromOffset(rx + rw / 2, y + 4),
					{
						anchor = TOP_MID,
						bold = true,
						color = Theme.TEXT,
					}
				)
			end
		end
	end
	-- T2.2: XP of the match, doubled while the boost runs
	if st.xp and st.xp > 0 then
		local boosted = (st.xpMult or 1) > 1
		-- M3.1: the multiplier may be 1.5 (friend) or 3 (boost and friend)
		local m = math.floor((st.xpMult or 2) * 10 + 0.5) / 10
		local xpText = Theme.text(
			root,
			string.format("+%d XP%s", st.xp, if boosted then `  ({m}x)` else ""),
			34,
			UDim2.fromOffset(400, 40),
			UDim2.fromOffset(cx, cy + 128),
			{ anchor = TOP_MID, color = if boosted then Theme.GOOD_TXT else Theme.YELLOW_TXT, stroke = 4 }
		)
		xpText.Name = "Xp"
		Theme.pop(xpText, 1.9, 0.3)
	end
	-- M3.1: coins of the match (friend bonus, streak), or why there are none (AFK)
	Money.result(root, st, cx, cy + 168)
	local back = Theme.text(root, "", 22, UDim2.fromOffset(400, 28), UDim2.new(0, cx, 1, -34), {
		anchor = TOP_MID,
		color = Theme.DIM,
		bold = true,
	})
	countdown(ctx, st.endsAt, 5, function(left)
		back.Text = string.format("Back to the lobby in %ds", math.ceil(left))
	end)
	if happy then
		confetti(root, ctx)
	end
end

function Menus.build(root: Frame, st: Net.State, ctx: Ctx)
	-- lobby and queue: UI/Plaza (compact buttons on the plaza, M1.6)
	if st.ph == "pick" then
		if st.mode == "ffa" then
			pickFfa(root, st, ctx)
		else
			pickStarter(root, st, ctx)
		end
	elseif st.ph == "draft" then
		draft(root, st, ctx)
	elseif st.ph == "choose" then
		choose(root, st, ctx)
	elseif st.ph == "wait" then
		waitScreen(root, ctx)
	elseif st.ph == "result" then
		result(root, st, ctx)
	elseif st.ph == "reward" then
		Reward.build(root, st, ctx :: any)
	end
end

return Menus
