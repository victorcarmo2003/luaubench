--!strict

--[[
	Teste dedicado de `./MessagingService.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Cobre o acceptance de task-services-021: eco local fiel (o publisher recebe a própria
	mensagem), formato `{ Data, Sent }`, múltiplos assinantes na ordem de inscrição, entrega
	ASSÍNCRONA (nunca síncrona dentro de `PublishAsync`), `Disconnect` cancelando de verdade, erro
	num callback isolado (não impede os outros nem derruba o processo -- via o próprio mecanismo de
	`ThreadError` do Scheduler, nunca um `pcall` manual deste módulo), e a validação de tamanho de
	mensagem (1 kB)/tópico (1-80 caracteres).

	BLOQUEIO REPORTADO EM task-services-021, FECHADO EM task-services-022: `MessagingService`
	ficou fora de `tools/coverage.luau`/`generated/**` até task-services-022 acrescentá-la ao
	gerador (junto com `HttpService`, mesma tarefa, para não rodar o gerador duas vezes -- ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.2"/"L2.3"). Agora que
	`generated/classes/MessagingService.luau` existe de verdade, este spec alcança a classe pelo
	caminho REAL -- `Services.Register()` (que itera `generated/Index.luau` cruzado com
	`behavior/Index.luau`, e já tinha a entrada `MessagingService` pronta desde task-services-021)
	seguido de `game:GetService("MessagingService")` -- MESMO padrão de
	`./DataStoreService.spec.luau`/`./HttpService.spec.luau`. Registrar a classe À MÃO aqui (como
	este spec fazia antes de task-services-022) colidiria com esse registro real ("classe já
	registrada em ClassRegistry").

	Todo método (`PublishAsync`/`SubscribeAsync`) passa por `../AsyncCall.luau`
	(`Context.GetScheduler():Wait(0)`) -- por isso toda chamada que deve SUCEDER até o fim roda
	dentro de `scheduler:Spawn(...)` seguido de `scheduler:StepOnce(0)` (mesmo padrão de
	`runAsync` em `../behavior/GlobalDataStore.spec.luau`/`../AsyncCall.spec.luau`). Uma chamada
	que deve ERRAR por VALIDAÇÃO (tópico/mensagem inválidos) roda DIRETO, fora de `runAsync`: a
	validação acontece ANTES do `AsyncCall.Yield` (mesma disciplina de `GlobalDataStore.luau`), e
	`Scheduler.Spawn` NUNCA propaga um erro síncrono da thread gerida de volta para quem chamou
	`Spawn` (ele vira `ThreadError` internamente) -- `pcall` em volta de `runAsync(...)` nunca
	pegaria esse erro; chamar direto é o jeito certo de testar validação síncrona.

	`subscriptionsByTopic` (estado de `./MessagingService.luau`) é module-local e persiste pelo
	spec INTEIRO (um único processo Lune) -- por isso cada teste usa um TÓPICO exclusivo (mesma
	disciplina de nome de DataStore exclusivo por teste em `GlobalDataStore.spec.luau`).

	Roda com `lune run src/services/behavior/MessagingService.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")

type Dynamic = { [string]: unknown }
type MessagePayload = { Data: unknown, Sent: number }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Ver cabeçalho, "BLOQUEIO REPORTADO EM task-services-021, FECHADO EM task-services-022":
-- `MessagingService` agora é registrada pelo caminho REAL (generated/Index.luau x
-- behavior/Index.luau) -- registro à mão via ClassBuilder/ClassRegistry.Register, como este spec
-- fazia antes desta tarefa, colidiria com este registro real.
Services.Register()

local scheduler = Runtime.Scheduler.new()
local game = Runtime.DataModel.new()
Services.Bootstrap({ scheduler = scheduler, dataModel = game })

-- Instância única, compartilhada pelo arquivo inteiro -- `MessagingService` é singleton de
-- verdade (estado module-local em `./MessagingService.luau`, nunca por instância), mesma
-- disciplina de `dataStoreService` em `GlobalDataStore.spec.luau`. Alcançada por
-- `game:GetService`, o caminho que um script real usaria (`Runtime.ClassRegistry.
-- NewEngineInstance` continua funcionando, mas deixou de ser necessário aqui).
local messagingService = (game:GetService("MessagingService") :: unknown) :: Dynamic
local publishAsync = messagingService.PublishAsync :: (self: Dynamic, topic: string, message: unknown) -> ()
local subscribeAsync = messagingService.SubscribeAsync :: (self: Dynamic, topic: string, callback: (MessagePayload) -> ()) -> Runtime.Connection

-- Chama `body` dentro de uma thread gerida pelo Scheduler e avança exatamente um passo -- basta
-- para o único `AsyncCall.Yield` (`Wait(0)`) que cada chamada de `PublishAsync`/`SubscribeAsync`
-- faz. Mesmo padrão de `runAsync` em `../behavior/GlobalDataStore.spec.luau`.
local function runAsync(body: () -> ()): ()
	scheduler:Spawn(body)
	scheduler:StepOnce(0)
end

test("PublishAsync entrega ao PRÓPRIO processo (eco local fiel, L2.3.1) com { Data, Sent } corretos -- NUNCA filtrado", function()
	local topic = "Spec1"
	local received: MessagePayload? = nil

	runAsync(function()
		subscribeAsync(messagingService, topic, function(message: MessagePayload)
			received = message
		end)
	end)

	local beforePublish = os.time()
	runAsync(function()
		publishAsync(messagingService, topic, "hello")
	end)

	assert(
		received ~= nil,
		"o publisher (este mesmo processo) deveria ter recebido a própria mensagem publicada -- eco local fiel, nunca filtrado por identidade (L2.3.1)"
	)
	local receivedNonNil = received :: MessagePayload
	assert(receivedNonNil.Data == "hello", `Data deveria ser exatamente a mensagem publicada, recebeu {tostring(receivedNonNil.Data)}`)
	assert(type(receivedNonNil.Sent) == "number", `Sent deveria ser number (Unix time em segundos), recebeu {type(receivedNonNil.Sent)}`)
	assert(receivedNonNil.Sent >= beforePublish, "Sent deveria ser >= o instante (os.time()) em que PublishAsync foi chamado")
end)

test("múltiplos assinantes recebem NA ORDEM DE INSCRIÇÃO (aproximação declarada -- Roblox não garante ordem)", function()
	local topic = "Spec2"
	local order: { number } = {}

	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			table.insert(order, 1)
		end)
	end)
	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			table.insert(order, 2)
		end)
	end)
	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			table.insert(order, 3)
		end)
	end)

	runAsync(function()
		publishAsync(messagingService, topic, "x")
	end)

	assert(#order == 3, `esperava 3 callbacks disparados, recebeu {#order}`)
	assert(
		order[1] == 1 and order[2] == 2 and order[3] == 3,
		`ordem deveria ser [1, 2, 3] (ordem de inscrição), recebeu [{order[1]}, {order[2]}, {order[3]}]`
	)
end)

test("entrega é ASSÍNCRONA -- PublishAsync yielda e o callback só roda DEPOIS de um passo de scheduler, nunca dentro do próprio frame", function()
	local topic = "Spec3"
	local fired = false
	local publishReturned = false

	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			fired = true
		end)
	end)

	scheduler:Spawn(function()
		publishAsync(messagingService, topic, "x")
		publishReturned = true
	end)

	-- Scheduler.Spawn roda a thread imediatamente, de forma síncrona, até o primeiro yield --
	-- logo após este Spawn devolver o controle, a thread de PublishAsync ainda deveria estar
	-- PARADA dentro do AsyncCall.Yield (Wait(0) chama coroutine.yield()): nem PublishAsync
	-- retornou, nem o callback do assinante rodou.
	assert(not publishReturned, "PublishAsync não deveria ter retornado antes de qualquer StepOnce -- Wait(0) suspende de verdade")
	assert(
		not fired,
		"o callback NÃO deveria ter disparado antes de qualquer StepOnce -- entrega assíncrona, nunca síncrona dentro do frame de PublishAsync"
	)

	scheduler:StepOnce(0)

	assert(publishReturned, "PublishAsync deveria ter retornado depois de exatamente um passo de scheduler")
	assert(fired, "o callback deveria ter disparado depois de exatamente um passo de scheduler (despachado via Scheduler:Spawn dentro de PublishAsync)")
end)

test("SubscribeAsync devolve uma Connection -- :Disconnect() cancela DE VERDADE (mensagem publicada depois não chega mais)", function()
	local topic = "Spec4"
	local callCount = 0
	local connection: Runtime.Connection? = nil

	runAsync(function()
		connection = subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			callCount += 1
		end)
	end)
	local nonNilConnection = connection :: Runtime.Connection
	-- `assert(x.Connected, ...)`/`assert(not x.Connected, ...)`, nunca `== true`/`== false` --
	-- mesma convenção de `src/runtime/Signal.spec.luau` (evita, de quebra, um falso-positivo do
	-- `luau-lsp` que estreita `Connected` para o tipo literal `true` depois do primeiro assert e
	-- reclama de comparar com `false` mais abaixo).
	assert(nonNilConnection.Connected, "Connection.Connected deveria ser true logo após SubscribeAsync")

	runAsync(function()
		publishAsync(messagingService, topic, "first")
	end)
	assert(callCount == 1, `esperava 1 chamada depois da primeira publicação, recebeu {callCount}`)

	nonNilConnection:Disconnect()
	assert(not nonNilConnection.Connected, "Connection.Connected deveria ser false depois de Disconnect")

	runAsync(function()
		publishAsync(messagingService, topic, "second")
	end)
	assert(callCount == 1, `depois de Disconnect, uma publicação seguinte NÃO deveria disparar o callback -- ainda {callCount}`)

	-- Idempotência -- chamar Disconnect de novo não deveria erro nem alterar nada.
	nonNilConnection:Disconnect()
	assert(not nonNilConnection.Connected, "uma segunda chamada a Disconnect deveria ser no-op, Connected continua false")
end)

test("erro DENTRO de um callback sai por Scheduler.ThreadError (nunca engolido) e NÃO impede os outros assinantes nem derruba o processo", function()
	local topic = "Spec5"
	local secondFired = false
	local threadErrorCount = 0
	local threadErrorMessage: string? = nil

	local errorConnection = scheduler.ThreadError:Connect(function(_thread: thread, message: string)
		threadErrorCount += 1
		threadErrorMessage = message
	end)

	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			error("erro proposital do primeiro assinante")
		end)
	end)
	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			secondFired = true
		end)
	end)

	-- SEM pcall em volta desta publicação -- é exatamente o ponto: o erro do primeiro assinante
	-- roda isolado na PRÓPRIA coroutine dele (via Scheduler:Spawn dentro de PublishAsync) e sai
	-- por ThreadError, nunca propaga para este teste nem para o segundo assinante.
	runAsync(function()
		publishAsync(messagingService, topic, "x")
	end)

	assert(secondFired, "o SEGUNDO assinante deveria ter disparado normalmente, mesmo o primeiro tendo lançado erro")
	assert(threadErrorCount == 1, `esperava exatamente 1 ThreadError (do primeiro assinante), recebeu {threadErrorCount}`)
	assert(
		string.find(threadErrorMessage or "", "erro proposital do primeiro assinante", 1, true) ~= nil,
		`ThreadError deveria carregar a mensagem original do erro do callback, recebeu: {tostring(threadErrorMessage)}`
	)

	errorConnection:Disconnect()
end)

test("PublishAsync ERRA com tópico vazio (0 caracteres, abaixo do mínimo de 1) -- validado ANTES do Yield, chamada direta (sem thread gerida)", function()
	local ok, err = pcall(function()
		publishAsync(messagingService, "", "x")
	end)
	assert(not ok, "PublishAsync com tópico vazio deveria erro")
	assert(
		string.find(tostring(err), "between 1 and 80 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 1-80 caracteres, recebeu: {err}`
	)
end)

test("PublishAsync ERRA com tópico de 81 caracteres (acima do máximo de 80)", function()
	local longTopic = string.rep("a", 81)
	local ok, err = pcall(function()
		publishAsync(messagingService, longTopic, "x")
	end)
	assert(not ok, "PublishAsync com tópico de 81 caracteres deveria erro")
	assert(
		string.find(tostring(err), "between 1 and 80 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 1-80 caracteres, recebeu: {err}`
	)
end)

test("SubscribeAsync ERRA com tópico fora de 1-80 caracteres -- MESMA validação de PublishAsync", function()
	local ok, err = pcall(function()
		subscribeAsync(messagingService, "", function(_message: MessagePayload) end)
	end)
	assert(not ok, "SubscribeAsync com tópico vazio deveria erro")
	assert(
		string.find(tostring(err), "between 1 and 80 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 1-80 caracteres, recebeu: {err}`
	)
end)

test("PublishAsync ERRA com mensagem acima de 1 kB (1024 bytes estimados)", function()
	local bigMessage = string.rep("x", 2000)
	local ok, err = pcall(function()
		publishAsync(messagingService, "Spec6", bigMessage)
	end)
	assert(not ok, "PublishAsync com mensagem de ~2000 bytes deveria erro (limite é 1024)")
	assert(
		string.find(tostring(err), "exceeds the maximum size of 1024 bytes", 1, true) ~= nil,
		`mensagem deveria citar o limite de tamanho, recebeu: {err}`
	)
end)

test("PublishAsync ACEITA tópico de exatamente 80 caracteres e mensagem de exatamente 1024 bytes estimados (limite é <=, não <)", function()
	local topic = string.rep("b", 80)
	local received = false
	local threadErrorCount = 0
	local errorConnection = scheduler.ThreadError:Connect(function()
		threadErrorCount += 1
	end)

	runAsync(function()
		subscribeAsync(messagingService, topic, function(_message: MessagePayload)
			received = true
		end)
	end)

	-- `Value.EstimateByteSize` de uma string soma 2 bytes de aspas delimitadoras (ver
	-- `../datastore/Value.luau`, `estimateStringBytes`) -- 1022 caracteres + 2 = 1024 bytes exatos.
	local exactMessage = string.rep("z", 1022)
	runAsync(function()
		publishAsync(messagingService, topic, exactMessage)
	end)

	assert(
		threadErrorCount == 0,
		`tópico de 80 caracteres e mensagem de exatamente 1024 bytes NÃO deveriam causar erro (limite é <=), houve {threadErrorCount} ThreadError(s)`
	)
	assert(received, "o assinante deveria ter recebido a mensagem de exatamente 1024 bytes / tópico de exatamente 80 caracteres")

	errorConnection:Disconnect()
end)

test("cada assinante recebe sua PRÓPRIA cópia profunda de uma mensagem-tabela -- mutar o recebido não afeta o publisher nem outro assinante", function()
	local topic = "Spec8"
	local receivedA: { count: number }? = nil
	local receivedB: { count: number }? = nil

	runAsync(function()
		subscribeAsync(messagingService, topic, function(message: MessagePayload)
			receivedA = message.Data :: { count: number }
		end)
	end)
	runAsync(function()
		subscribeAsync(messagingService, topic, function(message: MessagePayload)
			receivedB = message.Data :: { count: number }
		end)
	end)

	local original = { count = 1 }
	runAsync(function()
		publishAsync(messagingService, topic, original)
	end)
	original.count = 999 -- mutação DEPOIS de PublishAsync -- não deveria alcançar nenhum assinante

	local a = receivedA :: { count: number }
	local b = receivedB :: { count: number }
	assert(a.count == 1, `mutar o original depois de PublishAsync não deveria afetar o assinante A, achou {a.count}`)
	assert(b.count == 1, `mutar o original depois de PublishAsync não deveria afetar o assinante B, achou {b.count}`)

	a.count = 555 -- mutação do valor recebido por A -- não deveria alcançar B
	assert(b.count == 1, `mutar o valor recebido por A não deveria afetar o valor recebido por B (cópias independentes), achou {b.count}`)
	assert(a ~= b, "assinante A e assinante B deveriam ter recebido referências DIFERENTES (deep copy por assinante), não a mesma tabela")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
