--!strict

--[[
	Teste dedicado de `./DataStoreOptions.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Cobre o acceptance de task-services-018: "DataStoreOptions:SetExperimentalFeatures não
	erra".

	Roda com `lune run src/services/behavior/DataStoreOptions.spec.luau`.
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

-- Idempotente (guarda local em ../init.luau) -- seguro mesmo que outro spec do processo já tenha
-- chamado.
Services.Register()

test("Instance.new/Services.new('DataStoreOptions') funciona -- IsAbstract = false no dump", function()
	local options = Services.new("DataStoreOptions", nil)
	assert(options.ClassName == "DataStoreOptions", "ClassName deveria ser DataStoreOptions")
end)

test("DataStoreOptions.AllScopes é uma propriedade comum gravável, default false", function()
	local options = (Services.new("DataStoreOptions", nil) :: unknown) :: Dynamic

	-- Lido em variável antes de comparar (em vez de `options.AllScopes == false` inline): sem isso,
	-- `luau-lsp` estreita o TIPO de `options.AllScopes` para o singleton `false` a partir do
	-- primeiro `assert`, e a leitura seguinte (depois da reatribuição) vira `Type false cannot be
	-- compared with true` -- um falso-positivo de tooling sobre uma tabela `{ [string]: unknown }`
	-- dinâmica, não um erro de lógica.
	local beforeWrite: unknown = options.AllScopes
	assert(beforeWrite == false, "AllScopes deveria nascer false (Default do schema gerado)")

	options.AllScopes = true
	local afterWrite: unknown = options.AllScopes
	assert(afterWrite == true, "AllScopes deveria ser gravável -- ReadOnly = false no schema gerado")
end)

test("DataStoreOptions:SetExperimentalFeatures({v2 = true}) NÃO erra -- ProfileStore chama isto sempre", function()
	local options = (Services.new("DataStoreOptions", nil) :: unknown) :: Dynamic
	local setExperimentalFeatures = options.SetExperimentalFeatures :: (self: Dynamic, features: unknown) -> ()

	local ok = pcall(function()
		setExperimentalFeatures(options, { v2 = true })
	end)

	assert(ok, "SetExperimentalFeatures não deveria erro -- é aceito e ignorado de propósito (L2.1.3)")
end)

test("DataStoreOptions:SetExperimentalFeatures também não erra com argumento vazio/arbitrário -- é um no-op puro", function()
	local options = (Services.new("DataStoreOptions", nil) :: unknown) :: Dynamic
	local setExperimentalFeatures = options.SetExperimentalFeatures :: (self: Dynamic, features: unknown) -> ()

	local ok1 = pcall(function()
		setExperimentalFeatures(options, {})
	end)
	assert(ok1, "SetExperimentalFeatures({}) não deveria erro")

	local ok2 = pcall(function()
		setExperimentalFeatures(options, nil)
	end)
	assert(ok2, "SetExperimentalFeatures(nil) não deveria erro -- no-op puro, nenhuma validação de forma")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
