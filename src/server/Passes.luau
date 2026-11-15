--!strict
-- Game passes (Products.passes, docs/products.md) and the Robux prompts the server allows (Logic/Pay).
-- Ownership: UserOwnsGamePassAsync on join (retried), then PromptGamePassPurchaseFinished for an in-session buy.
-- A failed read counts as not owned for now and is tried again on the next join.
local Debug = require("./Debug")
local Products = require("./Products")

local Passes = {}

local owned: { [Player]: { [string]: boolean } } = {}
local changed: (Player) -> () = function() end

-- Looked up when used (like Receipts.luau), so a test server without MarketplaceService still loads.
local function market(): any
	local ok, m = pcall(function()
		return game:GetService("MarketplaceService")
	end)
	return if ok then m else nil
end

local function keyOf(passId: number): string?
	for key: string, id: number in Products.passes :: { [string]: number } do
		if id == passId then
			return key
		end
	end
	return nil
end

function Passes.owned(player: Player): { [string]: boolean }
	if Debug.noPasses() then -- TODO(REMOVE BEFORE LAUNCH)
		return {}
	end
	return owned[player] or {}
end

function Passes.has(player: Player, key: string): boolean
	if Debug.noPasses() then -- TODO(REMOVE BEFORE LAUNCH)
		return false
	end
	local o = owned[player]
	return o ~= nil and o[key] == true
end

function Passes.join(player: Player)
	local o: { [string]: boolean } = {}
	owned[player] = o
	task.spawn(function()
		local m = market()
		if not m then
			return
		end
		for key: string, id: number in Products.passes :: { [string]: number } do
			if type(id) ~= "number" or id <= 0 then
				continue
			end
			for try = 1, 3 do
				local ok, has = pcall(function()
					return m:UserOwnsGamePassAsync(player.UserId, id)
				end)
				if owned[player] ~= o then
					return
				end
				if ok then
					if has == true then
						o[key] = true
					end
					break
				end
				if try < 3 then
					task.wait(try * 2)
				end
			end
		end
		if owned[player] == o and next(o) then
			changed(player)
		end
	end)
end

function Passes.leave(player: Player)
	owned[player] = nil
end

-- Opens the prompt Logic/Pay allowed. A product prompt ends in ProcessReceipt (Receipts.luau).
function Passes.prompt(player: Player, offer: { product: number?, pass: number? })
	pcall(function()
		local m = market()
		if offer.pass then
			m:PromptGamePassPurchase(player, offer.pass)
		elseif offer.product then
			m:PromptProductPurchase(player, offer.product)
		end
	end)
end

-- `onChange` refreshes the client (the profile view carries the owned passes).
function Passes.start(onChange: (Player) -> ())
	changed = onChange
	local m = market()
	if not m then
		return
	end
	m.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = keyOf(passId)
		local o = owned[player]
		if key and o and not o[key] then
			o[key] = true
			changed(player)
		end
	end)
end

return Passes
