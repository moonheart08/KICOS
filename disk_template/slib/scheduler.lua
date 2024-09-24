local scheduler = {_scheduled_workers = {}}
local uptime = computer.uptime
local pull = computer.pullSignal
local push = computer.pushSignal

function scheduler.run()
	while true do
		local didWork = false
		for _,v in pairs(scheduler._scheduled_workers) do
			if v._leader ~= nil and not v:paused() then
				coroutine._nativeResume(v._leader)
				didWork = true
			end
			scheduler.pumpEvents()
		end
		
		if not didWork then
			error("All runnable workers died!")
		end
	end
end
local eventbus = nil

function scheduler.pumpEvents()
	if eventbus == nil then
		eventbus = require("eventbus")
	end
	
	eventbus.pump()
end

return scheduler