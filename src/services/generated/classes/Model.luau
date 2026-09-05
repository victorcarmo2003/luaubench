--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "Model". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
export type Model = Runtime.Instance & {
	["ModelStreamingMode"]: unknown,
	["PrimaryPart"]: unknown,
	["WorldPivot"]: unknown,
	["AddPersistentPlayer"]: (self: Model, playerInstance: unknown?) -> (),
	["BreakJoints"]: (self: Model) -> (),
	["GetBoundingBox"]: (self: Model) -> unknown,
	["GetExtentsSize"]: (self: Model) -> unknown,
	["GetModelCFrame"]: (self: Model) -> unknown,
	["GetModelSize"]: (self: Model) -> unknown,
	["GetPersistentPlayers"]: (self: Model) -> unknown,
	["GetPrimaryPartCFrame"]: (self: Model) -> unknown,
	["GetScale"]: (self: Model) -> number,
	["MakeJoints"]: (self: Model) -> (),
	["MoveTo"]: (self: Model, position: unknown) -> (),
	["RemovePersistentPlayer"]: (self: Model, playerInstance: unknown?) -> (),
	["ResetOrientationToIdentity"]: (self: Model) -> (),
	["ScaleTo"]: (self: Model, newScaleFactor: number) -> (),
	["SetIdentityOrientation"]: (self: Model) -> (),
	["SetPrimaryPartCFrame"]: (self: Model, cframe: unknown) -> (),
	["TranslateBy"]: (self: Model, delta: unknown) -> (),
	["breakJoints"]: (self: Model) -> (),
	["makeJoints"]: (self: Model) -> (),
	["move"]: (self: Model, location: unknown) -> (),
	["moveTo"]: (self: Model, location: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Model",
	Superclass = "PVInstance",
	IsService = false,
	IsAbstract = false,
	Schema = {
		["ModelStreamingMode"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["PrimaryPart"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["WorldPivot"] = { Kind = "Property", Default = nil, ReadOnly = false },
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
