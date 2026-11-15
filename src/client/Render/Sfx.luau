--!strict
-- Sounds of docs/audio.md. Cell paint stays silent. "hit" is ball bumps and KOs, at most 4 times a second.
-- rare / epic / legend reuse power, reaction and win (own Sound, own Volume and PlaybackSpeed).
-- A seated player hears the match; a plaza viewer does not (Render passes a no-op while view == true).
-- The music bed is separate: a viewer still hears it. Id 0 never creates or plays a Sound.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

type Cue = {
	id: number,
	volume: number,
	speed: number?,
	looped: boolean?,
	limit: number?,
}

local IDS: { [string]: Cue } = {
	-- capture asset, used as the collision / KO tick. Not a new upload.
	hit = { id = 84349985737198, volume = 0.35, limit = 4 },
	power = { id = 126093538007975, volume = 0.6 },
	reaction = { id = 124991616061855, volume = 0.9 },
	final = { id = 79742001226121, volume = 0.8 },
	win = { id = 82466908590237, volume = 0.8 },
	-- tier stops on the spin strip. Same uploads as power / reaction / win, different playback.
	rare = { id = 126093538007975, volume = 0.42, speed = 1 },
	epic = { id = 124991616061855, volume = 0.62, speed = 1.15 },
	legend = { id = 82466908590237, volume = 0.74, speed = 1.2 },
	-- Music from the Roblox Creator Store (APMOfficial, free for all experiences), see docs/audio.md.
	-- Quieter than every effect (lowest effect cue is 0.35). Lobby = plaza track, match = own track.
	music = { id = 1837768352, volume = 0.2, looped = true },
	musicMatch = { id = 1837768494, volume = 0.14, looped = true },
}

local Sfx = {}

local sounds: { [string]: Sound } = {}
local waiting: { [string]: boolean } = {}
local recent: { [string]: { number } } = {}
local folder: Folder? = nil
local battle = false
local bed: Sound? = nil

local function emit(s: Sound)
	s.TimePosition = 0
	-- Client Sounds under SoundService often stay silent on :Play() for an rbxassetid. PlayLocalSound is the
	-- local 2D path. It no-ops until the asset is loaded, so play() retries from Loaded.
	SoundService:PlayLocalSound(s)
end

-- At most `limit` plays of this name in the last second. Other cues are not gated.
local function gated(name: string, limit: number): boolean
	local now = os.clock()
	local list = recent[name]
	if not list then
		list = {}
		recent[name] = list
	end
	local i = 1
	while i <= #list do
		if now - list[i] >= 1 then
			table.remove(list, i)
		else
			i += 1
		end
	end
	if #list >= limit then
		return false
	end
	table.insert(list, now)
	return true
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
		if def.id == 0 then
			continue
		end
		local s = Instance.new("Sound")
		s.Name = name
		s.Volume = def.volume
		s.PlaybackSpeed = def.speed or 1
		s.Looped = def.looped == true
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
	folder, sounds, waiting, recent = nil, {}, {}, {}
	battle, bed = false, nil
end

-- Music bed: lobby track on the plaza, match track while this client is in its own match (a viewer of
-- another match still hears the lobby track). Switching stops the other track. Id 0: no Sound, no play.
function Sfx.plaza(inBattle: boolean)
	battle = inBattle
	local name = if inBattle then "musicMatch" else "music"
	local def = IDS[name]
	if def.id == 0 then
		return
	end
	if not folder then
		Sfx.start()
	end
	local s = sounds[name]
	if not s or bed == s then
		return
	end
	local function go()
		if sounds[name] ~= s or battle ~= inBattle or bed == s then
			return
		end
		if bed then
			bed:Stop()
		end
		bed = s
		s.Volume = def.volume
		SoundService:PlayLocalSound(s)
	end
	if s.IsLoaded then
		go()
	elseif not waiting[name] then
		waiting[name] = true
		s.Loaded:Once(function()
			waiting[name] = nil
			go()
		end)
	end
end

function Sfx.play(name: string)
	local def = IDS[name]
	if not def or def.id == 0 then
		return
	end
	if def.limit and not gated(name, def.limit) then
		return
	end
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
