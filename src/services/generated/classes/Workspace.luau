--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Tipo público de "Workspace". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
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
	["JoinToOutsiders"]: (self: Workspace, objects: unknown, jointType: ValueTypes.EnumItem) -> (),
	["PGSIsEnabled"]: (self: Workspace) -> boolean,
	["UnjoinFromOutsiders"]: (self: Workspace, objects: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Workspace",
	Superclass = "WorldRoot",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["AirDensity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
		["AirTurbulenceIntensity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
		["AllowThirdPartySales"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["ClientAnimatorThrottling"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "ClientAnimatorThrottlingMode", ValueCategory = "Enum" },
		["CurrentCamera"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Camera", ValueCategory = "Class" },
		["DistributedGameTime"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "double", ValueCategory = "Primitive" },
		["FallHeightEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive" },
		["FallenPartsDestroyHeight"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "float", ValueCategory = "Primitive" },
		["FilteringEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive" },
		["GlobalWind"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType" },
		["Gravity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
		["InsertPoint"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType" },
		["InterpolationThrottling"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "InterpolationThrottlingMode", ValueCategory = "Enum" },
		["Retargeting"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "AnimatorRetargetingMode", ValueCategory = "Enum" },
		["StreamingEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive" },
		["Terrain"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "Terrain", ValueCategory = "Class" },
		["PersistentLoaded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
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
