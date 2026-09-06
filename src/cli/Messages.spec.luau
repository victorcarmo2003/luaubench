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

test("HelpText documenta --allow-http/--allow-http-local -- default off e o que --allow-http-local libera", function()
	local text = Messages.HelpText()
	assert(contains(text, "--allow-http"), "HelpText deveria citar --allow-http")
	assert(contains(text, "--allow-http-local"), "HelpText deveria citar --allow-http-local")
	assert(contains(text, "Off by default"), "HelpText deveria deixar claro que a rede é desligada por padrão")
	assert(contains(text, "local"), "HelpText deveria mencionar que a segunda flag libera destinos locais/privados")
	assert(contains(text, "Implies --allow-http"), "HelpText deveria deixar explícita a implicação --allow-http-local -> --allow-http")
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

test("HttpRequestAuditLine interpola método + host, e NUNCA menciona corpo/headers (task-cli-026)", function()
	local line = Messages.HttpRequestAuditLine("POST", "example.com")
	assert(contains(line, "POST"), "deveria citar o método recebido")
	assert(contains(line, "example.com"), "deveria citar o host recebido")

	-- HttpRequestAuditLine só recebe (method, host) -- não há como um corpo/header vazar por ela,
	-- mas o teste trava a INTENÇÃO explicitamente: um payload nunca deveria aparecer numa chamada
	-- normal com method/host limpos.
	assert(not contains(line, "Authorization"), "linha de auditoria nunca deveria conter cabeçalho/corpo")
end)

--------------------------------------------------------------------------------------------------
-- Persistência local do estado "cloud" (task-cli-030, par de task-cli-029/task-services-031)
--------------------------------------------------------------------------------------------------

test("HelpText documenta --no-persist -- persistência ligada por padrão", function()
	local text = Messages.HelpText()
	assert(contains(text, "--no-persist"), "HelpText deveria citar --no-persist")
	assert(contains(text, "DataStoreService"), "HelpText deveria mencionar o que --no-persist desliga")
end)

test("CloudStateDirectoryCreated cita o caminho e menciona git-ignored + como desfazer", function()
	local message = Messages.CloudStateDirectoryCreated("/tmp/my-project/.luaubench")
	assert(contains(message, "/tmp/my-project/.luaubench"), "deveria citar o caminho exato recebido")
	assert(contains(message, "git-ignored"), "deveria deixar claro que o diretório é git-ignored por padrão")
	assert(contains(message, ".gitignore"), "deveria citar como desfazer (apagar o .gitignore gerado)")
end)

test("CloudStateUnreadable cita o caminho e o erro subjacente, nunca inventa um motivo genérico", function()
	local message = Messages.CloudStateUnreadable("/tmp/my-project/.luaubench/cloud/datastore.json", "unsupported SchemaVersion 99")
	assert(contains(message, "/tmp/my-project/.luaubench/cloud/datastore.json"), "deveria citar o caminho exato do documento")
	assert(contains(message, "unsupported SchemaVersion 99"), "deveria citar o erro subjacente recebido, sem reformular")
end)

test("CloudStateSaveFailed cita o caminho e o erro subjacente, e deixa claro que o script continua rodando", function()
	local message = Messages.CloudStateSaveFailed("/tmp/my-project/.luaubench/cloud/datastore.json", "permission denied")
	assert(contains(message, "/tmp/my-project/.luaubench/cloud/datastore.json"), "deveria citar o caminho exato do documento")
	assert(contains(message, "permission denied"), "deveria citar o erro subjacente recebido, sem reformular")
	assert(contains(message, "keeps running"), "deveria deixar claro que o script continua rodando com o estado em memória")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
