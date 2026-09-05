--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "RunService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
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
	["BindToSimulation"]: (self: RunService, function_: unknown, frequency: unknown?, priority: number?) -> unknown,
	["GetPredictionStatus"]: (self: RunService, context: unknown) -> unknown,
	["IsClient"]: (self: RunService) -> boolean,
	["IsResimulating"]: (self: RunService) -> boolean,
	["IsRunMode"]: (self: RunService) -> boolean,
	["IsRunning"]: (self: RunService) -> boolean,
	["IsServer"]: (self: RunService) -> boolean,
	["IsStudio"]: (self: RunService) -> boolean,
	["SetPredictionMode"]: (self: RunService, context: unknown, mode: unknown) -> (),
	["UnbindFromRenderStep"]: (self: RunService, name: string) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "RunService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["Heartbeat"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PostSimulation"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PreAnimation"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PreRender"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PreSimulation"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["RenderStepped"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["Rollback"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["Stepped"] = { Kind = "Event", Default = nil, ReadOnly = true },
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
