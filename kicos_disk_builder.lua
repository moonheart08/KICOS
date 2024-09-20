local ctx = ...
local fs = ctx.fs
local grabFile = ctx.grabFile
local component = ctx.component

-- Locate target disk..
local osDisk = fs.fstab["/"].address or fs.fstab["/"].fs.address

local target = nil

-- We're looking for a floppy drive.
for addr, t in component.list("filesystem", true) do
	local proxy = component.proxy(addr)
	-- You.. can't otherwise check if it's a floppy besides this route. 
	-- Very silly and will break if a server makes floppies bigger.
	if proxy.spaceTotal() == 524228 then
		target = proxy
		break
	end
end