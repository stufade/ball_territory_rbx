--!strict
-- Duel draft 1-2-2-1 with offers, pure. Each pick a side gets `size` random free balls (all 27 are open in M1)
-- and may once per duel take any free ball instead. Bots pick the best counter from their own offer.
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
}

local function deal(o: Offers)
	local free = {}
	for e = 0, o.nel - 1 do
		if o.duel.draftFree(o.draft, e) then
			table.insert(free, e)
		end
	end
	local out = {}
	for _ = 1, math.min(o.size, #free) do
		local i = math.floor(o.rand() * #free) + 1
		table.insert(out, table.remove(free, i) :: number)
	end
	o.offer = out
end

-- first = true: side 1 picks first. anyFree = free "any ball" picks per side.
function Offers.new(Rules: any, first: boolean, size: number, anyFree: number, rand: () -> number): Offers
	local o: Offers = {
		duel = Rules.Duel,
		nel = Rules.Config.NEL,
		draft = Rules.Duel.newDraft(first),
		size = size,
		offer = {},
		anyLeft = { anyFree, anyFree },
		rand = rand,
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

-- Free "any ball": any free element, once per duel.
function Offers.any(o: Offers, side: number, e: number): boolean
	if side ~= Offers.turn(o) or not Offers.canAny(o, side) or not o.duel.draftFree(o.draft, e) then
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
