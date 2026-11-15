--!strict
-- Cosmetic shelf (docs/economy.md «Косметика»). Pure. Prices are Economy.LOOKS.
-- A look can be bought for coins, or granted by a developer-product receipt, at any ball count.
-- Buying the same id again does not spend. The equipped row is one skin, one trail, one force effect, one frame,
-- plus the lobby podium and the KO card. The match reads only Looks.match (skin, trail, force, frame).
local Wallet = require("./Wallet")

local Looks = {}

local NEL = 27

export type Hit = { id: string, n: number, already: boolean }

export type On = {
	skin: string,
	trail: string,
	force: string,
	frame: string,
	podium: boolean,
	ko: boolean,
	ball: number,
}

export type Shelf = {
	n: number,
	need: number,
	owned: { string },
	on: On,
	robux: { [string]: number },
}

local function blank(): On
	return { skin = "", trail = "", force = "", frame = "", podium = false, ko = false, ball = -1 }
end

local function byId(E: any, id: unknown): any
	if type(id) ~= "string" or #id == 0 or #id > 32 then
		return nil
	end
	for _, look in E.LOOKS do
		if look.id == id then
			return look
		end
	end
	return nil
end

-- skin / trail / force / frame, or the two single lobby pieces.
local function slot(id: string): string?
	if string.sub(id, 1, 5) == "skin_" then
		return "skin"
	elseif string.sub(id, 1, 6) == "trail_" then
		return "trail"
	elseif string.sub(id, 1, 6) == "force_" then
		return "force"
	elseif string.sub(id, 1, 6) == "frame_" then
		return "frame"
	elseif id == "podium_spot" then
		return "podium"
	elseif id == "ko_card" then
		return "ko"
	end
	return nil
end

function Looks.count(d: any): number
	local seen: { [number]: boolean } = {}
	local n = 0
	if type(d.balls) ~= "table" then
		return 0
	end
	for _, e in d.balls do
		if type(e) == "number" and e == e and e % 1 == 0 and e >= 0 and e < NEL and not seen[e] then
			seen[e] = true
			n += 1
		end
	end
	return n
end

local function owned(d: any, id: string): boolean
	return type(d.looks) == "table" and table.find(d.looks, id) ~= nil
end

-- Old id -> new id. A look renamed in Economy.LOOKS must be listed here, or bought copies keep the old id
-- (kept on the profile, but not shown). Never remove an entry.
Looks.RENAMED = {} :: { [string]: string }

function Looks.known(E: any, id: unknown): boolean
	return byId(E, id) ~= nil
end

-- Renames old ids and drops a worn row the player does not own. An id the catalog no longer has stays owned
-- (it may have been bought for Robux): it is only taken off the worn row.
function Looks.repair(d: any, E: any)
	if type(d.looks) ~= "table" then
		d.looks = {}
	end
	if type(d.worn) ~= "table" then
		d.worn = blank()
	end
	local ok: { [string]: boolean } = {}
	if type(E) == "table" and type(E.LOOKS) == "table" then
		for _, look in E.LOOKS do
			ok[look.id] = true
		end
	end
	local seen: { [string]: boolean } = {}
	for i = #d.looks, 1, -1 do
		local id = d.looks[i]
		local to = Looks.RENAMED[id]
		if to then
			id = to
			d.looks[i] = to
		end
		if seen[id] then
			table.remove(d.looks, i)
		else
			seen[id] = true
		end
	end
	local w = d.worn
	for _, key in { "skin", "trail", "force", "frame" } do
		local id = w[key]
		if type(id) == "string" and Looks.RENAMED[id] then
			id = Looks.RENAMED[id]
			w[key] = id
		end
		if type(id) ~= "string" or not ok[id] or not owned(d, id) then
			w[key] = ""
		end
	end
	if w.skin == "" or type(w.ball) ~= "number" or not table.find(d.balls, w.ball) then
		w.ball = -1
	end
	w.podium = w.podium == true and owned(d, "podium_spot")
	w.ko = w.ko == true and owned(d, "ko_card")
end

-- "ok" added it, "have" it was already owned, "no" unknown id. Coins are not touched.
-- A receipt stays unacknowledged only on "no", so a bad id can be retried. Ball count does not matter.
function Looks.grant(d: any, id: unknown, E: any): string
	local look = byId(E, id)
	if not look or type(d.looks) ~= "table" then
		return "no"
	end
	if owned(d, look.id) then
		return "have"
	end
	table.insert(d.looks, look.id)
	return "ok"
