function component.byType(ty)
	for k, v in component.list(ty) do
		return k
	end
end

function component.proxyByType(ty)
	return component.proxy(component.byType(ty))
end

local fs = nil
local json = nil

function component.cnames()
	if not require then
		return nil
	end

	if not fs then
		fs = require("filesystem")
	end

	if not json then
		json = require("json")
	end

	local cnames

	do
		local text = fs.readFile("/cfg/cnames")
		if not text or text == "" then
			return nil -- No cnames file.
		end

		cnames = json.deserialize(text)
	end

	return cnames
end

function component.byName(name)
	local cnames = component.cnames()

	if cnames and cnames[name] == "string" then
		return cnames[name]
	end

	return nil
end

function component.nameOf(addr)
	local cnames = component.cnames()

	if not cnames then
		return nil
	end

	cnames = table.invert(cnames)

	return cnames[addr]
end

function component.getNamedGroup(name)
	local cnames = component.cnames()

	if cnames and cnames[name] == "table" then
		return cnames[name]
	end

	return nil
end
