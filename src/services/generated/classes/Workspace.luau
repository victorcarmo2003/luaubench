--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "Workspace". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type Workspace = Runtime.Instance & {
	["AirDensity"]: unknown,
	["AirTurbulenceIntensity"]: unknown,
	["AllowThirdPartySales"]: unknown,
	["ClientAnimatorThrottling"]: unknown,
	["CurrentCamera"]: unknown,
	["DistributedGameTime"]: unknown,
	["FallHeightEnabled"]: unknown,
	["FallenPartsDestroyHeight"]: unknown,
	["FilteringEnabled"]: unknown,
	["GlobalWind"]: unknown,
	["Gravity"]: unknown,
	["InsertPoint"]: unknown,
	["InterpolationThrottling"]: unknown,
	["Retargeting"]: unknown,
	["StreamingEnabled"]: unknown,
	["Terrain"]: unknown,
	["PersistentLoaded"]: Runtime.Signal<unknown>,
	["GetNumAwakeParts"]: (self: Workspace) -> number,
	["GetPhysicsThrottling"]: (self: Workspace) -> number,
	["GetRealPhysicsFPS"]: (self: Workspace) -> number,
	["GetServerTimeNow"]: (self: Workspace) -> number,
	["JoinToOutsiders"]: (self: Workspace, objects: unknown, jointType: unknown) -> (),
	["PGSIsEnabled"]: (self: Workspace) -> boolean,
	["UnjoinFromOutsiders"]: (self: Workspace, objects: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Workspace",
	Superclass = "WorldRoot",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["AirDensity"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["AirTurbulenceIntensity"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["AllowThirdPartySales"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ClientAnimatorThrottling"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["CurrentCamera"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["DistributedGameTime"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["FallHeightEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["FallenPartsDestroyHeight"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["FilteringEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["GlobalWind"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["Gravity"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["InsertPoint"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["InterpolationThrottling"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["Retargeting"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["StreamingEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["Terrain"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["PersistentLoaded"] = { Kind = "Event", Default = nil, ReadOnly = true },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetNumAwakeParts",
		"GetPhysicsThrottling",
		"GetRealPhysicsFPS",
		"GetServerTimeNow",
		"JoinToOutsiders",
		"PGSIsEnabled",
		"UnjoinFromOutsiders",
	},
}

table.freeze(Generated.Schema)

return Generated
