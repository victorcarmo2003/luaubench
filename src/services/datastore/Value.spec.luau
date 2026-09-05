--!strict

--[[
	Teste dedicado de `./Value.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o acceptance de task-services-017: "Value.luau recusa os 6 tipos não serializáveis e os
	3 limites de tamanho com erro nomeado" + "cópia profunda verificada (mutar o retorno não afeta
	o store, e vice-versa)".

	Roda SEM `Services.Bootstrap`/`Runtime` -- `Value.luau` não conhece Instance (ver cabeçalho do
	módulo). Roda com `lune run src/services/datastore/Value.spec.luau`.
]]

local process = require("@lune/process")
local Value = require("./Value")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- `table.pack(pcall(fn))` em vez de `local ok, err = pcall(fn)`: com `fn: () -> ()` (retorno
-- vazio), o Luau tipa `pcall(fn)` como devolvendo só 1 valor (o booleano) -- a mensagem de erro
-- do 2º retorno só existe em tempo de EXECUÇÃO no caminho de falha, não no tipo estático da
-- função de sucesso. `table.pack` sobre o pack variádico contorna isso sem precisar de `any`.
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

-- ================= Limite de nome (key/name/scope <= 50 caracteres) =================

test("CheckNameLength aceita exatamente 50 caracteres (limite inclusivo)", function()
	local exactly50 = string.rep("a", 50)
	assert(Value.CheckNameLength(exactly50, "key"), "50 caracteres deveria ser aceito (limite <=)")
end)

test("CheckNameLength rejeita 51 caracteres", function()
	local exactly51 = string.rep("a", 51)
	assert(not Value.CheckNameLength(exactly51, "key"), "51 caracteres deveria ser rejeitado")
end)

test("AssertNameLength (kind='key') erra citando 'DataStore key' e o tamanho recebido", function()
	local tooLong = string.rep("k", 51)
	expectErrorContaining(function()
		Value.AssertNameLength(tooLong, "key")
	end, "DataStore key", "AssertNameLength key")
	expectErrorContaining(function()
		Value.AssertNameLength(tooLong, "key")
	end, "50", "AssertNameLength key (limite)")
end)

test("AssertNameLength (kind='name') erra citando 'DataStore name'", function()
	expectErrorContaining(function()
		Value.AssertNameLength(string.rep("n", 51), "name")
	end, "DataStore name", "AssertNameLength name")
end)

test("AssertNameLength (kind='scope') erra citando 'DataStore scope'", function()
	expectErrorContaining(function()
		Value.AssertNameLength(string.rep("s", 51), "scope")
	end, "DataStore scope", "AssertNameLength scope")
end)

test("AssertNameLength não erra para nome dentro do limite", function()
	Value.AssertNameLength("chave-normal", "key")
	Value.AssertNameLength("PlayerData", "name")
	Value.AssertNameLength("global", "scope")
end)

-- ================= Serializabilidade: os 6 tipos da doc oficial =================

test("CheckSerializable aceita nil/boolean/number/string", function()
	assert(Value.CheckSerializable(nil) == nil, "nil deveria ser serializável")
	assert(Value.CheckSerializable(true) == nil, "boolean deveria ser serializável")
	assert(Value.CheckSerializable(42) == nil, "number deveria ser serializável")
	assert(Value.CheckSerializable("texto") == nil, "string deveria ser serializável")
end)

test("CheckSerializable aceita tabela dicionário (só chaves string) e tabela array (só chaves number)", function()
	assert(Value.CheckSerializable({ Foo = 1, Bar = "x" }) == nil, "dicionário puro deveria ser serializável")
	assert(Value.CheckSerializable({ 1, 2, 3 }) == nil, "array puro deveria ser serializável")

	-- Elementos de tipo misto (`number`/tabela) numa lista de literal: anotado explicitamente
	-- como `{ unknown }` para o Luau não tentar unificar o array como homogêneo (`{number}`) e
	-- rejeitar o 3º elemento -- questão de inferência de tipo do TESTE, não de `Value.luau`.
	local deepItem: { [string]: unknown } = { Deep = true }
	local mixedArray: { unknown } = { 1, 2, deepItem }
	local nested: { [string]: unknown } = { Nested = mixedArray }
	assert(Value.CheckSerializable(nested) == nil, "aninhamento válido deveria ser serializável")
end)

test("CheckSerializable rejeita tabela com chave mista (string + number)", function()
	local mixed: { [unknown]: unknown } = { Foo = 1 }
	mixed[1] = "bar"
	local failure = Value.CheckSerializable(mixed)
	assert(failure ~= nil, "tabela com chave mista deveria ser rejeitada")
	assert((failure :: Value.SerializabilityFailure).Kind == "MixedKeyTable", `Kind deveria ser MixedKeyTable, recebeu {tostring((failure :: Value.SerializabilityFailure).Kind)}`)
end)

test("CheckSerializable rejeita função", function()
	local failure = Value.CheckSerializable(function() end)
	assert(failure ~= nil and failure.Kind == "Function", "função deveria ser rejeitada com Kind=Function")
end)

test("CheckSerializable rejeita thread", function()
	local failure = Value.CheckSerializable(coroutine.create(function() end))
	assert(failure ~= nil and failure.Kind == "Thread", "thread deveria ser rejeitada com Kind=Thread")
end)

test("CheckSerializable rejeita userdata (cobre Instance -- ver cabeçalho do módulo)", function()
	local proxy = newproxy(false)
	local failure = Value.CheckSerializable(proxy)
	assert(failure ~= nil and failure.Kind == "Userdata", "userdata deveria ser rejeitado com Kind=Userdata")
end)

-- CORREÇÃO 2026-09-05 (task-services-028, pesquisa-services-leva2-pendencias-2026-09-05.md, item
-- 2): a doc oficial de Open Cloud confirma que a Engine API real (SetAsync/UpdateAsync chamados
-- de DENTRO do jogo -- o caso do LuauBench) ACEITA NaN/inf/-inf sem erro; só o Open Cloud (API
-- HTTP externa) precisaria de uma representação JSON especial. `Value.luau` NÃO rejeita mais
-- esses valores -- ver cabeçalho do módulo, "CORREÇÃO 2026-09-05".
test("CheckSerializable ACEITA NaN/inf/-inf (Engine API real aceita -- só Open Cloud precisaria de repr. especial)", function()
	assert(Value.CheckSerializable(0 / 0) == nil, "NaN deveria ser aceito (não é mais rejeitado)")
	assert(Value.CheckSerializable(math.huge) == nil, "+inf deveria ser aceito (não é mais rejeitado)")
	assert(Value.CheckSerializable(-math.huge) == nil, "-inf deveria ser aceito (não é mais rejeitado)")
end)

test("Value.Validate não erra para um valor contendo NaN/inf aninhado", function()
	Value.Validate({ Ratio = 0 / 0, Speed = math.huge, Drag = -math.huge })
end)

test("CheckSerializable detecta o problema DENTRO de uma tabela aninhada e reporta o Path", function()
	local nested = { Inventory = { { Owner = function() end } } }
	local failure = Value.CheckSerializable(nested)
	assert(failure ~= nil and failure.Kind == "Function", "função aninhada deveria ser detectada")
	assert(
		string.find((failure :: Value.SerializabilityFailure).Path, "Inventory", 1, true) ~= nil,
		`Path deveria citar 'Inventory', recebeu: {(failure :: Value.SerializabilityFailure).Path}`
	)
end)

test("CheckSerializable rejeita referência cíclica sem estourar a pilha", function()
	local cyclic: { [string]: unknown } = {}
	cyclic.Self = cyclic
	local failure = Value.CheckSerializable(cyclic)
	assert(failure ~= nil and failure.Kind == "CyclicReference", "tabela cíclica deveria ser rejeitada com Kind=CyclicReference")
end)

test("AssertSerializable erra com mensagem legível para cada uma das 4 categorias recusadas (com erro NOMEADO)", function()
	expectErrorContaining(function()
		Value.AssertSerializable(function() end)
	end, "function", "AssertSerializable função")
	expectErrorContaining(function()
		Value.AssertSerializable(coroutine.create(function() end))
	end, "thread", "AssertSerializable thread")
	expectErrorContaining(function()
		Value.AssertSerializable(newproxy(false))
	end, "Instance", "AssertSerializable userdata/Instance")
	local mixed: { [unknown]: unknown } = { Foo = 1 }
	mixed[1] = "bar"
	expectErrorContaining(function()
		Value.AssertSerializable(mixed)
	end, "mixed", "AssertSerializable chave mista")
end)

test("AssertSerializable NÃO erra para NaN/inf/-inf (correção 2026-09-05)", function()
	Value.AssertSerializable(0 / 0)
	Value.AssertSerializable(math.huge)
	Value.AssertSerializable(-math.huge)
end)

test("AssertSerializable não erra para valor válido", function()
	Value.AssertSerializable({ Coins = 100, Inventory = { "Sword", "Shield" } })
end)

-- ================= Limite de tamanho do valor (<= 4194304 bytes) =================

test("EstimateByteSize é determinístico para o mesmo valor estrutural", function()
	local a = Value.EstimateByteSize({ Foo = "bar", Count = 3 })
	local b = Value.EstimateByteSize({ Count = 3, Foo = "bar" })
	assert(a == b, `EstimateByteSize deveria ser determinístico independente da ordem de inserção -- recebeu {a} e {b}`)
end)

test("EstimateByteSize cresce com o tamanho do valor", function()
	local small = Value.EstimateByteSize("x")
	local big = Value.EstimateByteSize(string.rep("x", 1000))
	assert(big > small, "string maior deveria estimar mais bytes")
end)

test("AssertByteSize não erra para valor pequeno", function()
	Value.AssertByteSize({ Coins = 100 })
end)

test("AssertByteSize erra (com o limite nomeado, 4194304) para valor maior que 4 MiB", function()
	local huge = { Blob = string.rep("x", 4194304 + 100) }
	expectErrorContaining(function()
		Value.AssertByteSize(huge)
	end, "4194304", "AssertByteSize valor grande demais")
end)

test("Value.Validate combina serializabilidade + tamanho, na ordem certa (serializabilidade primeiro)", function()
	-- Um valor NÃO serializável E grande demais deveria errar pela serializabilidade primeiro
	-- (dizer O QUE está errado antes de quanto ele pesa).
	local invalidAndHuge = { Blob = string.rep("x", 4194304 + 100), Bad = function() end }
	expectErrorContaining(function()
		Value.Validate(invalidAndHuge)
	end, "function", "Validate prioriza serializabilidade sobre tamanho")

	Value.Validate({ Coins = 100 }) -- não deveria errar para valor válido e pequeno
end)

-- ================= Deep copy =================

test("DeepCopy: mutar a CÓPIA não afeta o ORIGINAL", function()
	local original = { Coins = 100, Inventory = { "Sword" } }
	local copy = Value.DeepCopy(original)

	copy.Coins = 999
	table.insert(copy.Inventory, "Shield")

	assert(original.Coins == 100, "mutar a cópia não deveria afetar Coins do original")
	assert(#original.Inventory == 1, "mutar a cópia não deveria afetar o array do original")
end)

test("DeepCopy: mutar o ORIGINAL depois da cópia não afeta a CÓPIA (o caso que importa para Set/leitura)", function()
	local original = { Coins = 100, Inventory = { "Sword" } }
	local copy = Value.DeepCopy(original)

	original.Coins = 1
	table.insert(original.Inventory, "Shield")

	assert(copy.Coins == 100, "mutar o original depois do DeepCopy não deveria afetar a cópia")
	assert(#copy.Inventory == 1, "mutar o original depois do DeepCopy não deveria afetar o array copiado")
end)

test("DeepCopy preserva valores primitivos e estrutura aninhada", function()
	local original = { A = 1, B = "x", C = true, D = { E = { F = 42 } } }
	local copy = Value.DeepCopy(original)
	assert(copy.A == 1 and copy.B == "x" and copy.C == true, "primitivos deveriam ser preservados")
	assert(copy.D.E.F == 42, "aninhamento profundo deveria ser preservado")
	assert(copy.D ~= original.D, "a tabela aninhada copiada deveria ser uma tabela NOVA, não a mesma referência")
end)

test("DeepCopy não estoura a pilha em referência cíclica (defesa, mesmo não sendo caminho esperado)", function()
	local cyclic: { [string]: unknown } = {}
	cyclic.Self = cyclic
	local copy = Value.DeepCopy(cyclic)
	assert(copy.Self == copy, "a referência cíclica deveria apontar para a PRÓPRIA cópia, não para o original")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
