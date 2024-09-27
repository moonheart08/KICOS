local syslog = require("syslog")
local eventbus = require("eventbus")
local component = require("component")
syslog:info("Setting up filesystem driver/etc.")
local filesystem = {}
local path = {}
local Overlay = {}
local VFSNode = {}
local handle = {}
filesystem.path = path
filesystem.Overlay = overlay

function Overlay:new(fs, physPath)
	local o = {
		readonly = false,
		label = fs,
	}
	
	setmetatable(o, self)
	self.__index = self
	
	syslog:info("Mounting %s at %s", fs, physPath)
	o.proxy = component.proxy(fs)
	o.physPath = physPath
	
	return o
end

-- Mount our root.
local root = Overlay:new(computer.getBootAddress(), "/")

-- A directory within the VFS, with an optional overlay to use at that level.
function VFSNode:new(name, overlay)
	local o = {
		name = name,
		overlay = overlay,
		children = {},
		parent = nil
	}
	
	setmetatable(o, self)
	self.__index = self
	syslog:trace("Made new VFS node %s", name)
	return o
end


function VFSNode.getDeepestOverlayAt(root, path)
	assert(not filesystem.path.isRelative(path), path)
	local base = "/"
	local curr = root
	local deepestBase = base
	local deepestOverlay = root.overlay

	for segment in filesystem.path.segments(path) do
		if curr.children[segment] == nil then
			return deepestOverlay, deepestBase
		end
		
		curr = curr.children[segment]
		base = base .. segment .. "/"
		if curr.overlay ~= nil then
			deepestBase = base
			deepestOverlay = curr.overlay
		end
	end
	
	return deepestOverlay, deepestBase
end

-- Gets the node at a given path, creating nodes if necessary.
function VFSNode.getNodeAt(root, path, create)
	assert(not filesystem.path.isRelative(path))
	local base = "/"
	local curr = root
	
	for segment in filesystem.path.segments(path) do
		if curr.children[segment] == nil then
			if create then
				curr.children[segment] = VFSNode:new(segment, nil)
				curr.children[segment].parent = root
			else
				return nil
			end
		end
		
		curr = curr.children[segment]
		base = base .. segment .. "/"
	end
	
	return curr, base
end

function path.isRelative(path)
	return string.sub(path, 1, 1) ~= "/"
end

function path.segments(path)
	local curPos = 1
	
	return function() 
		local s, e, cap = string.find(path, "/([^/]+)", curPos)
		
		if s == nil then
			return nil
		end
		curPos = e
		return cap
	end
end

filesystem._root = VFSNode:new("ROOT", root) 

function filesystem.mount(fs, path)
	local node = VFSNode.getNodeAt(filesystem._root, path, true)
	if node == nil then
		return false
	end
	
	node.overlay = Overlay:new(fs, path)
	
	return true
end

function filesystem.unmount(path)
	syslog:info("Unmounting %s", path)
	local node = VFSNode.getNodeAt(filesystem._root, path, true)
	if node == nil then
		return false
	end
	
	if node.overlay == nil then
		return false
	end
	
	node.overlay = nil
	
	return true
end

function filesystem.getRelativeBase(path)
	local overlay, base = VFSNode.getDeepestOverlayAt(filesystem._root, path)
	
	local baseLen = string.len(base)
	return overlay, string.sub(path, baseLen)
end

function filesystem.open(path, mode)
	local overlay, relative = filesystem.getRelativeBase(path)
	return handle:new(overlay, relative, mode)
end

function filesystem.exists(path)
	local overlay, relative = filesystem.getRelativeBase(path)
	
	return overlay.proxy.exists(relative)
end

function filesystem.isDirectory(path)
	local overlay, relative = filesystem.getRelativeBase(path)
	
	return overlay.proxy.isDirectory(relative)
end

function filesystem.isFile(path)
	local overlay, relative = filesystem.getRelativeBase(path)
	
	return not overlay.proxy.isDirectory(relative)
end

function filesystem.makeDirectory(path)
	local overlay, relative = filesystem.getRelativeBase(path)
	
	return overlay.proxy.makeDirectory(relative)
end

function filesystem.ensureDirectory(path)
	local overlay, relative = filesystem.getRelativeBase(path)
	
	if filesystem.exists(path) then
		return filesystem.isDirectory(path) 
	else 
		return filesystem.makeDirectory(path)
	end
end

function filesystem.readFile(path)
	local h = filesystem.open(path, "r")
	local data = h:readAll()
	h:close()
	
	return data
end

function handle:new(overlay, path, mode)
	local o = {
		overlay = overlay,
		path = path,
		_handle = overlay.proxy.open(path, mode),
	}
	setmetatable(o, self)
	self.__index = self
	syslog:trace("Opened handle to %s (%s)", path, overlay.proxy.address)
	return o
end

function handle:read(amount)
	local buffer = ""
	repeat
		local data = self.overlay.proxy.read(self._handle, amount - string.len(buffer))
		buffer = buffer .. (data or "")
		coroutine.yieldToOS()
	until not data or (string.len(buffer) == amount)
	
	return buffer
end

function handle:readAll()
	return self:read(math.maxinteger or math.huge)
end

function handle:close()
	self.overlay.proxy.close(self._handle)
	syslog:trace("Closed handle to %s (%s)", self.path, self.overlay.proxy.address)
end

if computer.tmpAddress() then
	filesystem.mount(computer.tmpAddress(), "/tmp")
end

local function loadfile(file)
	local h = filesystem.open(file, "r")
	local data = h:readAll()
	h:close()
	return load(data, "=VFS" .. file, "bt", _G)
end

local function loadfileExt(file, global)
	local h = filesystem.open(file, "r")
	local data = h:readAll()
	h:close()
	return load(data, "=VFS" .. file, "bt", global or _G)
end

_G.loadfile = loadfile
_G.loadfileExt = loadfileExt

table.insert(package.locators, function(pname)
	local path = "/lib/" .. pname .. ".lua"
	if filesystem.exists(path) and filesystem.isFile(path) then
		return {filesystem.readFile(path), path}
	end
	
	return nil
end)

return filesystem