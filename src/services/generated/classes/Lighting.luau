--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "Lighting". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type Lighting = Runtime.Instance & {
	["Ambient"]: unknown,
	["Brightness"]: number,
	["ClockTime"]: number,
	["ColorShift_Bottom"]: unknown,
	["ColorShift_Top"]: unknown,
	["EnvironmentDiffuseScale"]: number,
	["EnvironmentSpecularScale"]: number,
	["ExposureCompensation"]: number,
	["FogColor"]: unknown,
	["FogEnd"]: number,
	["FogStart"]: number,
	["GeographicLatitude"]: number,
	["GlobalShadows"]: boolean,
	["LightingStyle"]: unknown,
	["OutdoorAmbient"]: unknown,
	["Outlines"]: boolean,
	["PrioritizeLightingQuality"]: boolean,
	["ShadowColor"]: unknown,
	["ShadowSoftness"]: number,
	["TimeOfDay"]: string,
	["LightingChanged"]: Runtime.Signal<boolean>,
	["GetMinutesAfterMidnight"]: (self: Lighting) -> number,
	["GetMoonDirection"]: (self: Lighting) -> unknown,
	["GetMoonPhase"]: (self: Lighting) -> number,
	["GetSunDirection"]: (self: Lighting) -> unknown,
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
		["Ambient"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["Brightness"] = { Kind = "Property", Default = 1, ReadOnly = false },
		["ClockTime"] = { Kind = "Property", Default = 14, ReadOnly = false },
		["ColorShift_Bottom"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ColorShift_Top"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["EnvironmentDiffuseScale"] = { Kind = "Property", Default = 0, ReadOnly = false },
		["EnvironmentSpecularScale"] = { Kind = "Property", Default = 0, ReadOnly = false },
		["ExposureCompensation"] = { Kind = "Property", Default = 0, ReadOnly = false },
		["FogColor"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["FogEnd"] = { Kind = "Property", Default = 100000, ReadOnly = false },
		["FogStart"] = { Kind = "Property", Default = 0, ReadOnly = false },
		["GeographicLatitude"] = { Kind = "Property", Default = 41.7332993, ReadOnly = false },
		["GlobalShadows"] = { Kind = "Property", Default = false, ReadOnly = false },
		["LightingStyle"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["OutdoorAmbient"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["Outlines"] = { Kind = "Property", Default = true, ReadOnly = false },
		["PrioritizeLightingQuality"] = { Kind = "Property", Default = true, ReadOnly = true },
		["ShadowColor"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ShadowSoftness"] = { Kind = "Property", Default = 0.5, ReadOnly = false },
		["TimeOfDay"] = { Kind = "Property", Default = "14:00:00", ReadOnly = false },
		["LightingChanged"] = { Kind = "Event", Default = nil, ReadOnly = true },
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
