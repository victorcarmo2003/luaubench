--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Tipo público de "HttpService". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type HttpService = Runtime.Instance & {
	["HttpEnabled"]: boolean,
	["CreateWebStreamClient"]: (self: HttpService, streamClientType: ValueTypes.EnumItem, requestOptions: unknown) -> unknown,
	["GenerateGUID"]: (self: HttpService, wrapInCurlyBraces: boolean?) -> string,
	["GetSecret"]: (self: HttpService, key: string) -> unknown,
	["JSONDecode"]: (self: HttpService, input: string) -> { [string]: unknown },
	["JSONEncode"]: (self: HttpService, input: unknown) -> string,
	["UrlEncode"]: (self: HttpService, input: string) -> string,
	["GetAsync"]: (self: HttpService, url: unknown, nocache: boolean?, headers: unknown) -> string,
	["PostAsync"]: (self: HttpService, url: unknown, data: string, content_type: ValueTypes.EnumItem?, compress: boolean?, headers: unknown) -> string,
	["RequestAsync"]: (self: HttpService, requestOptions: unknown) -> { [string]: unknown },
}

local Generated: Types.GeneratedClass = {
	ClassName = "HttpService",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["HttpEnabled"] = { Kind = "Property", Default = false, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive" },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"CreateWebStreamClient",
		"GenerateGUID",
		"GetSecret",
		"JSONDecode",
		"JSONEncode",
		"UrlEncode",
		"GetAsync",
		"PostAsync",
		"RequestAsync",
	},
}

table.freeze(Generated.Schema)

return Generated
