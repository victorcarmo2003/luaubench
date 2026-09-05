--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "StarterGui". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type StarterGui = Runtime.Instance & {
	["ResetPlayerGuiOnSpawn"]: unknown,
	["ScreenOrientation"]: unknown,
	["ShowDevelopmentGui"]: unknown,
	["GetCoreGuiEnabled"]: (self: StarterGui, coreGuiType: unknown) -> boolean,
	["SetCore"]: (self: StarterGui, parameterName: string, value: unknown) -> (),
	["SetCoreGuiEnabled"]: (self: StarterGui, coreGuiType: unknown, enabled: boolean) -> (),
	["GetCore"]: (self: StarterGui, parameterName: string) -> { [string]: unknown },
}

local Generated: Types.GeneratedClass = {
	ClassName = "StarterGui",
	Superclass = "BasePlayerGui",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["ResetPlayerGuiOnSpawn"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ScreenOrientation"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ShowDevelopmentGui"] = { Kind = "Property", Default = nil, ReadOnly = false },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetCoreGuiEnabled",
		"SetCore",
		"SetCoreGuiEnabled",
		"GetCore",
	},
}

table.freeze(Generated.Schema)

return Generated
