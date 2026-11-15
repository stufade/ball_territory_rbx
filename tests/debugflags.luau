--!strict
-- Studio-only tester flags (TODO(REMOVE BEFORE LAUNCH)): DebugNoPasses, DebugPaidRandomRestricted.
-- lune run tests/debugflags
local process = require("@lune/process")
local Debug = require("../src/server/Debug")

local fails, passed = 0, 0
local function check(cond: any, msg: string)
	if cond then
		passed += 1
	else
		fails += 1
		print("FAIL: " .. msg)
	end
end

local function env(studio: boolean, attrs: { [string]: any }): Debug.Env
	return {
		studio = function()
			return studio
		end,
		attr = function(name: string)
			return attrs[name]
		end,
	}
end

check(Debug.noPasses(env(true, { DebugNoPasses = true })), "studio + DebugNoPasses")
check(not Debug.noPasses(env(true, {})), "studio, flag unset")
check(not Debug.noPasses(env(true, { DebugNoPasses = false })), "studio, flag false")
check(not Debug.noPasses(env(false, { DebugNoPasses = true })), "live server ignores DebugNoPasses")
check(Debug.paidRandomRestricted(env(true, { DebugPaidRandomRestricted = true })), "studio + DebugPaidRandomRestricted")
check(not Debug.paidRandomRestricted(env(true, { DebugNoPasses = true })), "flags are independent")
check(
	not Debug.paidRandomRestricted(env(false, { DebugPaidRandomRestricted = true })),
	"live server ignores restricted flag"
)

print(`debugflags: {passed} passed, {fails} failed`)
if fails > 0 then
	process.exit(1)
end
