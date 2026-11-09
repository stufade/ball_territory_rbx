--!strict
-- Matchmaking queue, pure. People join a mode; a group starts at once when the seats are full,
-- or after `wait` seconds of the oldest person with bots on the empty seats. Needs a free arena.
local Queue = {}

export type Entry = { id: number, mode: string, at: number }
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

-- Joins `mode`, leaving any other mode first. Returns false for an unknown mode.
function Queue.join(q: Queue, id: number, mode: string, now: number): boolean
	if not q.lists[mode] then
		return false
	end
	local cur = q.where[id]
	if cur and cur.mode == mode then
		return true
	end
	Queue.leave(q, id)
	local e = { id = id, mode = mode, at = now }
	table.insert(q.lists[mode], e)
	q.where[id] = e
	return true
end

function Queue.leave(q: Queue, id: number): boolean
	local e = q.where[id]
	if not e then
		return false
	end
	q.where[id] = nil
	local list = q.lists[e.mode]
	local i = table.find(list, e)
	if i then
		table.remove(list, i)
	end
	return true
end

function Queue.mode(q: Queue, id: number): string?
	local e = q.where[id]
	return if e then e.mode else nil
end

function Queue.count(q: Queue, mode: string): number
	local list = q.lists[mode]
	return if list then #list else 0
end

-- When the queue of the person's mode gives up waiting for people (bots join after this).
function Queue.deadline(q: Queue, id: number): number?
	local e = q.where[id]
	if not e then
		return nil
	end
	return q.lists[e.mode][1].at + q.wait
end

-- Groups ready to start. `free[mode]` is the number of free arenas; it is lowered for each group.
function Queue.poll(q: Queue, now: number, free: { [string]: number }): { Group }
	local out = {}
	for mode, list in q.lists do
		local seats = q.seats[mode]
		while #list > 0 and (free[mode] or 0) > 0 do
			if #list < seats and now - list[1].at < q.wait then
				break
			end
			local ids = {}
			for _ = 1, math.min(seats, #list) do
				local e = table.remove(list, 1) :: Entry
				q.where[e.id] = nil
				table.insert(ids, e.id)
			end
			free[mode] -= 1
			table.insert(out, { mode = mode, ids = ids })
		end
	end
	return out
end

return Queue
