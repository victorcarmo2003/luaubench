--!strict

--[[
	Teste da task-cli-001 (Diagnostics.luau): `Bag` acumula e conta por severidade, `Render`
	produz uma linha legível com e sem cor, e o `Code` de cada diagnóstico é o identificador
	estável que outro teste (nas tarefas seguintes, quando `ProjectFile`/`TreePlanner` existirem)
	vai asserir sem casar texto.

	Roda com `lune run src/cli/Diagnostics.spec.luau`.
]]

local process = require("@lune/process")
local Diagnostics = require("./Diagnostics")

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

test("Bag começa vazio: All() vazio, CountOf 0 para as três severidades, HasErrors false", function()
	local bag = Diagnostics.newBag()
	assert(#bag:All() == 0, "Bag novo deveria começar sem diagnósticos")
	assert(bag:CountOf("error") == 0, "CountOf('error') deveria começar em 0")
	assert(bag:CountOf("warning") == 0, "CountOf('warning') deveria começar em 0")
	assert(bag:CountOf("info") == 0, "CountOf('info') deveria começar em 0")
	assert(not bag:HasErrors(), "Bag novo não deveria ter erros")
end)

test("Add acumula e CountOf/HasErrors refletem a severidade de cada diagnóstico", function()
	local bag = Diagnostics.newBag()

	bag:Add({ Severity = "warning", Code = "sync/unsupported-extension", Message = "arquivo .csv ignorado" })
	assert(bag:CountOf("warning") == 1, "deveria contar 1 warning após o primeiro Add")
	assert(not bag:HasErrors(), "só um warning não deveria marcar HasErrors")

	bag:Add({ Severity = "error", Code = "project/unknown-field", Message = "campo desconhecido" })
	assert(bag:CountOf("error") == 1, "deveria contar 1 error após o segundo Add")
	assert(bag:HasErrors(), "um error deveria marcar HasErrors")

	bag:Add({ Severity = "info", Code = "sync/optional-path-missing", Message = "path opcional ausente" })
	assert(bag:CountOf("info") == 1, "deveria contar 1 info após o terceiro Add")

	assert(#bag:All() == 3, "All() deveria devolver os três diagnósticos acumulados")
	assert(bag:CountOf("warning") == 1 and bag:CountOf("error") == 1, "contagens anteriores não deveriam ter sido afetadas por Adds seguintes")
end)

test("All() devolve uma cópia -- mutar a tabela devolvida não afeta o estado interno do Bag", function()
	local bag = Diagnostics.newBag()
	bag:Add({ Severity = "error", Code = "x", Message = "y" })

	local snapshot = bag:All()
	table.remove(snapshot, 1)

	assert(#bag:All() == 1, "remover da cópia devolvida por All() não deveria afetar o Bag real")
end)

test("Render produz uma linha legível citando severidade, Code e Message", function()
	local diagnostic: Diagnostics.Diagnostic = {
		Severity = "error",
		Code = "project/unknown-field",
		Message = 'Unknown field "tre" at the project root',
	}

	local line = Diagnostics.Render(diagnostic, false)
	assert(contains(line, "project/unknown-field"), "linha deveria citar o Code")
	assert(contains(line, "Unknown field"), "linha deveria citar a Message")
end)

test("Render sem cor não contém nenhum código ANSI (byte 0x1b)", function()
	local diagnostic: Diagnostics.Diagnostic = { Severity = "warning", Code = "w", Message = "m" }
	local line = Diagnostics.Render(diagnostic, false)
	assert(string.find(line, "\27", 1, true) == nil, "Render(useColor=false) não deveria conter nenhum escape ANSI")
end)

test("Render com cor contém código ANSI (byte 0x1b) e ainda carrega Code/Message legíveis", function()
	local diagnostic: Diagnostics.Diagnostic = { Severity = "error", Code = "e", Message = "m" }
	local line = Diagnostics.Render(diagnostic, true)
	assert(string.find(line, "\27", 1, true) ~= nil, "Render(useColor=true) deveria conter ao menos um escape ANSI")
	assert(contains(line, "e") and contains(line, "m"), "a linha colorida ainda deveria carregar Code/Message por baixo do ANSI")
end)

test("Render inclui NodePath/FilePath/Field/ProjectPath quando presentes, omite quando ausentes", function()
	local withLocation: Diagnostics.Diagnostic = {
		Severity = "error",
		Code = "property/not-a-member",
		Message = "propriedade não existe",
		NodePath = "tree.ReplicatedStorage.Modules",
		FilePath = "C:/proj/default.project.json",
		Field = "$properties.Gravty",
		ProjectPath = "C:/proj/default.project.json",
	}
	local line = Diagnostics.Render(withLocation, false)
	assert(contains(line, "tree.ReplicatedStorage.Modules"), "deveria citar o NodePath")
	assert(contains(line, "C:/proj/default.project.json"), "deveria citar o FilePath/ProjectPath")
	assert(contains(line, "$properties.Gravty"), "deveria citar o Field")

	-- Confirma que os rótulos de localização vêm de Messages.LocationLabel (achado ALTO da revisão
	-- de task-cli-001) -- os quatro prefixos exatos ainda aparecem na linha final, na ordem
	-- node -> field -> file -> project que buildLocationSuffix monta.
	assert(contains(line, "node: tree.ReplicatedStorage.Modules"), "deveria conter o segmento 'node: ...' completo")
	assert(contains(line, "field: $properties.Gravty"), "deveria conter o segmento 'field: ...' completo")
	assert(contains(line, "file: C:/proj/default.project.json"), "deveria conter o segmento 'file: ...' completo")
	assert(contains(line, "project: C:/proj/default.project.json"), "deveria conter o segmento 'project: ...' completo")

	local withoutLocation: Diagnostics.Diagnostic = { Severity = "info", Code = "x", Message = "y" }
	local plainLine = Diagnostics.Render(withoutLocation, false)
	assert(not contains(plainLine, "("), "sem nenhum campo de localização, a linha não deveria abrir parênteses")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
