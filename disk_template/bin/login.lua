local workers <const> = require("workers")
local pipes <const> = require("pipes")
local env <const> = require("env")
local fs <const> = require("filesystem")

if fs.exists("/cfg/profile.lua") then
    loadfileExt("/cfg/profile.lua", _G)()
end

local shell = workers.runProgram(env.env().shell or "shell")
pipes.stdin():handover(shell)

shell.onDeath:await()
