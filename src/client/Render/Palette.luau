--!strict
-- Colours, terrain look and heights of the board. Heights are fractions of CellSize.

local Palette = {}

-- Owner colours by slot (Geo.slots): 1 viewer, 2-4 others. Clearly different hues.
Palette.owner = {
	Color3.fromRGB(46, 140, 255),
	Color3.fromRGB(240, 64, 64),
	Color3.fromRGB(64, 205, 90),
	Color3.fromRGB(250, 200, 40),
}
Palette.neutral = Color3.fromRGB(198, 207, 224)
Palette.unknownOwner = Color3.fromRGB(150, 150, 150)

export type Look = { color: Color3, h: number, material: Enum.Material, mix: number }

-- By layer name of Config.TOP. mix: share of the terrain colour over the owner colour.
Palette.layer = {
	shock = { color = Color3.fromRGB(255, 245, 90), h = 0.06, material = Enum.Material.Neon, mix = 0.8 },
	burn = { color = Color3.fromRGB(255, 130, 30), h = 0.08, material = Enum.Material.Neon, mix = 0.8 },
	gas = { color = Color3.fromRGB(180, 230, 120), h = 0.12, material = Enum.Material.SmoothPlastic, mix = 0.65 },
	lava = { color = Color3.fromRGB(235, 70, 20), h = 0.1, material = Enum.Material.Neon, mix = 0.9 },
	toxic = { color = Color3.fromRGB(150, 60, 200), h = 0.1, material = Enum.Material.SmoothPlastic, mix = 0.75 },
	slime = { color = Color3.fromRGB(130, 220, 60), h = 0.16, material = Enum.Material.SmoothPlastic, mix = 0.75 },
	water = { color = Color3.fromRGB(60, 140, 240), h = 0.03, material = Enum.Material.SmoothPlastic, mix = 0.8 },
	ice = { color = Color3.fromRGB(190, 235, 255), h = 0.08, material = Enum.Material.SmoothPlastic, mix = 0.8 },
	glass = { color = Color3.fromRGB(215, 245, 245), h = 0.14, material = Enum.Material.SmoothPlastic, mix = 0.7 },
	rock = { color = Color3.fromRGB(105, 100, 105), h = 0.3, material = Enum.Material.SmoothPlastic, mix = 0.9 },
	sand = { color = Color3.fromRGB(225, 195, 120), h = 0.1, material = Enum.Material.SmoothPlastic, mix = 0.8 },
	bush = { color = Color3.fromRGB(40, 150, 60), h = 0.22, material = Enum.Material.SmoothPlastic, mix = 0.8 },
} :: { [string]: Look }

Palette.plain = { color = Palette.neutral, h = 0, material = Enum.Material.SmoothPlastic, mix = 0 } :: Look

-- Ball colour by element id (Config 0-26), index = id + 1.
Palette.element = {
	Color3.fromRGB(255, 90, 30), -- fire
	Color3.fromRGB(120, 220, 255), -- ice
	Color3.fromRGB(80, 200, 70), -- plant
	Color3.fromRGB(255, 235, 60), -- lightning
	Color3.fromRGB(40, 110, 255), -- water
	Color3.fromRGB(150, 100, 60), -- earth
	Color3.fromRGB(190, 240, 225), -- wind
	Color3.fromRGB(150, 70, 200), -- poison
	Color3.fromRGB(170, 175, 185), -- metal
	Color3.fromRGB(255, 250, 190), -- sun
	Color3.fromRGB(230, 200, 130), -- sand
	Color3.fromRGB(220, 50, 20), -- lava
	Color3.fromRGB(120, 230, 90), -- slime
	Color3.fromRGB(40, 20, 70), -- void
	Color3.fromRGB(200, 120, 255), -- crystal
	Color3.fromRGB(215, 90, 110), -- mushroom
	Color3.fromRGB(255, 220, 40), -- smiley
	Color3.fromRGB(255, 140, 190), -- 67
	Color3.fromRGB(170, 210, 140), -- gas
	Color3.fromRGB(120, 160, 255), -- sound
	Color3.fromRGB(235, 235, 235), -- yin yang
	Color3.fromRGB(240, 180, 70), -- time
	Color3.fromRGB(190, 200, 230), -- ghost
	Color3.fromRGB(70, 70, 80), -- bomb
	Color3.fromRGB(140, 220, 255), -- bubble
	Color3.fromRGB(60, 255, 150), -- glitch
	Color3.fromRGB(255, 120, 200), -- candy
}

function Palette.elementColor(e: number): Color3
	return Palette.element[e + 1] or Palette.unknownOwner
end

return Palette
