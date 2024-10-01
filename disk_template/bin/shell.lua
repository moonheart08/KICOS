local io = require("io")
local workers = require("workers")

local prompt = "> "

function help()
	print("KICOS Shell.")
	print("exit | Exit the shell.")
	print("help | This help text.")
end

local builtins = {
	["exit"] = function() workers.current():exit() end,
	["help"] = help
}

while true do
	io.write(prompt)
	local line = io.read("l")
	
	local firstSpace = line:find(" ", 1, true)
	local cmd = nil
	local args = ""
	if firstSpace then
		args = line:sub(firstSpace + 1, -1)
		cmd = line:sub(1, firstSpace - 1)
	else
		cmd = line
	end
	
	local res, err = pcall(function()
		if builtins[cmd] then
			builtins[cmd]()
		else
			workers.runProgram(cmd, args).onDeath:await()
		end
	end)
	
	if not res then
		print("Command failed: %s", err)
	end
end