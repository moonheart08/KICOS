local workers <const> = require("workers")
local component <const> = require("component")
local fs <const> = require("filesystem")
local syslog <const> = require("syslog")
local ev <const> = require("eventbus")
local util <const> = require("util")
local Hook <const> = require("hooks").Hook

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
	local e = ev.pull(-1, "dman_reload")

	if e then
		loadDrivers()
	end
end
