--!strict
-- "Who beats whom" in the duel pickers, readable without a word of help: a green ▲ pill with the rival balls a ball
-- beats (top of the icon) and a red ▼ pill with the ones it loses to (bottom). Only the rival's real picks count.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Theme = require("./Theme")

local Matchup = {}

Matchup.UP = "▲"
Matchup.DOWN = "▼"

local function has(list: { number }?, e: number): boolean
	return list ~= nil and table.find(list, e) ~= nil
end

-- Rival balls that e beats and loses to in a duel.
function Matchup.split(e: number, foes: { number }): ({ number }, { number })
	local beats, loses = {}, {}
	for _, f in foes do
		if has(Config.DSTRONG[e], f) then
			table.insert(beats, f)
		elseif has(Config.DWEAK[e], f) then
			table.insert(loses, f)
		end
	end
	return beats, loses
end

local function row(parent: Instance, color: Color3, h: number, pos: UDim2, anchor: Vector2): Frame
	local f = Theme.frame(parent, UDim2.fromOffset(0, h), pos, color, anchor)
	f.AutomaticSize = Enum.AutomaticSize.X
	Theme.round(f, h // 2)
	Theme.stroke(f, 2, Theme.INK)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = f
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 2)
	lay.Parent = f
	return f
end

local function arrow(parent: Instance, up: boolean, size: number): TextLabel
	local l = Theme.text(
		parent,
		if up then Matchup.UP else Matchup.DOWN,
		size,
		UDim2.fromOffset(size, size + 2),
		nil,
		{ color = Theme.INK, stroke = 0 }
	)
	l.TextScaled = false
	l.TextSize = size
	l.LayoutOrder = 0
	return l
end

-- Pill "▲ [icons]" (up = beats) or "▼ [icons]" over a ball icon; nil when the list is empty.
function Matchup.pill(parent: Instance, up: boolean, list: { number }, h: number, pos: UDim2, anchor: Vector2): Frame?
	if #list == 0 then
		return nil
	end
	local f = row(parent, if up then Theme.GOOD else Theme.BAD, h, pos, anchor)
	f.ZIndex = 6
	arrow(f, up, h - 6).ZIndex = 7
	for i, e in list do
		local holder = Theme.clear(f, UDim2.fromOffset(h - 2, h - 2))
		holder.LayoutOrder = i
		Theme.ball(holder, e, h - 4, UDim2.fromScale(0.5, 0.5)).ZIndex = 7
	end
	return f
end

-- Both pills on a grid cell of icon diameter d: ▲ above the icon, ▼ below it.
function Matchup.badges(cell: Instance, e: number, foes: { number }, d: number)
	local beats, loses = Matchup.split(e, foes)
	local h = math.clamp(math.floor(d * 0.42), 22, 28)
	Matchup.pill(cell, true, beats, h, UDim2.new(0.5, 0, 0.5, -d / 2 + 2), Vector2.new(0.5, 0.5))
	Matchup.pill(cell, false, loses, h, UDim2.new(0.5, 0, 0.5, d / 2 - 2), Vector2.new(0.5, 0.5))
end

-- Card chip text: "▲ BEATS SAND" / "▼ LOSES TO SAND", colour; nil without a matchup.
function Matchup.chip(e: number, foes: { number }, title: (number) -> string): (string?, Color3?)
	local beats, loses = Matchup.split(e, foes)
	local function names(list: { number }): string
		local out = {}
		for _, f in list do
			table.insert(out, string.upper(title(f)))
		end
		return table.concat(out, ", ")
	end
	if #beats > 0 and #loses == 0 then
		return `{Matchup.UP} BEATS {names(beats)}`, Theme.GOOD
	elseif #loses > 0 and #beats == 0 then
		return `{Matchup.DOWN} LOSES TO {names(loses)}`, Theme.BAD
	elseif #beats > 0 then
		return `{Matchup.UP} {names(beats)}  {Matchup.DOWN} {names(loses)}`, Theme.YELLOW
	end
	return nil, nil
end

-- One-line legend: [▲ BEATS] [▼ LOSES TO] <whose balls>.
function Matchup.legend(parent: Instance, whose: string, pos: UDim2, anchor: Vector2): Frame
	local line = Theme.clear(parent, UDim2.fromOffset(0, 28), pos, anchor)
	line.AutomaticSize = Enum.AutomaticSize.X
	local lay = Instance.new("UIListLayout")
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 6)
	lay.Parent = line
	for i, up in { true, false } do
		-- fixed widths: automatic size measured before the font loads cuts the text
		local p =
			Theme.frame(line, UDim2.fromOffset(if up then 112 else 140, 26), nil, if up then Theme.GOOD else Theme.BAD)
		Theme.round(p, 13)
		Theme.stroke(p, 2, Theme.INK)
		p.LayoutOrder = i
		Theme.text(
			p,
			if up then `{Matchup.UP} BEATS` else `{Matchup.DOWN} LOSES TO`,
			20,
			UDim2.new(1, -8, 1, -2),
			UDim2.fromScale(0.5, 0.5),
			{ anchor = Vector2.new(0.5, 0.5), color = Theme.INK, stroke = 0 }
		)
	end
	if whose ~= "" then
		local tail =
			Theme.text(line, whose, 20, UDim2.fromOffset(0, 24), nil, { bold = true, color = Theme.DIM, stroke = 0 })
		tail.AutomaticSize = Enum.AutomaticSize.X
		tail.TextScaled = false
		tail.TextSize = 20
		tail.LayoutOrder = 3
	end
	return line
end

return Matchup
