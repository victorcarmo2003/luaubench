--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "WorldRoot". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type WorldRoot = Runtime.Instance & {
	["ArePartsTouchingOthers"]: (self: WorldRoot, partList: unknown, overlapIgnored: number?) -> boolean,
	["Blockcast"]: (self: WorldRoot, cframe: unknown, size: unknown, direction: unknown, params: unknown?) -> unknown,
	["BulkMoveTo"]: (self: WorldRoot, partList: unknown, cframeList: unknown, eventMode: unknown?) -> (),
	["CollisionGroupSetCollidable"]: (self: WorldRoot, name1: string, name2: string, collidable: boolean) -> (),
	["CollisionGroupsAreCollidable"]: (self: WorldRoot, name1: string, name2: string) -> boolean,
	["FindPartOnRay"]: (self: WorldRoot, ray: unknown, ignoreDescendantsInstance: unknown?, terrainCellsAreCubes: boolean?, ignoreWater: boolean?) -> ...unknown,
	["FindPartOnRayWithIgnoreList"]: (self: WorldRoot, ray: unknown, ignoreDescendantsTable: unknown, terrainCellsAreCubes: boolean?, ignoreWater: boolean?) -> ...unknown,
	["FindPartOnRayWithWhitelist"]: (self: WorldRoot, ray: unknown, whitelistDescendantsTable: unknown, ignoreWater: boolean?) -> ...unknown,
	["FindPartsInRegion3"]: (self: WorldRoot, region: unknown, ignoreDescendantsInstance: unknown?, maxParts: number?) -> unknown,
	["FindPartsInRegion3WithIgnoreList"]: (self: WorldRoot, region: unknown, ignoreDescendantsTable: unknown, maxParts: number?) -> unknown,
	["FindPartsInRegion3WithWhiteList"]: (self: WorldRoot, region: unknown, whitelistDescendantsTable: unknown, maxParts: number?) -> unknown,
	["GetMaxCollisionGroups"]: (self: WorldRoot) -> number,
	["GetPartBoundsInBox"]: (self: WorldRoot, cframe: unknown, size: unknown, overlapParams: unknown?) -> unknown,
	["GetPartBoundsInRadius"]: (self: WorldRoot, position: unknown, radius: number, overlapParams: unknown?) -> unknown,
	["GetPartsInPart"]: (self: WorldRoot, part: unknown, overlapParams: unknown?) -> unknown,
	["GetRegisteredCollisionGroups"]: (self: WorldRoot) -> { unknown },
	["IsCollisionGroupRegistered"]: (self: WorldRoot, name: string) -> boolean,
	["IsRegion3Empty"]: (self: WorldRoot, region: unknown, ignoreDescendentsInstance: unknown?) -> boolean,
	["IsRegion3EmptyWithIgnoreList"]: (self: WorldRoot, region: unknown, ignoreDescendentsTable: unknown) -> boolean,
	["Raycast"]: (self: WorldRoot, origin: unknown, direction: unknown, raycastParams: unknown?) -> unknown,
	["RegisterCollisionGroup"]: (self: WorldRoot, name: string) -> (),
	["RenameCollisionGroup"]: (self: WorldRoot, from: string, to: string) -> (),
	["Shapecast"]: (self: WorldRoot, part: unknown, direction: unknown, params: unknown?) -> unknown,
	["Spherecast"]: (self: WorldRoot, position: unknown, radius: number, direction: unknown, params: unknown?) -> unknown,
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
