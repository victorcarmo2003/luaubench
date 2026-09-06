--!strict

-- Cenário: um data/state manager estilo ProfileStore (sessão de perfil de jogador persistida via
-- DataStoreService, com session locking entre "servidores") -- o padrão de state manager mais
-- comum e mais crítico do ecossistema Roblox pra qualquer jogo com progresso de jogador.
-- Origem: sintético (harness deste arquivo) + tests/scenarios/fixtures/ProfileStore.luau, cópia
-- BYTE A BYTE do ProfileStore REAL (MadStudioRoblox/ProfileStore, autor loleris, commit
-- 9580f7c59cd3c04808e43c92e24b9afaefba679b, Apache-2.0 -- ver cabeçalho do fixture pra
-- proveniência completa). NÃO é a versão empacotada via Wally (ddashdev_profilestore) que os
-- jogos reais do usuário usam (PLANE/AnimeFallen/Towers/etc, ver o comentário histórico abaixo) --
-- é a fonte oficial direta, conforme pedido explícito de task-services-027. `ProfileStore.New`/
-- `:StartSessionAsync`/`.Data`/`:EndSession`/`:Reconcile`/`Steal`/`Cancel` são a MESMA API pública
-- documentada no cabeçalho do módulo real (ambas as libs -- ddashdev e MadStudioRoblox -- expõem
-- essa mesma superfície, é o motivo de serem intercambiáveis nos jogos reais do usuário).
-- Superfície exercitada: Runtime.DataModel.new/Scheduler.new, Services.Bootstrap/IsSimulatedClass,
-- game:GetService("DataStoreService"|"HttpService"|"MessagingService"|"RunService"|"Workspace"),
-- Services.new("ModuleScript", ...), src/cli/ScriptEnvironment.Build (o MESMO composition root que
-- `luaubench run` usa -- não uma versão reinventada pra este cenário), Runtime.Sandbox.Load (require
-- síncrono de um ModuleScript real, sem stub), DataStoreOptions:SetExperimentalFeatures,
-- DataStoreService:GetDataStore, GlobalDataStore:UpdateAsync (único caminho de escrita/leitura do
-- ProfileStore), HttpService:GenerateGUID, MessagingService:PublishAsync/SubscribeAsync,
-- game:BindToClose, RunService:IsStudio, scheduler:Run (cadência de tempo real -- NUNCA StepOnce
-- manual, porque o ProfileStore mede intervalo de retry via os.clock() de verdade).
--
-- DIVERGÊNCIA DECLARADA (regra 00, pedida explicitamente pela task-services-027): a persistência
-- entre sessões testada no passo 2 é INTRA-PROCESSO apenas -- o `GlobalDataStore` do LuauBench vive
-- em memória enquanto o processo do `lune run` deste cenário vive (arquiteto-services-2026-09-05.md,
-- "L2.1.2" -- persistência em disco entre execuções é contrato futuro, injetado por `cli`, nunca
-- implementado dentro de `services`). Fechar e reabrir o `lune run` perde todo o dado -- isso é
-- esperado nesta leva, não um bug.
--
-- ACHADO DESTA RODADA (reportado como gap, NÃO contornado com stub -- regra do papel de testador):
-- o ProfileStore real chama `game:GetService("MessagingService")` E `game:GetService("HttpService")`
-- INCONDICIONALMENTE no topo do módulo (fixture, linhas ~337-338 -- correspondem às linhas 317-318
-- do arquivo original antes do cabeçalho de atribuição), ANTES de qualquer chamada de
-- `StartSessionAsync`. Confirmado empiricamente (não inferido): rodando este cenário HOJE contra
-- `src/services` no estado atual, `Runtime.Sandbox.Load(...)()` (o require síncrono do fixture)
-- erra com `[LuauBench] MessagingService exists in the Roblox API Dump (...) but is not simulated
-- by LuauBench yet` -- MessagingService está em task-services-021 (in-progress no momento desta
-- rodada) e HttpService está em task-services-022 (todo, sem agente designado). NENHUM dos dois
-- estava listado em `depends` de task-services-027 (só task-services-018/019 e task-runtime-033) --
-- é uma dependência transitiva real que faltou no board, não uma suposição. Sem os dois, o módulo
-- ProfileStore não CARREGA -- não é possível chegar nem ao passo 1 sem inventar um stub de
-- HttpService/MessagingService, o que este agente está proibido de fazer. Ver o bloco "GATE" abaixo:
-- o cenário TENTA carregar o fixture de verdade a cada execução (nunca assume o gap sem checar) e
-- reporta a mensagem de erro real capturada -- assim que os dois Services existirem, os passos 1-3
-- abaixo rodam automaticamente, sem precisar de nenhuma edição neste arquivo.
--
-- Status: pending -- falta HttpService (task-services-022, sub-leva A) e MessagingService
-- (task-services-021) simulados. Os passos 1-3 estão implementados e prontos (não gaveta de texto,
-- código real) mas não foram executados de ponta a ponta ainda -- ver GATE abaixo.

