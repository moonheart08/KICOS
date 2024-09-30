local syslog = require("syslog")
local util = require("util")

local testing = {}

function testing.asserteq(left, right)
	if not util.deepCompare(left, right) then
		error(string.format("{%s} is not equal to {%s}", left, right), 2)
	end
end

return testing