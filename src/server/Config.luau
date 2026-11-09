--!strict
-- Server timers and limits of M1 matches (seconds). Round lengths live in Rules.Config.
return {
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
	SEATS = { duel = 2, ffa = 4, intro = 2 },
	-- weak bot of the first round: presses power after a full charge waited this long, aims in the final this often
	WEAK_PRESS = { 2.5, 5 },
	WEAK_FINAL_AIM = { 1.2, 2.4 },
	-- server stats print period with DebugBotMatches
	STAT_EVERY = 10,
}
