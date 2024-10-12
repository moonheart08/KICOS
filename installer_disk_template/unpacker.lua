-- AUTO GENERATED DO NOT MODIFY
-- Re-run build_unpacker.lua to change this script.
-- This script "just" unpacks the given tar file to a given disk.
-- Yes, this script tampers with require() which is bad for OpenOS.
-- The assumption is you plan to replace OpenOS and will not continue using it shortly after running this.

-- installer_disk_template/env_shim.lua
local function __GEN_env()
local env = {}
env.env = {}

return env

end
env = __GEN_env()
package.loaded["env"] = env

do --disk_template/slib/string.lua
-- Count matches in string.
function string.cmatch(s, pattern)
	local c = 0
	for _, _ in s:gmatch(pattern) do
		c = c + 1
	end
	return c
end

-- TODO: while this is nice for me, it's incompatible with annotated docs. :(

local function generateReaderForSignedUnsigned(unsigned, signed, fnName, tyNameSigned, tyNameUnsigned)
	for _, v in ipairs({ { "LE", "<" }, { "BE", ">" } }) do
		local signedFmt = v[2] .. signed
		string[string.format(fnName, v[1], tyNameSigned)] = function(str, pos)
			return string.unpack(signedFmt, str, pos)
		end

		local unsignedFmt = v[2] .. unsigned
		string[string.format(fnName, v[1], tyNameUnsigned)] = function(str, pos)
			return string.unpack(unsignedFmt, str, pos)
		end
	end

	string[string.format(fnName, "", tyNameSigned)] = string[string.format(fnName, "LE", tyNameSigned)]
	string[string.format(fnName, "", tyNameUnsigned)] = string[string.format(fnName, "LE", tyNameUnsigned)]
end

generateReaderForSignedUnsigned("B", "b", "read%s%s", "SByte", "Byte")
generateReaderForSignedUnsigned("I2", "i2", "read%s%s", "Short", "UShort")
generateReaderForSignedUnsigned("I4", "i4", "read%s%s", "Int", "UInt")
generateReaderForSignedUnsigned("I8", "i8", "read%s%s", "Long", "ULong")

-- Read a string of length len at pos in str.
function string.readFixedStr(str, pos, len)
	return string.unpack("<c" .. tostring(len), str, pos)
end

-- Read a string of length len at pos in str.
function string.readNullStr(str, pos)
	return string.unpack("<z", str, pos)
end

function string.readFixedOctal(str, pos, len)
	local str = string.readFixedStr(str, pos, len)
	return tonumber(str, 8)
end

end

-- disk_template/lib/tar.lua
local function __GEN_tar()
local tar <const> = {}

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

local endBlock = string.rep("\0", 512)

---@return TarFileEntry|nil
function Reader:__call()
	local header = self:nextBlock()

	if not header then
		return nil -- End of tar.
	end

	if header == endBlock then
		return nil
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

		local toTake = math.min(remaining, 513)
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

end
tar = __GEN_tar()
package.loaded["tar"] = tar

-- disk_template/lib/util.lua
local function __GEN_util()
local util <const> = {}

util.exitReasons = {
	-- Deliberately killed.
	killed = "killed",
	-- Ended normally.
	ended = "ended",
	-- Crashed.
	crashed = "crashed",
}

function util.deepCompare(t1, t2, ignore_mt)
	local ty1 = type(t1)
	local ty2 = type(t2)

	if ty1 ~= ty2 then
		return false
	end

	if ty1 ~= "table" then
		return t1 == t2
	end

	local mt = getmetatable(t1)

	if not ignore_mt and mt and mt.__eq then
		return t1 == t2
	end

	for k1, v1 in pairs(t1) do
		local v2 = t2[k1]

		if v2 == nil or not util.deepCompare(v1, v2) then
			return false
		end
	end

	for k2, v2 in pairs(t2) do
		local v1 = t1[k2]

		if v1 == nil or not util.deepCompare(v1, v2) then
			return false
		end
	end

	return true
end

local serialization = nil

