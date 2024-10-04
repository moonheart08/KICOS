-- buh.
do
  local addr, invoke = computer.getBootAddress(), component.invoke

  -- Required. If this crashes, well, the OS would crash anyway. :heck:
  computer.setArchitecture("Lua 5.4")

  local function loadfile(file)
    if _G._kicosCtx and _G._kicosCtx.syslog and _G._kicosCtx.syslog.info then
      _G._kicosCtx.syslog:info("Early file load of {%s} (%s/%s B)", file, computer.freeMemory(), computer.totalMemory())
    end
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
