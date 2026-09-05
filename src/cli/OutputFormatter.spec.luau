--!strict

--[[
	Teste da task-cli-006 (`OutputFormatter.luau`). Cobre o acceptance do board (Decisão 13):

	- `print` -> stdout; `warn`/`error` -> stderr (aqui: `OutputFormatter.FormatRecord` devolve o
	  STREAM certo -- a separação real via redirecionamento de processo é testada em
	  `RunCommand.spec.luau`, que spawna um `lune run` de verdade e inspeciona
	  `ExecResult.stdout`/`stderr` -- não há como interceptar `stdio.write`/`ewrite` reais de
	  dentro do mesmo processo, ver cabeçalho de `OutputFormatter.luau`).
	- Reatribuição de linha: erro vindo de um `ModuleScript` requerido (mensagem crua contendo
	  `[string "<módulo>"]:<linha>: <msg>`, `record.line == nil`) é renderizado citando o módulo
	  (nome + linha), não o Script de topo -- mas ainda cita o Script de topo como origem.
	- Erro "normal" (Script de topo, já limpo por `Sandbox.splitErrorMessage`, `record.line`
	  preenchido) é renderizado no formato direto, sem reatribuição.
	- `ErrorCount()` conta só `level == "error"`.
	- Cor: presente quando `useColor = true` (byte ANSI de verdade -- `\27`), ausente quando
	  `useColor = false`. `print` nunca ganha cor, mesmo com `useColor = true`.
	- Prefixo "DataModel." é removido de `scriptName` (e do nome do módulo reatribuído).

	Roda com `lune run src/cli/OutputFormatter.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local OutputFormatter = require("./OutputFormatter")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local ESCAPE = "\27"

local function hasEscapeCode(text: string): boolean
	return string.find(text, ESCAPE, 1, true) ~= nil
end

local function record(level: Runtime.OutputLevel, message: string, scriptName: string?, line: number?): Runtime.OutputRecord
	return {
		level = level,
		message = message,
		scriptName = scriptName,
		line = line,
		timestamp = os.time(),
	}
end

--------------------------------------------------------------------------------------------------
-- Roteamento de stream: print -> stdout, warn/error -> stderr
--------------------------------------------------------------------------------------------------

test("FormatRecord: print roteia para stdout", function()
	local line, stream = OutputFormatter.FormatRecord(record("print", "hello world", "DataModel.ServerScriptService.Main", nil), false)
	assert(stream == "stdout", `esperava stdout, recebeu {stream}`)
	assert(line == "ServerScriptService.Main: hello world", `linha inesperada: {line}`)
end)

test("FormatRecord: warn roteia para stderr, com o rótulo 'warn'", function()
	local line, stream = OutputFormatter.FormatRecord(record("warn", "cache miss", "DataModel.ServerScriptService.Main", nil), false)
	assert(stream == "stderr", `esperava stderr, recebeu {stream}`)
	assert(line == "warn  ServerScriptService.Main: cache miss", `linha inesperada: {line}`)
end)

test("FormatRecord: error roteia para stderr, com o rótulo 'error' e a linha quando presente", function()
	local line, stream = OutputFormatter.FormatRecord(record("error", "attempt to index nil with 'Foo'", "DataModel.ServerScriptService.Main", 12), false)
	assert(stream == "stderr", `esperava stderr, recebeu {stream}`)
	assert(line == "error ServerScriptService.Main:12: attempt to index nil with 'Foo'", `linha inesperada: {line}`)
end)

test("FormatRecord: error sem linha (record.line == nil, sem marcador de módulo) omite o ':N'", function()
	local line = OutputFormatter.FormatRecord(record("error", "something failed", "DataModel.ServerScriptService.Main", nil), false)
	assert(line == "error ServerScriptService.Main: something failed", `linha inesperada: {line}`)
end)

--------------------------------------------------------------------------------------------------
-- Prefixo "DataModel." removido de scriptName
--------------------------------------------------------------------------------------------------

test("FormatRecord: remove o prefixo 'DataModel.' de scriptName quando presente", function()
	local line = OutputFormatter.FormatRecord(record("print", "hi", "DataModel.Workspace.Foo", nil), false)
	assert(line == "Workspace.Foo: hi", `linha inesperada: {line}`)
end)

test("FormatRecord: scriptName sem o prefixo 'DataModel.' fica intacto", function()
	local line = OutputFormatter.FormatRecord(record("print", "hi", "Workspace.Foo", nil), false)
	assert(line == "Workspace.Foo: hi", `linha inesperada: {line}`)
end)

test("FormatRecord: scriptName nil usa o rótulo de fallback, nunca indexa nil", function()
	local line = OutputFormatter.FormatRecord(record("print", "hi", nil, nil), false)
	assert(line == "<unknown script>: hi", `linha inesperada: {line}`)
end)

--------------------------------------------------------------------------------------------------
-- Reatribuição de linha: erro de dentro de um ModuleScript requerido
--------------------------------------------------------------------------------------------------

test("FormatRecord: erro de um ModuleScript requerido é atribuído ao MÓDULO (nome + linha), citando o Script de origem", function()
	local rawMessage = '[string "ReplicatedStorage.Modules.Combat"]:12: attempt to index nil with \'Foo\''
	local line = OutputFormatter.FormatRecord(record("error", rawMessage, "DataModel.ServerScriptService.Main", nil), false)
	assert(
		line == "error ReplicatedStorage.Modules.Combat:12: attempt to index nil with 'Foo' (required by ServerScriptService.Main)",
		`linha inesperada: {line}`
	)
end)

test("FormatRecord: reatribuição funciona mesmo com um rótulo de categoria do Lune antes do marcador (ex.: 'runtime error: ')", function()
	local rawMessage = 'runtime error: [string "ReplicatedStorage.Modules.Combat"]:12: attempt to index nil with \'Foo\''
	local line = OutputFormatter.FormatRecord(record("error", rawMessage, "DataModel.ServerScriptService.Main", nil), false)
	assert(
		line == "error ReplicatedStorage.Modules.Combat:12: attempt to index nil with 'Foo' (required by ServerScriptService.Main)",
		`linha inesperada (prefixo de categoria não deveria impedir o casamento): {line}`
	)
end)

test("FormatRecord: mensagem sem marcador de módulo NÃO aciona a reatribuição (caminho normal preservado)", function()
	local line = OutputFormatter.FormatRecord(record("error", "attempt to call a nil value", "DataModel.ServerScriptService.Main", 7), false)
	assert(line == "error ServerScriptService.Main:7: attempt to call a nil value", `reatribuição não deveria ter disparado: {line}`)
end)

--------------------------------------------------------------------------------------------------
-- Cor
--------------------------------------------------------------------------------------------------

test("FormatRecord: useColor = true adiciona ANSI em warn/error, mas NUNCA em print", function()
	local printLine = OutputFormatter.FormatRecord(record("print", "hi", "Main", nil), true)
	local warnLine = OutputFormatter.FormatRecord(record("warn", "hi", "Main", nil), true)
	local errorLine = OutputFormatter.FormatRecord(record("error", "hi", "Main", nil), true)

	assert(not hasEscapeCode(printLine), "print nunca deveria ganhar cor")
	assert(hasEscapeCode(warnLine), "warn deveria ganhar cor quando useColor = true")
	assert(hasEscapeCode(errorLine), "error deveria ganhar cor quando useColor = true")
end)

test("FormatRecord: useColor = false nunca produz byte de escape ANSI", function()
	local printLine = OutputFormatter.FormatRecord(record("print", "hi", "Main", nil), false)
	local warnLine = OutputFormatter.FormatRecord(record("warn", "hi", "Main", nil), false)
	local errorLine = OutputFormatter.FormatRecord(record("error", "hi", "Main", nil), false)

	assert(not hasEscapeCode(printLine), "print não deveria ter cor")
	assert(not hasEscapeCode(warnLine), "warn não deveria ter cor com useColor = false")
	assert(not hasEscapeCode(errorLine), "error não deveria ter cor com useColor = false")
end)

--------------------------------------------------------------------------------------------------
-- Formatter (instância): Emit escreve, ErrorCount conta só "error"
--------------------------------------------------------------------------------------------------

test("Formatter.ErrorCount() conta só records de nível 'error' emitidos, nunca print/warn", function()
	local formatter = OutputFormatter.new(false)
	formatter:Emit(record("print", "a", "Main", nil))
	formatter:Emit(record("warn", "b", "Main", nil))
	assert(formatter:ErrorCount() == 0, `esperava ErrorCount 0 antes de qualquer erro, recebeu {formatter:ErrorCount()}`)

	formatter:Emit(record("error", "c", "Main", nil))
	assert(formatter:ErrorCount() == 1, `esperava ErrorCount 1 após um erro, recebeu {formatter:ErrorCount()}`)

	formatter:Emit(record("error", "d", "Main", nil))
	formatter:Emit(record("print", "e", "Main", nil))
	assert(formatter:ErrorCount() == 2, `esperava ErrorCount 2 após dois erros, recebeu {formatter:ErrorCount()}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