function util.xpcallErrHandlerBuilder(writer, innerFrames)
	innerFrames = innerFrames or 2
	return function(x)
		local out = ""
		out = out .. string.format("ERR: %s", x or "") .. "\n"
		for i in debug.traceback():gmatch("([^\n]+)") do
			if i:match("^%s+machine%:") ~= nil or i:match("^%s+/slib%/workers%.lua%:") ~= nil then
			else
				-- Remove the util.lua and xpcall frames.
				if innerFrames > 0 then
					innerFrames = innerFrames - 1
				else
					out = out .. string.format(i) .. "\n"
				end
			end
		end
		return out
	end
end

function util.prettyPrint(x, writer)
	if not serialization then
		serialization = require("serialization")
	end

	if type(x) ~= "table" then
		x = { x }
	end

	local res, err = xpcall(function()
		local didSomething = false
		for i = 1, #x do
			didSomething = true
			if x[i] == nil then
				writer("nil")
			else
				writer(serialization.serialize(x[i], true))
			end
		end

		if not didSomething then
			writer("nil")
		end
	end, util.xpcallErrHandlerBuilder(writer))

	return res, err
end

return util

end
util = __GEN_util()
package.loaded["util"] = util

-- disk_template/lib/json.lua
local function __GEN_json()
---@alias jvalue table<string,jvalue>|string|number|jvalue[]

-- JSON serializer/deserializer. Not OpenOS's serializer! That generates lua, which can be a problem with untrusted inputs.
-- The parser itself is implemented with recursive descent, and should not be used on very large inputs.
-- Consider capping the size of untrusted inputs.
local json <const> = {}

local cNumRangeStart <const> = string.byte("0", 1)
local cNumRangeEnd <const> = string.byte("9", 1)
local cMinus <const> = string.byte("-", 1)
local cPlus <const> = string.byte("+", 1)
local cOpenBrace <const> = string.byte("{", 1)
local cCloseBrace <const> = string.byte("}", 1)
local cColon <const> = string.byte(":JSON", 1)
local cDoubleQuote <const> = string.byte("\"", 1)
local cBackslash <const> = string.byte("\\", 1)
local cOpenBracket <const> = string.byte("[", 1)
local cCloseBracket <const> = string.byte("]", 1)
local cComma <const> = string.byte(",", 1)
local cX <const> = string.byte("x", 1)
local cU <const> = string.byte("u", 1)

---@return jvalue?, integer
function json.deserialize(text, cfg)
	assert(cfg == nil or type(cfg) == "table", "Config must be a table or nil!")
	assert(type(text) == "string", "Text to deserialize MUST be a string!")

	cfg = cfg or {}

	local v, pos = json._deserialize(cfg, text, 1)
	pos = json._eatWhitespace(text, pos)

	if cfg.allowTrailingData ~= true then
		if string.len(text) > pos then
			json._parseError("Expected end of data stream, but did not find it.", text, pos)
		end
	end

	return v, pos
end

function json._deserialize(cfg, text, pos)
	local t = nil
	cfg = cfg or {}
	pos = pos or 1

	local pos, kind = json._guessValueType(cfg, text, pos)

	if kind == "number" then
		if string.byte(text, pos + 1) == cX then
			-- Hex.
			pos = pos + 2
			local s, e, m = string.find(text, "^(%x+)", pos)
			if s == nil then
				json._parseError("Failed to parse hex literal", text, pos)
			end

			t = tonumber(m, 16)
			return t, pos + (e - s) + 1
		else
			local s, e = string.find(text, "[+-]?[%d]+%.[%d]+e[%d]+", pos)
			if s == nil then
				s, e = string.find(text, "[+-]?[%d]+%.[%d]+", pos)
				if s == nil then
					s, e = string.find(text, "[+-]?[%d]+", pos)
					if s == nil then
						return json._parseError("Failed to parse number", text, pos)
					end
				end
			end

			t = tonumber(string.sub(text, s, e))

			if t == nil then
				json._parseError("Lua failed to parse number, but it matched patterns.", text, pos)
			end

			return t, pos + (e - s) + 1
		end
	elseif kind == "string" then
		return json._parseString(cfg, text, pos)
	elseif kind == "list" then
		return json._parseArray(cfg, text, pos)
	elseif kind == "table" then
		return json._parseTable(cfg, text, pos)
	end
end

local escapeTable = {
	["b"] = "\b",
	["f"] = "\f",
	["n"] = "\n",
	["r"] = "\r",
	["t"] = "\t",
	["\\"] = "\\",
}

