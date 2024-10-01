-- Legacy VTerm API. Used during early boot, will be replaced later on with a more capable API.
-- Not a target for new features.
-- Bind the globals locally.
local component = component
local VTerm = {}

local vtermId = 1

function VTerm:new(screen, gpu)
	local o = {
		background = 0x000000,
		foreground = 0xFFBF00,
		scrollPos = 0,
		scrollback = {""},
		maxScrollback = 64, -- A small number by default for systems with little RAM.
		physicalScrollPos = 1,
		horzScrollPos = 1,
		viewMode = 1, -- 1: Text 2: DirectDraw
	}
	setmetatable(o, self)
	self.__index = self
	
	if type(screen) == 'string' then
		screen = component.proxy(screen)
	end
	
	if type(gpu) == 'string' then
		gpu = component.proxy(gpu)
	end
	
	o.vtermId = vtermId
	vtermId = vtermId + 1
	
	screen.turnOn() -- Ensure the display is, y'know, actually on.
	
	if gpu ~= nil then
		local w, h = gpu.maxResolution()
		o._width = w
		o._height = h
	end
	
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
	self._gpu.set(1,self._height,"VTERM "..tostring(self.vtermId))
	return true
end

function VTerm:clear()
	self:_prepForDraw()
	
	self._gpu.fill(1, 1, self._width, self._height, " ")
	self._gpu.set(1,self._height,"VTERM "..tostring(self.vtermId))
end

function VTerm:unbind()
	self._gpu = nil
	self._screen = nil
end

function VTerm:isTextMode()
	return self.viewMode == 1
end

function VTerm:printText(text)
	if not self:isTextMode() then
		return
	end
	
	if text == "\b" then
		-- Backspace.
		self:_backspace()
		return
	end
	
	local t = {}
	
	for v in text:gmatch("([^\n]+)") do
		table.insert(t, v)
	end

	for k, text in ipairs(t) do 
		self.scrollback[#self.scrollback] = self.scrollback[#self.scrollback] .. text
		table.insert(self.scrollback, "")

		if (#self.scrollback) > self.maxScrollback then
			table.remove(self.scrollback, 1) -- Drop the tail.
		else
			self.scrollPos = self.scrollPos + 1
		end

		repeat 
			local amnt = (self._width - self.horzScrollPos) + 1
			local toPrint = text:sub(1, amnt)
			self:_printTextInner(toPrint)
			text = text:sub(amnt, math.maxinteger or math.huge)
			if text ~= "" then
				self:_scrollDown()
			end
		until text == ""
		
		if k < #t then
			self:_scrollDown()
		end
	end
	
	if string.sub(text, -1) ~= "\n" then
		table.remove(self.scrollback, #self.scrollback) --Remove end.
	else
		self:_scrollDown()
	end
end

function VTerm:redraw()
	self.physicalScrollPos = 0
	self:clear() -- Reset everything.
	-- And draw our scrollback, starting from scrollPos
	local endPos = self.scrollPos
	local currPos = math.min(1, endPos - self._height)
	
	while currPos ~= (endPos + 1) do
		local text = self.scrollback[currPos]
		if text ~= nil then
			repeat 
				local amnt = (self._width - self.horzScrollPos) + 1
				local toPrint = text:sub(1, amnt)
				self:_printTextInner(toPrint)
				text = text:sub(amnt, math.maxinteger or math.huge)
				if text ~= "" then
					self:_scrollDown()
				end
			until text == ""
		end
		currPos = currPos + 1
	end
	
	_kicosCtx.syslog:debug("Fully redrew VTerm %s.", self.vtermId)
end

-- Doesn't properly handle very long lines.
function VTerm:_printTextInner(text)
	if not self:_prepForDraw() then
		return -- No GPU then no work.
	end

	self._gpu.set(self.horzScrollPos, self.physicalScrollPos, text)
	self.horzScrollPos = self.horzScrollPos + string.len(text)
end

function VTerm:_backspace()
	self.horzScrollPos = math.max(1, self.horzScrollPos - 1)
	self._gpu.set(self.horzScrollPos, self.physicalScrollPos, " ")
end

function VTerm:_scrollDown()
	if self._height - 1 == self.physicalScrollPos then
		self._gpu.copy(1, 2, self._width, self._height - 2, 0, -1)
		self._gpu.fill(1, self._height - 1, self._width, 1, " ")
	else
		self.physicalScrollPos = self.physicalScrollPos + 1
	end
	
	self.horzScrollPos = 1
end

return VTerm