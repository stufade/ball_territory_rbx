--!strict
local Rules = require("@rules")

print("Rules version: " .. Rules.getVersion())
assert(Rules.getVersion() == Rules.VERSION, "version mismatch")
