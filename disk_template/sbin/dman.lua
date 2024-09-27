local workers = require("workers")
local component = require("component")
local fs = require("filesystem")
local syslog = require("syslog")
syslog:info("Locating and starting drivers.")
local uniqueTy = {}
for addr, ty in component.list() do
	uniqueTy[ty] = true
end

for k, _ in pairs(uniqueTy) do
	local path = "/sbin/drivers/" .. k .. ".lua"
	if fs.exists(path) then
		workers.runProgram(path)
	end
end

while true do coroutine.yieldToOS() end