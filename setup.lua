local internet = require("internet")
local fs = require("filesystem")
local branch = "master"
local remoteFilesUrl = "https://raw.githubusercontent.com/moonheart08/gtnh-oc/"..branch.."/"
local runningStandalone = false

if string.find(_OSVERSION, "KICOS") ~= nil then
	runningStandalone = true
end

local logLevels = {
	["error"] = {0, "ERR "},
	["warning"] = {1, "WARN"},
	["info"] = {2, "INFO"},
	["debug"] = {3, "DBG "},
	["trace"] = {4, "TRCE"},
}

local maxLogLevel = 4

local function setMaxLogLevel(level) 
	if level > 4 or level < 0 then
		error("Log level must be between 0 and 4, inclusive. Got " .. tostring(level))
	end
	
	maxLogLevel = level
end

local function log(level, message, ...)
	local levelData = logLevels[level]
	if maxLogLevel < levelData[1] then
		return -- Be silent.
	end
	
	print("[" .. levelData[2] .. "] " .. string.format(message, arg)) 
end

local function logError(message, ...)
	log("error", message, arg)
end

local function logWarning(message, ...)
	log("warning", message, arg)
end

local function logInfo(message, ...)
	log("info", message, arg)
end

local function logDebug(message, ...)
	log("debug", message, arg)
end

local function logTrace(message, ...)
	log("trace", message, arg)
end


local function grabFile(url)
	local handle = internet.request(url)
	local result = ""
	-- Accumulate chunks of data from the sender.
	for chunk in handle do 
		result = result..chunk 
	end
	
	local mt = getmetatable(handle)
	
	local code, message, headers = mt.__index.response()
	
	if tostring(code) ~= "200" then
		error("Expected a 200 response when fetching " .. url .. " but got " .. code .. "instead.")
	end
	
	return result
end


-- Maps files on the disk to files on the repo. They will be fetched and emplaced one at a time.
-- These are files for the local host, not the target system!
local repoMap = {
	{"/bin/setup.lua", "setup.lua"},
	{"/bin/opl_flash.lua", "opl_flash.lua"}
	{"/bin/kicos_disk_builder.lua", "kicos_disk_builder.lua"}
}

-- OC computers don't have particularly much disk space, much less RAM, so I opt to not try to cache the changes in memory before applying.
for k,entry in pairs(repoMap) do
	local url = remoteFilesUrl .. entry[2]
	logInfo("Retrieving %s from %s.", entry[2], url)
	local data = grabFile(url .. "?" .. tostring(math.random()))
	local handle = fs.open(entry[1], "wb")
	handle:write(data)
	logInfo("File saved to OS disk.")
	handle:close()
end

-- Flash OPL.
loadfile("/bin/opl_flash.lua")({["quiet"]=true})
loadfile("/bin/kicos_disk_builder.lua")({
	["fs"] = fs,
	["grabFile"] = grabFile,
	["component"] = _G.component,
	["log"] = log,
	["logError"] = logError,
	["logWarning"] = logWarning,
	["logInfo"] = logInfo,
	["logDebug"] = logDebug,
	["logTrace"] = logTrace,
}
