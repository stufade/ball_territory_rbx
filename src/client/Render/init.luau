--!strict
-- Client 3D world of a match: board, balls, effects, camera, tap input, sounds. Driven by the Match / Snap / State
-- remotes of docs/net.md. One session per match; its connections and instances die with it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules)

local Actors = require(script.Actors)
local Board = require(script.Board)
local Cam = require(script.Cam)
local Cells = require(script.Cells)
local Fx = require(script.Fx)
local Geo = require(script.Geo)
local Input = require(script.Input)
local Sfx = require(script.Sfx)
local Smooth = require(script.Smooth)

local Snap = require(ReplicatedStorage.Shared.Net.Snap)
local SMOOTH_DELAY = 0.1
local SAFETY_END = 30 -- s: drop the session if no State follows the end

type Session = {
	id: number,
	board: Board.Board,
	you: number?,
	yourSide: number?,
	sideOf: { [number]: number },
	mode: string,
	dec: Snap.Decoder,
	smooth: Smooth.Buffer,
	cells: Cells.Cells,
	actors: Actors.Actors,
	fx: Fx.Fx,
	cam: Cam.Cam?,
	phase: string,
	frame: Snap.Frame?,
	hp: { [number]: number },
	conns: { RBXScriptConnection },
	stopInput: (() -> ())?,
	ended: boolean,
}

local Render = {}
local session: Session? = nil
local opening = 0

local function destroy(s: Session)
	for _, c in s.conns do
		c:Disconnect()
	end
	if s.stopInput then
		s.stopInput()
	end
	RunService:UnbindFromRenderStep("BTRender")
	if s.cam then
		Cam.stop(s.cam)
	end
	Actors.destroy(s.actors)
	Fx.destroy(s.fx)
	Board.close(s.board)
	if session == s then
		session = nil
	end
end

local function applyChanges(s: Session, animate: boolean)
	for _, c in Snap.takeChanged(s.dec) do
		Cells.set(s.cells, c, s.dec.cells[c + 1], animate)
	end
	if Cells.takeCaptured(s.cells) > 0 then
		Sfx.capture()
	end
end

local function onSnap(s: Session, buf: buffer)
	local f = Snap.decode(s.dec, buf)
	applyChanges(s, true)
	if not f then
		return
	end
	s.frame = f
	s.smooth:push(f.t, f)
	for _, b in f.balls do
		local old = s.hp[b.e]
		if old and b.alive and b.hp ~= old then
			Fx.damage(s.fx, b.x, b.y, b.hp - old)
		end
		s.hp[b.e] = b.hp
	end
end

local function render(s: Session, dt: number)
	local head = s.smooth:update(dt)
	if head then
		local a, b, t = s.smooth:sample(head)
		if a and b then
			Actors.update(s.actors, a, b, t)
		end
	end
	Cells.update(s.cells, dt)
	Fx.update(s.fx, dt)
end

local function startSession(data: Net.MatchStart)
	local token = opening + 1
	opening = token
	if session then
		destroy(session)
	end
	local board = Board.open(data.arena, data.ox, data.oy, data.w, data.h)
	if not board or token ~= opening then
		if board then
			Board.close(board)
		end
		return
	end
	local slots = Geo.slots(data.seats, data.you)
	local sideOf: { [number]: number } = {}
	for _, seat in data.seats do
		sideOf[seat.e] = seat.side
	end
	local dec = Snap.newDecoder()
	if not Snap.applyKey(dec, data.key) then
		Board.close(board)
		return
	end
	local cam: Cam.Cam? = Cam.start(board)
	local s: Session
	local fx = Fx.new(board, function(amount)
		if s.cam then
			Cam.addShake(s.cam, amount)
		end
	end, Sfx.play)
	for e, word in Rules.Config.WORD do
		fx.words[tostring(e)] = word
	end
	s = {
		id = data.id,
		board = board,
		you = data.you,
		yourSide = if data.you then sideOf[data.you] else nil,
		sideOf = sideOf,
		mode = data.mode,
		dec = dec,
		smooth = Smooth.new(SMOOTH_DELAY),
		cells = Cells.new(board, Rules.Config.TOP, slots),
		actors = Actors.new(board, slots, data.you),
		fx = fx,
		cam = cam,
		phase = "aim",
		frame = nil,
		hp = {},
		conns = {},
		stopInput = nil,
		ended = false,
	}
	session = s
	applyChanges(s, false)
	table.insert(
		s.conns,
		Remotes.Snap.OnClientEvent:Connect(function(buf: buffer)
			onSnap(s, buf)
		end)
	)
	RunService:BindToRenderStep("BTRender", Enum.RenderPriority.Camera.Value + 2, function(dt)
		render(s, dt)
	end)
	if data.you then
		s.stopInput = Input.start({
			board = board,
			you = data.you,
			phase = function()
				return if s.ended then "" else s.phase
			end,
			frame = function()
				return s.frame
			end,
			ballPos = function(e)
				return Actors.ballPos(s.actors, e)
			end,
			send = function(kind, dx, dy)
				Remotes.Input:FireServer(kind, dx, dy)
			end,
			kinds = Net.Input,
			finalGap = Net.Limits.finalTap + 0.02,
		})
	end
end

-- Next round of the same match: new cells, clean buffers, same board.
local function restartRound(s: Session, data: Net.MatchStart)
	if not Snap.applyKey(s.dec, data.key) then
		return
	end
	s.smooth:reset()
	s.frame = nil
	s.hp = {}
	s.phase = "aim"
	applyChanges(s, false)
end

local function endMatch(s: Session, data: Net.MatchEnd)
	s.ended = true
	local won = if s.mode == "duel" then data.winner == s.yourSide else s.you ~= nil and data.winner == s.you
	if won then
		Sfx.play("win")
	end
	for _, c in s.conns do
		c:Disconnect()
	end
	table.clear(s.conns)
	if s.stopInput then
		s.stopInput()
		s.stopInput = nil
	end
	task.delay(SAFETY_END, function()
		if session == s then
			destroy(s)
		end
	end)
end

local function onMatch(kind: string, data: any)
	if type(data) ~= "table" then
		return
	end
	local s = session
	if kind == Net.MatchKind.start then
		if s and s.id == data.id and s.board.model.Name == data.arena then
			restartRound(s, data)
		else
			task.spawn(startSession, data)
		end
		return
	end
	if not s or data.id ~= s.id then
		return
	end
	if kind == Net.MatchKind.ev then
		for _, e in data.list do
			Fx.event(s.fx, e.kind, e.d)
		end
	elseif kind == Net.MatchKind.phase then
		s.phase = data.ph
	elseif kind == Net.MatchKind.finish then
		endMatch(s, data)
	end
end

-- State leaves the match: anything but match/result tears the world down.
local function onState(st: any)
	local s = session
	if s and type(st) == "table" and st.ph ~= "match" and st.ph ~= "result" then
		opening += 1
		destroy(s)
	end
end

function Render.start()
	Sfx.start()
	Remotes.Match.OnClientEvent:Connect(onMatch)
	Remotes.State.OnClientEvent:Connect(onState)
	Players.LocalPlayer.AncestryChanged:Connect(function()
		if session then
			destroy(session)
		end
	end)
end

return Render
