--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "DataStore". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type DataStore = Runtime.Instance & {
	["GetVersionAsync"]: (self: DataStore, key: string, version: string) -> ...unknown,
	["GetVersionAtTimeAsync"]: (self: DataStore, key: string, timestamp: number) -> ...unknown,
	["ListKeysAsync"]: (self: DataStore, prefix: string?, pageSize: number?, cursor: string?, excludeDeleted: boolean?) -> unknown,
	["ListVersionsAsync"]: (self: DataStore, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> unknown,
	["RemoveVersionAsync"]: (self: DataStore, key: string, version: string) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "DataStore",
	Superclass = "GlobalDataStore",
	IsService = false,
	IsAbstract = true,
	Schema = {
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetVersionAsync",
		"GetVersionAtTimeAsync",
		"ListKeysAsync",
		"ListVersionsAsync",
		"RemoveVersionAsync",
	},
}

table.freeze(Generated.Schema)

return Generated
