function table.searchKey(t, pattern, plain)
	for k, v in pairs(t) do
		if k:find(pattern, 1, plain) then
			return k, v
		end
	end
	
	return nil, nil
end

function table.asSet(tab)
	local set = {}

	for _, v in pairs(tab) do
		set[v] = true
	end

	return set
end

function table.setAsList(set)
	local list = {}

	for k, _ in pairs(set) do
		table.insert(list, k)
	end

	return list
end

-- Swaps the keys and values of a table.
function table.invert(tab)
	local new = {}
	
	for k in pairs(tab) do
		new[tab[k]] = k
	end
	
	return new
end