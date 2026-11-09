--!strict
-- Arenas from CollectionService tag "Arena" (docs/scene.md). One session per arena at a time.
local CollectionService = game:GetService("CollectionService")

local Arenas = {}

export type Arena = {
	aid: number,
	model: Model,
	name: string,
	mode: string,
	stands: { BasePart },
	session: any?,
}

local list: { Arena } = {}
local byModel: { [Instance]: Arena } = {}
local nextAid = 0

local function stands(model: Model): { BasePart }
	local out = {}
	for i = 1, 4 do
		local s = model:FindFirstChild(`Stand{i}`)
		if s and s:IsA("BasePart") then
			out[i] = s
		end
	end
	return out
end

local function add(inst: Instance)
	if byModel[inst] or not inst:IsA("Model") then
		return
	end
	local mode = inst:GetAttribute("Mode")
	if mode ~= "duel" and mode ~= "ffa" then
		warn(`[BT] arena {inst:GetFullName()} has no Mode attribute, skipped`)
		return
	end
	local a: Arena = {
		aid = 0,
		model = inst,
		name = inst.Name,
		mode = mode,
		stands = stands(inst),
	}
	byModel[inst] = a
	nextAid += 1
	a.aid = nextAid
	table.insert(list, a)
end

function Arenas.init()
	-- stable numbers on start: by name
	local tagged = CollectionService:GetTagged("Arena")
	table.sort(tagged, function(x, y)
		return x.Name < y.Name
	end)
	for _, inst in tagged do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal("Arena"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Arena"):Connect(function(inst)
		local a = byModel[inst]
		if a and not a.session then
			byModel[inst] = nil
			table.remove(list, table.find(list, a) :: number)
		end
	end)
	local counts = { duel = 0, ffa = 0 }
	for _, a in list do
		counts[a.mode] += 1
	end
	print(`[BT] arenas: {counts.duel} duel, {counts.ffa} ffa`)
end

function Arenas.all(): { Arena }
	return list
end

function Arenas.byId(aid: number): Arena?
	for _, a in list do
		if a.aid == aid then
			return a
		end
	end
	return nil
end

function Arenas.free(mode: string): { Arena }
	local out = {}
	for _, a in list do
		if a.mode == mode and a.session == nil and a.model.Parent then
			table.insert(out, a)
		end
	end
	return out
end

return Arenas
