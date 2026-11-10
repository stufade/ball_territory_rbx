--!strict
-- Coins of a finished match (M3.1, docs/economy.md «Награды за матч»), pure: the mode's pay, reactions and KOs
-- (capped), the friend bonus (first FRIEND.daily matches of the UTC day), the x2 game pass, the duel win streak.
-- AFK (no aim or power in some round) gets nothing and leaves the streak as it was.
local Wallet = require("./Wallet")

local Earn = {}

export type Match = {
	mode: string,
	win: boolean,
	kills: number,
	rx: number,
	afk: boolean,
	-- an active Roblox friend (not a bot) played this match too
	friend: boolean,
	-- the coins x2 game pass (M3.2; false until the pass exists)
	pass2x: boolean,
}

export type Coins = {
	coins: number,
	-- match coins before the friend bonus and the pass
	base: number,
	-- the friend bonus was used for this match (it also gives the XP bonus)
	friend: boolean,
	mult: number,
	-- the streak after this match and its coins when it reached a step (3, 5, 10)
	streak: number,
	streakCoins: number,
	afk: boolean,
}

local DAY = 86400

function Earn.day(now: number): number
	return now // DAY
end

-- Base coins of the mode: taking part, the win (1st place in a 4-player match), reactions and KOs.
function Earn.base(m: Match, C: any): number
	local pay = if m.mode == "duel" then C.duel else C.ffa
	local rx = math.min(C.reactMax, math.max(0, m.rx) * C.react)
	local ko = math.min(C.koMax, math.max(0, m.kills) * C.ko)
	return pay.play + (if m.win then pay.win else 0) + rx + ko
end

-- Takes one friend match of today when the daily limit allows.
function Earn.friendOk(d: any, now: number, limit: number): boolean
	local today = Earn.day(now)
	if d.friend.day ~= today then
		d.friend = { day = today, n = 0 }
	end
	if d.friend.n >= limit then
		return false
	end
	d.friend.n += 1
	return true
end

function Earn.match(d: any, m: Match, now: number, E: any, log: { Wallet.Flow }?): Coins
	local out: Coins = {
		coins = 0,
		base = 0,
		friend = false,
		mult = 1,
		streak = d.streak,
		streakCoins = 0,
		afk = m.afk,
	}
	if m.afk then
		return out
	end
	local base = Earn.base(m, E.COINS)
	local friend = m.friend and Earn.friendOk(d, now, E.FRIEND.daily)
	local mult = (if friend then E.FRIEND.coins else 1) * (if m.pass2x then E.PASSES.coins2x.mult else 1)
	out.base, out.friend, out.mult = base, friend, mult
	out.coins = Wallet.add(d, "coins", math.floor(base * mult + 0.5), `match_{m.mode}`, "Gameplay", log)
	if m.mode == "duel" then
		if m.win then
			d.streak += 1
			local pay = E.STREAK[d.streak]
			if pay then
				out.streakCoins = Wallet.add(d, "coins", pay, `streak_{d.streak}`, "Gameplay", log)
			end
		else
			d.streak = 0
		end
		out.streak = d.streak
	end
	return out
end

return Earn
