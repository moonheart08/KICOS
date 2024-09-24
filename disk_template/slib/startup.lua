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
local VTerm = require("vterm")
_G._logVTerm:redraw()
local fooo = coroutine.wrap(function() syslog:debug("test coroutine") end)
require("workers").top(function(...) syslog:info(...) end)