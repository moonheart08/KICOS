-- Yieldable pcall.
-- This is STUPID and BAD, but necessary because this isn't luajit.
function ypcall(func, handler)
	local r = coroutine.create(func)

	return coroutine.resume(r)
end
