--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "ServerScriptService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type ServerScriptService = Runtime.Instance & {
}

local Generated: Types.GeneratedClass = {
	ClassName = "ServerScriptService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	-- Entradas abaixo com `ScriptVisible = false` têm `Default = nil` de propósito: a
	-- propriedade REAL do Roblox tem um default (às vezes um valor concreto, ex.:
	-- `Technology = Enum.Technology.Voxel`), só que ele não é representável/semeável
	-- por este runtime, porque a propriedade é invisível a script (`instance.X`/`instance.X
	-- = v` de um script nunca a alcança -- só `Instance.SetPropertyRaw`/`GetPropertyRaw`,
	-- o caminho que a hidratação de `$properties` do Rojo usa). Não leia `Default = nil`
	-- aqui como "esta propriedade não tem default no Roblox real" -- ver
	-- tools/generate-services.luau, classifySchemaMember/computeDefault.
	Schema = {
		["LoadStringEnabled"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
	} :: Runtime.ClassSchema,
	MethodNames = {
	},
}

table.freeze(Generated.Schema)

return Generated
