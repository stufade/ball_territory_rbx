--!strict
-- Worn looks of the seats on the board (Net.Seat.look, server Looks.match): the skin repaints its ball (only on
-- the ball it is worn on), the trail drops particles behind the moving ball, the force effect adds its ring and
-- burst on the "power" event. Paint is shared with the shop previews (Shared.Wear). Cosmetic only: no hitbox,
-- no rules. Seats without a look (bots) keep the default ball.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local PAINT = require(ReplicatedStorage.Shared.Wear)
local Actors = require(script.Parent.Actors)
local Field = require(script.Parent.Field)
local Fx = require(script.Parent.Fx)
local Gui = require(script.Parent.Gui)

local BALL_R = 31
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromHex("#0e0a22")

type Paint = { base: Color3, accent: Color3, pat: string }
type Seen = { box: Frame, x: number, y: number, acc: number }

export type Wear = {
	-- by ball e of this round
	skin: { [number]: Paint },
	trail: { [number]: Paint },
	force: { [number]: Paint },
	seen: { [number]: Seen },
	hue: number,
}

local Wear = {}

local function paint(id: string?): Paint?
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return PAINT[id]
end

function Wear.new(): Wear
	return { skin = {}, trail = {}, force = {}, seen = {}, hue = 0 }
end

-- Looks of the seats of this round (start or next duel round: ball ids change).
function Wear.set(self: Wear, seats: { Net.Seat })
	self.skin, self.trail, self.force, self.seen = {}, {}, {}, {}
	for _, seat in seats do
		local look = seat.look
		if type(look) == "table" then
			local sk = paint(look.skin)
			if sk and look.ball == seat.e then
				self.skin[seat.e] = sk
			end
			local tr, fo = paint(look.trail), paint(look.force)
			if tr then
				self.trail[seat.e] = tr
			end
			if fo then
				self.force[seat.e] = fo
			end
		end
	end
end

