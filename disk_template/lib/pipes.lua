local hooks <const> = require("hooks")
local workers <const> = require("workers")
local ev <const> = require("eventbus")
local kicosG <const> = require("_G") -- man, gross.

local pipes <const> = {}
---@class Pipe
---@field writeProxy fun(...)
---@field buffer string | nil
---@field bufferSize integer
---@field lastReader Worker? Last reader to interact with this pipe.
---@field lastWriter Worker? Last writer to interact with this pipe.
---@field onTryWrite Hook
local Pipe = {}
pipes.Pipe = Pipe

---Only use unbuffered (size 0) pipes if you know what you're doing!
---@param bufferSize integer?
---@return Pipe
function Pipe:new(bufferSize)
	bufferSize = bufferSize or 1024
	local o
	---@type Pipe
	o = {
		writeProxy = function(...) return o:write(...) end,
		onTryWrite = hooks.Hook:new(),
		bufferSize = bufferSize,
	}

	setmetatable(o, self)
	self.__index = self

	if bufferSize > 0 then
		o.buffer = ""
		o.onTryWrite:attach(Pipe._buffer(o), true) -- Attach workerless, so the pipe doesn't just stop buffering if the worker that made it dies.
	end

	return o
end

-- Returns amount read.
function Pipe:tryWrite(chunk)
	self.lastWriter = workers.current()
	if self.closed then
		return false
	end

	local res = self.onTryWrite:call(chunk, false)
	return res or false -- Result or failure, nonblocking.
end

function Pipe._buffer(pipe)
	return function(res, chunk)
		if res then
			return res
		end

		local avail = pipe.bufferSize - string.len(pipe.buffer)
		if avail == 0 then
			return 0
		end
		local bite = string.sub(chunk, 1, avail)
		pipe.buffer = pipe.buffer .. bite

		return avail
	end
end

-- Always writes the entirety, if possible.
function Pipe:write(chunk)
	self.lastWriter = workers.current()
	if self.closed then
		return false
	end

	local res = 0
	while true do
		res = self.onTryWrite:call(chunk, false)
		if type(res) == "number" then
			chunk = string.sub(chunk, res + 1, -1)
			if string.len(chunk) == 0 then
				return true
			end
		else
			return res or false
		end

		coroutine.yieldToOS()
	end
end

-- Ala UNIX pipes, these only support blocking reads.
function Pipe:read(a)
	self.lastReader = workers.current()
	if self.closed then
		return ""
	end

	if self.buffer then
		while true do
			if string.len(self.buffer) > 0 then
				local out = string.sub(self.buffer, 1, a)
				self.buffer = string.sub(self.buffer, a + 1, -1)
				return out
			elseif not self.closed then
				-- Snooze until we got something.
				self.onTryWrite:await()
			else
				return ""
			end
		end
	else
		local b = nil
		self.onTryWrite:await(function(res, chunk, blocking)
			b = string.sub(chunk, 1, a)
			return true
		end)
		return b
	end
end

function Pipe:clearBuffer()
	if self.buffer then
		self.buffer = ""
	else
		error("Cannot clear an unbuffered pipe!")
	end
end

function Pipe:close()
	self.closed = true           -- die!!!
	self.onTryWrite:call("", false) -- Ensure awaiters get the memo.
end

function Pipe:__close()
	self:close()
	self.onTryWrite = nil -- Ditch it.
end

--- "Hands over" the pipe to the given worker, adjusting the last reader and writer.
--- This just makes sure you don't get Ctrl-C'd through that pipe.
function Pipe:handover(worker)
	self.lastReader = worker
	self.lastWriter = worker
end

---@param worker Worker
---@return Stdout
function pipes._makeStdout(worker)
	---@class Stdout: Pipe
	---@field _stdoutHook HookEntry
	local out = Pipe:new(0) -- Unbuffered.

	out._stdoutHook = out.onTryWrite:attach(function(res, chunk, blocking)
		if worker.env.stdoutTarget ~= nil and worker.env.stdoutTarget.write ~= nil and worker.env.stdoutTarget.tryWrite ~= nil then
			if blocking then
				return worker.env.stdoutTarget:write(chunk)
			else
				return worker.env.stdoutTarget:tryWrite(chunk)
			end
		else
			kicosG._logVTerm:printText(chunk)
			return true
		end
	end)

	worker.stdout = out
	out.worker = worker
	return out
end

---@param worker Worker
---@return Stdin
function pipes._makeStdin(worker)
	---@class Stdin: Pipe
	---@field _id string
	---@field worker Worker
	local stdin = Pipe:new(1024) -- 1024B input buffer.

	worker.stdin = stdin

	return stdin
end

---@param worker Worker?
---@return Pipe
function pipes.stdin(worker)
	worker = worker or workers.current()
	if not worker.stdin then
		if worker.env.stdinTarget then
			worker.stdin = worker.env.stdinTarget
			return worker.stdin
		end
		return pipes._makeStdin(worker)
	else
		return worker.stdin
	end
end

---@param worker Worker?
---@return Stdout
function pipes.stdout(worker)
	worker = worker or workers.current()
	if not worker.stdout then
		return pipes._makeStdout(worker)
	else
		return worker.stdout
	end
end

return pipes
