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

	PARTE 3/4 -- task-cli-030 (persistência local do estado "cloud", par de task-cli-029/
	task-services-031): projetos MUTÁVEIS gerados em `%TEMP%/luaubench-runcommand-persist-spec/`
	(nunca em `src/cli/fixtures/`, que são projetos ESTÁTICOS versionados -- mesma disciplina de
	`CloudStore.spec.luau`/`TreePlanner.spec.luau`). CUIDADO DE ISOLAMENTO (regra 00, achado desta
	tarefa): o `Store` de `DataStoreService` é um SINGLETON MÓDULO-LOCAL do PROCESSO inteiro (ver
	`src/services/behavior/GlobalDataStore.luau`) -- todo teste da PARTE 3 (que chama
	`RunCommand.Execute` no MESMO processo Lune deste spec) usa um nome de DataStore ÚNICO
	(`RoundtripStore`/`NoPersistStore`/etc.), nunca reaproveitado entre casos, para que um valor
	deixado na memória por um caso nunca contamine a asserção de outro -- a PARTE 4 (processo real,
	`process.exec`) não tem esse cuidado porque cada chamada é um processo Lune SEPARADO.

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
		-- task-cli-030: default `false` (persistência LIGADA por padrão), mesma semântica de
		-- `Args.Parse` sem `--no-persist`.
		NoPersist = false,
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

