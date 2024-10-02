local util = {}

util.exitReasons = {
	-- Deliberately killed.
	killed = "killed",
	-- Ended normally.
	ended = "ended",
	-- Crashed.
	crashed = "crashed",
}

function util.deepCompare(t1, t2, ignore_mt)
    local ty1 = type(t1)
    local ty2 = type(t2)
	
    if ty1 ~= ty2 then
        return false
    end
	
    if ty1 ~= "table" then
        return t1 == t2
    end

    local mt = getmetatable(t1)
	
    if not ignore_mt and mt and mt.__eq then
        return t1 == t2
    end
	
    for k1, v1 in pairs(t1) do
        local v2 = t2[k1]
		
        if v2 == nil or not util.deepCompare(v1, v2) then
            return false
        end
    end
	
    for k2, v2 in pairs(t2) do
        local v1 = t1[k2]
		
        if v1 == nil or not util.deepCompare(v1, v2) then
            return false
        end
    end
	
    return true
end

local serialization = nil

function util.xpcallErrHandlerBuilder(writer, innerFrames)
	local out = ""
	innerFrames = innerFrames or 2
	return function(x)
		out = out .. string.format("ERR: %s", x or "")  .. "\n"
		for i in debug.traceback():gmatch("([^\n]+)") do
			if i:match("^%s+machine%:") ~= nil or i:match("^%s+/slib%/workers%.lua%:") ~= nil then
			else
				-- Remove the util.lua and xpcall frames.
				if innerFrames > 0 then
					innerFrames = innerFrames - 1
				else
					out = out .. string.format(i) .. "\n"
				end
			end

		end
		return out
	end

end

function util.prettyPrint(x, writer)
	if not serialization then
		serialization = require("serialization")
	end
	
	if type(x) ~= "table" then
		x = {x}
	end
	
	local res, err = xpcall(function()
		local didSomething = false
		for i = 1, #x do
			didSomething = true
			if x[i] == nil then
				writer("nil")
			else
				writer(serialization.serialize(x[i], true))
			end
		end
		
		if not didSomething then
			writer("nil")
		end
	end, util.xpcallErrHandlerBuilder(writer))
	
	return res, err
end

return util