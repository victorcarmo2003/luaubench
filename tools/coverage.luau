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

	task-services-022 (LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.2"/"L2.3",
	ANTES de mexer aqui) acrescenta `HttpService` e `MessagingService` JUNTAS, nesta mesma tarefa,
	para não rodar o gerador duas vezes -- as duas terminam em `Instance` direto (`Superclass:
	"Instance"` no dump, confirmado em pesquisa-http-messaging-2026-09-05.md, seção A), sem puxar
	nenhuma classe nova pelo fecho de superclasses. `MessagingService` já tinha `Behavior` completo
	e aprovado desde task-services-021 (`src/services/behavior/MessagingService.luau`) -- só
	faltava esta entrada para `game:GetService("MessagingService")` deixar de errar "not simulated
	yet". `HttpService` ganha `Behavior` nesta MESMA tarefa (`./behavior/HttpService.luau`):
	`JSONEncode`/`JSONDecode`/`UrlEncode`/`GenerateGUID` (sem rede) e `GetAsync`/`PostAsync`/
	`RequestAsync` errando com a família "HTTP não habilitado" -- `HttpEnabled` semeada `false` e
	`ReadOnly` pelo próprio schema gerado (Security Read=None/Write=LocalUserSecurity -> passo 5 da
	tabela A.4 do gerador, sem behavior explícito nenhum).
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

	-- HttpService + MessagingService (task-services-022, L2.2/L2.3)
	"HttpService",
	"MessagingService",
}

return Coverage
