local syslog <const> = require("syslog")
local component <const> = require("component")

syslog:info("Setting up filesystem core.")
local filesystem <const> = {}
local path <const> = {}
local Overlay <const> = {}
local VFSNode <const> = {}
local handle <const> = {}
filesystem.path = path
filesystem.Overlay = Overlay

function Overlay:new(fs, physPath)
	---@class Overlay
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
	---@class VFSNode
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
			return deepestOverlay, deepestBase, curr
		end

		curr = curr.children[segment]
		base = base .. segment .. "/"
		if curr.overlay ~= nil then
			deepestBase = base
			deepestOverlay = curr.overlay
		end
	end

	return deepestOverlay, deepestBase, curr
end

--- Gets the node at a given path, creating nodes if necessary.
---@return VFSNode, string
---@return nil
function VFSNode.getNodeAt(root, path, create)
	local base

	if filesystem.path.isRelative(path) then
		base = ""
	else
		base = "/"
	end

	local curr = root

	for segment in filesystem.path.segments(path) do
		if curr.children[segment] == nil then
			if create then
				curr.children[segment] = VFSNode:new(segment, nil)
				curr.children[segment].parent = root
			else
				---@diagnostic disable-next-line: return-type-mismatch
				return nil, nil
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
		local s, e, cap = string.find(path, "([^/]+)", curPos)

		if s == nil then
			return nil
		end
		curPos = e + 2
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
	local overlay, base, curr = VFSNode.getDeepestOverlayAt(filesystem._root, path)

	local baseLen = string.len(base)
	return overlay, string.sub(path, baseLen), curr
end

function filesystem.open(path, mode)
	local overlay, relative = filesystem.getRelativeBase(path)
	if overlay.proxy.exists(relative) then
		return handle:new(overlay, relative, mode)
	end

	return nil
end

function filesystem.exists(path)
	local overlay, relative = filesystem.getRelativeBase(path)

	return overlay.proxy.exists(relative)
end

function filesystem.list(path)
	local overlay, relative, currNode = filesystem.getRelativeBase(path)

	local half = overlay.proxy.list(relative) or {}
	half = table.asSet(half)
	local node, base = VFSNode.getNodeAt(filesystem._root, path, false)
	if node then
		for k, _ in pairs(node.children) do
			half[k .. "/"] = true
		end
	end

	return table.setAsList(half)
end

function filesystem.isDirectory(path)
	local overlay, relative, currNode = filesystem.getRelativeBase(path)

	if overlay.proxy.isDirectory(relative) then
		return true
	else
		local node, base = VFSNode.getNodeAt(currNode, relative, false)
		if not node then
			return false
		else
			return node.children[relative:sub(base:len())] ~= nil
		end
	end
end

function filesystem.isFile(path)
	return not filesystem.isDirectory(path)
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
	if not h then
		return nil
	end
	local data = h:readAll()
	h:close()

	return data
end

function filesystem.invalidateCache(path)
	-- Currently does nothing.
	return true
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
	amount = amount or math.maxinteger
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

local function loadfileExt(file, global)
	if string.sub(file, 1, 1) ~= "/" then
		-- We need to find it.

		local newFile = nil

		local env = require("env").env()

		for _, v in pairs(env.path) do
			if filesystem.exists(string.format(v, file)) then
				newFile = string.format(v, file)
				break
			elseif filesystem.exists(string.format(v, file .. ".lua")) then
				newFile = string.format(v, file .. ".lua")
				break
			end
		end

		if env.workingDirectory then
			if filesystem.exists(env.workingDirectory .. file) then
				newFile = env.workingDirectory .. file
			elseif filesystem.exists(env.workingDirectory .. file .. ".lua") then
				newfile = env.workingDirectory .. file .. ".lua"
			end
		end

		if not newFile then
			error("Could not locate " .. file .. " in the path when trying to load it.")
		end

		file = newFile
	end


	local h = filesystem.open(file, "r")

	if not h then
		return nil
	end

	local data = h:readAll()
	h:close()
	return load(data, "=VFS" .. file, "bt", global or _G)
end

local function loadfile(file)
	return loadfileExt(file, _G)
end


-- NOTE: This only works because filesystem.lua is loaded so early that package.require can't yet give it its own isolated environment.
-- NOTE: The OS *will* break into pieces trying to load a process if this ever changes without also fixing this code!
_G.loadfile = loadfile
_G.loadfileExt = loadfileExt

table.insert(package.locators, function(pname)
	local path = "/lib/" .. pname .. ".lua"
	if filesystem.exists(path) and filesystem.isFile(path) then
		return { filesystem.readFile(path), path }
	end

	return nil
end)

return filesystem
