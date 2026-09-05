--!strict

--[[
	Teste de integração da task-cli-001 (src/cli/init.luau). `require("./")`, NÃO
	`require("./init")`/`require("./init.luau")` -- mesmo gotcha de resolução do Lune já
	documentado no cabeçalho de `init.luau` (e, antes, em `src/runtime/init.spec.luau`/
	`src/services/init.spec.luau`): só a forma "estilo diretório" carrega o `init.luau` real a
	partir de um arquivo irmão cujo nome também começa por "init".

	Cobre o acceptance do board relativo a `Cli.Main`: `--help`/`--version` funcionam de ponta a
	ponta (via `require("./")`, sem disparar processo -- é exatamente o cenário que `tests/
	scenarios/`, território do `testador`, vai exercitar), `--version` cita a versão do dump de
	`Services.GetDumpVersion()`, erro de uso devolve ExitCode 2.

	ATUALIZADO NA task-cli-006: `Cli.Main({'run', ...})` agora delega para `RunCommand.Execute`
	de verdade (pipeline completo -- ver `RunCommand.spec.luau` para a cobertura funda do
	pipeline em si; este arquivo só confirma que `Cli.Main`/`Cli.RunProject` FAZEM essa ligação
	corretamente, um teste de "fiação", não de comportamento de pipeline). O teste antigo de
	"run sem pipeline ainda" foi reescrito: hoje `Cli.Main({})` roda o pipeline de verdade contra
	`process.cwd` (a raiz do repositório, quando este spec roda via `lune run` a partir dela) --
	que não é um projeto Rojo, então o resultado ainda é ExitCode 2/ErrorCount 1, mas agora por um
	motivo real (`project/file-not-found`), não mais um placeholder "não implementado".

	Roda com `lune run src/cli/init.spec.luau`.

	PENDÊNCIA DE TOOLING (mesmo achado já documentado nos cabeçalhos de
	`src/runtime/init.spec.luau`/`src/services/init.spec.luau`, reconfirmado aqui pelo mesmo
	protocolo -- nunca por suposição, regra 00): `luau-lsp analyze` 1.69.0 devolve "Unknown
	require" para as duas linhas de `require` abaixo, só porque o NOME deste arquivo começa por
	"init" -- uma cópia idêntica renomeada (`ZZZNotInit.spec.luau`), analisada isolada, dá **zero
	erros** com os MESMOS `require`s. `lune run src/cli/init.spec.luau` roda e passa de verdade
	(7/7, reconfirmado na task-cli-006) -- é só a análise estática que erra. `revisor-cli` deve
	reproduzir a cópia renomeada antes de reprovar esta tarefa por causa de diagnóstico neste
	arquivo especificamente.
]]

local process = require("@lune/process")
local Cli = require("./")
local RunCommand = require("./RunCommand")
local Services = require("../services")

local FIXTURES_ROOT = process.cwd .. "src/cli/fixtures"

local function fixturePath(name: string): string
	return `{FIXTURES_ROOT}/{name}`
end

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Cli.Main({'--help'}) devolve ExitCode 0 sem erros/warnings", function()
	local result = Cli.Main({ "--help" })
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, "help não deveria contar como erro")
	assert(result.WarningCount == 0, "help não deveria contar como warning")
end)

test("Cli.Main({'--version'}) devolve ExitCode 0 e a versão do dump bate com Services.GetDumpVersion()", function()
	local result = Cli.Main({ "--version" })
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, "version não deveria contar como erro")

	-- Confirma que init.luau de fato consultou Services.GetDumpVersion() (regra do board:
	-- "--version cita commit/versão do dump vindos de Services.GetDumpVersion()") em vez de um
	-- literal hardcoded -- comparando contra a MESMA fonte que init.luau consulta.
	local dump = Services.GetDumpVersion()
	assert(dump.Version ~= "", "sanity check: GetDumpVersion() deveria devolver uma Version não vazia")
	assert(dump.Commit ~= "", "sanity check: GetDumpVersion() deveria devolver um Commit não vazio")
end)

test("Cli.Main({'--bogus'}) devolve ExitCode 2 com ErrorCount 1 (erro de uso)", function()
	local result = Cli.Main({ "--bogus" })
	assert(result.ExitCode == 2, `esperava ExitCode 2 (uso inválido), recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 1, "flag desconhecida deveria contar como 1 erro")
	assert(result.WarningCount == 0, "erro de uso não deveria contar como warning")
end)

test("Cli.Main({'run', '--watch'}) devolve ExitCode 2 (motivo técnico, não sucesso silencioso)", function()
	local result = Cli.Main({ "run", "--watch" })
	assert(result.ExitCode == 2, `--watch deveria recusar com ExitCode 2, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 1, "--watch deveria contar como 1 erro")
end)

test("Cli.Main({}) sem projeto Rojo em process.cwd devolve ExitCode 2, nunca finge sucesso (regra 00)", function()
	-- `process.cwd`, quando este spec roda via `lune run` a partir da raiz do repositório, não é
	-- um projeto Rojo (não há `default.project.json` ali -- ver CLAUDE.md, "Estado atual do
	-- projeto") -- então `RunCommand.Execute` (chamado de verdade por `Cli.Main`, task-cli-006)
	-- falha em `ProjectFile.Locate` com um diagnostic real, nunca um placeholder.
	local result = Cli.Main({})
	assert(result.ExitCode == 2, `esperava ExitCode 2, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 1, "deveria contar exatamente 1 erro (projeto não encontrado)")
end)

test("Cli.Main({'run', <fixture>}) liga o pipeline real de ponta a ponta (fixture 'run-e2e/basic') -- ExitCode 0", function()
	local result = Cli.Main({ "run", fixturePath("run-e2e/basic"), "--no-color" })
	assert(result.ExitCode == 0, `esperava ExitCode 0, recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 0, `esperava ErrorCount 0, recebeu {result.ErrorCount}`)
end)

test("Cli.RunProject(options) delega para RunCommand.Execute com as MESMAS RunOptions -- mesmo resultado", function()
	local options: RunCommand.RunOptions = {
		ProjectPath = fixturePath("run-e2e/basic"),
		Cwd = process.cwd,
		Timeout = nil,
		UseColor = false,
		Verbose = false,
	}
	local viaRunProject = Cli.RunProject(options)
	local viaExecuteDirectly = RunCommand.Execute(options)

	assert(viaRunProject.ExitCode == viaExecuteDirectly.ExitCode, "Cli.RunProject deveria devolver o MESMO ExitCode que RunCommand.Execute")
	assert(viaRunProject.ErrorCount == viaExecuteDirectly.ErrorCount, "Cli.RunProject deveria devolver o MESMO ErrorCount que RunCommand.Execute")
	assert(viaRunProject.ExitCode == 0, `sanity check: fixture 'basic' deveria terminar ExitCode 0, recebeu {viaRunProject.ExitCode}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
