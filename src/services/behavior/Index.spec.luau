--!strict

--[[
	Teste de task-services-003 para `src/services/behavior/Index.luau`. Retomada: o mapa deixou de
	estar vazio (ver o cabeçalho de `Index.luau`, seção "HISTÓRICO", para o porquê) -- agora tem
	exatamente UMA entrada, `StarterPlayer`, cujo `Initialize` (cobertura de comportamento própria)
	é testado em `./StarterPlayer.spec.luau`. Este arquivo cobre só a FORMA do mapa (tipado
	corretamente, requerível, exatamente as entradas esperadas -- nem mais nem menos) e que
	`Services.Register()` (src/services/init.luau) consegue iterar `generated/Index.luau` cruzando
	com este mapa sem erro -- essa segunda parte já está coberta em `../Integration.spec.luau` (24
	classes registradas com sucesso, e `StarterPlayer` nascendo com os dois filhos fixos), não
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

test("behavior/Index.luau tem EXATAMENTE 1 entrada nesta leva: StarterPlayer", function()
	local count = 0
	for _ in BehaviorIndex do
		count += 1
	end
	assert(count == 1, `esperava 1 entrada nesta leva (StarterPlayer -- ver cabeçalho de Index.luau), recebeu {count}`)
end)

test("behavior/Index.luau['StarterPlayer'] existe e tem Initialize; classes-contêiner puro continuam sem entrada", function()
	local starterPlayerBehavior = BehaviorIndex["StarterPlayer"]
	assert(starterPlayerBehavior ~= nil, "StarterPlayer deveria ter Behavior nesta retomada (task-runtime-023 destravou NewEngineInstance)")
	assert(starterPlayerBehavior.Initialize ~= nil, "StarterPlayer.Initialize deveria existir -- é o que cria os 2 filhos fixos")
	assert(BehaviorIndex["Folder"] == nil, "Folder é contêiner puro -- nunca deveria ter Behavior")
	assert(BehaviorIndex["ReplicatedStorage"] == nil, "ReplicatedStorage é contêiner puro (Members == [] no dump) -- nunca deveria ter Behavior")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
