function computer.sleep(n)
	local start = computer.uptime()
	
	while (computer.uptime() - start) < n do coroutine.yieldToOS() end
end