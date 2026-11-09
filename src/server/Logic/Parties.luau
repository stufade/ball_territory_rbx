--!strict
-- Parties, pure: who is in which party, who hosts it, pending invites. Every call checks its own rules and returns
-- an error word instead of throwing. Server glue (remotes, friends, teleport) lives in Party.luau.
local Parties = {}

export type Party = { id: number, host: number, members: { number }, friendsUntil: number }
export type Invite = { pid: number, endsAt: number }
export type Book = {
	max: number,
	ttl: number,
	gap: number,
	perParty: number,
	nextId: number,
	byId: { [number]: Party },
	of: { [number]: number },
	-- invites[target][inviter]
	invites: { [number]: { [number]: Invite } },
	-- last invite time by "inviter:target"
	sentAt: { [string]: number },
}

-- max people per party, ttl seconds per invite, gap seconds between invites to the same person,
-- perParty pending invites a party may have
function Parties.new(max: number, ttl: number, gap: number, perParty: number): Book
	return {
		max = max,
		ttl = ttl,
		gap = gap,
		perParty = perParty,
		nextId = 0,
		byId = {},
		of = {},
		invites = {},
		sentAt = {},
	}
end

function Parties.of(b: Book, uid: number): Party?
	local pid = b.of[uid]
	return if pid then b.byId[pid] else nil
end

function Parties.isHost(b: Book, uid: number): boolean
	local p = Parties.of(b, uid)
	return p ~= nil and p.host == uid
end

-- Leaves the current party. The next member becomes host; an empty party is gone. Returns the party left.
function Parties.leave(b: Book, uid: number): Party?
	local p = Parties.of(b, uid)
	if not p then
		return nil
	end
	b.of[uid] = nil
	local i = table.find(p.members, uid)
	if i then
		table.remove(p.members, i)
	end
	if #p.members == 0 then
		b.byId[p.id] = nil
	elseif p.host == uid then
		p.host = p.members[1]
		p.friendsUntil = 0
	end
	return p
end

-- New party with `uid` as host (leaves any other party). An existing own party is returned as is.
function Parties.create(b: Book, uid: number): Party
	local cur = Parties.of(b, uid)
	if cur and cur.host == uid then
		return cur
	end
	Parties.leave(b, uid)
	b.nextId += 1
	local p: Party = { id = b.nextId, host = uid, members = { uid }, friendsUntil = 0 }
	b.byId[p.id] = p
	b.of[uid] = p.id
	return p
end

local function pending(b: Book, pid: number, now: number): number
	local n = 0
	for _, list in b.invites do
		for _, inv in list do
			if inv.pid == pid and inv.endsAt > now then
				n += 1
			end
		end
	end
	return n
end

-- A member invites `target` of the same server.
function Parties.invite(b: Book, from: number, target: number, now: number): (boolean, string?)
	local p = Parties.of(b, from)
	if not p then
		return false, "no party"
	end
	if from == target or b.of[target] == p.id then
		return false, "already in party"
	end
	if #p.members >= b.max then
		return false, "party is full"
	end
	local key = `{from}:{target}`
	local last = b.sentAt[key]
	if last and now - last < b.gap then
		return false, "too fast"
	end
	if pending(b, p.id, now) >= b.perParty then
		return false, "too many invites"
	end
	b.sentAt[key] = now
	b.invites[target] = b.invites[target] or {}
	b.invites[target][from] = { pid = p.id, endsAt = now + b.ttl }
	return true, nil
end

-- Adds `uid` to the party `pid` (leaves its own first). Checks the party is alive and has room.
local function admit(b: Book, uid: number, pid: number): (Party?, string?)
	local p = b.byId[pid]
	if not p then
		return nil, "party is gone"
	end
	if b.of[uid] == pid then
		return p, nil
	end
	if #p.members >= b.max then
		return nil, "party is full"
	end
	Parties.leave(b, uid)
	table.insert(p.members, uid)
	b.of[uid] = pid
	return p, nil
end

function Parties.accept(b: Book, uid: number, from: number, now: number): (Party?, string?)
	local list = b.invites[uid]
	local inv = list and list[from]
	if not inv or inv.endsAt <= now then
		return nil, "invite expired"
	end
	(list :: any)[from] = nil
	return admit(b, uid, inv.pid)
end

function Parties.decline(b: Book, uid: number, from: number)
	local list = b.invites[uid]
	if list then
		list[from] = nil
	end
end

-- Joins the party hosted by `host` without an invite (friend invite link, checked by the caller).
function Parties.joinHost(b: Book, uid: number, host: number): (Party?, string?)
	local p = Parties.of(b, host)
	if not p or p.host ~= host then
		return nil, "party is gone"
	end
	return admit(b, uid, p.id)
end

function Parties.kick(b: Book, host: number, target: number): (Party?, string?)
	local p = Parties.of(b, host)
	if not p or p.host ~= host then
		return nil, "not host"
	end
	if target == host or b.of[target] ~= p.id then
		return nil, "not in party"
	end
	Parties.leave(b, target)
	return p, nil
end

-- Live invites to `uid`, oldest first: { from, pid, endsAt }. Expired ones are dropped.
function Parties.invitesFor(b: Book, uid: number, now: number): { { from: number, pid: number, endsAt: number } }
	local out = {}
	local list = b.invites[uid]
	if not list then
		return out
	end
	for from, inv in list do
		if inv.endsAt <= now or not b.byId[inv.pid] or b.of[uid] == inv.pid then
			list[from] = nil
		else
			table.insert(out, { from = from, pid = inv.pid, endsAt = inv.endsAt })
		end
	end
	table.sort(out, function(x, y)
		return x.endsAt < y.endsAt
	end)
	return out
end

-- Player left the server: out of the party, invites to and from it dropped.
function Parties.remove(b: Book, uid: number): Party?
	local p = Parties.leave(b, uid)
	b.invites[uid] = nil
	for _, list in b.invites do
		list[uid] = nil
	end
	for key in b.sentAt do
		local a, c = string.match(key, "^(-?%d+):(-?%d+)$")
		if tonumber(a) == uid or tonumber(c) == uid then
			b.sentAt[key] = nil
		end
	end
	return p
end

return Parties
