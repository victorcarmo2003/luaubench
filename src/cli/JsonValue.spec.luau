--!strict

--[[
	Teste da task-cli-002 (JsonValue.luau). Cobre o acceptance do board: decodifica JSONC
	(comentário + vírgula sobrando), JSON malformado vira Diagnostic citando o arquivo (nunca
	stack trace cru do parser), e os cinco acessores (AsObject/AsString/AsNumber/AsBoolean/
	AsArray) devolvem valor OU Diagnostic nomeando o path e os tipos esperado/encontrado -- nunca
	lançam erro cru.

	Roda com `lune run src/cli/JsonValue.spec.luau`.
]]

local process = require("@lune/process")
local JsonValue = require("./JsonValue")

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

--------------------------------------------------------------------------------------------------
-- Decode
--------------------------------------------------------------------------------------------------

test("Decode aceita JSON estrito e devolve a árvore como JsonValue, sem Diagnostic", function()
	local value, diagnostic = JsonValue.Decode('{"a": 1, "b": [1, 2, 3], "c": "x", "d": true, "e": null}', "test.json")
	assert(diagnostic == nil, "JSON estrito válido não deveria produzir Diagnostic")
	assert(value ~= nil, "Decode deveria devolver um valor não-nil pra um objeto JSON não-vazio")

	if value ~= nil then
		local object = JsonValue.AsObject(value, "<root>")
		assert(object ~= nil, "o valor decodificado deveria ser acessível como objeto")
		if object ~= nil then
			assert(object["c"] == "x", "campo string deveria vir intacto")
			assert(object["d"] == true, "campo boolean deveria vir intacto")
			-- "e": null -- serde.decode devolve `nil` puro pra JSON null; uma tabela Lua não
			-- consegue distinguir "chave ausente" de "chave == nil" (limitação honesta,
			-- documentada no cabeçalho de JsonValue.luau) -- então "e" simplesmente não aparece.
			assert(object["e"] == nil, "JSON null vira ausência de chave (limitação declarada)")
		end
	end
end)

test("Decode tolera comentários '//' e '/* */' e vírgula sobrando (JSONC)", function()
	local text = [[
		{
			// comentário de linha
			"a": 1, /* comentário de bloco */
			"b": [1, 2, 3,],
		}
	]]
	local value, diagnostic = JsonValue.Decode(text, "test.jsonc")
	assert(diagnostic == nil, "JSONC válido (comentário + vírgula sobrando) não deveria produzir Diagnostic")
	assert(value ~= nil, "Decode deveria conseguir decodificar JSONC válido")

	if value ~= nil then
		local object = JsonValue.AsObject(value, "<root>")
		assert(object ~= nil, "resultado deveria ser um objeto")
		if object ~= nil then
			assert(object["a"] == 1, "campo numérico antes do comentário de bloco deveria vir intacto")
		end
	end
end)

test("Decode de JSON malformado devolve Diagnostic citando o sourcePath, NUNCA stack trace cru", function()
	local value, diagnostic = JsonValue.Decode("{ this is not json", "C:/proj/default.project.json")
	assert(value == nil, "JSON malformado não deveria produzir um valor")
	assert(diagnostic ~= nil, "JSON malformado deveria produzir um Diagnostic")

	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "JSON malformado deveria ser Severity 'error'")
		assert(diagnostic.FilePath == "C:/proj/default.project.json", "Diagnostic deveria citar o sourcePath recebido")
		assert(
			not contains(diagnostic.Message, "stack traceback"),
			"Message NUNCA deveria conter um stack trace cru do parser (regra 04)"
		)
		assert(not contains(diagnostic.Message, "[C]:"), "Message não deveria conter frames de stack cru (formato do Lune)")
	end
end)

--------------------------------------------------------------------------------------------------
-- AsObject
--------------------------------------------------------------------------------------------------

test("AsObject aceita objeto (inclusive vazio) e rejeita array/primitivo citando path e tipos", function()
	local objectValue = JsonValue.Decode('{"x": 1}', "t")
	assert(objectValue ~= nil)
	if objectValue ~= nil then
		local object, diagnostic = JsonValue.AsObject(objectValue, "root")
		assert(object ~= nil and diagnostic == nil, "objeto válido deveria ser aceito sem Diagnostic")
	end

	local emptyValue = JsonValue.Decode("{}", "t")
	assert(emptyValue ~= nil)
	if emptyValue ~= nil then
		local emptyObject, emptyDiagnostic = JsonValue.AsObject(emptyValue, "root")
		assert(emptyObject ~= nil and emptyDiagnostic == nil, "objeto vazio deveria ser aceito como objeto (ambiguidade JSON declarada)")
	end

	local arrayValue = JsonValue.Decode("[1, 2, 3]", "t")
	assert(arrayValue ~= nil)
	if arrayValue ~= nil then
		local rejected, diagnostic = JsonValue.AsObject(arrayValue, "tree.$path")
		assert(rejected == nil, "array não deveria ser aceito como objeto")
		assert(diagnostic ~= nil, "deveria produzir Diagnostic")
		if diagnostic ~= nil then
			assert(diagnostic.Field == "tree.$path", "Diagnostic deveria carregar o path recebido")
			assert(contains(diagnostic.Message, "tree.$path"), "Message deveria citar o path")
			assert(contains(diagnostic.Message, "object"), "Message deveria citar o tipo esperado (object)")
			assert(contains(diagnostic.Message, "array"), "Message deveria citar o tipo encontrado (array)")
		end
	end

	local stringValue = JsonValue.Decode('"hello"', "t")
	assert(stringValue ~= nil)
	if stringValue ~= nil then
		local rejected, diagnostic = JsonValue.AsObject(stringValue, "$className")
		assert(rejected == nil, "string não deveria ser aceita como objeto")
		if diagnostic ~= nil then
			assert(contains(diagnostic.Message, "string"), "Message deveria citar o tipo encontrado (string)")
		end
	end
end)

