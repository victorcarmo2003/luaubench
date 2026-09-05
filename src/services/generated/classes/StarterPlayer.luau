--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "StarterPlayer". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type StarterPlayer = Runtime.Instance & {
	["AllowCustomAnimations"]: boolean,
	["AutoJumpEnabled"]: boolean,
	["CameraMaxZoomDistance"]: number,
	["CameraMinZoomDistance"]: number,
	["CameraMode"]: unknown,
	["CharacterBreakJointsOnDeath"]: boolean,
	["CharacterJumpHeight"]: number,
	["CharacterJumpPower"]: number,
	["CharacterMaxSlopeAngle"]: number,
	["CharacterUseJumpPower"]: boolean,
	["CharacterWalkSpeed"]: number,
	["ClassicDeath"]: boolean,
	["DevCameraOcclusionMode"]: unknown,
	["DevComputerCameraMovementMode"]: unknown,
	["DevComputerMovementMode"]: unknown,
	["DevTouchCameraMovementMode"]: unknown,
	["DevTouchMovementMode"]: unknown,
	["EnableMouseLockOption"]: boolean,
	["HealthDisplayDistance"]: number,
	["LoadCharacterAppearance"]: boolean,
	["LuaCharacterController"]: unknown,
	["NameDisplayDistance"]: number,
	["UserEmotesEnabled"]: boolean,
}

local Generated: Types.GeneratedClass = {
	ClassName = "StarterPlayer",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["AllowCustomAnimations"] = { Kind = "Property", Default = true, ReadOnly = true },
		["AutoJumpEnabled"] = { Kind = "Property", Default = true, ReadOnly = false },
		["CameraMaxZoomDistance"] = { Kind = "Property", Default = 400, ReadOnly = false },
		["CameraMinZoomDistance"] = { Kind = "Property", Default = 0.5, ReadOnly = false },
		["CameraMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["CharacterBreakJointsOnDeath"] = { Kind = "Property", Default = true, ReadOnly = false },
		["CharacterJumpHeight"] = { Kind = "Property", Default = 7.19999981, ReadOnly = false },
		["CharacterJumpPower"] = { Kind = "Property", Default = 50, ReadOnly = false },
		["CharacterMaxSlopeAngle"] = { Kind = "Property", Default = 89, ReadOnly = false },
		["CharacterUseJumpPower"] = { Kind = "Property", Default = true, ReadOnly = false },
		["CharacterWalkSpeed"] = { Kind = "Property", Default = 16, ReadOnly = false },
		["ClassicDeath"] = { Kind = "Property", Default = true, ReadOnly = false },
		["DevCameraOcclusionMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["DevComputerCameraMovementMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["DevComputerMovementMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["DevTouchCameraMovementMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["DevTouchMovementMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["EnableMouseLockOption"] = { Kind = "Property", Default = true, ReadOnly = false },
		["HealthDisplayDistance"] = { Kind = "Property", Default = 100, ReadOnly = false },
		["LoadCharacterAppearance"] = { Kind = "Property", Default = true, ReadOnly = false },
		["LuaCharacterController"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["NameDisplayDistance"] = { Kind = "Property", Default = 100, ReadOnly = false },
		["UserEmotesEnabled"] = { Kind = "Property", Default = true, ReadOnly = false },
	} :: Runtime.ClassSchema,
	MethodNames = {
	},
}

table.freeze(Generated.Schema)

return Generated
