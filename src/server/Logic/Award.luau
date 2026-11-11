--!strict
-- A finished match for one person (M3.1), pure: coins (Earn), XP and levels (Progress), quests (Daily), the book.
-- Also the economy part of the client's profile view. Profiles calls these and logs the flows to analytics.
local Book = require("./Book")
local Daily = require("./Daily")
local Earn = require("./Earn")
local Progress = require("./Progress")
local Shop = require("./Shop")
local Wallet = require("./Wallet")

local Award = {}

export type Info = {
	mode: string,
	win: boolean,
	kills: number,
	rx: number,
	kinds: { [string]: number },
	balls: { number },
	afk: boolean,
	friend: boolean,
	pass2x: boolean,
}

export type Result = {
	gain: Progress.Gain,
	coins: Earn.Coins,
	quests: { Daily.QDone },
	book: Book.Found,
}

local function rareOf(balls: { number }, tiers: { [string]: { number } }): boolean
	for _, e in balls do
		for _, t in { "rare", "epic", "legendary" } do
			if table.find(tiers[t] or {}, e) then
				return true
			end
		end
	end
	return false
end

-- names: the 42 reactions (Rules.Config.REACTIONS).
function Award.match(
	d: Progress.Data,
	info: Info,
	now: number,
	cfg: any,
	rand: () -> number,
	names: { string },
	log: { Wallet.Flow }
): Result
	local E = cfg.ECON
	local coins = Earn.match(d, {
		mode = info.mode,
		win = info.win,
		kills = info.kills,
		rx = info.rx,
		afk = info.afk,
		friend = info.friend,
		pass2x = info.pass2x,
	}, now, E, log)
	local gain = Progress.award(d, {
		win = info.win,
		kills = info.kills,
		rx = info.rx,
		afk = info.afk,
		friend = coins.friend,
	}, now, cfg, rand, log)
	local quests, found = {}, { new = {}, crystals = 0, coins = 0, all = false }
	if not info.afk then
		quests = Daily.progress(d, {
			mode = info.mode,
			win = info.win,
			kills = info.kills,
			rx = info.rx,
			kinds = info.kinds,
			rare = rareOf(info.balls, cfg.TIERS),
		}, now, E, rand, log)
		found = Book.add(d, info.kinds, names, E.BOOK, log)
	end
	return { gain = gain, coins = coins, quests = quests, book = found }
end

-- The economy fields of Net.ProfileView. `serverNow` turns the UTC reset into the client's clock.
function Award.view(d: Progress.Data, now: number, serverNow: number, cfg: any, total: number): { [string]: any }
	local E = cfg.ECON
	local cards, pos, ready = Daily.cards(d, now, E)
	Shop.refresh(d, now, E)
	local deal = Shop.offer(d, E)
	return {
		coins = d.coins,
		crystals = d.crystals,
		-- ball of the day: both prices are already the floored 30% off; nil once that ball is owned
		dailyBall = if deal
			then { e = deal.e, coins = deal.coins, crystals = deal.crystals, endsAt = serverNow + Daily.left(now) }
			else nil,
		daily = { n = d.loginDays, pos = pos, ready = ready, cards = cards },
		quests = {
			list = Daily.questView(d, E),
			all = d.quests.all,
			allCoins = E.QUESTS.allDone,
			endsAt = serverNow + Daily.left(now),
		},
		book = table.clone(d.book),
		bookTotal = total,
		streak = d.streak,
	}
end

return Award