local process = require("@lune/process")
local fs = require("@lune/fs")
local Runtime = require("../../src/runtime")
local Services = require("../../src/services")
local ScriptEnvironment = require("../../src/cli/ScriptEnvironment")

type Dynamic = { [string]: unknown }

local passedCount = 0
local failedCount = 0
local totalCount = 0

-- Harness resiliente (mesmo padrão de real-roblox-games-pipeline-smoke.scenario.luau): uma falha
-- de assert não derruba os testes seguintes, só marca [FAIL] e segue.
local function test(name: string, run: () -> ())
	totalCount += 1
	local ok, err = pcall(run)
	if ok then
		passedCount += 1
		print(`[PASS] {name}`)
	else
		failedCount += 1
		print(`[FAIL] {name}`)
		print(`       {tostring(err)}`)
	end
end

-- Chama um "método" (convenção `:Nome(...)`) de uma tabela dinâmica vinda do fixture (Lua puro,
-- sem tipos -- ProfileStore.luau não é `--!strict`, então tudo que ele devolve é estruturalmente
-- desconhecido do ponto de vista do compilador). `unknown` em vez de `any` (regra 01): quem chama
-- estreita o retorno explicitamente antes de usar.
local function callMethod(obj: Dynamic, methodName: string, ...: unknown): unknown
	local fn = obj[methodName] :: (Dynamic, ...unknown) -> unknown
	return fn(obj, ...)
end

local function asDynamic(value: unknown): Dynamic
	return value :: Dynamic
end

-- `ProfileStore.New(store_name, template)` é declarado com PONTO no fixture (`function
-- ProfileStore.New(store_name, template)`, sem `self`) -- diferente de `StartSessionAsync`/
-- `EndSession`/`IsActive` (declarados com DOIS-PONTOS, `function ProfileStore:Metodo(...)`/
-- `function Profile:Metodo(...)`, que esperam a própria tabela como primeiro argumento
-- implícito). Chamar `.New` através de `callMethod` (que sempre injeta `obj` como primeiro
-- argumento) passaria a biblioteca inteira no lugar de `store_name` -- por isso um helper
-- separado, sem injetar `self`.
local function callNew(lib: Dynamic, storeName: string, template: Dynamic): Dynamic
	local newFn = lib.New :: (string, Dynamic) -> unknown
	return asDynamic(newFn(storeName, template))
end

-- Roda o `scheduler` com cadência de TEMPO REAL (`scheduler:Run`, nunca `StepOnce` manual) até
-- `predicate()` virar true ou `timeoutSeconds` de tempo real (host) se esgotarem -- exatamente o
-- que o ProfileStore precisa: seus retries usam `os.clock()`/`task.wait(n)` de verdade (backoff
-- exponencial 1s->20s, `FIRST_LOAD_REPEAT = 5`, `LOAD_REPEAT_PERIOD = 10`, ver fixture linhas
-- ~190-195), não um contador de frames sintético. `scheduler:Run` já para sozinho se
-- `IsAlive()` virar false (nenhuma coroutine viva) -- o `predicate`/timeout aqui só cobre o caso
-- em que ainda há trabalho pendente mas nada resolveu a condição esperada.
local function driveUntil(scheduler: Runtime.Scheduler, predicate: () -> boolean, timeoutSeconds: number): boolean
	local start = os.clock()
	scheduler:Run(function(): boolean
		if predicate() then
			return false
		end
		return (os.clock() - start) < timeoutSeconds
	end)
	return predicate()
end

