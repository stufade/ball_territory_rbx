--!strict
-- Sounds of docs/audio.md. Cell paint stays silent. "hit" is ball bumps and KOs, at most 4 times a second.
-- A seated player hears the match; a plaza viewer does not (Render passes a no-op while view == true).
-- The music bed is separate: a viewer still hears it. Id 0 never creates or plays a Sound.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

type Cue = {
	id: number,
	volume: number,
	speed: number?,
	looped: boolean?,
	limit: number?,
	cut: number?, -- seconds: fade out and stop here (library stings can be longer than the cue we want)
}

local IDS: { [string]: Cue } = {
	-- All ids are free Roblox / APM Creator Store assets (docs/audio.md has candidates and fallbacks).
	-- Not heard by the author: volumes and cuts are starting values, tune by ear.
	hit = { id = 16480568432, volume = 0.5, limit = 4, cut = 0.5 }, -- Roblox_Pinball_Bumper_Soft_Click_03
	power = { id = 1839901345, volume = 0.5, cut = 1.1 }, -- APM "Powered Up Chimes"
	reaction = { id = 108306323478967, volume = 0.7, cut = 1.3 }, -- APM "Whoosh Magic Spell"
	final = { id = 1837769225, volume = 0.7, cut = 2.4 }, -- APM "Retro Gamer (sting)", same album as the music
	win = { id = 1836473422, volume = 0.75, cut = 3.5 }, -- APM "Victory Fanfare Sting"
	-- tier stops on the spin strip
	rare = { id = 16480578737, volume = 0.5, cut = 0.8 }, -- Roblox_Pinball_8Bit_Blip_07
	epic = { id = 1846251193, volume = 0.6, cut = 2 }, -- APM Jackpot Mania "Win"
	legend = { id = 1846251212, volume = 0.7, cut = 3.2 }, -- APM Jackpot Mania "Star Prize"
	-- UI cues, quieter than the match sounds (Theme.press, Spin strip, Money.step)
	click = { id = 15675059323, volume = 0.3, limit = 6 }, -- Roblox_UI_Bright_Click
	tick = { id = 16480580213, volume = 0.25, limit = 12, cut = 0.25 }, -- Roblox_Pinball_8Bit_Blip_01
	coin = { id = 127645268874265, volume = 0.3, limit = 8, cut = 0.5 }, -- Roblox CoinTransfer_01
	-- Music from the Roblox Creator Store (APMOfficial, free for all experiences), see docs/audio.md.
	-- Quieter than every effect (UI cues are quieter still). Lobby = plaza track, match = own track.
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
local musicGroup: SoundGroup? = nil
local fades: { [Sound]: Tween } = {}
local cuts: { [Sound]: number } = {}

local function emit(s: Sound, def: Cue)
	s.TimePosition = 0
	s.Volume = def.volume
	local cut = def.cut
	if cut then
		-- fade out the tail and stop; a newer play of the same Sound makes the older timer a no-op
		cuts[s] = (cuts[s] or 0) + 1
		local stamp = cuts[s]
		task.delay(math.max(cut - 0.12, 0.05), function()
			if cuts[s] ~= stamp then
				return
			end
			TweenService:Create(s, TweenInfo.new(0.12), { Volume = 0 }):Play()
			task.delay(0.14, function()
				if cuts[s] == stamp then
					s:Stop()
				end
			end)
		end)
	end
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
	local g = Instance.new("SoundGroup")
	g.Name = "Music"
	g.Parent = SoundService
	musicGroup = g
	local list = {}
	for name, def in IDS do
		if def.id == 0 then
			continue
		end
		local s = Instance.new("Sound")
		if def.looped then
			s.SoundGroup = musicGroup
		end
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
	if musicGroup then
		musicGroup:Destroy()
	end
	for _, tw in fades do
		tw:Cancel()
	end
	table.clear(fades)
	table.clear(cuts)
	musicGroup = nil
	folder, sounds, waiting, recent = nil, {}, {}, {}
	battle, bed = false, nil
end

-- Music bed: lobby track on the plaza, match track while this client is in its own match (a viewer of
-- another match still hears the lobby track). The tracks are real Sounds in the Music SoundGroup, driven with
-- Play / Stop (IsPlaying tells the truth), one at a time: the old one fades out while the new one fades in.
local FADE = 0.5
local function fadeTo(s: Sound, volume: number, stopAfter: boolean)
	local old = fades[s]
	if old then
		old:Cancel()
	end
	local tw = TweenService:Create(s, TweenInfo.new(FADE, Enum.EasingStyle.Linear), { Volume = volume })
	fades[s] = tw
	tw.Completed:Once(function(state)
		if fades[s] == tw then
			fades[s] = nil
		end
		if stopAfter and state == Enum.PlaybackState.Completed then
			s:Stop()
		end
	end)
	tw:Play()
end

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
	local prev = bed
	-- a track still fading out from an earlier switch must not overlap a third one
	for other, def2 in IDS do
		local o = sounds[other]
		if def2.looped and o and o ~= s and o ~= prev and o.IsPlaying then
			local tw = fades[o]
			if tw then
				tw:Cancel()
				fades[o] = nil
			end
			o:Stop()
		end
	end
	bed = s
	if prev then
		fadeTo(prev, 0, true)
	end
	local tw = fades[s]
	if tw then
		tw:Cancel()
		fades[s] = nil
	end
	if not s.IsPlaying then
		s.Volume = 0
		s.TimePosition = 0
		s:Play()
	end
	fadeTo(s, def.volume, false)
end

-- Silences the music bed (fade out, then Stop). Plaza() starts it again.
function Sfx.silence()
	local prev = bed
	bed = nil
	if prev then
		fadeTo(prev, 0, true)
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
		emit(s, def)
		return
	end
	if waiting[name] then
		return
	end
	waiting[name] = true
	s.Loaded:Once(function()
		waiting[name] = nil
		if sounds[name] == s then
			emit(s, def)
		end
	end)
end

return Sfx
