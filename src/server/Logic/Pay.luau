--!strict
-- Which Robux purchase the server lets a client open (docs/products.md). Pure: the prompt itself is Passes.prompt.
-- The client names a key and an optional number; the server picks the product or pass id, so a second starter
-- pack, an owned pass, or Fast Spin under a paid-random ban never opens a prompt.
-- E4: Robux buy only coin packs, the starter pack and the passes. Balls and looks are coins only ("off").
--   "pack"         arg = coin pack index (Economy.COIN_PACKS)
--   "starter"      arg = the epic chosen for the pack
--   "pass_<key>"   a game pass of Economy.PASSES
local Progress = require("./Progress")
local Receipt = require("./Receipt")

local Pay = {}

export type Offer = { product: number?, pass: number?, key: string }

local function live(id: any): number?
	if type(id) == "number" and id == id and id > 0 and id % 1 == 0 then
		return id
	end
	return nil
end

local function int(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < lo or v > hi then
		return nil
	end
	return v
end

local function tierOf(E: any, e: number): string?
	for tier, list in E.TIERS do
		if table.find(list, e) then
			return tier
		end
	end
	return nil
end

-- Nil and a reason ("bad", "owned", "policy", "off") when the prompt must not open.
-- `blocked` is PolicyService ArePaidRandomItemsRestricted (unknown counts as blocked), `passes` the owned passes.
function Pay.offer(
	d: Progress.Data,
	key: any,
	arg: any,
	E: any,
	ids: any,
	blocked: boolean,
	passes: { [string]: boolean }
): (Offer?, string?)
	if type(key) ~= "string" or #key == 0 or #key > 32 then
		return nil, "bad"
	end
	local id: number? = nil
	if key == "pack" then
		local i = int(arg, 1, #E.COIN_PACKS)
		if not i then
			return nil, "bad"
		end
		id = live(ids.packs[i])
	elseif key == "starter" then
		if d.starterBought then
			return nil, "owned"
		end
		local e = int(arg, 0, 26)
		if not e or tierOf(E, e) ~= "epic" then
			return nil, "bad"
		end
		if Progress.owns(d, e) then
			return nil, "owned"
		end
		id = live(ids.starter)
		if id and not Receipt.choose(d, "epic", e, E) then
			return nil, "bad"
		end
	elseif string.sub(key, 1, 5) == "pass_" then
		local name = string.sub(key, 6)
		if type(E.PASSES[name]) ~= "table" then
			return nil, "bad"
		end
		if passes[name] then
			return nil, "owned"
		end
		-- Fast Spin only speeds up paid spins: not offered where paid random is restricted
		if name == "fastSpin" and blocked then
			return nil, "policy"
		end
		local pass = live(ids.passes and ids.passes[name])
		if not pass then
			return nil, "off"
		end
		return { pass = pass, key = key }, nil
	else
		return nil, "bad"
	end
	if not id then
		return nil, "off"
	end
	return { product = id, key = key }, nil
end

-- Pass keys a client may still be offered: not owned, and Fast Spin not under a paid-random ban.
function Pay.passOffers(E: any, ids: any, blocked: boolean, passes: { [string]: boolean }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for name in E.PASSES do
		if not passes[name] and live(ids.passes and ids.passes[name]) and not (name == "fastSpin" and blocked) then
			out[name] = true
		end
	end
	return out
end

return Pay
