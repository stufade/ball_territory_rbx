--!strict
-- Developer product asset ids (docs/economy.md «Монетизация»).
-- TODO(launch): paste real ids from Creator Dashboard → Monetization → Developer Products.
-- Every 0 is a placeholder, not a live asset id. Logic/Receipt ignores 0, so a receipt cannot grant
-- until that id is filled in. Do not invent ids.
-- `crystals` is parallel to Economy.CRYSTAL_PACKS. `ball` keys are Economy.PRICE.robux.
-- `looks` keys are Economy.LOOKS ids. The skin itself is granted by a later task; this file only records the product.
return {
	crystals = { 0, 0, 0, 0, 0, 0 },
	ball = { common = 0, rare = 0, epic = 0, legendary = 0 },
	starter = 0,
	looks = {
		frame_wood = 0,
		skin_ink = 0,
		skin_chalk = 0,
		trail_dust = 0,
		force_pulse = 0,
		skin_stripe = 0,
		skin_speckle = 0,
		trail_sparks = 0,
		skin_marble = 0,
		skin_candy = 0,
		frame_iron = 0,
		trail_ribbon = 0,
		force_ring = 0,
		skin_chrome = 0,
		skin_glass = 0,
		frame_gold = 0,
		trail_comet = 0,
		skin_neon = 0,
		skin_galaxy = 0,
		force_burst = 0,
		trail_rainbow = 0,
		skin_prism = 0,
		skin_crown = 0,
		frame_myth = 0,
		force_nova = 0,
		trail_void = 0,
		podium_spot = 0,
		ko_card = 0,
		trail_eclipse = 0,
		frame_champion = 0,
	},
}
