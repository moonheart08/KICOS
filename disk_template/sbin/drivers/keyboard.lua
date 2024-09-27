local component = require("component")
local ev = require("eventbus")
local syslog = require("syslog")
local keyboard = require("keyboard")
local computer = require("computer")

-- Magic key that invokes SYSRQ.
local sysrqKey = keyboard.keys.pause

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
end

local sysrqRequested = false
local lastPressedKey = nil

local keyDownListener = ev.listen("key_down", function(ty, addr, char, code, source)
	if code == sysrqKey then
		sysrqRequested = true
		lastPressedKey = nil
		return true
	else
		setHeldKey(addr, code, true)
		lastPressedKey = code
		syslog:trace("Key pressed: %s (%s)", string.char(char), code)
	end
	
	return true
end)

local keyUpListener = ev.listen("key_up", function(ty, addr, char, code, source)
	setHeldKey(addr, code, false)
	syslog:trace("Key released: %s (%s)", string.char(char), code)
	return true
end)


while true do 
	if sysrqRequested then
		syslog:warning("Keyboard waiting on SYSRQ input.")
		while lastPressedKey == nil do
			coroutine.yieldToOS()
		end
		
		if lastPressedKey == keyboard.keys.w then
			require("workers").top(function(...) syslog:info(...) end)
		elseif lastPressedKey == keyboard.keys.m then
			local max = 0
			for _=1,40 do
			  max = math.max(max, computer.freeMemory())
			  coroutine.yieldToOS() -- let GC happen.
			end
			
			syslog:info("Memory stats: %s / %s", max, computer.totalMemory())
		elseif lastPressedKey == keyboard.keys["1"] then
			syslog.setMaxLogLevel(0)
		elseif lastPressedKey == keyboard.keys["2"] then
			syslog.setMaxLogLevel(1)
		elseif lastPressedKey == keyboard.keys["3"] then
			syslog.setMaxLogLevel(2)
		elseif lastPressedKey == keyboard.keys["4"] then
			syslog.setMaxLogLevel(3)
		elseif lastPressedKey == keyboard.keys["5"] then
			syslog.setMaxLogLevel(4)
		end
		
		sysrqRequested = false
	end
	coroutine.yieldToOS()
 end