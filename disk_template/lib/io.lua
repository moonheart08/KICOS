local workers = require("workers")
local pipes = require("pipes")
local syslog = require("syslog")

local io = {}

function io.write(...)
	local stdout = pipes.stdout()
	
	stdout:write(string.format(...))
end

function io.print(...)
	local stdout = pipes.stdout()
	
	stdout:write(string.format(...) .. "\n")
end

function io.read(k, doFocus, echo)
	k = k or "l"
	
	if echo == nil then
		echo = true
	end
	
	local stdin = pipes.stdin()
	local stdout = pipes.stdout()
	if (doFocus == nil) or (doFocus == true) then
		pipes.focusStdin()
	end
	
	if k == "l" then
		local b = ""
		local inp = ""
		repeat 
			b = b .. inp
			inp = stdin:read(1)

			if inp == "\b" then
				-- Backspace.
				inp = ""
				if string.len(b) > 0 then
					b = string.sub(b, 1, string.len(b) - 1) -- Cut last char.
					if echo then
						stdout:write("\b")
					end
				end
			else
				if echo then
					stdout:write(inp)
				end
			end
		until inp == "\n"
		
		return b
	else
		error("Mode %s not yet supported.", k)
	end
end

function io.clearInput()
	local stdin = pipes.stdin()
	stdin:clearBuffer()
end

return io