---@return string | nil, integer
function json._parseString(cfg, text, pos)
	local str = ""
	repeat
		pos = pos + 1
		local b = string.byte(text, pos)
		if b == cBackslash then
			pos = pos + 1
			local bp = string.byte(text, pos)
			local escapeTableEntry = escapeTable[string.char(bp)]
			if escapeTableEntry ~= nil then
				str = str .. escapeTableEntry
			elseif bp == cU then
				pos = pos + 1
				local h = string.sub(text, pos, pos + 3)

				if string.len(h) ~= 4 then
					return json._parseError("Ran out of text when parsing unicode escape.", text, pos), -1
				end

				local num = tonumber(h, 16)

				if num == nil then
					return json._parseError("Expected valid unicode hex literal.", text, pos), -1
				end

				str = str .. utf8.char(num)
				pos = pos + 3
			else
				json._parseError("Unknown escape code.", text, pos)
			end
		elseif b ~= cDoubleQuote then
			str = str .. string.char(b)
		end
	until string.byte(text, pos) == cDoubleQuote

	return str, pos + 1
end

function json._parseArray(cfg, text, pos)
	local arr = {}

	while true do
		pos = pos + 1 -- eat the comma. Or opening bracket.
		local v = nil
		pos = json._eatWhitespace(text, pos)
		if string.byte(text, pos) == cCloseBracket then
			break
		end

		v, pos = json._deserialize(cfg, text, pos)
		table.insert(arr, v)
		pos = json._eatWhitespace(text, pos) -- Eat anything trailing the deserialized value.
		if string.byte(text, pos) ~= cComma then
			break
		end
	end

	pos = json._eatWhitespace(text, pos)

	if string.byte(text, pos) ~= cCloseBracket then
		json._parseError("Expected end of array.", text, pos)
	end

	return arr, pos + 1
end

function json._parseTable(cfg, text, pos)
	local t = {}

	while true do
		-- Discard the opening {, then eat whitespace.
		pos = json._eatWhitespace(text, pos + 1)

		if string.byte(text, pos) == cCloseBrace then
			break
		end

		local key = nil
		local ok = nil
		ok, key, pos = pcall(json._parseString, cfg, text, pos)
		if not ok then
			return json._parseError("Ran into error when reading key for table: " .. key, text, pos)
		end

		pos = json._eatWhitespace(text, pos)

		if string.byte(text, pos) ~= cColon then
			return json._parseError("Expected colon after table key.", text, pos)
		end
		-- Eat the equals, and trailing whitespace after it.
		pos = json._eatWhitespace(text, pos + 1)

		local value = nil

		value, pos = json._deserialize(cfg, text, pos)

		--Impossible for _parseString to return nil if we managed to get this far.
		---@diagnostic disable-next-line: need-check-nil
		t[key] = value

		pos = json._eatWhitespace(text, pos)

		if string.byte(text, pos) ~= cComma then
			break
		end
	end

	pos = json._eatWhitespace(text, pos)

	if string.byte(text, pos) ~= cCloseBrace then
		json._parseError("Expected end of table.", text, pos)
	end

	return t, pos + 1
end

---@return nil error
function json._parseError(err, text, loc)
	error(string.format("Parse error at byte %s: %s", loc, err), 2)
end

function json._isWhitespace(byte)
	return byte == 0x20 or byte == 0x0A or byte == 0x0D or byte == 0x09
end

function json._eatWhitespace(text, pos)
	while json._isWhitespace(string.byte(text, pos)) do
		pos = pos + 1
	end
	return pos
end

function json._guessValueType(cfg, text, pos)
	pos = json._eatWhitespace(text, pos)

	local start = string.byte(text, pos)
	if (start >= cNumRangeStart and start <= cNumRangeEnd) or start == cMinus or start == cPlus then
		return pos, "number"
	elseif start == cOpenBrace then
		return pos, "table"
	elseif start == cDoubleQuote then
		return pos, "string"
	elseif start == cOpenBracket then
		return pos, "list"
	else
		json._parseError("Unexpected token " .. string.char(start), text, pos)
	end
end

function json._serialize(cfg, value, addto)
	local vty = type(value)
	if vty == "number" then
		return addto .. tostring(value)
	elseif vty == "string" then
		return addto .. string.format("%q", value):gsub("\\\n", "\\n")
	elseif vty == "table" then
		-- Okay, what kind.
		local len = #value
		if len > 0 then -- Okay, assume an array. We can't serialize numeric keys in a table to JSON anyway.
			addto = addto .. "["

			for k, v in ipairs(value) do
				addto = json._serialize(cfg, v, addto)
				if k ~= len then
					addto = addto .. ","
				end
			end
			return addto .. "]"
		else
			addto = addto .. "{"

			for k, v in pairs(value) do
				addto = addto .. string.format("%q", k):gsub("\\\n", "\\n") .. ":"
				addto = json._serialize(cfg, v, addto)
				addto = addto .. ","
			end

			addto = string.sub(addto, 1, string.len(addto) - 1) -- Strip trailing comma.

			return addto .. "}"
		end
	else
		error("Cannot serialize type " .. vty)
	end
end

---@return string
function json.serialize(value, cfg)
	return json._serialize(cfg, value, "")
end

return json

end
json = __GEN_json()
package.loaded["json"] = json

-- disk_template/lib/serialization.lua
local function __GEN_serialization()
-- Copyright (c) 2013-2015 Florian "Sangar" Nücke
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

-- Exactly OpenOS's "serializer", for compatibility reasons.

local serialization <const> = {}

-- delay loaded tables fail to deserialize cross [C] boundaries (such as when having to read files that cause yields)
local local_pairs = function(tbl)
  local mt = getmetatable(tbl)
  return (mt and mt.__pairs or pairs)(tbl)
end

-- Deliberately pulled up and out of serialize to avoid creating a new one every time the function is called.
local kw = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function"] = true,
  ["goto"] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true
}

