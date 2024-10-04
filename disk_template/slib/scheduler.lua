local scheduler = { _scheduled_workers = {} }

function scheduler.run()
	while true do
		local didWork = false

		local ut = computer.uptime()
		for _, v in pairs(scheduler._scheduled_workers) do
			if v._leader ~= nil and not v.dead and not _kicosCtx.workers._get_coroutine_data(v._leader)._asleep then
				coroutine._nativeResume(v._leader)
			end
			if computer.uptime() - ut > 0.05 or scheduler.pumpNow then
				scheduler.pumpEvents()
				didWork = true
				ut = computer.uptime()
			end
		end

		if not didWork then
			-- Make sure we still yield to OC and read our eventbus.
			scheduler.pumpEvents()
		end
	end
end

local eventbus = nil

function scheduler.pumpEvents()
	scheduler.pumpNow = false
	if eventbus == nil then
		eventbus = require("eventbus")
	end

	eventbus.pump()
end

return scheduler
