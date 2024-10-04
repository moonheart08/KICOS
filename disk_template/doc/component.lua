---@meta

---@alias CAddress string

local component = {}

---@return fun(): (CAddress, string)|nil
function component.list(pattern, fuzzy) end

---@param addr CAddress
---@return table
function component.proxy(addr) end

return component
