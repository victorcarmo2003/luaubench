--!strict

-- Cenário: uma biblioteca de Signal "de terceiros" real (fixture adaptada de um jogo de
-- verdade do usuário -- ver tests/scenarios/fixtures/ThirdPartySignal.luau) sendo usada DE
-- DENTRO de threads geridas pelo Scheduler do LuauBench. O ponto central: essa lib de
-- terceiros faz `coroutine.resume` CRU dentro do seu `:Wait()`, nunca passando pelo
-- ThreadBroker -- exatamente a classe de bug que já foi achado GRAVE dentro do próprio
-- Signal.luau do LuauBench antes do ThreadBroker existir (ver Scheduler.luau, comentário de
-- topo, e ThreadBroker.luau). Este cenário pergunta: o Scheduler aguenta um script real que
-- usa a PRÓPRIA lib de evento (não a do LuauBench) sem vazar thread nem travar o laço
-- principal?
-- Origem: PLANE/src/shared/Modux/src/Signal.luau (via fixture) -- padrão real usado em pelo
-- menos 9 jogos do usuário (AnimeFallen, Towers, Frozen_Faithless, Hide-or-Hit, CodeBreaker,
-- RunningSmth, TheGame, SquishObby, BallBrawl).
-- Superfície exercitada: Scheduler.new/Spawn/StepOnce/IsAlive/ThreadError (a lib de terceiros
-- em si não usa nada do LuauBench -- de propósito, pra isolar o comportamento do Scheduler
-- quando não é ele quem resume a thread).
-- Status: passa hoje.

