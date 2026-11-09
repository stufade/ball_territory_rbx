--!strict
-- Tutorial overlay (T2.1) over the match HUD: big captions with the V1 ink outline, the "ball + terrain = WORD"
-- formula, a pointing hand, the lit POWER button, the arrow to the enemy, tap-to-go-on, fades between scenes.
-- Driven by Match "tut" cues (docs/net.md); the scenes themselves run on the real board (Render). Spec: docs/ui.md.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Rules")).Config
local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Render = require("../Render")
local Theme = require("./Theme")

local V2 = Vector2.new
local MID = V2(0.5, 0.5)
-- a waiting cue pulses harder after this long without the action
local NUDGE = 6

export type Ctx = {
	act: (verb: string, arg: number?) -> (),
	canvas: Vector2,
}

export type Overlay = {
	root: Frame,
	canvas: Frame,
	ctx: Ctx,
	hud: any?,
	you: number?,
	cue: { [string]: any }?,
	cueAt: number,
	caption: TextLabel,
	sub: TextLabel,
	capScale: UIScale,
	formula: Frame,
	hand: TextLabel,
	handScale: UIScale,
	tapWord: TextLabel,
	ring: Frame,
	ringScale: UIScale,
	arrow: Frame,
	head: TextLabel,
	catcher: TextButton,
	fade: Frame,
	hideAt: number,
}

local Tutor = {}

local function scaled(o: GuiObject): UIScale
	local s = Instance.new("UIScale")
	s.Parent = o
	return s
end

function Tutor.new(canvas: Frame, ctx: Ctx): Overlay
	local root = Theme.clear(canvas, UDim2.fromScale(1, 1))
	root.Name = "Tutor"
	root.ZIndex = 40
	root.Visible = false
	local caption = Theme.text(root, "", 50, UDim2.fromOffset(560, 60), UDim2.new(0.5, 0, 0, 52), {
		anchor = V2(0.5, 0),
		color = Theme.YELLOW_TXT,
		stroke = 6,
		z = 42,
	})
	local sub = Theme.text(caption, "", 38, UDim2.fromOffset(560, 46), UDim2.new(0.5, 0, 1, 2), {
		anchor = V2(0.5, 0),
		stroke = 5,
		z = 42,
	})
	local formula = Theme.clear(root, UDim2.fromOffset(560, 120), UDim2.fromScale(0.5, 0.62), MID)
	formula.ZIndex = 42
	formula.Visible = false
	local hand = Theme.text(root, "👆", 110, UDim2.fromOffset(120, 120), nil, { stroke = 0, z = 44 })
	hand.Visible = false
	local tapWord = Theme.text(hand, "TAP!", 44, UDim2.fromOffset(160, 50), UDim2.fromScale(0.5, 1), {
		anchor = V2(0.5, 0),
		color = Theme.YELLOW_TXT,
		stroke = 5,
		z = 44,
	})
	tapWord.Visible = false
	local ring = Theme.frame(root, UDim2.fromOffset(100, 100), nil, Theme.YELLOW, MID)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 43
	ring.Visible = false
	Theme.round(ring, 18)
	Theme.stroke(ring, 6, Theme.YELLOW)
	local arrow = Theme.frame(root, UDim2.fromOffset(10, 12), nil, Theme.YELLOW, MID)
	arrow.ZIndex = 43
	arrow.Visible = false
	Theme.round(arrow, 6)
	Theme.stroke(arrow, 3, Theme.INK)
	local head = Theme.text(root, "▶", 64, UDim2.fromOffset(70, 70), nil, {
		anchor = MID,
		color = Theme.YELLOW,
		stroke = 4,
		z = 43,
	})
	head.Visible = false
	-- tap anywhere to go on: catches the tap so it does not reach the board
	local catcher = Instance.new("TextButton")
	catcher.Name = "TapCatcher"
	catcher.Text = ""
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = 41
	catcher.Visible = false
	catcher.Parent = root
	local fade = Theme.frame(canvas, UDim2.new(1, 400, 1, 400), UDim2.fromOffset(-200, -200), Color3.new(0, 0, 0))
	fade.Name = "TutorFade"
	fade.ZIndex = 60
	fade.BackgroundTransparency = 1
	fade.Visible = false
	local o: Overlay = {
		root = root,
		canvas = canvas,
		ctx = ctx,
		hud = nil,
		you = nil,
		cue = nil,
		cueAt = 0,
		caption = caption,
		sub = sub,
		capScale = scaled(caption),
		formula = formula,
		hand = hand,
		handScale = scaled(hand),
		tapWord = tapWord,
		ring = ring,
		ringScale = scaled(ring),
		arrow = arrow,
		head = head,
		catcher = catcher,
		fade = fade,
		hideAt = 0,
	}
	catcher.Activated:Connect(function()
		local c = o.cue
		if c and c.k == "tap" and c.wait then
			o.ctx.act(Net.Action.tut, c.n)
			catcher.Visible = false
			Theme.pop(o.hand, 0, 1.4)
		end
	end)
	return o
