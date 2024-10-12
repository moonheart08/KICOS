local io <const> = require("io")

local requiredLibs <const> = {
    { "installer_disk_template/env_shim.lua",      "env" },
    { "disk_template/slib/string.lua",             nil },
    { "disk_template/lib/tar.lua",                 "tar" },
    { "disk_template/lib/util.lua",                "util" },
    { "disk_template/lib/json.lua",                "json" },
    { "disk_template/lib/serialization.lua",       "serialization" },
    { "disk_template/lib/present.lua",             "present" },
    -- Must be last.
    { "installer_disk_template/unpacker_core.lua", nil },
}



local source = [[
-- AUTO GENERATED DO NOT MODIFY
-- Re-run build_unpacker.lua to change this script.
-- This script "just" unpacks the given tar file to a given disk.
-- Yes, this script tampers with require() which is bad for OpenOS.
-- The assumption is you plan to replace OpenOS and will not continue using it shortly after running this.
]]

for _, v in ipairs(requiredLibs) do
    local text
    do
        local file = io.open(v[1], "rb")
        assert(file)
        text = file:read("a")
        file:close()
    end

    if v[2] then
        local fnname = "__GEN_" .. v[2]
        source = source
            .. "\n-- " .. v[1] .. "\n"
            .. "local function " .. fnname .. "()\n"
            .. text
            .. "\nend\n" .. v[2] .. " = " .. fnname .. "()\n"
            .. "package.loaded[" .. string.format("%q", v[2]) .. "] = " .. v[2] .. "\n"
    else
        source = source .. string.format("\ndo --%s\n", v[1]) .. text .. "\nend\n"
    end
end

do
    local target = io.open("installer_disk_template/unpacker.lua", "wb")
    assert(target)
    target:write(source)
end
