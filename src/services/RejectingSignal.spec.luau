--!strict

--[[
	Teste dedicado de `./RejectingSignal.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). `behavior/RunService.spec.luau` já cobre o caminho ponta a ponta (RunService.
	RenderStepped instalado de verdade, erro observado através de `game:GetService("RunService")`)
	-- este arquivo isola a peça que pertence a ESTE módulo: o objeto em si, construído direto,
	sem RunService/Context/Scheduler no meio -- o que falhar aqui aponta primeiro para
	RejectingSignal.luau, não para o resto do pipeline.

	Roda com `lune run src/services/RejectingSignal.spec.luau`.
]]

local process = require("@lune/process")
local RejectingSignal = require("./RejectingSignal")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local MESSAGE = "RenderStepped event can only be used from local scripts"

test("Connect erra com a mensagem recebida no construtor", function()
	local signal = RejectingSignal.new(MESSAGE)

	local ok, err = pcall(function()
		signal:Connect(function() end)
	end)

	assert(not ok, "Connect deveria erro -- é o mecanismo inteiro do módulo")
	assert(
		string.find(tostring(err), MESSAGE, 1, true) ~= nil,
		`mensagem de erro deveria conter '{MESSAGE}', recebeu: {err}`
	)
end)

test("Once erra com a mensagem recebida no construtor", function()
	local signal = RejectingSignal.new(MESSAGE)

	local ok, err = pcall(function()
		signal:Once(function() end)
	end)

	assert(not ok, "Once deveria erro, mesma disciplina de Connect")
	assert(
		string.find(tostring(err), MESSAGE, 1, true) ~= nil,
		`mensagem de erro deveria conter '{MESSAGE}', recebeu: {err}`
	)
end)

test("Wait erra com a mensagem recebida no construtor", function()
	local signal = RejectingSignal.new(MESSAGE)

	local ok, err = pcall(function()
		return signal:Wait()
	end)

	assert(not ok, "Wait deveria erro, mesma disciplina de Connect/Once")
	assert(
		string.find(tostring(err), MESSAGE, 1, true) ~= nil,
		`mensagem de erro deveria conter '{MESSAGE}', recebeu: {err}`
	)
end)

test("DisconnectAll é no-op -- nunca erra, mesmo sem nenhuma conexão real possível", function()
	local signal = RejectingSignal.new(MESSAGE)

	local ok = pcall(function()
		signal:DisconnectAll()
	end)

	assert(ok, "DisconnectAll não deveria erro -- é no-op por design (nunca houve conexão real para desfazer)")
end)

test("duas mensagens diferentes produzem erros diferentes -- a message não é fixa no módulo", function()
	local other = RejectingSignal.new("outra mensagem qualquer")

	local ok, err = pcall(function()
		other:Connect(function() end)
	end)

	assert(not ok, "Connect deveria erro também para outra mensagem")
	assert(
		string.find(tostring(err), "outra mensagem qualquer", 1, true) ~= nil,
		`mensagem de erro deveria conter a message passada ao construtor, recebeu: {err}`
	)
	assert(
		string.find(tostring(err), MESSAGE, 1, true) == nil,
		"mensagem de erro NÃO deveria conter a message de OUTRO RejectingSignal"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
