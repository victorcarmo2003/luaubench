--!strict

--[[
	Teste dedicado de `./StarterPlayer.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	`../Integration.spec.luau` já cobre o caminho ponta a ponta (`game:GetService("StarterPlayer")`
	criando o singleton E os dois filhos, com o `Parent` de `StarterPlayer` sob `game`) -- este
	arquivo isola a peça que pertence a ESTE módulo: o `Initialize` em si, construindo
	`StarterPlayer` direto via `Runtime.ClassRegistry.NewEngineInstance` (sem `DataModel`/
	`GetService` no meio), então o que falhar aqui aponta primeiro para `StarterPlayer.luau`, não
	para o resto do pipeline de `services`.

	`require("../")`, não `require("../init")`/`require("../init.luau")`: mesmo gotcha de resolução
	de `require` do Lune 0.10.5 documentado no cabeçalho de `../init.luau`/`../Integration.spec.luau`
	-- só a forma "estilo diretório" carrega o `init.luau` real a partir de um arquivo de fora do
	diretório (aqui, um nível mais fundo, em `behavior/`).

	Roda com `lune run src/services/behavior/StarterPlayer.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")
local StarterPlayerBehavior = require("./StarterPlayer")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Idempotente (guarda local em ../init.luau) -- seguro mesmo que outro spec do processo já tenha
-- chamado. Precisa rodar antes de `NewEngineInstance("StarterPlayer", ...)` abaixo: é o que
-- registra `StarterPlayer` (com este `Behavior` via `ClassBuilder.Build`) e os dois filhos fixos
-- (`StarterPlayerScripts`/`StarterCharacterScripts`) em `Runtime.ClassRegistry`.
Services.Register()

test("Types.Behavior exportado por StarterPlayer.luau tem Initialize e NENHUM Methods (StarterPlayer não declara método no dump)", function()
	assert(StarterPlayerBehavior.Initialize ~= nil, "StarterPlayer.luau deveria exportar Initialize -- é o que cria os 2 filhos fixos")
	assert(StarterPlayerBehavior.Methods == nil, "StarterPlayer não tem MethodNames no dump (generated/classes/StarterPlayer.luau) -- Methods não deveria existir")
end)

test(
	"Runtime.ClassRegistry.NewEngineInstance('StarterPlayer') roda o Initialize: nasce com StarterPlayerScripts e StarterCharacterScripts, parenteados A ELE -- e o Initialize NUNCA mexe no Parent da própria instância",
	function()
		local starterPlayer = Runtime.ClassRegistry.NewEngineInstance("StarterPlayer", nil)

		-- Contrato do campo Initialize (src/runtime/ClassRegistry.luau, comentário do campo): "só
		-- configura: não cria, não devolve nada" -- nunca seta o Parent da PRÓPRIA instância
		-- recebida. Quem decide o Parent de StarterPlayer é DataModel.GetService, de fora --
		-- aqui, sem GetService no caminho, o Parent deveria continuar nil.
		assert(starterPlayer.Parent == nil, "Initialize NUNCA deveria setar o Parent da própria instância recebida -- só o Parent dos filhos que ele cria")

		local starterPlayerScripts = starterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		local starterCharacterScripts = starterPlayer:FindFirstChildOfClass("StarterCharacterScripts")

		assert(starterPlayerScripts ~= nil, "StarterPlayer deveria nascer com um filho StarterPlayerScripts")
		assert(starterCharacterScripts ~= nil, "StarterPlayer deveria nascer com um filho StarterCharacterScripts")
		assert(starterPlayerScripts.ClassName == "StarterPlayerScripts", "o filho deveria ter ClassName == 'StarterPlayerScripts'")
		assert(starterCharacterScripts.ClassName == "StarterCharacterScripts", "o filho deveria ter ClassName == 'StarterCharacterScripts'")
		assert(
			rawequal(starterPlayerScripts.Parent, starterPlayer),
			"StarterPlayerScripts deveria estar parenteado a `instance` (o próprio StarterPlayer), nunca a outro objeto"
		)
		assert(
			rawequal(starterCharacterScripts.Parent, starterPlayer),
			"StarterCharacterScripts deveria estar parenteado a `instance` (o próprio StarterPlayer), nunca a outro objeto"
		)
	end
)

test(
	"os dois filhos fixos continuam INALCANÇÁVEIS pela via pública (Instance.new/ClassRegistry.new de um script) -- só a via do motor (NewEngineInstance) os cria",
	function()
		local ok, err = pcall(function()
			return Runtime.ClassRegistry.new("StarterPlayerScripts", nil)
		end)
		assert(not ok, "a via pública deveria rejeitar StarterPlayerScripts -- é NotCreatable no dump, igual StarterPlayer")
		assert(
			string.find(tostring(err), "NewEngineInstance", 1, true) ~= nil,
			`mensagem deveria citar NewEngineInstance como a via correta (task-runtime-023), recebeu: {err}`
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
