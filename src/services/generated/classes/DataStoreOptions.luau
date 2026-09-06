--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "DataStoreOptions". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type DataStoreOptions = Runtime.Instance & {
	["AllScopes"]: boolean,
	["SetExperimentalFeatures"]: (self: DataStoreOptions, experimentalFeatures: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "DataStoreOptions",
	Superclass = "Instance",
	IsService = false,
	IsAbstract = false,
	Schema = {
		["AllScopes"] = { Kind = "Property", Default = false, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"SetExperimentalFeatures",
	},
}

table.freeze(Generated.Schema)

return Generated
