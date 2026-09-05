-- Fixture end-to-end (task-cli-006): Script sob ServerScriptService -- roda de verdade. Requer um
-- ModuleScript de ReplicatedStorage que usa setmetatable/OOP (o caso de uso central do
-- LuauBench: ProfileStore, state managers e companhia dependem exatamente disto). Cobre
-- print -> stdout e warn -> stderr no mesmo run.
local Counter = require(game.ReplicatedStorage.Modules.Counter)

local counter = Counter.new(10)
counter:Add(5)

print("count is " .. tostring(counter:Get()))
warn("cache miss for demo-key")
