--!strict

--[[
	Teste de task-services-003 para `src/services/behavior/Index.luau`. Cobertura mínima
	deliberada: o mapa está vazio nesta leva (ver o cabeçalho de Index.luau para o porquê -- bloqueio
	de runtime confirmado nesta tarefa, não descuido), então o que há para verificar é a FORMA (mapa
	tipado corretamente, requerível, sem entradas fantasmas) e que `Services.Register()`
	(src/services/init.luau) consegue iterar `generated/Index.luau` cruzando com este mapa vazio
	sem erro -- essa segunda parte já está coberta em `../Integration.spec.luau` (24 classes
	registradas com sucesso), não duplicada aqui.

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

test("behavior/Index.luau devolve uma tabela vazia nesta leva (nenhuma classe com Behavior ainda)", function()
	local count = 0
	for _ in BehaviorIndex do
		count += 1
	end
	assert(count == 0, `esperava 0 entradas nesta leva (ver cabeçalho de Index.luau), recebeu {count}`)
end)

test("behavior/Index.luau[qualquer nome] é nil (não há entrada nenhuma) -- Services.Register trata isso como 'sem Behavior'", function()
	assert(BehaviorIndex["StarterPlayer"] == nil, "StarterPlayer ainda não tem Behavior -- ver bloqueio documentado no cabeçalho")
	assert(BehaviorIndex["Folder"] == nil, "Folder é contêiner puro -- nunca deveria ter Behavior")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
