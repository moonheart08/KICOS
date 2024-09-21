-- buh.
do
  local addr, invoke = computer.getBootAddress(), component.invoke
  
  local function loadfile(file)
    local handle = assert(invoke(addr, "open", file))
    local buffer = ""
    repeat
      local data = invoke(addr, "read", handle, math.maxinteger or math.huge)
      buffer = buffer .. (data or "")
    until not data
    invoke(addr, "close", handle)
    local res, err = load(buffer, "=" .. file, "bt", _G)
	if err ~= nil then
		error(err)
	end
	return res
  end
  
  loadfile("/sbin/boot.lua")(loadfile)
end
