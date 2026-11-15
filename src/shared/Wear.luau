--!strict
-- Paint of the worn looks in the match (base colour, accent, pattern), the same values as the shop previews in
-- UI/Shelf. Cosmetic only. Ids are Economy.LOOKS.
local function HEX(h: string): Color3
	return Color3.fromHex(h)
end

export type Paint = { base: Color3, accent: Color3, pat: string }

local PAINT: { [string]: Paint } = {
	skin_ink = { base = HEX("#1a1a28"), accent = HEX("#6a6aff"), pat = "ink" },
	skin_chalk = { base = HEX("#f4f0e4"), accent = HEX("#b4aa90"), pat = "chalk" },
	skin_stripe = { base = HEX("#ff4d6a"), accent = HEX("#ffe15a"), pat = "stripe" },
	skin_speckle = { base = HEX("#3d6bff"), accent = HEX("#ffffff"), pat = "speckle" },
	skin_marble = { base = HEX("#ece8f4"), accent = HEX("#8a84a8"), pat = "marble" },
	skin_candy = { base = HEX("#ff78d2"), accent = HEX("#7af6ff"), pat = "stripe" },
	skin_chrome = { base = HEX("#d5dde8"), accent = HEX("#6c7890"), pat = "chrome" },
	skin_glass = { base = HEX("#9ee6ff"), accent = HEX("#ffffff"), pat = "glass" },
	skin_neon = { base = HEX("#10141c"), accent = HEX("#39ffb0"), pat = "neon" },
	skin_galaxy = { base = HEX("#1c1240"), accent = HEX("#d2b0ff"), pat = "stars" },
	skin_prism = { base = HEX("#f4f4ff"), accent = HEX("#ff6ad5"), pat = "prism" },
	skin_crown = { base = HEX("#ffd24a"), accent = HEX("#e09a14"), pat = "crown" },
	trail_dust = { base = HEX("#e0c48a"), accent = HEX("#fff2cc"), pat = "dust" },
	trail_sparks = { base = HEX("#ffb03a"), accent = HEX("#fff1a0"), pat = "sparks" },
	trail_ribbon = { base = HEX("#ff6ad5"), accent = HEX("#ffffff"), pat = "ribbon" },
	trail_comet = { base = HEX("#7ecbff"), accent = HEX("#ffffff"), pat = "comet" },
	trail_rainbow = { base = HEX("#ff5a7a"), accent = HEX("#7af6ff"), pat = "rainbow" },
	trail_void = { base = HEX("#7a3cff"), accent = HEX("#2a1050"), pat = "void" },
	trail_eclipse = { base = HEX("#ffd63c"), accent = HEX("#1a1028"), pat = "eclipse" },
	force_pulse = { base = HEX("#ffd63c"), accent = HEX("#fff6c0"), pat = "pulse" },
	force_ring = { base = HEX("#7ad0ff"), accent = HEX("#ffffff"), pat = "ring" },
	force_burst = { base = HEX("#ff542c"), accent = HEX("#ffe15a"), pat = "burst" },
	force_nova = { base = HEX("#fff1a8"), accent = HEX("#ff9a3c"), pat = "nova" },
	frame_wood = { base = HEX("#c4844a"), accent = HEX("#7a4520"), pat = "wood" },
	frame_iron = { base = HEX("#b8c0d0"), accent = HEX("#5c6478"), pat = "iron" },
	frame_gold = { base = HEX("#ffe066"), accent = HEX("#d08a10"), pat = "gold" },
	frame_myth = { base = HEX("#d08cff"), accent = HEX("#6a28a8"), pat = "myth" },
	frame_champion = { base = HEX("#fff0a0"), accent = HEX("#ff9a1c"), pat = "champion" },
}

return PAINT
