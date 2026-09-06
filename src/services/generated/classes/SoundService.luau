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
		error(`generated/SoundService: Default de Enum inválido ({enumName}.{itemName}): {result.Reason}`)
	end
end

-- Tipo público de "SoundService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type SoundService = Runtime.Instance & {
	["AcousticSimulationEnabled"]: boolean,
	["AmbientReverb"]: ValueTypes.EnumItem,
	["CharacterSoundsUseNewApi"]: ValueTypes.EnumItem,
	["DiffractionEnabled"]: boolean,
	["DistanceFactor"]: number,
	["DopplerScale"]: number,
	["ListenerCFrame"]: ValueTypes.CFrame,
	["ListenerObject"]: unknown,
	["ListenerType"]: ValueTypes.EnumItem,
	["OcclusionEnabled"]: boolean,
	["RespectFilteringEnabled"]: boolean,
	["ReverbEnabled"]: boolean,
	["RolloffScale"]: number,
	["GetListener"]: (self: SoundService) -> ...unknown,
	["GetMixerTime"]: (self: SoundService) -> number,
	["PlayLocalSound"]: (self: SoundService, sound: unknown) -> (),
	["SetListener"]: (self: SoundService, listenerType: ValueTypes.EnumItem, listener: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "SoundService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["AcousticSimulationEnabled"] = { Kind = "Property", Default = false, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["AmbientReverb"] = { Kind = "Property", Default = enumDefault("ReverbType", "NoReverb"), ReadOnly = false, ValueType = "ReverbType", ValueCategory = "Enum" },
		["CharacterSoundsUseNewApi"] = { Kind = "Property", Default = enumDefault("RolloutState", "Default"), ReadOnly = true, ValueType = "RolloutState", ValueCategory = "Enum" },
		["DiffractionEnabled"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["DistanceFactor"] = { Kind = "Property", Default = 3.32999992, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
		["DopplerScale"] = { Kind = "Property", Default = 1, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
		["ListenerCFrame"] = { Kind = "Property", Default = ValueTypes.CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), ReadOnly = false, ValueType = "CFrame", ValueCategory = "DataType" },
		["ListenerObject"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Instance", ValueCategory = "Class" },
		["ListenerType"] = { Kind = "Property", Default = enumDefault("ListenerType", "Camera"), ReadOnly = false, ValueType = "ListenerType", ValueCategory = "Enum" },
		["OcclusionEnabled"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["RespectFilteringEnabled"] = { Kind = "Property", Default = false, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["ReverbEnabled"] = { Kind = "Property", Default = true, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["RolloffScale"] = { Kind = "Property", Default = 1, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive" },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetListener",
		"GetMixerTime",
		"PlayLocalSound",
		"SetListener",
	},
}

table.freeze(Generated.Schema)

return Generated
