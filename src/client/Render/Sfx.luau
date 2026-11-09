--!strict
-- Sounds of docs/audio.md. Capture is rate limited and quiet.
local SoundService = game:GetService("SoundService")

local IDS: { [string]: { id: number, volume: number } } = {
	capture = { id = 84349985737198, volume = 0.25 },
	power = { id = 126093538007975, volume = 0.6 },
	reaction = { id = 124991616061855, volume = 0.9 },
	final = { id = 79742001226121, volume = 0.8 },
	win = { id = 82466908590237, volume = 0.8 },
}
local CAPTURE_VOICES = 3
local CAPTURE_GAP = 1 / 8

local Sfx = {}

local sounds: { [string]: Sound } = {}
local captureVoices: { Sound } = {}
local nextVoice = 1
local lastCapture = 0
local folder: Folder? = nil

local function make(name: string): Sound
	local def = IDS[name]
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. def.id
	s.Volume = def.volume
	s.Parent = folder
	return s
end

function Sfx.start()
	if folder then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "BTSfx"
	f.Parent = SoundService
	folder = f
	for name in IDS do
		if name ~= "capture" then
			sounds[name] = make(name)
		end
	end
	for i = 1, CAPTURE_VOICES do
		captureVoices[i] = make("capture")
	end
end

function Sfx.stop()
	if folder then
		folder:Destroy()
	end
	folder, sounds, captureVoices = nil, {}, {}
end

function Sfx.play(name: string)
	local s = sounds[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- At most ~8 per second, whatever the number of captured cells.
function Sfx.capture()
	local now = os.clock()
	if now - lastCapture < CAPTURE_GAP or #captureVoices == 0 then
		return
	end
	lastCapture = now
	local s = captureVoices[nextVoice]
	nextVoice = nextVoice % #captureVoices + 1
	s.TimePosition = 0
	s:Play()
end

return Sfx
