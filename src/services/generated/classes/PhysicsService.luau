--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "PhysicsService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type PhysicsService = Runtime.Instance & {
	["CollisionGroupContainsPart"]: (self: PhysicsService, name: string, part: unknown) -> boolean,
	["CollisionGroupSetCollidable"]: (self: PhysicsService, name1: string, name2: string, collidable: boolean) -> (),
	["CollisionGroupsAreCollidable"]: (self: PhysicsService, name1: string, name2: string) -> boolean,
	["CreateCollisionGroup"]: (self: PhysicsService, name: string) -> number,
	["GetCollisionGroupId"]: (self: PhysicsService, name: string) -> number,
	["GetCollisionGroupName"]: (self: PhysicsService, name: number) -> string,
	["GetCollisionGroups"]: (self: PhysicsService) -> { unknown },
	["GetMaxCollisionGroups"]: (self: PhysicsService) -> number,
	["GetRegisteredCollisionGroups"]: (self: PhysicsService) -> { unknown },
	["IsCollisionGroupRegistered"]: (self: PhysicsService, name: string) -> boolean,
	["RegisterCollisionGroup"]: (self: PhysicsService, name: string) -> (),
	["RemoveCollisionGroup"]: (self: PhysicsService, name: string) -> (),
	["RenameCollisionGroup"]: (self: PhysicsService, from: string, to: string) -> (),
	["SetPartCollisionGroup"]: (self: PhysicsService, part: unknown, name: string) -> (),
	["UnregisterCollisionGroup"]: (self: PhysicsService, name: string) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "PhysicsService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
	} :: Runtime.ClassSchema,
	MethodNames = {
		"CollisionGroupContainsPart",
		"CollisionGroupSetCollidable",
		"CollisionGroupsAreCollidable",
		"CreateCollisionGroup",
		"GetCollisionGroupId",
		"GetCollisionGroupName",
		"GetCollisionGroups",
		"GetMaxCollisionGroups",
		"GetRegisteredCollisionGroups",
		"IsCollisionGroupRegistered",
		"RegisterCollisionGroup",
		"RemoveCollisionGroup",
		"RenameCollisionGroup",
		"SetPartCollisionGroup",
		"UnregisterCollisionGroup",
	},
}

table.freeze(Generated.Schema)

return Generated
