local tar = {}

---@alias TarReader fun(amount: integer): string|nil
---@private

---@class Reader
---@field _reader TarReader
local Reader = {}

tar.Reader = Reader

---comment
---@param readerFunc TarReader
---@return Reader
function Reader:new(readerFunc)
	---@type Reader
	local o = {
		_reader = readerFunc
	}
	setmetatable(o, self)
	self.__index = self

	return o
end

function Reader:nextBlock()
	local b = ""
	while b:len() < 512 do
		local chunk = self._reader(512 - b:len())

		if not chunk then
			return nil -- Whoops. End of file...
		end
		b = b .. chunk
	end

	return b
end

---@alias TarFileType
---| "normal"
---| "directory"
---| "unsupported"

local typeDict = {
	["\0"] = "normal",  -- Normal file.
	["0"] = "normal",   -- Normal file.
	["1"] = "unsupported", -- hard link.
	["2"] = "unsupported", -- symbolic link.
	["3"] = "unsupported", -- character device.
	["4"] = "unsupported", -- block device.
	["5"] = "directory", -- directory.
}

-- This is an iterator, yippee.
---comment
---@return nil
function Reader:__call()
	local header = self:nextBlock()

	if not header then
		return nil -- End of tar.
	end

	assert(string.readNullStr(header, 258) == "ustar",
		"MUST be a ustar format tar file! Other formats are not supported!")
	assert(string.readFixedOctal(header, 264, 2) == 0, "MUST be a version 0 ustar file!")

	---@class TarFileEntry
	---@field filename string
	---@field data string
	---@field type TarFileType
	local file = {}
	file.type = typeDict[string.char(string.readByte(header, 157))] or "unsupported"

	local filenamePrefix = string.readNullStr(header, 346)
	local filename = string.readNullStr(header, 1)
	file.filename = filenamePrefix .. filename
	local fileSize = string.readFixedOctal(header, 125, 12)

	local data = ""
	local remaining = fileSize
	while remaining > 0 do
		local chunk = self:nextBlock()

		if chunk == nil then
			return nil
		end

		local toTake = math.min(remaining - 514, 512)
		data = data .. chunk:sub(1, toTake)
		remaining = remaining - 512
	end

	file.data = data

	return file
end

function tar.stringReaderBuilder(str)
	local pos = 1

	return function(len)
		local out = str:sub(pos, pos + len)
		pos = pos + len
		return out
	end
end

return tar
