local eventbus <const> = {
	maxEventsPumped = 32,
	_listeners = {}
}

local syslog <const> = require("syslog")
local workers <const> = require("workers")
local ctx <const> = require("kicos")

local native_pull = computer.pullSignal
local native_push = computer.pushSignal

function eventbus.pump()
	local i = 0
	while i < eventbus.maxEventsPumped do
		local signal = table.pack(native_pull(0))

		if signal.n > 0 then
			-- Oooo, what'd we find?
			local kind = signal[1]

			if eventbus._listeners[kind] ~= nil then
				local to_remove = {}
				for k, v in pairs(eventbus._listeners[kind]) do
					if coroutine.status(v) ~= "dead" then
						for i = 1, 16 do
							-- TODO: Handle OS yields in an event listener more nicely.
							local status, oyield, status2, err = coroutine._nativeResume(v, table.unpack(signal))
							if oyield or not status then -- If we're a real yield and not an OS yield.
								nstat = status and status2
								if not nstat then
									table.insert(to_remove, k)
								end
								if not status then
									syslog:warning("Event handler crashed. %s", err)
								end
								break
							end

							if i == 16 then
								syslog:error("FUCK")
							end
						end
					else
						table.insert(to_remove, k)
					end
				end

				local adj = 0
				for _, v in ipairs(to_remove) do
					syslog:trace("Removed listener %s from event %s",
						workers.prettyPrintCoroutine(eventbus._listeners[kind][v]), kind)
					eventbus._listeners[kind][v] = nil
				end
			end
		else
			return
		end

		i = i + 1
	end

	syslog:warning("Eventbus jammed, significant number of events.")
end

-- Note: Unlike OpenOS, this does not support patterns for the filter!
-- Note 2: Must be called
function eventbus.pull(timeout, filter, ...)
	if type(timeout) == "string" then
		filter = timeout
		timeout = -1
	end

	local startTime = computer.uptime()
	local share = nil

	local d = workers._get_coroutine_data(coroutine.running())
	local listener = coroutine.createNamed(function(...)
		share = table.pack(...)
		d._asleep = false
		return false
	end, string.format("Poll listener (%s)", filter))

	eventbus.listen(filter, listener)

	if timeout < 0 then
		d._asleep = true
	end

	while share == nil and ((computer.uptime() < startTime + timeout) or timeout < 0) do coroutine.yieldToOS() end -- Yield to the OS scheduler.

	---@diagnostic disable-next-line: param-type-mismatch
	return table.unpack(share or {})
end

-- Takes an event to listen to, and a function or coroutine to act as a listener.
function eventbus.listen(event, co)
	if event == nil then
		return
	end

	local listeners = eventbus._listeners
	if listeners[event] == nil then
		listeners[event] = {}
	end

	local t = listeners[event]

	if type(co) == "function" then
		local co_ref = co
		co = coroutine.create(function(...)
			local args = table.pack(...)
			while true do
				local res = table.pack(pcall(co_ref, table.unpack(args)))
				if not res[1] then
					syslog:warning("Listener crashed: %s", res[2])
					return
				end

				table.remove(res, 1)
				args = table.pack(coroutine.yield(table.unpack(res)))
			end
		end)

		coroutine.setName(co, "Event listener (" .. event .. ")")
	end

	syslog:trace("Attached listener %s to event %s", workers.prettyPrintCoroutine(co), event)

	t[tostring(co)] = co
	return tostring(co)
end

function eventbus.remove(event, co, idx)
	local listeners = eventbus._listeners
	if listeners[event] == nil then
		return false
	end

	local t = listeners[event]

	if t[idx] ~= co then
		return false
	end

	return eventbus._remove(event, idx)
end

function eventbus._remove(event, idx)
	local listeners = eventbus._listeners
	if listeners[event] == nil then
		return false
	end

	local t = listeners[event]

	t[idx] = nil

	return true
end

eventbus.push = function(...)
	ctx.scheduler.pumpNow = true
	return computer.pushSignal(...)
end

computer.pullSignal = eventbus.pull -- No, don't you dare use the builtin pull to freeze my system.

return eventbus
