local ev <const> = require("eventbus")
local syslog <const> = require("syslog")
local keyboard <const> = require("keyboard")
local computer <const> = require("computer")
local workers <const> = require("workers")
local pipes <const> = require("pipes")
local fs <const> = require("filesystem")
local util <const> = require("util")
local graphics <const> = require("graphics")
local args <const> = ...

args:call() -- Tell driver manager to move along.

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

ev.listen("key_down", function(ty, addr, char, code, source)
	lastKeyboard = addr
	if code == sysrqKey then
		lastPressedKey = nil
		sysrqIoBlock = true
		ev.push("sysrq")
		return true
	else
		setHeldKey(addr, code, true)
		lastPressedKey = code
		syslog:trace("Key pressed: %s (%s)", string.char(char), code)
		local stdin = nil

		do
			local currDisplay = graphics.currentVDisplay()

			if currDisplay then
				stdin = currDisplay:getPipeOutput()
			end
		end

		if stdin and not sysrqIoBlock then
			if getControlHeld(addr) then
				if code == 0x2E then -- CTRL-C
					if stdin.lastReader and not stdin.lastReader.dead then
						stdin.lastReader:exit("killed")
					end
				elseif code == 0x20 then
					stdin:close()
				end
			end

			if specialKeyMap[code] then
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

ev.listen("key_up", function(ty, addr, char, code, source)
	setHeldKey(addr, code, false)
	syslog:trace("Key released: %s (%s)", string.char(char), code)
	return true
end)

local lastScratch = nil

local sysrqRegistry = {
	--["1"] = function() syslog.setMaxLogLevel(0) end,
	--["2"] = function() syslog.setMaxLogLevel(1) end,
	--["3"] = function() syslog.setMaxLogLevel(2) end,
	--["4"] = function() syslog.setMaxLogLevel(3) end,
	--["5"] = function() syslog.setMaxLogLevel(4) end,
	["w"] = function() workers.top(function(...) syslog:info(...) end) end,
	["m"] = function()
		local max = 0
		for _ = 1, 40 do
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
	end,
	["1"] = function() require("graphics").switchToVDisplay(1) end,
	["2"] = function() require("graphics").switchToVDisplay(2) end,
	["3"] = function() require("graphics").switchToVDisplay(3) end,
	["4"] = function() require("graphics").switchToVDisplay(4) end,
	["5"] = function() require("graphics").switchToVDisplay(5) end,
	["6"] = function() require("graphics").switchToVDisplay(6) end,
	["7"] = function() require("graphics").switchToVDisplay(7) end,
	["8"] = function() require("graphics").switchToVDisplay(8) end,
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
