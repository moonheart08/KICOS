local raw_loadfile = ...
local syslog = _kicosCtx.syslog

syslog:info("Starting up!")
raw_loadfile("/slib/package.lua")() -- Finally load package management so we can have require() work.
_OSLOADLEVEL(1)
-- We use this literally once...
table.insert(package.locators, function(pname)
	return raw_loadfile("/lib/" .. pname .. ".lua")
end)
local locatorIdx = #package.locators
require("filesystem") -- get the filesystem API loaded so we can finally load things SANELY.
table.remove(package.locators, locatorIdx) -- Get that shit outta there we have a REAL filesystem now.
_OSLOADLEVEL(2)

coroutine.yield()
local VTerm = require("vterm")
local workers = require("workers")
require("env")._setupInitialEnv()
workers.runProgram("/sbin/dman.lua")

while _OSLOADLEVEL() ~= 3 do coroutine.yieldToOS() end

workers.runProgram("hello").onDeath:await()

while true do
	local reason
	
	workers.runProgram("shell").onDeath:await(function(worker, r) 
		reason = r 
		return true
	end)
	
	if reason == require("util").exitReasons.ended then
		break
	end
	-- Else, keep trying.
end

syslog:info("Exiting.")
computer.shutdown()