local process = require("@lune/process")
local Scheduler = require("../../src/runtime/Scheduler")
local ThirdPartySignal = require("./fixtures/ThirdPartySignal")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("sanidade: Connect/Fire/DisconnectAll da lib de terceiros funcionam isolados (sem Scheduler)", function()
	local signal = ThirdPartySignal.new()
	local received: { number } = {}
	signal:Connect(function(n: number)
		table.insert(received, n)
	end)
	signal:Fire(1)
	signal:Fire(2)
	assert(#received == 2 and received[1] == 1 and received[2] == 2, "Connect/Fire deveriam funcionar igual ao original")

	signal:DisconnectAll()
	signal:Fire(3)
	assert(#received == 2, "depois de DisconnectAll, Fire não deveria disparar mais nada")
end)

test("proxytable da lib de terceiros: escrever connection.Connected = false desconecta sem chamar :Disconnect()", function()
	local signal = ThirdPartySignal.new()
	local callCount = 0
	local connection = signal:Connect(function()
		callCount += 1
	end)

	signal:Fire()
	assert(callCount == 1, "callback deveria ter disparado uma vez")

	-- Escrita direta no campo, não chamada de método -- exercita o __newindex customizado da
	-- Connection da lib de terceiros (não tem nada a ver com o __newindex de Instance.luau).
	connection.Connected = false

	signal:Fire()
	assert(callCount == 1, "depois de connection.Connected = false, o callback não deveria disparar de novo")
end)

test("Wait() da lib de terceiros dentro de uma thread do Scheduler: Fire() de FORA resolve, e a thread morre corretamente rastreada", function()
	local scheduler = Scheduler.new()
	local signal = ThirdPartySignal.new()

	local received: number? = nil
	local handle = scheduler:Spawn(function()
		received = signal:Wait()
	end)

	assert(scheduler:IsAlive(), "logo após Spawn, a thread suspensa em Wait() (lib de terceiros) deveria manter IsAlive() true")
	assert(coroutine.status(handle) == "suspended", "a coroutine deveria estar suspensa dentro do Wait() de terceiros")

	-- Fire() chamado diretamente (fora de qualquer Spawn/StepOnce do Scheduler) -- é a lib de
	-- terceiros, por baixo, chamando coroutine.resume(thread, ...) CRU, nunca
	-- ThreadBroker.Resume.
	signal:Fire(42)

	assert(received == 42, "Wait() deveria ter retornado o valor disparado por Fire()")
	assert(coroutine.status(handle) == "dead", "a coroutine deveria estar morta depois do resume cru da lib de terceiros")

	-- A pergunta real do cenário: o Scheduler DETECTA que essa thread morreu, mesmo sem ter
	-- sido ele quem a resumiu? IsAlive() tem uma rede de segurança pra exatamente isso
	-- (Scheduler.luau: poda liveThreads pra qualquer entrada com coroutine.status == "dead").
	assert(not scheduler:IsAlive(), "IsAlive() deveria detectar e podar a thread morta por fora, mesmo sem ThreadBroker ter mediado o resume")
end)

test("Wait() da lib de terceiros: se o Fire() acontece ENQUANTO o Scheduler está processando outro tique, nada trava", function()
	local scheduler = Scheduler.new()
	local signal = ThirdPartySignal.new()

	local waiterDone = false
	scheduler:Spawn(function()
		signal:Wait()
		waiterDone = true
	end)

	-- Um segundo script, gerido normalmente pelo Scheduler, dispara o Fire() de dentro do seu
	-- próprio tique -- ou seja, o resume cru da lib de terceiros acontece ANINHADO dentro de
	-- um StepOnce, não fora dele.
	scheduler:Spawn(function()
		scheduler:Wait(0.05)
		signal:Fire("de dentro de outro script")
	end)

	for _ = 1, 3 do
		scheduler:StepOnce(0.05)
	end

	assert(waiterDone, "o script esperando em Wait() deveria ter sido resolvido pelo Fire() disparado de dentro de outro tique")
	assert(not scheduler:IsAlive(), "depois que os dois scripts terminam, IsAlive() deveria ficar false (sem leak de liveThreads)")
end)

test("erro DEPOIS de um Wait() da lib de terceiros: divergência documentada -- o erro é engolido por completo, sem propagar e sem virar ThreadError", function()
	-- Isto não é um bug do LuauBench: é uma propriedade da própria lib de terceiros (ver
	-- comentário no fixture) -- `coroutine.resume(thread, ...)` dentro do Wait() dela descarta
	-- o (ok, err) do resume, e `coroutine.resume` NUNCA propaga o erro do lado de dentro como
	-- um erro Lua de verdade pra quem chamou resume (isso é semântica padrão de
	-- coroutine.resume, igual no Roblox real) -- ele só retorna (false, mensagem), que aqui
	-- ninguém lê. Resultado real, confirmado rodando: `Signal:Fire()` NÃO propaga nada (o
	-- `pcall(connection._callback, ...)` dentro de Fire vê `success = true`, porque a callback
	-- em si não erroou -- só resumiu uma thread que, por dentro, errou e morreu sozinha) E o
	-- Scheduler nunca vê esse erro (nunca passou por ThreadBroker.ReportError). Um script real
	-- usando essa lib real perderia esse erro tão silenciosamente no LuauBench quanto perderia
	-- no Roblox real -- mesma semântica de coroutine.resume cru em Lua/Luau puro, não é
	-- divergência introduzida pelo LuauBench.
	local scheduler = Scheduler.new()
	local signal = ThirdPartySignal.new()

	local handle = scheduler:Spawn(function()
		signal:Wait()
		error("erro depois do Wait() de terceiros -- deveria ser engolido")
	end)

	local capturedErrors: { string } = {}
	scheduler.ThreadError:Connect(function(_thread: thread, message: string)
		table.insert(capturedErrors, message)
	end)

	local fireOk = pcall(function()
		signal:Fire()
	end)

	assert(fireOk, "Fire() NÃO deveria propagar nada: coroutine.resume nunca relança erro de dentro da coroutine pra quem chamou resume")
	assert(coroutine.status(handle) == "dead", "a coroutine deveria estar morta (error() dentro dela também mata a coroutine, igual término normal)")
	assert(#capturedErrors == 0, "o Scheduler NÃO deveria ter capturado este erro como ThreadError -- ele nunca passou pelo ThreadBroker")
	assert(not scheduler:IsAlive(), "a thread morta (por erro) deveria ser podada por IsAlive() mesmo sem ThreadBroker ter mediado o resume")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