end

-- Coin purchase. Nil, and nothing spent, when the id is unknown or the balance is short.
-- The same id again returns already = true and does not spend. Ball count does not matter.
function Looks.buy(d: any, id: unknown, E: any, log: { Wallet.Flow }?): Hit?
	local look = byId(E, id)
	if not look or type(d.looks) ~= "table" then
		return nil
	end
	if owned(d, look.id) then
		return { id = look.id, n = 0, already = true }
	end
	if not Wallet.spend(d, "coins", look.coins, look.id, "Shop", log) then
		return nil
	end
	table.insert(d.looks, look.id)
	return { id = look.id, n = look.coins, already = false }
end

-- Equips an owned look into its one slot. A skin uses `ball` when that ball is owned, otherwise the previous
-- ball or the first owned ball. Returns false without changing the row.
function Looks.wear(d: any, id: unknown, ball: unknown, E: any): boolean
	local look = byId(E, id)
	local key = if look then slot(look.id) else nil
	if not look or not key or not owned(d, look.id) or type(d.worn) ~= "table" then
		return false
	end
	local w = d.worn
	if key == "podium" then
		w.podium = true
	elseif key == "ko" then
		w.ko = true
	elseif key == "skin" then
		local e = ball
		local function holds(x: unknown): number?
			if type(x) == "number" and x == x and x % 1 == 0 and table.find(d.balls, x) then
				return x
			end
			return nil
		end
		local pick = holds(e) or holds(w.ball) or holds(d.balls[1])
		if not pick then
			return false
		end
		w.skin = look.id
		w.ball = pick
	else
		w[key] = look.id
	end
	return true
end

export type Match = { skin: string, trail: string, force: string, frame: string, ball: number }

-- The worn skin, trail, force effect and frame for the match seat. Only owned, known ids; a skin only with its
-- owned ball. nil when nothing is worn (bots and players without looks draw the default ball).
function Looks.match(d: any, E: any): Match?
	if type(d) ~= "table" or type(d.worn) ~= "table" or type(E) ~= "table" or type(E.LOOKS) ~= "table" then
		return nil
	end
	local w = d.worn
	local function pick(key: string): string
		local id = w[key]
		if type(id) == "string" and byId(E, id) and slot(id) == key and owned(d, id) then
			return id
		end
		return ""
	end
	local ball = if type(w.ball) == "number"
			and type(d.balls) == "table"
			and table.find(d.balls, w.ball)
		then w.ball
		else -1
	local out: Match = {
		skin = if ball >= 0 then pick("skin") else "",
		trail = pick("trail"),
		force = pick("force"),
		frame = pick("frame"),
		ball = ball,
	}
	if out.skin == "" then
		out.ball = -1
	end
	if out.skin == "" and out.trail == "" and out.force == "" and out.frame == "" then
		return nil
	end
	return out
end

-- Profile view. `products.looks` is the asset-id table; only ids above 0 are sent (0 is not for sale).
function Looks.snapshot(d: any, E: any, products: any): Shelf
	local robux: { [string]: number } = {}
	local ids = if type(products) == "table" and type(products.looks) == "table" then products.looks else {}
	if type(E) == "table" and type(E.LOOKS) == "table" then
		for _, look in E.LOOKS do
			local id = ids[look.id]
			if type(id) == "number" and id > 0 and id == math.floor(id) and id == id then
				robux[look.id] = id
			end
		end
	end
	local w = if type(d.worn) == "table" then d.worn else blank()
	-- only ids the shelf can draw; a retired id stays on the profile
	local have: { string } = {}
	if type(d.looks) == "table" then
		for _, id in d.looks do
			if byId(E, id) then
				table.insert(have, id)
			end
		end
	end
	return {
		n = Looks.count(d),
		need = NEL,
		owned = have,
		on = {
			skin = if type(w.skin) == "string" then w.skin else "",
			trail = if type(w.trail) == "string" then w.trail else "",
			force = if type(w.force) == "string" then w.force else "",
			frame = if type(w.frame) == "string" then w.frame else "",
			podium = w.podium == true,
			ko = w.ko == true,
			ball = if type(w.ball) == "number" then w.ball else -1,
		},
		robux = robux,
	}
end

return Looks
