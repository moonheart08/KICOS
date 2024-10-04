local hooks = {}

---@class Hook
---@field listeners {func: fun(res: any, ...), worker: Worker}[]
local Hook = {}
hooks.Hook = Hook

---comment
---@return Hook
function Hook:new()
	---@type Hook
	local o = {
		listeners = {}
	}
	setmetatable(o, self)
	self.__index = self

	return o
end

--- Calls the hook.
---@param ... any
---@return any
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

	for _, v in ipairs(deadHooks) do
		self.listeners[v] = nil
	end
	if type(res) == "table" then
		return table.unpack(res)
	else
		return res
	end
end

local hookEntryId = 1

---@alias HookEntry string

---Attaches a listener to this hook.
---@param func fun(res: any, ...): any
---@param workerless boolean|nil
---@return HookEntry
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

---Removes a hook.
---@param entry HookEntry
function Hook:deattach(entry)
	self.listeners[entry] = nil
end

--- Similarly to event.pull, this will wait/sleep the process until completion.
--- The optional condition function gets the hook arguments and must return either true (quit waiting) or false (continue)
---@param condition nil | fun(...): boolean
---@return table
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
	---@diagnostic disable-next-line: param-type-mismatch
	return table.unpack(data)
end

return hooks
