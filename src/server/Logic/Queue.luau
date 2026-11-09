--!strict
-- Matchmaking queue, pure. People join a mode alone or as a party group (one entry, always in the same match).
-- A match starts at once when entries fill the seats, or after `wait` seconds of the oldest entry with bots on the
-- empty seats. Needs a free arena.
local Queue = {}

export type Entry = { id: number, ids: { number }, mode: string, at: number }
export type Queue = {
	wait: number,
	seats: { [string]: number },
	lists: { [string]: { Entry } },
	where: { [number]: Entry },
}
export type Group = { mode: string, ids: { number } }

function Queue.new(wait: number, seats: { [string]: number }): Queue
	local lists = {}
	for mode in seats do
		lists[mode] = {}
	end
	return { wait = wait, seats = seats, lists = lists, where = {} }
end

-- Takes the whole entry of `id` out of the queue. Returns the ids of that entry (a party leaves together).
function Queue.leave(q: Queue, id: number): { number }?
	local e = q.where[id]
	if not e then
		return nil
	end
	for _, other in e.ids do
		q.where[other] = nil
	end
	local list = q.lists[e.mode]
	local i = table.find(list, e)
	if i then
		table.remove(list, i)
	end
	return e.ids
end

-- Joins `mode` with one id or a group of ids, leaving any other entry first. Returns false for an unknown mode,
-- an empty group or a group bigger than the seats.
function Queue.join(q: Queue, who: number | { number }, mode: string, now: number): boolean
	local ids: { number } = if type(who) == "table" then table.clone(who) else { who :: number }
	local seats = q.seats[mode]
	if not q.lists[mode] or #ids == 0 or #ids > seats then
		return false
	end
	local cur = q.where[ids[1]]
	if #ids == 1 and cur and cur.mode == mode and #cur.ids == 1 then
		return true
	end
	for _, id in ids do
		Queue.leave(q, id)
	end
	local e: Entry = { id = ids[1], ids = ids, mode = mode, at = now }
	table.insert(q.lists[mode], e)
	for _, id in ids do
		q.where[id] = e
	end
	return true
end

function Queue.mode(q: Queue, id: number): string?
	local e = q.where[id]
	return if e then e.mode else nil
end

-- People (not entries) waiting in a mode.
function Queue.count(q: Queue, mode: string): number
	local n = 0
	local list: { Entry } = q.lists[mode] or {}
	for _, e in list do
		n += #e.ids
	end
	return n
end

-- When the queue of the person's mode gives up waiting for people (bots join after this).
function Queue.deadline(q: Queue, id: number): number?
	local e = q.where[id]
	if not e then
		return nil
	end
	return q.lists[e.mode][1].at + q.wait
end

-- Entries that fit the seats in queue order, starting with the oldest.
local function fill(list: { Entry }, seats: number): ({ Entry }, number)
	local picked, n = {}, 0
	for _, e in list do
		if n + #e.ids <= seats then
			table.insert(picked, e)
			n += #e.ids
			if n == seats then
				break
			end
		end
	end
	return picked, n
end

-- Groups ready to start. `free[mode]` is the number of free arenas; it is lowered for each group.
function Queue.poll(q: Queue, now: number, free: { [string]: number }): { Group }
	local out = {}
	for mode, list in q.lists do
		local seats = q.seats[mode]
		while #list > 0 and (free[mode] or 0) > 0 do
			local picked, n = fill(list, seats)
			if n < seats and now - list[1].at < q.wait then
				break
			end
			local ids = {}
			for _, e in picked do
				table.remove(list, table.find(list, e) :: number)
				for _, id in e.ids do
					q.where[id] = nil
					table.insert(ids, id)
				end
			end
			free[mode] -= 1
			table.insert(out, { mode = mode, ids = ids })
		end
	end
	return out
end

return Queue
