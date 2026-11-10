--!strict
-- M3.1 reaction book: all 42 reactions in a 6 x 7 grid. Found ones are cells in the reaction's colour with its name,
-- the rest dark silhouettes with "???". Header: count and the pay (25 coins each new, 10 crystals every 10, 1000 for
-- all). Reactions found in the last match glow (NEW!).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Money = require("./Money")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules"))
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)

local Book = {}

export type Ctx = { canvas: Vector2, frames: { (dt: number) -> () }, close: () -> () }

local COLS, CW, CH, GAP = 6, 146, 52, 6

-- fresh: names found in the last match (they glow)
function Book.build(parent: Frame, v: Net.ProfileView, ctx: Ctx, fresh: { [string]: boolean })
	parent:ClearAllChildren()
	local cv = ctx.canvas
	local names: { string } = Rules.Config.REACTIONS
	local got: { [string]: boolean } = {}
	local found: { string } = v.book or {}
	for _, k in found do
		got[k] = true
	end
	local bg = Theme.backdrop(parent, 0.18)
	bg.Active = true
	local rows = math.ceil(#names / COLS)
	local w = COLS * CW + (COLS - 1) * GAP + 32
	local h = 84 + rows * CH + (rows - 1) * GAP + 16
	local panel = Theme.frame(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, MID)
	panel.Name = "BookPanel"
	Theme.round(panel, 22)
	Theme.stroke(panel, 4, Theme.INK)
	Theme.pop(panel, 0, 0.7)
	local n = #(v.book or {})
	local head =
		Theme.text(panel, `REACTION BOOK {n}/{#names}`, 36, UDim2.fromOffset(520, 40), UDim2.fromOffset(20, 10), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.YELLOW,
			stroke = 4,
		})
	head.Name = "Head"
	-- "+25 (coin) EACH NEW · EVERY 10: +10 (gem)"
	local hint = Theme.clear(panel, UDim2.fromOffset(560, 26), UDim2.fromOffset(20, 52))
	local function piece(text: string, x: number, wd: number)
		Theme.text(hint, text, 20, UDim2.fromOffset(wd, 26), UDim2.fromOffset(x, 0), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
			color = Theme.DIM,
			bold = true,
		})
	end
	piece("+25", 0, 40)
	Money.icon(hint, "coins", 22, UDim2.fromOffset(52, 13))
	piece("EACH NEW · EVERY 10: +10", 68, 260)
	Money.icon(hint, "crystals", 24, UDim2.fromOffset(338, 13))
	piece("· ALL: +1000", 356, 150)
	local close =
		Theme.button(panel, "X", UDim2.fromOffset(56, 56), UDim2.new(1, -10, 0, 10), Theme.BAD, nil, 30, V2(1, 0))
	close.Name = "Close"
	close.Activated:Connect(ctx.close)
	local grid = Theme.clear(panel, UDim2.fromOffset(w - 32, h - 100), UDim2.fromOffset(16, 84))
	grid.Name = "Grid"
	for i, k in names do
		local col, row = (i - 1) % COLS, (i - 1) // COLS
		local open = got[k] == true
		local c = Look.RXCOL[k] or Theme.YELLOW
		local cell = Theme.frame(
			grid,
			UDim2.fromOffset(CW, CH),
			UDim2.fromOffset(col * (CW + GAP), row * (CH + GAP)),
			if open then c:Lerp(Theme.INK, 0.45) else Theme.INK:Lerp(Theme.SLOT, 0.4)
		)
		cell.Name = k
		cell:SetAttribute("Open", open)
		Theme.round(cell, 10)
		Theme.stroke(cell, if open then 3 else 2, if open then c else Theme.RING)
		Theme.text(cell, if open then k else "???", 22, UDim2.new(1, -10, 1, -8), UDim2.fromScale(0.5, 0.5), {
			anchor = MID,
			color = if open then c:Lerp(Color3.new(1, 1, 1), 0.35) else Theme.MUTED,
			wrap = true,
		}).Name =
			"Name"
		if open and fresh[k] then
			local tag = Theme.text(cell, "NEW!", 20, UDim2.fromOffset(60, 22), UDim2.new(1, 4, 0, -10), {
				anchor = V2(1, 0),
				color = Theme.YELLOW,
				z = 4,
			})
			tag.Name = "New"
			local s = Instance.new("UIScale")
			s.Parent = cell
			if not Theme.reduced() then
				table.insert(ctx.frames, function()
					if cell.Parent then
						s.Scale = 1 + 0.05 * math.sin(os.clock() * 6)
					end
				end)
			end
		end
	end
end

return Book
