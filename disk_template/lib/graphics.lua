local syslog = require("syslog")
local workers = require("workers")
local component = require("component")
local pipes = require("pipes")

local graphics = {}

---@type GPU[]
graphics._managedCards = {}
---@type VDisplay[]
graphics._vdisplays = {}

---@param address CAddress
---@return GPU
function graphics.getGPU(address)
    return graphics._managedCards[address]
end

---@alias ColorDepth
---|1
---|2
---|4
---

-- Read straight out of OC with getPaletteColor.
local DefaultPalette = {
    0x0F0F0F,
    0x1E1E1E,
    0x2D2D2D,
    0x3C3C3C,
    0x4B4B4B,
    0x5A5A5A,
    0x696969, -- nice
    0x787878,
    0x878787,
    0x969696,
    0xA5A5A5,
    0xB4B4B4,
    0xC3C3C3,
    0xD2D2D2,
    0xE1E1E1,
    0xF0F0F0
}

local colorDepthLookup = {
    -- why in the world can OC's API *ever* return this as a string??
    OneBit = 1,
    TwoBit = 2,
    FourBit = 4,
}

---@class GPU
---@field address CAddress Address of the GPU device.
---@field _currentBuffer integer Currently active buffer for this device.
---@field colorDepth integer color depth of the output.
---@field bufferMemory integer total amount of buffer memory in this GPU.
---@field displayBuffer Buffer? The display/screen buffer for drawing to.
---@field _buffers Buffer[]
---@field _proxy table Internally managed component proxy.
---@field width integer
---@field height integer
local GPU = {}

---@param address CAddress
---@return GPU
function GPU:new(address)
    ---@type GPU
    local o = {
        address = address,
        _currentBuffer = 0,
        colorDepth = 1,
        bufferMemory = 0,
        displayBuffer = nil,
        _buffers = {},
        _proxy = component.proxy(address),
        width = 0,
        height = 0,
    }
    setmetatable(o, self)
    self.__index = self

    syslog:debug("Created managed GPU device for %s", address)

    return o
end