test("Execute: fixture 'bindtoclose-error' não propaga o erro de um callback de BindToClose para fora de Execute, mas CONTA no ErrorCount e reflete no ExitCode (task-cli-031 + fix task-cli-032)", function()
	-- Se `RunBindToCloseCallbacks` propagasse o erro do primeiro callback, esta chamada (sem
	-- `pcall` nenhum -- `test()` não protege `run`) derrubaria o arquivo de spec inteiro. Chegar
	-- até a asserção abaixo já prova que a semântica de `DataModel` (ThreadError, nunca propaga)
	-- se mantém de ponta a ponta através de `RunCommand`.
	--
	-- task-cli-032 (BUG achado em task-cli-031, corrigido aqui): antes desta correção, o erro do
	-- callback saía por `scheduler.ThreadError` sem nenhum listener conectado -- `ExitCode` saía
	-- 0 e `ErrorCount` saía 0, mesmo com um erro real acontecendo (exit code 0 falso). O fixture
	-- registra DOIS callbacks: o primeiro erra, o segundo só imprime -- exatamente o cenário
	-- "múltiplos callbacks, um erra, outro continua rodando" do acceptance desta tarefa.
	local result = RunCommand.Execute(baseOptions(fixturePath("run-e2e/bindtoclose-error")))
	assert(result.ExitCode == 1, `esperava ExitCode 1 (erro de BindToClose agora conta como erro de script), recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 1, `esperava ErrorCount 1 (só o PRIMEIRO callback erra, o segundo não), recebeu {result.ErrorCount}`)
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

	-- task-cli-032 (regressão explícita do acceptance "callback que não erra continua
	-- silencioso"): o listener novo de `ThreadError` conectado ao redor de
	-- `RunBindToCloseCallbacks` NUNCA deveria produzir uma linha extra para um callback que só
	-- termina normalmente -- nenhum "error " no stderr, e o sumário final continua "0 error(s)",
	-- idêntico ao que já era antes desta tarefa (task-cli-031).
	assert(string.find(result.stderr, "error ", 1, true) == nil, `nenhum callback errou -- stderr não deveria conter linha de erro nenhuma: {result.stderr}`)
	assert(
		string.find(result.stdout, "0 error(s)", 1, true) ~= nil,
		`sumário deveria continuar contando 0 erros (nenhum callback deste fixture erra): {result.stdout}`
	)
end)

test("Processo real: fixture 'bindtoclose-error' -- erro num callback de BindToClose não derruba o processo, não impede o segundo callback de rodar, mas agora APARECE formatado no stderr, CONTA no sumário e muda o exit code (task-cli-031 + fix task-cli-032)", function()
	local result = runRealProcess({ "run", "src/cli/main.luau", "run", fixturePath("run-e2e/bindtoclose-error"), "--no-color" })

	-- BUG task-cli-032 (corrigido aqui): antes, esta chamada devolvia exit code 0 e "0 error(s)"
	-- mesmo com o erro real do callback tendo acontecido -- exatamente o "sucesso aparente" que o
	-- board descreve. Agora o erro conta como qualquer outro erro de script.
	assert(
		result.code == 1,
		`esperava exit code 1 (erro de BindToClose agora reflete no exit code do processo), recebeu {result.code} (stdout: {result.stdout}, stderr: {result.stderr})`
	)
	assert(string.find(result.stdout, "main script ran", 1, true) ~= nil, `stdout deveria conter o print do script principal: {result.stdout}`)
	assert(
		string.find(result.stdout, "bindtoclose: second callback still ran despite the first one erroring", 1, true) ~= nil,
		`o SEGUNDO callback de BindToClose deveria ter rodado mesmo com o PRIMEIRO tendo errado: {result.stdout}`
	)

	-- Formatado no MESMO padrão de um erro de Script principal (Messages.OutputErrorLine,
	-- "error <scriptName>:<line>: <mensagem>") -- nunca o marcador cru `[string "..."]` do motor,
	-- e nunca a stack traceback multi-linha vazando (mesma disciplina de qualquer outro erro de
	-- script já coberta pelo teste de 'module-error', acima).
	assert(
		string.find(result.stderr, "ServerScriptService.Main:6: bindtoclose boom (proposital, teste task-cli-031)", 1, true) ~= nil,
		`stderr deveria conter o erro do callback formatado como um erro de script normal: {result.stderr}`
	)
	assert(string.find(result.stderr, '[string "', 1, true) == nil, `marcador cru do motor vazou para a saída: {result.stderr}`)
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, `stack traceback crua vazou para a saída: {result.stderr}`)

	-- Conta no sumário final (`Messages.DiagnosticCountLine`) -- só UMA vez (o segundo callback
	-- não erra), nunca "0 error(s)" com um erro real tendo acontecido.
	assert(
		string.find(result.stdout, "1 error(s), 0 warning(s).", 1, true) ~= nil,
		`stdout deveria conter o sumário contando exatamente 1 erro: {result.stdout}`
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

--------------------------------------------------------------------------------------------------
-- PARTE 3 -- persistência local do estado "cloud" (task-cli-030), RunCommand.Execute em processo
--------------------------------------------------------------------------------------------------

-- Pasta-mãe de todo este bloco -- projetos MUTÁVEIS gerados em tempo de teste (ver cabeçalho do
-- arquivo, "PARTE 3/4"). Nunca reaproveitada de uma rodada anterior que tenha abortado no meio.
local PERSIST_TEMP_ROOT = process.env.TEMP or process.env.TMP
assert(PERSIST_TEMP_ROOT ~= nil, "TEMP/TMP precisa existir no ambiente pra este spec gerar projetos de persistência de teste")
local PERSIST_SCRATCH_ROOT = `{PERSIST_TEMP_ROOT}/luaubench-runcommand-persist-spec`

if fs.isDir(PERSIST_SCRATCH_ROOT) then
	fs.removeDir(PERSIST_SCRATCH_ROOT)
end
fs.writeDir(PERSIST_SCRATCH_ROOT)

-- Gera um projeto mínimo (DataModel -> ServerScriptService -> Main.server.lua) do ZERO -- apaga
-- qualquer resíduo do caso homônimo de uma rodada anterior, inclusive um ".luaubench/" que
-- tivesse sobrevivido (diferente de `rewriteScript`, abaixo, que preserva ".luaubench/" de
-- propósito para simular uma 2ª execução do MESMO projeto).
local function freshPersistProject(caseName: string, scriptSource: string): string
	local root = `{PERSIST_SCRATCH_ROOT}/{caseName}`
	if fs.isDir(root) then
		fs.removeDir(root)
	end
	fs.writeDir(root)
	fs.writeDir(`{root}/server`)
	fs.writeFile(
		`{root}/default.project.json`,
		table.concat({
			"{",
			'  "name": "PersistFixture",',
			'  "tree": {',
			'    "$className": "DataModel",',
			'    "ServerScriptService": { "$path": "server" }',
			"  }",
			"}",
		}, "\n")
	)
	fs.writeFile(`{root}/server/Main.server.lua`, scriptSource)
	return root
end

-- Sobrescreve SÓ o script de um projeto já existente -- preserva ".luaubench/" (ao contrário de
-- `freshPersistProject`) -- usado para simular uma 2ª execução do MESMO projeto sobre o mesmo
-- estado "cloud" em disco.
local function rewriteScript(root: string, scriptSource: string): ()
	fs.writeFile(`{root}/server/Main.server.lua`, scriptSource)
end

local function persistDocumentPath(root: string): string
	return `{root}/.luaubench/cloud/datastore.json`
end

test("persistência: FlushCloudState nunca grava nada quando o Store está limpo -- nenhum .luaubench/ criado (task-cli-030, confirmado por AUSÊNCIA de arquivo, não por achismo)", function()
	local root = freshPersistProject("clean-no-write", 'print("idle script, no DataStoreService usage")')
	local result = RunCommand.Execute(baseOptions(root))
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(
		not fs.isDir(`{root}/.luaubench`),
		".luaubench/ NUNCA deveria ser criado quando o Store nunca foi sujado -- se FlushCloudState tivesse chamado Save (mesmo com um documento vazio), CloudStore.Save teria criado o diretório na hora"
	)
end)

test("persistência: idem, mesmo com DEZENAS de consultas a shouldContinue (--timeout, script que cede) -- ainda ZERO escritas (task-cli-030)", function()
	local root = freshPersistProject("clean-no-write-many-ticks", "while true do\n\ttask.wait()\nend\n")
	local options = baseOptions(root)
	options.Timeout = 0.3
	local result = RunCommand.Execute(options)
	assert(result.ExitCode == 0, `esperava ExitCode 0 (timeout não é erro), recebeu {result.ExitCode}`)
	assert(
		not fs.isDir(`{root}/.luaubench`),
		".luaubench/ NUNCA deveria ser criado -- dezenas de consultas a shouldContinue com o Store limpo não deveriam custar nenhuma escrita"
	)
end)

test("persistência: 1ª execução grava via SetAsync e sai; .luaubench/cloud/datastore.json existe com o valor; 2ª execução lê o valor da 1ª (task-cli-030, acceptance principal)", function()
	local root = freshPersistProject(
		"roundtrip",
		table.concat({
			'local store = game:GetService("DataStoreService"):GetDataStore("RoundtripStore")',
			'store:SetAsync("Key1", "hello-from-run-1")',
			'print("wrote")',
		}, "\n")
	)

	local firstResult = RunCommand.Execute(baseOptions(root))
	assert(firstResult.ExitCode == 0, `1ª execução deveria terminar ExitCode 0, recebeu {firstResult.ExitCode}`)

	local documentPath = persistDocumentPath(root)
	assert(fs.isFile(documentPath), `1ª execução deveria ter criado {documentPath}`)
	assert(string.find(fs.readFile(documentPath), "hello-from-run-1", 1, true) ~= nil, "o documento deveria conter o valor gravado pela 1ª execução")

	rewriteScript(
		root,
		table.concat({
			'local store = game:GetService("DataStoreService"):GetDataStore("RoundtripStore")',
			'local value = store:GetAsync("Key1")',
			'assert(value == "hello-from-run-1", "valor lido na 2a execucao deveria bater com o gravado na 1a, recebeu: " .. tostring(value))',
			'print("read: " .. tostring(value))',
		}, "\n")
	)

	local secondResult = RunCommand.Execute(baseOptions(root))
	assert(secondResult.ExitCode == 0, `2ª execução deveria terminar ExitCode 0 (leu o valor certo), recebeu {secondResult.ExitCode}`)
	assert(secondResult.ErrorCount == 0, `2ª execução não deveria contar erro nenhum, recebeu {secondResult.ErrorCount}`)
end)

test("persistência: --no-persist não cria .luaubench/ mesmo com SetAsync no script (task-cli-030)", function()
	local root = freshPersistProject(
		"no-persist",
		table.concat({
			'local store = game:GetService("DataStoreService"):GetDataStore("NoPersistStore")',
			'store:SetAsync("Key1", "should-not-be-persisted")',
			'print("wrote (no-persist)")',
		}, "\n")
	)

	local options = baseOptions(root)
	options.NoPersist = true
	local result = RunCommand.Execute(options)

	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(not fs.isDir(`{root}/.luaubench`), "--no-persist NUNCA deveria criar .luaubench/")
end)

test("persistência: --no-persist NUNCA lê estado 'cloud' existente em disco, mesmo que o documento já exista (task-cli-030)", function()
	local root = freshPersistProject(
		"no-persist-ignore-existing",
		table.concat({
			'local value = game:GetService("DataStoreService"):GetDataStore("NoPersistIgnoreStore"):GetAsync("Key1")',
			'assert(value == nil, "--no-persist NUNCA deveria ler estado existente, mas leu: " .. tostring(value))',
			'print("confirmed nil")',
		}, "\n")
	)

	-- Documento propositalmente GARBAGE (nem JSON válido) -- se --no-persist chegasse perto de
	-- tentar ler isto, Services.Bootstrap propagaria um erro de decode e o ExitCode seria 2, não 0.
	fs.writeDir(`{root}/.luaubench/cloud`)
	fs.writeFile(persistDocumentPath(root), "this is not even valid json -- --no-persist must never read this")

	local options = baseOptions(root)
	options.NoPersist = true
	local result = RunCommand.Execute(options)

	assert(result.ExitCode == 0, `--no-persist deveria ignorar o documento existente por completo (ExitCode 0), recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `--no-persist não deveria contar erro nenhum, recebeu {result.ErrorCount}`)
end)

