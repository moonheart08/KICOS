local syslog = {}

local logLevels = {
	["error"] = {0, "ERR "},
	["warning"] = {1, "WARN"},
	["info"] = {2, "INFO"},
	["debug"] = {3, "DBG "},
	["trace"] = {4, "TRCE"},
}

local maxLogLevel = 4

function syslog:setMaxLogLevel(level) 
	if level > 4 or level < 0 then
		error("Log level must be between 0 and 4, inclusive. Got " .. tostring(level))
	end
	
	maxLogLevel = level
end

syslog.unsaved = {}

function syslog:log(level, message, ...)
	local levelData = logLevels[level]
	if maxLogLevel < levelData[1] then
		return -- Be silent.
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

return syslog