--!strict
-- The save did not load (server flag saveFail on the Profile view): a window over everything says so and offers
-- REJOIN (same place). It closes by itself when the server picks the real profile up later.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local Theme = require("./Theme")

local SaveFail = {}

export type Window = { root: Frame, shown: boolean }

function SaveFail.new(canvas: Frame): Window
	local root = Theme.frame(canvas, UDim2.fromScale(1, 1), nil, Color3.new(0, 0, 0))
	root.Name = "SaveFail"
	root.BackgroundTransparency = 0.45
	root.ZIndex = 900
	root.Active = true -- eats taps behind the window
	root.Visible = false
	local box =
		Theme.frame(root, UDim2.fromOffset(460, 250), UDim2.fromScale(0.5, 0.5), Theme.PANEL, Vector2.new(0.5, 0.5))
	box.ZIndex = 901
	Theme.round(box, 18)
	Theme.stroke(box, 4, Theme.INK)
	local msg = Theme.text(
		box,
		"Couldn't load your save. Rejoin to keep progress.",
		30,
		UDim2.fromOffset(400, 110),
		UDim2.fromOffset(30, 24),
		{ bold = true, wrap = true, z = 902 }
	)
	msg.Name = "Message"
	local btn = Instance.new("TextButton")
	btn.Name = "Rejoin"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Theme.GO
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(240, 70)
	btn.Position = UDim2.fromOffset(110, 150)
	btn.ZIndex = 902
	btn.Parent = box
	Theme.round(btn, 14)
	Theme.stroke(btn, 3, Theme.INK)
	Theme.text(btn, "REJOIN", 34, UDim2.fromScale(1, 1), nil, { bold = true, z = 903 })
	Theme.press(btn)
	btn.Activated:Connect(function()
		pcall(function()
			TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
		end)
	end)
	return { root = root, shown = false }
end

-- Called with every Profile view: the flag opens the window, its absence (the real profile arrived) closes it.
function SaveFail.setProfile(w: Window, view: { saveFail: boolean? })
	local on = view.saveFail == true
	if on ~= w.shown then
		w.shown = on
		w.root.Visible = on
	end
end

return SaveFail
