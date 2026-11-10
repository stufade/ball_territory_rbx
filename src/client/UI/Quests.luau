--!strict
-- M3.1 quest panel on the plaza: a compact card left of the right-edge buttons (the avatar keeps running): today's
-- 3 quests with a progress bar, their coins, a tick when done, "ALL 3: +50" and the time to the 00:00 UTC reset.
-- The server counts and pays (Logic/Daily); this only shows the Profile view.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)

local Quests = {}

export type Ctx = { frames: { (dt: number) -> () }, close: () -> () }

local W, ROW = 430, 78

local function left(s: number): string
	s = math.max(0, math.floor(s))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, s // 60 % 60)
	end
	return string.format("%dm %02ds", s // 60, s % 60)
end

-- right, top: the panel's top right corner in canvas px.
function Quests.build(parent: Frame, v: Net.ProfileView, ctx: Ctx, right: number, top: number)
	parent:ClearAllChildren()
	local q = v.quests
	if not q then
		return
	end
	local h = 64 + #q.list * ROW + 56
	local panel = Theme.frame(parent, UDim2.fromOffset(W, h), UDim2.fromOffset(right, top), Theme.PANEL, V2(1, 0))
	panel.Name = "QuestPanel"
	panel.BackgroundTransparency = 0.05
	panel.Active = true
	Theme.round(panel, 18)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)
	Theme.text(panel, "DAILY QUESTS", 32, UDim2.fromOffset(300, 36), UDim2.fromOffset(18, 12), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
		stroke = 4,
	})
	local close =
		Theme.button(panel, "X", UDim2.fromOffset(48, 48), UDim2.new(1, -8, 0, 8), Theme.BAD, nil, 26, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)
	for i, r in q.list do
		local y = 58 + (i - 1) * ROW
		local row = Theme.frame(panel, UDim2.fromOffset(W - 28, ROW - 8), UDim2.fromOffset(14, y), Theme.SLOT)
		row.Name = `Quest{i}`
		Theme.round(row, 12)
		if r.done then
			row.BackgroundColor3 = Theme.SLOT:Lerp(Theme.GOOD, 0.25)
		end
		Theme.text(row, r.text, 22, UDim2.fromOffset(280, 26), UDim2.fromOffset(12, 7), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = if r.done then Theme.GOOD_TXT else Theme.TEXT,
		}).Name =
			"Text"
		local track = Theme.frame(row, UDim2.fromOffset(250, 18), UDim2.fromOffset(12, 40), Theme.INK)
		Theme.round(track, 9)
		local k = math.clamp(r.n / math.max(1, r.goal), 0, 1)
		local fill = Theme.frame(track, UDim2.fromScale(math.max(0.06, k), 1), nil, Theme.GOOD)
		fill.Name = "Fill"
		Theme.round(fill, 9)
		if k <= 0 then
			fill.BackgroundTransparency = 1
		end
		Theme.text(row, `{r.n}/{r.goal}`, 20, UDim2.fromOffset(70, 24), UDim2.fromOffset(270, 37), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.DIM,
			bold = true,
		}).Name =
			"Count"
		if r.done then
			local tick = Theme.disc(row, 44, Theme.GOOD, UDim2.new(1, -34, 0.5, 0))
			tick.Name = "Done"
			Theme.stroke(tick, 3, Theme.INK)
			Theme.text(tick, "✓", 30, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), {
				anchor = MID,
				color = Theme.INK,
				stroke = 0,
			})
		else
			Money.icon(row, "coins", 30, UDim2.new(1, -24, 0.5, 0))
			Theme.text(row, tostring(r.coins), 24, UDim2.fromOffset(56, 28), UDim2.new(1, -42, 0.5, 0), {
				anchor = V2(1, 0.5),
				align = Enum.TextXAlignment.Right,
			}).Name =
				"Pay"
		end
	end
	local fy = 58 + #q.list * ROW + 6
	local all = Theme.text(
		panel,
		if q.all then "ALL DONE! +" .. q.allCoins else `ALL {#q.list}: +{q.allCoins}`,
		22,
		UDim2.fromOffset(180, 28),
		UDim2.fromOffset(18, fy),
		{ anchor = V2(0, 0), align = Enum.TextXAlignment.Left, color = Theme.YELLOW_TXT }
	)
	all.Name = "All"
	Money.icon(panel, "coins", 26, UDim2.fromOffset(18 + 184, fy + 14))
	local reset = Theme.text(panel, "", 20, UDim2.fromOffset(190, 26), UDim2.new(1, -18, 0, fy + 1), {
		anchor = V2(1, 0),
		align = Enum.TextXAlignment.Right,
		color = Theme.DIM,
		bold = true,
	})
	reset.Name = "Reset"
	local function tick()
		reset.Text = `NEW IN {left(q.endsAt - workspace:GetServerTimeNow())}`
	end
	tick()
	table.insert(ctx.frames, function()
		if reset.Parent then
			tick()
		end
	end)
end

return Quests
