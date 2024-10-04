local component = require("component")
local fs = require("filesystem")
local ev = require("eventbus")
local syslog = require("syslog")

local msgs = {}

local function queueFSMount(addr, ty)
	table.insert(msgs, {"added", addr, ty})
end

local function queueFSUnmount(addr, ty)
	table.insert(msgs, {"removed", addr, ty})
end

for addr, ty in component.list("filesystem") do
	queueFSMount(addr, ty) -- ensure we mount the existing FSes to /mnt.
end

ev.listen("component_added", function(msg, addr, ty)
	if ty ~= "filesystem" then
		return true
	end
	queueFSMount(addr, ty)
	return true
end)

ev.listen("component_removed", function(msg, addr, ty)
	if ty ~= "filesystem" then
		return true
	end
	queueFSUnmount(addr, ty)
	return true
end)

fs.ensureDirectory("/mnt")

local args = ...

args:call() -- Tell driver manager to move along.

while true do
	if #msgs > 0 then
		while #msgs > 0 do
			local msg = table.remove(msgs, 1)
			
			if msg[1] == "added" then
				fs.mount(msg[2], "/mnt/" .. msg[2])
			elseif msg[1] == "removed" then
				fs.unmount("/mnt/" .. msg[2])
			end
		end
	end
	coroutine.yieldToOS()
end
