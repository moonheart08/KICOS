local args = ...
local minitel = require("minitel")
local computer = require("computer")
local term = require("term")
local args = term.parseArgs(args)

if args[1][1] ~= "literal" then
    print("First argument must be a subcommand name.")
    return
end

if args[1][2] == "friends" then
    print("UPTIME: %s", computer.uptime())
    for k, ls in pairs(minitel.friends) do
        print("H %s LS %s", k, ls)
    end
end
