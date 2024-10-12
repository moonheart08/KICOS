local minitel <const> = require("minitel")
local ev <const> = require("eventbus")
local workers <const> = require("workers")
local pipes <const> = require("pipes")
local syslog <const> = require("syslog")
local args = ...

local listener
function start()
    listener = minitel.flisten(2, function(socket)
        syslog:info("Telnet connection from %s", socket.addr)
        workers.runThread(tnetWorker, string.format("Telnet worker %s", socket.addr), socket).onDeath:await()
    end)

    while true do coroutine.yieldToOS() end
end

function tnetWorker(socket)
    local stdin = pipes.Pipe:new()
    local stdout = pipes.Pipe:new(0)

    local stdoutBuffer = ""

    stdout.onTryWrite:attach(function(res, data, nb)
        stdoutBuffer = stdoutBuffer .. data

        return true
    end)

    workers.current().env.stdinTarget = stdin
    workers.current().env.stdoutTarget = stdout
    workers.current().env.echo = false

    local w = workers.runProgram(args)

    while true do
        if w.dead then
            socket:close()
        end
        if socket.state == "closed" then
            if not w.dead then
                w:exit("killed")
            end
            return
        end

        if stdoutBuffer ~= "" then
            local b = stdoutBuffer
            stdoutBuffer = ""

            socket:write(b)
        end

        read = socket:read(1)
        if (read ~= nil) and (#read > 0) then
            stdin:write(read)
        else
            coroutine.yieldToOS()
        end
    end
end

function stop()
    if listener then
        ev.remove("net_msg", listener)
    end
end
