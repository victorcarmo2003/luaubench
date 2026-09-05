--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "GlobalDataStore". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type GlobalDataStore = Runtime.Instance & {
	["OnUpdate"]: (self: GlobalDataStore, key: string, callback: unknown) -> unknown,
	["BatchGetAsync"]: (self: GlobalDataStore, keys: unknown, options: unknown?) -> { [string]: unknown },
	["GetAsync"]: (self: GlobalDataStore, key: string, options: unknown?) -> ...unknown,
	["IncrementAsync"]: (self: GlobalDataStore, key: string, delta: number?, userIds: unknown?, options: unknown?) -> { [string]: unknown },
	["RemoveAsync"]: (self: GlobalDataStore, key: string) -> ...unknown,
	["SetAsync"]: (self: GlobalDataStore, key: string, value: unknown, userIds: unknown?, options: unknown?) -> { [string]: unknown },
	["UpdateAsync"]: (self: GlobalDataStore, key: string, transformFunction: unknown) -> ...unknown,
}

local Generated: Types.GeneratedClass = {
	ClassName = "GlobalDataStore",
	Superclass = "Instance",
	IsService = false,
	IsAbstract = true,
	Schema = {
	} :: Runtime.ClassSchema,
	MethodNames = {
		"OnUpdate",
		"BatchGetAsync",
		"GetAsync",
		"IncrementAsync",
		"RemoveAsync",
		"SetAsync",
		"UpdateAsync",
	},
}

table.freeze(Generated.Schema)

return Generated
