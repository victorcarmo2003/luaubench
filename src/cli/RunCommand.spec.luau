--!strict

--[[
	Teste da task-cli-006 (`RunCommand.luau`) -- o pipeline `luaubench run` DE PONTA A PONTA.
	Cobre o acceptance completo do board (arquiteto-cli-2026-09-05.md, "Pipeline do `luaubench run
	[caminho]`", Decisões 3/4/5/7/11/13):

	PARTE 1 -- chamadas diretas a `RunCommand.Execute` (em processo, rápidas): exit codes 0/1/2,
	contagem de erros/avisos, `--timeout` interrompendo um script que CEDE indefinidamente.

	PARTE 2 -- `process.exec` spawnando um `lune run src/cli/main.luau run <fixture>` REAL: é o
	único jeito de verificar "print vai pra stdout e warn/error pra stderr, verificável por
	redirecionamento" (acceptance do board, literal) e o efeito de `--no-color`/`NO_COLOR` no
	processo real -- não há como interceptar `stdio.write`/`stdio.ewrite` de dentro do mesmo
	processo (ver cabeçalho de `OutputFormatter.luau`).

	Fixtures em `src/cli/fixtures/run-e2e/{basic,module-error,timeout,http-audit}` (task-cli-006,
	novas -- `http-audit` adicionada na correção do achado MÉDIO da revisão de task-cli-026):
	`basic` cobre setmetatable/OOP + `require` entre módulos + print/warn + LocalScript/Enabled=
	false/Script-fora-de-container todos carregados mas nunca executados; `module-error` cobre a
	reatribuição de linha/nome do `OutputFormatter`; `timeout` cobre `--timeout`; `http-audit`
	cobre o contrato `OnHttpRequest`/`Messages.HttpRequestAuditLine` de ponta a ponta contra uma
	requisição HTTP REAL (servida por um `net.serve` local que este próprio arquivo sobe -- nunca
	uma dependência externa).

	Roda com `lune run src/cli/RunCommand.spec.luau`.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local RunCommand = require("./RunCommand")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local FIXTURES_ROOT = process.cwd .. "src/cli/fixtures"

local function fixturePath(name: string): string
	return `{FIXTURES_ROOT}/{name}`
end

local ESCAPE = "\27"

local function hasEscapeCode(text: string): boolean
	return string.find(text, ESCAPE, 1, true) ~= nil
end

local function baseOptions(projectPath: string): RunCommand.RunOptions
	return {
		ProjectPath = projectPath,
		Cwd = process.cwd,
		Timeout = nil,
		UseColor = false,
		Verbose = false,
		-- task-cli-026: default `false` nos dois, mesma semântica de `Args.Parse` sem as flags.
		AllowHttp = false,
		AllowHttpLocal = false,
	}
end

--------------------------------------------------------------------------------------------------
-- PARTE 1 -- RunCommand.Execute em processo
--------------------------------------------------------------------------------------------------

test("Execute: fixture 'basic' termina com ExitCode 0 e sem erros (setmetatable/OOP + require entre módulos)", function()
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/basic")))
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `esperava ErrorCount 0, recebeu {result.ErrorCount}`)
end)

test("Execute: fixture 'value-types' termina com ExitCode 0 -- typeof(Vector3.new(...)) == 'Vector3' de ponta a ponta (task-cli-025, TypeNameResolver)", function()
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/value-types")))
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `esperava ErrorCount 0, recebeu {result.ErrorCount}`)
end)

test("Execute: fixture 'module-error' termina com ExitCode 1 (erro de script não tratado) e ErrorCount >= 1", function()
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/module-error")))
	assert(result.ExitCode == 1, `esperava ExitCode 1, recebeu {result.ExitCode}`)
	assert(result.ErrorCount >= 1, `esperava ErrorCount >= 1, recebeu {result.ErrorCount}`)
end)

test("Execute: projeto inválido (.project.json com campo desconhecido) termina com ExitCode 2 ANTES de rodar nada", function()
	-- Reaproveita o fixture já existente de `ProjectFile.spec.luau`/`TreePlanner.spec.luau` --
	-- Decisão 14, "espelha o deny_unknown_fields do Rojo no nível raiz" -- em vez de duplicar um
	-- projeto malformado só para este teste.
	local result = RunCommand.Execute(baseOptions(fixturePath("unknown-field")))
	assert(result.ExitCode == 2, `esperava ExitCode 2, recebeu {result.ExitCode}`)
	assert(result.ErrorCount >= 1, `esperava ErrorCount >= 1, recebeu {result.ErrorCount}`)
end)

test("Execute: caminho de projeto inexistente termina com ExitCode 2, mensagem de projeto (nunca stack trace cru)", function()
	local bogusPath = fixturePath("this-directory-does-not-exist")
	local result = RunCommand.Execute(baseOptions(bogusPath))
	assert(result.ExitCode == 2, `esperava ExitCode 2, recebeu {result.ExitCode}`)
	assert(result.ErrorCount >= 1, "deveria ter ao menos um diagnostic de erro")
end)

test("Execute: --timeout interrompe um script que CEDE indefinidamente (while true do task.wait() end)", function()
	local startClock = os.clock()
	local options = baseOptions(fixturePath("run-e2e/timeout"))
	options.Timeout = 0.2
	local result = RunCommand.Execute(options)
	local elapsed = os.clock() - startClock

	-- Timeout não é erro de script (o script nunca falhou -- só foi cortado) -- exit 0.
	assert(result.ExitCode == 0, `esperava ExitCode 0 (timeout não é erro), recebeu {result.ExitCode}`)
	-- Rede de segurança, não watchdog (Decisão 11): o script CEDE (task.wait), então o deadline É
	-- consultado entre tiques -- o processo não deveria travar por muito mais que o timeout.
	assert(elapsed < 5, `--timeout não interrompeu o script a tempo (levou {elapsed}s -- esperava perto de 0.2s)`)
end)

test("Execute: fixture 'bindtoclose' termina com ExitCode 0 sem propagar exceção (BindToClose disparado e esperado de verdade, task-cli-031)", function()
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/bindtoclose")))
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `esperava ErrorCount 0, recebeu {result.ErrorCount}`)
end)

test("Execute: fixture 'bindtoclose-error' não propaga o erro de um callback de BindToClose para fora de Execute (task-cli-031)", function()
	-- Se `RunBindToCloseCallbacks` propagasse o erro do primeiro callback, esta chamada (sem
	-- `pcall` nenhum -- `test()` não protege `run`) derrubaria o arquivo de spec inteiro. Chegar
	-- até a asserção abaixo já prova que a semântica de `DataModel` (ThreadError, nunca propaga)
	-- se mantém de ponta a ponta através de `RunCommand`.
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/bindtoclose-error")))
	assert(result.ExitCode == 0, `esperava ExitCode 0 (erro de BindToClose não é contado como erro de script), recebeu {result.ExitCode}`)
end)

test("Diagnostics.Bag: um projeto com apenas warnings (sem erros) ainda produz ExitCode 0", function()
	-- `globIgnorePaths`/`syncRules` não-vazios geram warning (Decisão 14), nunca erro -- reusa o
	-- fixture de warnings já existente de `ProjectFile.spec.luau`.
	local result = RunCommand.Execute(baseOptions(fixturePath("warnings")))
	assert(result.ExitCode == 0, `um projeto só com warnings deveria terminar ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.WarningCount >= 1, "esperava ao menos 1 warning contado")
end)

--------------------------------------------------------------------------------------------------
-- PARTE 2 -- processo real (`lune run src/cli/main.luau run <fixture>`), stdout/stderr/cor/exit
-- code verificados por redirecionamento de verdade
--------------------------------------------------------------------------------------------------

local function runRealProcess(args: { string }, extraEnv: { [string]: string }?): process.ExecResult
	return process.exec("lune", args, { env = extraEnv })
end

test("Processo real: 'basic' -- print vai para stdout, warn para stderr, cor ligada por padrão", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/basic") })

	assert(result.code == 0, `esperava exit code 0, recebeu {result.code} (stderr: {result.stderr})`)
	assert(string.find(result.stdout, "count is 15", 1, true) ~= nil, `stdout deveria conter o print do script: {result.stdout}`)
	assert(string.find(result.stdout, "cache miss", 1, true) == nil, "warn NUNCA deveria aparecer em stdout")
	assert(string.find(result.stderr, "cache miss", 1, true) ~= nil, `stderr deveria conter o warn do script: {result.stderr}`)

	-- LocalScript / Enabled=false / Script fora de ServerScriptContainers -- nenhum dos três
	-- deveria ter rodado, em NENHUM dos dois streams.
	assert(string.find(result.stdout, "THIS SHOULD NEVER RUN", 1, true) == nil, "nenhum script não-elegível deveria ter rodado (stdout)")
	assert(string.find(result.stderr, "THIS SHOULD NEVER RUN", 1, true) == nil, "nenhum script não-elegível deveria ter rodado (stderr)")

	-- Cor ligada por padrão (Decisão 13): a linha de warn no stderr deveria carregar ANSI.
	assert(hasEscapeCode(result.stderr), "cor deveria estar ligada por padrão (sem --no-color/NO_COLOR)")
end)

test("Processo real: --no-color desliga a cor", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/basic"), "--no-color" })
	assert(result.code == 0, `esperava exit code 0, recebeu {result.code}`)
	assert(not hasEscapeCode(result.stdout), "stdout não deveria conter ANSI com --no-color")
	assert(not hasEscapeCode(result.stderr), "stderr não deveria conter ANSI com --no-color")
end)

test("Processo real: a variável de ambiente NO_COLOR desliga a cor (mesma presença, qualquer valor)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/basic") }, { NO_COLOR = "1" })
	assert(result.code == 0, `esperava exit code 0, recebeu {result.code}`)
	assert(not hasEscapeCode(result.stdout), "stdout não deveria conter ANSI com NO_COLOR setado")
	assert(not hasEscapeCode(result.stderr), "stderr não deveria conter ANSI com NO_COLOR setado")
