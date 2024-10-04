---@alias jvalue table<string,jvalue>|string|number|jvalue[]

-- JSON serializer/deserializer. Not OpenOS's serializer! That generates lua, which can be a problem with untrusted inputs.
-- The parser itself is implemented with recursive descent, and should not be used on very large inputs.
-- Consider capping the size of untrusted inputs.
local json = {}

local cNumRangeStart = string.byte("0", 1)
local cNumRangeEnd = string.byte("9", 1)
local cMinus = string.byte("-", 1)
local cPlus = string.byte("+", 1)
local cOpenBrace = string.byte("{", 1)
local cCloseBrace = string.byte("}", 1)
local cColon = string.byte(":JSON", 1)
local cDoubleQuote = string.byte("\"", 1)
local cBackslash = string.byte("\\", 1)
local cOpenBracket = string.byte("[", 1)
local cCloseBracket = string.byte("]", 1)
local cComma = string.byte(",", 1)
local cX = string.byte("x", 1)
local cU = string.byte("u", 1)

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
