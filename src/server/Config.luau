--!strict
-- Server timers and limits of M1 matches (seconds). Round lengths live in Rules.Config.
return {
	-- playtest switch: everybody owns all 27 balls (starter pick of all 27, "any ball" on every draft pick).
	-- false brings back M1: 4 starters, one free "any ball" per duel. There are no drops yet.
	TEST_ALL_BALLS = true,
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
}
