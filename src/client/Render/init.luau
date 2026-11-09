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
local Field = require(script.Field)
local Fx = require(script.Fx)
local Input = require(script.Input)
local Sfx = require(script.Sfx)
local Smooth = require(script.Smooth)
local Stage = require(script.Stage)

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
	field: Field.Field,
	cells: Cells.Cells,
	actors: Actors.Actors,
	fx: Fx.Fx,
	cam: Cam.Cam?,
	stage: Stage.Stage,
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
	Stage.destroy(s.stage)
	Actors.destroy(s.actors)
	Fx.destroy(s.fx)
	Field.destroy(s.field)
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

-- Hot terrain under the balls and burning cells for the web ambient() sparks.
local function ambient(s: Session)
	local f = s.frame
	if not f then
		return
	end
	local hot: { [string]: { number } } = { burn = {}, lava = {}, toxic = {} }
	for c, layer in s.cells.layerOf do
		local list = hot[layer]
		if list then
			table.insert(list, c)
		end
	end
	local balls = {}
	local bd = s.board
	for _, b in f.balls do
		if b.alive then
			local x, y = Actors.ballPos(s.actors, b.e)
			if x and y then
				local i, j = math.floor(x) - bd.ox, math.floor(y) - bd.oy
				local layer = if i >= 0
						and j >= 0
						and i < bd.gw
						and j < bd.gh
					then s.cells.layerOf[j * bd.gw + i]
					else nil
				table.insert(balls, { e = b.e, x = x, y = y, layer = layer })
			end
		end
	end
	Fx.ambient(s.fx, hot, balls)
end

local function render(s: Session, dt: number)
	-- hit pause: hold the playback a moment on hits, KOs and reactions (the web slow motion feel)
	local head = s.smooth:update(if s.fx.pause > 0 then dt * 0.15 else dt)
	if head then
		local a, b, t = s.smooth:sample(head)
		if a and b then
			Actors.update(s.actors, a, b, t, s.fx.now, s.phase == "aim")
		end
	end
	Cells.update(s.cells, dt, s.fx.now)
	if (s.phase == "play" or s.phase == "aim") and math.random() < 0.3 then
		ambient(s)
	end
	Fx.update(s.fx, dt, s.frame)
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
	local field = Field.new(board)
	local names: { [number]: string } = {}
	for _, seat in data.seats do
		if seat.userId > 0 and seat.e ~= data.you then
			names[seat.e] = seat.name
		end
	end
	local fx = Fx.new(field, Sfx.play, function(amount)
		if s.cam then
			Cam.addShake(s.cam, amount)
		end
	end)
	for e, word in Rules.Config.WORD do
		fx.words[e] = word
	end
	fx.you = data.you
	s = {
		id = data.id,
		board = board,
		you = data.you,
		yourSide = if data.you then sideOf[data.you] else nil,
		sideOf = sideOf,
		mode = data.mode,
		dec = dec,
		smooth = Smooth.new(SMOOTH_DELAY),
		field = field,
		cells = Cells.new(field, Rules.Config.TOP),
		actors = Actors.new(field, data.you, names),
		fx = fx,
		cam = cam,
		stage = Stage.new(board, data),
		phase = "aim",
		frame = nil,
		hp = {},
		conns = {},
		stopInput = nil,
		ended = false,
	}
	session = s
	fx.ballPos = function(e)
		return Actors.ballPos(s.actors, e)
	end
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
	Stage.setSeats(s.stage, data.seats)
	applyChanges(s, false)
end

local function endMatch(s: Session, data: Net.MatchEnd)
	s.ended = true
	local won = if s.mode == "duel" then data.winner == s.yourSide else s.you ~= nil and data.winner == s.you
	if won then
		Sfx.play("win")
	end
	Stage.react(s.stage, function(seat)
		return if s.mode == "duel" then seat.side == data.winner else seat.e == data.winner
	end)
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
	elseif kind == Net.MatchKind.round then
		Stage.react(s.stage, function(seat)
			return seat.side == data.win
		end)
	elseif kind == Net.MatchKind.finish then
		endMatch(s, data)
	end
end

-- State leaves the match: anything but match/result tears the world down.
local held: any = nil
local function onState(st: any)
	-- debug: the UI keeps its screen while workspace.BTHold is set; keep the arena too
	if workspace:GetAttribute("BTHold") == true then
		held = st
		return
	end
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
	workspace:GetAttributeChangedSignal("BTHold"):Connect(function()
		local st = held
		if st and workspace:GetAttribute("BTHold") ~= true then
			held = nil
			onState(st)
		end
	end)
	Players.LocalPlayer.AncestryChanged:Connect(function()
		if session then
			destroy(session)
		end
	end)
end

return Render
