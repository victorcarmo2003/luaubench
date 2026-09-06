--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "Instance". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type Instance = Runtime.Instance & {
	["Archivable"]: unknown,
	["Capabilities"]: unknown,
	["Sandboxed"]: unknown,
	["archivable"]: unknown,
	["AttributeChanged"]: Runtime.Signal<string>,
	["DescendantAdded"]: Runtime.Signal<unknown>,
	["DescendantRemoving"]: Runtime.Signal<unknown>,
	["StyledPropertiesChanged"]: Runtime.Signal<>,
	["childAdded"]: Runtime.Signal<unknown>,
	["className"]: unknown,
	["AddTag"]: (self: Instance, tag: string) -> (),
	["Clone"]: (self: Instance) -> unknown,
	["FindFirstAncestorOfClass"]: (self: Instance, className: string) -> unknown,
	["FindFirstAncestorWhichIsA"]: (self: Instance, className: string) -> unknown,
	["FindFirstDescendant"]: (self: Instance, name: string) -> unknown,
	["GetActor"]: (self: Instance) -> unknown,
	["GetAttribute"]: (self: Instance, attribute: string) -> { [string]: unknown },
	["GetAttributeChangedSignal"]: (self: Instance, attribute: string) -> unknown,
	["GetAttributes"]: (self: Instance) -> { [string]: unknown },
	["GetStyled"]: (self: Instance, name: string, selector: unknown) -> { [string]: unknown },
	["GetStyledPropertyChangedSignal"]: (self: Instance, property: string) -> unknown,
	["GetTags"]: (self: Instance) -> { unknown },
	["HasTag"]: (self: Instance, tag: string) -> boolean,
	["IsPropertyModified"]: (self: Instance, property: string) -> boolean,
	["QueryDescendants"]: (self: Instance, selector: string) -> unknown,
	["Remove"]: (self: Instance) -> (),
	["RemoveTag"]: (self: Instance, tag: string) -> (),
	["ResetPropertyToDefault"]: (self: Instance, property: string) -> (),
	["SetAttribute"]: (self: Instance, attribute: string, value: unknown) -> (),
	["children"]: (self: Instance) -> unknown,
	["clone"]: (self: Instance) -> unknown,
	["destroy"]: (self: Instance) -> (),
	["findFirstChild"]: (self: Instance, name: string, recursive: boolean?) -> unknown,
	["getChildren"]: (self: Instance) -> unknown,
	["isDescendantOf"]: (self: Instance, ancestor: unknown) -> boolean,
	["remove"]: (self: Instance) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Instance",
	Superclass = "Instance",
	IsService = false,
	IsAbstract = true,
	Schema = {
		["Archivable"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["Capabilities"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "SecurityCapabilities", ValueCategory = "DataType" },
		["Name"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive" },
		["Parent"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "Instance", ValueCategory = "Class" },
		["Sandboxed"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["archivable"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive" },
		["AncestryChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["AttributeChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["ChildAdded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["ChildRemoved"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["DescendantAdded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["DescendantRemoving"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["Destroying"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["StyledPropertiesChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["childAdded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
		["ClassName"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "string", ValueCategory = "Primitive" },
		["className"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "string", ValueCategory = "Primitive" },
		["Changed"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"AddTag",
		"ClearAllChildren",
		"Clone",
		"Destroy",
		"FindFirstAncestor",
		"FindFirstAncestorOfClass",
		"FindFirstAncestorWhichIsA",
		"FindFirstChild",
		"FindFirstChildOfClass",
		"FindFirstChildWhichIsA",
		"FindFirstDescendant",
		"GetActor",
		"GetAttribute",
		"GetAttributeChangedSignal",
		"GetAttributes",
		"GetChildren",
		"GetDescendants",
		"GetFullName",
		"GetStyled",
		"GetStyledPropertyChangedSignal",
		"GetTags",
		"HasTag",
		"IsAncestorOf",
		"IsDescendantOf",
		"IsPropertyModified",
		"QueryDescendants",
		"Remove",
		"RemoveTag",
		"ResetPropertyToDefault",
		"SetAttribute",
		"WaitForChild",
		"children",
		"clone",
		"destroy",
		"findFirstChild",
		"getChildren",
		"isDescendantOf",
		"remove",
	},
}

table.freeze(Generated.Schema)

return Generated
