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
		error(`generated/Model: Default de Enum inválido ({enumName}.{itemName}): {result.Reason}`)
	end
end

-- Tipo público de "Model". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type Model = Runtime.Instance & {
	["ModelStreamingMode"]: ValueTypes.EnumItem,
	["PrimaryPart"]: unknown,
	["WorldPivot"]: ValueTypes.CFrame,
	["AddPersistentPlayer"]: (self: Model, playerInstance: unknown?) -> (),
	["BreakJoints"]: (self: Model) -> (),
	["GetBoundingBox"]: (self: Model) -> unknown,
	["GetExtentsSize"]: (self: Model) -> ValueTypes.Vector3,
	["GetModelCFrame"]: (self: Model) -> ValueTypes.CFrame,
	["GetModelSize"]: (self: Model) -> ValueTypes.Vector3,
	["GetPersistentPlayers"]: (self: Model) -> unknown,
	["GetPrimaryPartCFrame"]: (self: Model) -> ValueTypes.CFrame,
	["GetScale"]: (self: Model) -> number,
	["MakeJoints"]: (self: Model) -> (),
	["MoveTo"]: (self: Model, position: ValueTypes.Vector3) -> (),
	["RemovePersistentPlayer"]: (self: Model, playerInstance: unknown?) -> (),
	["ResetOrientationToIdentity"]: (self: Model) -> (),
	["ScaleTo"]: (self: Model, newScaleFactor: number) -> (),
	["SetIdentityOrientation"]: (self: Model) -> (),
	["SetPrimaryPartCFrame"]: (self: Model, cframe: ValueTypes.CFrame) -> (),
	["TranslateBy"]: (self: Model, delta: ValueTypes.Vector3) -> (),
	["breakJoints"]: (self: Model) -> (),
	["makeJoints"]: (self: Model) -> (),
	["move"]: (self: Model, location: ValueTypes.Vector3) -> (),
	["moveTo"]: (self: Model, location: ValueTypes.Vector3) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Model",
	Superclass = "PVInstance",
	IsService = false,
	IsAbstract = false,
	Schema = {
		["LevelOfDetail"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "ModelLevelOfDetail", ValueCategory = "Enum", ScriptVisible = false },
		["LodEntity"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "LodDataEntity", ValueCategory = "Class", ScriptVisible = false },
		["ModelMeshCFrame"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "CFrame", ValueCategory = "DataType", ScriptVisible = false },
		["ModelMeshData"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SharedString", ValueCategory = "DataType", ScriptVisible = false },
		["ModelMeshSize"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Vector3", ValueCategory = "DataType", ScriptVisible = false },
		["ModelStreamingMode"] = { Kind = "Property", Default = enumDefault("ModelStreamingMode", "Default"), ReadOnly = false, ValueType = "ModelStreamingMode", ValueCategory = "Enum", ScriptVisible = true },
		["NeedsPivotMigration"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["PrimaryPart"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "BasePart", ValueCategory = "Class", ScriptVisible = true },
		["Scale"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = false },
		["ScaleFactor"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = false },
		["SlimAnimationTarget"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SlimAnimationDataEntity", ValueCategory = "Class", ScriptVisible = false },
		["SlimHash"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SharedString", ValueCategory = "DataType", ScriptVisible = false },
		["WorldPivot"] = { Kind = "Property", Default = ValueTypes.CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), ReadOnly = false, ValueType = "CFrame", ValueCategory = "DataType", ScriptVisible = true },
		["WorldPivotData"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "OptionalCoordinateFrame", ValueCategory = "DataType", ScriptVisible = false },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"AddPersistentPlayer",
		"BreakJoints",
		"GetBoundingBox",
		"GetExtentsSize",
		"GetModelCFrame",
		"GetModelSize",
		"GetPersistentPlayers",
		"GetPrimaryPartCFrame",
		"GetScale",
		"MakeJoints",
		"MoveTo",
		"RemovePersistentPlayer",
		"ResetOrientationToIdentity",
		"ScaleTo",
		"SetIdentityOrientation",
		"SetPrimaryPartCFrame",
		"TranslateBy",
		"breakJoints",
		"makeJoints",
		"move",
		"moveTo",
	},
}

table.freeze(Generated.Schema)

return Generated
