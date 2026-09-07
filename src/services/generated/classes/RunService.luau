--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Tipo público de "RunService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type RunService = Runtime.Instance & {
	["Heartbeat"]: Runtime.Signal<number>,
	["PostSimulation"]: Runtime.Signal<number>,
	["PreAnimation"]: Runtime.Signal<number>,
	["PreRender"]: Runtime.Signal<number>,
	["PreSimulation"]: Runtime.Signal<number>,
	["RenderStepped"]: Runtime.Signal<number>,
	["Rollback"]: Runtime.Signal<number>,
	["Stepped"]: Runtime.Signal<number, number>,
	["BindToRenderStep"]: (self: RunService, name: string, priority: number, function_: unknown) -> (),
	["BindToSimulation"]: (self: RunService, function_: unknown, frequency: ValueTypes.EnumItem?, priority: number?) -> unknown,
	["GetPredictionStatus"]: (self: RunService, context: unknown) -> ValueTypes.EnumItem,
	["IsClient"]: (self: RunService) -> boolean,
	["IsResimulating"]: (self: RunService) -> boolean,
	["IsRunMode"]: (self: RunService) -> boolean,
	["IsRunning"]: (self: RunService) -> boolean,
	["IsServer"]: (self: RunService) -> boolean,
	["IsStudio"]: (self: RunService) -> boolean,
	["SetPredictionMode"]: (self: RunService, context: unknown, mode: ValueTypes.EnumItem) -> (),
	["UnbindFromRenderStep"]: (self: RunService, name: string) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "RunService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["ClientGitHash"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = false },
		["FrameNumber"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int64", ValueCategory = "Primitive", ScriptVisible = false },
		["RunState"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "RunState", ValueCategory = "Enum", ScriptVisible = false },
		["Heartbeat"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PostSimulation"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PreAnimation"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PreRender"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PreSimulation"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["RenderStepped"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["Rollback"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["Stepped"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"BindToRenderStep",
		"BindToSimulation",
		"GetPredictionStatus",
		"IsClient",
		"IsResimulating",
		"IsRunMode",
		"IsRunning",
		"IsServer",
		"IsStudio",
		"SetPredictionMode",
		"UnbindFromRenderStep",
	},
}

table.freeze(Generated.Schema)

return Generated
