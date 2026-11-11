--!strict
-- M3 economy values (E3.1). Design and reasons: docs/economy.md; checked by `lune run tools/econ/sim`.
-- Shared so the client shows the same prices and odds the server uses. Robux prices here are for the sim and tests:
-- the UI reads real prices through MarketplaceService:GetProductInfo (brief «Монетизация»).
-- Source tags: [brief] docs/game-brief.md, [idea] docs/idea-analysis.md «Монетизация», [sim] tuned by tools/econ/sim.
-- Element ids as in Rules.Config (0 FIRE ... 26 CANDY).
export type Gift = { coins: number?, crystals: number?, ball: number?, trials: number? }
export type Quest = { id: string, tier: string, kind: string, goal: number, text: string, k: string? }
export type Mile = { day: number, coins: number, crystals: number? }
export type Look = { id: string, coins: number, robux: number }

return {
	-- [brief] 8/8/6/5. Same lists as Config.TIERS (server, T2.2); luau-coder: make Config.TIERS read these.
	TIERS = {
		common = { 0, 1, 3, 2, 4, 5, 6, 10 }, -- FIRE ICE LIGHTNING PLANT (starters), WATER EARTH WIND SAND
		rare = { 11, 7, 8, 12, 15, 18, 24, 26 }, -- LAVA POISON METAL SLIME MUSHROOM GAS BUBBLE CANDY
		epic = { 9, 14, 19, 23, 22, 21 }, -- LIGHT CRYSTAL SOUND BOMB GHOST TIME
		legendary = { 13, 17, 16, 20, 25 }, -- VOID (7th login day), 67, SMILEY, YIN YANG, GLITCH
	},
	TIER_ORDER = { "common", "rare", "epic", "legendary" },

	-- Coins per finished match (not AFK: the player aimed or pressed power at least once per round).
	-- Duel is ~4 min, a 4-player match ~1.8 min [sim]: both pay ~13 coins a minute, so no mode is a farm.
	COINS = {
		duel = { play = 25, win = 25 },
		ffa = { play = 11, win = 15 }, -- win = 1st place
		react = 2, -- each reaction of the player's balls
		reactMax = 10,
		ko = 3, -- each KO by the player
		koMax = 9,
	},

	-- Levels. XP per match and the need() curve stay in Config.XP (T2.2: 150 + 50 * (L - 1)).
	-- [sim] the curve flattens at XP_CAP so a level after 20 is ~2 days of a 30-min player, never a wall.
	XP_CAP = 1100,
	-- levels 2..9 give a random ball (Config.LEVEL_BALLS). From level 10 on every level gives coins,
	-- every 5th level also crystals (a small free taste of the draft actions) [idea «Валюты»].
	LEVEL_COINS = 150,
	LEVEL_CRYSTALS_EVERY = 5,
	LEVEL_CRYSTALS = 15,

	-- Direct buy of a chosen ball by tier: coins (the free path, [brief] "все 27 бесплатно"),
	-- crystals, or a Robux developer product per tier (server remembers the chosen ball before the prompt).
	PRICE = {
		coins = { common = 1000, rare = 3000, epic = 6000, legendary = 12000 }, -- [idea] 1000/2500/5000/8000 -> [sim]: free 30 min/day = ~7 weeks
		crystals = { common = 50, rare = 100, epic = 200, legendary = 400 },
		robux = { common = 49, rare = 99, epic = 199, legendary = 399 }, -- [brief]
	},

	-- Ball of the day: one ball the player lacks, changes at 00:00 UTC (real timer), 30% off in coins and crystals
	-- [brief]. The same ball is not offered again for REPEAT_DAYS. Legendaries take part.
	DAILY_BALL = { off = 0.3, repeatDays = 7 },

	-- Spins. Odds are per tier, then a uniform ball of that tier the player lacks (no repeats [brief]).
	-- A rolled tier the player owns fully moves its share DOWN to the nearest lower tier with a missing ball;
	-- with nothing lower the outcome is `refund` (always shown as its own line with its own %). Shares never move
	-- up, so a late spin can't become a cheap sure legendary. The odds screen shows these personal odds.
	SPIN = {
		coins = {
			price = 1000, -- [brief]
			odds = { common = 70, rare = 24, epic = 5, legendary = 1 }, -- "шансы хуже" [brief]
			refund = 250, -- coins back
			-- pity: an epic or better at the latest on this spin since the last epic+ (visible counter)
			pity = { tier = "epic", every = 10 },
		},
		crystals = {
			price = 49, -- [brief]
			price10 = 399, -- 10 spins, the pity counter runs through all 10
			odds = { common = 50, rare = 30, epic = 15, legendary = 5 }, -- [brief]
			refund = 15, -- crystals back
			pity = { tier = "legendary", every = 30 }, -- [brief] "легендарный не позже 30-го"
		},
	},

	-- Crystal packs, developer products [brief]. Bonus grows with size; "best value" badge on 650.
	CRYSTAL_PACKS = {
		{ crystals = 50, robux = 49 },
		{ crystals = 110, robux = 99 },
		{ crystals = 300, robux = 249 },
		{ crystals = 650, robux = 499, best = true },
		{ crystals = 1400, robux = 999 },
		{ crystals = 3750, robux = 2499 },
	},

	-- Duel draft actions [brief]. Paid "Any ball" at most 2 per duel; a duel has 3 picks per player.
	DRAFT = {
		freeAny = 1, -- per duel (VIP +1)
		reroll = 5, -- "New 3"
		any = 10,
		paidAnyMax = 2,
		trial = 15, -- a ball the player lacks, for one duel
		freeTrials = 1, -- per day (00:00 UTC)
	},

	-- Login reward [sim: coins small, crystals a taste ~5/day]: day N of the player's login days, missed days don't reset it [decision, docs/economy.md].
	-- Cycle 1 day 7 = VOID; later cycles repeat with LATER_DAY7 instead.
	DAILY = {
		{ coins = 50 },
		{ coins = 75 },
		{ crystals = 15 }, -- [idea] "3-й день входа"
		{ coins = 100 },
		{ coins = 150, trials = 1 },
		{ coins = 200 },
		{ ball = 13 }, -- VOID [brief]
	} :: { Gift },
	LATER_DAY7 = { coins = 300, crystals = 10 } :: Gift,

	-- 3 quests a day (VIP 4), new at 00:00 UTC, about reactions and balls [brief]. All 3 take ~8 matches (~25 min) [sim].
	QUESTS = {
		perDay = 3,
		easy = 60, -- e.g. play 3 matches
		mid = 80, -- e.g. make 3 WILDFIRE, win 1 duel with a rare ball
		hard = 120, -- e.g. win 3 duels, 10 reactions in one day
		allDone = 50, -- coins for all of the day
		-- M3.1: one quest of each tier a day, drawn from these (kinds: Logic/Daily.luau). Counted only in matches
		-- where the player was not AFK. WILDFIRE: fire on grass, every new player has FIRE and PLANT.
		pool = {
			{ id = "play3", tier = "easy", kind = "play", goal = 3, text = "PLAY 3 MATCHES" },
			{ id = "rx10", tier = "easy", kind = "rx", goal = 10, text = "MAKE 10 REACTIONS" },
			{ id = "ko2", tier = "easy", kind = "ko", goal = 2, text = "KNOCK OUT 2 BALLS" },
			{ id = "win2", tier = "mid", kind = "win", goal = 2, text = "WIN 2 MATCHES" },
			{ id = "wild3", tier = "mid", kind = "rxk", k = "WILDFIRE", goal = 3, text = "MAKE 3 WILDFIRE" },
			{ id = "rare1", tier = "mid", kind = "rareWin", goal = 1, text = "WIN WITH A RARE+ BALL" },
			{ id = "duel3", tier = "hard", kind = "duelWin", goal = 3, text = "WIN 3 DUELS" },
			{ id = "rx30", tier = "hard", kind = "rx", goal = 30, text = "MAKE 30 REACTIONS" },
			{ id = "top2", tier = "hard", kind = "ffaTop", goal = 2, text = "WIN 2 4-PLAYER MATCHES" },
		} :: { Quest },
	},

	-- Reaction book, 42 reactions [brief]: coins for each new one, crystals every 10, a big prize for all 42.
	BOOK = { coins = 25, crystalsEvery = 10, crystals = 10, allCoins = 1000 },

	-- A match with a Roblox friend (not a bot, both active): +50% XP [idea «Бонус за игру с другом»], +25% coins,
	-- for the first FRIEND_DAILY matches of the day (anti-farm).
	FRIEND = { xp = 1.5, coins = 1.25, daily = 20 },

	-- Duel win streak (bots count: they fill empty seats; streak shown over the avatar). Coins once per step.
	STREAK = { [3] = 50, [5] = 100, [10] = 300 },

	-- Starter pack: once per player, offered on session 2-3 with a real 48 h timer that never restarts [brief].
	STARTER = { robux = 99, epicChoice = true, crystals = 100, coins = 1000, hours = 48 },

	-- Game passes [brief]
	PASSES = {
		coins2x = { robux = 249, mult = 2 }, -- match coins only (not quests, login, book)
		vip = { robux = 249, freeAny = 1, quests = 1 }, -- tag, gold name, +1 free Any ball, +1 quest
		fastSpin = { robux = 99 }, -- no spin animation, x10 button on the coin spin too
	},

	-- Offers: at most one modal offer per OFFER_GAP seconds, never in a match; a "No" adds OFFER_COOLDOWN.
	OFFER_GAP = 600,
	OFFER_COOLDOWN = 1800,

	-- Login-day chests, once each [docs/economy.md «Вехи д14–д42»]. Missed calendar days do not skip or reset
	-- them: the counter is login days, same as the 7-day track. Copied from tools/econ/sim.luau (E3.2).
	-- Weekly, and worth a real ball: a rare is 3 000, an epic is 6 000. 6 000 every week was too much —
	-- a 30-min free player then finished the 27 balls on day 28, and x2 (249 R$) only saved about 5 days.
	MILE = {
		{ day = 14, coins = 4000 },
		{ day = 21, coins = 4000, crystals = 50 },
		{ day = 28, coins = 6000 },
		{ day = 35, coins = 6000, crystals = 50 },
		{ day = 42, coins = 8000 },
	} :: { Mile },

	-- Cosmetic sink. Buyable at any ball count. No combat stats. Coin price is the free path,
	-- Robux is a one-time developer product. Order is the sim's buy order (cheapest first), not the shelf groups.
	LOOKS = {
		{ id = "frame_wood", coins = 2000, robux = 49 },
		{ id = "skin_ink", coins = 2500, robux = 49 },
		{ id = "skin_chalk", coins = 2500, robux = 49 },
		{ id = "trail_dust", coins = 2500, robux = 49 },
		{ id = "force_pulse", coins = 3000, robux = 49 },
		{ id = "skin_stripe", coins = 3500, robux = 79 },
		{ id = "skin_speckle", coins = 3500, robux = 79 },
		{ id = "trail_sparks", coins = 4000, robux = 79 },
		{ id = "skin_marble", coins = 5000, robux = 99 },
		{ id = "skin_candy", coins = 5000, robux = 99 },
		{ id = "frame_iron", coins = 5000, robux = 79 },
		{ id = "trail_ribbon", coins = 6000, robux = 99 },
		{ id = "force_ring", coins = 6000, robux = 99 },
		{ id = "skin_chrome", coins = 7000, robux = 129 },
		{ id = "skin_glass", coins = 7000, robux = 129 },
		{ id = "frame_gold", coins = 8000, robux = 149 },
		{ id = "trail_comet", coins = 8000, robux = 149 },
		{ id = "skin_neon", coins = 9000, robux = 149 },
		{ id = "skin_galaxy", coins = 9000, robux = 149 },
		{ id = "force_burst", coins = 9000, robux = 149 },
		{ id = "trail_rainbow", coins = 10000, robux = 199 },
		{ id = "skin_prism", coins = 12000, robux = 199 },
		{ id = "skin_crown", coins = 12000, robux = 199 },
		{ id = "frame_myth", coins = 12000, robux = 199 },
		{ id = "force_nova", coins = 14000, robux = 249 },
		{ id = "trail_void", coins = 14000, robux = 249 },
		-- Prestige shelf. A 2 h/day player cleared the 26 looks above by ~day 84 and then hoarded
		-- ~80 000 coins by day 120. These four keep a next purchase in front of that player.
		{ id = "podium_spot", coins = 18000, robux = 299 },
		{ id = "ko_card", coins = 22000, robux = 349 },
		{ id = "trail_eclipse", coins = 28000, robux = 399 },
		{ id = "frame_champion", coins = 36000, robux = 499 },
	} :: { Look },
}
