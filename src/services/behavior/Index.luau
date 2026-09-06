--!strict

--[[
	Mapa `ClassName -> Behavior`, escrito À MÃO de propósito (não gerado -- o gerador nunca deve
	poder apagar esta lista curada). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md,
	seção "Módulos" -> "src/services/behavior/Index.luau": "É a lista curada do que tem
	comportamento, e o gerador nunca deve poder apagá-la."

	task-services-003 (primeira leva de classes reais: contêineres da árvore Rojo + Scripts +
	Workspace + Lighting) — LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5"
	antes de mexer aqui.

	A imensa maioria das 24 classes desta leva é contêiner puro (ReplicatedStorage tem
	`Members == []` no dump, por exemplo) e legitimamente dispensa `Behavior` — `ClassBuilder.Build`
	já cobre todo `MethodNames` sem implementação com o stub `[LuauBench] ... not simulated by
	LuauBench yet` (regra 03: nunca stub silencioso). Isso é o esperado, não uma lacuna desta
	tarefa.

	`StarterPlayer` é a ÚNICA classe da leva anterior (task-services-003) com `Behavior` de
	verdade: `Initialize` cria os filhos fixos `StarterPlayerScripts`/`StarterCharacterScripts`
	(ver `./StarterPlayer.luau`).

	HISTÓRICO (retomada de task-services-003): na primeira passada daquela tarefa, este mapa
	ficou vazio e `StarterPlayer` não pôde ser escrito -- `Runtime.ClassRegistry.new`, o ÚNICO
	criador de instância que `services` tinha acesso, rejeitava `IsAbstract == true`
	INCONDICIONALMENTE, e `StarterPlayer`/`StarterPlayerScripts`/`StarterCharacterScripts` são
	todas `NotCreatable` no dump (fiel ao Roblox real, onde também não dá para
	`Instance.new("StarterPlayer")`). Isso bloqueava tanto `game:GetService("StarterPlayer")`
	quanto a criação dos filhos fixos por QUALQUER caminho, tornando um `Initialize` aqui código
	morto e intestável (regra 01: teste na MESMA tarefa da lógica que cobre). `task-runtime-023`
	resolveu o bloqueio separando a política de "script não pode `Instance.new` isto" (que
	continua em `ClassRegistry.new`, a via pública) da construção do motor
	(`ClassRegistry.NewEngineInstance`, nova via SEM essa guarda, usada por `DataModel.GetService`
	e -- agora -- por `./StarterPlayer.luau`). Ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração 2026-09-05
	(4)", para o desenho completo do fix.

	task-services-004 (RunService/Players -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5" e "Fidelidade vs.
	pragmatismo", e a seção "Revisão pós-integração 2026-09-05 -- Capabilities e RenderStepped",
	parte B, antes de mexer aqui) adiciona as duas próximas entradas com `Behavior` de verdade:
	- `RunService` (ver `./RunService.luau`): `Initialize` liga `Heartbeat`/`Stepped` ao Signal
	  REAL do `Scheduler` corrente (via `Context.GetScheduler()`) e instala um
	  `RejectingSignal` (`../RejectingSignal.luau`, módulo novo desta tarefa) sobre
	  `RenderStepped`. `Methods` cobre `IsServer`/`IsClient`/`IsStudio`/`IsRunning`.
	- `Players` (ver `./Players.luau`): `Methods` cobre `GetPlayers`/`GetPlayerByUserId`/
	  `GetPlayerFromCharacter` com o resultado honesto de um mundo sem jogadores (`{}`/`nil`).
	  SEM `Initialize` -- `LocalPlayer`/`PlayerAdded`/`PlayerRemoving` já ficam corretos só com o
	  que o schema gerado semeia sozinho (ver comentário completo em `./Players.luau`).

	task-services-024 (`Lighting` -- LER .claude/agents-memory/arquiteto-services-2026-09-05.md,
	seção "L2.5.2", antes de mexer aqui) adiciona a quarta entrada com `Behavior` de verdade:
	- `Lighting` (ver `./Lighting.luau`): `Initialize` conecta em `instance.Changed` para manter
	  `ClockTime`/`TimeOfDay`/minutos como três vistas do mesmo estado sincronizadas, e dispara
	  `LightingChanged` para toda propriedade do schema exceto as quatro exclusões documentadas
	  oficialmente (`GlobalShadows`/`FogColor`/`FogStart`/`FogEnd`). `Methods` cobre
	  `Get`/`SetMinutesAfterMidnight` e `GetMoonPhase` (sempre `0.75`); `GetSunDirection`/
	  `GetMoonDirection` permanecem com o stub `[LuauBench]` do `ClassBuilder` de propósito (sem
	  fórmula pública, ver o cabeçalho de `Lighting.luau`).

	task-services-018 (`DataStoreService`/`GlobalDataStore`/`DataStoreKeyInfo`/as 3 classes de
	options -- LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3" a "L2.1.7",
	antes de mexer aqui) adiciona seis entradas:
	- `DataStoreService` (ver `./DataStoreService.luau`): `Methods` cobre `GetDataStore`/
	  `GetGlobalDataStore`/`GetOrderedDataStore` (memoizados por `(name, scope)`, um cache
	  compartilhado por `Kind`) e `GetRequestBudgetForRequestType`/`SetRateLimitForRequestType`
	  (constante fixa/no-op). `ListDataStoresAsync` fica com o stub `[LuauBench]`.
	- `GlobalDataStore` (ver `./GlobalDataStore.luau`): `Methods` cobre `GetAsync`/`SetAsync`/
	  `UpdateAsync`/`RemoveAsync`/`IncrementAsync` (herdados por `DataStore`/`OrderedDataStore` via
	  o achatamento de classe do `runtime`) -- todo yield passa por `../AsyncCall.luau`, toda
	  validação/versionamento por `../datastore/Value.luau`/`../datastore/Store.luau`. `OnUpdate`/
	  `BatchGetAsync` ficam com o stub `[LuauBench]`.
	- `DataStoreKeyInfo` (ver `./DataStoreKeyInfo.luau`): `Methods` cobre `GetMetadata`/
	  `GetUserIds`; a fábrica `New` (fora do contrato `Types.Behavior`, consumida direto por
	  `./GlobalDataStore.luau`) constrói a instância e escreve `CreatedTime`/`UpdatedTime`/`Version`
	  via `SetPropertyRaw`.
	- `DataStoreOptions` (ver `./DataStoreOptions.luau`): `SetExperimentalFeatures` no-op (o
	  `ProfileStore` chama sempre).
	- `DataStoreSetOptions`/`DataStoreIncrementOptions` (ver `./DataStoreSetOptions.luau`/
	  `./DataStoreIncrementOptions.luau`): `GetMetadata`/`SetMetadata`, metadata como estado
	  privado por instância (nenhuma propriedade no schema gerado das duas).
	task-services-019 (sub-leva B: `GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync` + a família
	`Pages` -- LER .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6", antes
	de mexer aqui) adiciona mais DUAS entradas:
	- `DataStore` (ver `./DataStore.luau`): `Methods` cobre `GetVersionAsync`/`ListVersionsAsync`/
	  `ListKeysAsync`, construídos EM CIMA do `Store` singleton de `./GlobalDataStore.luau`
	  (exportado a partir desta tarefa). `GetVersionAtTimeAsync`/`RemoveVersionAsync` (Deprecated)
	  ficam com o stub `[LuauBench]`.
	- `Pages` (ver `./Pages.luau`): `Methods` cobre `GetCurrentPage`/`AdvanceToNextPageAsync` (a
	  fábrica `New`, fora do contrato `Types.Behavior`, consumida por `./DataStore.luau`, fatia um
	  buffer completo de itens em páginas) -- via o achatamento de classe do `runtime`, os mesmos
	  dois métodos ficam disponíveis em `DataStoreVersionPages`/`DataStoreKeyPages`/
	  `DataStoreListingPages`/`DataStorePages` sem entrada própria para cada uma.
	`OrderedDataStore` continuou SEM entrada própria em task-services-019 (`GetSortedAsync` ficou com
	o stub `[LuauBench]`, fora daquele território) -- a herança de `GlobalDataStore` continuou
	funcionando para ela mesmo assim.

	task-services-020 (`OrderedDataStore`/`GetSortedAsync` -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3", antes de mexer aqui) adiciona a
	entrada que faltava:
	- `OrderedDataStore` (ver `./OrderedDataStore.luau`): `Methods` cobre só `GetSortedAsync` (o
	  ÚNICO membro que `generated/classes/OrderedDataStore.luau` declara -- `SetAsync`/
	  `UpdateAsync`/`IncrementAsync`/`RemoveAsync`/`GetAsync` continuam herdados de
	  `GlobalDataStore` via achatamento de classe, sem entrada própria aqui). A validação "valor
	  precisa ser INTEIRO" que essa herança precisa ganhar para `OrderedDataStore` foi acrescentada
	  DENTRO de `./GlobalDataStore.luau` (gated por `self.ClassName`) -- `ClassBuilder.Build` não
	  permite registrar, no `behavior.Methods` de `OrderedDataStore`, uma chave que não está no
	  `MethodNames` DELA MESMA (só `GetSortedAsync`) -- ver o cabeçalho de `./GlobalDataStore.luau`,
	  seção "task-services-020", para o raciocínio completo. `RemoveAsync` também não muda (continua
	  herdado, tombstone por baixo) -- a "remoção permanente" exigida pelo despacho da tarefa é
	  observacionalmente garantida porque `OrderedDataStore` nunca ganha `GetVersionAsync`/
	  `ListVersionsAsync` (membros de "DataStore", fora da sua cadeia de superclasses).

	task-services-021 (`MessagingService` -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.3", e `./MessagingService.luau`,
	cabeçalho, ANTES de mexer aqui) adiciona a entrada:
	- `MessagingService` (ver `./MessagingService.luau`): `Methods` cobre `PublishAsync`/
	  `SubscribeAsync` (a superfície INTEIRA da classe no dump -- nenhuma propriedade, nenhum
	  evento). NA ÉPOCA de task-services-021, `MessagingService` ainda não estava em
	  `tools/coverage.luau` nem em `generated/**` -- essa lacuna foi FECHADA por task-services-022
	  (abaixo), que acrescentou a classe ao gerador. Esta entrada, que já existia pronta desde
	  task-services-021, ficou automaticamente ATIVA nesse momento -- nenhuma mudança neste arquivo
	  foi necessária para isso.

	task-services-022 (`HttpService` sub-leva A + registro de `MessagingService` no gerador -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.2", e `./HttpService.luau`,
	cabeçalho, ANTES de mexer aqui) fez DUAS coisas:
	1. Acrescentou `HttpService`/`MessagingService` a `tools/coverage.luau` e rodou
	   `lune run tools/generate-services` -- `generated/classes/MessagingService.luau` e
	   `generated/classes/HttpService.luau` passaram a existir, e `game:GetService(...)` das duas
	   classes deixou de errar `[LuauBench] ... not simulated by LuauBench yet` (o bloqueio
	   reportado em task-services-021 está FECHADO).
	2. Adicionou esta última entrada:
	- `HttpService` (ver `./HttpService.luau`): `Methods` cobre `JSONEncode`/`JSONDecode`/
	  `UrlEncode`/`GenerateGUID` (sem rede, funcionam com `HttpEnabled == false`) e
	  `GetAsync`/`PostAsync`/`RequestAsync` (erram com a família "HTTP não habilitado" -- SEM
	  REDE nesta sub-leva, `@lune/net` nunca é `require`d). `HttpEnabled` (Property) NÃO precisa de
	  `Initialize` NESTA sub-leva -- o schema gerado já semeia `false`/`ReadOnly` sozinho (ver
	  cabeçalho de `./HttpService.luau`). `GetSecret`/`CreateWebStreamClient` ficam com o stub
	  `[LuauBench]` do `ClassBuilder`, de propósito. **Ver task-services-026, abaixo -- esta
	  afirmação de "NÃO precisa de Initialize" deixa de valer a partir de lá.**

	task-services-026 (`HttpService` sub-leva B: rede real via `@lune/net` -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.2.2"/"L2.2.4"/"L2.2.5", e
	`./HttpService.luau`, cabeçalho, ANTES de mexer aqui) NÃO adiciona entrada nova (continua
	sendo a mesma entrada `HttpService` de task-services-022, atualizada) -- mas MUDA sua forma:
	- `HttpService` (ver `./HttpService.luau`) GANHA `Initialize`: lê `Context.IsHttpAllowed()`
	  (novo campo `BootstrapOptions.AllowHttp`, populado por `cli` a partir de `--allow-http`) e,
	  se `true`, sobrescreve `HttpEnabled` para `true` via `SetPropertyRaw` -- só então
	  `GetAsync`/`PostAsync`/`RequestAsync` deixam de errar "not enabled" e passam a fazer
	  requisição REAL sobre `net.request`, atrás também de um endurecimento de destino (loopback/
	  link-local/privado recusado sem `AllowHttpLocal`). Sem a flag, o comportamento continua
	  IDÊNTICO ao de task-services-022 (HttpEnabled `false`, três métodos errando "not enabled").
	  `Methods` continua com a MESMA lista de nomes (`JSONEncode`/`JSONDecode`/`UrlEncode`/
	  `GenerateGUID`/`GetAsync`/`PostAsync`/`RequestAsync`) -- só o CORPO de `GetAsync`/
	  `PostAsync`/`RequestAsync` mudou, de "sempre erra" para "erra sem a permissão, requisita de
	  verdade com ela".

	task-services-023 (`CollisionGroups`/`WorldRoot`/`PhysicsService` -- LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5.1", e
	.claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md, item 3, ANTES de mexer
	aqui) adiciona as duas últimas entradas:
	- `WorldRoot` (ver `./WorldRoot.luau`): DONA do estado -- `Methods` cobre os oito métodos de
	  grupo de colisão (`RegisterCollisionGroup`/`UnregisterCollisionGroup`/
	  `IsCollisionGroupRegistered`/`RenameCollisionGroup`/`GetRegisteredCollisionGroups`/
	  `GetMaxCollisionGroups`/`CollisionGroupSetCollidable`/`CollisionGroupsAreCollidable`), um
	  `../CollisionGroups.luau` `Registry` POR INSTÂNCIA (get-or-create preguiçoso via
	  `../InstanceState`, SEM `Initialize` -- `Runtime.ClassRegistry.NewEngineInstance` só chama o
	  `Initialize` da classe EXATA "Workspace", nunca o de uma superclasse no meio da cadeia; só
	  `Methods`/`Schema` são achatados pela cadeia inteira, ver cabeçalho de `./WorldRoot.luau` para
	  o raciocínio completo). É A PRIMEIRA VEZ que `Workspace` ganha comportamento de verdade --
	  antes desta tarefa não havia entrada nenhuma para ela neste mapa. `getRegistry` é exportado
	  ALÉM do contrato `Types.Behavior` (mesmo padrão de `StoreIdState` em `./GlobalDataStore.luau`)
	  para `./PhysicsService.luau` reusar o MESMO registro.
	- `PhysicsService` (ver `./PhysicsService.luau`): vista LEGADA -- os MESMOS oito métodos,
	  DELEGANDO ao `Registry` da instância de `Workspace` corrente (`Context.GetDataModel():GetService("Workspace")`
	  + `WorldRoot.GetRegistry(...)`), nunca criando um registro próprio -- é o que garante que
	  `PhysicsService:RegisterCollisionGroup("X")` e `workspace:IsCollisionGroupRegistered("X")`
	  enxerguem o MESMO estado. Os 7 métodos `Deprecated` (`CreateCollisionGroup`/
	  `GetCollisionGroupId`/`GetCollisionGroupName`/`GetCollisionGroups`/`RemoveCollisionGroup`/
	  `SetPartCollisionGroup`/`CollisionGroupContainsPart`) ficam com o stub `[LuauBench]` do
	  `ClassBuilder`, de propósito -- ver cabeçalho de `./PhysicsService.luau` para a razão de cada
	  um (modelo de id numérico abandonado, ou dependência de `BasePart`, não coberta).

	Todas as outras classes desta e das levas anteriores continuam registradas por
	`Services.Register()` (ver ../init.luau) SEM Behavior — contêiner puro, nenhuma precisa de
	`Initialize`/`Methods` próprio.
]]

local Types = require("../Types")

local BehaviorIndex: { [string]: Types.Behavior } = {
	StarterPlayer = require("./StarterPlayer") :: Types.Behavior,
	RunService = require("./RunService") :: Types.Behavior,
	Players = require("./Players") :: Types.Behavior,
	Lighting = require("./Lighting") :: Types.Behavior,
	DataStoreService = require("./DataStoreService") :: Types.Behavior,
	GlobalDataStore = require("./GlobalDataStore") :: Types.Behavior,
	DataStoreKeyInfo = require("./DataStoreKeyInfo") :: Types.Behavior,
	DataStoreOptions = require("./DataStoreOptions") :: Types.Behavior,
	DataStoreSetOptions = require("./DataStoreSetOptions") :: Types.Behavior,
	DataStoreIncrementOptions = require("./DataStoreIncrementOptions") :: Types.Behavior,
	DataStore = require("./DataStore") :: Types.Behavior,
	Pages = require("./Pages") :: Types.Behavior,
	OrderedDataStore = require("./OrderedDataStore") :: Types.Behavior,
	MessagingService = require("./MessagingService") :: Types.Behavior,
	HttpService = require("./HttpService") :: Types.Behavior,
	WorldRoot = require("./WorldRoot") :: Types.Behavior,
	PhysicsService = require("./PhysicsService") :: Types.Behavior,
}

return BehaviorIndex
