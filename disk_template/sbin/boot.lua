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
syslog:debug("Testing really long text: AWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWAWA")

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
	_kicosCtx.workers = raw_loadfile("/slib/workers.lua")()
	local os_worker = _kicosCtx.workers.Worker:_new_empty("KICOS")
	os_worker:_assign_coroutine(coroutine.running())
	coroutine.setName(coroutine.running(), "Scheduler")
	syslog:debug("State: %s", os_worker:status(true))
	
	syslog:info("Entering scheduler.")
	
	local uptime = computer.uptime
	local pull = computer.pullSignal
	local push = computer.pushSignal
	
	local function yieldToOC()
	    local signal = table.pack(pull(0))

		if signal.n > 0 then
		  push(table.unpack(signal, 1, signal.n))
		end
	end
	
	local function runProcess(file, ...)
		local worker = raw_loadfile(file)
		_kicosCtx.workers.Worker:new(worker, file, ...)
	end
	
	runProcess("/slib/startup.lua", raw_loadfile)
	
	while true do
		for k,v in ipairs(_kicosCtx.workers._worker_list) do
			if v._leader ~= nil then
				coroutine.resume(v._leader)
			end
			yieldToOC()
		end
	end
end, sys_errhandler)

