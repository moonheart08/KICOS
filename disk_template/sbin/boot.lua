local raw_loadfile = ...
local component = component

_G._OSVERSION = "KICOS v0.0.0"


-- All files in slib are safe to load early, and go straight into the exec context.
_G._kicosCtx = {}

local VTerm = raw_loadfile("/slib/vterm.lua")()
_G._kicosCtx.VTerm = VTerm

local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()

_G._logVTerm = VTerm:new(screen, gpu)


_kicosCtx.syslog = raw_loadfile("/slib/syslog.lua")()
_kicosCtx.bootDevice = computer.getBootAddress()

local syslog = _kicosCtx.syslog
syslog:info("Survived early boot, VTerms available.")
syslog:info("Booting from %s", _kicosCtx.bootDevice)

local function sys_errhandler(x)
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
function computer.crash(reason)
	sys_errhandler(x)
	real_crash(reason)
end

_, err = xpcall(function() 
	syslog:info("Entering protected context.")
	syslog:info("Booting %s with %s/%s B of RAM", _G._OSVERSION, computer.freeMemory(), computer.totalMemory())
	_kicosCtx.scheduler = raw_loadfile("/slib/scheduler.lua")()
	_kicosCtx.workers = raw_loadfile("/slib/workers.lua")()
	
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

