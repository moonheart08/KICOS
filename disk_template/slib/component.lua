function component.byType(ty)
	for k,v in component.list(ty) do
		return k
	end
end

function component.proxyByType(ty)
	return component.proxy(component.byType(ty))
end
