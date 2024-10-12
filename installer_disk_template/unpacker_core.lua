local io = require("io")
local tar = require("tar")
local present = require("present")
local component = require("component")
local computer = require("computer")
local pack = io.open("disk.tar", "rb")
assert(pack, "No package file found. Please make sure you downloaded disk.tar")

local old_print = print
local function print(...)
    old_print(string.format(...))
end

local reader = tar.Reader:new(function(amnt)
    return pack:read(amnt)
end)


local target

do
    local targets = {}

    for target, _ in component.list("filesystem") do
        if target ~= computer.getBootAddress() and target ~= computer.tmpAddress() then
            table.insert(targets, target)
        end
    end

    print("Select a target drive:")
    target = present.select(targets)
end

local proxy = component.proxy(target)

print("Should this drive be WIPED? (y/n)")
if present.yesNo() then
    for _, obj in pairs(proxy.list("/")) do
        print("Deleting /%s", obj)
        proxy.remove("/" .. obj)
    end
end


for file in reader do
    ---@type TarFileEntry
    local file = file

    if file.data == "" and (file.type == "unsupported" or file.type == "directory") then
        print("Making directory %s", file.filename)
        proxy.makeDirectory(file.filename)
    else
        local h = proxy.open("/" .. file.filename, "wb")
        print("Writing %s (%sB)", file.filename, file.data:len())
        assert(h, "Could not write " .. file.filename)
        proxy.write(h, file.data)
        proxy.close(h)
    end
end
