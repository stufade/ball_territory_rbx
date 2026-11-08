--!strict
-- Seeded random, same algorithm as seedRandom (mulberry32) in the web build.
local Rng = {}

export type Rand = () -> number

local band, bxor, bor, rshift, lshift = bit32.band, bit32.bxor, bit32.bor, bit32.rshift, bit32.lshift

-- Low 32 bits of a * b for unsigned 32-bit a and b (Math.imul).
local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xffff)
	return band(al * b + lshift(band(ah * b, 0xffff), 16), 0xffffffff)
end
Rng.imul = imul

function Rng.new(seed: number?): Rand
	if seed == nil then
		return function(): number
			return math.random()
		end
	end
	local a = band(seed, 0xffffffff)
	return function(): number
		a = band(a + 0x6D2B79F5, 0xffffffff)
		local t = a
		t = imul(bxor(t, rshift(t, 15)), bor(t, 1))
		t = bxor(t, band(t + imul(bxor(t, rshift(t, 7)), bor(t, 61)), 0xffffffff))
		return bxor(t, rshift(t, 14)) / 4294967296
	end
end

return Rng
