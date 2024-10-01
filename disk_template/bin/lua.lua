local io = require("io")
local workers = require("workers")
local env = require("env").env()
local serialization = require("serialization")
local util = require("util")

function makeEnv()
	local e =  workers.buildGlobalContext() -- Start with a standard worker's context.
	local preloads = env.luaEvalPreload or {}
	for _, v in pairs(preloads) do
		loadfileExt(v, e)()
	end
	
	return e
end

function help()
	print("exit     | Exit the REPL (ctrl-D also works.)")
	print("refresh  | Rebuilds the global context (_G) from scratch.")
	print("clr      | Clears accumulated code in a multi-line input.")
	print("scratch  | Loads the scratch file from /scratch.lua, to global `scratch`")
	print("<code>   | Runs as a lua program.")
	print("=<code>  | Runs as a lua expression, printing the result.")
	print("packages | Lists loaded packages.")
	print("help     | Prints this help message.")
end

local luaEnv = makeEnv()

local accum = ""

local errHandler = util.xpcallErrHandlerBuilder(print)

local args = ...
if args ~= "" then
	local code, err = load("return " .. args, "=cmdline", "t", luaEnv)
	if not code then
		print("ERR %s", err)
	else
		local res = table.pack(xpcall(code, errHandler))
		if res[1] then
			table.remove(res, 1)
			util.prettyPrint(res, print)
		end
	end
	
	return
end


print("KICOS Lua REPL")
print("Lua version: %s", _VERSION)
help()

while true do
	if accum == "" then
		io.write(luaEnv._PROMPT or "lua> ")
	else
		io.write(luaEnv._NEXTLINEPROMPT or "...> ")
	end
	
	local line = io.read("l")
	
	if not line then
		return -- Pipe's closed.
	end
	
	if line == "exit" then
		return
	elseif line == "refresh" then
		luaEnv = makeEnv()
	elseif line == "clr" then
		accum = ""
	elseif line == "help" then
		help()
	elseif line == "scratch" then
		local res, err = loadfileExt("/scratch.lua", luaEnv)
		if not res then
			print("Failed to load /scratch.lua!")
			print("%s", err)
		end
		luaEnv.scratch = scratch
	elseif line == "packages" then
		for k,_ in pairs(package.loaded) do
			if luaEnv[k] then
				io.write(k .. " ")
			end
		end
		print("") -- Annnd a newline.
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
				table.remove(res, 1)
				luaEnv.ans = res[1]
				
				local res, err = util.prettyPrint(res, print)
				
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
