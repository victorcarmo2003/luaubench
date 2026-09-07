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
		error(`generated/Lighting: Default de Enum inválido ({enumName}.{itemName}): {result.Reason}`)
	end
end

-- Tipo público de "Lighting". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type Lighting = Runtime.Instance & {
	["Ambient"]: ValueTypes.Color3,
	["Brightness"]: number,
	["ClockTime"]: number,
	["ColorShift_Bottom"]: ValueTypes.Color3,
	["ColorShift_Top"]: ValueTypes.Color3,
	["EnvironmentDiffuseScale"]: number,
	["EnvironmentSpecularScale"]: number,
	["ExposureCompensation"]: number,
	["FogColor"]: ValueTypes.Color3,
	["FogEnd"]: number,
	["FogStart"]: number,
	["GeographicLatitude"]: number,
	["GlobalShadows"]: boolean,
	["LightingStyle"]: ValueTypes.EnumItem,
	["OutdoorAmbient"]: ValueTypes.Color3,
	["Outlines"]: boolean,
	["PrioritizeLightingQuality"]: boolean,
	["ShadowColor"]: ValueTypes.Color3,
	["ShadowSoftness"]: number,
	["TimeOfDay"]: string,
	["LightingChanged"]: Runtime.Signal<boolean>,
	["GetMinutesAfterMidnight"]: (self: Lighting) -> number,
	["GetMoonDirection"]: (self: Lighting) -> ValueTypes.Vector3,
	["GetMoonPhase"]: (self: Lighting) -> number,
	["GetSunDirection"]: (self: Lighting) -> ValueTypes.Vector3,
	["SetMinutesAfterMidnight"]: (self: Lighting, minutes: number) -> (),
	["getMinutesAfterMidnight"]: (self: Lighting) -> number,
	["setMinutesAfterMidnight"]: (self: Lighting, minutes: number) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Lighting",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["Ambient"] = { Kind = "Property", Default = ValueTypes.Color3.new(0.5, 0.5, 0.5), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["Brightness"] = { Kind = "Property", Default = 1, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ClockTime"] = { Kind = "Property", Default = 14, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ColorShift_Bottom"] = { Kind = "Property", Default = ValueTypes.Color3.new(0, 0, 0), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["ColorShift_Top"] = { Kind = "Property", Default = ValueTypes.Color3.new(0, 0, 0), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["EnvironmentDiffuseScale"] = { Kind = "Property", Default = 0, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["EnvironmentSpecularScale"] = { Kind = "Property", Default = 0, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ExposureCompensation"] = { Kind = "Property", Default = 0, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ExtendLightRangeTo120"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RolloutState", ValueCategory = "Enum", ScriptVisible = false },
		["FogColor"] = { Kind = "Property", Default = ValueTypes.Color3.new(0.75, 0.75, 0.75), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["FogEnd"] = { Kind = "Property", Default = 100000, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["FogStart"] = { Kind = "Property", Default = 0, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["GeographicLatitude"] = { Kind = "Property", Default = 41.7332993, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["GlobalShadows"] = { Kind = "Property", Default = false, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["LightingStyle"] = { Kind = "Property", Default = enumDefault("LightingStyle", "Realistic"), ReadOnly = true, ValueType = "LightingStyle", ValueCategory = "Enum", ScriptVisible = true },
		["OutdoorAmbient"] = { Kind = "Property", Default = ValueTypes.Color3.new(0.5, 0.5, 0.5), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["Outlines"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["PrioritizeLightingQuality"] = { Kind = "Property", Default = true, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["ShadowColor"] = { Kind = "Property", Default = ValueTypes.Color3.new(0.7, 0.7, 0.72), ReadOnly = false, ValueType = "Color3", ValueCategory = "DataType", ScriptVisible = true },
		["ShadowSoftness"] = { Kind = "Property", Default = 0.5, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["Technology"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Technology", ValueCategory = "Enum", ScriptVisible = false },
		["TimeOfDay"] = { Kind = "Property", Default = "14:00:00", ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = true },
		["LightingChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetMinutesAfterMidnight",
		"GetMoonDirection",
		"GetMoonPhase",
		"GetSunDirection",
		"SetMinutesAfterMidnight",
		"getMinutesAfterMidnight",
		"setMinutesAfterMidnight",
	},
}

table.freeze(Generated.Schema)

return Generated
