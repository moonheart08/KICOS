local io = require("io")
local fs = require("filesystem")
local workers = require("workers")
local util = require("util")

print("Running test suite.")

local tests = {}

for _, v in pairs(fs.list("/tests/")) do
	if v:match(".lua$") then
		table.insert(tests, "/tests/" .. v)
	end
end

table.sort(tests)

local fails = {}

for k,v in ipairs(tests) do
	print("Running test %s", v)
	local w = workers.runProgram(v)
	local _, res = w.onDeath:await()
	if res ~= util.exitReasons.ended then
		print("Failed!")
		table.insert(fails, v)
	end
end

if #fails > 0 then
	local out = "The following tests failed (run them individially for debugging?): "
	for k, v in ipairs(fails) do
		out = out .. v .. ", "
	end
	print(out)
else
	print("All tests passed.")
end
