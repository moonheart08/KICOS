local io = require("io")
local workers = require("workers")
local fs = require("filesystem")
local env = require("env").env()

function help()
	print("KICOS Shell.")
	print("exit | Exit the shell.")
	print("help | This help text.")
	print("cd   | Change the working directory.")
end

local builtins = {
	["exit"] = function() workers.current():exit() end,
	["help"] = help,
	["cd"] = function(args)
		if fs.path.isRelative(args) then
			if env.workingDirectory:sub(-1) == "/" then
				args = env.workingDirectory .. args
			else
				args = env.workingDirectory .. "/" .. args
			end
		end
		if not fs.exists(args) or not fs.isDirectory(args) then
			print("Cannot change working directory (does not exist or is not a directory.")
		else
			env.workingDirectory = args
		end
	end,
}

while true do
	io.write(env.prompt or "> ")
	local line = io.read("l")
	
	if not line then
		return -- Pipe's closed.
	end
	
	local firstSpace = line:find(" ", 1, true)
	local cmd = nil
	local args = ""
	if firstSpace then
		args = line:sub(firstSpace + 1, -1)
		cmd = line:sub(1, firstSpace - 1)
	else
		cmd = line
	end
	
	if cmd ~= "" then
		local res, err = pcall(function()
			if builtins[cmd] then
				builtins[cmd](args)
			else
				workers.runProgram(cmd, args).onDeath:await()
				io.clearInput() -- Ensure we don't read anything that managed to get in our stdin when the new program was running.
			end
		end)
		
		if not res then
			print("Command failed: %s", err)
		end
	end
end