test("persistência: falha de ESCRITA gera UM warning (nunca um erro), script continua rodando, exit code inalterado (task-cli-030, política f)", function()
	local root = freshPersistProject(
		"write-failure",
		table.concat({
			'local store = game:GetService("DataStoreService"):GetDataStore("WriteFailureStore")',
			'store:SetAsync("Key1", "value")',
			'print("script finished despite the persistence write failing")',
		}, "\n")
	)

	-- Obstrui ".luaubench/" com um ARQUIVO antes de qualquer Save -- mesmo cenário de
	-- CloudStore.spec.luau, "Save se recupera de uma obstrução transitória" -- aqui usado de
	-- propósito pra forçar TODA tentativa de flush (tique + forçado) a falhar.
	fs.writeFile(`{root}/.luaubench`, "isto deveria ser um diretório, não um arquivo")

	local result = RunCommand.Execute(baseOptions(root))

	assert(result.ExitCode == 0, `falha de escrita de persistência NUNCA deveria mudar o exit code do script (esperava 0), recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `falha de escrita é warning, nunca erro -- ErrorCount deveria ser 0, recebeu {result.ErrorCount}`)
	assert(
		result.WarningCount == 1,
		`deveria haver EXATAMENTE 1 warning (nunca um por tique/flush, mesmo com várias tentativas de flush falhando) -- recebeu {result.WarningCount}`
	)
end)

test("persistência: documento 'cloud' corrompido gera erro de projeto (ExitCode 2) e o arquivo fica INTACTO no disco depois da falha (task-cli-030, política f)", function()
	local root = freshPersistProject("corrupted", 'print("should never run")')
	fs.writeDir(`{root}/.luaubench/cloud`)
	local documentPath = persistDocumentPath(root)
	local corruptedContent = "{ this is not valid json"
	fs.writeFile(documentPath, corruptedContent)

	local result = RunCommand.Execute(baseOptions(root))

	assert(result.ExitCode == 2, `documento corrompido deveria gerar ExitCode 2 (erro de projeto), recebeu {result.ExitCode}`)
	assert(result.ErrorCount >= 1, "deveria contar ao menos 1 erro")
	assert(fs.readFile(documentPath) == corruptedContent, "o arquivo corrompido NUNCA deveria ser sobrescrito depois da falha de leitura")
end)

--------------------------------------------------------------------------------------------------
-- PARTE 4 -- persistência local do estado "cloud" (task-cli-030), processo real (stderr/exit code
-- verificados por redirecionamento de verdade -- necessário para a linha informativa de
-- `onFirstCreate`, que usa `stdio.ewrite` e não é interceptável de dentro do mesmo processo, mesmo
-- motivo já documentado no cabeçalho deste arquivo para a PARTE 2).
--------------------------------------------------------------------------------------------------

test("Processo real: 1ª execução com persistência imprime a linha informativa de criação do .luaubench/ UMA vez no stderr; a 2ª execução NÃO repete (task-cli-030)", function()
	local root = freshPersistProject(
		"first-create-message",
		table.concat({
			'game:GetService("DataStoreService"):GetDataStore("FirstCreateStore"):SetAsync("K", "V")',
			'print("done")',
		}, "\n")
	)

	local firstResult = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })
	assert(firstResult.code == 0, `esperava exit code 0, recebeu {firstResult.code} (stderr: {firstResult.stderr})`)
	assert(string.find(firstResult.stderr, ".luaubench", 1, true) ~= nil, `1ª execução deveria imprimir a linha informativa de criação do .luaubench/: {firstResult.stderr}`)
	assert(string.find(firstResult.stderr, "git-ignored", 1, true) ~= nil, `linha informativa deveria mencionar que é git-ignored por padrão: {firstResult.stderr}`)

	local secondResult = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })
	assert(secondResult.code == 0, `esperava exit code 0 na 2ª execução, recebeu {secondResult.code}`)
	assert(string.find(secondResult.stderr, ".luaubench", 1, true) == nil, `2ª execução NUNCA deveria repetir a linha informativa: {secondResult.stderr}`)
end)

test("Processo real: documento 'cloud' corrompido produz diagnóstico citando o CAMINHO exato, nunca stack trace cru, script nunca roda (task-cli-030)", function()
	local root = freshPersistProject("corrupted-real-process", 'print("should never run")')
	fs.writeDir(`{root}/.luaubench/cloud`)
	local documentPath = persistDocumentPath(root)
	fs.writeFile(documentPath, "{ not valid json")

	local result = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })

	assert(result.code == 2, `esperava exit code 2, recebeu {result.code} (stderr: {result.stderr})`)
	assert(string.find(result.stderr, documentPath, 1, true) ~= nil, `stderr deveria citar o caminho exato do documento corrompido: {result.stderr}`)
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "nunca deveria vazar stack traceback cru")
	assert(string.find(result.stdout, "should never run", 1, true) == nil, "o script nunca deveria ter rodado")
	assert(fs.readFile(documentPath) == "{ not valid json", "o arquivo corrompido deveria continuar intacto após a falha")
end)

test("Processo real: documento 'cloud' corrompido NUNCA vaza o caminho de instalação do LuauBench na mensagem [cloud/state-unreadable] (achado ALTO de revisão task-cli-030)", function()
	-- Reproduz o cenário EXATO do achado: `Snapshot.DecodeDocument` (`src/services/datastore/
	-- Snapshot.luau`) levanta com `error(msg, 2)` a partir de dentro de `loadCloudStateIfPresent`
	-- (`src/services/init.luau`) -- nível 2 aponta pro CALL SITE dentro DAQUELE arquivo, então
	-- `tostring(err)`, sem tratamento, citava `<caminho absoluto de instalação>/src/services:335:
	-- Snapshot.DecodeDocument: invalid JSON: ...` (confirmado por reprodução manual antes desta
	-- correção -- `lune run src/cli/main.luau run <projeto>` contra este MESMO JSON malformado).
	-- Documento genuinamente malformado (erro REAL do decoder JSON via `@lune/serde`, nunca uma
	-- string de erro já limpa fabricada à mão) -- é o pipeline inteiro (`CloudStore.Load` ->
	-- `Snapshot.DecodeDocument` -> `pcall` de `RunCommand.Execute` -> `TreeMaterializer.
	-- StripEngineErrorLocation`) que precisa produzir a mensagem limpa de ponta a ponta.
	local root = freshPersistProject("corrupted-no-path-leak", 'print("should never run")')
	fs.writeDir(`{root}/.luaubench/cloud`)
	local documentPath = persistDocumentPath(root)
	fs.writeFile(documentPath, "{ this is not valid json")

	local result = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })

	assert(result.code == 2, `esperava exit code 2, recebeu {result.code} (stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "Snapshot.DecodeDocument: invalid JSON", 1, true) ~= nil,
		`stderr deveria conter a mensagem LIMPA do decoder (sem prefixo de localização): {result.stderr}`
	)
	-- `documentPath` (dentro do projeto do usuário, em %TEMP%) É esperado na mensagem -- ver o
	-- teste acima ("cita o CAMINHO exato"). O que NUNCA pode aparecer é o caminho de INSTALAÇÃO do
	-- LuauBench (a raiz deste repositório, de onde `lune run src/cli/main.luau` foi invocado).
	assert(
		string.find(result.stderr, process.cwd, 1, true) == nil,
		`stderr NUNCA deveria conter o caminho de instalação do LuauBench ("{process.cwd}"): {result.stderr}`
	)
	assert(string.find(result.stderr, "\\src\\", 1, true) == nil, `stderr NUNCA deveria conter o padrão de caminho interno "\\src\\": {result.stderr}`)
	assert(string.find(result.stderr, "/src/", 1, true) == nil, `stderr NUNCA deveria conter o padrão de caminho interno "/src/": {result.stderr}`)
end)

