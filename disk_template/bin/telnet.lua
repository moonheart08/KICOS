local minitel <const> = require("minitel")
local ev <const> = require("eventbus")
local workers <const> = require("workers")
local pipes <const> = require("pipes")

local args = ...
assert(type(args) == "string")


local socket = minitel.open(args, 2)

assert(socket, "Failed to connect!")

local t = workers.runThread(function()
    while true do
        local read = socket:read(1)

        if socket.state == "closed" then
            print("== Connection lost.")
            return
        end

        if read and #read > 0 then
            io.write(read)
        else
            coroutine.yieldToOS()
        end
    end
end, "Reader")

local writer = workers.runThread(function()
    while true do
        -- TODO: Support modes other than line mode, support echo on/off, etc.
        local data = io.read("L")

        if pipes.stdin().closed then
            return
        end

        socket:write(data)
    end
end, "Writer")

writer.onDeath:await()
if not t.dead then
    t:exit("killed")
end
