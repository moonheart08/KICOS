local pipes <const> = require("pipes")
local fs <const> = require("filesystem")
local env <const> = require("env")

local io <const> = {}

function io.write(s)
	local stdout = pipes.stdout()

	stdout:write(s)
end

function io.print(...)
	local stdout = pipes.stdout()

	stdout:write(string.format(...) .. "\n")
end

function io.closed()
	return pipes.stdin().closed
end

function io.read(k, doFocus, echo)
	k = k or "l"

	if echo == nil then
		if env.env().echo == nil then
			echo = true
		else
			echo = env.env().echo
		end
	end

	local stdin = pipes.stdin()
	local stdout = pipes.stdout()

	if stdin.closed then
		error("Cannot read from a closed pipe!")
	end

	if k == "l" or k == "L" then -- Read a line, without or with a \n.
		local b = ""
		---@type string|nil
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
		until inp == "\n" or stdin.closed

		if stdin.closed and b == "" then
			return nil
		end

		if k == "L" and not stdin.closed then
			b = b .. "\n" -- We got a newline, supposedly.
		end

		return b
	elseif k == "a" then -- Read until EOF, i.e. closed.
		local b = ""

		while true do
			b = b .. stdin:read(1024)

			if stdin.closed then
				break
			end
		end

		if stdin.closed and b == "" then
			return nil
		end

		return b
	elseif type(k) == "number" then -- Read `k` bytes.
		local b = ""
		while k > 0 do
			b = b .. stdin:read(1)
			k = k - 1

			if stdin.closed then
				break
			end
		end

		if stdin.closed and b == "" then
			return nil
		end

		return b
	else
		error("Mode %s not yet supported.", k)
	end
end

function io.clearInput()
	local stdin = pipes.stdin()
	stdin:clearBuffer()
end

function io.open(file, mode)
	return fs.open(file, mode)
end

return io
