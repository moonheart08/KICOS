local env = require("env")

for k, v in pairs(env.env()) do
	print("%s | {%s}", k, tostring(v))
end