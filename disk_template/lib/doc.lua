local fs = require("filesystem")
local syslog = require("syslog")

local doc = {}

-- Check if the magical file that enables documenting everything is present.
doc.enabled = fs.exists("/DEVENV_FLAG")

doc._functions = {}
setmetatable(doc._functions, {__mode = "k"})

doc.syslogWriter = function(...)
	syslog:info(...)
end

function doc.describe(f, desc, tab)
	if not doc.enabled then
		return
	end
	tab = tab or {}
	tab.desc = desc
	-- NOTE: Yea this just doesn't work in OC due to how they sandbox it. Unfortunate.
	tab.name = debug.getinfo(f, "n").name
	doc._functions[f] = tab
end

function doc.explain(f, writer)
	writer = writer or print or doc.syslogWriter
	
	if not doc.enabled then
		writer("Documentation is disabled; not a development machine.")
	end
	
	local docData = doc._functions[f]
	
	if docData == nil then
		writer("No documentation attached, can't explain this function.")
		return
	end
	
	writer("# %s", docData.name or f)
	
	writer("  %s", docData.desc)
	
	if docData.args then
		writer("# Arguments")
		for k, v in pairs(docData.args) do
			writer("  %s (%s): %s", v[1], v[2], v[3]) 
		end
	end
	
	if docData.returns then
		writer("# Returns")
		writer("  " .. docData.returns)
	end

	if docData.throws then
		writer("# Exceptions")
		writer("  " .. docData.throws)
	end
end

doc.describe(doc.describe, "Attaches a documentation description to the given function.", {
	args = {{"f", "function", "Function to document."}, {"desc", "string", "Description for the function."}, {"tab", "table?", "Table containing documentation data."}}
})

doc.describe(doc.explain, "Prints a human readable description of the given function.", {
	args = {{"f", "function", "Function to explain."}, {"writer", "function(...)?", "A syslog-style writer function to print the explanation to."}}
})


return doc