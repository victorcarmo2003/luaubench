--!strict

--[[
	Behavior de `DataStoreSetOptions` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3", ANTES de mexer aqui.

	`GetMetadata`/`SetMetadata` são os ÚNICOS membros desta classe (`Schema = {}` no gerado -- ver
	`generated/classes/DataStoreSetOptions.luau`: nenhuma propriedade, só os 2 métodos) -- o
	metadata em si é estado privado por instância (L2.0.2), nunca uma propriedade do schema (a doc
	real também não expõe metadata por ponto, só via os 2 métodos). Consumido por
	`../GlobalDataStore.luau` (`extractMetadata`), passado como `options` em `SetAsync`.

	Instância desta classe nasce normalmente via `Instance.new("DataStoreSetOptions")`/
	`Services.new` (NÃO é `NotCreatable` no dump -- `IsAbstract = false`), então PODE chegar aqui
	sem `SetMetadata` nunca ter sido chamado -- `GetMetadata` devolve `{}` nesse caso (nunca `nil`,
	mesma disciplina de `Players.GetPlayers()`/`DataStoreKeyInfo.GetMetadata`).

	DEEP COPY na ESCRITA e na LEITURA -- mesma razão de `Value.luau`, cabeçalho, "DEEP COPY": sem
	isso, mutar a tabela original depois de `SetMetadata(t)` alteraria o estado guardado (alias
	silencioso), e mutar o retorno de `GetMetadata()` alteraria esse mesmo estado entre chamadas.
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local Value = require("../datastore/Value")

local MetadataState = InstanceState.new("_LuauBenchMetadata") :: InstanceState.InstanceStateAccessor<{ [string]: unknown }>

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `DataStoreSetOptions:GetMetadata(): Dictionary`.
	GetMetadata = function(self: Runtime.Instance): { [string]: unknown }
		local metadata = MetadataState.Get(self)
		if metadata == nil then
			return {}
		end
		return Value.DeepCopy(metadata)
	end,

	-- Doc oficial: `DataStoreSetOptions:SetMetadata(metadata: Dictionary)`. Aproximação de boa-fé
	-- (regra de idioma dos erros: TEM contraparte real -> família Roblox, forma de erro de
	-- argumento nativo, string exata NÃO CONFIRMADA) para o único caso de má-formação verificado
	-- aqui: `attributes` não é uma tabela.
	SetMetadata = function(self: Runtime.Instance, attributes: unknown): ()
		if type(attributes) ~= "table" then
			error(`invalid argument #1 to 'SetMetadata' (table expected, got {type(attributes)})`, 2)
		end
		MetadataState.Set(self, Value.DeepCopy(attributes :: { [string]: unknown }))
	end,
}

local DataStoreSetOptionsBehavior = {
	Methods = Methods,
}

return DataStoreSetOptionsBehavior
