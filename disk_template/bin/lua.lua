local io = require("io")
local workers = require("workers")
local env = require("env").env()
local serialization = require("serialization")

function makeEnv()
	local e =  workers.buildGlobalContext() -- Start with a standard worker's context.
	local preloads = env.luaEvalPreload or {}
	for _, v in pairs(preloads) do
		loadfileExt(v, e)
	end
end

local luaEnv = makeEnv()

local accum = ""

print("KICOS Lua REPL")
print("Lua version: %s", _VERSION)
print("Type `exit` to exit.")
print("Type `refresh` to reset the environment.")
print("Type `clr` to clear accumulated code in a multi-line input.")

function errHandler(x)
	print("ERR: %s", x)
	local innerFrames = 3
	for i in debug.traceback():gmatch("([^\n]+)") do
		if i:match(".machine:.*") ~= nil or i:match(".slib/workers.lua:.*") ~= nil then
		else
			-- Remove the workers.lua and xpcall frames.
			if innerFrames > 0 then
				innerFrames = innerFrames - 1
			else
				print(i)
			end
		end

	end
end
		

while true do
	if accum == "" then
		io.write(luaEnv._PROMPT or "lua> ")
	else
		io.write(luaEnv._NEXTLINEPROMPT or "...> ")
	end
	
	local line = io.read("l")
	
	if line == "exit" then
		return
	elseif line == "refresh" then
		luaEnv = makeEnv()
	elseif line == "clr" then
		accum = ""
	else
		local code, err = nil

		if line:sub(1, 1) == "=" and accum == "" then 
			local s = "return " .. line:sub(2, -1)
			code, err = load(s, "=stdin", "t", luaEnv)
		else 
		
			if accum == "" then
				local s = "return " .. line
				code, err = load(s, "=stdin", "t", luaEnv)
			end
			
			if not code then
				accum = accum .. line .. "\n"
				code, err = load(accum, "=stdin", "t", luaEnv)
			end
		end
		
		if code then 
			accum = ""
			local res = table.pack(xpcall(code, errHandler))
			
			if res[1] then
				local res, err = pcall(function()
					local didSomething = false
					for i = 2, #res do
						didSomething = true
						if res[i] == nil then
							print("nil")
						else
							print(serialization.serialize(res[i], true))
						end
					end
					
					if not didSomething then
						print("nil")
					end
				end)
				
				if not res then
					print("Failed to pretty-print results: %s", err)
				end
			end
		elseif err:match("<eof>") == nil then
			accum = ""
			print("ERR %s", err)
		end
	end
end