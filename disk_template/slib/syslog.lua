local syslog = {}

local logLevels = {
	["error"] = { 0, "ERR " },
	["warning"] = { 1, "WARN" },
	["info"] = { 2, "INFO" },
	["debug"] = { 3, "DBG " },
	["trace"] = { 4, "TRCE" },
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

syslog._emuLog = nil

for k, v in component.list() do
	if v == "ocelot" then --Emulated syslog/""serial"".
		---@param msg string
		syslog._emuLog = function(msg)
			component.invoke(k, "log", msg)
		end
		component.invoke(k, "clearLog") -- Clean slate.
	end
end

local maxLogLevel = 2

function syslog.setMaxLogLevel(level)
	if level > 4 or level < 0 then
		error("Log level must be between 0 and 4, inclusive. Got " .. tostring(level))
	end

	maxLogLevel = level

	syslog:info("Set global log level to %s", logLevels[level])
end

syslog.unsaved = {}

local workers = nil

syslog.writer = nil

function syslog:log(level, message, ...)
	local levelData = logLevels[level]
	if maxLogLevel < levelData[1] then
		if syslog._emuLog ~= nil and (maxLogLevel >= (levelData[1] - 1)) then
			local msg
			if workers then
				msg = "[" ..
					levelData[2] .. "]" .. "[" .. workers.current().name .. "] " .. string.format(message, ...) .. "\n"
			else
				msg = "[" .. levelData[2] .. "] " .. string.format(message, ...) .. "\n"
			end

			syslog._emuLog(msg)
		end

		return -- Be silent.
	end

	if syslog.writer and workers then
		local msg = "[" ..
			levelData[2] .. "]" .. "[" .. workers.current().name .. "] " .. string.format(message, ...) .. "\n"

		if syslog._emuLog then
			syslog._emuLog(msg)
		end

		syslog.writer(msg)

		table.insert(syslog.unsaved, msg)
		return
	end

	local msg = "[" .. levelData[2] .. "] " .. string.format(message, ...) .. "\n"

	if syslog._emuLog then
		syslog._emuLog(msg)
	end

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
end

return syslog
