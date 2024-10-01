-- Count matches in string.
function string.cmatch(s, pattern)
	local c = 0
	for _, _ in s:gmatch(pattern) do
		c = c + 1
	end
	return c
end

local function generateReaderForSignedUnsigned(unsigned, signed, fnName, tyNameSigned, tyNameUnsigned)
	for _, v in ipairs({{"LE", "<"}, {"BE", ">"}}) do
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