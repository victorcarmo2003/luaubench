--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Resolve o Default de uma Property Enum a partir do NOME do item -- gramática confirmada por
-- inspeção direta do dump pinado nesta geração (Default de uma Property "Enum" é sempre o
-- `Name` de um EnumItem, ex.: "Realistic" em Lighting.LightingStyle). Reusa
-- `ValueTypes.Decode.FromRojoJson` (a MESMA resolução nome->EnumItem que `cli` usa pra
-- decodificar `$properties` do Rojo, task-valuetypes-007) em vez de reimplementar aqui uma
-- segunda forma de indexar `ValueTypes.Enum` por nome dinâmico de enum -- ver
-- tools/generate-services.luau, computeDefault. Nunca falha em uso normal: o par
-- (enum, item) já foi confirmado contra o MESMO Full-API-Dump.json nesta geração; só erra se
-- o dump mudar sem o gerador ser revisado (mesmo protocolo de falha alta e cedo do resto
-- deste arquivo).
local function enumDefault(enumName: string, itemName: string): unknown
	local result = ValueTypes.Decode.FromRojoJson(enumName, "Enum", itemName)
	if result.Ok then
		return result.Value
	else
		error(`generated/StarterPlayer: Default de Enum inválido ({enumName}.{itemName}): {result.Reason}`)
	end
end

-- Tipo público de "StarterPlayer". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type StarterPlayer = Runtime.Instance & {
	["AllowCustomAnimations"]: boolean,
	["AutoJumpEnabled"]: boolean,
	["CameraMaxZoomDistance"]: number,
	["CameraMinZoomDistance"]: number,
	["CameraMode"]: ValueTypes.EnumItem,
	["CharacterBreakJointsOnDeath"]: boolean,
	["CharacterJumpHeight"]: number,
	["CharacterJumpPower"]: number,
	["CharacterMaxSlopeAngle"]: number,
	["CharacterUseJumpPower"]: boolean,
	["CharacterWalkSpeed"]: number,
	["ClassicDeath"]: boolean,
	["DevCameraOcclusionMode"]: ValueTypes.EnumItem,
	["DevComputerCameraMovementMode"]: ValueTypes.EnumItem,
	["DevComputerMovementMode"]: ValueTypes.EnumItem,
	["DevTouchCameraMovementMode"]: ValueTypes.EnumItem,
	["DevTouchMovementMode"]: ValueTypes.EnumItem,
	["EnableMouseLockOption"]: boolean,
	["HealthDisplayDistance"]: number,
	["LoadCharacterAppearance"]: boolean,
	["LuaCharacterController"]: ValueTypes.EnumItem,
	["NameDisplayDistance"]: number,
	["UserEmotesEnabled"]: boolean,
}

local Generated: Types.GeneratedClass = {
	ClassName = "StarterPlayer",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["AllowCustomAnimations"] = { Kind = "Property", Default = true, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["AutoJumpEnabled"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["AvatarJointUpgrade"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["AvatarJointUpgrade_SerializedRollout"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["CameraMaxZoomDistance"] = { Kind = "Property", Default = 400, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["CameraMinZoomDistance"] = { Kind = "Property", Default = 0.5, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["CameraMode"] = { Kind = "Property", Default = enumDefault("CameraMode", "Classic"), ReadOnly = false, ValueType = "CameraMode", ValueCategory = "Enum", ScriptVisible = true },
		["CharacterBreakJointsOnDeath"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterJumpHeight"] = { Kind = "Property", Default = 7.19999981, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterJumpPower"] = { Kind = "Property", Default = 50, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterMaxSlopeAngle"] = { Kind = "Property", Default = 89, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterUseJumpPower"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterWalkSpeed"] = { Kind = "Property", Default = 16, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ClassicDeath"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["CreateDefaultPlayerModule"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["DevCameraOcclusionMode"] = { Kind = "Property", Default = enumDefault("DevCameraOcclusionMode", "Zoom"), ReadOnly = false, ValueType = "DevCameraOcclusionMode", ValueCategory = "Enum", ScriptVisible = true },
		["DevComputerCameraMovementMode"] = { Kind = "Property", Default = enumDefault("DevComputerCameraMovementMode", "UserChoice"), ReadOnly = false, ValueType = "DevComputerCameraMovementMode", ValueCategory = "Enum", ScriptVisible = true },
		["DevComputerMovementMode"] = { Kind = "Property", Default = enumDefault("DevComputerMovementMode", "UserChoice"), ReadOnly = false, ValueType = "DevComputerMovementMode", ValueCategory = "Enum", ScriptVisible = true },
		["DevTouchCameraMovementMode"] = { Kind = "Property", Default = enumDefault("DevTouchCameraMovementMode", "UserChoice"), ReadOnly = false, ValueType = "DevTouchCameraMovementMode", ValueCategory = "Enum", ScriptVisible = true },
		["DevTouchMovementMode"] = { Kind = "Property", Default = enumDefault("DevTouchMovementMode", "UserChoice"), ReadOnly = false, ValueType = "DevTouchMovementMode", ValueCategory = "Enum", ScriptVisible = true },
		["EnableDynamicHeads"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "LoadDynamicHeads", ValueCategory = "Enum", ScriptVisible = false },
		["EnableMouseLockOption"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["GameSettingsAssetIDFace"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDHead"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDLeftArm"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDLeftLeg"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDPants"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDRightArm"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDRightLeg"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDShirt"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDTeeShirt"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAssetIDTorso"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["GameSettingsAvatar"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "GameAvatarType", ValueCategory = "Enum", ScriptVisible = false },
		["GameSettingsR15Collision"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "R15CollisionType", ValueCategory = "Enum", ScriptVisible = false },
		["GameSettingsScaleRangeBodyType"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "NumberRange", ValueCategory = "DataType", ScriptVisible = false },
		["GameSettingsScaleRangeHead"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "NumberRange", ValueCategory = "DataType", ScriptVisible = false },
		["GameSettingsScaleRangeHeight"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "NumberRange", ValueCategory = "DataType", ScriptVisible = false },
		["GameSettingsScaleRangeProportion"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "NumberRange", ValueCategory = "DataType", ScriptVisible = false },
		["GameSettingsScaleRangeWidth"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "NumberRange", ValueCategory = "DataType", ScriptVisible = false },
		["HealthDisplayDistance"] = { Kind = "Property", Default = 100, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["LoadCharacterAppearance"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["LoadCharacterLayeredClothing"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "LoadCharacterLayeredClothing", ValueCategory = "Enum", ScriptVisible = false },
		["LoadCharacterLayeredClothing "] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "LoadCharacterLayeredClothing", ValueCategory = "Enum", ScriptVisible = false },
		["LuaCharacterController"] = { Kind = "Property", Default = enumDefault("CharacterControlMode", "Default"), ReadOnly = false, ValueType = "CharacterControlMode", ValueCategory = "Enum", ScriptVisible = true },
		["NameDisplayDistance"] = { Kind = "Property", Default = 100, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["PlayerModuleStatus"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["UserEmotesEnabled"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
	} :: Runtime.ClassSchema,
	MethodNames = {
	},
}

table.freeze(Generated.Schema)

return Generated