-- Important: pretty formatting will allow presenting non-serializable values
-- but may generate output that cannot be unserialized back.
function serialization.serialize(value, pretty)
  local id = "^[%a_][%w_]*$"
  local ts = {}
  local result_pack = {}
  local function recurse(current_value, depth)
    local t = type(current_value)
    if t == "number" then
      if current_value ~= current_value then
        table.insert(result_pack, "0/0")
      elseif current_value == math.huge then
        table.insert(result_pack, "math.huge")
      elseif current_value == -math.huge then
        table.insert(result_pack, "-math.huge")
      else
        table.insert(result_pack, tostring(current_value))
      end
    elseif t == "string" then
      table.insert(result_pack, (string.format("%q", current_value):gsub("\\\n", "\\n")))
    elseif
        t == "nil" or
        t == "boolean" or
        pretty and (t ~= "table" or (getmetatable(current_value) or {}).__tostring) then
      table.insert(result_pack, tostring(current_value))
    elseif t == "table" then
      if ts[current_value] then
        if pretty then
          table.insert(result_pack, "recursion")
          return
        else
          error("tables with cycles are not supported")
        end
      end
      ts[current_value] = true
      local f
      if pretty then
        local ks, sks, oks = {}, {}, {}
        for k in local_pairs(current_value) do
          if type(k) == "number" then
            table.insert(ks, k)
          elseif type(k) == "string" then
            table.insert(sks, k)
          else
            table.insert(oks, k)
          end
        end
        table.sort(ks)
        table.sort(sks)
        for _, k in ipairs(sks) do
          table.insert(ks, k)
        end
        for _, k in ipairs(oks) do
          table.insert(ks, k)
        end
        local n = 0
        f = table.pack(function()
          n = n + 1
          local k = ks[n]
          if k ~= nil then
            return k, current_value[k]
          else
            return nil
          end
        end)
      else
        f = table.pack(local_pairs(current_value))
      end
      local i = 1
      ---@type boolean|nil
      local first = true
      table.insert(result_pack, "{")
      for k, v in table.unpack(f) do
        if not first then
          table.insert(result_pack, ",")
          if pretty then
            table.insert(result_pack, "\n" .. string.rep(" ", depth))
          end
        end
        first = nil
        local tk = type(k)
        if tk == "number" and k == i then
          i = i + 1
          recurse(v, depth + 1)
        else
          if tk == "string" and not kw[k] and string.match(k, id) then
            table.insert(result_pack, k)
          else
            table.insert(result_pack, "[")
            recurse(k, depth + 1)
            table.insert(result_pack, "]")
          end
          table.insert(result_pack, "=")
          recurse(v, depth + 1)
        end
      end
      ts[current_value] = nil -- allow writing same table more than once
      table.insert(result_pack, "}")
    else
      error("unsupported type: " .. t)
    end
  end
  recurse(value, 1)
  local result = table.concat(result_pack)
  if pretty then
    local limit = type(pretty) == "number" and pretty or 10
    ---@type integer|nil
    local truncate = 0
    while limit > 0 and truncate do
      truncate = string.find(result, "\n", truncate + 1, true)
      limit = limit - 1
    end
    if truncate then
      return result:sub(1, truncate) .. "..."
    end
  end
  return result
