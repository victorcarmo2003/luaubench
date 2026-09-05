--!strict

--[[
	Teste da task-runtime-001 (Signal/Connection genérico). Cobre, na mesma tarefa da
	lógica que testa (regra 01): Connect/Once/DisconnectAll, ordem de disparo do Fire,
	auto-desconexão do Once após a primeira chamada, e o bloqueio real da coroutine
	chamadora em Wait() até o próximo Fire.

	Roda com `lune run src/runtime/Signal.spec.luau`.
]]

local process = require("@lune/process")
local Signal = require("./Signal")
local Scheduler = require("./Scheduler")
-- Módulo-folha interno do território (ver ThreadBroker.luau) -- não faz parte da API pública
-- reexportada por init.luau para services/cli, mas este é um teste de caixa-branca DENTRO do
-- próprio território runtime (mesmo padrão já usado em Integration.spec.luau/task-runtime-012):
-- precisa registrar uma segunda limpeza na MESMA thread para provar, de forma determinística,
-- que o listener interno de Wait() já foi desconectado ANTES dela rodar (ver teste de
-- cancelamento abaixo, task-runtime-020).
local ThreadBroker = require("./ThreadBroker")

-- Roda cada teste imediatamente (em vez de registrar e rodar via pcall depois): o stub de
-- tipo do `pcall` do Luau não modela o valor de erro quando a função protegida retorna `()`
-- (arity fixa em `(boolean, R...)`), então capturar `ok, err = pcall(fn)` para uma `fn` sem
-- retorno é erro de tipagem em --!strict. Deixar o assert de um teste que falhar estourar
-- para fora do chunk (traceback + exit code != 0 do próprio Lune) é mais simples e não exige
-- nenhum cast/`any` para contornar essa limitação do stub de `pcall`.
local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Connect dispara callbacks na ordem de Connect", function()
	local signal = Signal.new()

	local order: { number } = {}
	signal:Connect(function()
		table.insert(order, 1)
	end)
	signal:Connect(function()
		table.insert(order, 2)
	end)
	signal:Connect(function()
		table.insert(order, 3)
	end)

	signal:Fire()

	assert(#order == 3, `esperava 3 chamadas, recebeu {#order}`)
	assert(order[1] == 1, "primeira conexão deveria disparar primeiro")
	assert(order[2] == 2, "segunda conexão deveria disparar em segundo")
	assert(order[3] == 3, "terceira conexão deveria disparar em terceiro")
end)

test("Fire repassa os argumentos do disparo para os callbacks conectados", function()
	local signal: Signal.FireableSignal<number, string> = Signal.new()

	local capturedA: number? = nil
	local capturedB: string? = nil
	signal:Connect(function(a: number, b: string)
		capturedA = a
		capturedB = b
	end)

	signal:Fire(42, "ola")

	assert(capturedA == 42, "argumento numérico não chegou correto")
	assert(capturedB == "ola", "argumento string não chegou correto")
end)

test("Connect/Disconnect: callback desconectado não dispara mais", function()
	local signal = Signal.new()

	local callCount = 0
	local connection = signal:Connect(function()
		callCount += 1
	end)

	signal:Fire()
	assert(callCount == 1, "callback deveria ter disparado uma vez antes do Disconnect")
	assert(connection.Connected, "Connection deveria estar conectada antes do Disconnect")

	connection:Disconnect()
	assert(not connection.Connected, "Connection deveria refletir desconectado após Disconnect")

	signal:Fire()
	assert(callCount == 1, "callback não deveria disparar após Disconnect")
end)

test("Once desconecta após a primeira chamada", function()
	local signal = Signal.new()

	local callCount = 0
	local connection = signal:Once(function()
		callCount += 1
	end)

	assert(connection.Connected, "Connection de Once deveria começar conectada")

	signal:Fire()
	assert(callCount == 1, "callback de Once deveria disparar na primeira chamada")
	assert(not connection.Connected, "Connection de Once deveria estar desconectada após disparar")

	signal:Fire()
	assert(callCount == 1, "callback de Once não deveria disparar de novo no segundo Fire")
end)

