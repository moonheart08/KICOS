local syslog = {}

local logLevels = {
	["error"] = {0, "ERR "},
	["warning"] = {1, "WARN"},
	["info"] = {2, "INFO"},
	["debug"] = {3, "DBG "},
	["trace"] = {4, "TRCE"},
}

do
  local keys = {}
  for k in pairs(logLevels) do
    table.insert(keys, k)
  end
  for _, k in pairs(keys) do
    logLevels[logLevels[k][1]] = k
  end
end


local maxLogLevel = 3

function syslog.setMaxLogLevel(level) 
	if level > 4 or level < 0 then
		error("Log level must be between 0 and 4, inclusive. Got " .. tostring(level))
	end
	
	maxLogLevel = level
	
	syslog:info("Set global log level to %s", logLevels[level])
end

syslog.unsaved = {}

local workers = nil
local pipes = nil

function syslog:log(level, message, ...)
	local levelData = logLevels[level]
	if maxLogLevel < levelData[1] then
		return -- Be silent.
	end
	
	if _OSLOADLEVEL() == 2 and workers and pipes then
		local msg = "[" .. levelData[2] .. "]" .. "[" .. workers.current().name .. "] " .. string.format(message, ...)
		
		--pipes.stdout():write(msg)
		_G._logVTerm:printText(msg)
		table.insert(syslog.unsaved, msg)
		return
	end
	
	local msg = "[" .. levelData[2] .. "] " .. string.format(message, ...)
	
	_G._logVTerm:printText(msg)
	table.insert(syslog.unsaved, msg)
end

function syslog:error(message, ...)
	self:log("error", message, ...)
end

function syslog:warning(message, ...)
	self:log("warning", message, ...)
end

function syslog:info(message, ...)
	self:log("info", message, ...)
end

function syslog:debug(message, ...)
	self:log("debug", message, ...)
end

function syslog:trace(message, ...)
	self:log("trace", message, ...)
end

function syslog.loadReqs()
	workers = require("workers")
	pipes = require("pipes")
end

return syslog