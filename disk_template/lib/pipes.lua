local hooks = require("hooks")
local workers = require("workers")
local ev = require("eventbus")
local syslog = require("syslog")
local kicosG = require("_G") -- man, gross.

local pipes = {}
local Pipe = {}
pipes.Pipe = Pipe

-- Only use unbuffered (size 0) pipes if you know what you're doing!
function Pipe:new(bufferSize)
	bufferSize = bufferSize or 1024
	local o = {
		writeProxy = function(...) o:write(...) end,
		onTryWrite = hooks.Hook:new()
	}
	
	setmetatable(o, self)
	self.__index = self
	
	if bufferSize > 0 then
		o.buffer = ""
		o.bufferSize = bufferSize
		o.onTryWrite:attach(Pipe._buffer(o), true) -- Attach workerless, so the pipe doesn't just stop buffering if the worker that made it dies.
	end
	
	return o
end

-- Returns amount read.
function Pipe:tryWrite(chunk)
	local res = self.onTryWrite:call(chunk, false)
	return res or false -- Result or failure, nonblocking.
end

function Pipe._buffer(pipe)
	return function(res, chunk)
		if res then
			return res
		end
		local clen = string.len(chunk)
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
	if self.buffer then
		while true do
			if string.len(self.buffer) > 0 then
				local out = string.sub(self.buffer, 1, a)
				self.buffer = string.sub(self.buffer, a + 1, -1)
				return out
			else
				-- Snooze until we got something.
				self.onTryWrite:await()
			end
		end
	else
		local b = nil
		self.onTryWrite:await(function(res, chunk, blocking) 
				b = string.sub(chunk, 1, a)
				return math.min(string.len(chunk), a)
			end)
		return b
	end
end

function pipes._makeStdout(worker) 
	local out = Pipe:new(0) -- Unbuffered.
	
	out._stdoutHook = out.onTryWrite:attach(function(res, chunk, blocking) 
		if worker.stdoutTarget ~= nil and worker.stdoutTarget.write ~= nil and worker.stdoutTarget.tryWrite ~= nil then
			if blocking then
				return worker.stdoutTarget:write(chunk)
			else
				return worker.stdoutTarget:tryWrite(chunk)
			end
		else
			kicosG._logVTerm:printText(chunk)
			return true
		end
	end)
	
	worker.stdout = out
	return out
end

local stdins = {}
local stdinIds = 1
setmetatable(stdins, {__mode = "v"})


function pipes._makeStdin(worker)
	local stdin = Pipe:new(1024) -- 1024B input buffer.
	
	worker.stdin = stdin
	stdin._id = tostring(stdinIds)
	stdinIds = stdinIds + 1
	stdins[stdin._id] = stdin
	return stdin
end

function pipes.stdin(worker)
	worker = worker or workers.current()
	if not worker.stdin then
		return pipes._makeStdin(worker)
	else
		return worker.stdin
	end
end

-- Non-blocking focus request. Does not guarantee stdin actually becomes the current keyboard reader!
function pipes.focusStdin(worker)
	worker = worker or workers.current()
	local stdin = pipes.stdin(worker)
	ev.push("focus_stdin", stdin._id)
end

function pipes._getStdinById(id)
	return stdins[id]
end

function pipes.stdout(worker)
	worker = worker or workers.current()
	if not worker.stdout then
		return pipes._makeStdout(worker)
	else
		return worker.stdout
	end
end

return pipes