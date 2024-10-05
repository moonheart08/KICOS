local io = require("io")
local package = require("package")
local asserteq = require("testing").asserteq
local json = require("json")

asserteq(table.pack(json._guessValueType({}, "123", 1))[2], "number")
asserteq(table.pack(json._guessValueType({}, "{}", 1))[2], "table")
asserteq(table.pack(json._guessValueType({}, "[]", 1))[2], "list")
asserteq(table.pack(json._guessValueType({}, "\"\"", 1))[2], "string")
asserteq(json._deserialize({}, "0x1A"), 0x1A)
asserteq(json._deserialize({}, "0.1"), 0.1)
asserteq(json._deserialize({}, "\"abcdef\\u0020\\t\""), "abcdef \t")
asserteq(json._deserialize({}, "[1, 2, 3]"), { 1, 2, 3 })
asserteq(json._deserialize({}, "[1, [1, 2], 3]"), { 1, { 1, 2 }, 3 })
asserteq(json._deserialize({}, "{\"foo\": 1}"), { foo = 1 })
asserteq(json._deserialize({}, "{\"foo\": 1, \"bar\": \"baz\"}"), { foo = 1, bar = "baz" })

local test = { array = { 1, 2, 3 }, str = "among us.\n", table = { foo = "bar", baz = "qux" } }
local ser = json.serialize(test)
asserteq(test, json.deserialize(ser))