function GPU:reset(display, clearDisplay)
    if clearDisplay == nil then
        clearDisplay = true
    end

    self._proxy.freeAllBuffers()
    do
        local res, err = self._proxy.bind(display, clearDisplay)

        if not res then
            syslog:error("Failed to bind display to GPU. %s to %s", self.address, display)
            return res, err -- We failed :(
        end
    end

    self.colorDepth = self._proxy.maxDepth()
    self.bufferMemory = self._proxy.totalMemory()
    local w, h = self._proxy.maxResolution()
    self.width = w
    self.height = h
    self.displayBuffer = graphics.Buffer:new(self, 0)
    self:setResolution(self.width, self.height)
    self:setColorDepth(self.colorDepth)
end

---@param w integer|nil
---@param h integer|nil
---@param workerIndependent boolean|nil
function GPU:createBuffer(w, h, workerIndependent)
    workerIndependent = workerIndependent or false

    local bidx = self._proxy.allocateBuffer(w, h)
    self._buffers[bidx] = graphics.Buffer:new(self, bidx)

    if not workerIndependent then
        local curr = workers.current()
        curr.onDeath:attach(function(res, ...)
            if self._buffers[bidx] then
                self._buffers[bidx]:destroy()
            end
            return res
        end)
    end
end

---@param depth ColorDepth
function GPU:setColorDepth(depth)
    self._proxy.setDepth(depth)
end

function GPU:setResolution(width, height)
    if self._proxy.setResolution(width, height) then
        self.width = width
        self.height = height
        return true
    end

    return false
end

---Sets the GPU's palette.
---@param palette integer[]
function GPU:setPaletteTable(palette)
    assert(#palette == 16)

    for i = 1, 16 do
        -- yes, this is zero indexed.
        self._proxy.setPaletteColor(i - 1, palette[i])
    end
end

function GPU:getPaletteTable(palette)

end

---A display buffer, i.e. the screen or any one of the backing buffers.
---@class Buffer
---@field idx integer Buffer index
---@field gpu GPU Buffer owning GPU
---@field _proxy table GPU component proxy
---@field _dead boolean Whether or not the buffer has been destroyed.
---@field width integer
---@field height integer
local Buffer = {}

function Buffer:new(gpu, idx)
    local width, height = gpu._proxy.getBufferSize(idx)
    ---@type Buffer
    local o = {
        gpu = gpu,
        idx = idx,
        _proxy = gpu._proxy,
        width = width,
        height = height,
        _dead = false,
    }
    setmetatable(o, self)
    self.__index = self

    return o
end

function Buffer:_ensureActive()
    if self.gpu._currentBuffer == self.idx then
        return
    end

    self._proxy.setActiveBuffer(self.idx)
    self.gpu._currentBuffer = self.idx
end

function Buffer:setBackground(color, isPalette)
    self:_ensureActive()
    isPalette = isPalette or false

    return self._proxy.setBackground(color, isPalette)
end

function Buffer:setForeground(color, isPalette)
    self:_ensureActive()
    isPalette = isPalette or false

    return self._proxy.setForeground(color, isPalette)
end

function Buffer:setLine(x, y, value, vertical)
    self:_ensureActive()

    return self._proxy.set(x, y, value, vertical)
end

function Buffer:copy(x, y, w, h, tx, ty)
    self:_ensureActive()

    return self._proxy.copy(x, y, w, h, tx, ty)
end

function Buffer:fill(x, y, w, h, c)
    self:_ensureActive()

    return self._proxy.fill(x, y, w, h, c)
end

function Buffer:destroy()
    if self.idx == 0 then
        return -- can't destroy the display.
    end

    self._dead = true
    self._proxy.freeBuffer(self.idx)
end

function Buffer:__close()
    self:destroy()
end

---@class VT100
---@field gpu GPU GPU this VT100 is attached to.
---@field screen CAddress Screen this VT100 is attached to.
---@field width integer
---@field height integer
---@field inPipe Pipe Pipe for inputting text to this VT100.
---@field outPipe Pipe Pipe for sending out keyboard inputs received by this VT100.
---@field scrollbackHeight integer Height of the scrollback.
---@field _shadowDisplay string[] Backing buffer used to track what the VT looks like if it needs redrawn.
---@field _shadowColorCommands _ColorCommand[][] Companion to _shadowDisplay containing color data.
---@field _cursorX integer Horizontal position of the cursor, relative to the view.
---@field _cursorY integer Vertical position of the cursor, relative to the view.
---@field _scrollPos integer Horizontal scroll location
---@field _drawCursor boolean Whether or not to draw the cursor.
---@field statline string Statline for this terminal.
---@field _inputWorker Worker
---@field _drawState boolean Whether or not this VT100 is the active drawer.
---@field _mode integer VT100 parser mode.
local VT100 = {}

---@param gpu GPU
---@param screen CAddress
---@return VT100
function VT100:new(gpu, screen)
    ---@type VT100
    local o = {
        gpu = gpu,
        screen = screen,
        width = gpu.width,
        height = gpu.height - 1,
        scrollbackHeight = 128,
        statline = "STATLINE",
        inPipe = pipes.Pipe:new(),
        outPipe = pipes.Pipe:new(),
        _shadowDisplay = {},
        _shadowColorCommands = {},
        _scrollPos = 128 - gpu.height,
        _cursorX = 1,
        _cursorY = 1,
        _drawCursor = true,
        ---@diagnostic disable-next-line: assign-type-mismatch
        _inputWorker = nil,
        _drawState = false,
        _mode = 0,
    }
    setmetatable(o, self)
    self.__index = self

    o:_rebuildShadow()
    o._inputWorker = workers.runThread(self._workerThread, "VT100 worker", o)

    return o
end

---@class _ColorCommand
---@field foreground integer
---@field background integer
---@field hLoc integer Horizontal location of the command.

function VT100:_rebuildShadow()
    assert(self.scrollbackHeight >= self.height)

    for i = 1, self.scrollbackHeight do
        self:_setEmptyShadowLine(i)
    end
end

function VT100:_setEmptyShadowLine(i)
    self._shadowDisplay[i] = string.rep(" ", self.width)
    self._shadowColorCommands[i] = { { foreground = 0xFFFFFF, background = 0x000000, hLoc = 1 } }
end

---Fully redraws the VT100 emulator, from scratch.
function VT100:redraw()
    local display = self.gpu.displayBuffer

    if not display then
        return -- Can't draw if we're not up front.
    end

    for i = self._scrollPos, (math.min(self.scrollbackHeight, self._scrollPos + self.height)) do
        self:_redrawLine(i - self._scrollPos, i)
    end



    display:setLine(1, self.height + 1, self.statline)
end

function VT100:_redrawLine(visualPos, scrollPos)
    local line = self._shadowDisplay[scrollPos]
    local colorData = self._shadowColorCommands[scrollPos]

    local display = self.gpu.displayBuffer

    if not display then
        return
    end

    local lastPos = 1

    for i = 1, #colorData do
        display:setForeground(colorData[i].foreground)
        display:setBackground(colorData[i].background)

        local len = self.width - lastPos + 1

        if colorData[i + 1] then
            len = colorData[i + 1].hLoc - lastPos + 1
        end

        local toDraw = line:sub(lastPos, len)

        display:setLine(lastPos, visualPos, toDraw)
    end
end

function VT100:processInput(c)
    for i = 1, c:len() do
        local b = c:sub(i, i)

        if self._mode == 0 then
            if b == "\n" then
                self:_newline(true)
            elseif b == "\b" then
                self._cursorX = math.max(self._cursorX - 1, 1)
                self:_setChar(self._cursorX, self._cursorY, " ")
            else
                self:_setChar(self._cursorX, self._cursorY, b)
                self:_cursorRight(true)
            end
        end
    end
end

---@param x integer View relative X,
---@param y integer View relative Y
---@param c string Character to set.
function VT100:_setChar(x, y, c)
    local shadowLineBase = self.scrollbackHeight - self.height
    local l = self._shadowDisplay[shadowLineBase + y - 1]
    l = l:sub(1, x - 1) .. c .. l:sub(x + 1, -1)
    self._shadowDisplay[shadowLineBase + y - 1] = l

    local display = self.gpu.displayBuffer

    if display then
        display:setLine(x, y, c)
    end
end

function VT100:_cursorRight(newlineOnWrap)
    self._cursorX = self._cursorX + 1

    if self._cursorX > self.width then
        self._cursorX = 1
        if newlineOnWrap then
            self:_newline(true)
        end
    end
end

function VT100:_newline(resetCursor)
    if resetCursor then
        self._cursorX = 1
    end

    if self._cursorY ~= self.height then
        self._cursorY = self._cursorY + 1
    else
        local display = self.gpu.displayBuffer

        if display then
            display:copy(1, 2, self.width, self.height - 1, 0, -1)
            display:fill(1, self.height, self.width, 1, " ")
        end

        table.remove(self._shadowDisplay, 1)
        table.remove(self._shadowColorCommands, 1)
        self:_setEmptyShadowLine(self.scrollbackHeight)
    end
end

function VT100:_workerThread()
    while true do
        local chunk = self.inPipe:read(1024)
        if not chunk then
            return
        end

        if chunk ~= "" then
            self:processInput(chunk)
        end
    end
end

function VT100:setDrawState(s)
    self._drawState = s
end

---Virtual display, backed by either a VT100 or Buffer.
---@class VDisplay
---@field _backing VT100|Buffer VT100 or Buffer backing. One must be present.
---@field _id integer
---@field palette integer[] The palette to use when drawing this vdisplay.
local VDisplay = {}
local vDisplayIDs = 1

function VDisplay:newWithVT(gpu, screen)
    ---@type VDisplay
    local o = {
        _backing = VT100:new(gpu or graphics.primaryGPU, screen or graphics.primaryScreen),
        _id = vDisplayIDs,
        palette = graphics.DefaultPalette
    }

    vDisplayIDs = vDisplayIDs + 1
    setmetatable(o, self)
    self.__index = self

    table.insert(graphics._vdisplays, o)
    o._backing.statline = string.format("VDisplay %s", o._id)
    return o
end

function VDisplay:newFromBuffer(buffer)
    ---@type VDisplay
    local o = {
        _backing = buffer,
        _id = vDisplayIDs,
        palette = graphics.DefaultPalette
    }

    vDisplayIDs = vDisplayIDs + 1
    setmetatable(o, self)
    self.__index = self

    table.insert(graphics._vdisplays)
    return o
end

---@return Pipe?
function VDisplay:getPipeInput()
    if self._backing.inPipe then
        return self._backing.inPipe
    end

    return nil
end

local activeVDisplay = nil

function VDisplay:switchTo()
    if activeVDisplay then
        self._backing:setDrawState(false)
    end
    activeVDisplay = self
    self._backing:setDrawState(true)
    self._backing:redraw() -- Ensure we're up front now!
end

function graphics.switchToVDisplay(id)
    if graphics._vdisplays[id] then
        graphics._vdisplays[id]:switchTo()
    end
end

graphics.GPU = GPU
graphics.Buffer = Buffer
graphics.VT100 = VT100
graphics.VDisplay = VDisplay
graphics.DefaultPalette = DefaultPalette

return graphics