test("Processo real: falha de escrita da persistência produz EXATAMENTE 1 ocorrência do warning no stderr (nunca um por tique), exit code inalterado (task-cli-030)", function()
	local root = freshPersistProject(
		"write-failure-real-process",
		table.concat({
			'game:GetService("DataStoreService"):GetDataStore("WriteFailureRealStore"):SetAsync("K", "V")',
			'print("script finished")',
		}, "\n")
	)
	fs.writeFile(`{root}/.luaubench`, "blocking file, not a directory")

	local result = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })

	assert(result.code == 0, `falha de escrita nunca deveria mudar o exit code, recebeu {result.code} (stderr: {result.stderr})`)
	assert(string.find(result.stdout, "script finished", 1, true) ~= nil, "o script deveria ter rodado até o fim, apesar da falha de persistência")
	assert(string.find(result.stderr, "stack traceback", 1, true) == nil, "nunca deveria vazar stack traceback cru")

	-- `gsub` substitui por STRING VAZIA só para contar ocorrências -- a string de substituição
	-- nunca pode repetir o padrão de busca aqui: um "%" na substituição é interpretado como
	-- referência de captura pelo próprio `gsub` ("%-" não é uma referência válida e erra em tempo
	-- de execução), diferente do "%" no PADRÃO de busca (onde escapa o hífen literal).
	local _, occurrences = string.gsub(result.stderr, "cloud/save%-failed", "")
	assert(occurrences == 1, `deveria haver EXATAMENTE 1 ocorrência do warning de falha de escrita (nunca um por tique), recebeu {occurrences}: {result.stderr}`)
