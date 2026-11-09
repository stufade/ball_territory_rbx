--!strict
-- Party on the plaza (M1.6): a small card at the top left (portraits of up to 4, host crown, who is playing, kick,
-- INVITE, LEAVE), the invite sheet (players of this server, Roblox friend invite with launch data: host and JobId)
-- and incoming invite cards. The server checks everything again (src/server/Party.luau).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require("./Theme")

local V2 = Vector2.new
local SLOT = 62

export type Ctx = { act: (verb: string, arg: number?) -> (), canvas: Vector2, topbar: Vector2 }

export type Panel = {
	root: Frame,
	ctx: Ctx,
	flash: (string) -> (),
	view: Net.PartyView?,
	open: boolean,
	sheet: boolean,
	shown: boolean,
	kickOf: number?,
}

local PartyPanel = {}

local function me(): number
	return Players.LocalPlayer.UserId
end

local function portrait(parent: Instance, uid: number, d: number, pos: UDim2): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundColor3 = Theme.SLOT
	img.Size = UDim2.fromOffset(d, d)
	img.Position = pos
	img.AnchorPoint = V2(0.5, 0)
	img.Image = if uid > 0 then `rbxthumb://type=AvatarHeadShot&id={uid}&w=150&h=150` else ""
	Theme.round(img, 999)
	Theme.stroke(img, 3, Theme.INK)
	img.Parent = parent
	return img
end

local function inviteFriends(p: Panel)
	local v = p.view
	if not v or not v.host then
		return
	end
	p.ctx.act(Net.Action.pfriends)
	local host = v.host
	task.spawn(function()
		local player = Players.LocalPlayer
		local okCan, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCan or not can then
			p.flash("Friend invites are not available here")
			return
		end
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = "Play Ball Territory with me!"
		opts.LaunchData = HttpService:JSONEncode({ h = host, j = game.JobId })
		local ok = pcall(function()
			SocialService:PromptGameInvite(player, opts)
		end)
		if not ok then
			p.flash("Couldn't open friend invites")
		end
	end)
end

-- Players of this server to invite, and the friend invite button.
local function sheet(p: Panel, layer: Frame)
	local cv = p.ctx.canvas
	local box =
		Theme.frame(layer, UDim2.fromOffset(470, 380), UDim2.fromOffset(cv.X / 2, cv.Y / 2), Theme.PANEL, V2(0.5, 0.5))
	box.Active = true
	Theme.round(box, 18)
	Theme.stroke(box, 4, Theme.INK)
	Theme.text(box, "INVITE TO PARTY", 32, UDim2.fromOffset(360, 40), UDim2.fromOffset(20, 12), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
	})
	local close =
		Theme.button(box, "X", UDim2.fromOffset(52, 48), UDim2.new(1, -10, 0, 10), Theme.BAD, nil, 26, V2(1, 0))
	close.Activated:Connect(function()
		p.sheet = false
		PartyPanel.render(p)
	end)
	local friends =
		Theme.button(box, "INVITE FRIENDS", UDim2.new(1, -40, 0, 60), UDim2.fromOffset(20, 64), Theme.GO, Theme.INK, 30)
	friends.Activated:Connect(function()
		inviteFriends(p)
	end)
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, -40, 1, -150)
	list.Position = UDim2.fromOffset(20, 136)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = box
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 6)
	lay.Parent = list
	local inParty: { [number]: boolean } = {}
	local members: { Net.PartyMember } = if p.view then p.view.members else {}
	for _, m in members do
		inParty[m.userId] = true
	end
	local n = 0
	for _, pl in Players:GetPlayers() do
		if pl == Players.LocalPlayer or inParty[pl.UserId] then
			continue
		end
		n += 1
		local row = Theme.frame(list, UDim2.new(1, -10, 0, 54), nil, Theme.SLOT)
		Theme.round(row, 12)
		portrait(row, pl.UserId, 42, UDim2.fromOffset(30, 6))
		Theme.text(row, pl.DisplayName, 24, UDim2.new(1, -200, 0, 30), UDim2.fromOffset(60, 12), {
			anchor = V2(0, 0),
			align = Enum.TextXAlignment.Left,
		})
		local inv = Theme.button(
			row,
			"INVITE",
			UDim2.fromOffset(116, 44),
			UDim2.new(1, -6, 0.5, 0),
			Theme.PURPLE,
			nil,
			22,
			V2(1, 0.5)
		)
		local uid = pl.UserId
		inv.Activated:Connect(function()
			p.ctx.act(Net.Action.pinvite, uid)
		end)
	end
	if n == 0 then
		Theme.text(list, "NOBODY ELSE ON THIS SERVER", 22, UDim2.new(1, 0, 0, 40), nil, { color = Theme.MUTED })
	end
	Theme.pop(box, 0, 0.8)
