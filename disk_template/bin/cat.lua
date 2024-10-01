local args = ...

local fs = require("filesystem")
local io = require("io")
local pipes = require("pipes")

local h = pipes.stdin()

if args ~= "" then
	h = fs.open(args, "r")
end

while true do
	local b = h:read(128)
	if b ~= "" then
		io.write(b)
	else
		break
	end
end