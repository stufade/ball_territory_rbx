--!strict
-- Seat rows of the match start (Net.Seat from Runner seats: e, name, userId, side, rec). Pure: vip and look are asked per person seat; a bot (rec nil) gets
-- neither and is drawn with the default ball. Looks are cosmetic: the rules never read them.
local Seats = {}

function Seats.rows(seats: { any }, vipOf: (rec: any) -> boolean, lookOf: (rec: any) -> any?): { { [string]: any } }
	local out = {}
	for _, s in seats do
		local vip = s.rec ~= nil and vipOf(s.rec)
		local look = if s.rec ~= nil then lookOf(s.rec) else nil
		table.insert(out, {
			e = s.e,
			name = s.name,
			userId = s.userId,
			side = s.side,
			vip = if vip then true else nil,
			look = look,
		})
	end
	return out
end

return Seats
