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

	task-runtime-022 (.claude/agents-memory/arquiteto-services-2026-09-05.md, "Contrato entre
	territórios", subseção "`runtime` -> `services`") acrescenta dois cenários: (a) uso real de
	ponta a ponta dos quatro tipos que `init.luau` passou a reexportar -- `MemberKind`/
	`MemberDescriptor`/`ClassSchema` (registrando uma classe com `Schema`, confirmando que
	`ClassRegistry.new` semeia o `Default` de uma `Property` e cria um `Signal` fresco por entrada
	`Kind == "Event"`) e `FireableSignal<T...>` (estreitando o `unknown` de `GetPropertyRaw` sem
	cast cego, exatamente como `services` vai disparar `Players.PlayerAdded`); (b) o mesmo teste de
	vazamento que a revisão de task-runtime-007 já tinha feito manualmente fora do repositório
	(ver `.claude/agents-memory/revisor-runtime-init-2026-09-04.md`, seção 3) passa a viver aqui,
	comitado, com `Instance.SetClassSchema` acrescentado à lista: `Runtime.Instance.NewBase`/
	`SetClassChain`/`SetClassMethods`/`SetClassSchema` e `Runtime.ThreadBroker` continuam ausentes.
	A verificação usa cast em duas etapas por `unknown` para indexação dinâmica (nunca acesso
	estático a um campo que o tipo não declara -- isso faria o PRÓPRIO `luau-lsp analyze` reprovar
	este arquivo, já que o objetivo é provar ausência, não presença). Reexportação dos quatro tipos
	via `require("../runtime")` (a forma real que `services` usa) foi verificada à parte, em um
	diretório-irmão temporário fora do repositório com `luau-lsp analyze` limpo -- mesmo protocolo
	de verificação da revisão de task-runtime-007 -- e reportada como tal (não comitada: o escopo
	desta tarefa é só `init.luau`/`init.spec.luau`).

	Roda com `lune run src/runtime/init.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("./")

type Instance = Runtime.Instance
type ClassDescriptor = Runtime.ClassDescriptor
type OutputRecord = Runtime.OutputRecord

-- Tipos novos de task-runtime-022 (reexportados de Instance.luau/Signal.luau via init.luau) --
-- usados abaixo em anotação de tipo real, não só declarados aqui.
type MemberKind = Runtime.MemberKind
type MemberDescriptor = Runtime.MemberDescriptor
type ClassSchema = Runtime.ClassSchema

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

-- Segunda classe de teste, task-runtime-022: declara um `Schema` de verdade (uma `Property` com
-- `Default` e um `Event`) para exercitar `MemberKind`/`MemberDescriptor`/`ClassSchema` em
-- anotação de tipo real -- exatamente como `services` vai declarar o schema que o gerador emite
-- (ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3"). `table.freeze` é
-- exigência de `Instance.SetClassSchema` (chamada por `ClassRegistry.new`, nunca direto aqui --
-- a função não é reexportada, ver cabeçalho de `init.luau`).
-- Terceira classe de teste, task-runtime-023: IsAbstract = true (NotCreatable), para provar que
-- Runtime.ClassRegistry.NewEngineInstance está exportada e constrói o que Runtime.ClassRegistry.new
-- rejeitaria -- ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, "Revisão pós-integração
-- 2026-09-05 (4)".
local ENGINE_ONLY_CLASS_NAME = "InitSpecEngineOnly"
Runtime.ClassRegistry.Register({
	ClassName = ENGINE_ONLY_CLASS_NAME,
	SuperClassName = nil,
	IsAbstract = true,
	IsService = false,
	Initialize = nil,
} :: ClassDescriptor)

local SCHEMA_CLASS_NAME = "InitSpecSchemaContainer"
local schemaContainerSchema: ClassSchema = {
	Label = { Kind = "Property" :: MemberKind, Default = "default-label", ReadOnly = false } :: MemberDescriptor,
	Added = { Kind = "Event" :: MemberKind, Default = nil, ReadOnly = true } :: MemberDescriptor,
}
table.freeze(schemaContainerSchema)
Runtime.ClassRegistry.Register({
	ClassName = SCHEMA_CLASS_NAME,
	SuperClassName = nil,
	IsAbstract = false,
	IsService = false,
	Schema = schemaContainerSchema,
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

test(
	"task-runtime-022: MemberKind/MemberDescriptor/ClassSchema em uso real -- ClassRegistry.new semeia Default de Property e cria Signal fresco por Event",
	function()
		local instance = Runtime.ClassRegistry.new(SCHEMA_CLASS_NAME, "SchemaInstance")

		assert(
			instance.Label == "default-label",
			"uma entrada Kind == 'Property' do schema deveria semear o Default declarado na instância"
		)

		-- `services` alcança um evento de classe concreta (ex.: Players.PlayerAdded) exatamente
		-- assim: GetPropertyRaw devolve `unknown`, estreitado para `Runtime.FireableSignal<T...>`
		-- (reexportado nesta tarefa) sem cast cego para um tipo redeclarado à mão -- é o ganho de
		-- expor o tipo `FireableSignal` que esta tarefa fecha.
		local raw: unknown = Runtime.Instance.GetPropertyRaw(instance, "Added")
		local addedSignal: Runtime.FireableSignal<string> = raw :: Runtime.FireableSignal<string>

		local received: string? = nil
		addedSignal:Connect(function(value: string)
			received = value
		end)
		addedSignal:Fire("ok")

		assert(
			received == "ok",
			"o Signal fresco que ClassRegistry.new cria para uma entrada Kind == 'Event' deveria disparar de ponta a ponta"
		)
	end
)

test(
	"Runtime.Instance NÃO vaza NewBase/SetClassChain/SetClassMethods/SetClassSchema; Runtime.ThreadBroker não é reexportado",
	function()
		-- Cast em duas etapas por `unknown` (nunca `any`, regra 01): a existência do campo é
		-- verificada por indexação DINÂMICA sobre um tipo indexável, nunca por acesso estático a
		-- um campo que o tipo de `Runtime.Instance`/`Runtime` não declara -- acesso estático
		-- reprovaria o próprio `luau-lsp analyze` deste arquivo, e o objetivo aqui é provar
		-- ausência, não presença (mesmo padrão de cast usado em ThreadBroker.luau para storage).
		local runtimeInstanceDict: { [string]: unknown } = (Runtime.Instance :: unknown) :: { [string]: unknown }
		assert(runtimeInstanceDict["NewBase"] == nil, "Runtime.Instance.NewBase não deveria estar exposto")
		assert(runtimeInstanceDict["SetClassChain"] == nil, "Runtime.Instance.SetClassChain não deveria estar exposto")
		assert(runtimeInstanceDict["SetClassMethods"] == nil, "Runtime.Instance.SetClassMethods não deveria estar exposto")
		assert(
			runtimeInstanceDict["SetClassSchema"] == nil,
			"Runtime.Instance.SetClassSchema não deveria estar exposto (task-runtime-022: ClassRegistry.new é o único chamador legítimo)"
		)

		local runtimeDict: { [string]: unknown } = (Runtime :: unknown) :: { [string]: unknown }
		assert(runtimeDict["ThreadBroker"] == nil, "Runtime.ThreadBroker não deveria estar reexportado (plumbing interno do Scheduler)")
	end
)

-- task-runtime-023 (6a): Runtime.ClassRegistry.NewEngineInstance exportada e chamável -- constrói
-- uma classe NotCreatable que Runtime.ClassRegistry.new rejeitaria. A asserção de vazamento (6b,
-- teste acima) permanece intocada: NewEngineInstance é o ÚNICO acréscimo deliberado à lista de
-- plumbing que fica de fora -- prova de que o desvio é pontual, não uma erosão geral da
-- disciplina de esconder NewBase/SetClassChain/SetClassMethods/SetClassSchema/ThreadBroker.
test(
	"Runtime.ClassRegistry.NewEngineInstance está exportada e é chamável -- constrói uma classe NotCreatable que Runtime.ClassRegistry.new rejeitaria",
	function()
		local okNew = pcall(function()
			return Runtime.ClassRegistry.new(ENGINE_ONLY_CLASS_NAME, nil)
		end)
		assert(not okNew, "Runtime.ClassRegistry.new deveria rejeitar uma classe NotCreatable (IsAbstract=true)")

		local instance = Runtime.ClassRegistry.NewEngineInstance(ENGINE_ONLY_CLASS_NAME, nil)
		assert(instance ~= nil, "Runtime.ClassRegistry.NewEngineInstance deveria construir a mesma classe sem a guarda de política")
		assert(instance.ClassName == ENGINE_ONLY_CLASS_NAME, "ClassName da instância deveria ser o da classe pedida")
	end
)

-- task-runtime-036 (achado REPROVADO em revisão: GetFlattenedSchema existia em ClassRegistry.luau
-- mas não estava reexportada em init.luau -- ficava inalcançável para quem só pode usar
-- `require("../runtime")`, nunca um módulo interno). Mesmo padrão do teste de NewEngineInstance
-- acima: prova que a função está exposta e é chamável de fora do território, e que o achatamento
-- (própria classe + cadeia de superclasses, via SCHEMA_CLASS_NAME já registrada acima) bate com o
-- que `ClassRegistry.new`/`Instance.Label` já confirmaram nos testes anteriores.
test(
	"Runtime.ClassRegistry.GetFlattenedSchema está exportada e é chamável -- achata Schema da própria classe (sem superclasse aqui)",
	function()
		local flattened = Runtime.ClassRegistry.GetFlattenedSchema(SCHEMA_CLASS_NAME)

		assert(flattened ~= nil, "GetFlattenedSchema não deveria devolver nil para uma classe registrada")
		assert(
			flattened.Label ~= nil and (flattened.Label :: MemberDescriptor).Default == "default-label",
			"a entrada 'Label' achatada deveria trazer o mesmo Default declarado no Schema de SCHEMA_CLASS_NAME"
		)
		assert(
			flattened.Added ~= nil and (flattened.Added :: MemberDescriptor).Kind == "Event",
			"a entrada 'Added' achatada deveria preservar Kind == 'Event'"
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
