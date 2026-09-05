--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "OrderedDataStore". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type OrderedDataStore = Runtime.Instance & {
	["GetSortedAsync"]: (self: OrderedDataStore, ascending: boolean, pagesize: number, minValue: unknown, maxValue: unknown) -> unknown,
}

local Generated: Types.GeneratedClass = {
	ClassName = "OrderedDataStore",
	Superclass = "GlobalDataStore",
	IsService = false,
	IsAbstract = true,
	Schema = {
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetSortedAsync",
	},
}

table.freeze(Generated.Schema)

return Generated
