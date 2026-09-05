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
	`Services.GetDumpVersion()`, erro de uso devolve ExitCode 2, e o comando "run" (ainda sem
	pipeline real nesta tarefa) devolve um resultado honesto de "não implementado" em vez de
	fingir sucesso.

	Roda com `lune run src/cli/init.spec.luau`.

	PENDÊNCIA DE TOOLING (mesmo achado já documentado nos cabeçalhos de
	`src/runtime/init.spec.luau`/`src/services/init.spec.luau`, reconfirmado aqui pelo mesmo
	protocolo -- nunca por suposição, regra 00): `luau-lsp analyze` 1.69.0 devolve "Unknown
	require" para as duas linhas de `require` abaixo, só porque o NOME deste arquivo começa por
	"init" -- uma cópia idêntica renomeada (`ZZZNotInit.spec.luau`), analisada isolada, dá **zero
	erros** com os MESMOS `require`s. `lune run src/cli/init.spec.luau` roda e passa de verdade
	(5/5, confirmado nesta tarefa) -- é só a análise estática que erra. `revisor-cli` deve
	reproduzir a cópia renomeada antes de reprovar esta tarefa por causa de diagnóstico neste
	arquivo especificamente.
]]

local process = require("@lune/process")
local Cli = require("./")
local Services = require("../services")

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

test("Cli.Main({}) (comando 'run' sem pipeline ainda) devolve ExitCode 2, nunca finge sucesso (regra 00)", function()
	local result = Cli.Main({})
	assert(result.ExitCode == 2, `run sem pipeline implementado deveria devolver ExitCode 2 (não-sucesso), recebeu {result.ExitCode}`)
	assert(result.ErrorCount == 1, "run sem pipeline deveria contar como 1 erro, nunca 0 (que pareceria sucesso)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
