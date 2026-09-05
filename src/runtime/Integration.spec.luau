--!strict

--[[
	Teste da task-runtime-009 (Integration.spec.luau). Diferente de Signal.spec.luau/
	Instance.spec.luau/Scheduler.spec.luau -- que testam cada módulo isolado, ou usando
	`coroutine.create`/`coroutine.resume` cru no lugar do vizinho real --, este arquivo
	exercita Signal + Instance + Scheduler JUNTOS, de verdade, sempre com um `Scheduler` real
	dirigindo as threads. Foi exatamente a ausência desse tipo de teste que deixou passar os
	dois achados GRAVE (e o ALTO 3/ALTO 4) descritos em
	.claude/agents-memory/revisor-runtime-signal-instance-scheduler-2026-09-04.md, corrigidos
	pelo patch de task-runtime-008 (ThreadBroker.luau + patch em Signal/Instance/Scheduler).

	Os 9 cenários abaixo reproduzem exatamente a lista "Testes de integração exigidos" de
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-04 -- contrato Wait/resume". O cenário 9 (regressão de Signal.spec/Instance.spec/
	Scheduler.spec sem alterar esses arquivos) não é um `test()` deste arquivo -- é uma
	execução separada dos três specs existentes, documentada no relatório da tarefa.

	Todo teste que depende de tempo de parede real (cenários 3 e 4, que chamam
	`Scheduler:Run()`) usa uma guarda de tempo só como rede de segurança contra travar a
	suíte -- nunca como mecanismo de "dar tempo" a um teste que deveria ser determinístico
	(regra 01/acceptance da tarefa). As asserções confirmam explicitamente que a guarda NUNCA
	foi o motivo real do término do laço.

	Roda com `lune run src/runtime/Integration.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("./Scheduler")
local InstanceModule = require("./Instance")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Teto de segurança (bem acima do que qualquer cenário legítimo precisa) para os testes que
-- chamam `Scheduler:Run()` com tempo de parede real -- nunca deveria disparar de verdade;
-- serve só para não pendurar a suíte indefinidamente se uma regressão futura reintroduzir um
-- laço que não termina sozinho. Cada teste que usa isto assevera explicitamente que a guarda
-- NÃO foi o motivo do término (ver `runWithGuard`).
local RUN_GUARD_SECONDS = 3

-- Roda `scheduler:Run()` com um `shouldContinue` que só existe como rede de segurança:
-- devolve `true` (deixa `IsAlive()` decidir sozinho) até `guardSeconds` de tempo de parede
-- real decorrido, e só então devolve `false`. Devolve se a guarda chegou a disparar -- se
-- `Run()` já tiver terminado por `IsAlive()` ficar false antes disso (o caminho esperado em
-- todo teste desta suíte), a guarda nunca chega a ser avaliada como `false` nenhuma vez,
-- porque o próprio `Run()` já não chama `shouldContinue()` quando `IsAlive()` é falso
-- (curto-circuito do `and`, ver Scheduler.luau:427/433).
local function runWithGuard(scheduler: Scheduler.Scheduler, guardSeconds: number): boolean
	local guardTriggered = false
	local start = os.clock()
	scheduler:Run(function(): boolean
		if os.clock() - start > guardSeconds then
			guardTriggered = true
			return false
		end
		return true
	end)
	return guardTriggered
end

-- ── Cenário 1 ──────────────────────────────────────────────────────────────────────────
-- Spawn + Heartbeat:Wait() + StepOnce -> a thread termina E IsAlive() fica false. Repro
-- direto do achado GRAVE 2: antes do patch, `Signal:Wait()` resumia a thread com
-- `coroutine.resume` cru, fora do ponto único de `resumeThread` -- `liveThreads` nunca era
-- podado para essa thread e `IsAlive()` ficava `true` para sempre.
test("1. Spawn + Heartbeat:Wait() + StepOnce -> thread termina e IsAlive() fica false", function()
	local scheduler = Scheduler.new()
	local finished = false

	local handle = scheduler:Spawn(function()
		scheduler.Heartbeat:Wait()
		finished = true
	end)

	assert(scheduler:IsAlive(), "logo após Spawn, a thread suspensa em Heartbeat:Wait() deveria manter IsAlive() true")
	assert(not finished, "a thread não deveria ter terminado antes de Heartbeat disparar")

	scheduler:StepOnce(0.016)

	assert(finished, "a thread deveria ter terminado depois que Heartbeat disparou em StepOnce")
	assert(coroutine.status(handle) == "dead", "a coroutine deveria estar morta (dead) após a thread terminar")
	assert(not scheduler:IsAlive(), "depois que a thread terminou e nada mais está pendente, IsAlive() deveria ser false")
end)

-- ── Cenário 2 ──────────────────────────────────────────────────────────────────────────
-- Spawn + WaitForChild sem timeout + child.Parent = parent -> resolve E IsAlive() fica
-- false. Mesma raiz do cenário 1 (GRAVE 2), mas passando pelo caminho real de
-- Instance:WaitForChild (que usa Signal:Wait por baixo), não por Heartbeat direto.
test("2. Spawn + WaitForChild sem timeout + Parent -> resolve e IsAlive() fica false", function()
	local scheduler = Scheduler.new()
	local parent = InstanceModule.NewBase("Folder", "Parent")
	local found: InstanceModule.Instance? = nil

	scheduler:Spawn(function()
		found = parent:WaitForChild("Child")
	end)

	assert(scheduler:IsAlive(), "thread suspensa em WaitForChild sem timeout deveria manter IsAlive() true")
	assert(found == nil, "não deveria ter resolvido antes do filho existir")

	local child = InstanceModule.NewBase("Folder", "Child")
	child.Parent = parent

	assert(found ~= nil, "WaitForChild deveria ter resolvido depois de Parent ser setado")
	assert((found :: InstanceModule.Instance).Name == "Child", "WaitForChild deveria ter resolvido com o filho certo")
	assert(not scheduler:IsAlive(), "depois que a thread resolveu e nada mais está pendente, IsAlive() deveria ser false")
end)

-- ── Cenário 3 ──────────────────────────────────────────────────────────────────────────
-- Run() SEM precisar de shouldContinue termina sozinho, nos dois casos acima -- usando
-- Scheduler:Run() de verdade (tempo de parede real) em vez de StepOnce manual. A guarda de
-- tempo é só rede de segurança (ver runWithGuard); a asserção confirma que ela nunca disparou.
test("3a. Run() termina sozinho por IsAlive() ficar false, não pela guarda (caso Heartbeat:Wait)", function()
	local scheduler = Scheduler.new()
	local finished = false

	scheduler:Spawn(function()
		scheduler.Heartbeat:Wait()
		finished = true
	end)

	local guardTriggered = runWithGuard(scheduler, RUN_GUARD_SECONDS)

	assert(finished, "a thread deveria ter terminado durante Run()")
	assert(not scheduler:IsAlive(), "Run() só deveria ter retornado com IsAlive() já false")
	assert(not guardTriggered, "o término de Run() não deveria ter sido causado pela guarda de tempo, e sim por IsAlive() ficar false sozinho")
end)

test("3b. Run() termina sozinho por IsAlive() ficar false, não pela guarda (caso WaitForChild + Parent)", function()
	local scheduler = Scheduler.new()
	local parent = InstanceModule.NewBase("Folder", "Parent")
	local found: InstanceModule.Instance? = nil

	scheduler:Spawn(function()
		found = parent:WaitForChild("Child")
	end)
	scheduler:Spawn(function()
		-- Wait real pequeno: garante que a resolução acontece DENTRO do laço de Run() (mais
		-- de um tique), não já no primeiro Spawn síncrono, exercitando o laço de verdade.
		scheduler:Wait(0.02)
		local child = InstanceModule.NewBase("Folder", "Child")
		child.Parent = parent
	end)

	local guardTriggered = runWithGuard(scheduler, RUN_GUARD_SECONDS)

	assert(found ~= nil, "WaitForChild deveria ter resolvido durante Run()")
	assert((found :: InstanceModule.Instance).Name == "Child", "deveria ter resolvido com o filho certo")
	assert(not scheduler:IsAlive(), "Run() só deveria ter retornado com IsAlive() já false")
	assert(not guardTriggered, "o término de Run() não deveria ter sido causado pela guarda de tempo, e sim por IsAlive() ficar false sozinho")
end)

-- ── Cenário 4 ──────────────────────────────────────────────────────────────────────────
-- WaitForChild(nome, 0.05) dentro de Run() devolve nil com wall-clock decorrido dentro de
-- [0.05, 0.5]. Repro exato do achado GRAVE 1: antes do patch, o timeout usava polling via
-- @lune/task nativo mesmo sob thread gerida, competindo com o laço de Run() pelo executor
-- assíncrono do Lune -- o achado original mediu "não resolve em 2s de wall-clock" para este
-- mesmo timeout de 0.05s.
test("4. WaitForChild(nome, 0.05) dentro de Run() devolve nil com wall-clock em [0.05, 0.5] (repro GRAVE 1)", function()
	local scheduler = Scheduler.new()
	local parent = InstanceModule.NewBase("Folder", "Parent")
	local result: InstanceModule.Instance? = nil
	local elapsed = -1

	scheduler:Spawn(function()
		local t0 = os.clock()
		result = parent:WaitForChild("Fantasma", 0.05)
		elapsed = os.clock() - t0
	end)

	local guardTriggered = runWithGuard(scheduler, RUN_GUARD_SECONDS)

	assert(not guardTriggered, "não deveria ter precisado da guarda -- o timeout de 0.05s deveria resolver bem antes disso")
	assert(result == nil, "o filho 'Fantasma' nunca aparece; WaitForChild deveria devolver nil")
	assert(elapsed >= 0.05, `wall-clock decorrido ({elapsed}s) não deveria ser menor que o timeout pedido (0.05s)`)
	assert(elapsed <= 0.5, `wall-clock decorrido ({elapsed}s) deveria estar próximo do timeout pedido (0.05s), não competindo com o executor assíncrono do Lune -- é o repro exato do achado GRAVE 1 (que media >2s)`)
end)

-- ── Cenário 5 ──────────────────────────────────────────────────────────────────────────
-- WaitForChild(nome, 5) sob StepOnce determinístico: 4x StepOnce(1) ainda esperando, o 5º
-- resolve nil. Prova que, sob thread gerida, o timeout é medido no relógio SIMULADO do
-- Scheduler (raw.time, avançado só por tick/StepOnce), não em wall-clock real -- ganho de
-- testabilidade documentado na seção "Fidelidade vs. pragmatismo (entradas novas)" do
-- desenho, e a mesma propriedade que corrige o achado GRAVE 1 (cenário 4 acima).
test("5. WaitForChild(nome, 5) sob StepOnce determinístico: 4x StepOnce(1) esperando, 5º resolve nil", function()
	local scheduler = Scheduler.new()
	local parent = InstanceModule.NewBase("Folder", "Parent")
	local resolved = false
	local result: InstanceModule.Instance? = nil

	scheduler:Spawn(function()
		result = parent:WaitForChild("Fantasma", 5)
		resolved = true
	end)

	for i = 1, 4 do
		scheduler:StepOnce(1)
		assert(not resolved, `não deveria ter resolvido ainda após StepOnce #{i} (relógio simulado = {i} < 5)`)
	end

	scheduler:StepOnce(1)

	assert(resolved, "deveria ter resolvido no 5º StepOnce(1), quando o relógio simulado atinge o timeout de 5")
	assert(result == nil, "o filho 'Fantasma' nunca aparece; deveria resolver com nil")
end)

