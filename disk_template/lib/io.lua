local workers = require("workers")
local pipes = require("pipes")
local syslog = require("syslog")

local io = {}

function io.write(...)
	local stdout = pipes.stdout()
	
	stdout:write(string.format(...))
end

function io.read(k)
	k = k or "l"
	
	local stdin = pipes.stdin()
	pipes.focusStdin()
	
	if k == "l" then
		local b = ""
		local inp = ""
		repeat 
			b = b .. inp
			inp = stdin:read(1)
			syslog:trace("Read %s", inp)
		until inp == "\n"
		
		return b
	else
		error("Mode %s not yet supported.", k)
	end
end

return io