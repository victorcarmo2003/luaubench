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
		["AirDensity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["AirTurbulenceIntensity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["AllowThirdPartySales"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["AuthorityMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "AuthorityMode", ValueCategory = "Enum", ScriptVisible = false },
		["AvatarUnificationMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "AvatarUnificationMode", ValueCategory = "Enum", ScriptVisible = false },
		["ClientAnimatorThrottling"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "ClientAnimatorThrottlingMode", ValueCategory = "Enum", ScriptVisible = true },
		["CollisionGroups"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = false },
		["CurrentCamera"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Camera", ValueCategory = "Class", ScriptVisible = true },
		["DataModelPlaceVersion"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["DistributedGameTime"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "double", ValueCategory = "Primitive", ScriptVisible = true },
		["EnableSLIMAvatars"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["ExpandedTerrain"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["ExplicitAutoJoints"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["FallHeightEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["FallenPartsDestroyHeight"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["FilteringEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["FluidForces"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "FluidForces", ValueCategory = "Enum", ScriptVisible = false },
		["GlobalWind"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType", ScriptVisible = true },
		["Gravity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["IKControlConstraintSupport"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "IKControlConstraintSupport", ValueCategory = "Enum", ScriptVisible = false },
		["ImprovedAnimationConstraint"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["ImprovedPhysicsReplication"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["InsertPoint"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType", ScriptVisible = true },
		["InterpolationThrottling"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "InterpolationThrottlingMode", ValueCategory = "Enum", ScriptVisible = true },
		["LayeredClothingCacheOptimizations"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["LuauTypeCheckMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "LuauTypeCheckMode", ValueCategory = "Enum", ScriptVisible = false },
		["MeshPartHeadsAndAccessories"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "MeshPartHeadsAndAccessories", ValueCategory = "Enum", ScriptVisible = false },
		["MeshStreamingAndImprovedLods"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["ModelStreamingBehavior"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "ModelStreamingBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["NextGenerationReplication"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["NextGenerationReplicationAlias"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["PathfindingUseImprovedSearch"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "PathfindingUseImprovedSearch", ValueCategory = "Enum", ScriptVisible = false },
		["PhysicsSteppingMethod"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "PhysicsSteppingMethod", ValueCategory = "Enum", ScriptVisible = false },
		["PlayerCharacterDestroyBehavior"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "PlayerCharacterDestroyBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["PlayerScriptsUseInputActionSystem"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["PlayerScriptsUseInputActionSystemAlias"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["PredictiveStreamingMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "PredictiveStreamingMode", ValueCategory = "Enum", ScriptVisible = false },
		["PrimalPhysicsSolver"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "PrimalPhysicsSolver", ValueCategory = "Enum", ScriptVisible = false },
		["RejectCharacterDeletions"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RejectCharacterDeletions", ValueCategory = "Enum", ScriptVisible = false },
		["RenderingCacheOptimizations"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RenderingCacheOptimizationMode", ValueCategory = "Enum", ScriptVisible = false },
		["ReplicateInstanceDestroySetting"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "ReplicateInstanceDestroySetting", ValueCategory = "Enum", ScriptVisible = false },
		["Retargeting"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "AnimatorRetargetingMode", ValueCategory = "Enum", ScriptVisible = true },
		["SandboxedInstanceMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SandboxedInstanceMode", ValueCategory = "Enum", ScriptVisible = false },
		["SignalBehavior"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SignalBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["SignalBehavior2"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SignalBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["SignalBehaviorAlias"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SignalBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["StreamOutBehavior"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "StreamOutBehavior", ValueCategory = "Enum", ScriptVisible = false },
		["StreamingEnabled"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["StreamingEnabledAlias"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["StreamingIntegrityMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "StreamingIntegrityMode", ValueCategory = "Enum", ScriptVisible = false },
		["StreamingMinRadius"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["StreamingPauseMode"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "StreamingPauseMode", ValueCategory = "Enum", ScriptVisible = false },
		["StreamingTargetRadius"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["Terrain"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "Terrain", ValueCategory = "Class", ScriptVisible = true },
		["TerrainWeldsFixed"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["ThrottleLevel"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["TouchEventsUseCollisionGroups"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["TouchesUseCollisionGroups"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["UseFixedSimulation"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["UseFixedSimulationAlias"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["UseInputSink"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["UseNewLuauTypeSolver"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["ValidateEnabledProximityPrompt"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["WatermarkHash"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = false },
		["PersistentLoaded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
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