end)

test("Processo real: erro de ModuleScript requerido é renderizado com o nome/linha do MÓDULO, citando o Script de origem -- exit code 1", function()
	local brokenModulePath = fixturePath("run-e2e/module-error") .. "/shared/Modules/Broken.lua"
	local brokenContent = fs.readFile(brokenModulePath)
	-- Conta linhas contando quebras de linha -- o arquivo termina com uma única quebra de linha
	-- final, então o número de "\n" bate com o número de linhas de código (a última sendo
	-- "return nothing.explode", onde o erro de fato acontece). Calculado em vez de hardcodado
	-- (ver comentário no próprio fixture) -- nunca dessincroniza se o arquivo for editado.
	local _, newlineCount = string.gsub(brokenContent, "\n", "\n")
	local expectedLine = newlineCount

	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/module-error"), "--no-color" })

	assert(result.code == 1, `esperava exit code 1, recebeu {result.code} (stdout: {result.stdout}, stderr: {result.stderr})`)
	assert(
		string.find(result.stdout, "THIS SHOULD NEVER RUN", 1, true) == nil,
		"a linha depois do require com erro nunca deveria rodar"
	)

	local moduleMarker = `ReplicatedStorage.Modules.Broken:{expectedLine}:`
	assert(
		string.find(result.stderr, moduleMarker, 1, true) ~= nil,
		`stderr deveria citar o módulo e a linha exatos ({moduleMarker}): {result.stderr}`
	)
	assert(
		string.find(result.stderr, "required by ServerScriptService.Main", 1, true) ~= nil,
		`stderr deveria citar o Script que originou o require: {result.stderr}`
	)
	-- O marcador CRU do motor (`[string "..."]`) nunca deveria vazar para a saída final -- é
	-- exatamente o que a reatribuição de OutputFormatter substitui.
	assert(string.find(result.stderr, '[string "', 1, true) == nil, `marcador cru do motor vazou para a saída: {result.stderr}`)
end)