end

function serialization.unserialize(data)
  local result, reason = load("return " .. data, "=data", nil, { math = { huge = math.huge } })
  if not result then
    return nil, reason
  end
  local ok, output = pcall(result)
  if not ok then
    return nil, output
  end
  return output
end

return serialization

end
serialization = __GEN_serialization()
package.loaded["serialization"] = serialization

-- disk_template/lib/present.lua
local function __GEN_present()
local util <const> = require("util")
local env <const> = require("env")
local io <const> = require("io")
local present <const> = {}

-- OpenOS compat shim.
local old_print = print
local function print(...)
	old_print(string.format(...))
end
function present.inputChar()
	io.write(":")
	local c = io.read(1) -- wait.
	io.write("\b")    -- backspace that out.

	return c
end

function present.more(table)
	local printed = 0
	for k, v in pairs(table) do
		local key = ""
		util.prettyPrint(k, function(...) key = key .. string.format(...) end)
		local value = ""
		util.prettyPrint(v, function(...) value = value .. string.format(...) end)
		print("%s = %s", key, value)
		printed = printed + 1
		if printed > (env.env().moreThreshhold or 15) then
			local c = present.inputChar()

			if c == "q" then
				print("quit")
				return -- ok done.
			end
		end
	end
end

function present.hex(str, width)
	width = width or 16
	for i = 1, str:len() do
		local c = str:byte(i)

		io.write(string.format("%02x ", c))

		if i % width == 0 then
			io.write("\n")
		end
	end

	io.write("\n")
end

function present.yesNo()
	local yn = nil

	while yn ~= "y" and yn ~= "n" do
		yn = present.inputChar()
	end

	return yn == "y"
end

function present.select(tab)
	assert(#tab < 10)

	for i = 1, #tab do
		print("%1i: %s", i, tab[i])
	end

	while true do
		local c = present.inputChar()

		if c == "q" then
			return nil
		end

		local n = tonumber(c)
		if not (n == nil or n < 0 or n > #tab) then
			return tab[n]
		end
	end
end

return present

end
present = __GEN_present()
package.loaded["present"] = present

do --installer_disk_template/unpacker_core.lua
local io = require("io")
local tar = require("tar")
local present = require("present")
local component = require("component")
local computer = require("computer")
local pack = io.open("disk.tar", "rb")
assert(pack, "No package file found. Please make sure you downloaded disk.tar")

local old_print = print
local function print(...)
    old_print(string.format(...))
end

local reader = tar.Reader:new(function(amnt)
    return pack:read(amnt)
end)


local target

do
    local targets = {}

    for target, _ in component.list("filesystem") do
        if target ~= computer.getBootAddress() and target ~= computer.tmpAddress() then
            table.insert(targets, target)
        end
    end

    print("Select a target drive:")
    target = present.select(targets)
end

local proxy = component.proxy(target)

print("Should this drive be WIPED? (y/n)")
if present.yesNo() then
    for _, obj in pairs(proxy.list("/")) do
        print("Deleting /%s", obj)
        proxy.remove("/" .. obj)
    end
end


for file in reader do
    ---@type TarFileEntry
    local file = file

    if file.data == "" and (file.type == "unsupported" or file.type == "directory") then
        print("Making directory %s", file.filename)
        proxy.makeDirectory(file.filename)
    else
        local h = proxy.open("/" .. file.filename, "wb")
        print("Writing %s (%sB)", file.filename, file.data:len())
        assert(h, "Could not write " .. file.filename)
        proxy.write(h, file.data)
        proxy.close(h)
    end
end

end
