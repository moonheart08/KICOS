local component = require("component")
local ev = require("eventbus")
local syslog = require("syslog")
local keyboard = require("keyboard")
local computer = require("computer")
local workers = require("workers")
local pipes = require("pipes")
local fs = require("filesystem")
local util = require("util")

-- Magic key that invokes SYSRQ.
local sysrqKey = keyboard.keys.pause
local stdin = nil

do
	local data = {}
	
	function getKeyboardData(addr)
		if data[addr] == nil then
			data[addr] = {
				held_keys = {}
			}
		end
		
		return data[addr]
	end
	
	function setHeldKey(addr, code, state)
		local data = getKeyboardData(addr)
		
		data.held_keys[code] = state
	end
	
	function getKeyState(addr, code)
		local data = getKeyboardData(addr)
		
		return data.held_keys[code] or false
	end
	
	function getControlHeld(addr)
		local data = getKeyboardData(addr)
		
		return data.held_keys[0x1D] or data.held_keys[0x9D]
	end
end

local lastPressedKey = nil
local lastKeyboard = nil

local specialKeyMap = {
	[28] = "\n"
}

local sysrqIoBlock = false

local keyDownListener = ev.listen("key_down", function(ty, addr, char, code, source)
	lastKeyboard = addr
	if code == sysrqKey then
		lastPressedKey = nil
		ev.push("sysrq")
		sysrqIoBlock = true
		return true
	else
		setHeldKey(addr, code, true)
		lastPressedKey = code
		syslog:trace("Key pressed: %s (%s)", string.char(char), code)
		if stdin and not sysrqIoBlock then
			if getControlHeld(addr) then
				if code == 0x2E then -- CTRL-C
					stdin.worker:exit("killed")
				elseif code == 0x20 then
					stdin:close()
				end
			elseif specialKeyMap[code] then
				local res, err = pcall(function()
					stdin:tryWrite(specialKeyMap[code])
				end)
				
				if not res then
					syslog:warning("Stdin write failed: %s", err)
				end
			elseif char ~= 0 then
				-- on god if you block the keyboard thread, explode.
				local res, err = pcall(function()
					stdin:tryWrite(string.char(char))
				end)
				
				if not res then
					syslog:warning("Stdin write failed: %s", err)
				end
			end
		end
	end
	
	return true
end)

local keyUpListener = ev.listen("key_up", function(ty, addr, char, code, source)
	setHeldKey(addr, code, false)
	syslog:trace("Key released: %s (%s)", string.char(char), code)
	return true
end)

local stdinFocusListneer = ev.listen("focus_stdin", function(ty, toFocus)
	stdin = pipes._getStdinById(toFocus)
	syslog:trace("Focusing new stdin %s", toFocus)
	return true
end)

local lastScratch = nil
_OSLOADLEVEL(3)

local sysrqRegistry = {
	["1"] = function() syslog.setMaxLogLevel(0) end,
	["2"] = function() syslog.setMaxLogLevel(1) end,
	["3"] = function() syslog.setMaxLogLevel(2) end,
	["4"] = function() syslog.setMaxLogLevel(3) end,
	["5"] = function() syslog.setMaxLogLevel(4) end,
	["w"] = function() workers.top(function(...) syslog:info(...) end) end,
	["m"] = function()
		local max = 0
		for _=1,40 do
		  max = math.max(max, computer.freeMemory())
		  coroutine.yieldToOS() -- let GC happen.
		end
		
		syslog:info("Memory stats: %s / %s", max, computer.totalMemory())
	end,
	["c"] = function()
		for addr, ty in require("component").list() do
			syslog:info("C %s %s", addr, ty)
		end
	end,
	["s"] = function()
		if lastScratch then
			lastScratch:exit(util.exitReasons.killed)
		end
		
		-- run the scratch program.
		local res, err = pcall(function()
			fs.invalidateCache("/scratch.lua")
			lastScratch = workers.runProgram("/scratch.lua")
		end)
		
		if not res then
			syslog:error("Scratch program failed to load: %s", err)
		end
	end,
	["r"] = function()
		syslog:info("Reloading drivers.")
		ev.push("dman_reload")
	end,
	["q"] = function()
		computer.shutdown(true)
	end,
	["t"] = function()
		workers.runProgram("/bin/dotests.lua")
	end
}

while true do 
	ev.pull(-1, "sysrq")
	syslog:warning("Keyboard waiting on SYSRQ input.")
	
	while lastPressedKey == nil do
		coroutine.yieldToOS()
	end
	
	sysrqIoBlock = false
	
	local key = keyboard.keys[lastPressedKey]
	
	if sysrqRegistry[key] ~= nil then
		sysrqRegistry[key](key)
	else
		syslog:warning("Unknown SYSRQ {%s}", key)
	end
 end