--!strict
-- Sounds of docs/audio.md. Cell paint stays silent (F1: the capture pop on every cell). Capture plays once on a KO.
-- A seated player hears the match; a plaza viewer does not (Render passes a no-op while view == true).
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local IDS: { [string]: { id: number, volume: number } } = {
	-- quiet hit: one shot per KO, never per painted cell
	capture = { id = 84349985737198, volume = 0.35 },
	power = { id = 126093538007975, volume = 0.6 },
	reaction = { id = 124991616061855, volume = 0.9 },
	final = { id = 79742001226121, volume = 0.8 },
	win = { id = 82466908590237, volume = 0.8 },
}

local Sfx = {}

local sounds: { [string]: Sound } = {}
local waiting: { [string]: boolean } = {}
local folder: Folder? = nil

local function emit(s: Sound)
	s.TimePosition = 0
	-- Client Sounds under SoundService often stay silent on :Play() for an rbxassetid. PlayLocalSound is the
	-- local 2D path. It no-ops until the asset is loaded, so play() retries from Loaded.
	SoundService:PlayLocalSound(s)
end

function Sfx.start()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "BTSfx"
	f.Parent = SoundService
	folder = f
	local list = {}
	for name, def in IDS do
		local s = Instance.new("Sound")
		s.Name = name
		s.Volume = def.volume
		s.Looped = false
		s.Parent = f
		s.SoundId = "rbxassetid://" .. def.id
		sounds[name] = s
		table.insert(list, s)
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

function Sfx.stop()
	if folder then
		folder:Destroy()
	end
	folder, sounds, waiting = nil, {}, {}
end

function Sfx.play(name: string)
	if not folder then
		Sfx.start()
	end
	local s = sounds[name]
	if not s then
		return
	end
	if s.IsLoaded then
		emit(s)
		return
	end
	if waiting[name] then
		return
	end
	waiting[name] = true
	s.Loaded:Once(function()
		waiting[name] = nil
		if sounds[name] == s then
			emit(s)
		end
	end)
end

return Sfx
