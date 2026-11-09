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

function Analytics.forget(player: Player)
	done[player] = nil
end

return Analytics