test("DisconnectAll remove todos os listeners de uma vez", function()
	local signal = Signal.new()

	local callCount = 0
	local connectionA = signal:Connect(function()
		callCount += 1
	end)
	local connectionB = signal:Connect(function()
		callCount += 1
	end)

	signal:DisconnectAll()

	assert(not connectionA.Connected, "connectionA deveria estar desconectada após DisconnectAll")
	assert(not connectionB.Connected, "connectionB deveria estar desconectada após DisconnectAll")

	signal:Fire()
	assert(callCount == 0, "nenhum callback deveria disparar após DisconnectAll")
end)

test("Wait() bloqueia a coroutine chamadora até o próximo Fire e retorna os argumentos", function()
	local signal: Signal.FireableSignal<number, string> = Signal.new()

	local resultA: number? = nil
	local resultB: string? = nil
	local finished = false

	local waiter = coroutine.create(function()
		local a, b = signal:Wait()
		resultA = a
		resultB = b
		finished = true
	end)

	local ok = coroutine.resume(waiter)
	assert(ok, "coroutine deveria iniciar sem erro")
	assert(coroutine.status(waiter) == "suspended", "coroutine deveria estar suspensa esperando Wait()")
	assert(not finished, "Wait() não deveria retornar antes do Fire")

	signal:Fire(7, "acordou")

	assert(finished, "Wait() deveria ter retornado depois do Fire")
	assert(resultA == 7, "Wait() deveria devolver o primeiro argumento do Fire")
	assert(resultB == "acordou", "Wait() deveria devolver o segundo argumento do Fire")
	assert(coroutine.status(waiter) == "dead", "coroutine deveria ter terminado após Wait() retornar")
end)

test("Cancelar uma thread real parada em Signal:Wait() desconecta o listener interno no momento do Cancel (task-runtime-020)", function()
	local scheduler = Scheduler.new()
	local signal: Signal.FireableSignal<number> = Signal.new()

	local resolvedNaturally = false
	local handle = scheduler:Spawn(function()
		signal:Wait()
		resolvedNaturally = true
	end)

	assert(coroutine.status(handle) == "suspended", "esperava a thread presa em Signal:Wait() sob o Scheduler")

	-- Registra uma SEGUNDA limpeza na mesma thread, DEPOIS da que Signal.luau já registrou
	-- dentro de Wait() (RunCleanups roda na ordem de registro -- ver ThreadBroker.luau). Quando
	-- Scheduler:Cancel chamar RunCleanups, a limpeza de Signal.luau (desconectar o listener
	-- interno) roda PRIMEIRO; só depois roda este probe. Nesse instante exato a coroutine ainda
	-- está "suspended" (Cancel só fecha com coroutine.close DEPOIS de RunCleanups retornar) e
	-- ThreadBroker já não tem mais driver para `handle` (Release roda antes de RunCleanups em
	-- Cancel) -- então, SE o listener interno de Wait() ainda estivesse conectado, este Fire o
	-- encontraria vivo e ThreadBroker.Resume cairia no fallback standalone (coroutine ainda
	-- suspensa -> coroutine.resume cru), resumindo `handle` de verdade e virando
	-- `resolvedNaturally = true`. Se o listener já foi desconectado (comportamento corrigido por
	-- esta tarefa), este Fire não encontra mais ninguém e nada acontece.
	local probeRanDuringCancel = false
	ThreadBroker.RegisterCleanup(handle, function()
		probeRanDuringCancel = true
		signal:Fire(99)
	end)

	scheduler:Cancel(handle)

	assert(probeRanDuringCancel, "a limpeza de instrumentação deveria ter rodado dentro de Scheduler:Cancel")
	assert(
		not resolvedNaturally,
		"o listener interno de Signal:Wait() deveria ter sido desconectado pelo cleanup que Signal.luau registra (roda ANTES deste probe, mesma ordem de RegisterCleanup) -- se ainda estivesse conectado, o Fire disparado pelo probe (coroutine ainda 'suspended', antes de coroutine.close) teria resumido a thread de verdade"
	)
	assert(coroutine.status(handle) == "dead", "após Cancel, a coroutine deveria estar fechada (dead)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