-- ── Cenário 6 ──────────────────────────────────────────────────────────────────────────
-- Heartbeat:Wait() seguido de error() -> ThreadError recebe o HANDLE devolvido por Spawn,
-- não a thread hospedeira (quem chamou StepOnce/tick). Repro exato do achado ALTO 4: antes
-- do patch, a continuação de Wait() resumia via coroutine.resume cru dentro do próprio
-- Fire, sem isolamento por listener -- o erro propagava para fora de Fire e fireProtected
-- atribuía a coroutine.running() no momento do tick (a thread principal), não ao handle.
test("6. Heartbeat:Wait() seguido de error() -> ThreadError recebe o handle de Spawn, não a thread hospedeira", function()
	local scheduler = Scheduler.new()
	local errorThread: thread? = nil
	local errorMessage: string? = nil

	scheduler.ThreadError:Connect(function(thread: thread, message: string)
		errorThread = thread
		errorMessage = message
	end)

	local hostThread = coroutine.running()
	local handle = scheduler:Spawn(function()
		scheduler.Heartbeat:Wait()
		error("boom apos heartbeat (integracao)")
	end)

	scheduler:StepOnce(0.016)

	assert(errorThread ~= nil, "ThreadError deveria ter disparado")
	assert(errorThread == handle, "ThreadError deveria identificar exatamente o handle devolvido por Spawn")
	assert(errorThread ~= hostThread, "ThreadError NUNCA deveria apontar para a thread hospedeira (quem chamou StepOnce)")
	assert(errorMessage ~= nil and string.find(errorMessage :: string, "boom apos heartbeat") ~= nil, "mensagem de ThreadError deveria conter a causa original")
end)

