--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

local Types = require("../../Types")
local Runtime = require("../../../runtime")

-- Tipo público de "Players". Campos/métodos que `src/runtime/Instance.luau` já cobre nativamente
-- (ClassName/Name/Parent, os 5 sinais fixos, os 13 métodos base) NÃO são redeclarados aqui -- já vêm
-- de `Runtime.Instance &` com o tipo real; redeclarar criaria redundância/risco de conflito de tipo.
-- `unknown` (nunca `any`) para ValueType não representável nesta fase (Enum/DataType/Class) e para
-- retorno/parametro de método cuja categoria não é Primitive -- ver tools/generate-services.luau,
-- luauTypeForValueType/luauReturnType.
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
	["PlayerRemoving"]: Runtime.Signal<unknown, unknown>,
	["UserSubscriptionStatusChanged"]: Runtime.Signal<unknown, string>,
	["GetPlayerByUserId"]: (self: Players, userId: unknown) -> unknown,
	["GetPlayerFromCharacter"]: (self: Players, character: unknown) -> unknown,
	["GetPlayers"]: (self: Players) -> unknown,
	["getPlayers"]: (self: Players) -> unknown,
	["playerFromCharacter"]: (self: Players, character: unknown) -> unknown,
	["players"]: (self: Players) -> unknown,
	["BanAsync"]: (self: Players, config: unknown) -> (),
	["CreateHumanoidModelFromDescription"]: (self: Players, description: unknown, rigType: unknown, assetTypeVerification: unknown?) -> unknown,
	["CreateHumanoidModelFromDescriptionAsync"]: (self: Players, description: unknown, rigType: unknown, assetTypeVerification: unknown?) -> unknown,
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
	["GetUserThumbnailAsync"]: (self: Players, userId: unknown, thumbnailType: unknown, thumbnailSize: unknown) -> ...unknown,
	["UnbanAsync"]: (self: Players, config: unknown) -> (),
}

local Generated: Types.GeneratedClass = {
	ClassName = "Players",
	Superclass = "Instance",
	IsService = true,
	IsAbstract = true,
	Schema = {
		["BubbleChat"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["CharacterAutoLoads"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["ClassicChat"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["LocalPlayer"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["MaxPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["NumPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["PreferredPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["RespawnTime"] = { Kind = "Property", Default = nil, ReadOnly = false },
		["localPlayer"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["numPlayers"] = { Kind = "Property", Default = nil, ReadOnly = true },
		["PlayerAdded"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PlayerMembershipChanged"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["PlayerRemoving"] = { Kind = "Event", Default = nil, ReadOnly = true },
		["UserSubscriptionStatusChanged"] = { Kind = "Event", Default = nil, ReadOnly = true },
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
