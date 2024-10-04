-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- This is a port of Minitel, https://github.com/ShadowKatStudios/OC-Minitel/tree/master

--[[
packet format:
packetID: random string to differentiate
packetType:
 - 0: unreliable
 - 1: reliable, requires ack
 - 2: ack packet
destination: end destination hostname
sender: original sender of packet
data: the actual packet data, duh.
]] --

local args = ...

args:call() -- Tell driver manager to move along.

local listeners = {}
local packetPushers = {}

local cfg = {}

local event = require("eventbus")
local component = require("component")
local computer = require("computer")
local serial = require("json")
local workers = require("workers")
local minitel = require("minitel")
local syslog = require("syslog")

local hostname = computer.address():sub(1, 8)
local modems = {}

cfg.debug = false
cfg.port = 4096
cfg.retry = 10
cfg.retrycount = 3
cfg.route = true
-- How often we politely tell the rest of the network HI I EXIST
cfg.advertiseInterval = 60
-- Port 1 is where we scream into the void.
cfg.advertisePort = 1

--[[
LKR format:
address {
 local hardware address
 remote hardware address
 time last received
}
]] --
cfg.sroutes = {}
local rcache = setmetatable({}, { __index = cfg.sroutes })
cfg.rctime = 15

--[[
packet queue format:
{
 packetID,
 packetType
 destination,
 data,
 timestamp,
 attempts
}
]] --
local pqueue = {}

-- packet cache: [packet ID]=uptime
local pcache = {}
cfg.pctime = 30

local function dprint(...)
    --- ...
end

local function saveconfig()
    local f = io.open("/cfg/minitel.cfg", "wb")
    if f then
        f:write(serial.serialize(cfg))
        f:close()
    end
end

local function loadconfig()
    local f = io.open("/cfg/minitel.cfg", "rb")
    if f then
        local newcfg = serial.deserialize(f:read(math.maxinteger))
        f:close()
        for k, v in pairs(newcfg) do
            cfg[k] = v
        end
    else
        saveconfig()
    end
end

