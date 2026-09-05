--!strict

--[[
	Narrowing de `unknown` para JSON tipado (arquiteto-cli-2026-09-05.md, seção "Módulos" ->
	"JsonValue.luau"; Decisão 2, "JSONC sempre, e um módulo de narrowing entre `serde` e o
	resto"). Único ponto de TODO o território `cli` que chama `serde.decode` -- nenhum outro
	módulo (`ProjectFile.luau` incluído) toca `@lune/serde` diretamente.

	Decodifica SEMPRE com o formato `"jsonc"` -- Lune 0.10.5 confirma que JSON estrito é um
	subconjunto válido (`serde.EncodeDecodeFormat`), e o Rojo real também não ramifica por
	extensão (`.project.json` aceita comentário igual a `.project.jsonc` -- pesquisa-formato-
	projeto-rojo-2026-09-05.md, seção 1). Ramificar por extensão aqui divergiria do motor real
	sem ganho nenhum.

	`serde.decode(format, s): any` devolve `any` -- fronteira externa que regra 01 proíbe manter
	como `any` em qualquer lugar do nosso código. O CAST DE FRONTEIRA fica isolado em
	`JsonValue.Decode`, comentado no ponto exato: o closure passado a `pcall` já anota seu
	próprio retorno como `unknown` (não `any`) no lugar onde tocamos `serde.decode` -- é o mesmo
	precedente do cast de `LoadOptions.environment` em `src/runtime/Sandbox.luau:392`, só que na
	direção de LEITURA (lá se escreve um valor nosso num campo `any` externo; aqui se lê um
	valor externo `any` para dentro do nosso `JsonValue`). Daqui em diante, absolutamente nada
	do território usa a palavra `any` -- os acessores abaixo (`AsObject`/`AsString`/`AsNumber`/
	`AsBoolean`/`AsArray`) só manipulam `JsonValue`/`unknown`, nunca `any`.

	Ambiguidade de JSON->Lua HONESTAMENTE DECLARADA (regra 00): `null` decodifica para `nil` puro
	do Lua -- como uma tabela Lua não consegue distinguir "chave ausente" de "chave presente com
	valor nil", um campo do `.project.json` setado explicitamente para `null` se comporta,
	daqui em diante, EXATAMENTE como se o campo estivesse ausente. Confirmado empiricamente
	(`serde.decode("jsonc", "null")` devolve `nil`) -- comportamento padrão de qualquer ponte
	Lua<->JSON, não é bug nosso.

	Acessores (`AsObject`/`AsString`/`AsNumber`/`AsBoolean`/`AsArray`) recebem o `JsonValue` e um
	`path` (só para a mensagem de erro, ex.: `"tree.ReplicatedStorage.$path"`) e devolvem
	`(valor?, Diagnostic?)` -- nunca lançam erro cru (regra 04: "erro claro apontando o campo
	problemático, nunca stack trace cru do parser"). `ProjectFile.luau` é o consumidor principal,
	mas este módulo não conhece nada de Rojo/`.project.json` -- é JSON genérico.
]]

local serde = require("@lune/serde")
local Diagnostics = require("./Diagnostics")
local Messages = require("./Messages")

export type JsonValue = nil | boolean | number | string | { JsonValue } | { [string]: JsonValue }

local JsonValue = {}

-- Uma tabela JSON decodificada pelo serde é um ARRAY quando sua primeira chave (via `next`) é um
-- NÚMERO -- chave de objeto JSON é sempre string, e o serde nunca reinterpreta uma chave de
-- objeto como número (confirmado empiricamente para esta task: `next({"optional":"src"})`
-- devolve chave `string`, `next({1,2,3})` devolve chave `number`). Tabela vazia é ambígua por
-- natureza do JSON (`{}` e `[]` decodificam igual -- `next` devolve `nil` pros dois) -- tratamos
-- vazio como OBJETO por default, o caso mais comum no uso deste território (`$properties`/
-- `$attributes`/nó da árvore ausentes/vazios).
local function isArrayShaped(value: { [unknown]: unknown }): boolean
	local firstKey = next(value)
	if firstKey == nil then
		return false
	end
	return typeof(firstKey) == "number"
end

-- Descreve o "kind" de um `JsonValue` em vocabulário JSON (não Luau) -- "null" em vez de "nil",
-- "array"/"object" em vez de só "table" -- é o que aparece do lado "found" de
-- `Messages.JsonTypeMismatch`. Único lugar do território com lógica de decisão sobre isso;
-- `Messages.luau` só formata os dois rótulos já prontos.
local function describeKind(value: JsonValue): string
	if value == nil then
		return "null"
	end

	local kind = typeof(value)
	if kind == "table" then
		-- Cast em duas etapas por `unknown` -- mesmo padrão já usado em runtime/services pra
		-- reconciliar os dois shapes de tabela do union `JsonValue` (array vs. objeto), que o
		-- Luau trata como estruturalmente não relacionados aos olhos do `next` genérico.
		local asGeneric = (value :: unknown) :: { [unknown]: unknown }
		if isArrayShaped(asGeneric) then
			return "array"
		end
		return "object"
	end

	return kind
end

-- Uma falha de `serde.decode` chega via `pcall` como um valor do tipo exótico do próprio Lune
-- (`typeof(...) == "error"`, confirmado empiricamente para esta task -- não estava na pesquisa
-- salva). `tostring(...)` sobre ele devolve a mensagem do parser SEGUIDA de
-- "\nstack traceback:\n\t..." multi-linha -- mesmo formato que `src/runtime/Sandbox.luau` já
-- documenta pra erro de `coroutine.resume`. Corta na primeira quebra de linha: é o que garante
-- que o `Diagnostic` NUNCA carregue um stack trace cru do parser (regra 04). `tostring` aceita
-- literalmente qualquer valor (inclusive um `unknown` não estreitado) -- não precisa de
-- narrowing antes de chamar.
local function firstLineOf(value: unknown): string
	local text = tostring(value)
	local newlineIndex = string.find(text, "\n", 1, true)
	if newlineIndex == nil then
		return text
	end
	return string.sub(text, 1, newlineIndex - 1)
end

local function typeMismatch(path: string, expectedKind: string, actualKind: string): Diagnostics.Diagnostic
	return {
		Severity = "error",
		Code = "json/type-mismatch",
		Message = Messages.JsonTypeMismatch(path, expectedKind, actualKind),
		Field = path,
	}
end

-- Único ponto do território que chama `serde.decode`. `sourcePath` só é usado para citar o
-- arquivo na mensagem de erro (regra 04) -- este módulo não lê filesystem, quem chama já tem o
-- texto em mãos (`ProjectFile.Read` via `fs.readFile`).
function JsonValue.Decode(text: string, sourcePath: string): (JsonValue?, Diagnostics.Diagnostic?)
	local ok, decodedOrError = pcall(function(): unknown
		return serde.decode("jsonc", text)
	end)

	if not ok then
		return nil, {
			Severity = "error",
			Code = "json/malformed",
			Message = Messages.MalformedJson(sourcePath, firstLineOf(decodedOrError)),
			FilePath = sourcePath,
		}
	end

	-- CAST DE FRONTEIRA ÚNICO do território sobre a saída de `serde.decode`: o closure acima já
	-- anota seu próprio retorno como `unknown` (nunca `any`) no exato ponto em que tocamos a
	-- fronteira externa -- é o que elimina `any` por completo (em vez de só escondê-lo atrás de
	-- um cast). Daqui em diante, `decodedOrError` é tratado como `JsonValue`; nenhum outro
	-- módulo do território chama `serde.decode` diretamente -- todo acesso passa pelos
	-- acessores abaixo.
	local value = (decodedOrError :: unknown) :: JsonValue
	return value, nil
end

function JsonValue.AsObject(value: JsonValue, path: string): ({ [string]: JsonValue }?, Diagnostics.Diagnostic?)
	if typeof(value) == "table" then
		local asGeneric = (value :: unknown) :: { [unknown]: unknown }
		if isArrayShaped(asGeneric) then
			return nil, typeMismatch(path, "object", "array")
		end
		return (value :: unknown) :: { [string]: JsonValue }, nil
	end
	return nil, typeMismatch(path, "object", describeKind(value))
end

function JsonValue.AsArray(value: JsonValue, path: string): ({ JsonValue }?, Diagnostics.Diagnostic?)
	if typeof(value) == "table" then
		local asGeneric = (value :: unknown) :: { [unknown]: unknown }
		if not isArrayShaped(asGeneric) then
			return nil, typeMismatch(path, "array", describeKind(value))
		end
		return (value :: unknown) :: { JsonValue }, nil
	end
	return nil, typeMismatch(path, "array", describeKind(value))
end

function JsonValue.AsString(value: JsonValue, path: string): (string?, Diagnostics.Diagnostic?)
	if typeof(value) == "string" then
		return value :: string, nil
	end
	return nil, typeMismatch(path, "string", describeKind(value))
end

function JsonValue.AsNumber(value: JsonValue, path: string): (number?, Diagnostics.Diagnostic?)
	if typeof(value) == "number" then
		return value :: number, nil
	end
	return nil, typeMismatch(path, "number", describeKind(value))
end

function JsonValue.AsBoolean(value: JsonValue, path: string): (boolean?, Diagnostics.Diagnostic?)
	if typeof(value) == "boolean" then
		return value :: boolean, nil
	end
	return nil, typeMismatch(path, "boolean", describeKind(value))
end

return JsonValue