local function seq(cols: { Color3 }): ColorSequence
	local ks = {}
	for i, c in cols do
		table.insert(ks, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
	end
	return ColorSequence.new(ks)
end

local function grad(o: GuiObject, s: ColorSequence, rot: number): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = s
	g.Rotation = rot
	g.Parent = o
	return g
end

-- Fixed speck layout (same every match) in the ball disc.
local function specks(o: GuiObject, col: Color3, n: number, k: number, alpha: number?)
	for i = 1, n do
		local a = i * 2.39996
		local rr = BALL_R * 0.72 * math.sqrt(i / n)
		local d = Gui.circle(o, BALL_R * k, col, 7)
		d.Position = UDim2.new(0.5, math.cos(a) * rr, 0.5, math.sin(a) * rr)
		d.BackgroundTransparency = alpha or 0
	end
end

-- The skin over the element art: a shell of the skin material, the element still shows through it.
local function dress(box: Frame, p: Paint)
	local img = box:FindFirstChildOfClass("ImageLabel")
	if img then
		img.ImageColor3 = p.base:Lerp(WHITE, 0.45)
	end
	local skin = Gui.circle(box, BALL_R, p.base, 6)
	skin.Name = "Skin"
	skin.BackgroundTransparency = 0.38
	local st = Instance.new("UIStroke")
	st.Thickness = 3
	st.Color = INK
	st.Parent = skin
	local pat = p.pat
	if pat == "stripe" then
		local ks = {}
		for i = 0, 5 do
			local c = if i % 2 == 0 then p.base else p.accent
			table.insert(ks, ColorSequenceKeypoint.new(i / 6, c))
			table.insert(ks, ColorSequenceKeypoint.new(math.min(1, (i + 1) / 6 - 0.001), c))
		end
		grad(skin, ColorSequence.new(ks), 35)
	elseif pat == "prism" then
		grad(
			skin,
			seq({
				Color3.fromHex("#ff5a7a"),
				Color3.fromHex("#ffd63c"),
				Color3.fromHex("#5af096"),
				Color3.fromHex("#5ac8ff"),
				Color3.fromHex("#b06cff"),
			}),
			45
		)
		skin.BackgroundTransparency = 0.25
	elseif pat == "marble" then
		grad(skin, seq({ p.base, p.accent, p.base, WHITE, p.base }), 60)
	elseif pat == "chrome" then
		grad(skin, seq({ WHITE, p.base, p.accent, WHITE, p.base }), 90)
		skin.BackgroundTransparency = 0.2
	elseif pat == "glass" then
		grad(skin, seq({ WHITE, p.base }), 120)
		skin.BackgroundTransparency = 0.55
		Gui.ring(skin, BALL_R * 0.78, 2, WHITE, 7).Position = UDim2.fromScale(0.5, 0.5)
	elseif pat == "neon" then
		st.Color = p.accent
		st.Thickness = 4
		skin.BackgroundTransparency = 0.25
		Gui.ring(skin, BALL_R * 0.66, 3, p.accent, 7).Position = UDim2.fromScale(0.5, 0.5)
	elseif pat == "stars" then
		grad(skin, seq({ Color3.fromHex("#7a4ae0"), Color3.fromHex("#2a1a6a"), Color3.fromHex("#0a0618") }), 50)
		skin.BackgroundTransparency = 0.2
		specks(skin, p.accent, 7, 0.09)
		specks(skin, WHITE, 4, 0.04)
	elseif pat == "ink" then
		grad(skin, seq({ Color3.fromHex("#3a3a64"), p.base }), 70)
		skin.BackgroundTransparency = 0.25
		specks(skin, p.accent, 5, 0.12, 0.1)
	elseif pat == "chalk" then
		skin.BackgroundTransparency = 0.3
		specks(skin, p.accent, 9, 0.07, 0.2)
	elseif pat == "speckle" then
		specks(skin, p.accent, 10, 0.08)
	elseif pat == "crown" then
		grad(skin, seq({ Color3.fromHex("#fff3a0"), p.base, p.accent }), 90)
		skin.BackgroundTransparency = 0.3
		local c = Gui.frame(box, p.accent, 7)
		c.Size = UDim2.fromOffset(26, 12)
		c.Position = UDim2.fromOffset(0, -BALL_R - 4)
		Instance.new("UIStroke", c).Color = INK
	end
	local shine = Gui.circle(skin, BALL_R * 0.24, WHITE, 7)
	shine.Position = UDim2.fromOffset(BALL_R * 0.64, BALL_R * 0.6)
	shine.BackgroundTransparency = 0.45
end

-- Trail kinds: particle count per second, size, life, spread.
local TRAIL: { [string]: { rate: number, r: number, life: number, spread: number } } = {
	dust = { rate = 26, r = 6, life = 0.6, spread = 30 },
	sparks = { rate = 40, r = 3, life = 0.35, spread = 120 },
	ribbon = { rate = 50, r = 7, life = 0.45, spread = 4 },
	comet = { rate = 45, r = 9, life = 0.4, spread = 10 },
	rainbow = { rate = 50, r = 7, life = 0.5, spread = 6 },
	void = { rate = 36, r = 8, life = 0.55, spread = 18 },
	eclipse = { rate = 44, r = 8, life = 0.55, spread = 14 },
}

local function trailCol(self: Wear, p: Paint, i: number): Color3
	if p.pat == "rainbow" then
		return Color3.fromHSV((self.hue + i * 0.07) % 1, 0.75, 1)
	end
	return if i % 2 == 0 then p.base else p.accent
end

-- After Actors.update: dress new ball views, drop trail particles behind moving balls.
function Wear.update(self: Wear, actors: Actors.Actors, fx: Fx.Fx, dt: number)
	self.hue = (self.hue + dt * 0.6) % 1
	local field = actors.field
	for e, v in actors.balls do
		local old = self.seen[e]
		local s: Seen
		if old and old.box == v.box then
			s = old
		else
			local sk = self.skin[e]
			if sk then
				dress(v.box, sk)
			end
			s = { box = v.box, x = v.x, y = v.y, acc = 0 }
			self.seen[e] = s
		end
		local p = self.trail[e]
		local moved = (v.x - s.x) ^ 2 + (v.y - s.y) ^ 2
		if p and v.shown and moved > 1e-4 and moved < 4 then
			local k = TRAIL[p.pat] or TRAIL.dust
			s.acc += dt * k.rate
			local px, py = Field.px(field, v.x), Field.py(field, v.y)
			local i = 0
			while s.acc >= 1 do
				s.acc -= 1
				i += 1
				local a = math.random() * 2 * math.pi
				local sp = math.random() * k.spread
				Fx.spark(fx, px, py, math.cos(a) * sp, math.sin(a) * sp, k.life, k.r, trailCol(self, p, i))
			end
		end
		s.x, s.y = v.x, v.y
	end
end

-- "power" event of ball e: its force effect on top of the element ring.
function Wear.power(self: Wear, fx: Fx.Fx, e: number, x: number, y: number)
	local p = self.force[e]
	if not p then
		return
	end
	local C = Gui.CELL
	if p.pat == "pulse" then
		Fx.ring(fx, x, y, 20, C * 3, 0.4, p.base, 8)
		Fx.ring(fx, x, y, 20, C * 3, 0.4, p.accent, 6, 0.15)
		Fx.ring(fx, x, y, 20, C * 3, 0.4, p.base, 4, 0.3)
	elseif p.pat == "ring" then
		Fx.ring(fx, x, y, 34, C * 5, 0.55, p.base, 16)
		Fx.ring(fx, x, y, 30, C * 4, 0.5, p.accent, 5, 0.08)
	elseif p.pat == "burst" then
		Fx.burst(fx, x, y, p.base, 26, 460, 0.6, 4, 8)
		Fx.burst(fx, x, y, p.accent, 14, 300, 0.5, 3, 6)
		Fx.ring(fx, x, y, 24, C * 3.5, 0.35, p.accent, 10)
	else
		Fx.ring(fx, x, y, 40, C * 6, 0.7, p.base, 18)
		Fx.ring(fx, x, y, 30, C * 4.5, 0.6, p.accent, 8, 0.1)
		Fx.burst(fx, x, y, WHITE, 20, 520, 0.7, 4, 9)
		Fx.burst(fx, x, y, p.accent, 16, 360, 0.6, 3, 7)
	end
end

return Wear
