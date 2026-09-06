--!strict

--[[
	Teste de task-services-003 para `src/services/behavior/Index.luau`, ATUALIZADO por
	task-services-004, task-services-024, task-services-018, task-services-019 e task-services-020.
	O mapa deixou de estar vazio na retomada de task-services-003 (ver o cabeçalho de `Index.luau`,
	seção "HISTÓRICO", para o porquê) com UMA entrada (`StarterPlayer`), ganhou mais DUAS em
	task-services-004 (`RunService`/`Players`), mais UMA em task-services-024 (`Lighting`), mais
	SEIS em task-services-018 (`DataStoreService`/`GlobalDataStore`/`DataStoreKeyInfo`/
	`DataStoreOptions`/`DataStoreSetOptions`/`DataStoreIncrementOptions`), mais DUAS em
	task-services-019 (`DataStore`/`Pages`) e mais UMA em task-services-020 (`OrderedDataStore`) --
	13 entradas ao todo. `Initialize`/`Methods` de cada uma (cobertura de comportamento própria) é
	testado em `./StarterPlayer.spec.luau`/`./RunService.spec.luau`/`./Players.spec.luau`/
	`./Lighting.spec.luau`/`./DataStoreService.spec.luau`/`./GlobalDataStore.spec.luau`/
	`./DataStoreKeyInfo.spec.luau`/`./DataStoreOptions.spec.luau`/`./DataStoreSetOptions.spec.luau`/
	`./DataStoreIncrementOptions.spec.luau`/`./DataStore.spec.luau`/`./Pages.spec.luau`/
	`./OrderedDataStore.spec.luau`. Este arquivo cobre só a FORMA do mapa (tipado corretamente,
	requerível, exatamente as entradas esperadas -- nem mais nem menos) e que `Services.Register()`
	(src/services/init.luau) consegue iterar `generated/Index.luau` cruzando com este mapa sem erro
	-- essa segunda parte já está coberta em `../Integration.spec.luau` (24 classes registradas com
	sucesso, `StarterPlayer` nascendo com os dois filhos fixos, e `RunService`/`Players` alcançáveis
	por `GetService`) e em `../init.spec.luau`, não duplicada aqui.

	Roda com `lune run src/services/behavior/Index.spec.luau`.
]]

local process = require("@lune/process")
local BehaviorIndex = require("./Index")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("behavior/Index.luau tem EXATAMENTE 13 entradas até esta leva: StarterPlayer, RunService, Players, Lighting, DataStoreService, GlobalDataStore, DataStoreKeyInfo, DataStoreOptions, DataStoreSetOptions, DataStoreIncrementOptions, DataStore, Pages, OrderedDataStore", function()
	local count = 0
	for _ in BehaviorIndex do
		count += 1
	end
	assert(count == 13, `esperava 13 entradas até esta leva (ver cabeçalho de Index.luau), recebeu {count}`)
end)

test("behavior/Index.luau['StarterPlayer'] existe e tem Initialize; classes-contêiner puro continuam sem entrada", function()
	local starterPlayerBehavior = BehaviorIndex["StarterPlayer"]
	assert(starterPlayerBehavior ~= nil, "StarterPlayer deveria ter Behavior nesta retomada (task-runtime-023 destravou NewEngineInstance)")
	assert(starterPlayerBehavior.Initialize ~= nil, "StarterPlayer.Initialize deveria existir -- é o que cria os 2 filhos fixos")
	assert(BehaviorIndex["Folder"] == nil, "Folder é contêiner puro -- nunca deveria ter Behavior")
	assert(BehaviorIndex["ReplicatedStorage"] == nil, "ReplicatedStorage é contêiner puro (Members == [] no dump) -- nunca deveria ter Behavior")
end)

test("behavior/Index.luau['RunService'] existe, tem Initialize e Methods (task-services-004)", function()
	local runServiceBehavior = BehaviorIndex["RunService"]
	assert(runServiceBehavior ~= nil, "RunService deveria ter Behavior a partir de task-services-004")
	assert(runServiceBehavior.Initialize ~= nil, "RunService.Initialize deveria existir -- liga Heartbeat/Stepped ao Scheduler e instala o RejectingSignal de RenderStepped")
	assert(runServiceBehavior.Methods ~= nil, "RunService.Methods deveria existir -- IsServer/IsClient/IsStudio/IsRunning")
end)

test("behavior/Index.luau['Players'] existe, tem Methods e NENHUM Initialize (task-services-004)", function()
	local playersBehavior = BehaviorIndex["Players"]
	assert(playersBehavior ~= nil, "Players deveria ter Behavior a partir de task-services-004")
	assert(playersBehavior.Methods ~= nil, "Players.Methods deveria existir -- GetPlayers/GetPlayerByUserId/GetPlayerFromCharacter")
	assert(playersBehavior.Initialize == nil, "Players não precisa de Initialize -- LocalPlayer/PlayerAdded/PlayerRemoving já ficam corretos só com o schema gerado (ver cabeçalho de Players.luau)")
end)

test("behavior/Index.luau['Lighting'] existe, tem Initialize e Methods (task-services-024)", function()
	local lightingBehavior = BehaviorIndex["Lighting"]
	assert(lightingBehavior ~= nil, "Lighting deveria ter Behavior a partir de task-services-024")
	assert(lightingBehavior.Initialize ~= nil, "Lighting.Initialize deveria existir -- sincroniza ClockTime/TimeOfDay/minutos e liga LightingChanged")
	assert(lightingBehavior.Methods ~= nil, "Lighting.Methods deveria existir -- Get/SetMinutesAfterMidnight e GetMoonPhase")
end)

