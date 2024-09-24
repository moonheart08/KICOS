local syslog = _kicosCtx.syslog
syslog:info("Setting up package management.")

local package = {}
package.loaded = {
	["_G"] = _G,
	["bit32"] = bit32,
	["coroutine"] = coroutine,
	["workers"] = _kicosCtx.workers,
	["vterm"] = _kicosCtx.VTerm,
	["syslog"] = _kicosCtx.syslog,
	["math"] = math,
	["os"] = os,
	["package"] = package,
	["string"] = string,
	["table"] = table,
	["component"] = component,
}

package.locators = {}

package.require = function(pname)
	if package.loaded[pname] then
		return package.loaded[pname]
	end
	syslog:info("require() grabbing uncached package {%s}", pname)
	
	for _, locator in ipairs(package.locators) do
		local status, res = pcall(locator, pname)
		if status then
			local pkg = res()
			package.loaded[pname] = pkg
			return pkg
		end
	end
	
	error("Couldn't locate package " .. pname)
end

_G.require = package.require
_G.package = package