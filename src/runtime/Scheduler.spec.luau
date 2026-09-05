--!strict

--[[
	Teste da task-runtime-003 (Scheduler: task.*, coroutine, Heartbeat/Stepped). Cobre, na
	mesma tarefa da lógica que testa (regra 01): concorrência cooperativa real (Wait nunca
	bloqueia o processo), erro dentro de thread spawnada nunca derruba Run()/tick (inclusive
	o caso propagado por Signal:Wait -- ver comentário em Scheduler.luau), Heartbeat/Stepped
	com deltaTime real e ordem relativa entre si, Delay/Defer, Cancel, e IsAlive.

	task-runtime-011 acrescenta os testes de `ThreadBroker.RegisterCleanup`/`RunCleanups`
	(achado MÉDIO de task-runtime-008 -- Cancel não desconectava Connection que a thread
	cancelada tinha registrado num Signal alheio): requer `ThreadBroker.luau` e `Signal.luau`
	diretamente, mesmo padrão de teste de caixa-branca já usado em Integration.spec.luau
	(task-runtime-012) para inspecionar o território `runtime` por dentro.

	Roda com `lune run src/runtime/Scheduler.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("./Scheduler")
local ThreadBroker = require("./ThreadBroker")
local Signal = require("./Signal")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("dois spawns concorrentes: o de wait mais curto roda enquanto o outro ainda espera", function()
	local scheduler = Scheduler.new()
	local order: { string } = {}

	scheduler:Spawn(function()
		table.insert(order, "A-start")
		scheduler:Wait(1)
		table.insert(order, "A-end")
	end)
	scheduler:Spawn(function()
		table.insert(order, "B-start")
		scheduler:Wait(0.1)
		table.insert(order, "B-end")
	end)

	assert(#order == 2, `ambos deveriam ter rodado até o primeiro yield antes de qualquer StepOnce, recebeu {#order}`)
	assert(order[1] == "A-start" and order[2] == "B-start", "spawn roda imediato/síncrono, na ordem de chamada")

	scheduler:StepOnce(0.1)
	assert(#order == 3 and order[3] == "B-end", "B (wait mais curto) deveria resolver sem esperar A terminar")

	scheduler:StepOnce(0.95)
	assert(#order == 4 and order[4] == "A-end", "A deveria resolver só quando seu 1s total decorrer")
end)

test("erro dentro de thread spawnada dispara ThreadError e nunca derruba o Scheduler", function()
	local scheduler = Scheduler.new()
	local errorThread: thread? = nil
	local errorMessage: string? = nil
	scheduler.ThreadError:Connect(function(thread, message)
		errorThread = thread
		errorMessage = message
	end)

	local handle = scheduler:Spawn(function()
		error("boom")
	end)

	assert(errorThread == handle, "ThreadError deveria identificar a thread que errou")
	assert(errorMessage ~= nil and string.find(errorMessage :: string, "boom") ~= nil, "mensagem de erro deveria conter a causa original")

	local ranAfter = false
	scheduler:Spawn(function()
		ranAfter = true
	end)
	assert(ranAfter, "scheduler deveria continuar aceitando/rodando novas threads normalmente após o erro")
end)

test("erro dentro de thread spawnada não derruba Run() (com task.wait real)", function()
	local scheduler = Scheduler.new()
	local errorFired = false
	scheduler.ThreadError:Connect(function(_thread, _message)
		errorFired = true
	end)

	scheduler:Spawn(function()
		scheduler:Wait(0.01)
		error("erro dentro de spawn, depois de um wait")
	end)

	local completed = false
	scheduler:Spawn(function()
		scheduler:Wait(0.03)
		completed = true
	end)

	scheduler:Run()

	assert(errorFired, "ThreadError deveria ter disparado durante Run()")
	assert(completed, "a outra thread spawnada deveria ter completado normalmente, Run() não pode ter derrubado")
	assert(not scheduler:IsAlive(), "depois de Run() retornar, não deveria sobrar nada pendente")
end)

test("erro após Heartbeat:Wait() não derruba tick/Run() (Signal:Wait repropaga o erro para dentro do Fire)", function()
	local scheduler = Scheduler.new()
	local errorFired = false
	scheduler.ThreadError:Connect(function(_thread, message)
		errorFired = true
		assert(string.find(message, "boom apos heartbeat") ~= nil, "mensagem deveria conter a causa original")
	end)

	scheduler:Spawn(function()
		scheduler.Heartbeat:Wait()
		error("boom apos heartbeat")
	end)

	-- Sem a proteção de fireProtected em Scheduler.luau, este StepOnce propagaria o erro pra
	-- fora (crash do teste) em vez de convertê-lo em ThreadError.
	scheduler:StepOnce(0.016)

	assert(errorFired, "ThreadError deveria ter disparado mesmo com o erro vindo de dentro do próprio Fire de Heartbeat")
end)

test("Delay agenda execução só depois do tempo decorrido, nunca antes", function()
	local scheduler = Scheduler.new()
	local ran = false
	scheduler:Delay(0.5, function()
		ran = true
	end)

	scheduler:StepOnce(0.2)
	assert(not ran, "não deveria ter rodado ainda (0.2s < 0.5s)")

	scheduler:StepOnce(0.35)
	assert(ran, "deveria ter rodado após 0.55s acumulados no total")
end)

test("Defer roda depois de todo o trabalho imediato (spawn) do mesmo tique", function()
	local scheduler = Scheduler.new()
	local order: { string } = {}

	scheduler:Defer(function()
		table.insert(order, "deferred")
	end)
	scheduler:Spawn(function()
		table.insert(order, "spawned")
	end)

	assert(#order == 1 and order[1] == "spawned", "spawn já deveria ter rodado; defer ainda não")

	scheduler:StepOnce(0.016)
	assert(#order == 2 and order[2] == "deferred", "defer deveria rodar no tique seguinte, depois do spawn imediato")
end)

test("StepOnce dispara Stepped antes de Heartbeat, com deltaTime/time corretos", function()
	local scheduler = Scheduler.new()
	local order: { string } = {}
	local steppedDt: number = 0
	local steppedTime: number = 0
	local heartbeatDt: number = 0

	scheduler.Stepped:Connect(function(time, dt)
		table.insert(order, "stepped")
		steppedTime = time
		steppedDt = dt
	end)
	scheduler.Heartbeat:Connect(function(dt)
		table.insert(order, "heartbeat")
		heartbeatDt = dt
	end)

	scheduler:StepOnce(0.25)
	assert(order[1] == "stepped" and order[2] == "heartbeat", "Stepped deve disparar antes de Heartbeat no mesmo tique")
	assert(steppedDt == 0.25, `Stepped dt esperado 0.25, recebeu {steppedDt}`)
	assert(heartbeatDt == 0.25, `Heartbeat dt esperado 0.25, recebeu {heartbeatDt}`)
	assert(steppedTime == 0.25, `Stepped time esperado 0.25, recebeu {steppedTime}`)

	scheduler:StepOnce(0.1)
	assert(steppedTime == 0.35000000000000003 or math.abs(steppedTime - 0.35) < 1e-9, "tempo acumulado deveria somar os tiques")
end)

test("Cancel impede que uma thread agendada via Delay seja retomada", function()
	local scheduler = Scheduler.new()
	local ran = false
	local handle = scheduler:Delay(0.1, function()
		ran = true
	end)

	scheduler:Cancel(handle)
	scheduler:StepOnce(0.2)

	assert(not ran, "thread cancelada não deveria rodar")
	assert(coroutine.status(handle) == "dead", "thread cancelada deveria estar fechada (dead)")
end)

test("Cancel impede retomada de uma thread suspensa em Scheduler:Wait", function()
	local scheduler = Scheduler.new()
	local resumed = false
	local handle = scheduler:Spawn(function()
		scheduler:Wait(1)
		resumed = true
	end)

	scheduler:Cancel(handle)
	scheduler:StepOnce(2)

	assert(not resumed, "thread cancelada durante Wait não deveria retomar")
end)

test("IsAlive reflete threads pendentes e conexões vivas de Heartbeat/Stepped", function()
	local scheduler = Scheduler.new()
	assert(not scheduler:IsAlive(), "scheduler recém-criado, sem nada pendente, não deveria estar vivo")

	local connection = scheduler.Heartbeat:Connect(function() end)
	assert(scheduler:IsAlive(), "conexão viva em Heartbeat deveria manter IsAlive verdadeiro")
	connection:Disconnect()
	assert(not scheduler:IsAlive(), "sem conexões nem threads pendentes, IsAlive deveria voltar a falso")

	local finished = false
	scheduler:Spawn(function()
		scheduler:Wait(1)
		finished = true
	end)
	assert(scheduler:IsAlive(), "thread suspensa em Wait deveria manter IsAlive verdadeiro")

	scheduler:StepOnce(1)
	assert(finished, "thread deveria ter terminado após o tempo decorrido")
	assert(not scheduler:IsAlive(), "após a thread terminar e nada mais pendente, IsAlive deveria voltar a falso")
end)

test("Scheduler:Wait fora de uma thread gerida lança erro claro (nunca yield solto)", function()
	local scheduler = Scheduler.new()
	local ok = pcall(function()
		scheduler:Wait(0.1)
	end)
	assert(not ok, "Wait chamado fora de uma thread gerida pelo Scheduler deveria falhar, não travar/yield solto")
end)

test("Run() roda até IsAlive() ficar falso e retorna sozinho (task.wait real, cooperativo)", function()
	local scheduler = Scheduler.new()
	local order: { string } = {}

	scheduler:Spawn(function()
		table.insert(order, "A-start")
		scheduler:Wait(0.02)
		table.insert(order, "A-end")
	end)
	scheduler:Spawn(function()
		table.insert(order, "B-start")
		scheduler:Wait(0.05)
		table.insert(order, "B-end")
	end)

	scheduler:Run()

	assert(#order == 4, `esperava 4 eventos, recebeu {#order}`)
	assert(order[3] == "A-end", "A (wait mais curto) deveria terminar antes de B")
	assert(order[4] == "B-end", "B deveria terminar por último")
	assert(not scheduler:IsAlive(), "depois de Run() retornar, não deveria sobrar nada pendente")
end)

test("Cancel desconecta, no momento do cancelamento, uma Connection registrada via ThreadBroker.RegisterCleanup pela thread cancelada (repro do achado de task-runtime-011 -- padrão do ramo B de WaitForChild com timeout)", function()
	local scheduler = Scheduler.new()
	-- Simula o padrão de Instance:WaitForChild com timeout (Instance.luau, fora do território
	-- desta tarefa): a thread gerida conecta (Connect, NÃO Once -- não se autolimpa num Fire
	-- genérico que não bata o alvo esperado) um listener num Signal alheio e registra a
	-- própria desconexão como limpeza da thread, para o Scheduler poder desfazer no Cancel
	-- sem esperar o evento disparar de novo.
	local childAdded: Signal.FireableSignal<string> = Signal.new()
	local capturedConnection: Signal.Connection? = nil

	local handle = scheduler:Spawn(function()
		local co = coroutine.running()
		local connection = childAdded:Connect(function(_name: string) end)
		capturedConnection = connection
		ThreadBroker.RegisterCleanup(co, function()
			connection:Disconnect()
		end)
		scheduler:Wait(10) -- mantém a thread suspensa, como o WakeAfter de WaitForChild faria
	end)

	assert(capturedConnection ~= nil, "a thread deveria ter conectado o listener antes do primeiro yield (Spawn roda síncrono até lá)")
	assert((capturedConnection :: Signal.Connection).Connected, "listener deveria estar conectado antes do Cancel")

	scheduler:Cancel(handle)

	assert(
		not (capturedConnection :: Signal.Connection).Connected,
		"Cancel deveria ter desconectado o listener no PRÓPRIO momento do cancelamento, sem esperar childAdded disparar de novo"
	)
end)

test("RunCleanups (via Cancel) isola erro entre múltiplas limpezas da mesma thread -- uma falhar não impede as demais nem propaga para quem chamou Cancel", function()
	local scheduler = Scheduler.new()
	local secondRan = false

	local handle = scheduler:Spawn(function()
		local co = coroutine.running()
		ThreadBroker.RegisterCleanup(co, function()
			error("limpeza 1 falhou de propósito")
		end)
		ThreadBroker.RegisterCleanup(co, function()
			secondRan = true
		end)
		scheduler:Wait(10)
	end)

	local ok = pcall(function()
		scheduler:Cancel(handle)
	end)

	assert(ok, "Cancel não pode propagar erro de uma limpeza que falhou")
	assert(secondRan, "a segunda limpeza registrada para a mesma thread deveria rodar mesmo com a primeira falhando")
end)

test("ThreadBroker.RegisterCleanup devolve desregistro idempotente -- limpeza desregistrada antes do Cancel não roda mais", function()
	local scheduler = Scheduler.new()
	local ran = false
	local unregister: (() -> ())? = nil

	local handle = scheduler:Spawn(function()
		local co = coroutine.running()
		unregister = ThreadBroker.RegisterCleanup(co, function()
			ran = true
		end)
		scheduler:Wait(10)
	end)

	assert(unregister ~= nil, "RegisterCleanup deveria ter devolvido a função de desregistro")
	local doUnregister = unregister :: () -> ()
	doUnregister()
	-- Chamar de novo deveria ser no-op (idempotente), nunca erro nem duplicar a remoção.
	doUnregister()

	scheduler:Cancel(handle)

	assert(not ran, "limpeza desregistrada antes do Cancel não deveria rodar quando a thread for cancelada")
end)

test("Cancel de uma thread sem nenhuma limpeza registrada continua no-op seguro (RunCleanups não exige registro prévio)", function()
	local scheduler = Scheduler.new()
	local handle = scheduler:Spawn(function()
		scheduler:Wait(10)
	end)

	local ok = pcall(function()
		scheduler:Cancel(handle)
	end)

	assert(ok, "Cancel de thread sem limpezas registradas nunca deveria lançar erro")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
