--!strict
-- Server timers and limits of M1 matches (seconds). Round lengths live in Rules.Config.
return {
	-- debug switch: everybody owns all 27 balls (starter pick of all 27, "any ball" on every draft pick).
	-- false (players): each person drafts from the collection of the profile (T2.2). In Studio the same is on with
	-- the ServerScriptService attribute DebugAllBalls = true.
	TEST_ALL_BALLS = false,
	-- wait for other people in the queue, then bots fill the seats
	QUEUE_WAIT = 5,
	-- duel draft 1-2-2-1: time per pick, balls offered per pick, free "any ball" picks per duel
	DRAFT_TURN = 15,
	OFFER = 3,
	ANY_FREE = 1,
	-- ball choice before a duel round (the loser sees the winner's ball)
	CHOOSE_TIME = 10,
	-- ball pick before a 4-player match, and the starter pick of the first entry
	FFA_PICK = 10,
	INTRO_PICK = 8,
	-- aim before launch; the match starts earlier when every person pressed launch
	AIM_TIME = 6,
	INTRO_AIM = 10,
	-- pause after a duel round, result screen before the lobby
	ROUND_PAUSE = 3.5,
	RESULT_TIME = 5,
	-- bots "think" in the draft so their turn is visible
	BOT_THINK = 0.9,
	-- at most this many 1/30 s steps per server frame (catch-up cap)
	MAX_STEPS = 6,
	SEATS = { duel = 2, ffa = 4, intro = 2, tutor = 2 },
	-- weak bot of the first round: presses power after a full charge waited this long, aims in the final this often
	WEAK_PRESS = { 2.5, 5 },
	WEAK_FINAL_AIM = { 1.2, 2.4 },
	-- server stats print period with DebugBotMatches
	STAT_EVERY = 10,
	-- M1.6 lobby: walk speed on the plaza (Roblox default 16)
	LOBBY_WALK = 26,
	-- spectators: a person on the plaza watches the nearest live arena within WATCH_ENTER studs, keeps it up to
	-- WATCH_LEAVE; distance to the board centre with depth (z) counted at WATCH_DEPTH, so the board in front wins
	-- (arenas are 52 studs apart, the plaza is 30..74 studs in front); at most WATCH_MAX viewers per arena;
	-- checked every WATCH_EVERY s
	WATCH_ENTER = 32,
	WATCH_LEAVE = 40,
	WATCH_DEPTH = 0.35,
	WATCH_MAX = 6,
	WATCH_EVERY = 0.25,
	-- a friend invite link lets friends join the party this long after the host opened the invite prompt
	FRIENDS_OPEN = 600,
	-- T2.1: the first entry is the tutorial cartoon (false: the old starter pick and the hinted round vs a weak bot)
	TUTORIAL = true,
	-- tutorial scenes (s). A: elements react, B: power grabs land, C: choose a direction, D: the final, played alone.
	TUT = {
		-- the first tutorial waits for the client's hello this long at most
		helloWait = 20,
		-- transition: the client fades to black, the next scene starts behind it
		fade = 0.4,
		-- a waiting cue: no action this long -> the tutorial does it for the player (AFK, tests)
		afk = 20,
		-- A: the scene stands still this long, then the fire flies; watch the wildfire this long; tap cue by watchMax
		look = 1.2,
		afterWild = 1.5,
		watchMax = 7,
		-- B: the land fills this long after the power
		grab = 2.6,
		-- C: a tap within `cone` rad of the enemy counts (and flies straight at it); after `misses` misses any tap
		-- counts; a miss flies this long before the scene repeats; the KO shows this long; no KO by hitWait -> repeat
		cone = 0.6,
		misses = 2,
		missShow = 1.3,
		koShow = 2.2,
		hitWait = 3,
		-- D: the final round, the player's head start (land disc radius, cells), the bot turns every aim s and keeps
		-- `keep` cells away from the player
		final = 15,
		land = 4.0,
		botAim = { 0.5, 0.9 },
		keep = 4.5,
	},
	-- T2.2 profile (DataStore): store name, autosave period, session lock, retries; a lock older than LOCK_TTL
	-- belongs to a dead server; a live one is waited for LOCK_WAIT s, then taken over (the old server stops saving)
	PROFILE = {
		store = "Profiles1",
		autosave = 60,
		lockTtl = 600,
		lockWait = 15,
		retries = 5,
		-- seconds between two writes of one key (DataStore allows one per 6 s)
		writeGap = 7,
	},
	-- T2.2 progression. Tiers are rarity and show, not strength (docs/idea-analysis.md, «Тиры»).
	TIERS = {
		common = { 0, 1, 3, 2, 4, 5, 6, 10 },
		rare = { 11, 7, 8, 12, 15, 18, 24, 26 },
		epic = { 9, 14, 19, 23, 22, 21 },
		legendary = { 13, 17, 16, 20, 25 },
	},
	-- the tutorial reward: the 4 starters one by one, then the free spin lands on one of these legendaries
	BASE_BALLS = { 0, 1, 3, 2 },
	SPIN_POOL = { 17, 16, 20, 25 },
	-- XP of a match: taking part, winning, each reaction and KO of the player's balls (capped), times the boost.
	-- With the 2x boost of the first 15 min level 2 comes after 2-3 matches (tests/profile prints the count).
	XP = {
		play = 20,
		win = 25,
		react = 2,
		reactMax = 10,
		ko = 5,
		koMax = 15,
		-- XP from level L to L+1: base + step * (L - 1), capped at Economy.XP_CAP (E3.1). step 100 (was 50):
		-- a 30-min player reaches level 9 (the last level ball) on day ~8, not day 5 (tools/econ/sim)
		base = 150,
		step = 100,
		boost = 2,
		boostTime = 15 * 60,
	},
	-- levels 2..LEVEL_BALLS each give a random ball not collected yet from these tiers (legendaries come from
	-- spins and the 7th day; brief «Прогрессия»: 8 random balls for levels 2-9)
	LEVEL_BALLS = 9,
	LEVEL_TIERS = { "common", "rare", "epic" },
	-- the reward screen moves on by itself after this long (AFK)
	REWARD_MAX = 90,
}
