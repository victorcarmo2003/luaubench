--!strict

--[[
	Teste dedicado de `./AsyncCall.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o acceptance de task-services-016: `AsyncCall.Yield` suspende um passo de scheduler
	dentro de uma thread gerida, e erra com uma mensagem `[LuauBench]` em inglês (nunca a mensagem
	de engenharia interna em português de `Scheduler.Wait`) fora de uma thread gerida.

	Roda com `lune run src/services/AsyncCall.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Context = require("./Context")
local AsyncCall = require("./AsyncCall")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Yield, dentro de uma thread gerida pelo Scheduler, suspende exatamente um passo e retoma sem erro", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()
	Context.Set({ scheduler = scheduler, dataModel = dataModel })

	local reachedAfterYield = false
	-- Scheduler.Spawn roda a thread imediatamente, de forma síncrona, até o primeiro yield --
	-- então, logo após este Spawn devolver o controle, a thread já deve estar PARADA dentro do
	-- Yield (Wait(0) chama coroutine.yield()), sem ter chegado no código depois dele.
	scheduler:Spawn(function()
		AsyncCall.Yield("GlobalDataStore:GetAsync")
		reachedAfterYield = true
	end)

	assert(
		not reachedAfterYield,
		"a thread não deveria ter avançado além do Yield antes de qualquer StepOnce -- Wait(0) ainda assim suspende de verdade"
	)

	-- Um único passo de scheduler (StepOnce, determinístico -- mesmo padrão de Scheduler.spec.luau)
	-- deveria bastar para acordar a thread: Wait(0) enfileira wakeAt = time + 0 (ver cabeçalho de
	-- AsyncCall.luau, "CONSEQUÊNCIA PARA A LIVENESS DO SCHEDULER").
	scheduler:StepOnce(0)

	assert(reachedAfterYield, "a thread deveria ter retomado depois de um único passo de scheduler e chegado no código após o Yield")
end)

test("Yield fora de uma thread gerida pelo Scheduler erra com [LuauBench] em inglês, NUNCA com a mensagem interna em português", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()
	Context.Set({ scheduler = scheduler, dataModel = dataModel })

	-- Este teste roda na thread PRINCIPAL do próprio processo Lune do spec -- nunca passou por
	-- Scheduler:Spawn/Delay, então `self.liveThreads[coroutine.running()]` é `nil` dentro de
	-- `Scheduler.Wait`: exatamente o caso patológico que AsyncCall.Yield precisa retraduzir.
	local ok, err = pcall(function()
		AsyncCall.Yield("GlobalDataStore:GetAsync")
	end)

	assert(not ok, "Yield fora de thread gerida deveria erro, nunca completar silenciosamente")
	local message = tostring(err)

	assert(
		string.find(message, "[LuauBench]", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra de idioma dos erros), recebeu: {message}`
	)
	assert(
		string.find(message, "GlobalDataStore:GetAsync", 1, true) ~= nil,
		`mensagem deveria citar o label recebido (nome qualificado do método real), recebeu: {message}`
	)
	assert(
		string.find(message, "Scheduler:Wait", 1, true) == nil,
		`a mensagem de engenharia interna em português de Scheduler.Wait NUNCA deveria vazar para o Output, recebeu: {message}`
	)
	assert(
		string.find(message, "gerida pelo Scheduler", 1, true) == nil,
		`nenhum fragmento em português (da mensagem interna real de Scheduler.Wait) deveria vazar, recebeu: {message}`
	)
end)

test("duas chamadas com labels diferentes produzem mensagens diferentes -- o label não é fixo no módulo", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()
	Context.Set({ scheduler = scheduler, dataModel = dataModel })

	local ok, err = pcall(function()
		AsyncCall.Yield("MessagingService:PublishAsync")
	end)

	assert(not ok, "Yield fora de thread gerida deveria erro também para outro label")
	local message = tostring(err)
	assert(
		string.find(message, "MessagingService:PublishAsync", 1, true) ~= nil,
		`mensagem deveria citar o label passado a ESTA chamada, recebeu: {message}`
	)
	assert(
		string.find(message, "GlobalDataStore:GetAsync", 1, true) == nil,
		"mensagem NÃO deveria conter o label de OUTRA chamada"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
