-- Yieldable pcall.
-- This is STUPID and BAD, but necessary because this isn't luajit.
function ypcall(func, ...)
	local r = coroutine.create(func)

	return coroutine.resume(r, ...)
end
