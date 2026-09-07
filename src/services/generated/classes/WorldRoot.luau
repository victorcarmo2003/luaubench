--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Tipo público de "WorldRoot". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type WorldRoot = Runtime.Instance & {
	["ArePartsTouchingOthers"]: (self: WorldRoot, partList: unknown, overlapIgnored: number?) -> boolean,
	["Blockcast"]: (self: WorldRoot, cframe: ValueTypes.CFrame, size: ValueTypes.Vector3, direction: ValueTypes.Vector3, params: unknown?) -> unknown,
	["BulkMoveTo"]: (self: WorldRoot, partList: unknown, cframeList: unknown, eventMode: ValueTypes.EnumItem?) -> (),
	["CollisionGroupSetCollidable"]: (self: WorldRoot, name1: string, name2: string, collidable: boolean) -> (),
	["CollisionGroupsAreCollidable"]: (self: WorldRoot, name1: string, name2: string) -> boolean,
	["FindPartOnRay"]: (self: WorldRoot, ray: unknown, ignoreDescendantsInstance: unknown?, terrainCellsAreCubes: boolean?, ignoreWater: boolean?) -> ...unknown,
	["FindPartOnRayWithIgnoreList"]: (self: WorldRoot, ray: unknown, ignoreDescendantsTable: unknown, terrainCellsAreCubes: boolean?, ignoreWater: boolean?) -> ...unknown,
	["FindPartOnRayWithWhitelist"]: (self: WorldRoot, ray: unknown, whitelistDescendantsTable: unknown, ignoreWater: boolean?) -> ...unknown,
	["FindPartsInRegion3"]: (self: WorldRoot, region: unknown, ignoreDescendantsInstance: unknown?, maxParts: number?) -> unknown,
	["FindPartsInRegion3WithIgnoreList"]: (self: WorldRoot, region: unknown, ignoreDescendantsTable: unknown, maxParts: number?) -> unknown,
	["FindPartsInRegion3WithWhiteList"]: (self: WorldRoot, region: unknown, whitelistDescendantsTable: unknown, maxParts: number?) -> unknown,
	["GetMaxCollisionGroups"]: (self: WorldRoot) -> number,
	["GetPartBoundsInBox"]: (self: WorldRoot, cframe: ValueTypes.CFrame, size: ValueTypes.Vector3, overlapParams: unknown?) -> unknown,
	["GetPartBoundsInRadius"]: (self: WorldRoot, position: ValueTypes.Vector3, radius: number, overlapParams: unknown?) -> unknown,
	["GetPartsInPart"]: (self: WorldRoot, part: unknown, overlapParams: unknown?) -> unknown,
	["GetRegisteredCollisionGroups"]: (self: WorldRoot) -> { unknown },
	["IsCollisionGroupRegistered"]: (self: WorldRoot, name: string) -> boolean,
	["IsRegion3Empty"]: (self: WorldRoot, region: unknown, ignoreDescendentsInstance: unknown?) -> boolean,
	["IsRegion3EmptyWithIgnoreList"]: (self: WorldRoot, region: unknown, ignoreDescendentsTable: unknown) -> boolean,
	["Raycast"]: (self: WorldRoot, origin: ValueTypes.Vector3, direction: ValueTypes.Vector3, raycastParams: unknown?) -> unknown,
	["RegisterCollisionGroup"]: (self: WorldRoot, name: string) -> (),
	["RenameCollisionGroup"]: (self: WorldRoot, from: string, to: string) -> (),
	["Shapecast"]: (self: WorldRoot, part: unknown, direction: ValueTypes.Vector3, params: unknown?) -> unknown,
	["Spherecast"]: (self: WorldRoot, position: ValueTypes.Vector3, radius: number, direction: ValueTypes.Vector3, params: unknown?) -> unknown,
	["UnregisterCollisionGroup"]: (self: WorldRoot, name: string) -> (),
	["findPartOnRay"]: (self: WorldRoot, ray: unknown, ignoreDescendantsInstance: unknown?, terrainCellsAreCubes: boolean?, ignoreWater: boolean?) -> ...unknown,
	["findPartsInRegion3"]: (self: WorldRoot, region: unknown, ignoreDescendantsInstance: unknown?, maxParts: number?) -> unknown,
}

local Generated: Types.GeneratedClass = {
	ClassName = "WorldRoot",
	Superclass = "Model",
	IsService = false,
	IsAbstract = true,
	Schema = {
		["AutoSimulate"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["CollisionGroupData"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "BinaryString", ValueCategory = "DataType", ScriptVisible = false },
		["GravityDirection"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType", ScriptVisible = false },
		["PhysicsStepTime"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = false },
		["SimulationRate"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = false },
		["Wind"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = false },
		["WindDirection"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType", ScriptVisible = false },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"ArePartsTouchingOthers",
		"Blockcast",
		"BulkMoveTo",
		"CollisionGroupSetCollidable",
		"CollisionGroupsAreCollidable",
		"FindPartOnRay",
		"FindPartOnRayWithIgnoreList",
		"FindPartOnRayWithWhitelist",
		"FindPartsInRegion3",
		"FindPartsInRegion3WithIgnoreList",
		"FindPartsInRegion3WithWhiteList",
		"GetMaxCollisionGroups",
		"GetPartBoundsInBox",
		"GetPartBoundsInRadius",
		"GetPartsInPart",
		"GetRegisteredCollisionGroups",
		"IsCollisionGroupRegistered",
		"IsRegion3Empty",
		"IsRegion3EmptyWithIgnoreList",
		"Raycast",
		"RegisterCollisionGroup",
		"RenameCollisionGroup",
		"Shapecast",
		"Spherecast",
		"UnregisterCollisionGroup",
		"findPartOnRay",
		"findPartsInRegion3",
	},
}

table.freeze(Generated.Schema)

return Generated
