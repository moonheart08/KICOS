local workers = require("workers")
local syslog = require("syslog")

local env = {}

function env.env() 
	return workers.current().env
end

function env._setupInitialEnv()
	local filesystem = require("filesystem")
	local json = require("json")
	local e = json.deserialize(filesystem.readFile("/cfg/initial_env.json"))
	local EnvTable = env.env()

	for k, v in pairs(e) do
		EnvTable[k] = v
	end
end

return env