-- ── Cenário 7 ──────────────────────────────────────────────────────────────────────────
-- Corrida deadline x ChildAdded no MESMO tique -> resultado único, zero ThreadError
-- espúrio de "cannot resume dead coroutine". Duas WaitForChild com o mesmo timeout: A
-- resolve por deadline (o filho que ela espera nunca aparece) e, como efeito colateral da
-- sua própria continuação, cria o filho que B está esperando -- cujo timeout vence NO MESMO
-- tique. As duas entradas ficam juntas em `due` dentro de resumeDueWaiting (Scheduler.luau);
-- B é resolvida via ChildAdded ANINHADO dentro da resolução de A, e o laço de resumeDueWaiting
-- precisa pular a entrada de B (já cancelada) quando chegar nela, sem tentar resumi-la de
-- novo -- exatamente o `cancelled` de WaitingEntry, documentado em Scheduler.luau.
test("7. corrida deadline x ChildAdded no mesmo tique: resultado único, zero ThreadError espúrio", function()
	local scheduler = Scheduler.new()
	local parent = InstanceModule.NewBase("Folder", "Parent")

	local threadErrorCount = 0
	scheduler.ThreadError:Connect(function(_thread: thread, _message: string)
		threadErrorCount += 1
	end)

	local resultA: InstanceModule.Instance? = nil
	local resolvedACount = 0
	scheduler:Spawn(function()
		-- A espera por um nome que nunca aparece: só resolve pelo deadline (1s). A própria
		-- continuação de A cria "Presente" e o parenteia -- disparando ChildAdded no MESMO
		-- instante simulado (self.time == 1) em que o deadline de B também vence.
		resultA = parent:WaitForChild("NuncaAparece", 1)
		resolvedACount += 1
		local presente = InstanceModule.NewBase("Folder", "Presente")
		presente.Parent = parent
	end)

	local resultB: InstanceModule.Instance? = nil
	local resolvedBCount = 0
	scheduler:Spawn(function()
		-- B tem o MESMO timeout (1s) -- sua entrada de deadline fica no mesmo `due` que a de
		-- A dentro do mesmo StepOnce. B deveria resolver pelo ChildAdded (disparado pela
		-- continuação de A), não pelo próprio deadline, que chega a estar "vencido" ao mesmo
		-- tempo mas já foi cancelado quando o laço de resumeDueWaiting chegar nele.
		resultB = parent:WaitForChild("Presente", 1)
		resolvedBCount += 1
	end)

	scheduler:StepOnce(1)

	assert(resolvedACount == 1, `A deveria ter resolvido exatamente uma vez, resolveu {resolvedACount}`)
	assert(resolvedBCount == 1, `B deveria ter resolvido exatamente uma vez (via ChildAdded, correndo contra seu próprio deadline no mesmo tique), resolveu {resolvedBCount}`)
	assert(resultA == nil, "A esperava um filho que nunca aparece antes do timeout -- deveria ter resolvido nil")
	assert(resultB ~= nil, "B deveria ter resolvido com o filho adicionado pela continuação de A")
	assert((resultB :: InstanceModule.Instance).Name == "Presente", "B deveria ter resolvido com o filho certo")
	assert(threadErrorCount == 0, `nenhum ThreadError (nem 'cannot resume dead coroutine') deveria ter disparado nesta corrida, disparou {threadErrorCount}`)
	assert(not scheduler:IsAlive(), "depois que as duas threads resolveram e nada mais está pendente, IsAlive() deveria ser false")
end)

