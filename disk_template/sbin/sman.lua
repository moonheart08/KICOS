local workers <const> = require("workers")
local json <const> = require("json")
local fs <const> = require("filesystem")
local syslog <const> = require("syslog")
local ev <const> = require("eventbus")
local util <const> = require("util")
local Hook <const> = require("hooks").Hook

local servicesFolder = "/cfg/services/"

---@class ServiceDefinition
---@field file string
---@field version integer
---@field args any

---@class Service
---@field worker Worker
---@field start fun()
---@field stop fun()
---@field reload fun()

---@type table<string, Service>
local active = {}

local function loadServices()
    for _, v in pairs(active) do
        pcall(v.stop) -- Protect ourselves from the fate of timing out.
        v.worker:exit(util.exitReasons.killed)
    end

    active = {}

    for _, p in pairs(fs.list(servicesFolder)) do
        pcall(function()
            syslog:info("Starting %s", p)

            ---@type ServiceDefinition
            ---@diagnostic disable-next-line: assign-type-mismatch
            local data = json.deserialize(fs.readFile(servicesFolder .. p))
            assert(type(data) == "table", "Service definition must be a table!")
            assert(data.file, "Service definition must point to a file to run!")
            assert(data.version == 1, "Version must be 1!")

            local serviceCtx = workers.buildGlobalContext()
            local serviceDecl, err = loadfileExt(data.file, serviceCtx)

            assert(serviceDecl, err)

            workers.runThread(function()
                serviceDecl(data.args)
                active[p] = {
                    worker = workers.current(),
                    reload = serviceCtx.reload,
                    stop = serviceCtx.stop,
                    start = serviceCtx.start,
                }

                active[p].start()
            end, data.file:match("/([^/]+)$"))
        end)
    end
end

loadServices()
