local workers = require("workers")
local component = require("component")
local fs = require("filesystem")
local syslog = require("syslog")
local ev = require("eventbus")
local util = require("util")
local Hook = require("hooks").Hook

local drivers = {}

local function loadDrivers()
	syslog:info("Locating and starting drivers.")
	for _, v in pairs(drivers) do
		v:exit(util.exitReasons.killed)
	end

	for _, v in pairs(drivers) do
		assert(v.dead)
	end

	drivers = {}
	assert(#drivers == 0)


	local uniqueTy = {}
	for addr, ty in component.list() do
		uniqueTy[ty] = true
	end

	for k, _ in pairs(uniqueTy) do
		local path = "/sbin/drivers/" .. k .. ".lua"
		if fs.exists(path) then
			local barrier = Hook:new()
			local worker = workers.runProgram(path, barrier)
			table.insert(drivers, worker)
			barrier:await()
		end
	end
end

loadDrivers()
_OSLOADLEVEL(3) -- Yes, we're responsible for indicating the OS is ready for a user.

while true do
	local e = ev.pull(0, "dman_reload")

	if e then
		loadDrivers()
	end
end
