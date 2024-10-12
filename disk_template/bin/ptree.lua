local workers <const> = require("workers")

local depthPadding <const> = "  "


---comment
---@param worker Worker
---@param depth integer
function recurse_children(worker, depth)
    print("%s%s - %s (%s)", string.rep(depthPadding, depth), worker.id, worker.name, worker:status())
    for _, v in pairs(worker.children) do
        if not (v.dead and #v.children == 0) then
            recurse_children(v, depth + 1)
        end
    end
end

local root = workers.worker_list["1"]

recurse_children(root, 0)
