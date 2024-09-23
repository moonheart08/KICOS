local raw_loadfile = ...
local component = component

_G._OSVERSION = "KICOS v0.0.0"


-- All files in slib are safe to load early, and go straight into the exec context.

VTerm = raw_loadfile("/slib/vterm.lua")()
_G.VTerm = VTerm

local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()

_G._logVTerm = VTerm:new(screen, gpu)

_G._kicosCtx = {}
_kicosCtx.syslog = raw_loadfile("/slib/syslog.lua")()
_kicosCtx.bootDevice = computer.getBootAddress()

local syslog = _kicosCtx.syslog
syslog:info("Survived early boot, VTerms available.")
syslog:info("Booting from %s", _kicosCtx.bootDevice)
syslog:debug("Testing really long text: AWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWA")

local function sys_errhandler(x)
	syslog:error("System died!")
	syslog:error(x)
	for i in debug.traceback():gmatch("([^\n]+)") do
		syslog:error(i)
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
	_kicosCtx.workers = raw_loadfile("/slib/workers.lua")()
	local os_worker = _kicosCtx.workers.Worker:_new_empty("KICOS")
	os_worker:_assign_coroutine(coroutine.running())
	coroutine.setName(coroutine.running(), "Core")
	syslog:debug("State: %s", os_worker:status(true))
	
	syslog:info("Searching for early boot drivers.")
	
	for addr, ty in component.list() do
		local success = " "
		local path = "/slib/ebd_" .. ty .. ".lua"
		if component.invoke(_kicosCtx.bootDevice, "exists", path) then
			syslog:info("[x] %s %s", addr, ty)
			raw_loadfile(path)()
		else 
			syslog:info("[ ] %s %s", addr, ty)
		end
		
		
	end
end, sys_errhandler)

