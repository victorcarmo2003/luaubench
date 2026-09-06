--!strict

--[[
	Teste dedicado de `./DataStore.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o acceptance de task-services-019: `GetVersionAsync` (versão existente e inexistente),
	`ListVersionsAsync` (paginação completa via `Pages`, `sortDirection` omitido usa Ascending,
	`sortDirection` presente erra citando a lacuna), `ListKeysAsync` (paginação, prefixo filtrando
	corretamente, `excludeDeleted` junto com tombstone), e o fluxo
	`GetCurrentPage`/`IsFinished`/`AdvanceToNextPageAsync` completo -- exatamente o uso real de
	`ProfileVersionQuery` (ProfileStore) descrito em pesquisa-datastore-2026-09-05.md, seção C.

	Todo método `*Async` (incluindo `AdvanceToNextPageAsync`, herdado de `Pages`) passa por
	`../AsyncCall.luau` -- mesmo padrão de `GlobalDataStore.spec.luau`: `scheduler:Spawn(...)`
	seguido de `scheduler:StepOnce(0)`.

	`store` (o dado de verdade, em `./GlobalDataStore.luau`) é MÓDULO-LOCAL, compartilhado com
	`GetDataStore`/`SetAsync`/etc -- por isso cada teste usa um NOME de DataStore (ou uma CHAVE)
	exclusivo, mesma disciplina de `GlobalDataStore.spec.luau`.

	Roda com `lune run src/services/behavior/DataStore.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
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

local scheduler = Runtime.Scheduler.new()
local game = Runtime.DataModel.new()
Services.Bootstrap({ scheduler = scheduler, dataModel = game })
local dataStoreService = (game:GetService("DataStoreService") :: unknown) :: Dynamic
local getDataStore = dataStoreService.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

-- Chama `body` dentro de uma thread gerida pelo Scheduler e avança exatamente um passo -- basta
-- para o único `AsyncCall.Yield` que cada método `*Async` faz (`Wait(0)`).
local function runAsync(body: () -> ()): ()
	scheduler:Spawn(body)
	scheduler:StepOnce(0)
end

-- ================= GetVersionAsync =================

test("GetVersionAsync com uma versão que EXISTE devolve (valorNaquelaVersao, keyInfo)", function()
	local store = getDataStore(dataStoreService, "Spec19-GetVersion", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getVersionAsync = store.GetVersionAsync :: (self: Dynamic, key: string, version: string) -> ...unknown

	local version: string
	runAsync(function()
		version = setAsync(store, "K1", { count = 1 }, nil, nil)
	end)

	local value: unknown, keyInfo: unknown
	runAsync(function()
		value, keyInfo = getVersionAsync(store, "K1", version)
	end)

	assert((value :: { count: number }).count == 1, "GetVersionAsync deveria devolver o valor daquela versão")
	assert(keyInfo ~= nil, "GetVersionAsync deveria devolver um keyInfo não-nil para uma versão existente")
	local keyInfoDynamic = keyInfo :: Dynamic
	assert(keyInfoDynamic.Version == version, "keyInfo.Version deveria bater com a versão pedida")
end)

test("GetVersionAsync com uma versão INEXISTENTE devolve (nil, nil)", function()
	local store = getDataStore(dataStoreService, "Spec20-GetVersion", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getVersionAsync = store.GetVersionAsync :: (self: Dynamic, key: string, version: string) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", { count = 1 }, nil, nil)
	end)

	local value: unknown = "not yet set"
	local keyInfo: unknown = "not yet set"
	runAsync(function()
		value, keyInfo = getVersionAsync(store, "K1", "versao-que-nunca-existiu")
	end)

	assert(value == nil, "GetVersionAsync com versão inexistente deveria devolver value nil")
	assert(keyInfo == nil, "GetVersionAsync com versão inexistente deveria devolver keyInfo nil")
end)

test("GetVersionAsync: a versão ANTERIOR a um RemoveAsync continua legível (histórico/tombstone, L2.1.3)", function()
	local store = getDataStore(dataStoreService, "Spec21-GetVersion", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local removeAsync = store.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown
	local getVersionAsync = store.GetVersionAsync :: (self: Dynamic, key: string, version: string) -> ...unknown

	local versionBeforeRemove: string
	runAsync(function()
		versionBeforeRemove = setAsync(store, "K1", { count = 42 }, nil, nil)
	end)
	runAsync(function()
		removeAsync(store, "K1")
	end)

	local value: unknown
	runAsync(function()
		value = getVersionAsync(store, "K1", versionBeforeRemove)
	end)
	assert((value :: { count: number }).count == 42, "a versão anterior ao RemoveAsync deveria continuar legível por GetVersionAsync")
end)

-- ================= ListVersionsAsync =================

test("ListVersionsAsync devolve uma DataStoreVersionPages navegável -- GetCurrentPage/IsFinished/AdvanceToNextPageAsync, exatamente como ProfileVersionQuery usa", function()
	local store = getDataStore(dataStoreService, "Spec22-ListVersions", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	-- 3 versões da MESMA chave (via 3 SetAsync -- cada um cria uma versão nova, task-017).
	local versions: { string } = {}
	for i = 1, 3 do
		runAsync(function()
			versions[i] = setAsync(store, "ProfileKey", { revision = i }, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = listVersionsAsync(store, "ProfileKey", nil, nil, nil, nil)
	end)

	assert(pages.ClassName == "DataStoreVersionPages", `ListVersionsAsync deveria devolver uma DataStoreVersionPages, devolveu {tostring(pages.ClassName)}`)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()

	-- Uso EXATO de ProfileVersionQuery (pesquisa-datastore-2026-09-05.md, seção C): processa a
	-- página corrente, checa IsFinished, avança se não terminou.
	local collectedVersions: { string } = {}
	while true do
		local page = getCurrentPage(pages)
		for _, item in page do
			local objectVersionInfo = item :: Dynamic
			table.insert(collectedVersions, objectVersionInfo.Version :: string)
		end
		if pages.IsFinished == true then
			break
		end
		runAsync(function()
			advance(pages)
		end)
	end

	assert(#collectedVersions == 3, `esperava as 3 versões escritas, achou {#collectedVersions}`)
	-- Ascending (default) -- ordem cronológica crescente: a 1a versão escrita vem primeiro.
	assert(collectedVersions[1] == versions[1], "1a versão coletada deveria ser a MAIS ANTIGA (Ascending é o default)")
	assert(collectedVersions[3] == versions[3], "3a versão coletada deveria ser a MAIS RECENTE")
end)

test("ListVersionsAsync: cada item da página é um DataStoreObjectVersionInfo com CreatedTime/IsDeleted/Version", function()
	local store = getDataStore(dataStoreService, "Spec23-ListVersions", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local removeAsync = store.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	local firstVersion: string
	runAsync(function()
		firstVersion = setAsync(store, "K1", 1, nil, nil)
	end)
	runAsync(function()
		removeAsync(store, "K1") -- cria uma 2a versão, tombstoned (IsDeleted == true)
	end)

	local pages: Dynamic
	runAsync(function()
		pages = listVersionsAsync(store, "K1", nil, nil, nil, nil)
	end)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 2, `esperava 2 versões (1 Set + 1 Remove), achou {#items}`)

	assert(items[1].ClassName == "DataStoreObjectVersionInfo", "item da página deveria ser DataStoreObjectVersionInfo")
	assert(items[1].Version == firstVersion, "1o item deveria ser a versão do Set")
	assert(items[1].IsDeleted == false, "1o item (Set) não deveria estar marcado IsDeleted")
	assert(type(items[1].CreatedTime) == "number", "CreatedTime deveria ser number")

	assert(items[2].IsDeleted == true, "2o item (Remove) deveria estar marcado IsDeleted == true")
end)

test("ListVersionsAsync com sortDirection OMITIDO usa Ascending (default do dump) -- sem erro", function()
	local store = getDataStore(dataStoreService, "Spec24-ListVersions", nil, nil)
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return listVersionsAsync(store, "NeverWritten", nil, nil, nil, nil)
		end)
	end)
	assert(ok, `ListVersionsAsync sem sortDirection não deveria erro, recebeu: {tostring(err)}`)
end)

test("ListVersionsAsync com sortDirection PRESENTE (qualquer valor) ERRA [LuauBench] citando a lacuna de ponte Enum -- nunca aceito em silêncio", function()
	local store = getDataStore(dataStoreService, "Spec25-ListVersions", nil, nil)
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return listVersionsAsync(store, "K1", "Ascending", nil, nil, nil)
		end)
	end)

	assert(ok == false, "ListVersionsAsync com sortDirection PRESENTE deveria erro -- Enum.SortDirection não tem ponte")
	assert(
		string.find(tostring(err), "[LuauBench]", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench], recebeu: {err}`
	)
	assert(
		string.find(tostring(err), "sortDirection", 1, true) ~= nil,
		`mensagem deveria citar 'sortDirection', recebeu: {err}`
	)
end)

test("ListVersionsAsync filtra por minDate/maxDate", function()
	local store = getDataStore(dataStoreService, "Spec26-ListVersions", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	runAsync(function()
		setAsync(store, "K1", 1, nil, nil)
	end)

	-- `maxDate = 1` (1 ms desde epoch) é ANTES de qualquer timestamp real (`DateTime.now()`) --
	-- nenhuma versão deveria passar no filtro.
	local pages: Dynamic
	runAsync(function()
		pages = listVersionsAsync(store, "K1", nil, nil, 1, nil)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(#getCurrentPage(pages) == 0, "maxDate no passado distante deveria filtrar TODAS as versões")

	-- `minDate = 1` (bem no passado) não deveria filtrar nada -- a versão escrita é bem mais recente.
	local pagesUnfiltered: Dynamic
	runAsync(function()
		pagesUnfiltered = listVersionsAsync(store, "K1", nil, 1, nil, nil)
	end)
	local getCurrentPageUnfiltered = pagesUnfiltered.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(#getCurrentPageUnfiltered(pagesUnfiltered) == 1, "minDate no passado distante NÃO deveria filtrar a versão recente")
end)

-- ================= ListKeysAsync =================

test("ListKeysAsync sem argumentos lista TODAS as chaves do store, paginando até IsFinished", function()
	local store = getDataStore(dataStoreService, "Spec27-ListKeys", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local listKeysAsync = store.ListKeysAsync :: (self: Dynamic, prefix: string?, pageSize: number?, cursor: string?, excludeDeleted: boolean?) -> Dynamic

	local expectedKeys = { "alpha", "bravo", "charlie" }
	for _, key in expectedKeys do
		runAsync(function()
			setAsync(store, key, 1, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = listKeysAsync(store, nil, 1, nil, nil) -- pageSize=1 força múltiplas páginas
	end)
	assert(pages.ClassName == "DataStoreKeyPages", `ListKeysAsync deveria devolver uma DataStoreKeyPages, devolveu {tostring(pages.ClassName)}`)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()

	local collectedKeys: { string } = {}
	local pageCount = 0
	while true do
		local page = getCurrentPage(pages)
		for _, item in page do
			table.insert(collectedKeys, item :: string)
		end
		pageCount += 1
		if pages.IsFinished == true then
			break
		end
		runAsync(function()
			advance(pages)
		end)
	end

	assert(pageCount == 3, `pageSize=1 com 3 chaves deveria dar 3 páginas, deu {pageCount}`)
	table.sort(collectedKeys)
	assert(collectedKeys[1] == "alpha" and collectedKeys[2] == "bravo" and collectedKeys[3] == "charlie", "as 3 chaves escritas deveriam ter sido coletadas, em ordem alfabética")
end)

test("ListKeysAsync com prefix filtra corretamente", function()
	local store = getDataStore(dataStoreService, "Spec28-ListKeys", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local listKeysAsync = store.ListKeysAsync :: (self: Dynamic, prefix: string?, pageSize: number?, cursor: string?, excludeDeleted: boolean?) -> Dynamic

	for _, key in { "player_1", "player_2", "guild_1" } do
		runAsync(function()
			setAsync(store, key, 1, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = listKeysAsync(store, "player_", nil, nil, nil)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local items = getCurrentPage(pages)

	assert(#items == 2, `prefix 'player_' deveria filtrar só as 2 chaves que começam assim, achou {#items}`)
	local sorted: { string } = {}
	for _, item in items do
		table.insert(sorted, item :: string)
	end
	table.sort(sorted)
	assert(sorted[1] == "player_1" and sorted[2] == "player_2", "as chaves filtradas deveriam ser exatamente player_1/player_2")
end)

test("ListKeysAsync com excludeDeleted == true exclui chaves cuja versão CORRENTE é tombstone; excludeDeleted == false (default) inclui", function()
	local store = getDataStore(dataStoreService, "Spec29-ListKeys", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local removeAsync = store.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown
	local listKeysAsync = store.ListKeysAsync :: (self: Dynamic, prefix: string?, pageSize: number?, cursor: string?, excludeDeleted: boolean?) -> Dynamic

	runAsync(function()
		setAsync(store, "alive", 1, nil, nil)
	end)
	runAsync(function()
		setAsync(store, "removed", 1, nil, nil)
	end)
	runAsync(function()
		removeAsync(store, "removed")
	end)

	-- excludeDeleted == false (default) -- as DUAS chaves aparecem.
	local pagesIncluding: Dynamic
	runAsync(function()
		pagesIncluding = listKeysAsync(store, nil, nil, nil, false)
	end)
	local getCurrentPageIncluding = pagesIncluding.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(#getCurrentPageIncluding(pagesIncluding) == 2, "excludeDeleted == false deveria incluir a chave removida também")

	-- excludeDeleted == true -- só "alive" aparece.
	local pagesExcluding: Dynamic
	runAsync(function()
		pagesExcluding = listKeysAsync(store, nil, nil, nil, true)
	end)
	local getCurrentPageExcluding = pagesExcluding.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local itemsExcluding = getCurrentPageExcluding(pagesExcluding)
	assert(#itemsExcluding == 1, `excludeDeleted == true deveria excluir a chave removida, sobrando 1, achou {#itemsExcluding}`)
	assert(itemsExcluding[1] == "alive", "a única chave restante deveria ser 'alive'")
end)

-- ================= Engenharia interna =================

test("engenharia interna: um DataStore construído FORA de DataStoreService (sem _LuauBenchStoreId) erra em português ao chamar GetVersionAsync", function()
	local rawInstance = (Runtime.ClassRegistry.NewEngineInstance("DataStore", nil) :: unknown) :: Dynamic
	local getVersionAsync = rawInstance.GetVersionAsync :: (self: Dynamic, key: string, version: string) -> ...unknown

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return getVersionAsync(rawInstance, "K1", "v1")
		end)
	end)

	assert(ok == false, "GetVersionAsync sobre uma instância sem _LuauBenchStoreId deveria erro")
	assert(
		string.find(tostring(err), "_LuauBenchStoreId", 1, true) ~= nil,
		`mensagem de engenharia interna deveria citar a chave ausente, recebeu: {err}`
	)
end)

test("chamar ListVersionsAsync FORA de uma thread gerida pelo Scheduler erra [LuauBench] (AsyncCall.Yield) -- confirma a fiação", function()
	local store = getDataStore(dataStoreService, "Spec30-ListVersions", nil, nil)
	local listVersionsAsync = store.ListVersionsAsync :: (self: Dynamic, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?) -> Dynamic

	local ok, err = pcall(function()
		listVersionsAsync(store, "K1", nil, nil, nil, nil)
	end)

	assert(not ok, "ListVersionsAsync fora de thread gerida deveria erro")
	assert(
		string.find(tostring(err), "DataStore:ListVersionsAsync", 1, true) ~= nil,
		`mensagem deveria citar o label do método real, recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