test("Processo real: exit code 2 para .project.json inválido, com diagnóstico legível (nunca stack trace cru)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("unknown-field"), "--no-color" })
	assert(result.code == 2, `esperava exit code 2, recebeu {result.code}`)
	assert(string.find(result.stderr, "project/unknown-field", 1, true) ~= nil, `stderr deveria citar o Code do diagnostic: {result.stderr}`)
	assert(string.find(result.stderr, "Traceback", 1, true) == nil, "nunca deveria vazar traceback cru do parser/engine")
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "nunca deveria vazar stack traceback cru")
end)

test("Processo real: fixture 'http-audit' -- OnHttpRequest/HttpRequestAuditLine fiados de ponta a ponta contra uma requisição HTTP real (achado MÉDIO, revisão task-cli-026)", function()
	-- Porta FIXA, combinada com `src/cli/fixtures/run-e2e/http-audit/server/Main.server.lua` (o
	-- fixture é um arquivo estático em disco -- não há como injetar a porta em tempo de execução
	-- sem expor variável de ambiente ao sandbox do script, o que a regra 00 proíbe). Mesmo padrão
	-- de `HttpService.spec.luau` (`TEST_PORT = 47182`) para o canário `net.serve` local -- número
	-- diferente de propósito, para nunca colidir caso as duas suítes rodem em paralelo.
	local TEST_PORT = 47210
	local RESPONSE_BODY = "http-audit-ok"

	-- Servidor HTTP local de verdade (nunca dependência externa) -- é contra ELE que o processo
	-- real do `luaubench run`, abaixo, faz a requisição via `HttpService:GetAsync`.
	local serveHandle = net.serve(TEST_PORT, function(_request: net.ServeRequest): net.ServeResponse
		return { status = 200, body = RESPONSE_BODY }
	end)

	local result = runRealProcess({
		"run",
		"src/cli/main.luau",
		"run",
		fixturePath("run-e2e/http-audit"),
		"--allow-http",
		"--allow-http-local",
		"--verbose",
		"--no-color",
	})

	serveHandle.stop()

	assert(result.code == 0, `esperava exit code 0, recebeu {result.code} (stdout: {result.stdout}, stderr: {result.stderr})`)
	assert(
		string.find(result.stdout, "got body: " .. RESPONSE_BODY, 1, true) ~= nil,
		`stdout deveria conter o corpo da resposta ecoado pelo script: {result.stdout}`
	)
	-- Formato EXATO produzido por `Messages.HttpRequestAuditLine("GET", "127.0.0.1")` -- confirmado
	-- contra `src/cli/Messages.luau` antes de escrever esta asserção (nunca um formato adivinhado).
	-- `extractHost` (`services/behavior/HttpService.luau`) devolve o host SEM porta -- a linha não
	-- carrega ":47210".
	assert(
		string.find(result.stderr, "[http] GET 127.0.0.1", 1, true) ~= nil,
		`stderr deveria conter a linha de auditoria de rede (--verbose): {result.stderr}`
	)
end)

