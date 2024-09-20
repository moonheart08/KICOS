local ctx = ...
local fs = ctx.fs
local grabFile = ctx.grabFile

-- Locate target disk..
local osDisk = fs.fstab["/"].address or fs.fstab["/"].fs.address

-- We're looking for a floppy drive.
