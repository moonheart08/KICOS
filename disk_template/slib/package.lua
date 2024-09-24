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
	["scheduler"] = _kicosCtx.scheduler,
	["kicos"] = _kicosCtx,
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
		if status and res ~= nil then
			local pkg = res()
			package._insert(pname, pkg)
			return pkg
		elseif res ~= nil then
			syslog:warning("Package locator failed, got %s", res)
		end
	end
	
	error("Couldn't locate package " .. pname)
end

package._insert = function(pname, t)
	package.loaded[pname] = t
end

_G.require = package.require
_G.package = package