function start()
    loadconfig()
    local f = io.open("/cfg/hostname", "rb")
    if f then
        hostname = f:read()
        f:close()
    end
    syslog:info("Hostname: " .. hostname)

    if next(listeners) ~= nil then return end

    modems = {}
    for a, t in component.list("modem") do
        modems[#modems + 1] = component.proxy(a)
    end
    for k, v in ipairs(modems) do
        v.open(cfg.port)
        syslog:info("Opened port " .. cfg.port .. " on " .. v.address)
    end
    for a, t in component.list("tunnel") do
        modems[#modems + 1] = component.proxy(a)
    end

    local function genPacketID()
        local npID = ""
        for i = 1, 16 do
            npID = npID .. string.char(math.random(32, 126))
        end
        return npID
    end

    local function sendPacket(packetID, packetType, dest, sender, vPort, data, repeatingFrom)
        if rcache[dest] then
            dprint("Cached", rcache[dest][1], "send", rcache[dest][2], cfg.port, packetID, packetType, dest, sender,
                vPort, data)
            if component.type(rcache[dest][1]) == "modem" then
                component.invoke(rcache[dest][1], "send", rcache[dest][2], cfg.port, packetID, packetType, dest, sender,
                    vPort, data)
            elseif component.type(rcache[dest][1]) == "tunnel" then
                component.invoke(rcache[dest][1], "send", packetID, packetType, dest, sender, vPort, data)
            end
        else
            dprint("Not cached", cfg.port, packetID, packetType, dest, sender, vPort, data)
            for k, v in pairs(modems) do
                -- do not send message back to the wired or linked modem it came from
                -- the check for tunnels is for short circuiting `v.isWireless()`, which does not exist for tunnels
                if v.address ~= repeatingFrom or (v.type ~= "tunnel" and v.isWireless()) then
                    if v.type == "modem" then
                        v.broadcast(cfg.port, packetID, packetType, dest, sender, vPort, data)
                    elseif v.type == "tunnel" then
                        v.send(packetID, packetType, dest, sender, vPort, data)
                    end
                end
            end
        end
    end

    local function pruneCache()
        for k, v in pairs(rcache) do
            dprint(k, v[3], computer.uptime())
            if v[3] < computer.uptime() then
                rcache[k] = nil
                dprint("pruned " .. k .. " from routing cache")
            end
        end
        for k, v in pairs(pcache) do
            if v < computer.uptime() then
                pcache[k] = nil
                dprint("pruned " .. k .. " from packet cache")
            end
        end
    end

    local function checkPCache(packetID)
        dprint(packetID)
        for k, v in pairs(pcache) do
            dprint(k)
            if k == packetID then return true end
        end
        return false
    end

    local function processPacket(_, localModem, from, pport, _, packetID, packetType, dest, sender, vPort, data)
        pruneCache()
        if pport == cfg.port or pport == 0 then -- for linked cards
            syslog:debug("%s, %s, %s, %s", cfg.port, vPort, packetType, dest)
            if checkPCache(packetID) then return true end
            minitel.friends[sender] = computer.uptime()
            if dest == hostname then
                if packetType == 1 then
                    sendPacket(genPacketID(), 2, sender, hostname, vPort, packetID)
                end
                if packetType == 2 then
                    dprint("Dropping " .. data .. " from queue")
                    pqueue[data] = nil
                    computer.pushSignal("net_ack", data)
                end
                if packetType ~= 2 then
                    computer.pushSignal("net_msg", sender, vPort, data)
                end
            elseif dest:sub(1, 1) == "~" then -- broadcasts start with ~
                computer.pushSignal("net_broadcast", sender, vPort, data)
            elseif cfg.route then             -- repeat packets if route is enabled
                sendPacket(packetID, packetType, dest, sender, vPort, data, localModem)
            end
            if not rcache[sender] then -- add the sender to the rcache
                dprint("rcache: " .. sender .. ":", localModem, from, computer.uptime())
                rcache[sender] = { localModem, from, computer.uptime() + cfg.rctime }
            end
            if not pcache[packetID] then -- add the packet ID to the pcache
                pcache[packetID] = computer.uptime() + cfg.pctime
            end
        end

        return true
    end

    listeners["modem_message"] = processPacket
    event.listen("modem_message", processPacket)
    syslog:info("Started packet listening event handler: " .. tostring(processPacket))

    local function queuePacket(_, ptype, to, vPort, data, npID)
        npID = npID or genPacketID()
        if to == hostname or to == "localhost" then
            computer.pushSignal("net_msg", to, vPort, data)
            computer.pushSignal("net_ack", npID)
            return
        end
        pqueue[npID] = { ptype, to, vPort, data, 0, 0 }
        dprint(npID, table.unpack(pqueue[npID]))
        return true
    end

    listeners["net_send"] = queuePacket
    event.listen("net_send", queuePacket)
    syslog:info("Started packet queueing event handler: " .. tostring(queuePacket))

    local function packetPusher()
        while true do
            for k, v in pairs(pqueue) do
                if v[5] < computer.uptime() then
                    dprint(k, v[1], v[2], hostname, v[3], v[4])
                    sendPacket(k, v[1], v[2], hostname, v[3], v[4])
                    if v[1] ~= 1 or v[6] == cfg.retrycount then
                        pqueue[k] = nil
                    else
                        pqueue[k][5] = computer.uptime() + cfg.retry
                        pqueue[k][6] = pqueue[k][6] + 1
                    end
                end
            end
            coroutine.yieldToOS()
        end
    end

    packetPushers[#packetPushers + 1] = workers.runThread(packetPusher,
        string.format("Packet pusher %s", #packetPushers + 1))
    syslog:info("Started packet pusher: " .. tostring(packetPushers[#packetPushers]))

    listeners["net_ack"] = dprint
    event.listen("net_ack", dprint)
end

function set(k, v)
    if type(cfg[k]) == "string" then
        cfg[k] = v
    elseif type(cfg[k]) == "number" then
        cfg[k] = tonumber(v)
    elseif type(cfg[k]) == "boolean" then
        if v:lower():sub(1, 1) == "t" then
            cfg[k] = true
        else
            cfg[k] = false
        end
    end
    print("cfg." .. k .. " = " .. tostring(cfg[k]))
    saveconfig()
end

function set_route(to, laddr, raddr)
    cfg.sroutes[to] = { laddr, raddr, 0 }
    saveconfig()
end

function del_route(to)
    cfg.sroutes[to] = nil
    saveconfig()
end

start()

while true do
    minitel.usend("~", cfg.advertisePort, "ADVERTISEMENT")
    computer.sleep(cfg.advertiseInterval)
end
