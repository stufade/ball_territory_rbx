--!strict
-- AnalyticsService events of M1 (T1.7): onboarding funnel once per player per server, custom events by mode.
-- Analytics must never break a match, so every call is guarded.
local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- Onboarding funnel, steps in the order a new player meets them.
Analytics.Step = {
	Join = 1,
	FirstRoundStart = 2,
	HintAim = 3,
	HintPower = 4,
	HintReact = 5, -- the first reaction of the round
	HintFinal = 6,
	FirstRoundEnd = 7,
	SecondMatch = 8,
}

local NAMES = {}
for name, n in Analytics.Step do
	NAMES[n] = name
end

local done: { [Player]: { [number]: boolean } } = {}

local function safe(what: string, f: () -> ())
	local ok, err = (pcall :: any)(f)
	if not ok then
		warn(`[BT] analytics {what}: {err}`)
	end
end

function Analytics.step(player: Player, n: number)
	local d = done[player]
	if not d then
		d = {}
		done[player] = d
	end
	if d[n] then
		return
	end
	d[n] = true
	safe("onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, NAMES[n])
	end)
end

local HINT_STEP = {
	aim = Analytics.Step.HintAim,
	power = Analytics.Step.HintPower,
	react = Analytics.Step.HintReact,
	final = Analytics.Step.HintFinal,
}

function Analytics.hint(player: Player, k: string)
	local n = HINT_STEP[k]
	if n then
		Analytics.step(player, n)
	end
end

-- Custom events: MatchStart, MatchEnd (value 1 win / 0 not), MatchLeave (value = seconds played), QueueWait (seconds).
function Analytics.custom(player: Player, name: string, value: number, mode: string, result: string?)
	safe(name, function()
		local fields: { [string]: string } = {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = mode,
		}
		if result then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = result
		end
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
end

-- M3.1 economy (docs/economy.md «Что делать luau-coder» 8): every source and sink of coins and crystals.
-- f: Logic/Wallet.Flow {cur, n, sink, kind (AnalyticsEconomyTransactionType name), why (item SKU), bal}.
function Analytics.flows(player: Player, log: { any })
	for _, f in log do
		safe("economy", function()
			AnalyticsService:LogEconomyEvent(
				player,
				if f.sink then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source,
				if f.cur == "coins" then "Coins" else "Crystals",
				f.n,
				f.bal,
				f.kind,
				f.why
			)
		end)
	end
end

local function event(player: Player, name: string, value: number, f1: string?, f2: string?)
	safe(name, function()
		local fields: { [string]: string } = {}
		if f1 then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = f1
		end
		if f2 then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = f2
		end
		AnalyticsService:LogCustomEvent(player, name, value, fields)
	end)
end

-- Login reward claimed: value = login days so far; day of the cycle and the cycle.
function Analytics.login(player: Player, n: number, pos: number, cycle: number)
	event(player, "LoginDay", n, `day {pos}`, `cycle {cycle}`)
end

-- Once per profile load: balls owned (value) on day N since the first visit (D7/D14/D30), and the book.
function Analytics.collection(player: Player, balls: number, day: number, book: number)
	local d = `d{if day >= 30 then "30+" elseif day >= 14 then "14-29" elseif day >= 7 then "7-13" else tostring(day)}`
	event(player, "Collection", balls, d, `book {book // 10 * 10}`)
end

-- M3.2 hooks (spins and offers do not exist in M3.1): a spin (coins | crystals, tier, pity counter after),
-- an offer (what, shown | declined | bought).
function Analytics.spin(player: Player, kind: string, tier: string, pity: number)
	event(player, "Spin", pity, kind, tier)
end

-- Once per session when PolicyService answers. hidden = both paid spins stay off (not a broken shop).
function Analytics.paidRandom(player: Player, restricted: boolean)
	event(player, "PaidRandom", if restricted then 1 else 0, if restricted then "hidden" else "shown", "spin")
end

function Analytics.offer(player: Player, what: string, action: string)
	event(player, "Offer", 1, what, action)
end

-- A cosmetic (docs/economy.md «Косметика»): the look id, paid with coins or Robux.
function Analytics.look(player: Player, id: string, pay: string)
	event(player, "Look", 1, id, pay)
end

function Analytics.forget(player: Player)
	done[player] = nil
end

return Analytics
