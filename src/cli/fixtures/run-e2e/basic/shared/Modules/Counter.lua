-- Fixture end-to-end (task-cli-006): classe OOP clássica via setmetatable -- o padrão real usado
-- por ProfileStore/state managers do ecossistema Roblox (o caso de uso central do LuauBench,
-- CLAUDE.md).
local Counter = {}
Counter.__index = Counter

function Counter.new(initial)
	local self = setmetatable({}, Counter)
	self._value = initial
	return self
end

function Counter:Add(amount)
	self._value += amount
end

function Counter:Get()
	return self._value
end

return Counter
