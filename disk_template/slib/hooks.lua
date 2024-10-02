local hooks = {}

local Hook = {}
hooks.Hook = Hook

function Hook:new()
	local o = {
		listeners = {}
	}
	setmetatable(o, self)
	self.__index = self
	
	return o
end

function Hook:call(...)
	local deadHooks = {}
	local res = nil
	self.working = true
	for k, v in pairs(self.listeners) do
		if (v.worker ~= nil) and v.worker.dead then
			table.insert(deadHooks, k)
		else
			-- While error handling would be *nice* here, Hooks are used in some locations that would need to yield across the hook due to OC or system yields.
			-- As such, we're just not allowed to have pcall. Shame.
			res = v.func(res, ...)
		end
	end
	
	self.working = false
	
	for _,v in ipairs(deadHooks) do
		self.listeners[v] = nil
	end
	if type(res) == "table" then
		return table.unpack(res)
	else
		return res
	end
end

local hookEntryId = 1

function Hook:attach(func, workerless)
	assert(not self.working, "Do NOT attach a hook mid-call. Please.")
	assert(type(func) == "function" or getmetatable(func).__call ~= nil, "Cannot attach non-callable value to a hook.")
	
	local currWorker = _kicosCtx.workers.current()
	local entryId = tostring(hookEntryId)
	hookEntryId = hookEntryId + 1
	if workerless then
		self.listeners[entryId] = { func = func }
	else
		self.listeners[entryId] = { worker = currWorker, func = func }
	end
	
	return entryId
end

function Hook:deattach(entry)
	self.listeners[entry] = nil
end

-- Similarly to event.pull, this will wait/sleep the process until completion.
-- The optional condition function gets the hook arguments and must return either true (quit waiting) or false (continue)
function Hook:await(condition)
	local yielding = true
	local data = nil
	
	condition = condition or function() return true end -- No-op.
	
	local entry = self:attach(function(res, ...)
		if condition(...) then
			yielding = false
			data = table.pack(...)
		end
		
		return res
	end)
	
	while yielding do coroutine.yieldToOS() end
	
	self:deattach(entry)
	return table.unpack(data)
end

return hooks