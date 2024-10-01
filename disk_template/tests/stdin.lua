local io = require("io")
local pipes = require("pipes")
local asserteq = require("testing").asserteq

local test_string = "Awawa\n"
local test_string_2 = "Ababababa\n"

local stdin = pipes.stdin()
stdin:write(test_string)
stdin:write(test_string_2)

local first = io.read("l", false)
local second = io.read("l", false)

asserteq(first, string.sub(test_string, 1, string.len(test_string) - 1))
asserteq(second, string.sub(test_string_2, 1, string.len(test_string_2) - 1))