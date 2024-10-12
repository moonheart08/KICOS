-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- This is a port of Minitel, https://github.com/ShadowKatStudios/OC-Minitel/tree/master

local computer <const> = require("computer")
local event <const> = require("eventbus")
local workers <const> = require("workers")
local net <const> = {}
net.mtu = 8192
net.streamdelay = 10
net.minport = 32768
net.maxport = 65535
net.openports = {}
net.friends = {}

for k, v in pairs(computer.getDeviceInfo()) do
    if v.class == "network" then
        net.mtu = math.min(net.mtu, tonumber(v.capacity))
    end
end

function net.hostname()
    return os.getenv("HOSTNAME") or computer.address():sub(1, 8)
end

---@alias PacketID string

---Generates a random packet ID.
---@return PacketID
function net.genPacketID()
    local npID = ""
    for i = 1, 16 do
        npID = npID .. string.char(math.random(32, 126))
    end
    return npID
end

---Attempt to send a raw packet, unreliably.
---@param to string Target host.
---@param port integer Port to send on.
---@param data string Data to transmit, up to net.mtu
---@param npID PacketID|nil
function net.usend(to, port, data, npID)
    computer.pushSignal("net_send", 0, to, port, data, npID)
end

---Attempt to send a packet reliably.
---@param to string Target host.
---@param port integer Port to send on.
---@param data string Data to transmit, up to net.mtu
---@param block boolean|nil Whether or not to block on transmit. If true, then do not block.
---@return boolean | PacketID Returns boolean if blocking, or the ID of the packet if not.
function net.rsend(to, port, data, block)
    local pid, stime = net.genPacketID(), computer.uptime() + net.streamdelay
    computer.pushSignal("net_send", 1, to, port, data, pid)
    if block then return pid end
    repeat
        _, rpid = event.pull(math.min(stime - computer.uptime(), 0.5), "net_ack")
    until rpid == pid or computer.uptime() > stime
    if not rpid then return false end
    return true
end

--- Attempt to send a packet, or packets, reliably over the network.
--- Always blocks.
---@param to string Target host.
---@param port integer Port to send on.
---@param ldata string Data to transmit, of any size.
function net.send(to, port, ldata)
    local tdata, hsize = {}, 44 + #(os.getenv("HOSTNAME") or computer.address():sub(1, 8)) + #to
    while hsize + #ldata > net.mtu do
        tdata[#tdata + 1] = ldata:sub(1, net.mtu - hsize)
        ldata = ldata:sub(#tdata[#tdata] + 1)
    end
    tdata[#tdata + 1] = ldata
    for k, v in ipairs(tdata) do
        if not net.rsend(to, port, v) then return false end
    end
    return true
end

-- socket stuff, layer 5?

local function cwrite(self, data)
    if self.state == "open" then
        if not net.send(self.addr, self.port, data) then
            self:close()
            return false, "timed out"
        end
    end

    return false, "closed"
end

local function cread(self, length)
    length = length or "\n"
    local rdata = ""
    if type(length) == "number" then
        rdata = self.rbuffer:sub(1, length)
        self.rbuffer = self.rbuffer:sub(length + 1)
        return rdata
    elseif type(length) == "string" then
        if length:sub(1, 2) == "*a" then
            rdata = self.rbuffer
            self.rbuffer = ""
            return rdata
        elseif length:len() == 1 then
            local pre, post = self.rbuffer:match("(.-)" .. length .. "(.*)")
            if pre and post then
                self.rbuffer = post
                return pre
            end
            return nil
        end
    end
end

local function socket(addr, port, sclose)
    local conn = {}
    conn.addr, conn.port = addr, tonumber(port)
    conn.rbuffer = ""
    conn.write = cwrite
    conn.read = cread
    conn.state = "open"
    conn.sclose = sclose
    local function listener(_, f, p, d)
        if f == conn.addr and p == conn.port then
            if d == sclose then
                conn:close()
            else
                conn.rbuffer = conn.rbuffer .. d
            end
        end

        return true
    end
    local listener = event.listen("net_msg", listener)
    function conn.close(self)
        event.remove("net_msg", listener)
        conn.state = "closed"
        net.rsend(addr, port, sclose, true)
    end

    return conn
end

function net.open(to, port)
    if not net.rsend(to, port, "openstream") then return false, "no ack from host" end
    local st = computer.uptime() + net.streamdelay
    local est = false
    while true do
        _, from, rport, data = event.pull(net.streamdelay, "net_msg")
        if to == from and rport == port then
            if tonumber(data) then
                est = true
            end
            break
        end
        if st < computer.uptime() then
            return nil, "timed out"
        end
    end
    if not est then
        return nil, "refused"
    end
    data = tonumber(data)
    sclose = ""
    repeat
        _, from, nport, sclose = event.pull("net_msg")
    until from == to and nport == data
    return socket(to, data, sclose)
end

function net.listen(port)
    repeat
        _, from, rport, data = event.pull("net_msg")
    until rport == port and data == "openstream"
    local nport = math.random(net.minport, net.maxport)
    local sclose = net.genPacketID()
    net.rsend(from, rport, tostring(nport))
    net.rsend(from, nport, sclose)
    return socket(from, nport, sclose)
end

function net.flisten(port, listener)
    local function helper(_, from, rport, data)
        if rport == port and data == "openstream" then
            local nport = math.random(net.minport, net.maxport)
            local sclose = net.genPacketID()
            -- we WILL out-of-time if we rsend here otherwise!
            workers.runThread(function()
                net.rsend(from, rport, tostring(nport))
                net.rsend(from, nport, sclose)
                listener(socket(from, nport, sclose))
            end, "Packet handler")
        end

        return true
    end
    return event.listen("net_msg", helper)
end

return net
