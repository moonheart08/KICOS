local ev = require("eventbus")
local util = require("util")
local args = ...

if args == "" then
	print("USAGE: Provide event name(s) to listen for as commandline argument. Event data will be printed to terminal.")
	print("Can be exited with ctrl-C or ctrl-D.")
	return
end

function evhandler(name, ...)
	local args = table.pack(...)
	
	print("%s: ", name)
	util.prettyPrint(args, print)
	
	return true
end

for evname in args:gmatch("([^%s]+)") do
	print("Watching %s", evname)
	ev.listen(evname, evhandler)
end

while true do 
	if not pcall(io.read, 1) then
		return
	end
end