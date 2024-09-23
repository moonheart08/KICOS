-- A "worker" is a collection of coroutines that can be tracked by the OS.
-- This file implements workers, and overrides the built-in coroutines library to facilitate this.

local builtin_coroutine = coroutine
local syslog = _kicosCtx.syslog

local workers = {}

local Worker = { coroutines = {} }
workers.Worker = Worker
workers._worker_list = {}

local workerId = 1

function Worker:_new(body, name)
	local o = Worker:_new_empty(name)
	coroutine.create(body, o)
	return o
end

function Worker:_new_empty(name)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	-- Configure table to have weak values so we don't hang up coroutines forever when they should die.
	setmetatable(o.coroutines, {__mode = "v"})
	
	o.id = workerId
	workerId = workerId + 1
	table.insert(workers._worker_list, self)
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
			status = status .. "  " .. workers.prettyPrintCoroutine(routine)
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

local coroutine = {
	create = function(f, _worker)
		local curr = builtin_coroutine.running()
		local currData = workers._get_coroutine_data(curr)
		if currData == nil then
			return builtin_coroutine.create(f)
		end
		
		local worker = _worker or currData._worker
		
		local new = builtin_coroutine.create(f)
		worker:_assign_coroutine(new)
		syslog:trace("Created new coroutine on worker %s")
		return new
	end,
	
	resume = builtin_coroutine.resume,
	yield = builtin_coroutine.yield,
	running = builtin_coroutine.running,
	status = builtin_coroutine.status,
	wrap = function(f, _worker)
		local curr = builtin_coroutine.running()
		local currData = workers._get_coroutine_data(curr)
		if currData == nil then
			return builtin_coroutine.wrap(f)
		end
		
		local worker = _worker or currData._worker
		
		local new = builtin_coroutine.wrap(f)
		worker:_assign_coroutine(new)
		syslog:trace("Created new coroutine on worker %s")
		return new
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

_G.coroutine = coroutine

return workers