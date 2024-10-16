local raw_loadfile <const> = ...
local syslog <const> = _kicosCtx.syslog

syslog:info("Starting up!")
raw_loadfile("/slib/package.lua")() -- Finally load package management so we can have require() work.
_OSLOADLEVEL(1)
-- We use this literally once...
table.insert(package.locators, function(pname)
	return raw_loadfile("/lib/" .. pname .. ".lua")
end)
coroutine.yield()
local locatorIdx = #package.locators
require("filesystem")                      -- get the filesystem API loaded so we can finally load things SANELY.
table.remove(package.locators, locatorIdx) -- Get that shit outta there we have a REAL filesystem now.
_OSLOADLEVEL(2)

coroutine.yield()
local workers <const> = require("workers")
syslog.loadReqs()
require("env")._setupInitialEnv()
workers.runProgram("/sbin/dman.lua")

while _OSLOADLEVEL() ~= 3 do coroutine.yieldToOS() end

workers.runProgram("/sbin/sman.lua")

local hasGpu = component.list("gpu")()

if hasGpu then
	local graphics <const> = require("graphics")

	graphics.switchToVDisplay(2)
end
