local args = ...
local filesystem = require("filesystem")

local listing

if args ~= "" then
	listing = filesystem.list(args)
else
	listing = filesystem.list(require("env").env().workingDirectory)
end
listing = listing or {}
for _, v in pairs(listing) do
	print(v)
end