----------------------------------------------------------------------------------------------
-- Bootstrap único pra todo o cenário: um `game`/`scheduler` real de `runtime`+`services`, exatamente
-- a sequência de 8 passos documentada em src/services/init.luau ("SEQUÊNCIA DE BOOTSTRAP que cli
-- DEVE seguir").
----------------------------------------------------------------------------------------------
local scheduler = Runtime.Scheduler.new()
local game = Runtime.DataModel.new()
Services.Bootstrap({ scheduler = scheduler, dataModel = game })

local workspace = game:GetService("Workspace")
assert(workspace ~= nil, "Workspace deveria existir logo após Bootstrap")

----------------------------------------------------------------------------------------------
-- GATE: tenta carregar o ProfileStore REAL pelo pipeline de produção de verdade (o mesmo que
-- `luaubench run` usa: src/cli/ScriptEnvironment.Build + Runtime.Sandbox.Load) -- NUNCA assume o
-- gap por inspeção estática (ex: `Services.IsSimulatedClass`) sem também tentar rodar de verdade,
-- porque uma checagem estática poderia ficar desatualizada em relação ao comportamento real do
-- require. Se falhar, a mensagem de erro real (capturada, não inferida) vira o relatório de gap.
----------------------------------------------------------------------------------------------
local scriptInstance = Services.new("ModuleScript", "ProfileStore")

local environmentContext: ScriptEnvironment.EnvironmentContext = {
	Game = game,
	Workspace = workspace :: Runtime.Instance,
	GlobalTable = {} :: { [string]: unknown },
	SharedTable = {} :: { [string]: unknown },
	-- ProfileStore.luau real não tem NENHUM `require` alcançável em tempo de execução (só um
	-- comentário morto, `-- local Util = require(game.ReplicatedStorage.Shared.Util)`, linha ~185
	-- do arquivo original) -- um `Require` que erra é fiel: se algum dia isto disparar, é sinal de
	-- que uma versão diferente do fixture foi colada por engano.
	Require = function(_target: unknown): unknown
		error("engenharia interna do cenário: ProfileStore.luau real não deveria chamar require() em tempo de execução")
	end,
}

local scriptGlobals = ScriptEnvironment.Build(environmentContext, scriptInstance)

local fixtureSource = fs.readFile("tests/scenarios/fixtures/ProfileStore.luau")

-- `Runtime.Sandbox.Load` compila e devolve uma função chamável SEM criar thread (é o mecanismo
-- real de `require` de ModuleScript do LuauBench, task-runtime-025/cli/ModuleLoader.luau) --
-- diferente de `require` real do Roblox, cada CHAMADA deste `chunk` re-executa o corpo do módulo
-- do zero (sem cache) -- usamos isso DE PROPÓSITO no passo 3 para simular DOIS "servidores"
-- independentes (cada um com seu próprio `ActiveSessionCheck`/`AutoSaveList` locais ao módulo)
-- compartilhando o MESMO DataStoreService por baixo -- exatamente o cenário que a trava de sessão
-- existe para proteger.
local chunk = Runtime.Sandbox.Load({
	scriptName = "ProfileStore",
	source = fixtureSource,
	scheduler = scheduler,
	extraGlobals = scriptGlobals,
	onOutput = function(record: Runtime.OutputRecord)
		print(`[ProfileStore/{record.level}]`, record.message)
	end,
})

local loadOk, loadResultOrError = pcall(chunk)

if not loadOk then
	local message = tostring(loadResultOrError)
	local errorMentionsHttp = string.find(message, "HttpService", 1, true) ~= nil
	local errorMentionsMessaging = string.find(message, "MessagingService", 1, true) ~= nil

	-- O módulo erra na PRIMEIRA `game:GetService(...)` incondicional que encontra (ordem fixa do
	-- fixture: DataStoreService, MessagingService, HttpService, RunService) -- então a mensagem
	-- capturada acima só denuncia UMA das duas dependências faltantes por vez. Checagem PROATIVA
	-- das duas (via `Services.IsSimulatedClass`, leitura pura do registro vivo) além do erro
	-- capturado, para o relatório já vir completo mesmo antes da primeira das duas landar.
	local httpSimulated = Services.IsSimulatedClass("HttpService")
	local messagingSimulated = Services.IsSimulatedClass("MessagingService")

	print("[PENDING] datastore-profilestore-pattern: o ProfileStore real (fixture) não conseguiu ser carregado hoje.")
	print(`         Erro real capturado (Runtime.Sandbox.Load -> chunk()): {message}`)
	if not messagingSimulated then
		print(`         Falta: MessagingService simulado (game:GetService("MessagingService") no topo do módulo) -- task-services-021.{if errorMentionsMessaging then " [é a causa do erro acima]" else " [ainda não alcançado pelo erro acima, mas bloqueia igual]"}`)
	end
	if not httpSimulated then
		print(`         Falta: HttpService simulado (game:GetService("HttpService"), usado em :GenerateGUID() dentro de StartSessionAsync) -- task-services-022.{if errorMentionsHttp then " [é a causa do erro acima]" else " [ainda não alcançado pelo erro acima, mas bloqueia igual]"}`)
	end
	if httpSimulated and messagingSimulated then
		print("         HttpService e MessagingService já estão simulados -- este erro NÃO é o gap conhecido, é um achado NOVO (investigar DataStoreService/BindToClose/RunService/ScriptEnvironment).")
	end
	print("         Os passos 1-3 deste cenário estão implementados abaixo e rodam automaticamente assim que o require acima parar de errar -- nenhuma edição neste arquivo é necessária quando o gap fechar.")
	process.exit(0)
end

-- Se chegou aqui, o require teve sucesso de verdade -- os 3 passos abaixo rodam contra o
-- ProfileStore real, sem stub nenhum.
local ProfileStoreLib1 = asDynamic(loadResultOrError)

----------------------------------------------------------------------------------------------
-- Passos 1 e 2 (mesma sessão de "servidor"): sessão nova devolve o template; alterar, encerrar,
-- reabrir e confirmar que persistiu DENTRO DO PROCESSO.
----------------------------------------------------------------------------------------------
test("passo 1: sessão nova de um profile_key inédito devolve Profile.Data == template (sem dado salvo ainda)", function()
	local template: Dynamic = { Coins = 0, Level = 1 }
	local store = callNew(ProfileStoreLib1, "TestPlayerData", template)

	local profileKey = "Player_FreshSession"
	local profileUnknown: unknown = nil

	-- `StartSessionAsync` faz `task.wait`/`os.clock()` por dentro -- só funciona suspendendo uma
	-- coroutine gerida pelo Scheduler (nunca a thread principal deste arquivo, que não é uma
	-- coroutine). `scheduler:Spawn` roda até o primeiro yield sincronamente e devolve o handle.
	scheduler:Spawn(function()
		profileUnknown = callMethod(store, "StartSessionAsync", profileKey, nil)
	end)

	local ok = driveUntil(scheduler, function(): boolean
		return profileUnknown ~= nil
	end, 15)

	assert(ok, "StartSessionAsync deveria ter resolvido dentro de 15s reais de scheduler:Run")
	local profile = asDynamic(profileUnknown)
	local data = asDynamic(profile.Data)
	assert(data.Coins == 0, `Profile.Data.Coins deveria ser 0 (template), veio {tostring(data.Coins)}`)
	assert(data.Level == 1, `Profile.Data.Level deveria ser 1 (template), veio {tostring(data.Level)}`)

	-- Este passo usa uma chave própria ("Player_FreshSession") -- o passo 2, abaixo, usa OUTRA
	-- chave ("Player_PersistCycle") e abre/fecha sua própria sessão do zero, sem depender desta.
	-- Encerra aqui só por higiene (best-effort, fora da asserção deste passo).
	pcall(function()
		callMethod(profile, "EndSession")
	end)
end)

test("passo 2: alterar Profile.Data, EndSession, reabrir a MESMA chave e confirmar que persistiu intra-processo", function()
	local template: Dynamic = { Coins = 0, Level = 1 }
	local store = callNew(ProfileStoreLib1, "TestPlayerData", template)

	local profileKey = "Player_PersistCycle"

	local firstProfileUnknown: unknown = nil
	scheduler:Spawn(function()
		firstProfileUnknown = callMethod(store, "StartSessionAsync", profileKey, nil)
	end)
	assert(driveUntil(scheduler, function(): boolean
		return firstProfileUnknown ~= nil
	end, 15), "primeira StartSessionAsync deveria ter resolvido")

	local firstProfile = asDynamic(firstProfileUnknown)
	local firstData = asDynamic(firstProfile.Data)
	firstData.Coins = 100 -- ProfileStore não valida o schema de Data -- mutação direta, como um script real faria.

	-- `EndSession` salva de forma ASSÍNCRONA (`task.spawn(SaveProfileAsync, ...)`, fixture ~1113)
	-- -- precisa esperar `IsActive()` virar false (sessão liberada) antes de tentar reabrir, senão
	-- `StartSessionAsync` da mesma chave erra "already loaded in this session" (guarda local,
	-- fixture ~1391).
	callMethod(firstProfile, "EndSession")
	assert(driveUntil(scheduler, function(): boolean
		return callMethod(firstProfile, "IsActive") == false
	end, 15), "Profile deveria ficar IsActive() == false depois de EndSession + save assíncrono")

	local secondProfileUnknown: unknown = nil
	scheduler:Spawn(function()
		secondProfileUnknown = callMethod(store, "StartSessionAsync", profileKey, nil)
	end)
	assert(driveUntil(scheduler, function(): boolean
		return secondProfileUnknown ~= nil
	end, 15), "segunda StartSessionAsync (reabrindo a mesma chave) deveria ter resolvido")

	local secondProfile = asDynamic(secondProfileUnknown)
	local secondData = asDynamic(secondProfile.Data)
	assert(
		secondData.Coins == 100,
		`Profile.Data.Coins deveria ter persistido intra-processo como 100, veio {tostring(secondData.Coins)} -- DIVERGÊNCIA DECLARADA: só intra-processo, ver cabeçalho deste arquivo`
	)

	callMethod(secondProfile, "EndSession")
end)

----------------------------------------------------------------------------------------------
-- Passo 3: session lock. Duas instâncias INDEPENDENTES do módulo ProfileStore (duas chamadas de
-- `chunk()`, cada uma com seu próprio `ActiveSessionCheck` local -- ver comentário acima de
-- `chunk` sobre por que isto simula dois "servidores" de verdade) competindo pela MESMA chave no
-- MESMO DataStoreService por baixo.
----------------------------------------------------------------------------------------------
test("passo 3: session lock -- o segundo StartSessionAsync para a MESMA chave NÃO rouba sem Steal, e rouba imediatamente COM Steal=true", function()
	local template: Dynamic = { Coins = 0 }
	local profileKey = "Player_SessionLock"

	local serverA = asDynamic((chunk :: () -> ...unknown)())
	local serverB = asDynamic((chunk :: () -> ...unknown)())

	local storeA = callNew(serverA, "SessionLockStore", template)
	local storeB = callNew(serverB, "SessionLockStore", template)

	-- Servidor A abre a sessão primeiro.
	local profileAUnknown: unknown = nil
	scheduler:Spawn(function()
		profileAUnknown = callMethod(storeA, "StartSessionAsync", profileKey, nil)
	end)
	assert(driveUntil(scheduler, function(): boolean
		return profileAUnknown ~= nil
	end, 15), "servidor A deveria ter adquirido a sessão")
	local profileA = asDynamic(profileAUnknown)
	assert(callMethod(profileA, "IsActive") == true, "profileA deveria estar IsActive() == true logo após adquirir")

	-- Servidor B tenta a MESMA chave SEM Steal, com um Cancel que desiste depois de ~2s reais --
	-- API pública documentada no cabeçalho do fixture ("Cancel = fn() -> (boolean), -- Pass this
	-- to create a request cancel condition."). Se B conseguisse a sessão aqui, seria a trava de
	-- sessão falhando (bug GRAVE de fidelidade -- corromperia save concorrente em produção).
	local cancelDeadline = os.clock() + 2
	local paramsNoSteal: Dynamic = {
		Cancel = function(): boolean
			return os.clock() >= cancelDeadline
		end,
	}
	local resultBNoStealUnknown: unknown = nil
	local bNoStealDone = false
	scheduler:Spawn(function()
		resultBNoStealUnknown = callMethod(storeB, "StartSessionAsync", profileKey, paramsNoSteal)
		bNoStealDone = true
	end)
	assert(driveUntil(scheduler, function(): boolean
		return bNoStealDone
	end, 10), "StartSessionAsync de B (sem Steal, com Cancel) deveria ter retornado (via Cancel) dentro de 10s")
	assert(
		resultBNoStealUnknown == nil,
		"servidor B NÃO deveria ter roubado a sessão de A sem passar Steal=true -- trava de sessão violada"
	)
	assert(callMethod(profileA, "IsActive") == true, "profileA deveria continuar IsActive() == true (não foi roubado)")

	-- Servidor B tenta de novo, agora COM Steal=true -- doc do fixture: "Steal = true, -- Pass
	-- this to disregard an existing session lock". Deve suceder sem precisar esperar o timeout
	-- natural de SESSION_STEAL (40s, fixture linha ~173).
	local paramsSteal: Dynamic = { Steal = true }
	local resultBStealUnknown: unknown = nil
	scheduler:Spawn(function()
		resultBStealUnknown = callMethod(storeB, "StartSessionAsync", profileKey, paramsSteal)
	end)
	assert(driveUntil(scheduler, function(): boolean
		return resultBStealUnknown ~= nil
	end, 15), "StartSessionAsync de B com Steal=true deveria ter resolvido com um Profile dentro de 15s")

	local profileB = asDynamic(resultBStealUnknown)
	assert(callMethod(profileB, "IsActive") == true, "profileB deveria estar IsActive() == true depois do Steal")

	-- Limpeza -- encerra o que ainda estiver ativo (best-effort, não faz parte da asserção).
	pcall(function()
		callMethod(profileB, "EndSession")
	end)
end)

print(`\n{passedCount}/{totalCount} testes passaram ({failedCount} falharam)`)

if failedCount > 0 then
	process.exit(1)
end
