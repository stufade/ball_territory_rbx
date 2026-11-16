--!strict
-- M3.1 coin art in the V2 style (flat shapes with an ink outline and a shine, no image assets) and the
-- rolling number of a counter. Rolls run from step(dt) on Heartbeat, not TweenService.
local Theme = require("./Theme")

local Money = {}

local MID = Vector2.new(0.5, 0.5)

Money.COIN = Color3.fromHex("#ffd63c")
Money.COIN_DARK = Color3.fromHex("#e89a14")

-- A coin (yellow disc, darker rim, shine) of size d. E4: coins are the only currency; `cur` stays for callers.
function Money.icon(parent: Instance, cur: string, d: number, pos: UDim2?): Frame
	local box = Theme.clear(parent, UDim2.fromOffset(d, d), pos, MID)
	box.Name = "Coin"
	local o = Theme.disc(box, d, Money.COIN_DARK, UDim2.fromScale(0.5, 0.5))
	Theme.stroke(o, math.max(2, d // 14), Theme.INK)
	local i = Theme.disc(o, d * 0.72, Money.COIN, UDim2.fromScale(0.5, 0.5))
	i.ZIndex = o.ZIndex + 1
	local s = Theme.disc(o, d * 0.22, Color3.new(1, 1, 1), UDim2.fromScale(0.36, 0.34), 0.25)
	s.ZIndex = o.ZIndex + 2
	return box
end

-- 12345 -> "12,345"
function Money.fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- Counter text: full with separators up to 9,999,999, then "12.3M" so the pill never clips a digit.
function Money.pill(n: number): string
	n = math.floor(n)
	if n >= 10000000 then
		return string.format("%.1fM", math.floor(n / 100000) / 10)
	end
	return Money.fmt(n)
end

-- A number that rolls from what it shows to its target (0.9 s, ease out) and pulses its box while it rolls.
export type Roll = { shown: number, from: number, to: number, t: number, label: TextLabel?, box: GuiObject? }

local DUR = 0.9

function Money.roll(start: number): Roll
	return { shown = start, from = start, to = start, t = DUR, label = nil, box = nil }
end

function Money.target(r: Roll, to: number)
	if to == r.to then
		return
	end
	r.from = r.shown
	r.to = to
	r.t = 0
end

-- Returns true while it moves.
function Money.step(r: Roll, dt: number): boolean
	if r.t >= DUR then
		r.shown = r.to
	else
		r.t = math.min(DUR, r.t + dt)
		local u = r.t / DUR
		r.shown = r.from + (r.to - r.from) * (1 - (1 - u) ^ 3)
	end
	local l = r.label
	if l and l.Parent then
		l.Text = Money.pill(r.shown + 0.5)
	end
	local b = r.box
	local moving = r.t < DUR
	if b and b.Parent then
		local s = b:FindFirstChildOfClass("UIScale")
		if s then
			s.Scale = if moving and not Theme.reduced() then 1 + 0.12 * math.sin(math.pi * r.t / DUR) else 1
		end
	end
	return moving
end

-- Result screen line under the XP: "+48 (coin)  FRIEND +25%  ·  3 WINS IN A ROW!", or "AFK: NO REWARD".
function Money.result(root: Instance, st: any, cx: number, y: number)
	if st.afk then
		local t =
			Theme.text(root, "NO REWARD: YOU DID NOT PLAY", 26, UDim2.fromOffset(460, 32), UDim2.fromOffset(cx, y), {
				anchor = Vector2.new(0.5, 0),
				color = Theme.BAD_TXT,
			})
		t.Name = "Afk"
		Theme.pop(t, 1.9, 0.3)
		return
	end
	if not st.coins or st.coins <= 0 then
		return
	end
	local box = Theme.clear(root, UDim2.fromOffset(460, 36), UDim2.fromOffset(cx, y), Vector2.new(0.5, 0))
	box.Name = "Coins"
	local parts = {}
	if st.friend then
		table.insert(parts, "FRIEND +25%")
	end
	if st.streak and st.streak >= 2 then
		table.insert(parts, `{st.streak} WINS IN A ROW!`)
	end
	local main = Theme.text(box, `+{Money.fmt(st.coins)}`, 34, UDim2.fromOffset(130, 36), UDim2.fromOffset(0, 0), {
		anchor = Vector2.new(0, 0),
		align = Enum.TextXAlignment.Right,
		color = Money.COIN,
		stroke = 4,
	})
	main.Name = "Amount"
	Money.icon(box, "coins", 32, UDim2.fromOffset(152, 18))
	if #parts > 0 then
		Theme.text(box, table.concat(parts, "  ·  "), 22, UDim2.fromOffset(290, 28), UDim2.fromOffset(176, 4), {
			anchor = Vector2.new(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.GOOD_TXT,
		})
	end
	Instance.new("UIScale").Parent = box
	Theme.pop(box, 2.1, 0.3)
end

return Money
