--!strict
-- Victory juice of V2 (web drawEnd): turning rays, a particle burst, falling confetti. Shared by the result screen,
-- the T2.2 reward and NEW BALL!. Every effect runs from ctx.frames (called each frame with dt) and stops with
-- GuiService.ReducedMotionEnabled.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Look = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Look"))
local Theme = require("./Theme")

local Cheer = {}

export type Ctx = { frames: { (dt: number) -> () }, canvas: Vector2 }

local MID = Vector2.new(0.5, 0.5)

local CONFETTI = { "#ff3c46", "#ffd63c", "#40baff", "#5af096", "#ff78d2", "#ffffff", "#b04cff" }

function Cheer.rays(parent: Instance, ctx: Ctx, e: number, cx: number, cy: number, len: number): Frame
	local box = Theme.clear(parent, UDim2.fromOffset(len, len), UDim2.fromOffset(cx, cy), MID)
	local bars: { Frame } = {}
	for i = 1, 9 do
		local b = Theme.frame(
			box,
			UDim2.fromOffset(len, 46),
			UDim2.fromScale(0.5, 0.5),
			if i % 2 == 0 then Look.light(e) else Look.bright(e),
			MID
		)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.55),
			NumberSequenceKeypoint.new(0.42, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(0.58, 0.35),
			NumberSequenceKeypoint.new(0.8, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = b
		bars[i] = b
	end
	local s = Instance.new("UIScale")
	s.Scale = 0
	s.Parent = box
	TweenService
		:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.4), { Scale = 1 })
		:Play()
	table.insert(ctx.frames, function()
		local t = if Theme.reduced() then 0 else os.clock() * 14
		for i, b in bars do
			b.Rotation = t + (i - 1) * 180 / #bars
		end
	end)
	return box
end

function Cheer.burst(parent: Instance, ctx: Ctx, e: number, cx: number, cy: number)
	if Theme.reduced() then
		return
	end
	local cols = { Look.bright(e), Look.light(e), Color3.new(1, 1, 1) }
	type P = { f: Frame, vx: number, vy: number, life: number }
	local parts: { P } = {}
	for i = 1, 36 do
		local a = math.random() * math.pi * 2
		local v = 300 + math.random() * 600
		local d = 8 + math.random() * 12
		local f = Theme.disc(parent, d, cols[i % 3 + 1], UDim2.fromOffset(cx + math.cos(a) * 80, cy + math.sin(a) * 80))
		table.insert(parts, { f = f, vx = math.cos(a) * v, vy = math.sin(a) * v, life = 0.7 + math.random() * 0.5 })
	end
	table.insert(ctx.frames, function(dt)
		for i = #parts, 1, -1 do
			local p = parts[i]
			p.life -= dt
			if p.life <= 0 then
				p.f:Destroy()
				table.remove(parts, i)
			else
				p.vx *= 0.96
				p.vy *= 0.96
				local pos = p.f.Position
				p.f.Position = UDim2.fromOffset(pos.X.Offset + p.vx * dt, pos.Y.Offset + p.vy * dt)
				p.f.BackgroundTransparency = 1 - math.min(1, p.life * 2)
			end
		end
	end)
end

function Cheer.confetti(parent: Instance, ctx: Ctx)
	if Theme.reduced() then
		return
	end
	local cv = ctx.canvas
	type C = { f: Frame, vy: number, vx: number, vr: number }
	local list: { C } = {}
	local made = 0
	local acc = 0
	table.insert(ctx.frames, function(dt)
		acc += dt
		while acc > 0.03 and made < 140 do
			acc -= 0.03
			made += 1
			local f = Theme.frame(
				parent,
				UDim2.fromOffset(8 + math.random() * 8, 12 + math.random() * 10),
				UDim2.fromOffset(math.random() * cv.X, -20),
				Color3.fromHex(CONFETTI[math.random(#CONFETTI)]),
				MID
			)
			f.Rotation = math.random() * 360
			f.ZIndex = 30
			table.insert(list, {
				f = f,
				vy = 120 + math.random() * 180,
				vx = (math.random() - 0.5) * 80,
				vr = (math.random() - 0.5) * 400,
			})
		end
		for i = #list, 1, -1 do
			local c = list[i]
			local p = c.f.Position
			local y = p.Y.Offset + c.vy * dt
			if y > cv.Y + 30 then
				c.f:Destroy()
				table.remove(list, i)
			else
				c.f.Position = UDim2.fromOffset(p.X.Offset + c.vx * dt + math.sin(y / 40) * 0.6, y)
				c.f.Rotation += c.vr * dt
			end
		end
	end)
end

return Cheer
