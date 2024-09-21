local ctx = ...

-- Bind the globals locally.
local component = component
local VTerm = {
	["background"] = 0x000000,
	["foreground"] = 0xFFBF00
}
ctx.VTerm = VTerm

function VTerm:new(screen, gpu)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	
	if type(screen) == 'string' then
		screen = component.proxy(screen)
	end
	
	if type(gpu) == 'string' then
		gpu = component.proxy(gpu)
	end
	
	screen.turnOn() -- Ensure the display is, y'know, actually on.
	
	local w, h = gpu.maxResolution()
	o._width = w
	o._height = h
	
	o._screen = screen
	o._gpu = gpu
	return o
end

-- Returns whether or not the VTerm will block on write 
function VTerm:willBlock()
	return true -- Don't yet support not blocking.
end

-- Prep the GPU for drawing to our display, from scratch.
function VTerm:_prepForDraw()
	-- No GPU, no draw. 
	if self._gpu == nil then
		return
	end
	if self._gpu.getScreen() == self._screen.address then
		return -- Already set up.
	end
	
	self:_prepForDrawInner()
end

function VTerm:_prepForDrawInner()
	self._gpu.setResolution(self._width, self._height)
	self._gpu.setBackground(self.background)
	self._gpu.setForeground(self.foreground)
end

function VTerm:clear()
	self:_prepForDraw()
	
	self._gpu.fill(1, 1, self._width, self._height, "A")
end