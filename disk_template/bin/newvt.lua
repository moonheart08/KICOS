local workers <const> = require("workers")
local graphics <const> = require("graphics")


local vtt <close> = graphics.VDisplay:newWithVT()

workers.current().env.stdinTarget = vtt:getPipeOutput()
workers.current().env.stdoutTarget = vtt:getPipeInput()

vtt:switchTo()

workers.runProgram("login").onDeath:await()