end

-- Party card: portraits in a row, INVITE and LEAVE.
local function card(p: Panel, layer: Frame, v: Net.PartyView)
	local host = v.host == me()
	local y0 = math.max(p.ctx.topbar.Y, 84)
	local box = Theme.frame(layer, UDim2.fromOffset(312, 206), UDim2.fromOffset(14, y0), Theme.PANEL)
	box.BackgroundTransparency = 0.1
	Theme.round(box, 16)
	Theme.stroke(box, 3, Theme.INK)
	Theme.text(box, `PARTY {#v.members}/4`, 26, UDim2.fromOffset(200, 30), UDim2.fromOffset(14, 6), {
		anchor = V2(0, 0),
		align = Enum.TextXAlignment.Left,
		color = Theme.YELLOW,
	})
	for i = 1, 4 do
		local m = v.members[i]
		local x = 45 + (i - 1) * 74
		if m then
			local img = portrait(box, m.userId, SLOT, UDim2.fromOffset(x, 42))
			if m.busy then
				img.ImageTransparency = 0.5
			end
			if m.userId == v.host then
				Theme.crown(box, 30, UDim2.fromOffset(x, 40), V2(0.5, 0.5))
			end
			local label = if m.userId == me() then "YOU" elseif m.busy then "PLAYING" else m.name
			if host and m.userId ~= me() and p.kickOf == m.userId then
				local kick = Theme.button(
					box,
					"KICK",
					UDim2.fromOffset(70, 34),
					UDim2.fromOffset(x, 106),
					Theme.BAD,
					nil,
					20,
					V2(0.5, 0)
				)
				kick.Activated:Connect(function()
					p.kickOf = nil
					p.ctx.act(Net.Action.pkick, m.userId)
				end)
			else
				Theme.text(box, label, 20, UDim2.fromOffset(72, 24), UDim2.fromOffset(x, 108), {
					anchor = V2(0.5, 0),
					color = if m.busy then Theme.YELLOW_TXT else Theme.TEXT,
				})
			end
			if host and m.userId ~= me() then
				local hit = Instance.new("TextButton")
				hit.BackgroundTransparency = 1
				hit.Text = ""
				hit.Size = UDim2.fromOffset(SLOT, SLOT)
				hit.Position = UDim2.fromOffset(x, 42)
				hit.AnchorPoint = V2(0.5, 0)
				hit.Parent = box
				hit.Activated:Connect(function()
					p.kickOf = if p.kickOf == m.userId then nil else m.userId
					PartyPanel.render(p)
				end)
			end
		else
			local add = Theme.button(
				box,
				"+",
				UDim2.fromOffset(SLOT, SLOT),
				UDim2.fromOffset(x, 42),
				Theme.SLOT,
				nil,
				36,
				V2(0.5, 0)
			)
			add.Activated:Connect(function()
				p.sheet = true
				PartyPanel.render(p)
			end)
		end
	end
	local invite =
		Theme.button(box, "INVITE", UDim2.fromOffset(140, 50), UDim2.fromOffset(14, 144), Theme.PURPLE, nil, 26)
	invite.Activated:Connect(function()
		p.sheet = true
		PartyPanel.render(p)
	end)
	local leave =
		Theme.button(box, "LEAVE", UDim2.fromOffset(140, 50), UDim2.fromOffset(298, 144), Theme.BAD, nil, 26, V2(1, 0))
	leave.Activated:Connect(function()
		p.open = false
		p.sheet = false
		p.ctx.act(Net.Action.pleave)
	end)
