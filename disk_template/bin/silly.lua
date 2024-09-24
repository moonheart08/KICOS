local syslog = require("syslog")
local io = require("io")

syslog:info("Silly! :3")
coroutine.yieldToOS()
syslog:info("and being cooperative 2")