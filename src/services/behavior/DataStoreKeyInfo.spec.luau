--!strict

--[[
	Teste dedicado de `./DataStoreKeyInfo.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). `./GlobalDataStore.spec.luau` cobre o CONSUMO desta classe (via `GetAsync`/`SetAsync`/
	etc. devolvendo um `DataStoreKeyInfo` de verdade) -- este arquivo isola a fábrica `New` e os
	`Methods` em si, sem depender de `DataStoreService`/`Store`.

	`DataStoreKeyInfo` é `NotCreatable` no dump (`IsAbstract = true` -- ver
	`generated/classes/DataStoreKeyInfo.luau`) -- não existe via `Instance.new`/`Services.new`.
	Só nasce pela fábrica `New`, exportada por `./DataStoreKeyInfo.luau` ao lado de `Methods`.

	Roda com `lune run src/services/behavior/DataStoreKeyInfo.spec.luau`.
]]

local process = require("@lune/process")
local Services = require("../")
local Store = require("../datastore/Store")
local DataStoreKeyInfoBehavior = require("./DataStoreKeyInfo")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Idempotente -- precisa rodar antes de `New` abaixo: é o que registra a classe
-- `DataStoreKeyInfo` (com este `Behavior`, via `ClassBuilder.Build`) em `Runtime.ClassRegistry`.
Services.Register()

-- `metadata`/`userIds` omitidos (`nil`) usam um default não-vazio -- é o que os testes de
-- "roundtrip" (ler de volta o que foi passado a New) precisam; os testes de "GetMetadata/
-- GetUserIds devolvem {}" passam `{}`/`{}` explicitamente. Parâmetros tipados (em vez de uma
-- `overrides: { [string]: unknown }?` genérica) evitam a incompatibilidade de tipo que
-- `luau-lsp` acusa ao misturar `{ [string]: unknown }` com um literal de tabela sealed.
local function sampleVersionInfo(metadata: { [string]: unknown }?, userIds: { number }?): Store.VersionInfo
	return {
		Version = "test-version-1",
		CreatedTime = 1000,
		UpdatedTime = 2000,
		UserIds = if userIds ~= nil then userIds else { 111, 222 },
		Metadata = if metadata ~= nil then metadata else { origin = "test" },
		Tombstone = false,
	}
end

test("Types.Behavior exportado por DataStoreKeyInfo.luau tem Methods (GetMetadata/GetUserIds) e a fábrica New", function()
	assert(DataStoreKeyInfoBehavior.Methods ~= nil, "DataStoreKeyInfo.luau deveria exportar Methods")
	assert(DataStoreKeyInfoBehavior.New ~= nil, "DataStoreKeyInfo.luau deveria exportar a fábrica New (fora do contrato Types.Behavior)")
end)

test("New(versionInfo) cria uma Instance de ClassName DataStoreKeyInfo, com Parent nil", function()
	local instance = DataStoreKeyInfoBehavior.New(sampleVersionInfo())
	assert(instance.ClassName == "DataStoreKeyInfo", "ClassName deveria ser DataStoreKeyInfo")
	assert(instance.Parent == nil, "DataStoreKeyInfo nunca é filho de ninguém -- L2.0.3, chamador #3 de NewEngineInstance")
end)

test("CreatedTime/UpdatedTime/Version lêem o valor passado a New", function()
	local instance = (DataStoreKeyInfoBehavior.New(sampleVersionInfo()) :: unknown) :: Dynamic
	assert(instance.CreatedTime == 1000, `CreatedTime deveria ser 1000, foi {tostring(instance.CreatedTime)}`)
	assert(instance.UpdatedTime == 2000, `UpdatedTime deveria ser 2000, foi {tostring(instance.UpdatedTime)}`)
	assert(instance.Version == "test-version-1", `Version deveria ser "test-version-1", foi {tostring(instance.Version)}`)
end)

test("CreatedTime/UpdatedTime/Version são ReadOnly -- escrever erra 'Property is read only'", function()
	local instance = (DataStoreKeyInfoBehavior.New(sampleVersionInfo()) :: unknown) :: Dynamic

	local okCreated, errCreated = pcall(function()
		instance.CreatedTime = 9999
	end)
	assert(not okCreated, "escrever CreatedTime deveria erro -- ReadOnly = true no schema gerado")
	assert(
		string.find(tostring(errCreated), "Property is read only", 1, true) ~= nil,
		`mensagem deveria bater com a família ReadOnly confirmada, recebeu: {errCreated}`
	)

	local okVersion = pcall(function()
		instance.Version = "hacked"
	end)
	assert(not okVersion, "escrever Version deveria erro -- ReadOnly = true no schema gerado")
end)

test("GetMetadata()/GetUserIds() devolvem o que foi passado a New, deep-copiado", function()
	local versionInfo = sampleVersionInfo()
	local instance = (DataStoreKeyInfoBehavior.New(versionInfo) :: unknown) :: Dynamic

	local getMetadata = instance.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local getUserIds = instance.GetUserIds :: (self: Dynamic) -> { number }

	local metadata = getMetadata(instance)
	assert(metadata.origin == "test", "GetMetadata deveria devolver o Metadata passado a New")

	local userIds = getUserIds(instance)
	assert(#userIds == 2 and userIds[1] == 111 and userIds[2] == 222, "GetUserIds deveria devolver o UserIds passado a New")
end)

test("deep copy NA LEITURA: mutar o retorno de GetMetadata/GetUserIds não afeta o estado guardado", function()
	local instance = (DataStoreKeyInfoBehavior.New(sampleVersionInfo()) :: unknown) :: Dynamic
	local getMetadata = instance.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local getUserIds = instance.GetUserIds :: (self: Dynamic) -> { number }

	local metadata1 = getMetadata(instance)
	metadata1.origin = "MUTATED"
	local metadata2 = getMetadata(instance)
	assert(metadata2.origin == "test", `deep copy na leitura de GetMetadata quebrado, achou {tostring(metadata2.origin)}`)

	local userIds1 = getUserIds(instance)
	userIds1[1] = 999
	local userIds2 = getUserIds(instance)
	assert(userIds2[1] == 111, `deep copy na leitura de GetUserIds quebrado, achou {tostring(userIds2[1])}`)
end)

test("GetMetadata()/GetUserIds() devolvem {} quando Metadata/UserIds vieram vazios", function()
	local instance = (
		DataStoreKeyInfoBehavior.New(sampleVersionInfo({}, {})) :: unknown
	) :: Dynamic

	local getMetadata = instance.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local getUserIds = instance.GetUserIds :: (self: Dynamic) -> { number }

	assert(next(getMetadata(instance)) == nil, "GetMetadata deveria devolver tabela vazia")
	assert(#getUserIds(instance) == 0, "GetUserIds deveria devolver array vazio")
end)

test("duas instâncias de New(...) têm Metadata/UserIds independentes", function()
	local instance1 = (DataStoreKeyInfoBehavior.New(sampleVersionInfo({ onOne = true } :: { [string]: unknown }, nil)) :: unknown) :: Dynamic
	local instance2 = (DataStoreKeyInfoBehavior.New(sampleVersionInfo({}, nil)) :: unknown) :: Dynamic

	local getMetadata1 = instance1.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local metadata1 = getMetadata1(instance1)
	assert(metadata1.onOne == true, "instance1 deveria ver o próprio Metadata (onOne = true)")

	local getMetadata2 = instance2.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	assert(next(getMetadata2(instance2)) == nil, "instance2 nunca deveria ver o Metadata gravado em instance1 -- estado privado por instância")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
