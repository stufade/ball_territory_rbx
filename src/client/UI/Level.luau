--!strict
-- T2.2 on the plaza: a compact level bar at the top middle ("LV 2", XP bar, "120/200 XP"), the "2x XP 14:32"
-- badge next to it while the boost runs, and NEW BALL! for a level up with a ball (card flip, rays, confetti).
-- Data: the Profile remote (Net.ProfileView). Shown with the plaza (State lobby/queue), NEW BALL! only in the lobby.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Cheer = require("./Cheer")
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Reward = require("./Reward")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
local TOP_MID = V2(0.5, 0)

export type Ctx = { canvas: Vector2, topbar: Vector2 }

export type Level = {
	root: Frame,
	pop: Frame,
	ctx: Ctx,
	fx: Cheer.Ctx,
	view: Net.ProfileView?,
	st: Net.State?,
	news: { Net.LevelUp },
	showing: boolean,
	fill: Frame?,
	label: TextLabel?,
	timer: TextLabel?,
	badge: Frame?,
	lastLevel: number,
}

local Level = {}

local function fmt(s: number): string
	s = math.max(0, math.ceil(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function onPlaza(l: Level): boolean
	local st = l.st
	return st ~= nil and (st.ph == "lobby" or st.ph == "queue")
end

-- Bar and badge (rebuilt on every change; cheap).
function Level.render(l: Level)
	l.root:ClearAllChildren()
	l.fill, l.label, l.timer, l.badge = nil, nil, nil, nil
	local v = l.view
	l.root.Visible = v ~= nil and onPlaza(l)
	if not v or not l.root.Visible then
		return
	end
	local cv = l.ctx.canvas
	local at = Reward.badgeAt(cv, l.ctx.topbar)
	local cx = at.X - 170
	-- in the search the pill takes the top: the bar goes under it
	local y = if l.st and l.st.ph == "queue" then 84 else 12
	local box = Theme.frame(l.root, UDim2.fromOffset(330, 56), UDim2.fromOffset(cx - 90, y), Theme.PANEL, TOP_MID)
	box.Name = "Bar"
	box.BackgroundTransparency = 0.1
	Theme.round(box, 28)
	Theme.stroke(box, 3, Theme.INK)
	local disc = Theme.disc(box, 56, Theme.YELLOW, UDim2.fromOffset(28, 28))
	disc.ZIndex = 3
	Theme.stroke(disc, 3, Theme.INK)
	local num = Theme.text(disc, tostring(v.level), 30, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), {
		anchor = MID,
		color = Theme.INK,
		stroke = 0,
		z = 4,
	})
	num.Name = "Num"
	local more = v.level < v.levelBalls
	local label = Theme.text(
		box,
		string.format("LEVEL %d · %d/%d XP", v.level, v.xp, v.need),
		20,
		UDim2.fromOffset(250, 24),
		UDim2.fromOffset(66, 5),
		{ align = Enum.TextXAlignment.Left, anchor = V2(0, 0) }
	)
	label.Name = "Label"
	local track = Theme.frame(box, UDim2.fromOffset(250, 14), UDim2.fromOffset(66, 33), Theme.SLOT)
	Theme.round(track, 7)
	local k = math.clamp(v.xp / math.max(1, v.need), 0, 1)
	local fill =
		Theme.frame(track, UDim2.fromScale(math.max(0.04, k), 1), nil, if more then Theme.GOOD else Theme.YELLOW)
	fill.Name = "Fill"
	Theme.round(fill, 7)
	if more then
		-- the next level gives a ball: a small ball icon at the end of the bar
		local q = Theme.text(track, "?", 20, UDim2.fromOffset(24, 24), UDim2.new(1, 4, 0.5, 0), {
			anchor = V2(0, 0.5),
			color = Theme.YELLOW_TXT,
		})
		q.Name = "NextBall"
	end
	l.fill, l.label = fill, label
	if v.boostEnds and v.boostEnds > workspace:GetServerTimeNow() then
		local badge = Theme.frame(l.root, UDim2.fromOffset(170, 52), UDim2.fromOffset(at.X, y + 2), Theme.GO, TOP_MID)
		badge.Name = "Boost"
		Theme.round(badge, 26)
		Theme.stroke(badge, 3, Theme.INK)
		local t = Theme.text(badge, "", 26, UDim2.new(1, -16, 1, -10), UDim2.fromScale(0.5, 0.5), {
			anchor = MID,
			color = Theme.INK,
			stroke = 0,
			z = 3,
		})
		t.Name = "Text"
		Instance.new("UIScale").Parent = badge
		l.timer, l.badge = t, badge
		Level.step(l, 0)
	end
	if v.level ~= l.lastLevel and l.lastLevel > 0 then
		Theme.pop(box, 0, 0.7)
	end
	l.lastLevel = v.level
end

local function close(l: Level)
	l.pop:ClearAllChildren()
	l.pop.Visible = false
	table.clear(l.fx.frames)
	l.showing = false
end

-- NEW BALL! of the next queued level up (only on the plaza, never over a match or a menu).
local function showNews(l: Level)
	if l.showing or #l.news == 0 or not l.st or l.st.ph ~= "lobby" then
		return
	end
	local up = table.remove(l.news, 1) :: Net.LevelUp
	local e = up.e
	if e == nil then
		showNews(l)
		return
	end
	l.showing = true
	local cv = l.ctx.canvas
	l.fx.canvas = cv
	local pop = l.pop
	pop.Visible = true
	pop:SetAttribute("NewBall", e)
	local bg = Theme.backdrop(pop, 1)
	TweenService:Create(bg, TweenInfo.new(0.3), { BackgroundTransparency = 0.08 }):Play()
	local cx, cy = cv.X / 2, cv.Y * 0.58
	local r = Cheer.rays(pop, l.fx, e, cx, cy, 700)
	r.ZIndex = 1
	Reward.card(pop, l.fx, e, cx, cy, 170, 0.25)
	local top = math.max(12, l.ctx.topbar.Y)
	local lv = Theme.text(pop, `LEVEL {up.level}!`, 30, UDim2.fromOffset(400, 36), UDim2.fromOffset(cx, top), {
		anchor = TOP_MID,
		color = Theme.YELLOW_TXT,
	})
	Theme.pop(lv, 0.1, 0.4)
	local head = Theme.text(pop, "NEW BALL!", 64, UDim2.fromOffset(600, 70), UDim2.fromOffset(cx, top + 36), {
		anchor = TOP_MID,
		color = Theme.YELLOW,
		stroke = 7,
	})
	head.Name = "Head"
	Theme.pop(head, 0.8, 0.3)
	local nm = Theme.text(
		pop,
		(Rules.Config.TITLE[e] or "?") .. "  +1",
		34,
		UDim2.fromOffset(500, 40),
		UDim2.new(0.5, 0, 1, -64),
		{ anchor = TOP_MID, color = Theme.nameColor(e), stroke = 4 }
	)
	nm.TextTransparency = 1
	task.delay(1.0, function()
		if nm.Parent then
			nm.TextTransparency = 0
			Theme.pop(nm, 0, 0.5)
			Cheer.confetti(pop, l.fx)
		end
	end)
	local hint = Theme.text(pop, "TAP TO CONTINUE", 22, UDim2.fromOffset(400, 26), UDim2.new(0.5, 0, 1, -24), {
		anchor = TOP_MID,
		color = Theme.DIM,
		bold = true,
	})
	hint.Visible = false
	local tap = Instance.new("TextButton")
	tap.Text = ""
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 40
	tap.Parent = pop
	local open = os.clock()
	task.delay(1.6, function()
		if hint.Parent then
			hint.Visible = true
		end
	end)
	tap.Activated:Connect(function()
		if os.clock() - open > 1.2 then
			close(l)
			showNews(l)
		end
	end)
	task.delay(8, function()
		if tap.Parent and l.showing then
			close(l)
			showNews(l)
		end
	end)
	-- a flash of the element colour behind the card
	local glow = Theme.disc(pop, 300, Look.bright(e), UDim2.fromOffset(cx, cy), 0.75)
	glow.ZIndex = 0
end

function Level.new(parent: Instance, ctx: Ctx): Level
	local root = Instance.new("Frame")
	root.Name = "Level"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = false
	root.Parent = parent
	local pop = Instance.new("Frame")
	pop.Name = "NewBall"
	pop.BackgroundTransparency = 1
	pop.Size = UDim2.fromScale(1, 1)
	pop.Visible = false
	pop.ZIndex = 50
	pop.Parent = parent
	return {
		root = root,
		pop = pop,
		ctx = ctx,
		fx = { frames = {}, canvas = ctx.canvas },
		view = nil,
		st = nil,
		news = {},
		showing = false,
		fill = nil,
		label = nil,
		timer = nil,
		badge = nil,
		lastLevel = 0,
	}
end

function Level.setProfile(l: Level, v: Net.ProfileView)
	l.view = v
	local news = v.news
	if news then
		for _, up in news do
			if typeof(up) == "table" and type(up.level) == "number" then
				table.insert(l.news, up)
			end
		end
	end
	Level.render(l)
	showNews(l)
end

function Level.setState(l: Level, st: Net.State)
	l.st = st
	if l.showing and st.ph ~= "lobby" then
		-- a match or a menu comes: the popup waits for the next lobby
		close(l)
	end
	Level.render(l)
	showNews(l)
end

-- Every frame: popup effects; the badge timer, and it goes when the boost ends.
function Level.step(l: Level, dt: number)
	for _, f in l.fx.frames do
		f(dt)
	end
	local t, v = l.timer, l.view
	if t and v and v.boostEnds then
		local left = v.boostEnds - workspace:GetServerTimeNow()
		if left <= 0 then
			Level.render(l)
			return
		end
		t.Text = string.format("%dx XP %s", v.boostMult, fmt(left))
		local b = l.badge
		local s = if b then b:FindFirstChildOfClass("UIScale") else nil
		if s and not Theme.reduced() then
			s.Scale = 1 + 0.03 * math.sin(os.clock() * 4)
		end
	end
end

return Level
