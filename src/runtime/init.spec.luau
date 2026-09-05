--!strict

--[[
	Teste de integração da task-runtime-007 (src/runtime/init.luau, ponto de entrada público do
	runtime). Só importa o agregador -- nunca um módulo interno de `src/runtime/` direto -- é
	justamente esse o critério de pronto que o board cobra: nenhum cenário aqui precisa alcançar
	Signal/Instance/Scheduler/ClassRegistry/DataModel/Sandbox/ThreadBroker por fora dele.

	`require("./")`, NÃO `require("./init")`: confirmado empiricamente (rodando `lune run`
	isolado antes de escrever este arquivo, nunca por suposição -- regra 00) que o resolvedor de
	`require` do Lune 0.10.5 trata `require("./init")`/`require("./init.luau")` como erro
	("could not resolve child component 'init' (ambiguous)"/"...'init.luau'") a partir de um
	módulo irmão -- só a forma "estilo diretório" carrega este arquivo. `services`/`cli` (fora de
	`src/runtime/`) usam a forma equivalente `require("../runtime")`, documentada no contrato em
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md ("Contrato entre territórios"); as duas
	formas ("./" daqui de dentro, "../runtime" de fora) foram confirmadas funcionando de verdade
	em tempo de execução nesta tarefa (a segunda, testada a partir de um diretório irmão
	simulado). Ver o comentário de cabeçalho de `init.luau` para o detalhe completo do gotcha do
	Lune (inclusive por que os `require` DENTRO dele usam `./runtime/Xxx`, não `./Xxx`).

	PENDÊNCIA DE TOOLING (achado desta tarefa, não do código): `luau-lsp analyze` 1.69.0 devolve
	um falso-positivo de "Unknown require" bem NESTA linha, mesmo com `require("./")` -- e o
	mesmo acontece com `require("../runtime")`, testado como alternativa. Confirmado
	empiricamente (nunca por suposição) que o gatilho é o NOME deste arquivo, não o conteúdo:
	uma cópia idêntica deste arquivo, renomeada para algo que não comece com "init", analisa
	limpo com `luau-lsp` usando a MESMA linha de `require`; e um arquivo de controle qualquer,
	nomeado normalmente, ao lado do `init.luau` real, também analisa limpo com `require("./")`.
	Ou seja: `luau-lsp` parece generalizar demais a convenção "arquivo `init.luau` representa o
	diretório" para QUALQUER arquivo cujo nome comece por "init" (incluindo `init.spec.luau`),
	deslocando a base de resolução dos `require` relativos DELE MESMO em um nível -- um bug
	isolado da ferramenta de análise estática, não do Lune (que executa este arquivo
	corretamente, confirmado pelos 3/3 abaixo) nem deste código (os `TypeError`s em cascata
	"Unknown type 'Runtime.X'" são consequência direta desta única falha de resolução, não erros
	de tipo independentes). Reportado no relatório desta tarefa para `arquiteto`/`pesquisador`
	decidirem se vale acompanhar upstream ou mitigar via configuração de projeto -- não
	escondido, não adivinhado.

	Cobre, fim a fim: registro de classe no formato NOVO de ClassDescriptor (`Initialize`
	opcional, sem `Construct` -- ver arquiteto-runtime-2026-09-04.md, "Revisão pós-integração
	2026-09-04 (2)") -> `Runtime.DataModel.new()` -> instanciação via `Runtime.ClassRegistry.new`
	-> hierarquia via `.Parent` -> `Runtime.Sandbox.Run` rodando um script real que usa
	`WaitForChild` sem timeout e `task.wait` de verdade (bloqueio cooperativo via `Scheduler`,
	nunca polling) -> um segundo script que erra de propósito, confirmando que o erro vira
	`OutputRecord` e NUNCA derruba o processo do LuauBench (regra 00, invariante 7).

	Roda com `lune run src/runtime/init.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("./")

type Instance = Runtime.Instance
type ClassDescriptor = Runtime.ClassDescriptor
type OutputRecord = Runtime.OutputRecord

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Classe de teste registrada uma única vez (ClassRegistry é um registro global por processo,
-- sem reset -- ver ClassRegistry.luau, cabeçalho -- então cada teste reaproveita o mesmo
-- descriptor em vez de tentar Register de novo). Formato NOVO: `Initialize` recebe a instância
-- JÁ criada e JÁ com a cadeia de classes aplicada por `ClassRegistry.new`, nunca cria nada
-- (o campo `Construct` do desenho original deixou de existir, task-runtime-013). Usa
-- `Runtime.Instance.SetPropertyRaw` -- a única forma pública de instalar propriedade sem passar
-- pela metatable -- exercitando também esse pedaço reexportado do agregador.
local CONTAINER_CLASS_NAME = "InitSpecContainer"
Runtime.ClassRegistry.Register({
	ClassName = CONTAINER_CLASS_NAME,
	SuperClassName = nil,
	IsAbstract = false,
	IsService = false,
	Initialize = function(instance: Instance)
		Runtime.Instance.SetPropertyRaw(instance, "Label", CONTAINER_CLASS_NAME)
	end,
} :: ClassDescriptor)

test("registro de classe + DataModel.new + ClassRegistry.new + hierarquia via .Parent", function()
	local dataModel = Runtime.DataModel.new()
	local root = Runtime.ClassRegistry.new(CONTAINER_CLASS_NAME, "Root")

	root.Parent = dataModel

	assert(root.Parent == dataModel, "atribuir .Parent deveria refletir no getter")
	assert(
		dataModel:FindFirstChild("Root") == root,
		"root deveria aparecer como filho da raiz, via a API pública de Instance"
	)
	assert(
		Runtime.Instance.GetPropertyRaw(root, "Label") == CONTAINER_CLASS_NAME,
		"Initialize deveria ter semeado 'Label' via Runtime.Instance.SetPropertyRaw, ANTES de ClassRegistry.new devolver"
	)
end)

test(
	"Sandbox.Run executa WaitForChild sem timeout e task.wait de verdade dentro do script sandboxed, cooperativo via Scheduler (nunca polling)",
	function()
		local dataModel = Runtime.DataModel.new()
		local root = Runtime.ClassRegistry.new(CONTAINER_CLASS_NAME, "Root")
		root.Parent = dataModel

		local scheduler = Runtime.Scheduler.new()

		-- Thread gerida, FORA do sandbox: só parenteia o filho depois de um pequeno delay real
		-- do próprio Scheduler -- é o que força o WaitForChild dentro do sandbox a bloquear de
		-- verdade (ceder a coroutine via ThreadBroker) em vez de encontrar o filho já pronto na
		-- primeira checagem.
		scheduler:Spawn(function()
			scheduler:Wait(0.02)
			local child = Runtime.ClassRegistry.new(CONTAINER_CLASS_NAME, "Child")
			child.Parent = root
		end)

		local results: { [string]: boolean } = {}

		Runtime.Sandbox.Run({
			scriptName = "IntegrationSpec.WaitAndTaskWait",
			source = [[
				local child = game:WaitForChild("Child")
				report("waitForChildResolved", child ~= nil)
				task.wait(0.01)
				report("taskWaitCompleted", true)
			]],
			scheduler = scheduler,
			extraGlobals = {
				game = root,
				report = function(key: string, ok: boolean)
					results[key] = ok
				end,
			},
			onOutput = function(_record) end,
		})

		-- Guarda de wall-clock (2s): nunca deixa o teste pendurar o CI se algo não resolver.
		-- Em condições normais `Run()` termina sozinho bem antes disso, assim que IsAlive()
		-- vira false (as duas threads geridas terminaram).
		local deadline = os.clock() + 2
		scheduler:Run(function()
			return os.clock() < deadline
		end)

		assert(
			results.waitForChildResolved == true,
			"WaitForChild deveria ter bloqueado de verdade e resolvido quando o filho apareceu (nunca nil cedo)"
		)
		assert(
			results.taskWaitCompleted == true,
			"task.wait deveria ter cedido a coroutine e retomado depois, cooperativo via Scheduler (nunca sleep bloqueante)"
		)
	end
)

test(
	"erro proposital dentro de um script sandboxed é capturado como OutputRecord e NUNCA derruba o processo do LuauBench",
	function()
		local scheduler = Runtime.Scheduler.new()
		local outputs: { OutputRecord } = {}

		Runtime.Sandbox.Run({
			scriptName = "IntegrationSpec.Erro",
			source = [[error("erro proposital de teste -- nunca deveria derrubar o processo do LuauBench")]],
			scheduler = scheduler,
			onOutput = function(record)
				table.insert(outputs, record)
			end,
		})

		-- O erro acontece de forma SÍNCRONA dentro do próprio `Scheduler:Spawn` (task.spawn roda
		-- até o primeiro yield/término -- aqui não há yield nenhum, então o erro já aconteceu
		-- antes de `Sandbox.Run` devolver o controle).
		assert(#outputs == 1, `deveria ter capturado exatamente 1 OutputRecord de erro, capturou {#outputs}`)
		assert(outputs[1].level == "error", "o OutputRecord deveria ser de nível 'error'")
		assert(outputs[1].scriptName == "IntegrationSpec.Erro", "o OutputRecord deveria trazer o scriptName do script que errou")
		assert(
			string.find(outputs[1].message, "erro proposital de teste") ~= nil,
			`a mensagem deveria conter o texto do erro proposital, recebeu: {outputs[1].message}`
		)

		-- A prova de que o processo continua vivo: o Scheduler segue funcionando normalmente
		-- depois do erro, e o teste seguinte (fora deste `test(...)`) ainda vai rodar.
		local stillWorks = false
		scheduler:Spawn(function()
			stillWorks = true
		end)
		assert(stillWorks, "o Scheduler deveria continuar funcionando normalmente depois do erro do script")
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
