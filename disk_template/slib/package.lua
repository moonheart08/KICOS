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
	["computer"] = computer,
}

package.fundamental = {}

for k, _ in pairs(package.loaded) do
	package.fundamental[k] = true
end

package.locators = {}

package.require = function(pname)
	if package.loaded[pname] then
		return package.loaded[pname]
	end
	syslog:info("require() grabbing uncached package {%s}", pname)
	
	for _, locator in ipairs(package.locators) do
		local status, res = pcall(locator, pname)
		if status and res ~= nil then
			if type(res) == "table" then
				local pkg = load(res[1], "=VFS" .. res[2], "bt", _kicosCtx.workers.buildGlobalContext())()
				package._insert(pname, pkg)
				return pkg
			else
				local pkg = res()
				package._insert(pname, pkg)
				return pkg
			end
		elseif res ~= nil then
			syslog:warning("Package locator failed, got %s", res)
		end
	end
	
	error("Couldn't locate package " .. pname)
end

package._insert = function(pname, t)
	package.loaded[pname] = t
end

package.drop = function(pname)
	assert(not package.fundamental[pname], "Can't drop a fundamental package!")
	
	package.loaded[pname] = nil -- ditch it.
	syslog:warning("Deliberately dropping package %s!", pname)
end

_G.require = package.require
_G.package = package