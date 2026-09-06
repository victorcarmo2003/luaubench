--!strict

--[[
	Teste dedicado de `./DataStoreSetOptions.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). O acceptance de task-services-018 cobre isto indiretamente ("deep copy verificada de
	ponta a ponta"); `./GlobalDataStore.spec.luau` cobre o CONSUMO desta classe via `SetAsync`
	(propagação de metadata até `DataStoreKeyInfo:GetMetadata()`) -- este arquivo isola a classe em
	si, sem depender de `DataStoreService`.

	Roda com `lune run src/services/behavior/DataStoreSetOptions.spec.luau`.
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
	return (Services.new("DataStoreSetOptions", nil) :: unknown) :: Dynamic
end

test("Instance.new/Services.new('DataStoreSetOptions') funciona -- IsAbstract = false no dump", function()
	local options = newOptions()
	assert(options.ClassName == "DataStoreSetOptions", "ClassName deveria ser DataStoreSetOptions")
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

	setMetadata(options, { origin = "test", count = 3 })
	local metadata = getMetadata(options)

	assert(metadata.origin == "test", "metadata.origin deveria ter sido preservado")
	assert(metadata.count == 3, "metadata.count deveria ter sido preservado")
end)

test("deep copy NA ESCRITA: mutar a tabela original depois de SetMetadata não afeta o valor guardado", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadata = options.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	local original = { value = 1 }
	setMetadata(options, original)
	original.value = 999

	local metadata = getMetadata(options)
	assert(metadata.value == 1, `deep copy na escrita quebrado -- esperava 1, achou {tostring(metadata.value)}`)
end)

test("deep copy NA LEITURA: mutar o retorno de GetMetadata não afeta o valor guardado", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadata = options.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	setMetadata(options, { value = 1 })
	local firstRead = getMetadata(options)
	firstRead.value = 999

	local secondRead = getMetadata(options)
	assert(secondRead.value == 1, `deep copy na leitura quebrado -- esperava 1, achou {tostring(secondRead.value)}`)
end)

test("SetMetadata(valor que não é tabela) erra -- família Roblox de argumento nativo", function()
	local options = newOptions()
	local setMetadata = options.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()

	local ok, err = pcall(function()
		setMetadata(options, "not a table")
	end)

	assert(not ok, "SetMetadata com argumento não-tabela deveria erro")
	assert(
		string.find(tostring(err), "table expected", 1, true) ~= nil,
		`mensagem deveria citar o tipo esperado, recebeu: {err}`
	)
end)

test("duas instâncias de DataStoreSetOptions têm metadata independente", function()
	local options1 = newOptions()
	local options2 = newOptions()
	local setMetadata1 = options1.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	local getMetadata2 = options2.GetMetadata :: (self: Dynamic) -> { [string]: unknown }

	setMetadata1(options1, { onlyOnOptions1 = true })
	local metadata2 = getMetadata2(options2)

	assert(next(metadata2) == nil, "options2 nunca deveria ver metadata gravado em options1 -- estado privado por instância")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