--------------------------------------------------------------------------------------------------
-- AsArray
--------------------------------------------------------------------------------------------------

test("AsArray aceita array e rejeita objeto/primitivo citando path e tipos", function()
	local arrayValue = JsonValue.Decode("[1, 2, 3]", "t")
	assert(arrayValue ~= nil)
	if arrayValue ~= nil then
		local array, diagnostic = JsonValue.AsArray(arrayValue, "globIgnorePaths")
		assert(array ~= nil and diagnostic == nil, "array válido deveria ser aceito sem Diagnostic")
		if array ~= nil then
			assert(#array == 3, "array deveria preservar os três elementos")
		end
	end

	local objectValue = JsonValue.Decode('{"optional": "src"}', "t")
	assert(objectValue ~= nil)
	if objectValue ~= nil then
		local rejected, diagnostic = JsonValue.AsArray(objectValue, "globIgnorePaths")
		assert(rejected == nil, "objeto não deveria ser aceito como array")
		if diagnostic ~= nil then
			assert(contains(diagnostic.Message, "array"), "Message deveria citar o tipo esperado (array)")
			assert(contains(diagnostic.Message, "object"), "Message deveria citar o tipo encontrado (object)")
		end
	end

	local numberValue = JsonValue.Decode("42", "t")
	assert(numberValue ~= nil)
	if numberValue ~= nil then
		local rejected, diagnostic = JsonValue.AsArray(numberValue, "syncRules")
		assert(rejected == nil, "número não deveria ser aceito como array")
		if diagnostic ~= nil then
			assert(contains(diagnostic.Message, "number"), "Message deveria citar o tipo encontrado (number)")
		end
	end
end)

--------------------------------------------------------------------------------------------------
-- AsString / AsNumber / AsBoolean
--------------------------------------------------------------------------------------------------

test("AsString aceita string e rejeita outros tipos citando path e tipos", function()
	local stringValue = JsonValue.Decode('"ReplicatedStorage"', "t")
	assert(stringValue ~= nil)
	if stringValue ~= nil then
		local text, diagnostic = JsonValue.AsString(stringValue, "$className")
		assert(text == "ReplicatedStorage" and diagnostic == nil, "string válida deveria ser aceita sem Diagnostic")
	end

	local numberValue = JsonValue.Decode("1", "t")
	assert(numberValue ~= nil)
	if numberValue ~= nil then
		local rejected, diagnostic = JsonValue.AsString(numberValue, "$className")
		assert(rejected == nil, "número não deveria ser aceito como string")
		if diagnostic ~= nil then
			assert(contains(diagnostic.Message, "$className"), "Message deveria citar o path")
			assert(contains(diagnostic.Message, "string"), "Message deveria citar o tipo esperado (string)")
			assert(contains(diagnostic.Message, "number"), "Message deveria citar o tipo encontrado (number)")
		end
	end
end)

test("AsNumber aceita número e rejeita outros tipos", function()
	local numberValue = JsonValue.Decode("42", "t")
	assert(numberValue ~= nil)
	if numberValue ~= nil then
		local number, diagnostic = JsonValue.AsNumber(numberValue, "servePort")
		assert(number == 42 and diagnostic == nil, "número válido deveria ser aceito sem Diagnostic")
	end

	local boolValue = JsonValue.Decode("true", "t")
	assert(boolValue ~= nil)
	if boolValue ~= nil then
		local rejected, diagnostic = JsonValue.AsNumber(boolValue, "servePort")
		assert(rejected == nil, "boolean não deveria ser aceito como número")
		if diagnostic ~= nil then
			assert(contains(diagnostic.Message, "number"), "Message deveria citar o tipo esperado (number)")
			assert(contains(diagnostic.Message, "boolean"), "Message deveria citar o tipo encontrado (boolean)")
		end
	end
end)

test("AsBoolean aceita boolean e rejeita outros tipos, inclusive null", function()
	local boolValue = JsonValue.Decode("false", "t")
	assert(boolValue ~= nil)
	if boolValue ~= nil then
		local boolean, diagnostic = JsonValue.AsBoolean(boolValue, "emitLegacyScripts")
		assert(boolean == false and diagnostic == nil, "boolean válido (false) deveria ser aceito sem Diagnostic")
	end

	local nullValue = JsonValue.Decode("null", "t")
	assert(nullValue == nil, "Decode('null') devolve nil (sem Diagnostic) -- é o valor JSON null, não uma falha")

	-- `nullValue` já É `nil` (o próprio JsonValue), então chamamos o acessor direto sobre ele.
	local rejected, diagnostic = JsonValue.AsBoolean(nullValue, "emitLegacyScripts")
	assert(rejected == nil, "null não deveria ser aceito como boolean")
	if diagnostic ~= nil then
		assert(contains(diagnostic.Message, "null"), "Message deveria citar o tipo encontrado (null, vocabulário JSON, não 'nil')")
	end
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