end)

test("Processo real: falha de escrita da persistência NUNCA vaza o caminho de instalação do LuauBench na mensagem [cloud/save-failed] (achado ALTO de revisão task-cli-030)", function()
	-- Mesmo achado do teste acima, outro ponto de entrada: `CloudStore.Save`/`ensureDirectoryExists`
	-- (`src/cli/CloudStore.luau`) levantam com `error(msg)` (nível padrão 1, aponta pra DENTRO de
	-- `CloudStore.luau`). Antes desta correção, `Services.FlushCloudState` (`src/services/
	-- init.luau`) só cortava a quebra de linha (nunca o prefixo de localização) e `RunCommand.luau`
	-- reaplicava o MESMO corte incompleto -- o resultado citava `<caminho absoluto de instalação>/
	-- CloudStore:<linha>: CloudStore: could not create ...` (confirmado por reprodução manual antes
	-- desta correção). Obstrução REAL (arquivo no lugar do diretório, forçando `fs.writeDir` a
	-- falhar de verdade) -- não uma string de erro fabricada à mão.
	local root = freshPersistProject(
		"write-failure-no-path-leak",
		table.concat({
			'game:GetService("DataStoreService"):GetDataStore("WriteFailureNoLeakStore"):SetAsync("K", "V")',
			'print("script finished")',
		}, "\n")
	)
	fs.writeFile(`{root}/.luaubench`, "blocking file, not a directory")

	local result = runRealProcess({ "run", "src/cli/main.luau", "run", root, "--no-color" })

	assert(result.code == 0, `falha de escrita nunca deveria mudar o exit code, recebeu {result.code} (stderr: {result.stderr})`)
	assert(
		string.find(result.stderr, "CloudStore: could not create", 1, true) ~= nil,
		`stderr deveria conter a mensagem LIMPA do CloudStore (sem prefixo de localização): {result.stderr}`
	)
	-- `root` (dentro do projeto do usuário, em %TEMP%) pode aparecer -- é o caminho do documento
	-- "cloud" do PRÓPRIO projeto (Messages.CloudStateSaveFailed sempre cita o caminho exato,
	-- de propósito). O que NUNCA pode aparecer é o caminho de INSTALAÇÃO do LuauBench.
	assert(
		string.find(result.stderr, process.cwd, 1, true) == nil,
		`stderr NUNCA deveria conter o caminho de instalação do LuauBench ("{process.cwd}"): {result.stderr}`
	)
	assert(string.find(result.stderr, "\\src\\", 1, true) == nil, `stderr NUNCA deveria conter o padrão de caminho interno "\\src\\": {result.stderr}`)
	assert(string.find(result.stderr, "/src/", 1, true) == nil, `stderr NUNCA deveria conter o padrão de caminho interno "/src/": {result.stderr}`)
end)

-- Limpeza final -- `pcall` pra garantir que a bateria acima nunca deixe `PERSIST_SCRATCH_ROOT` pra
-- trás, mesmo se algo inesperado tiver deixado um arquivo com atributo especial pelo caminho
-- (mesmo protocolo de CloudStore.spec.luau).
pcall(function()
	fs.removeDir(PERSIST_SCRATCH_ROOT)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