end

-- Incoming invites: one card each (JOIN / X), under the party card place.
local function invites(p: Panel, layer: Frame, v: Net.PartyView, y: number)
	local now = workspace:GetServerTimeNow()
	for _, inv in v.invites do
		if inv.endsAt <= now then
			continue
		end
		local box = Theme.frame(layer, UDim2.fromOffset(312, 104), UDim2.fromOffset(14, y), Theme.PANEL_HI)
		Theme.round(box, 16)
		Theme.stroke(box, 3, Theme.INK)
		portrait(box, inv.from, 50, UDim2.fromOffset(40, 8))
		Theme.text(
			box,
			`{string.upper(inv.name)} INVITES YOU`,
			22,
			UDim2.fromOffset(230, 26),
			UDim2.fromOffset(76, 10),
			{
				anchor = V2(0, 0),
				align = Enum.TextXAlignment.Left,
			}
		)
		local join =
			Theme.button(box, "JOIN", UDim2.fromOffset(150, 46), UDim2.fromOffset(76, 48), Theme.GO, Theme.INK, 24)
		local no = Theme.button(box, "X", UDim2.fromOffset(60, 46), UDim2.fromOffset(234, 48), Theme.BAD, nil, 24)
		local from = inv.from
		join.Activated:Connect(function()
			p.ctx.act(Net.Action.paccept, from)
		end)
		no.Activated:Connect(function()
			p.ctx.act(Net.Action.pdecline, from)
		end)
		Theme.pop(box, 0, 0.7)
		y += 112
	end
end

function PartyPanel.render(p: Panel)
	p.root:ClearAllChildren()
	local v = p.view
	if not p.shown or not v then
		return
	end
	local layer = Theme.clear(p.root, UDim2.fromScale(1, 1))
	local y = math.max(p.ctx.topbar.Y, 84)
	if v.id and p.open then
		card(p, layer, v)
		y += 214
	end
	invites(p, layer, v, y)
	if v.id and p.sheet then
		sheet(p, layer)
	end
end

function PartyPanel.new(parent: Instance, ctx: Ctx, flash: (string) -> ()): Panel
	local root = Instance.new("Frame")
	root.Name = "Party"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 5
	root.Parent = parent
	local p: Panel = {
		root = root,
		ctx = ctx,
		flash = flash,
		view = nil,
		open = false,
		sheet = false,
		shown = false,
		kickOf = nil,
	}
	local function players()
		if p.sheet then
			PartyPanel.render(p)
		end
	end
	Players.PlayerAdded:Connect(players)
	Players.PlayerRemoving:Connect(function()
		task.defer(players)
	end)
	return p
end

function PartyPanel.set(p: Panel, v: Net.PartyView)
	local was = p.view and p.view.id
	p.view = v
	if v.id and v.id ~= was then
		p.open = true
	elseif not v.id then
		p.open, p.sheet = false, false
	end
	PartyPanel.render(p)
end

function PartyPanel.open(p: Panel, on: boolean)
	p.open = on
	if not on then
		p.sheet = false
	end
	PartyPanel.render(p)
end

function PartyPanel.show(p: Panel, on: boolean)
	if p.shown ~= on then
		p.shown = on
		PartyPanel.render(p)
	end
end

-- Expired invites disappear.
function PartyPanel.step(p: Panel)
	local v = p.view
	if not v or not p.shown then
		return
	end
	local now = workspace:GetServerTimeNow()
	for i = #v.invites, 1, -1 do
		if v.invites[i].endsAt <= now then
			table.remove(v.invites, i)
			PartyPanel.render(p)
		end
	end
end

return PartyPanel
