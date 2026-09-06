--!strict

--[[
	Teste dedicado de `./Snapshot.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o acceptance de task-services-029:

		"INVARIANTE CENTRAL, property test: para todo v com Value.CheckSerializable(v) == nil,
		DeepEqual(Decode(decode_json(encode_json(Encode(v)))), v). Gerador cobrindo as 8 linhas da
		tabela do desenho MAIS os 5 casos hostis medidos (NaN, inf, -inf, array esparso,
		{[2]='a'}, {[-1]='a'}, {[1.5]='a'}, string com byte 0xFF, dicionário contendo a chave
		'$'). Documento com SchemaVersion maior que o suportado erra com mensagem nomeando
		encontrada vs suportada. JSON inválido erra claro."

	Roda SEM `Services.Bootstrap`/`Runtime` -- `Snapshot.luau` não conhece Instance (ver cabeçalho
	do módulo). Roda com `lune run src/services/datastore/Snapshot.spec.luau`.
]]

local process = require("@lune/process")
local serde = require("@lune/serde")
local Snapshot = require("./Snapshot")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Mesmo padrão de `./Value.spec.luau`/`./Store.spec.luau` (`expectErrorContaining`).
local function expectErrorContaining(fn: () -> (), fragment: string, context: string): ()
	local results = table.pack(pcall(fn))
	local ok = results[1] :: boolean
	assert(not ok, `{context}: esperava erro, mas completou sem erro`)
	local message = tostring(results[2])
	assert(
		string.find(message, fragment, 1, true) ~= nil,
		`{context}: mensagem deveria conter "{fragment}", recebeu: {message}`
	)
end

-- `DeepEqual` genérico para o property test. NaN ~= NaN por IEEE754 (`0/0 == 0/0` é `false`) --
-- mas o round-trip do envelope PRECISA reconhecer "os dois lados são NaN" como sucesso
-- (`Value.CheckSerializable` aceita NaN como valor válido, ver `./Value.luau`); tratado como caso
-- especial abaixo, não é uma noção inventada de igualdade -- é a MESMA noção que `Store.spec.luau`
-- precisaria para comparar valores de DataStore contendo NaN.
local function deepEqual(a: unknown, b: unknown): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end

	local ta = type(a)
	local tb = type(b)
	if ta ~= tb then
		return false
	end

	if ta == "number" then
		local an = a :: number
		local bn = b :: number
		if an ~= an and bn ~= bn then
			-- Ambos NaN.
			return true
		end
		return an == bn
	end

	if ta == "boolean" then
		return (a :: boolean) == (b :: boolean)
	end

	if ta == "string" then
		return (a :: string) == (b :: string)
	end

	if ta == "table" then
		local at = a :: { [unknown]: unknown }
		local bt = b :: { [unknown]: unknown }

		local countA = 0
		for _ in at do
			countA += 1
		end
		local countB = 0
		for _ in bt do
			countB += 1
		end
		if countA ~= countB then
			return false
		end

		for key, value in at do
			if not deepEqual(value, bt[key]) then
				return false
			end
		end
		return true
	end

	-- Fora do domínio de `Value.CheckSerializable` (function/thread/userdata) -- nunca alcançado
	-- pelos casos deste spec; comparação por referência como fallback honesto.
	return a == b
end

-- ================================================================================================
-- Gerador: as 8 linhas da tabela do desenho (seção 4) + os casos hostis nomeados no acceptance
-- (NaN, inf, -inf, array esparso, {[2]='a'}, {[-1]='a'}, {[1.5]='a'}, string com byte 0xFF,
-- dicionário contendo a chave '$').
-- ================================================================================================

type Case = { Name: string, Value: unknown }

local cases: { Case } = {}
local function addCase(name: string, value: unknown)
	table.insert(cases, { Name = name, Value = value })
end

-- `nil` no valor de topo -- `Value.CheckSerializable(nil) == nil` (ver `./Value.spec.luau`).
addCase("nil (valor de topo)", nil)

-- Linha 1: boolean.
addCase("boolean true", true)
addCase("boolean false", false)

-- Linha 2: number finito.
addCase("number finito positivo", 42)
addCase("number finito negativo/fracionário", -3.5)
addCase("number finito zero", 0)
addCase("number finito grande (1234567890123)", 1234567890123)

-- Linha 3 + caso hostil (NaN/inf/-inf viram `null` sem erro no serde cru).
addCase("number NaN (hostil)", 0 / 0)
addCase("number +inf (hostil)", math.huge)
addCase("number -inf (hostil)", -math.huge)

-- Linha 4: string UTF-8 válida.
addCase("string UTF-8 válida", "hello, café")
addCase("string vazia", "")

-- Linha 5 + caso hostil (byte inválido erra no serde.encode cru).
local invalidUtf8 = string.char(0xFF)
addCase("string com byte 0xFF inválido (hostil)", invalidUtf8)

-- Linha 6: table densa 1..n.
addCase("table vazia (convenção: array vazio)", {})
addCase("table array densa (1..n)", { 1, 2, 3 })

-- Anotado `{ unknown }` (mesmo padrão de `./Value.spec.luau`, "mixedArray"): sem isso o Luau
-- infere o tipo do array a partir do 1º elemento (`{number}`) e rejeita os seguintes.
local mixedArray: { unknown } = { 1, "two", true }
addCase("table array com valores mistos", mixedArray)

-- Idem: sem a anotação, o Luau infere `{A: number}` do 1º elemento e rejeita `{B = 2}`.
local nestedArray: { unknown } = { { A = 1 }, { B = 2 } }
addCase("table aninhada (array de dicionários)", nestedArray)

-- Linha 7: table só chaves string, sem "$".
addCase("table dicionário (só chaves string, sem '$')", { Coins = 100, Name = "x" })

-- Linha 8 + casos hostis (numérica esparsa/negativa/fracionária, dicionário com "$").
local sparse: { [unknown]: unknown } = {}
sparse[1] = "a"
sparse[3] = "c"
addCase("table numérica esparsa {[1]='a',[3]='c'} (hostil)", sparse)

local notStartingAtOne: { [unknown]: unknown } = {}
notStartingAtOne[2] = "a"
addCase("table {[2]='a'} (hostil)", notStartingAtOne)

local negativeKey: { [unknown]: unknown } = {}
negativeKey[-1] = "a"
addCase("table {[-1]='a'} (hostil)", negativeKey)

local fractionalKey: { [unknown]: unknown } = {}
fractionalKey[1.5] = "a"
addCase("table {[1.5]='a'} (hostil)", fractionalKey)

addCase("dicionário contendo a chave '$' (hostil)", { ["$"] = "not-a-tag", Other = 1 })

-- Combinação realista: valor não-finito ANINHADO dentro de um dicionário (o caso que
-- `Value.spec.luau` também cobre para `Value.Validate`).
addCase("table com valores não-finitos aninhados", { Ratio = 0 / 0, Speed = math.huge, Drag = -math.huge })

-- ================================================================================================
-- INVARIANTE CENTRAL (acceptance da task): para todo `v` da lista acima,
-- DeepEqual(Decode(decode_json(encode_json(Encode(v)))), v).
-- ================================================================================================

for _, case in cases do
	test(`round-trip via JSON: {case.Name}`, function()
		local encoded = Snapshot.Encode(case.Value)

		-- `encode_json`/`decode_json`: aplicados DIRETO via `serde` (não os wrappers de
		-- conveniência de `Snapshot`) para isolar a invariante no formato ENCODE/DECODE puro,
		-- separado da conveniência JSON (testada à parte, abaixo).
		local json = serde.encode("json", encoded)
		local decodedJson = serde.decode("json", json)

		local decoded = Snapshot.Decode(decodedJson :: Snapshot.EncodedValue)

		assert(deepEqual(decoded, case.Value), `round-trip falhou para "{case.Name}"`)
	end)
end

-- ================================================================================================
-- Conveniência JSON (`EncodeToJson`/`DecodeFromJson`) -- mesmo round-trip, API combinada.
-- ================================================================================================

test("EncodeToJson/DecodeFromJson fazem o mesmo round-trip que Encode/Decode manual", function()
	local value = { Coins = 100, Ratio = 0 / 0, Bad = string.char(0xFF), Items = { 1, 2, 3 } }
	local json = Snapshot.EncodeToJson(value)
	local decoded = Snapshot.DecodeFromJson(json)
	assert(deepEqual(decoded, value), "EncodeToJson/DecodeFromJson deveria fazer round-trip idêntico")
end)

test("EncodeToJson produz uma string JSON válida (parseável por serde.decode diretamente)", function()
	local json = Snapshot.EncodeToJson({ Foo = "bar" })
	local decoded = serde.decode("json", json)
	assert(type(decoded) == "table", "JSON produzido deveria decodificar para uma tabela")
end)

-- ================================================================================================
-- Documento de topo (seção 3 do desenho).
-- ================================================================================================

test("EncodeDocument/DecodeDocument fazem round-trip do documento inteiro (Stores aninhado, com valor não-finito)", function()
	-- Anotado `{ [string]: unknown }` (o tipo que `Snapshot.EncodeDocument` espera): sem isso o
	-- Luau infere um tipo exato (`{| PlayerDataglobal: {| ... |} |}`) mais estreito que o
	-- parâmetro, e rejeita a chamada.
	local stores: { [string]: unknown } = {
		PlayerDataglobal = {
			Name = "PlayerData",
			Scope = "global",
			Keys = {
				Player_123 = {
					CreatedTime = 1757164700000,
					Versions = {
						{
							Version = "1757164700000-0000000001",
							UpdatedTime = 1757164700000,
							UserIds = { 123 },
							Metadata = {},
							Tombstone = false,
							Value = { Coins = 100, Ratio = 0 / 0, Inventory = { "sword" } },
						},
					},
				},
			},
		},
	}

	local json = Snapshot.EncodeDocument(stores, 1757164800123)
	local doc = Snapshot.DecodeDocument(json)

	assert(doc.SchemaVersion == Snapshot.CurrentSchemaVersion, "SchemaVersion deveria bater com o atual")
	assert(doc.Kind == Snapshot.DocumentKind, "Kind deveria bater com o documento de DataStore")
	assert(doc.SavedAt == 1757164800123, "SavedAt deveria ser preservado")
	assert(deepEqual(doc.Stores, stores), "Stores deveria fazer round-trip idêntico (inclusive o Ratio=NaN aninhado)")
end)

test("EncodeDocument produz JSON pretty-printed (legível/diffável, seção 3 do desenho)", function()
	local json = Snapshot.EncodeDocument({}, 0)
	assert(string.find(json, "\n", 1, true) ~= nil, "documento deveria ser pretty-printed (multilinha)")
end)

test("DecodeDocument aceita SchemaVersion igual ao suportado sem erro", function()
	local json = serde.encode("json", {
		SchemaVersion = Snapshot.CurrentSchemaVersion,
		Kind = Snapshot.DocumentKind,
		SavedAt = 0,
		Stores = {},
	})
	local doc = Snapshot.DecodeDocument(json)
	assert(doc.SchemaVersion == Snapshot.CurrentSchemaVersion, "SchemaVersion no limite deveria ser aceito")
end)

test("DecodeDocument RECUSA SchemaVersion maior que o suportado, nomeando ENCONTRADA e SUPORTADA (acceptance da task)", function()
	local futureVersion = Snapshot.CurrentSchemaVersion + 1
	local futureDoc = serde.encode("json", {
		SchemaVersion = futureVersion,
		Kind = Snapshot.DocumentKind,
		SavedAt = 0,
		Stores = {},
	})
	expectErrorContaining(function()
		Snapshot.DecodeDocument(futureDoc)
	end, tostring(futureVersion), "DecodeDocument SchemaVersion desconhecido (deveria nomear a versão ENCONTRADA)")
	expectErrorContaining(function()
		Snapshot.DecodeDocument(futureDoc)
	end, tostring(Snapshot.CurrentSchemaVersion), "DecodeDocument SchemaVersion desconhecido (deveria nomear a versão SUPORTADA)")
end)

test("DecodeDocument erra claro para JSON inválido (acceptance da task)", function()
	expectErrorContaining(function()
		Snapshot.DecodeDocument("{ this is not valid json")
	end, "invalid JSON", "DecodeDocument JSON malformado")
end)

test("DecodeDocument erra claro quando o campo SchemaVersion está ausente", function()
	expectErrorContaining(function()
		Snapshot.DecodeDocument(serde.encode("json", { Foo = "bar" }))
	end, "SchemaVersion", "DecodeDocument campo SchemaVersion ausente")
end)

test("DecodeDocument erra claro quando o campo Stores está ausente", function()
	expectErrorContaining(function()
		Snapshot.DecodeDocument(serde.encode("json", {
			SchemaVersion = Snapshot.CurrentSchemaVersion,
			Kind = Snapshot.DocumentKind,
			SavedAt = 0,
		}))
	end, "Stores", "DecodeDocument campo Stores ausente")
end)

test("DecodeDocument erra claro quando o topo não é um objeto JSON", function()
	expectErrorContaining(function()
		Snapshot.DecodeDocument(serde.encode("json", { 1, 2, 3 }))
	end, "malformed document", "DecodeDocument topo não é objeto")
end)

-- ================================================================================================
-- JSON inválido (valor solto) -- acceptance da task.
-- ================================================================================================

test("DecodeFromJson erra claro para JSON inválido (acceptance da task)", function()
	expectErrorContaining(function()
		Snapshot.DecodeFromJson("{ not valid json at all")
	end, "invalid JSON", "DecodeFromJson JSON malformado")
end)

-- ================================================================================================
-- Defesa: `Encode` fora do domínio (não é caminho esperado, mas nunca deveria corromper
-- silenciosamente -- regra 01).
-- ================================================================================================

test("Snapshot.Encode erra com clareza para tipo fora do domínio de Value.CheckSerializable (function)", function()
	expectErrorContaining(function()
		Snapshot.Encode(function() end)
	end, "unsupported Luau type", "Encode tipo não suportado (function)")
end)

test("Snapshot.Encode erra com clareza para tipo fora do domínio de Value.CheckSerializable (thread)", function()
	expectErrorContaining(function()
		Snapshot.Encode(coroutine.create(function() end))
	end, "unsupported Luau type", "Encode tipo não suportado (thread)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
