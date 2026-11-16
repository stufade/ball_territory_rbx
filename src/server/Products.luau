--!strict
-- Developer product and game pass ids of the live game (universe 10775439626), created 2026-11-15
-- on Creator Dashboard → Monetization. Table of names, prices and ids: docs/products.md.
-- `packs` is parallel to Economy.COIN_PACKS (E4: the former crystal packs, same ids). `ball` (tiers) and `looks`
-- (Economy.LOOKS ids) are no longer sold (E4: coins only); they stay so a late receipt still grants (Logic/Receipt).
-- `passes` keys are Economy.PASSES ids; they are game passes, not products (UserOwnsGamePassAsync).
return {
	packs = { 3732004217, 3732004316, 3732004487, 3732004521, 3732004528, 3732004535 },
	ball = { common = 3732004545, rare = 3732004551, epic = 3732004558, legendary = 3732004565 },
	starter = 3732004572,
	passes = { coins2x = 2089810640, vip = 2088964657, fastSpin = 2088970590 },
	looks = {
		frame_wood = 3732004585,
		skin_ink = 3732004599,
		skin_chalk = 3732004607,
		trail_dust = 3732004612,
		force_pulse = 3732004621,
		skin_stripe = 3732004630,
		skin_speckle = 3732004635,
		trail_sparks = 3732004642,
		skin_marble = 3732004647,
		skin_candy = 3732004657,
		frame_iron = 3732004666,
		trail_ribbon = 3732004673,
		force_ring = 3732004679,
		skin_chrome = 3732004690,
		skin_glass = 3732004699,
		frame_gold = 3732004712,
		trail_comet = 3732004718,
		skin_neon = 3732004725,
		skin_galaxy = 3732004735,
		force_burst = 3732004743,
		trail_rainbow = 3732004749,
		skin_prism = 3732004757,
		skin_crown = 3732004769,
		frame_myth = 3732004776,
		force_nova = 3732004784,
		trail_void = 3732004788,
		podium_spot = 3732004795,
		ko_card = 3732004803,
		trail_eclipse = 3732004806,
		frame_champion = 3732004812,
	},
}
