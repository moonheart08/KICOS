local raw_loadfile = ...

_G._OSVERSION = "KICOS v0.0.0"


-- All files in slib are safe to load early, and go straight into the exec context.
-- However, vterm is special and loaded before the rest.

local ctx = {}

raw_loadfile("/slib/vterm.lua")(ctx)

local screen = component.list("screen", true)()
local gpu = screen and component.list("gpu", true)()

_G._logVTerm = ctx.VTerm:new(screen, gpu)
_G._logVTerm:clear()