--!strict
-- Tap or click on the board -> cell -> direction from the player's own ball -> Input remote.
-- aim in the aim phase, dir in the CHOOSE DIRECTION window and in the final. Taps on GUI (gameProcessed) are ignored.
local UserInputService = game:GetService("UserInputService")

local Board = require(script.Parent.Board)
local Geo = require(script.Parent.Geo)

export type Ctx = {
	board: Board.Board,
	you: number?,
	phase: () -> string,
	frame: () -> any?, -- newest decoded frame (pu, t, final)
	ballPos: (e: number) -> (number?, number?),
	send: (kind: number, dx: number, dy: number) -> (),
	kinds: { aim: number, dir: number },
	finalGap: number,
}

local Input = {}

local AIM_GAP = 0.06
local DIR_GAP = 0.1
local WINDOW_SLACK = 0.2 -- s of match time

local function cellOf(board: Board.Board, pos: Vector3?): (number?, number?)
	local cam = workspace.CurrentCamera
	if not cam or not pos then
		return nil, nil
	end
	local ray = cam:ScreenPointToRay(pos.X, pos.Y)
	local o = board.origin:PointToObjectSpace(ray.Origin)
	local d = board.origin:VectorToObjectSpace(ray.Direction)
	local lx, ly = Geo.rayToPlane(o.X, o.Y, o.Z, d.X, d.Y, d.Z)
	if not (lx and ly) then
		return nil, nil
	end
	return Geo.pointToCell(lx, ly, board.cs, board.gw, board.gh)
end

-- Returns a disconnect function.
function Input.start(ctx: Ctx): () -> ()
	local lastSend = 0
	local lastDir = 0
	local down: InputObject? = nil

	local function tap(pos: Vector3, dragging: boolean)
		local you = ctx.you
		if not you then
			return
		end
		local ph = ctx.phase()
		local now = os.clock()
		local kind: number
		if ph == "aim" then
			kind = ctx.kinds.aim
			if now - lastSend < AIM_GAP then
				return
			end
		elseif ph == "play" then
			local f = ctx.frame()
			if dragging or not f then
				return
			end
			local window = f.pu > 0 and f.t <= f.pu + WINDOW_SLACK
			if not (f.final or window) then
				return
			end
			kind = ctx.kinds.dir
			if now - lastDir < (if f.final then ctx.finalGap else DIR_GAP) then
				return
			end
		else
			return
		end
		local i, j = cellOf(ctx.board, pos)
		local bx, by = ctx.ballPos(you)
		if not (i and j and bx and by) then
			return
		end
		local dx, dy = Geo.dirToCell(bx, by, i, j, ctx.board.ox, ctx.board.oy)
		if not (dx and dy) then
			return
		end
		lastSend = now
		if kind == ctx.kinds.dir then
			lastDir = now
		end
		ctx.send(kind, dx, dy)
	end

	local began = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			down = input
			tap(input.Position, false)
		end
	end)
	local changed = UserInputService.InputChanged:Connect(function(input)
		if input == down and ctx.phase() == "aim" then
			tap(input.Position, true)
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		if input == down then
			down = nil
		end
	end)
	return function()
		began:Disconnect()
		changed:Disconnect()
		ended:Disconnect()
	end
end

return Input
