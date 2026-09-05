--!strict

--[[
	Lista de classes-alvo da primeira leva de `services` -- a ÚNICA entrada humana do gerador
	(tools/generate-services.luau). O FECHO de superclasses é calculado automaticamente pelo
	gerador andando `Superclass` no Roblox API Dump até "Instance" -- NÃO listar aqui WorldRoot/
	Model/PVInstance (puxados a partir de Workspace) nem BasePlayerGui (puxado a partir de
	StarterGui). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 1 -- Fecho
	transitivo automático" e "Decisão 5 -- Escopo da primeira leva".

	Lista exata da leva 1 (task-services-002), na ordem em que a tarefa do board a enumera:
	árvore básica do Rojo + Scripts + Workspace/Lighting + RunService/Players.

	Leva 2 (task-services-017): as 16 classes de `DataStoreService`, listadas em
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.7". O fecho de superclasses já
	cobre tudo que elas precisam (todas terminam em Instance -> Object, nenhuma tem superclasse
	fora desta lista, exceto `Pages`, que já está listada aqui) -- confirmado por
	.claude/agents-memory/pesquisa-datastore-2026-09-05.md, seção A.
]]

local Coverage: { string } = {
	"Instance",

	-- Contêineres da árvore Rojo
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedFirst",
	"StarterPack",
	"Folder",

	-- GUI/Player containers
	"StarterGui",
	"StarterPlayer",
	"StarterPlayerScripts",
	"StarterCharacterScripts",

	-- Scripts
	"LuaSourceContainer",
	"BaseScript",
	"Script",
	"LocalScript",
	"ModuleScript",

	-- Mundo / Ambiente
	"Workspace",
	"Lighting",

	-- Comportamento real
	"RunService",
	"Players",

	-- DataStoreService (task-services-017, L2.1.7)
	"DataStoreService",
	"GlobalDataStore",
	"DataStore",
	"OrderedDataStore",
	"DataStoreKeyInfo",
	"DataStoreSetOptions",
	"DataStoreOptions",
	"DataStoreGetOptions",
	"DataStoreIncrementOptions",
	"Pages",
	"DataStorePages",
	"DataStoreKeyPages",
	"DataStoreListingPages",
	"DataStoreVersionPages",
	"DataStoreObjectVersionInfo",
	"DataStoreInfo",
}

return Coverage
