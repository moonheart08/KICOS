local util <const> = require("util")
local env <const> = require("env")
local io <const> = require("io")
local present <const> = {}

-- OpenOS compat shim.
local old_print = print
local function print(...)
	old_print(string.format(...))
end
function present.inputChar()
	io.write(":")
	local c = io.read(1) -- wait.
	io.write("\b")    -- backspace that out.

	return c
end

function present.more(table)
	local printed = 0
	for k, v in pairs(table) do
		local key = ""
		util.prettyPrint(k, function(...) key = key .. string.format(...) end)
		local value = ""
		util.prettyPrint(v, function(...) value = value .. string.format(...) end)
		print("%s = %s", key, value)
		printed = printed + 1
		if printed > (env.env().moreThreshhold or 15) then
			local c = present.inputChar()

			if c == "q" then
				print("quit")
				return -- ok done.
			end
		end
	end
end

function present.hex(str, width)
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

function present.yesNo()
	local yn = nil

	while yn ~= "y" and yn ~= "n" do
		yn = present.inputChar()
	end

	return yn == "y"
end

function present.select(tab)
	assert(#tab < 10)

	for i = 1, #tab do
		print("%1i: %s", i, tab[i])
	end

	while true do
		local c = present.inputChar()

		if c == "q" then
			return nil
		end

		local n = tonumber(c)
		if not (n == nil or n < 0 or n > #tab) then
			return tab[n]
		end
	end
end

return present
