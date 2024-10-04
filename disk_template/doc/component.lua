---@meta

---@alias CAddress string
---@alias DeviceType
---|"gpu" Graphics adapter
---|"screen" Screen.
---|"computer" External computer (or, the external view of itself)
---|"filesystem" Managed filesystem
---|"relay" Network relay
---|"eeprom" 4KiB EEPROM used within the computer for booting.
---|"modem" Network adapter
---|"ocelot" Emulator-only debug tool.
---|"internet" Real-world internet adapter
---|"data" Data card (provides DEFLATE, encryption utils, etc.)
---|"redstone" Redstone adapter.
---|"sound" Sound card.
---|"disk_drive" External floppy disk drive.
---|"hologram" Hologram projector.
---|"tape_drive" Tape player/reader.

component = {}

---@return fun(): (CAddress, DeviceType)|nil
function component.list(pattern, fuzzy) end

---@param addr CAddress
---@return table
function component.proxy(addr) end

---@param device CAddress
---@param method string
---@param ... any
---@return any
function component.invoke(device, method, ...) end

---@param device CAddress
---@return DeviceType
function component.type(device) end

---@param device CAddress
---@return integer
function component.slot(device) end
