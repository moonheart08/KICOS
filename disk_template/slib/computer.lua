function computer.sleep(n)
	local start = computer.uptime()

	while (computer.uptime() - start) < n do coroutine.yieldToOS() end
end

local env
function os.getenv(field)
	if not env then
		env = require("env")
	end

	return env.env()[field]
end
