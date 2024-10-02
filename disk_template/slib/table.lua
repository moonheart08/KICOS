function table.searchKey(t, pattern, plain)
	for k, v in pairs(t) do
		if k:find(pattern, 1, plain) then
			return k, v
		end
	end
	
	return nil, nil
end