local raw_loadfile = ...
local syslog = _kicosCtx.syslog

syslog:info("Starting up!")
raw_loadfile("/slib/package.lua")() -- Finally load package management so we can have require() work.
-- We use this literally once...
table.insert(package.locators, function(pname)
	return raw_loadfile("/lib/" .. pname .. ".lua")
end)
local locatorIdx = #package.locators
require("filesystem") -- get the filesystem API loaded so we can finally load things SANELY.
table.remove(package.locators, locatorIdx) -- Get that shit outta there we have a REAL filesystem now.
coroutine.yield()
local VTerm = require("vterm")
require("workers").runProgram("/bin/silly.lua")
coroutine.yieldToOS()
syslog:info("continuing :)")
coroutine.yieldToOS()
syslog:info("and being cooperative")

while true do coroutine.yieldToOS() end