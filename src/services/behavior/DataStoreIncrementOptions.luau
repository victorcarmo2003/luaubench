--!strict

--[[
	Behavior de `DataStoreIncrementOptions` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3", ANTES de mexer aqui.

	Espelha `./DataStoreSetOptions.luau` ao pé da letra (mesmos 2 métodos, mesma ausência de
	propriedade no schema gerado -- ver `generated/classes/DataStoreIncrementOptions.luau`), para
	uma classe DIFERENTE e INDEPENDENTE do dump (nenhuma herda da outra -- ambas herdam só de
	`Instance`). O código não é fatorado num módulo compartilhado de propósito: são ~15 linhas por
	classe, e cada uma tem seu PRÓPRIO `Types.Behavior`/`ClassDescriptor` -- introduzir um terceiro
	módulo só para isto teria custo de indireção maior que o da duplicação. Reutilizar a MESMA
	string literal `"_LuauBenchMetadata"` desta classe e de `DataStoreSetOptions.luau` é seguro: o
	estado privado é por INSTÂNCIA (nunca compartilhado entre instâncias de classes diferentes), e
	nenhuma instância é simultaneamente das duas classes.

	Consumido por `../GlobalDataStore.luau` (`extractMetadata`), passado como `options` em
	`IncrementAsync`.
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local Value = require("../datastore/Value")

local MetadataState = InstanceState.new("_LuauBenchMetadata") :: InstanceState.InstanceStateAccessor<{ [string]: unknown }>

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `DataStoreIncrementOptions:GetMetadata(): Dictionary`.
	GetMetadata = function(self: Runtime.Instance): { [string]: unknown }
		local metadata = MetadataState.Get(self)
		if metadata == nil then
			return {}
		end
		return Value.DeepCopy(metadata)
	end,

	-- Doc oficial: `DataStoreIncrementOptions:SetMetadata(metadata: Dictionary)` -- mesma
	-- aproximação de boa-fé de `DataStoreSetOptions.luau` para o argumento malformado.
	SetMetadata = function(self: Runtime.Instance, attributes: unknown): ()
		if type(attributes) ~= "table" then
			error(`invalid argument #1 to 'SetMetadata' (table expected, got {type(attributes)})`, 2)
		end
		MetadataState.Set(self, Value.DeepCopy(attributes :: { [string]: unknown }))
	end,
}

local DataStoreIncrementOptionsBehavior = {
	Methods = Methods,
}

return DataStoreIncrementOptionsBehavior
