--!strict

--[[
	Teste de task-services-003 para `src/services/behavior/Index.luau`, ATUALIZADO por
	task-services-004 e task-services-024. O mapa deixou de estar vazio na retomada de
	task-services-003 (ver o cabeçalho de `Index.luau`, seção "HISTÓRICO", para o porquê) com UMA
	entrada (`StarterPlayer`), ganhou mais DUAS em task-services-004 (`RunService`/`Players`) e mais
	UMA em task-services-024 (`Lighting`) -- 4 entradas ao todo. `Initialize`/`Methods` de cada uma
	(cobertura de comportamento própria) é testado em `./StarterPlayer.spec.luau`/
	`./RunService.spec.luau`/`./Players.spec.luau`/`./Lighting.spec.luau`. Este arquivo cobre só a
	FORMA do mapa (tipado corretamente, requerível, exatamente as entradas esperadas -- nem mais
	nem menos) e que `Services.Register()` (src/services/init.luau) consegue iterar
	`generated/Index.luau` cruzando com este mapa sem erro -- essa segunda parte já está coberta
	em `../Integration.spec.luau` (24 classes registradas com sucesso, `StarterPlayer` nascendo
	com os dois filhos fixos, e `RunService`/`Players` alcançáveis por `GetService`), não
	duplicada aqui.

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

test("behavior/Index.luau tem EXATAMENTE 4 entradas até esta leva: StarterPlayer, RunService, Players, Lighting", function()
	local count = 0
	for _ in BehaviorIndex do
		count += 1
	end
	assert(count == 4, `esperava 4 entradas até esta leva (StarterPlayer + RunService + Players + Lighting -- ver cabeçalho de Index.luau), recebeu {count}`)
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

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
