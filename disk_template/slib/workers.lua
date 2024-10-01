-- A "worker" is a collection of coroutines that can be tracked by the OS.
-- This file implements workers, and overrides the built-in coroutines library to facilitate this.

local builtin_coroutine = coroutine
local syslog = _kicosCtx.syslog
local scheduler = _kicosCtx.scheduler

local workers = {}

local Worker = {}
workers.Worker = Worker
workers._worker_list = {}

local workerId = 1

function Worker:new(body, name, ...)
	local o = Worker:_new_empty(name)
	local workerArgs = table.pack(...)
	o._leader = coroutine.create(function() 
		local function workerDeathHandler(x)
			syslog:warning("Worker %s's leader exited with an error!", o)
			syslog:warning(x)
			local innerFrames = 3
			for i in debug.traceback():gmatch("([^\n]+)") do
				if i:match(".machine:.*") ~= nil then
				else
					-- Remove the workers.lua and xpcall frames.
					if innerFrames > 0 then
						innerFrames = innerFrames - 1
					else
						syslog:warning(i)
					end
				end

			end
		end
		
		local res, err = xpcall(function()
			return body(table.unpack(workerArgs))
		end, workerDeathHandler)
		
		if res == true then
			o:exit("ended")
		else
			o:exit("crashed")
		end
	end, o)
	coroutine.setName(o._leader, "Leader")
	-- Hashset. Yea this stinks.
	scheduler._scheduled_workers[o] = o
	return o
end

local io = nil

function workers.runProgram(file, ...)
	io = require("io")
	local contents, err = loadfileExt(file, workers.buildGlobalContext())
	assert(not err, err)
	coroutine.yieldToOS()
	return Worker:new(contents, file:match("/([^/]+)$") or file, ...)
end

function workers.buildGlobalContext()
	local newContext = {
		package = package,
		loadfile = loadfile, 
		loadfileExt = loadfileExt,
		load = load,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		table = table,
		coroutine = coroutine,
		math = math,
		string = string,
		pairs = pairs,
		ipairs = ipairs,
		pcall = pcall,
		xpcall = xpcall,
		rawequal = rawequal,
		rawget = rawget,
		rawset = rawset,
		rawlen = rawlen,
		select = select,
		tonumber = tonumber,
		tostring = tostring,
		type = type,
		_OSVERSION = _OSVERSION,
		next = next,
		error = error,
		assert = assert,
		require = require,
		unicode = unicode,
		os = os,
		bit32 = bit32,
		utf8 = utf8,
		debug = debug,
		_OSLOADLEVEL = _OSLOADLEVEL,
		io = io,
		print = function(...) 
			io.write(string.format(...) .. "\n")
		end,
		
	}
	newContext._G = newContext
	return newContext
end

function workers.runThread(f, name, ...)
	return Worker:new(f, name, ...)
end

function Worker:_new_empty(name)
	local o = {
		dead = false,
		_ev_waiter = nil,
		onDeath = _kicosCtx.hooks.Hook:new(),
	}
	
	setmetatable(o, self)
	self.__index = self
	o.coroutines = {}
	-- Configure table to have weak values so we don't hang up coroutines forever when they should die.
	setmetatable(o.coroutines, {__mode = "v"})
	
	o.id = tostring(workerId)
	workerId = workerId + 1
	workers._worker_list[o.id] = o
	o:setname(name)
	syslog:info("Created %s", o)
	return o
end

local coroutineWorkerMap = {}
-- Configure table to have weak keys so we don't hang up coroutines forever when they should die.
setmetatable(coroutineWorkerMap, {__mode = "k"})

function Worker:_assign_coroutine(co)
	table.insert(self.coroutines, co)
	local data = { worker = self }
	coroutineWorkerMap[co] = data
end

-- todo: THIS IS BAD AND SHOULD BE PART OF COROUTINES, NOT WORKERS.
-- IT DOESN'T EVEN WORK PROPERLY WHY DID I WRITE IT THIS WAY.
function Worker:paused()
	if self._ev_waiter ~= nil then
		return self._ev_waiter()
	end
	
	return false
end

function Worker:exit(res)
	self.dead = true
	syslog:info("%s has exited (result %s)",self, res or 0)
	workers._worker_list[self.id] = nil -- Sparse, but that's fine.
	
	if workers.current() == self then
		self.onDeath:call(self, res) -- Call the death hook, so listeners are aware.
									 -- We do this BEFORE removing ourselves from scheduling
									 -- as to not only half-complete the hook if we yield.
		scheduler._scheduled_workers[self] = nil
		coroutine.yieldToOS()
	else
		scheduler._scheduled_workers[self] = nil
	end
