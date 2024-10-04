local args = ...
local minitel = require("minitel")
local computer = require("computer")
local term = require("term")
local args = term.parseArgs(args)

local addr = nil
local port = 1
local attempts = 5

local options = {}

do
    ---@type table<string, {[1]: string, [2]: boolean}>
    local knownOptions = {
        ["p"] = { "port", true },
        ["port"] = { "port", true },
        ["attempts"] = { "attempts", true },
        ["a"] = { "attempts", true },
    }

    local litIdx = 1

    local i = 1
    while i <= #args do
        if args[i][1] == "option" or args[i][1] == "shortOption" then
            local info = knownOptions[args[i][2]]
            if not info then
                print("Unknown option %s", args[i][2])
                return
            end

            if info[2] then
                if args[i + 1][1] ~= "literal" then
                    print("Expected an argument for %s", args[i][2])
                    return
                end
                options[info[1]] = args[i + 1][2]
                i = i + 1
            else
                options[info[1]] = true
            end
        else
            if litIdx == 1 then
                addr = args[i][2]
            else
                print("Unexpected literal argument %s", args[i][2])
                return
            end

            litIdx = litIdx + 1
        end

        i = i + 1
    end
end

if options["port"] then
    port = tonumber(options["port"])

    if not port then
        print("Given port was not a number.")
        return
    end
end

if options["attempts"] then
    attempts = tonumber(options["attempts"])

    if not attempts then
        print("Given attempts was not a number.")
        return
    end
end

if not addr then
    print("Must provide an address.")
    return
end


local lost = 0
local avg = 0
for i = 1, attempts do
    local start = computer.uptime()
    local r = minitel.rsend(addr, port, "PING", false)
    if r then
        local t = computer.uptime() - start
        print("PING %s (took %ss)", addr, t)
        avg = t + avg
    else
        print("Packet lost.")
        lost = lost + 1
    end
end

print("AVG %ss | Lost %s (%s%%)", avg / attempts, lost, lost / attempts)
