--!strict
-- Duel draft 1-2-2-1 with offers, pure. Each pick a side gets `size` random free balls of its own collection
-- (T2.2; nil = every ball) and may once per duel take any free ball of it instead. Bots pick the best counter from
-- their own offer, dealt from balls the rival person does not own when there are enough, so a bot does not take a
-- newcomer's few balls. A side with fewer own free balls than the offer gets the rest from all free balls.
-- Rules comes in through Offers.new: the server requires it from ReplicatedStorage, tests from the file.
local Offers = {}

export type Draft = { order: { number }, i: number, teams: { { number } } }
export type Offers = {
	duel: any,
	nel: number,
	draft: Draft,
	size: number,
	offer: { number },
	anyLeft: { number },
	rand: () -> number,
	-- own balls of sides 0 and 1 as sets (nil = every ball)
	own: { { [number]: boolean }? },
}

local function owns(o: Offers, side: number, e: number): boolean
	local set = o.own[side + 1]
	return set == nil or set[e] == true
end

local function sample(o: Offers, from: { number }, n: number, out: { number })
	for _ = 1, math.min(n, #from) do
		local i = math.floor(o.rand() * #from) + 1
		table.insert(out, table.remove(from, i) :: number)
	end
end

local function deal(o: Offers)
	local side = o.duel.draftTurn(o.draft)
	local rival = 1 - side
	local mine, spare = {}, {}
	for e = 0, o.nel - 1 do
		if o.duel.draftFree(o.draft, e) then
			local first = owns(o, side, e)
			if o.own[side + 1] == nil and o.own[rival + 1] ~= nil then
				-- a bot (or an all-balls side) leaves the rival person's own balls alone when it can
				first = not owns(o, rival, e)
			end
			table.insert(if first then mine else spare, e)
		end
	end
	local out = {}
	sample(o, mine, o.size, out)
	sample(o, spare, o.size - #out, out)
	o.offer = out
end

-- first = true: side 1 picks first. anyFree = free "any ball" picks per side (a number for both, or one per side).
-- own = own balls of sides 0 and 1 (nil = every ball).
function Offers.new(
	Rules: any,
	first: boolean,
	size: number,
	anyFree: number | { number },
	rand: () -> number,
	own: { { number }? }?
): Offers
	local sets: { { [number]: boolean }? } = {}
	for side = 1, 2 do
		local list = own and own[side]
		if list then
			local set = {}
			for _, e in list do
				set[e] = true
			end
			sets[side] = set
		end
	end
	local anyLeft = if type(anyFree) == "table" then table.clone(anyFree) else { anyFree, anyFree }
	local o: Offers = {
		duel = Rules.Duel,
		nel = Rules.Config.NEL,
		draft = Rules.Duel.newDraft(first),
		size = size,
		offer = {},
		anyLeft = anyLeft,
		rand = rand,
		own = sets,
	}
	deal(o)
	return o
end

function Offers.turn(o: Offers): number
	return o.duel.draftTurn(o.draft)
end

function Offers.done(o: Offers): boolean
	return o.duel.draftDone(o.draft)
end

function Offers.teams(o: Offers): { { number } }
	return o.draft.teams
end

-- Current offer of the side whose turn it is (empty for the other side).
function Offers.offerFor(o: Offers, side: number): { number }
	return if side == Offers.turn(o) then table.clone(o.offer) else {}
end

function Offers.canAny(o: Offers, side: number): boolean
	return (o.anyLeft[side + 1] or 0) > 0
end

local function take(o: Offers, side: number, e: number): boolean
	if not o.duel.draftPick(o.draft, side, e) then
		return false
	end
	if not Offers.done(o) then
		deal(o)
	else
		o.offer = {}
	end
	return true
end

-- Pick from the offer.
function Offers.pick(o: Offers, side: number, e: number): boolean
	if side ~= Offers.turn(o) or not table.find(o.offer, e) then
		return false
	end
	return take(o, side, e)
end

-- Free "any ball": any free element of the side's collection, once per duel.
function Offers.any(o: Offers, side: number, e: number): boolean
	if
		side ~= Offers.turn(o)
		or not Offers.canAny(o, side)
		or not o.duel.draftFree(o.draft, e)
		or not owns(o, side, e)
	then
		return false
	end
	if not take(o, side, e) then
		return false
	end
	o.anyLeft[side + 1] -= 1
	return true
end

-- Time ran out: a random ball of the offer.
function Offers.timeout(o: Offers): number
	local side = Offers.turn(o)
	local e = o.offer[math.floor(o.rand() * #o.offer) + 1]
	take(o, side, e)
	return e
end

-- Bot turn: best counter to the rival's picks among its offer.
function Offers.bot(o: Offers): number
	local side = Offers.turn(o)
	local rivals = o.draft.teams[2 - side]
	local best, be = -math.huge, o.offer[1]
	for _, e in o.offer do
		local s = o.duel.duelScore(e, rivals) + o.rand() * 2.5
		if s > best then
			best, be = s, e
		end
	end
	take(o, side, be)
	return be
end

return Offers