end

function Worker:__tostring()
	return string.format("Worker %s (%s)", self.id, self.name or "unnamed")
end

function workers._get_coroutine_data(co)
	return coroutineWorkerMap[co]
end

function Worker:setname(n)
	self.name = n
end

function Worker:getname()
	return self.name
end

function Worker:status(long)
	if long then
		local status = "" .. tostring(self) .. "\n"
		status = status .. "Associated coroutines:\n"
		for k,routine in pairs(self.coroutines) do
			status = status .. "  " .. workers.prettyPrintCoroutine(routine) .. "\n"
		end
		return status
	else
		return self:__tostring()
	end
end

function workers.prettyPrintCoroutine(co)
	local data = workers._get_coroutine_data(co)
	if data == nil or data.name == nil then
		return tostring(co)
	end
	
	return string.format("%s (%s)", data.name, tostring(co))
end

function workers.current()
	local curr = coroutine.running()
	return workers._get_coroutine_data(curr).worker
end

function workers.top(writer)
	writer("All workers:")
	for _, worker in pairs(workers._worker_list) do
		writer(worker:status(true))
	end
end

local coroutine = {
	create = function(f, _worker)
		local curr = builtin_coroutine.running()
		local currData = workers._get_coroutine_data(curr)
		if currData == nil then
			return builtin_coroutine.create(f)
		end
		
		local worker = _worker or currData.worker
		
		local new = builtin_coroutine.create(f)
		worker:_assign_coroutine(new)
		syslog:trace("Created new coroutine on worker %s", worker)
		return new
	end,
	createNamed = function(f, name)
		local co = coroutine.create(f)
		coroutine.setName(co, name)
		return co
	end,
	
	resume = function(co, ...)
		local data = workers._get_coroutine_data(co)
		if data == nil then
			return builtin_coroutine.resume(co, ...)
		end
		
		if data.worker.dead or data.dead then
			return false, "Worker died, cannot process."
		end
		
		if data.worker:paused() and workers.current().id ~= 1 then
			return false, "Coroutine paused. Not dead, though!"
		end
		while true do
			local res = table.pack(builtin_coroutine.resume(co, ...))
			if res[1] and not res[2] then -- OS yield. Get me outta here.
				builtin_coroutine.yield()
			else
				table.remove(res, 2)
				return table.unpack(res)
			end
		end
	end,
	_nativeResume = builtin_coroutine.resume,
	yield = function(...)
		return builtin_coroutine.yield(true, ...)
	end,
	yieldToOS = function()
		-- Yielding the OS thread causes death.
		if workers.current().id ~= 1 then
			builtin_coroutine.yield(false)
		end
	end,
	running = builtin_coroutine.running,
	status = function(co)
		local data = workers._get_coroutine_data(co)
		if data == nil then
			return builtin_coroutine.status(co)
		end
		
		if data.worker.dead or data.dead then
			return "dead"
		end
		
		if data.worker:paused() then
			-- Condition is unique to KICOS, and will only be run into if you're using the eventbus or other OS features.
			-- Do not try to resume a paused coroutine, 
			return "paused"
		end
		
		return builtin_coroutine.status(co)
	end,
	wrap = function(f, _worker)
		local curr = builtin_coroutine.running()
		local currData = workers._get_coroutine_data(curr)
		if currData == nil then
			return builtin_coroutine.wrap(f)
		end
		
		local worker = _worker or currData.worker
		
		local new = builtin_coroutine.create(f)
		worker:_assign_coroutine(new)
		coroutine.setName(new, "Wrap (" .. tostring(f) .. ")")
		syslog:trace("Created new coroutine on worker %s", worker)
		return function(...)
			local res = table.pack(coroutine.resume(new, ...))
			if res[1] == false then
				error(res[2], 2)
			end
			table.remove(res, 1)
			return table.unpack(res)
		end
	end,
	
	name = function(co)
		local currData = workers._get_coroutine_data(co)
		if currData == nil then
			return nil
		end
		return currData.name
	end,
	
	setName = function(co, name)
		local currData = workers._get_coroutine_data(co)
		if currData == nil then
			return false
		end
		currData.name = name
		return true
	end,
}

function os.exit(code)
	workers.current():exit(code or 0)
end

_G.coroutine = coroutine

return workers