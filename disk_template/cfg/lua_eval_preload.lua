component = require("component")
env = require("env")
json = require("json")
filesystem = require("filesystem")
util = require("util")
pipes = require("pipes")
present = require("present")

more = present.more

__qloadedName = nil

function qload(pack)
	package.drop(pack)
	_G[pack] = require(pack)
	__qloadedName = pack
end

function qrload()
	qload(__qloadedName)
end

function readfile(f)
	return filesystem.readFile(f)
end