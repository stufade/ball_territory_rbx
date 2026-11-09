--!strict
-- Weak bot of the first round, pure. Its ball has ctl set (so the rules' smart bot stays off) and prompts off.
-- It presses power only after a full charge has waited a while, and in the final turns at random now and then.
local WeakBot = {}

export type WeakBot = {
	e: number,
	rand: () -> number,
	pressAfter: number,
	aimAt: number,
	press: { number },
	aim: { number },
}

local function range(rand: () -> number, r: { number }): number
	return r[1] + rand() * (r[2] - r[1])
end

function WeakBot.new(e: number, rand: () -> number, press: { number }, aim: { number }): WeakBot
	return { e = e, rand = rand, pressAfter = range(rand, press), aimAt = 0, press = press, aim = aim }
end

-- Call after each Rules.step. Rules is passed in (see Offers).
function WeakBot.step(w: WeakBot, Rules: any, S: any)
	local b = S.by[w.e]
	if not b or not b.alive then
		return
	end
	if b.charge >= 1 and b.readyT >= w.pressAfter then
		if Rules.press(S, w.e) then
			w.pressAfter = range(w.rand, w.press)
		end
	end
	if S.final and S.t >= w.aimAt then
		w.aimAt = S.t + range(w.rand, w.aim)
		local a = w.rand() * math.pi * 2
		Rules.redirect(S, w.e, math.cos(a), math.sin(a))
	end
end

return WeakBot
