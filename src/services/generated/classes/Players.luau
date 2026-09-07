--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")
local ValueTypes = require("../../../valuetypes")

-- Tipo público de "Players". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável/ainda não simulado (DataType da leva
-- 2/Class) e para retorno/parâmetro de método cuja categoria não é Primitive/DataType já
-- simulado/Enum -- ver tools/generate-services.luau, luauTypeForValueType/luauReturnType.
export type Players = Runtime.Instance & {
	["BubbleChat"]: unknown,
	["CharacterAutoLoads"]: unknown,
	["ClassicChat"]: unknown,
	["LocalPlayer"]: unknown,
	["MaxPlayers"]: unknown,
	["NumPlayers"]: unknown,
	["PreferredPlayers"]: unknown,
	["RespawnTime"]: unknown,
	["localPlayer"]: unknown,
	["numPlayers"]: unknown,
	["PlayerAdded"]: Runtime.Signal<unknown>,
	["PlayerMembershipChanged"]: Runtime.Signal<unknown>,
	["PlayerRemoving"]: Runtime.Signal<unknown, ValueTypes.EnumItem>,
	["UserSubscriptionStatusChanged"]: Runtime.Signal<unknown, string>,
	["GetPlayerByUserId"]: (self: Players, userId: unknown) -> unknown,
	["GetPlayerFromCharacter"]: (self: Players, character: unknown) -> unknown,
	["GetPlayers"]: (self: Players) -> unknown,
	["getPlayers"]: (self: Players) -> unknown,
	["playerFromCharacter"]: (self: Players, character: unknown) -> unknown,
	["players"]: (self: Players) -> unknown,
	["BanAsync"]: (self: Players, config: unknown) -> (),
	["CreateHumanoidModelFromDescription"]: (self: Players, description: unknown, rigType: ValueTypes.EnumItem, assetTypeVerification: ValueTypes.EnumItem?) -> unknown,
	["CreateHumanoidModelFromDescriptionAsync"]: (self: Players, description: unknown, rigType: ValueTypes.EnumItem, assetTypeVerification: ValueTypes.EnumItem?) -> unknown,
	["CreateHumanoidModelFromUserId"]: (self: Players, userId: unknown) -> unknown,
	["CreateHumanoidModelFromUserIdAsync"]: (self: Players, userId: unknown) -> unknown,
	["GetBanHistoryAsync"]: (self: Players, userId: unknown) -> unknown,
	["GetCharacterAppearanceAsync"]: (self: Players, userId: unknown) -> unknown,
	["GetCharacterAppearanceInfoAsync"]: (self: Players, userId: unknown) -> { [string]: unknown },
	["GetFriendsAsync"]: (self: Players, userId: unknown) -> unknown,
	["GetHumanoidDescriptionFromOutfitId"]: (self: Players, outfitId: number) -> unknown,
	["GetHumanoidDescriptionFromOutfitIdAsync"]: (self: Players, outfitId: number) -> unknown,
	["GetHumanoidDescriptionFromUserId"]: (self: Players, userId: unknown) -> unknown,
	["GetHumanoidDescriptionFromUserIdAsync"]: (self: Players, userId: unknown) -> unknown,
	["GetNameFromUserIdAsync"]: (self: Players, userId: unknown) -> string,
	["GetProfileConfigurationFromUserIdAsync"]: (self: Players, userId: unknown) -> { [string]: unknown },
	["GetUserIdFromNameAsync"]: (self: Players, userName: string) -> number,
	["GetUserThumbnailAsync"]: (self: Players, userId: unknown, thumbnailType: ValueTypes.EnumItem, thumbnailSize: ValueTypes.EnumItem) -> ...unknown,
	["UnbanAsync"]: (self: Players, config: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Players",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	-- Entradas abaixo com `ScriptVisible = false` têm `Default = nil` de propósito: a
	-- propriedade REAL do Roblox tem um default (às vezes um valor concreto, ex.:
	-- `Technology = Enum.Technology.Voxel`), só que ele não é representável/semeável
	-- por este runtime, porque a propriedade é invisível a script (`instance.X`/`instance.X
	-- = v` de um script nunca a alcança -- só `Instance.SetPropertyRaw`/`GetPropertyRaw`,
	-- o caminho que a hidratação de `$properties` do Rojo usa). Não leia `Default = nil`
	-- aqui como "esta propriedade não tem default no Roblox real" -- ver
	-- tools/generate-services.luau, classifySchemaMember/computeDefault.
	Schema = {
		["BanningEnabled"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["BubbleChat"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["CharacterAutoLoads"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["ClassicChat"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = true },
		["LocalPlayer"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "Player", ValueCategory = "Class", ScriptVisible = true },
		["MaxPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = true },
		["MaxPlayersInternal"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["NumPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = true },
		["PreferredPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = true },
		["PreferredPlayersInternal"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = false },
		["RespawnTime"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "float", ValueCategory = "Primitive", ScriptVisible = true },
		["ServerGitHash"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = false },
		["ServerLogPrefix"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "string", ValueCategory = "Primitive", ScriptVisible = false },
		["UseStrafingAnimations"] = { Kind = "Property", Default = nil, ReadOnly = false, ValueType = "bool", ValueCategory = "Primitive", ScriptVisible = false },
		["localPlayer"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "Player", ValueCategory = "Class", ScriptVisible = true },
		["numPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true, ValueType = "int", ValueCategory = "Primitive", ScriptVisible = true },
		["PlayerAdded"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PlayerMembershipChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["PlayerRemoving"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
		["UserSubscriptionStatusChanged"] = { Kind = "Event", Default = nil, ReadOnly = true, ValueType = nil, ValueCategory = nil, ScriptVisible = true },
	} :: Runtime.ClassSchema,
	MethodNames = {
		"GetPlayerByUserId",
		"GetPlayerFromCharacter",
		"GetPlayers",
		"getPlayers",
		"playerFromCharacter",
		"players",
		"BanAsync",
		"CreateHumanoidModelFromDescription",
		"CreateHumanoidModelFromDescriptionAsync",
		"CreateHumanoidModelFromUserId",
		"CreateHumanoidModelFromUserIdAsync",
		"GetBanHistoryAsync",
		"GetCharacterAppearanceAsync",
		"GetCharacterAppearanceInfoAsync",
		"GetFriendsAsync",
		"GetHumanoidDescriptionFromOutfitId",
		"GetHumanoidDescriptionFromOutfitIdAsync",
		"GetHumanoidDescriptionFromUserId",
		"GetHumanoidDescriptionFromUserIdAsync",
		"GetNameFromUserIdAsync",
		"GetProfileConfigurationFromUserIdAsync",
		"GetUserIdFromNameAsync",
		"GetUserThumbnailAsync",
		"UnbanAsync",
	},
}

table.freeze(Generated.Schema)

return Generated
