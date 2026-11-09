--!strict
-- Screen geometry shared by the match camera and the UI: viewport, the side columns of the match layout, the Roblox
-- topbar to keep clear, and a debug phone emulation for Studio.
--
-- Emulation: workspace:SetAttribute("BTEmulate", "844x390") on the client. The screen becomes a centered band of that
-- aspect (black bars outside), the camera FOV is set so the band shows exactly what such a phone shows, and the
-- topbar buttons of an iPhone 12 landscape (x 70..247, y 11..49 at 844x390) are drawn as grey placeholders.
local GuiService = game:GetService("GuiService")

local Screen = {}

-- Match layout: each side column is this share of the screen width (avatar, plate, power button); the board fits
-- in the middle. Top strip: land bar and timer (design px of the 960x540 UI canvas).
Screen.COLUMN = 0.26
Screen.TOP_STRIP = 46
Screen.DESIGN_W = 960
Screen.DESIGN_H = 540

local changed = Instance.new("BindableEvent")
Screen.changed = changed.Event

local function emu(): Vector2?
	local v = workspace:GetAttribute("BTEmulate")
	if type(v) ~= "string" then
		return nil
	end
	local w, h = string.match(v, "^(%d+)x(%d+)$")
	if not w or not h then
		return nil
	end
	local x, y = tonumber(w) :: number, tonumber(h) :: number
	return if x > 0 and y > 0 then Vector2.new(x, y) else nil
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam then cam.ViewportSize else Vector2.new(1280, 720)
end

-- Band of the real viewport used as the screen: (offset, size) in viewport px.
function Screen.band(): (Vector2, Vector2)
	local vp = viewport()
	local e = emu()
	if not e then
		return Vector2.zero, vp
	end
	local w, h = vp.X, vp.X * e.Y / e.X
	if h > vp.Y then
		h, w = vp.Y, vp.Y * e.X / e.Y
	end
	return Vector2.new((vp.X - w) / 2, (vp.Y - h) / 2), Vector2.new(w, h)
end

function Screen.emulated(): Vector2?
	return emu()
end

-- Screen px of the emulated phone per real px (1 without emulation).
function Screen.k(): number
	local e = emu()
	if not e then
		return 1
	end
	local _, size = Screen.band()
	return size.X / e.X
end

-- Topbar area to keep clear, in band px: everything left of x and above y belongs to the Roblox buttons.
function Screen.topbar(): Vector2
	local e = emu()
	if e then
		local k = Screen.k()
		return Vector2.new(256 * k, 58 * k)
	end
	local r = GuiService.TopbarInset
	local inset = GuiService:GetGuiInset()
	local h = math.max(r.Max.Y, inset.Y)
	return Vector2.new(if r.Min.X > 0 then r.Min.X else 260, h)
end

-- Vertical FOV for the real viewport so that the band shows `bandFov` (degrees).
function Screen.fovFor(bandFov: number): number
	local _, size = Screen.band()
	local vp = viewport()
	if size.Y >= vp.Y - 0.5 then
		return bandFov
	end
	local t = math.tan(math.rad(bandFov) / 2) * vp.Y / size.Y
	return math.deg(2 * math.atan(t))
end

local function fire()
	changed:Fire()
end
workspace:GetAttributeChangedSignal("BTEmulate"):Connect(fire)
local function watchCam()
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(fire)
	end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCam()
	fire()
end)
watchCam()

return Screen