-- ── Cenário 8 ──────────────────────────────────────────────────────────────────────────
-- Erro no primeiro de dois listeners de um mesmo Signal -> o segundo roda mesmo assim.
-- Repro do achado ALTO 3, usando um Signal real de Scheduler (Heartbeat) com dois listeners
-- de verdade -- não um Signal.new() solto -- para exercitar a integração Signal+Scheduler:
-- o erro do primeiro listener é isolado por Fire (pcall individual), reportado via
-- ThreadBroker.ReportError/fireProtected como exatamente 1 ThreadError, e o segundo listener
-- roda mesmo assim no mesmo Fire.
test("8. erro no primeiro de dois listeners de um Signal real (Heartbeat) -> o segundo roda mesmo assim", function()
	local scheduler = Scheduler.new()
	local firstRan = false
	local secondRan = false
	local threadErrorCount = 0
	local threadErrorMessage: string? = nil

	scheduler.ThreadError:Connect(function(_thread: thread, message: string)
		threadErrorCount += 1
		threadErrorMessage = message
	end)

	scheduler.Heartbeat:Connect(function(_dt: number)
		firstRan = true
		error("erro proposital no primeiro listener de Heartbeat")
	end)
	scheduler.Heartbeat:Connect(function(_dt: number)
		secondRan = true
	end)

	scheduler:StepOnce(0.016)

	assert(firstRan, "o primeiro listener deveria ter rodado")
	assert(secondRan, "o segundo listener deveria ter rodado mesmo com o erro no primeiro (isolamento por listener em Fire)")
	assert(threadErrorCount == 1, `o erro do primeiro listener deveria ter virado exatamente 1 ThreadError, ocorreram {threadErrorCount}`)
	assert(threadErrorMessage ~= nil and string.find(threadErrorMessage :: string, "erro proposital no primeiro listener") ~= nil, "mensagem de ThreadError deveria conter a causa original")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
print("\n(cenário 9 -- regressão de Signal.spec/Instance.spec/Scheduler.spec sem alterá-los -- é verificado à parte, rodando os três arquivos diretamente; ver relatório da tarefa)")
process.exit(0)
