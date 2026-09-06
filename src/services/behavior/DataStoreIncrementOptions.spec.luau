--!strict

--[[
	Teste dedicado de `./DataStoreIncrementOptions.luau` (regra 01: teste na mesma tarefa da lógica
	que cobre). Espelha `./DataStoreSetOptions.spec.luau` -- mesma superfície (`GetMetadata`/
	`SetMetadata`), classe DIFERENTE e INDEPENDENTE do dump (ver cabeçalho do próprio behavior).

	Roda com `lune run src/services/behavior/DataStoreIncrementOptions.spec.luau`.
]]

local process = require("@lune/process")
local Services = require("../")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

Services.Register()

local function newOptions(): Dynamic
	return (Services.new("DataStoreIncrementOptions", nil) :: unknown) :: Dynamic
end

test("Instance.new/Services.new('DataStoreIncrementOptions') funciona -- IsAbstract = false no dump", function()
	local options = newOptions()
	assert(options.ClassName == "DataStoreIncrementOptions", "ClassName deveria ser DataStoreIncrementOptions")
end)

test("GetMetadata() sem SetMetadata prévio devolve {} (nunca nil)", function()
	local options = newOptions()
	local getMetadata = options.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	local metadata = getMetadata(options)
	assert(metadata ~= nil, "GetMetadata nunca deveria devolver nil")
	assert(next(metadata) == nil, "GetMetadata deveria devolver tabela vazia quando SetMetadata nunca foi chamado")
end)

test("SetMetadata + GetMetadata: roundtrip básico", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadata = options.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	setMetadata(options, { reason = "increment" })
	local metadata = getMetadata(options)

	assert(metadata.reason == "increment", "metadata.reason deveria ter sido preservado")
end)

test("deep copy NA ESCRITA e NA LEITURA -- mesma disciplina de DataStoreSetOptions", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadata = options.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	local original = { value = 1 }
	setMetadata(options, original)
	original.value = 999

	local firstRead = getMetadata(options)
	assert(firstRead.value == 1, `deep copy na escrita quebrado -- esperava 1, achou {tostring(firstRead.value)}`)

	firstRead.value = 42
	local secondRead = getMetadata(options)
	assert(secondRead.value == 1, `deep copy na leitura quebrado -- esperava 1, achou {tostring(secondRead.value)}`)
end)

test("SetMetadata(valor que não é tabela) erra -- família Roblox de argumento nativo", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()

	local ok, err = pcall(function()
		setMetadata(options, 123)
	end)

	assert(not ok, "SetMetadata com argumento não-tabela deveria erro")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria citar o tipo esperado, recebeu: {err}`
	)
end)

test("'_LuauBenchMetadata' reutilizado por DataStoreSetOptions.luau não colide entre as duas classes", function()
	local incrementOptions = newOptions()
	local setOptions = (Services.new("DataStoreSetOptions", nil) :: unknown) :: Dynamic

	local setMetadataOnIncrement = incrementOptions.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadataOnSet = setOptions.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	setMetadataOnIncrement(incrementOptions, { onlyOnIncrementOptions = true })
	local metadataOnSet = getMetadataOnSet(setOptions)

	assert(
		next(metadataOnSet) == nil,
		"uma DataStoreSetOptions separada nunca deveria ver o metadata gravado numa DataStoreIncrementOptions -- estado privado por INSTÂNCIA, chave reutilizada com segurança entre classes"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
