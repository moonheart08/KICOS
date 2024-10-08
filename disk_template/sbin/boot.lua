local raw_loadfile <const> = ...
local component <const> = component

_G._OSVERSION = "KICOS v0.0.2"
local _loadLevel = 0
_G._OSLOADLEVEL = function(l)
	if l ~= nil then
		_loadLevel = l
	else
		return _loadLevel
	end
end

-- All files in slib are safe to load early, and go straight into the exec context.
_G._kicosCtx = {}

local VTerm = raw_loadfile("/slib/vterm.lua")()
_G._kicosCtx.VTerm = VTerm

local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()

_G._logVTerm = VTerm:new(screen, gpu)
_G._kicosCtx._logVTerm = _logVTerm -- aAAAA

_kicosCtx.syslog = raw_loadfile("/slib/syslog.lua")()
_kicosCtx.bootDevice = computer.getBootAddress()

local syslog <const> = _kicosCtx.syslog
syslog:info("Survived early boot, VTerms available.")
syslog:info("Booting from %s", _kicosCtx.bootDevice)

local function sys_errhandler(x)
	_OSLOADLEVEL(-1)
	syslog:error("Core thread died!")
	syslog:error(x)
	for i in debug.traceback():gmatch("([^\n]+)") do
		if i:match(".machine:.*") ~= nil then
		else
			syslog:error(i)
		end
	end
end

local real_crash = computer.crash
-- Deliberate override.
---@diagnostic disable-next-line: duplicate-set-field
function computer.crash(reason)
	sys_errhandler(reason)
	real_crash(reason)
end

xpcall(function()
	syslog:info("Entering protected context.")
	syslog:info("Booting %s with %s/%s B of RAM", _G._OSVERSION, computer.freeMemory(), computer.totalMemory())
	_kicosCtx.scheduler = raw_loadfile("/slib/scheduler.lua")()
	_kicosCtx.workers = raw_loadfile("/slib/workers.lua")()
	_kicosCtx.hooks = raw_loadfile("/slib/hooks.lua")()
	raw_loadfile("/slib/component.lua")() -- Injection based, don't worry about saving it.
	raw_loadfile("/slib/string.lua")() -- Also injection based.
	raw_loadfile("/slib/table.lua")()  -- You get the idea.
	raw_loadfile("/slib/computer.lua")()
	raw_loadfile("/slib/global.lua")()

	local os_worker = _kicosCtx.workers.Worker:_new_empty("KICOS")
	os_worker:_assign_coroutine(coroutine.running())

	syslog:info("Entering scheduler.")

	local function runProcess(file, ...)
		local worker = raw_loadfile(file)
		_kicosCtx.workers.Worker:new(worker, file:match("/([^/]+)$"), ...)
	end

	runProcess("/slib/startup.lua", raw_loadfile)

	_kicosCtx.scheduler.run()
end, sys_errhandler)