test("behavior/Index.luau['DataStoreService'] existe, tem Methods e NENHUM Initialize (task-services-018)", function()
	local dataStoreServiceBehavior = BehaviorIndex["DataStoreService"]
	assert(dataStoreServiceBehavior ~= nil, "DataStoreService deveria ter Behavior a partir de task-services-018")
	assert(dataStoreServiceBehavior.Methods ~= nil, "DataStoreService.Methods deveria existir -- GetDataStore/GetGlobalDataStore/GetOrderedDataStore/GetRequestBudgetForRequestType/SetRateLimitForRequestType")
	assert(dataStoreServiceBehavior.Initialize == nil, "DataStoreService não precisa de Initialize -- estado (cache de memoização) é local de módulo, não por instância")
end)

test("behavior/Index.luau['GlobalDataStore'] existe, tem Methods e NENHUM Initialize (task-services-018)", function()
	local globalDataStoreBehavior = BehaviorIndex["GlobalDataStore"]
	assert(globalDataStoreBehavior ~= nil, "GlobalDataStore deveria ter Behavior a partir de task-services-018")
	assert(globalDataStoreBehavior.Methods ~= nil, "GlobalDataStore.Methods deveria existir -- GetAsync/SetAsync/UpdateAsync/RemoveAsync/IncrementAsync")
	assert(globalDataStoreBehavior.Initialize == nil, "GlobalDataStore não precisa de Initialize -- storeId é setado por DataStoreService.luau, via SetPropertyRaw, não em Initialize")
end)

test("behavior/Index.luau['DataStoreKeyInfo'] existe, tem Methods e NENHUM Initialize (task-services-018)", function()
	local dataStoreKeyInfoBehavior = BehaviorIndex["DataStoreKeyInfo"]
	assert(dataStoreKeyInfoBehavior ~= nil, "DataStoreKeyInfo deveria ter Behavior a partir de task-services-018")
	assert(dataStoreKeyInfoBehavior.Methods ~= nil, "DataStoreKeyInfo.Methods deveria existir -- GetMetadata/GetUserIds")
	assert(dataStoreKeyInfoBehavior.Initialize == nil, "DataStoreKeyInfo não precisa de Initialize -- toda a construção acontece na fábrica New, fora do contrato Types.Behavior")
end)

test("behavior/Index.luau['DataStoreOptions']/['DataStoreSetOptions']/['DataStoreIncrementOptions'] existem, cada uma só com Methods (task-services-018)", function()
	local dataStoreOptionsBehavior = BehaviorIndex["DataStoreOptions"]
	assert(dataStoreOptionsBehavior ~= nil, "DataStoreOptions deveria ter Behavior a partir de task-services-018")
	assert(dataStoreOptionsBehavior.Methods ~= nil, "DataStoreOptions.Methods deveria existir -- SetExperimentalFeatures")

	local dataStoreSetOptionsBehavior = BehaviorIndex["DataStoreSetOptions"]
	assert(dataStoreSetOptionsBehavior ~= nil, "DataStoreSetOptions deveria ter Behavior a partir de task-services-018")
	assert(dataStoreSetOptionsBehavior.Methods ~= nil, "DataStoreSetOptions.Methods deveria existir -- GetMetadata/SetMetadata")

	local dataStoreIncrementOptionsBehavior = BehaviorIndex["DataStoreIncrementOptions"]
	assert(dataStoreIncrementOptionsBehavior ~= nil, "DataStoreIncrementOptions deveria ter Behavior a partir de task-services-018")
	assert(dataStoreIncrementOptionsBehavior.Methods ~= nil, "DataStoreIncrementOptions.Methods deveria existir -- GetMetadata/SetMetadata")
end)

test("behavior/Index.luau['DataStore'] existe, tem Methods e NENHUM Initialize (task-services-019)", function()
	local dataStoreBehavior = BehaviorIndex["DataStore"]
	assert(dataStoreBehavior ~= nil, "DataStore deveria ter Behavior a partir de task-services-019")
	assert(dataStoreBehavior.Methods ~= nil, "DataStore.Methods deveria existir -- GetVersionAsync/ListVersionsAsync/ListKeysAsync")
	assert(dataStoreBehavior.Initialize == nil, "DataStore não precisa de Initialize -- todo o estado é resolvido via GlobalDataStore.Store/StoreIdOf")
end)

test("behavior/Index.luau['Pages'] existe, tem Methods e NENHUM Initialize (task-services-019)", function()
	local pagesBehavior = BehaviorIndex["Pages"]
	assert(pagesBehavior ~= nil, "Pages deveria ter Behavior a partir de task-services-019")
	assert(pagesBehavior.Methods ~= nil, "Pages.Methods deveria existir -- GetCurrentPage/AdvanceToNextPageAsync")
	assert(pagesBehavior.Initialize == nil, "Pages não precisa de Initialize -- toda a construção acontece na fábrica New, fora do contrato Types.Behavior")
end)

test("behavior/Index.luau['OrderedDataStore'] existe, tem Methods (só GetSortedAsync) e NENHUM Initialize (task-services-020)", function()
	local orderedDataStoreBehavior = BehaviorIndex["OrderedDataStore"]
	assert(orderedDataStoreBehavior ~= nil, "OrderedDataStore deveria ter Behavior a partir de task-services-020")
	assert(orderedDataStoreBehavior.Methods ~= nil, "OrderedDataStore.Methods deveria existir -- GetSortedAsync")
	assert((orderedDataStoreBehavior.Methods :: { [string]: unknown }).GetSortedAsync ~= nil, "OrderedDataStore.Methods.GetSortedAsync deveria existir")
	assert(orderedDataStoreBehavior.Initialize == nil, "OrderedDataStore não precisa de Initialize -- storeId é setado por DataStoreService.luau, via SetPropertyRaw, não em Initialize")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
