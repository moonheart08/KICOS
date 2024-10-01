local asserteq = require("testing").asserteq
local fs = require("filesystem")

assert(#fs.list("/mnt") ~= 0, "Filesystem listing failed to return virtual nodes.")
