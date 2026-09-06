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

	task-services-023 (LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5.1", ANTES
	de mexer aqui) acrescenta `PhysicsService` -- `Superclass: "Instance"` no dump (confirmado por
	leitura direta de `.cache/api-dump/28360dea....json`), sem puxar nenhuma classe nova pelo fecho
	de superclasses. `WorldRoot` NÃO entra aqui -- já está na lista desde a leva 1, puxada
	automaticamente pelo fecho de superclasses de `Workspace` (`Workspace -> WorldRoot -> Model ->
	... -> Instance`), exatamente como o comentário do topo deste arquivo já avisa para não
	listar. `Behavior` novo: `src/services/behavior/WorldRoot.luau` (dono do estado -- os 8 métodos
	de grupo de colisão, POR INSTÂNCIA de `Workspace`) e `src/services/behavior/PhysicsService.luau`
	(vista legada, delegando ao registro de `WorldRoot`).

	task-services-025 (LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5.3", ANTES
	de mexer aqui) acrescenta `SoundService` -- `Superclass: "Instance"` no dump (confirmado por
	leitura direta de `.cache/api-dump/28360dea....json`), sem puxar nenhuma classe nova pelo fecho
	de superclasses. 17 membros sobrevivem ao filtro (13 Property, 4 Function, 0 Event) -- cobertura
	de SUPERFÍCIE, deliberadamente sem `Behavior` próprio para a maioria: propriedades guardam e
	devolvem (dado morto, como o resto de `Lighting`), e os métodos ficam com o stub `[LuauBench]`
	do `ClassBuilder`. ÚNICA EXCEÇÃO: `PlayLocalSound` ganhou um `src/services/behavior/
	SoundService.luau` MÍNIMO (só esse método, nada mais) para errar com a string EXATA confirmada
	por citação ao vivo (pesquisa `task-services-028`): "SoundService:PlayLocalSound only works on
	a client." -- ver o cabeçalho daquele arquivo para o raciocínio completo (reabertura da decisão
	original de L2.5.3, que previa NENHUM `Behavior` para esta classe). DISCREPÂNCIA dump x doc
	registrada aqui e no relatório do gerador: `RespectFilteringEnabled` tem `Default` `"false"` no
	dump e `true` na doc oficial -- o dump vence (regra 03, fonte única), nunca "corrigido" à mão.

	task-services-019-fix (LER .claude/agents-memory/revisor-services-task-services-019-2026-09-05.md,
	achado MÉDIO, ANTES de mexer aqui) acrescenta `DataStoreKey` -- ENTRADA MANUAL, DIFERENTE de
	todas as outras acima: `DataStoreKey` tem `Superclass: "Instance"` no dump (confirmado por
	leitura direta de `.cache/api-dump/28360dea....json`), então sozinha ela NÃO puxaria nenhuma
	classe nova pelo fecho de superclasses -- mas o fecho AUTOMÁTICO (Decisão 1: anda só por
	`Superclass` a partir das sementes desta lista) nunca a DESCOBRE sozinho, porque nada no
	restante do fecho a REFERENCIA como `Superclass`/dependência: `Pages:GetCurrentPage()` e
	`DataStore:ListKeysAsync()` devolvem, no dump, `ReturnType = { Category: "Group", Name: "Array"
	}` -- um Array SEM parametrização de item (o dump não tem como dizer "Array de DataStoreKey"),
	logo o gerador (que só caminha por `Superclass`, nunca por `ValueType`/`ReturnType` de membro)
	não tem como inferir essa dependência sozinho. Isso NÃO é um bug do gerador -- é uma limitação
	estrutural do formato do dump (Array sem tipo de item), documentada em
	pesquisa-datastore-2026-09-05.md e no achado MÉDIO da revisão de task-services-019. Por isso
	`DataStoreKey` entra aqui à MÃO, como semente adicional (mesmo mecanismo de toda entrada acima
	-- só a JUSTIFICATIVA muda: não é "puxada pelo fecho automático de uma nova leva", é "puxada por
	USO PRÁTICO que o dump não consegue expressar via Superclass/tipo de retorno"). Consumidor:
	`src/services/behavior/DataStore.luau` (`ListKeysAsync`/`buildKeyItems`), que passa a devolver
	instâncias `DataStoreKey` reais (`.KeyName`) em vez de strings cruas.
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

	-- PhysicsService (task-services-023, L2.5.1) -- WorldRoot já vem pelo fecho de superclasses
	-- de Workspace, ver comentário acima.
	"PhysicsService",

	-- SoundService (task-services-025, L2.5.3) -- Superclass "Instance" direto, não puxa nada novo.
	"SoundService",

	-- DataStoreKey (task-services-019-fix) -- ENTRADA MANUAL, ver comentário acima ("task-services-
	-- 019-fix") para o porquê de não ter sido puxada pelo fecho transitivo automático.
	"DataStoreKey",
}

return Coverage
