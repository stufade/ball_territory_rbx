--!strict
-- Roblox friendships between people on this server (M3.1 friend bonus). IsFriendsWithAsync yields, so it is asked
-- when someone joins (against everybody here) and the answer is cached; a match end only reads the cache.
local Players = game:GetService("Players")

local Friends = {}

local cache: { [string]: boolean } = {}

local function key(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function ask(a: Player, b: Player)
	if a.UserId <= 0 or b.UserId <= 0 or a == b then
		return
	end
	local ok, yes = pcall(function()
		return a:IsFriendsWithAsync(b.UserId)
	end)
	if ok then
		cache[key(a.UserId, b.UserId)] = yes == true
	end
end

function Friends.are(a: Player, b: Player): boolean
	return cache[key(a.UserId, b.UserId)] == true
end

function Friends.joined(player: Player)
	for _, other in Players:GetPlayers() do
		if other ~= player then
			task.spawn(ask, player, other)
		end
	end
end

function Friends.left(player: Player)
	local id = tostring(player.UserId)
	for k in table.clone(cache) do
		local a, b = string.match(k, "^(%-?%d+):(%-?%d+)$")
		if a == id or b == id then
			cache[k] = nil
		end
	end
end

-- Tests and the debug fake friend: set a pair by hand.
function Friends.set(a: number, b: number, yes: boolean)
	cache[key(a, b)] = yes
end

return Friends
