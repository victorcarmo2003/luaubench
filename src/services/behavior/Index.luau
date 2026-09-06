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
	`DataStore`/`OrderedDataStore`/`Pages`/as classes de paginação NÃO entram nesta leva (sub-leva
	B: `GetVersionAsync`/`ListVersionsAsync`/`ListKeysAsync`/`GetSortedAsync`, fora do território de
	task-services-018) -- ficam SEM entrada aqui, cobertas pelo stub `[LuauBench]` do `ClassBuilder`
	método a método (a HERANÇA de `GlobalDataStore` continua funcionando para `DataStore`/
	`OrderedDataStore` mesmo sem entrada própria neste mapa -- ver cabeçalho de
	`./GlobalDataStore.luau`).

	Todas as outras classes desta e da leva anterior continuam registradas por
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
}

return BehaviorIndex
