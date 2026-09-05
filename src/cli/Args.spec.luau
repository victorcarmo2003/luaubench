--!strict

--[[
	Teste da task-cli-001 (Args.luau). Cobre o acceptance do board: run/version/help, as três
	flags de "run" (--timeout/--no-color/--verbose), argumento faltando em --timeout, flag
	desconhecida, e --watch com o motivo técnico real (nunca "flag desconhecida").

	Roda com `lune run src/cli/Args.spec.luau`.
]]

local process = require("@lune/process")
local Args = require("./Args")
local Messages = require("./Messages")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

--------------------------------------------------------------------------------------------------
-- version / help
--------------------------------------------------------------------------------------------------

test("--version em qualquer posição vira Kind 'version'", function()
	assert(Args.Parse({ "--version" }).Kind == "version", "--version isolado deveria virar Kind 'version'")
	assert(Args.Parse({ "run", "--version" }).Kind == "version", "--version depois de 'run' ainda deveria vencer")
	assert(Args.Parse({ "./MyProject", "--version" }).Kind == "version", "--version depois de um caminho ainda deveria vencer")
end)

test("--help em qualquer posição vira Kind 'help'", function()
	assert(Args.Parse({ "--help" }).Kind == "help", "--help isolado deveria virar Kind 'help'")
	assert(Args.Parse({ "run", "--help" }).Kind == "help", "--help depois de 'run' ainda deveria vencer")
end)

test("subcomando bare 'version'/'help' (sem flag) também funciona", function()
	assert(Args.Parse({ "version" }).Kind == "version", "subcomando 'version' bare deveria virar Kind 'version'")
	assert(Args.Parse({ "help" }).Kind == "help", "subcomando 'help' bare deveria virar Kind 'help'")
end)

--------------------------------------------------------------------------------------------------
-- run: caminho + as três flags
--------------------------------------------------------------------------------------------------

test("argv vazio vira Kind 'run' com ProjectPath nil (comando padrão, sem 'run' explícito)", function()
	local command = Args.Parse({})
	assert(command.Kind == "run", "argv vazio deveria virar Kind 'run'")
	if command.Kind == "run" then
		assert(command.ProjectPath == nil, "sem argumento posicional, ProjectPath deveria ser nil")
		assert(command.Timeout == nil, "sem --timeout, Timeout deveria ser nil")
		assert(command.NoColor == false, "sem --no-color, NoColor deveria começar false")
		assert(command.Verbose == false, "sem --verbose, Verbose deveria começar false")
	end
end)

test("'run <caminho>' explícito e '<caminho>' implícito produzem o mesmo ProjectPath", function()
	local explicit = Args.Parse({ "run", "./MyProject" })
	local implicit = Args.Parse({ "./MyProject" })

	assert(explicit.Kind == "run" and implicit.Kind == "run", "as duas formas deveriam virar Kind 'run'")
	if explicit.Kind == "run" and implicit.Kind == "run" then
		assert(explicit.ProjectPath == "./MyProject", "forma explícita deveria capturar o caminho")
		assert(implicit.ProjectPath == "./MyProject", "forma implícita deveria capturar o mesmo caminho")
	end
end)

test("--timeout <segundos> parseia como número", function()
	local command = Args.Parse({ "run", "--timeout", "30" })
	assert(command.Kind == "run", "deveria continuar Kind 'run'")
	if command.Kind == "run" then
		assert(command.Timeout == 30, `Timeout deveria ser 30, recebeu {command.Timeout}`)
	end
end)

test("--no-color e --verbose setam as flags booleanas correspondentes", function()
	local command = Args.Parse({ "run", "--no-color", "--verbose" })
	assert(command.Kind == "run", "deveria continuar Kind 'run'")
	if command.Kind == "run" then
		assert(command.NoColor == true, "--no-color deveria setar NoColor = true")
		assert(command.Verbose == true, "--verbose deveria setar Verbose = true")
	end
end)

test("caminho + as três flags juntos, em qualquer ordem em torno do caminho", function()
	local command = Args.Parse({ "run", "--no-color", "./MyProject", "--timeout", "5", "--verbose" })
	assert(command.Kind == "run", "deveria continuar Kind 'run'")
	if command.Kind == "run" then
		assert(command.ProjectPath == "./MyProject", "deveria capturar o caminho no meio das flags")
		assert(command.Timeout == 5, "deveria capturar --timeout mesmo depois do caminho")
		assert(command.NoColor == true, "deveria capturar --no-color antes do caminho")
		assert(command.Verbose == true, "deveria capturar --verbose depois de --timeout")
	end
end)

--------------------------------------------------------------------------------------------------
-- erros: argumento faltando, flag desconhecida, argumento extra
--------------------------------------------------------------------------------------------------

test("--timeout sem valor vira Kind 'error' citando a flag (Messages.MissingFlagValue)", function()
	local command = Args.Parse({ "run", "--timeout" })
	assert(command.Kind == "error", "--timeout sem valor deveria virar Kind 'error'")
	if command.Kind == "error" then
		assert(command.Message == Messages.MissingFlagValue("--timeout"), "mensagem deveria vir de Messages.MissingFlagValue")
	end
end)

test("--timeout com valor não numérico vira Kind 'error' citando o valor recebido", function()
	local command = Args.Parse({ "run", "--timeout", "abc" })
	assert(command.Kind == "error", "--timeout com valor não numérico deveria virar Kind 'error'")
	if command.Kind == "error" then
		assert(command.Message == Messages.InvalidFlagValue("--timeout", "abc"), "mensagem deveria vir de Messages.InvalidFlagValue")
	end
end)

test("flag desconhecida vira Kind 'error' citando a flag exata (Messages.UnknownFlag)", function()
	local command = Args.Parse({ "run", "--bogus" })
	assert(command.Kind == "error", "flag desconhecida deveria virar Kind 'error'")
	if command.Kind == "error" then
		assert(command.Message == Messages.UnknownFlag("--bogus"), "mensagem deveria vir de Messages.UnknownFlag")
	end
end)

test("segundo argumento posicional vira Kind 'error' (Messages.UnexpectedArgument)", function()
	local command = Args.Parse({ "run", "./MyProject", "./OutroProjeto" })
	assert(command.Kind == "error", "um segundo caminho deveria virar Kind 'error'")
	if command.Kind == "error" then
		assert(command.Message == Messages.UnexpectedArgument("./OutroProjeto"), "mensagem deveria vir de Messages.UnexpectedArgument")
	end
end)

--------------------------------------------------------------------------------------------------
-- --watch: motivo técnico real, nunca "flag desconhecida" (Decisão 9)
--------------------------------------------------------------------------------------------------

test("--watch vira Kind 'error' com o motivo técnico real, NUNCA a mensagem de flag desconhecida", function()
	local command = Args.Parse({ "run", "--watch" })
	assert(command.Kind == "error", "--watch deveria virar Kind 'error'")
	if command.Kind == "error" then
		assert(command.Message == Messages.WatchNotSupported(), "mensagem deveria ser o motivo técnico real de Messages.WatchNotSupported")
		assert(command.Message ~= Messages.UnknownFlag("--watch"), "--watch NUNCA deveria cair na mensagem genérica de flag desconhecida")
	end
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
