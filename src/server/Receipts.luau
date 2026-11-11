--!strict
-- The one ProcessReceipt for developer products. Product ids live in Products.luau (0 until the dashboard
-- ids exist). Grant rules are Logic/Receipt. This file finds the player, waits for the profile, saves, then
-- acknowledges. PurchaseGranted is returned only after the PurchaseId is in the saved profile.
local Players = game:GetService("Players")

local Analytics = require("./Analytics")
local Config = require("./Config")
local Products = require("./Products")
local Profiles = require("./Profiles")
local Receipt = require("./Logic/Receipt")

local Receipts = {}

local catalog = Receipt.index(Config.ECON, Products)
local WAIT = 20

local function handle(receipt: any): string
	if type(receipt) ~= "table" or type(receipt.PlayerId) ~= "number" then
		return "NotProcessedYet"
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return "NotProcessedYet"
	end
	local deadline = os.clock() + WAIT
	local profile = Profiles.get(player)
	while not profile and player.Parent == Players and os.clock() < deadline do
		task.wait(0.5)
		profile = Profiles.get(player)
	end
	if not profile then
		return "NotProcessedYet"
	end
	local log = {}
	local result = Receipt.apply(profile.data, receipt, player.UserId, catalog, Config.ECON, log)
	if result == "later" then
		return "NotProcessedYet"
	end
	if result == "granted" then
		Profiles.showGain(player, log)
		local spec = catalog[receipt.ProductId]
		if spec and spec.kind == "look" and spec.id then
			Analytics.look(player, spec.id, "robux")
		end
		print(`[BT] {player.Name} developer product {receipt.ProductId} ({receipt.PurchaseId})`)
	end
	if not Profiles.commit(player) then
		return "NotProcessedYet"
	end
	return "PurchaseGranted"
end

function Receipts.start()
	local ok, market = pcall(function()
		return game:GetService("MarketplaceService")
	end)
	if not ok then
		return
	end
	market.ProcessReceipt = function(receipt)
		local decision = handle(receipt)
		if decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end :: any
end

return Receipts
