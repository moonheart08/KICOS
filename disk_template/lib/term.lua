local term = {}

function term.parseArgs(argstr)
    ---@alias TermArg {[1]: ArgType, [2]: string}

    ---@alias ArgType
    ---|"shortOption"
    ---|"option"
    ---|"literal"

    ---@type TermArg[]
    local out = {}
    for v in argstr:gmatch("([^%s]+)") do
        if v:sub(1, 1) == "-" and #v == 2 then
            table.insert(out, { "shortOption", v:sub(2, 2) })
        elseif v:sub(1, 2) == "--" then
            table.insert(out, { "option", v:sub(2, -1) })
        else
            table.insert(out, { "literal", v })
        end
    end

    return out
end

return term
