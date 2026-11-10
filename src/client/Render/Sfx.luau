--!strict
-- Sounds of docs/audio.md: only rare match moments (power, reaction, final, win). Cell capture is silent (F1: the
-- capture pop played many times a second and the user found it grating).
local SoundService = game:GetService("SoundService")

local IDS: { [string]: { id: number, volume: number } } = {
	power = { id = 126093538007975, volume = 0.6 },
	reaction = { id = 124991616061855, volume = 0.9 },
	final = { id = 79742001226121, volume = 0.8 },
	win = { id = 82466908590237, volume = 0.8 },
}

local Sfx = {}

local sounds: { [string]: Sound } = {}
local folder: Folder? = nil

function Sfx.start()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "BTSfx"
	f.Parent = SoundService
	folder = f
	for name, def in IDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = "rbxassetid://" .. def.id
		s.Volume = def.volume
		s.Parent = f
		sounds[name] = s
	end
end

function Sfx.stop()
	if folder then
		folder:Destroy()
	end
	folder, sounds = nil, {}
end

function Sfx.play(name: string)
	local s = sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

return Sfx
