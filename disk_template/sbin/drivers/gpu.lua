-- The all powerful graphics driver, and the most painful thing if it crashes.
local osctx = require("kicos")
local component = require("component")
local graphics = require("graphics")
local workers = require("workers")
local syslog = require("syslog")

local primaryScreen = osctx._logVTerm._screen.address -- This is what we were running on before.
local primaryGPU = component.list("gpu")()

do
	local group = component.getNamedGroup("primaryDisplay")

	if group then
		primaryScreen = group["screen"]
		primaryGPU = group["gpu"]
	end
end

syslog:info("Primary display/GPU pair: %s to %s", primaryGPU, primaryScreen)

osctx._logVTerm._gpu = nil -- Send the VTerm to the abyss. DIE, vterm!!!
-- Man the VTerm API just wasn't thought out well. Oh well.
-- With the VTerm no longer able to mess up our work, we can now set up the card ourselves.

for k, _ in component.list("gpu", false) do
	graphics._managedCards[k] = graphics.GPU:new(k)
end

local primaryGPU = graphics.getGPU(primaryGPU)
primaryGPU:reset(primaryScreen, true)

graphics.primaryGPU = primaryGPU
graphics.primaryScreen = primaryScreen

local logDisplay = graphics.VDisplay:newWithVT(primaryGPU, primaryScreen)
logDisplay:switchTo()

local stdout = logDisplay:getPipeInput()
assert(stdout)

for _, v in pairs(syslog.unsaved) do
	stdout:write(v)
end

syslog.writer = function(msg)
	stdout:write(msg)
end

local args = ...

args:call() -- Tell driver manager to move along now that graphics are back.
