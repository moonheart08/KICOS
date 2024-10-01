component = require("component")
env = require("env")
json = require("json")
filesystem = require("filesystem")
util = require("util")
pipes = require("pipes")

function more(table)
	local printed = 0
	for k, v in pairs(table) do
		local key = ""
		util.prettyPrint(k, function(...) key = key .. string.format(...) end)
		local value = ""
		util.prettyPrint(v, function(...) value = value .. string.format(...) end)
		print("%s = %s", key, value)
		printed = printed + 1
		if printed > (env.env().moreThreshhold or 15) then
			io.write(":")
			local c = pipes.stdin():read(1) -- wait.
			io.write("\b") -- backspace that out.
			if c == "q" then
				print("quit")
				return -- ok done.
			end
		end
	end
end

function hex(str, width)
	width = width or 16
	for i = 1, str:len() do
		local c = str:byte(i)
		
		io.write(string.format("%02x ", c))
		
		if i % width == 0 then
			io.write("\n")
		end
	end
	
	io.write("\n")
end

