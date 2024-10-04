local minitel = require("minitel")

local port = tonumber(...)

assert(port, "Need a port!")

s = minitel.listen(port)

while s.state == "open" do
    local v = s:read("*a")
    if v ~= "" and v ~= nil then
        io.write(v)
    end

    coroutine.yieldToOS()
end
