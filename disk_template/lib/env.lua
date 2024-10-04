local workers = require("workers")
local syslog = require("syslog")

local env = {}

function env.env()
	return workers.current().env
end

function env._setupInitialEnv()
	local filesystem = require("filesystem")
	local json = require("json")
	-- In case the user fucked up the file somehow, be ready to load the fallback.
	local res, e = pcall(json.deserialize, filesystem.readFile("/cfg/initial_env.json"))

	if not res or type(e) ~= "table" then
		syslog:error("FAILED TO LOAD USER PROVIDED INITIAL ENV. FIX IT!")
		syslog:error("%s", e or "Probably wasn't a table...")
		-- If we can't load this we explode, though.
		e = json.deserialize(filesystem.readFile("/lib/initial_env.json"))
	end

	assert(type(e) == "table", "Initial env MUST be a table.")

	local EnvTable = env.env()

	for k, v in pairs(e) do
		EnvTable[k] = v
	end
end

return env
