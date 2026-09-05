--!strict

--[[
	Teste dedicado de `./EngineFixedChildren.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Módulo folha, sem dependência de `Context`/`Runtime.ClassRegistry`/`fs` -- por isso este
	spec testa `Of`/`Is` diretamente, sem `Services.Bootstrap` nem `Runtime.DataModel` no meio.

	`../Integration.spec.luau` e `./behavior/StarterPlayer.spec.luau` cobrem o caminho ponta a
	ponta (o motor de verdade criando os filhos); `./init.spec.luau` cobre `Services.IsEngineFixedChild`
	(a superfície pública que `cli` enxerga) antes e depois de `Bootstrap`, e a coerência contra o
	`game` real. Este arquivo isola só a peça que pertence a ESTE módulo: a tabela declarada e os
	dois acessores puros.

	Roda com `lune run src/services/EngineFixedChildren.spec.luau`.
]]

local process = require("@lune/process")
local EngineFixedChildren = require("./EngineFixedChildren")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Of('StarterPlayer') devolve EXATAMENTE os dois filhos fixos, NA ORDEM declarada (ordem de criação)", function()
	local children = EngineFixedChildren.Of("StarterPlayer")
	assert(#children == 2, `esperava 2 entradas para StarterPlayer, recebeu {#children}`)
	assert(children[1].Name == "StarterPlayerScripts", "primeira entrada deveria ser StarterPlayerScripts (ordem de criação)")
	assert(children[1].ClassName == "StarterPlayerScripts", "primeira entrada deveria ter ClassName == 'StarterPlayerScripts'")
	assert(children[2].Name == "StarterCharacterScripts", "segunda entrada deveria ser StarterCharacterScripts (ordem de criação)")
	assert(children[2].ClassName == "StarterCharacterScripts", "segunda entrada deveria ter ClassName == 'StarterCharacterScripts'")
end)

test("Of(classe sem filhos fixos declarados) devolve {} -- NUNCA nil", function()
	local children = EngineFixedChildren.Of("Workspace")
	assert(children ~= nil, "Of nunca deveria devolver nil -- contrato explícito do módulo")
	assert(#children == 0, "Workspace não tem filhos fixos declarados nesta leva (Covered=false, sem behavior/Workspace.luau) -- deveria ser {}")

	local unknown = EngineFixedChildren.Of("TotalmenteInventada123")
	assert(unknown ~= nil and #unknown == 0, "classe desconhecida também deveria devolver {} (nunca nil, nunca erro)")
end)

test("Is('StarterPlayer', 'StarterPlayerScripts', 'StarterPlayerScripts') == true", function()
	assert(EngineFixedChildren.Is("StarterPlayer", "StarterPlayerScripts", "StarterPlayerScripts"), "trio deveria bater a primeira entrada declarada")
end)

test("Is('StarterPlayer', 'StarterCharacterScripts', 'StarterCharacterScripts') == true", function()
	assert(EngineFixedChildren.Is("StarterPlayer", "StarterCharacterScripts", "StarterCharacterScripts"), "trio deveria bater a segunda entrada declarada")
end)

--------------------------------------------------------------------------------------------------
-- TESTE DE GUARDA (acceptance da task-services-010): Is devolve false para TODO trio fora da
-- lista fechada -- cobre os cinco casos explícitos do acceptance, um por um, com a razão de cada
-- um não bater.
--------------------------------------------------------------------------------------------------

test("Is('StarterPlayer', 'Terrain', 'Terrain') == false -- Terrain não é filho fixo de StarterPlayer", function()
	assert(not EngineFixedChildren.Is("StarterPlayer", "Terrain", "Terrain"), "Terrain não está na lista de StarterPlayer")
end)

test("Is('Workspace', 'Terrain', 'Terrain') == false -- Workspace não tem entrada em ENGINE_FIXED_CHILDREN (Covered=false, sem behavior/Workspace.luau)", function()
	assert(not EngineFixedChildren.Is("Workspace", "Terrain", "Terrain"), "Workspace não é uma chave declarada -- o motor simulado não pré-cria Terrain")
end)

test("Is('DataModel', 'StarterPlayerScripts', 'StarterPlayerScripts') == false -- DataModel não é uma chave declarada", function()
	assert(not EngineFixedChildren.Is("DataModel", "StarterPlayerScripts", "StarterPlayerScripts"), "DataModel não tem filhos fixos declarados neste módulo")
end)

test("Is('ReplicatedStorage', 'Folder', 'Folder') == false -- ReplicatedStorage não é uma chave declarada", function()
	assert(not EngineFixedChildren.Is("ReplicatedStorage", "Folder", "Folder"), "ReplicatedStorage não tem filhos fixos declarados neste módulo")
end)

test(
	"Is('StarterPlayer', 'MyScripts', 'StarterPlayerScripts') == false -- Name e ClassName cruzados (Name errado)",
	function()
		assert(
			not EngineFixedChildren.Is("StarterPlayer", "MyScripts", "StarterPlayerScripts"),
			"Name precisa bater EXATAMENTE, não só ClassName -- é o que mantém fiel o caso 'MyScripts' renomeado sob $className explícito"
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
