-- Bind the globals locally.
local component = component
local VTerm = {
	background = 0x000000,
	foreground = 0xFFBF00,
	scrollPos = 1,
	scrollback = {},
	maxScrollback = 64, -- A small number by default for systems with little RAM.
	physicalScrollPos = 1,
}

local vtermId = 0

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
	
	vtermId = vtermId + 1
	
	screen.turnOn() -- Ensure the display is, y'know, actually on.
	
	local w, h = gpu.maxResolution()
	o._width = w
	o._height = h
	
	o._screen = screen
	o._gpu = gpu
	o:clear()

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
		
		return false
	end
	if self._gpu.getScreen() == self._screen.address then
		return true -- Already set up.
	end
	
	return self:_prepForDrawInner()
end

function VTerm:_prepForDrawInner()
	self._gpu.setResolution(self._width, self._height)
	self._gpu.setBackground(self.background)
	self._gpu.setForeground(self.foreground)
	self._gpu.fill(1, self._height, self._width, self._height, " ")
	self._gpu.set(1,self._height,"VTERM "..tostring(vtermId))
	return true
end

function VTerm:clear()
	self:_prepForDraw()
	
	self._gpu.fill(1, 1, self._width, self._height, " ")
	self._gpu.set(1,self._height,"VTERM "..tostring(vtermId))
end

function VTerm:printText(text)
	for text in text:gmatch("([^\n]+)") do 
		table.insert(self.scrollback, text)
		if (#self.scrollback) > self.maxScrollback then
			table.remove(self.scrollback, 1) -- Drop the tail.
		end

		repeat 
			local toPrint = text:sub(1, self._width)
			self:_printTextInner(toPrint)
			text = text:sub(self._width, math.maxinteger or math.huge)
		until text == ""
	end
end

-- Doesn't properly handle very long lines.
function VTerm:_printTextInner(text)
	if not self:_prepForDraw() then
		return -- No GPU then no work.
	end

	self._gpu.set(1, self.physicalScrollPos, text)
	if self._height - 1 == self.physicalScrollPos then
		gpu.copy(1, 2, self.width, self._height - 2, 0, -1)
		gpu.fill(1, self._height - 1, self.width, 1, " ")
	else
		self.physicalScrollPos = self.physicalScrollPos + 1
	end
end

return VTerm