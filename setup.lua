local internet = require("internet")
local fs = require("filesystem")
local branch = "master"
local remoteFilesUrl = "https://raw.githubusercontent.com/moonheart08/gtnh-oc/"..branch.."/"

local function grabFile(url)
	local handle = internet.request(url)
	local result = ""
	-- Accumulate chunks of data from the sender.
	for chunk in handle do 
		result = result..chunk 
	end
	
	local mt = getmetatable(handle)
	
	local code, message, headers = mt.__index.response()
	
	return result
end

-- Maps files on the disk to files on the repo. They will be fetched and emplaced one at a time.
local repoMap = {
	{"/bin/setup.lua", "setup.lua"}
}

-- OC computers don't have particularly much disk space, much less RAM, so I opt to not try to cache the changes in memory before applying.
for entry in repoMap do
	local url = remoteFilesUrl .. entry[2]
	local data = grabFile(url)
	local handle = fs.open(entry[1], "wb")
	handle:write(data)
	handle:close()
end