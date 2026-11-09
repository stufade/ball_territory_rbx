--!strict
-- Rookie bot of the tutorial final (T2.1), pure. Its ball has ctl set (the rules' smart bot stays off) and prompts off.
-- It never presses power and keeps circling over its own land, turning away from the player when close: it moves and
-- looks alive, but grabs little, so the player wins the final while it looks like a fair game.
local TutorBot = {}

export type TutorBot = {
	e: number,
	foe: number,
	rand: () -> number,
	aim: { number },
	keep: number,
	aimAt: number,
}

-- aim: seconds between turns {lo, hi}; keep: cells to stay away from the player's ball.
function TutorBot.new(e: number, foe: number, rand: () -> number, aim: { number }, keep: number): TutorBot
	return { e = e, foe = foe, rand = rand, aim = aim, keep = keep, aimAt = 0 }
end

local function home(S: any, e: number): (number?, number?)
	local sx, sy, n = 0, 0, 0
	for k = 1, S.N do
		if S.owner[k] == e then
			sx += S.cxs[k] + 0.5
			sy += S.cys[k] + 0.5
			n += 1
		end
	end
	if n == 0 then
		return nil, nil
	end
	return sx / n, sy / n
end

-- Call after each Rules.step. Rules is passed in (see WeakBot).
function TutorBot.step(w: TutorBot, Rules: any, S: any)
	local b = S.by[w.e]
	if not b or not b.alive or not S.final or S.t < w.aimAt then
		return
	end
	w.aimAt = S.t + w.aim[1] + w.rand() * (w.aim[2] - w.aim[1])
	local tx, ty = home(S, w.e)
	local p = S.by[w.foe]
	if p and p.alive then
		local ax, ay = b.x - p.x, b.y - p.y
		if ax * ax + ay * ay < w.keep * w.keep then
			tx, ty = b.x + ax, b.y + ay
		end
	end
	if tx and ty then
		-- a little wobble, like a person who is not sure yet
		local a = (w.rand() - 0.5) * 0.8
		local dx, dy = tx - b.x, ty - b.y
		Rules.redirect(S, w.e, dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a))
	end
end

return TutorBot