test("Processo real: fixture 'bindtoclose' -- BindToClose dispara e ESPERA os callbacks (inclusive o que cede) ANTES do sumário final (task-cli-031)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/bindtoclose"), "--no-color" })

	assert(result.code == 0, `esperava exit code 0, recebeu {result.code} (stdout: {result.stdout}, stderr: {result.stderr})`)
	assert(string.find(result.stdout, "main script ran", 1, true) ~= nil, `stdout deveria conter o print do script principal: {result.stdout}`)
	assert(
		string.find(result.stdout, "bindtoclose: simple callback ran", 1, true) ~= nil,
		`stdout deveria conter o print do primeiro callback de BindToClose: {result.stdout}`
	)
	assert(
		string.find(result.stdout, "bindtoclose: yielding callback finished", 1, true) ~= nil,
		`stdout deveria conter o print do callback que cede (task.wait) -- prova que RunBindToCloseCallbacks ESPEROU o yield: {result.stdout}`
	)

	-- Ordem: os dois callbacks de BindToClose têm que aparecer ANTES da linha de sumário final
	-- (passo 12) -- é exatamente o "ANTES do sumário" do acceptance desta tarefa.
	local _, simpleCallbackEnd = string.find(result.stdout, "bindtoclose: simple callback ran", 1, true)
	local _, yieldingCallbackEnd = string.find(result.stdout, "bindtoclose: yielding callback finished", 1, true)
	local summaryStart = string.find(result.stdout, "Script(s) executed", 1, true)
	assert(summaryStart ~= nil, `stdout deveria conter a linha de sumário: {result.stdout}`)
	assert(
		simpleCallbackEnd ~= nil and summaryStart ~= nil and simpleCallbackEnd < summaryStart,
		"callback simples de BindToClose deveria aparecer ANTES do sumário final"
	)
	assert(
		yieldingCallbackEnd ~= nil and summaryStart ~= nil and yieldingCallbackEnd < summaryStart,
		"callback que cede de BindToClose deveria aparecer ANTES do sumário final, mesmo tendo que esperar o task.wait"
	)
end)

test("Processo real: fixture 'bindtoclose-error' -- erro num callback de BindToClose não derruba o processo nem impede o segundo callback de rodar (task-cli-031)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/bindtoclose-error"), "--no-color" })

	assert(
		result.code == 0,
		`esperava exit code 0 -- erro de BindToClose não deveria mudar o exit code do processo, recebeu {result.code} (stdout: {result.stdout}, stderr: {result.stderr})`
	)
	assert(string.find(result.stdout, "main script ran", 1, true) ~= nil, `stdout deveria conter o print do script principal: {result.stdout}`)
	assert(
		string.find(result.stdout, "bindtoclose: second callback still ran despite the first one erroring", 1, true) ~= nil,
		`o SEGUNDO callback de BindToClose deveria ter rodado mesmo com o PRIMEIRO tendo errado: {result.stdout}`
	)
end)

test("Processo real: fixture 'basic' (SEM nenhum BindToClose) continua idêntico -- no-op, sem linha nova no output (task-cli-031)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/basic"), "--no-color" })
	assert(result.code == 0, `esperava exit code 0, recebeu {result.code}`)
	assert(
		string.find(result.stdout, "bindtoclose", 1, true) == nil,
		"um projeto sem BindToClose nunca deveria produzir nenhuma linha relacionada a bindtoclose"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
