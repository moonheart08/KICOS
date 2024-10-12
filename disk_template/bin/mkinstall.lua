local fs <const> = require("filesystem")
local workers <const> = require("workers")
local present <const> = require("present")
local computer <const> = require("computer")
local component <const> = require("component")

-- Boot device is where we get the install image from, we clone ourselves.
local bootDevice <const> = computer.getBootAddress()

print("== KICOS Installation Cloner ==")

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
    for obj in proxy.list("/") do
        print("Deleting /%s", obj)
        proxy.remove("/" .. obj)
    end
end

local source = 