end

local function say(o: Overlay, text: string, sub: string?, color: Color3?, hideIn: number?)
	o.caption.Text = text
	o.caption.TextColor3 = color or Theme.YELLOW_TXT
	o.sub.Text = sub or ""
	o.caption.Visible = text ~= ""
	o.hideAt = if hideIn then os.clock() + hideIn else 0
	if text ~= "" then
		Theme.pop(o.caption, 0, 0.5)
	end
end

local function clearPointers(o: Overlay)
	o.hand.Visible = false
	o.tapWord.Visible = false
	o.ring.Visible = false
	o.arrow.Visible = false
	o.head.Visible = false
	o.catcher.Visible = false
end

-- Big "ball + terrain = WORD!" in the middle of the board.
local function formula(o: Overlay, e: number, layer: string, word: string)
	local f = o.formula
	f:ClearAllChildren()
	f.Visible = true
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	local function cell(w: number): Frame
		local c = Theme.clear(f, UDim2.fromOffset(w, 110))
		c.LayoutOrder = #f:GetChildren()
		c.ZIndex = 42
		return c
	end
	local b = Theme.ball(cell(110), e, 100, UDim2.fromScale(0.5, 0.5))
	b.ZIndex = 43
	Theme.text(cell(50), "+", 70, UDim2.fromScale(1, 1), nil, { z = 43, stroke = 6 })
	local row = table.find(Config.TOP, layer)
	if row then
		local i = Theme.ball(cell(110), 26 + row, 100, UDim2.fromScale(0.5, 0.5))
		i.ZIndex = 43
	end
	Theme.text(cell(50), "=", 70, UDim2.fromScale(1, 1), nil, { z = 43, stroke = 6 })
	local wc = cell(if #word > 6 then 300 else 220)
	Theme.text(wc, word .. "!", 84, UDim2.fromScale(1, 1), nil, {
		color = Look.RXCOL[word] or Theme.YELLOW_TXT,
		stroke = 7,
		z = 43,
	})
	Theme.pop(f, 0, 0.3)
	local token = o.cueAt
	task.delay(2.2, function()
		if o.cueAt == token or (o.cue and o.cue.k ~= "boom" and o.cue.k ~= "wild") then
			f.Visible = false
		end
	end)
end

-- Starts a scene (Match start of mode "tutor"): fade in from black.
function Tutor.begin(o: Overlay, hud: any, start: Net.MatchStart)
	o.hud = hud
	o.you = start.you
	o.root.Visible = true
	clearPointers(o)
	o.formula.Visible = false
	o.caption.Visible = false
	o.cue = nil
	if o.fade.Visible then
		TweenService:Create(o.fade, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		task.delay(0.36, function()
			if o.fade.BackgroundTransparency > 0.99 then
				o.fade.Visible = false
			end
		end)
	end
end

function Tutor.stop(o: Overlay)
	o.root.Visible = false
	o.hud = nil
	o.cue = nil
	o.fade.Visible = false
	o.fade.BackgroundTransparency = 1
	clearPointers(o)
end

function Tutor.cue(o: Overlay, c: { [string]: any })
	if type(c.k) ~= "string" then
		return
	end
	o.cue = c
	o.cueAt = os.clock()
	local hud = o.hud
	if hud then
		-- scenes A-C have no clock: the timer would only distract
		hud.timer.Visible = c.s == "D"
	end
	local k = c.k
	if k == "react" then
		say(o, "ELEMENTS REACT!")
	elseif k == "boom" or k == "wild" then
		formula(o, c.e or 0, c.l or "", c.rx or "")
	elseif k == "tap" then
		say(o, "COOL! TAP TO GO ON")
		o.formula.Visible = false
		o.hand.Text = "👆"
		o.hand.Visible = true
		o.tapWord.Visible = true
		o.catcher.Visible = true
	elseif k == "power" then
		say(o, "TAP POWER — GRAB LAND!")
		o.hand.Text = "👇"
		o.hand.Visible = true
		o.ring.Visible = true
	elseif k == "grab" then
		clearPointers(o)
		say(o, "LAND GRABBED!", nil, Theme.GOOD_TXT)
		local p = hud and o.you and hud.plates[o.you]
		if p then
			Theme.pop(p.pct, 0, 1.8)
		end
	elseif k == "dir" then
		say(o, if c.retry then "TRY AGAIN!" else "EVERY 12s: TAP WHERE TO FLY", "HIT THE ENEMY!")
		o.hand.Text = "👆"
		o.hand.Visible = true
		o.tapWord.Visible = true
		o.arrow.Visible = true
		o.head.Visible = true
	elseif k == "go" then
		clearPointers(o)
		say(o, "")
	elseif k == "miss" then
		clearPointers(o)
		say(o, "MISSED! TRY AGAIN", nil, Theme.BAD_TXT)
	elseif k == "ko" then
		say(o, "LAND STOLEN!", nil, Theme.YELLOW_TXT)
	elseif k == "final" then
		say(o, "YOUR TURN! WIN THE LAND!", nil, nil, 2.6)
	elseif k == "out" then
		clearPointers(o)
		o.fade.Visible = true
		TweenService:Create(o.fade, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	end
end

-- Viewport px -> design px of the canvas.
local function design(o: Overlay, v: Vector2): Vector2
	local k = o.canvas.AbsoluteSize.X / math.max(1, o.ctx.canvas.X)
	return (v - o.canvas.AbsolutePosition) / math.max(k, 1e-3)
end

local function ballScreen(o: Overlay, e: number): Vector2?
	local x, y = Render.ballPos(e)
	if not (x and y) then
		return nil
	end
	local v = Render.toScreen(x, y)
	return if v then design(o, v) else nil
end

-- Every frame: pulses (harder after NUDGE s of waiting), pointers that follow the button and the balls.
function Tutor.step(o: Overlay, _dt: number)
	if not o.root.Visible then
		return
	end
	local t = os.clock()
	local c = o.cue
	local nudge = c ~= nil and c.wait == true and t - o.cueAt > NUDGE
	local amp, speed = if nudge then 0.22 else 0.09, if nudge then 11 else 6
	local beat = if Theme.reduced() then 0 else math.sin(t * speed)
	o.handScale.Scale = 1 + amp * beat
	o.ringScale.Scale = 1.04 + amp * 0.5 * beat
	o.capScale.Scale = if nudge then 1 + 0.06 * beat else o.capScale.Scale
	if o.hideAt > 0 and t > o.hideAt then
		o.hideAt = 0
		o.caption.Visible = false
	end
	local cv = o.ctx.canvas
	local hud = o.hud
	o.caption.Size = UDim2.fromOffset(if hud then math.max(320, hud.mid - 10) else 560, 60)
	o.sub.Size = UDim2.new(1, 0, 0, 46)
	if not c then
		return
	end
	if c.k == "tap" then
		o.hand.Position = UDim2.fromOffset(cv.X / 2, cv.Y - 150 + 8 * beat)
		o.hand.AnchorPoint = MID
	elseif c.k == "power" and hud and hud.power then
		local btn = hud.power.btn :: GuiObject
		local p0 = design(o, btn.AbsolutePosition)
		local p1 = design(o, btn.AbsolutePosition + btn.AbsoluteSize)
		local mid = (p0 + p1) / 2
		o.ring.Position = UDim2.fromOffset(mid.X, mid.Y)
		o.ring.Size = UDim2.fromOffset(p1.X - p0.X + 16, p1.Y - p0.Y + 16)
		o.hand.AnchorPoint = V2(0.5, 1)
		o.hand.Position = UDim2.fromOffset(mid.X, p0.Y - 4 + 10 * beat)
	elseif c.k == "dir" then
		local me, foe = ballScreen(o, o.you or 0), ballScreen(o, c.e or 1)
		if foe then
			-- the fingertip (top of the emoji) on the enemy
			o.hand.AnchorPoint = V2(0.42, 0.08)
			o.hand.Position = UDim2.fromOffset(foe.X, foe.Y + 26 + 8 * beat)
		end
		if me and foe then
			local d = foe - me
			local len = d.Magnitude
			local u = if len > 1 then d / len else V2(1, 0)
			local a = me + u * 40
			local b = foe - u * 58
			local mid = (a + b) / 2
			o.arrow.Position = UDim2.fromOffset(mid.X, mid.Y)
			o.arrow.Size = UDim2.fromOffset(math.max(0, (b - a).Magnitude), 12)
			o.arrow.Rotation = math.deg(math.atan2(u.Y, u.X))
			o.arrow.BackgroundTransparency = 0.15 + 0.15 * beat
			o.head.Position = UDim2.fromOffset(b.X + u.X * 14, b.Y + u.Y * 14)
			o.head.Rotation = o.arrow.Rotation
		end
		o.arrow.Visible = me ~= nil and foe ~= nil and c.wait == true and o.hand.Visible
		o.head.Visible = o.arrow.Visible
	end
end

return Tutor
