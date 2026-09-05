--!strict

--[[
	Teste da task-cli-001 (Messages.luau). `Messages` não tem ramificação real (é formatação),
	então o teste cobre o que é prático e vale a pena travar: os FATOS que cada mensagem precisa
	carregar (regra 04 -- `--watch` cita o motivo técnico real, não "flag desconhecida"; a versão
	citada em `VersionLine` é a que foi passada, não um literal hardcoded) e que a interpolação
	de parâmetros realmente aparece na saída.

	Roda com `lune run src/cli/Messages.spec.luau`.
]]

local process = require("@lune/process")
local Messages = require("./Messages")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

test("HelpText menciona as três flags de --run e --help/--version", function()
	local text = Messages.HelpText()
	assert(contains(text, "--timeout"), "HelpText deveria citar --timeout")
	assert(contains(text, "--no-color"), "HelpText deveria citar --no-color")
	assert(contains(text, "--verbose"), "HelpText deveria citar --verbose")
	assert(contains(text, "--watch"), "HelpText deveria citar --watch (reconhecida, mesmo não suportada)")
	assert(contains(text, "--help"), "HelpText deveria citar --help")
	assert(contains(text, "--version"), "HelpText deveria citar --version")
end)

test("VersionLine interpola exatamente os três parâmetros recebidos, nunca um literal fixo", function()
	local line = Messages.VersionLine("9.9.9-teste", "0.000.0.0000000-teste", "commitDeTeste123")
	assert(contains(line, "9.9.9-teste"), "deveria conter a versão do CLI passada")
	assert(contains(line, "0.000.0.0000000-teste"), "deveria conter a versão do dump passada")
	assert(contains(line, "commitDeTeste123"), "deveria conter o commit passado")
end)

test("UnknownFlag cita a flag recebida", function()
	local message = Messages.UnknownFlag("--bogus")
	assert(contains(message, "--bogus"), "mensagem deveria citar a flag desconhecida exata")
end)

test("MissingFlagValue/InvalidFlagValue citam a flag (e o valor, no segundo caso)", function()
	local missing = Messages.MissingFlagValue("--timeout")
	assert(contains(missing, "--timeout"), "MissingFlagValue deveria citar a flag")

	local invalid = Messages.InvalidFlagValue("--timeout", "abc")
	assert(contains(invalid, "--timeout"), "InvalidFlagValue deveria citar a flag")
	assert(contains(invalid, "abc"), "InvalidFlagValue deveria citar o valor inválido recebido")
end)

test("UnexpectedArgument cita o argumento recebido", function()
	local message = Messages.UnexpectedArgument("extra")
	assert(contains(message, "extra"), "mensagem deveria citar o argumento inesperado")
end)

test("WatchNotSupported cita o motivo técnico real (Lune 0.10.5, rokit.toml, sem polling) -- Decisão 9", function()
	local message = Messages.WatchNotSupported()
	assert(contains(message, "0.10.5"), "deveria citar a versão do Lune fixada")
	assert(contains(message, "rokit.toml"), "deveria citar onde a versão está fixada")
	assert(contains(message, "polling"), "deveria explicar que LuauBench não faz polling em vez de watcher real")
	assert(not contains(message, "flag desconhecida"), "--watch NUNCA deveria ser reportada como flag desconhecida (Decisão 9)")
end)

test("RunPipelineNotImplementedYet não finge sucesso -- menciona que o pipeline ainda não existe", function()
	local message = Messages.RunPipelineNotImplementedYet()
	assert(contains(message, "luaubench run"), "deveria citar o comando afetado")
	assert(contains(message, "not"), "deveria deixar claro que não está pronto, nunca fingir sucesso")
end)

test("SeverityLabel cobre as três severidades com rótulos distintos", function()
	local errorLabel = Messages.SeverityLabel("error")
	local warningLabel = Messages.SeverityLabel("warning")
	local infoLabel = Messages.SeverityLabel("info")

	assert(errorLabel ~= warningLabel and warningLabel ~= infoLabel and errorLabel ~= infoLabel, "as três severidades deveriam ter rótulos distintos")
end)

test("LocationLabel cobre os quatro tipos de localização com os rótulos exatos node/field/file/project", function()
	-- Trava a redação exata (não só "são distintos") -- achado ALTO da revisão de task-cli-001:
	-- esses rótulos apareciam como literais soltos em Diagnostics.luau, e a promessa de que trocar
	-- o idioma dos diagnósticos custa editar só este arquivo depende de nenhum outro lugar do
	-- território guardar a própria cópia da palavra.
	assert(Messages.LocationLabel("node") == "node", "LocationLabel('node') deveria devolver exatamente 'node'")
	assert(Messages.LocationLabel("field") == "field", "LocationLabel('field') deveria devolver exatamente 'field'")
	assert(Messages.LocationLabel("file") == "file", "LocationLabel('file') deveria devolver exatamente 'file'")
	assert(Messages.LocationLabel("project") == "project", "LocationLabel('project') deveria devolver exatamente 'project'")
end)

test("LocationSegment/DiagnosticLine compõem uma linha legível com código, mensagem e localização", function()
	local segment = Messages.LocationSegment("node", "tree.ReplicatedStorage")
	assert(contains(segment, "node") and contains(segment, "tree.ReplicatedStorage"), "segmento deveria citar rótulo e valor")

	local line = Messages.DiagnosticLine("error", "project/unknown-field", "Unknown field \"tre\"", ` ({segment})`)
	assert(contains(line, "error"), "linha deveria citar a severidade")
	assert(contains(line, "project/unknown-field"), "linha deveria citar o Code")
	assert(contains(line, "Unknown field"), "linha deveria citar a Message")
	assert(contains(line, "tree.ReplicatedStorage"), "linha deveria citar a localização")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
