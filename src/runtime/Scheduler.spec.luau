--!strict

--[[
	Teste da task-runtime-003 (Scheduler: task.*, coroutine, Heartbeat/Stepped). Cobre, na
	mesma tarefa da lógica que testa (regra 01): concorrência cooperativa real (Wait nunca
	bloqueia o processo), erro dentro de thread spawnada nunca derruba Run()/tick (inclusive
	o caso propagado por Signal:Wait -- ver comentário em Scheduler.luau), Heartbeat/Stepped
	com deltaTime real e ordem relativa entre si, Delay/Defer, Cancel, e IsAlive.

	Roda com `lune run src/runtime/Scheduler.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("./Scheduler")

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

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
