--!strict
-- Pure rules: no Roblox API, must run in Roblox and in lune.
local Rules = {}

Rules.VERSION = "0.0.1"

function Rules.getVersion(): string
	return Rules.VERSION
end

return Rules
