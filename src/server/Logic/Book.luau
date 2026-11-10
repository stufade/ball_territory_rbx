--!strict
-- Reaction book (M3.1): 42 reactions, each found once. A new one pays BOOK.coins, every BOOK.crystalsEvery-th new one
-- BOOK.crystals, all of them BOOK.allCoins. Pure; the reactions come from a not AFK match of the player's balls.
local Wallet = require("./Wallet")

local Book = {}

export type Found = { new: { string }, crystals: number, coins: number, all: boolean }

-- kinds: reaction name -> times in the match; names: the 42 (Rules.Config.REACTIONS).
function Book.add(d: any, kinds: { [string]: number }, names: { string }, B: any, log: { Wallet.Flow }?): Found
	local out: Found = { new = {}, crystals = 0, coins = 0, all = false }
	-- in book order, so the same match always gives the same order
	for _, k in names do
		if (kinds[k] or 0) > 0 and not table.find(d.book, k) then
			table.insert(d.book, k)
			table.insert(out.new, k)
			out.coins += Wallet.add(d, "coins", B.coins, "book_new", "Gameplay", log)
			if #d.book % B.crystalsEvery == 0 then
				out.crystals += Wallet.add(d, "crystals", B.crystals, `book_{#d.book}`, "Gameplay", log)
			end
			if #d.book == #names then
				out.all = true
				out.coins += Wallet.add(d, "coins", B.allCoins, "book_all", "Gameplay", log)
			end
		end
	end
	return out
end

return Book
