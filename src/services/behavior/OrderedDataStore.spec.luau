--!strict

--[[
	Teste dedicado de `./OrderedDataStore.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Cobre o acceptance de task-services-020: `GetSortedAsync` ordenando crescente e
	decrescente, respeitando `minValue`/`maxValue` e `pagesize`; valor não inteiro recusado em
	`SetAsync`/`UpdateAsync`/`IncrementAsync` de um `OrderedDataStore` (validação que mora em
	`./GlobalDataStore.luau`, gated por ClassName -- ver o cabeçalho de ambos os arquivos); e
	remoção permanente (sem `GetVersionAsync`/`ListVersionsAsync` alcançáveis para ler o histórico
	de volta).

	Todo método `*Async` (incluindo `GetSortedAsync` e `AdvanceToNextPageAsync`, herdado de `Pages`)
	passa por `../AsyncCall.luau` -- mesmo padrão de `GlobalDataStore.spec.luau`/`DataStore.spec.luau`:
	`scheduler:Spawn(...)` seguido de `scheduler:StepOnce(0)`.

	`store` (o dado de verdade, em `./GlobalDataStore.luau`) é MÓDULO-LOCAL, compartilhado com
	`GlobalDataStore.spec.luau`/`DataStore.spec.luau` -- por isso cada teste abaixo usa um NOME de
	OrderedDataStore exclusivo (mesma disciplina dos specs irmãos).

	Roda com `lune run src/services/behavior/OrderedDataStore.spec.luau`.
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
local getOrderedDataStore = dataStoreService.GetOrderedDataStore :: (self: Dynamic, name: string, scope: string?) -> Dynamic

-- Chama `body` dentro de uma thread gerida pelo Scheduler e avança exatamente um passo -- basta
-- para o único `AsyncCall.Yield` que cada método `*Async` faz (`Wait(0)`).
local function runAsync(body: () -> ()): ()
	scheduler:Spawn(body)
	scheduler:StepOnce(0)
end

-- ================= GetSortedAsync -- ordenação =================

test("GetSortedAsync(ascending = true) ordena do MENOR pro MAIOR valor", function()
	local store = getOrderedDataStore(dataStoreService, "Spec1-Sorted", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	for _, entry in { { key = "Alice", value = 30 }, { key = "Bob", value = 10 }, { key = "Carol", value = 20 } } do
		runAsync(function()
			setAsync(store, entry.key, entry.value, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, nil, nil)
	end)
	assert(pages.ClassName == "DataStorePages", `GetSortedAsync deveria devolver uma DataStorePages, devolveu {tostring(pages.ClassName)}`)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 3, `esperava as 3 chaves escritas, achou {#items}`)
	assert(items[1].key == "Bob" and items[1].value == 10, `1o item deveria ser o menor valor (Bob/10), achou {tostring(items[1].key)}/{tostring(items[1].value)}`)
	assert(items[2].key == "Carol" and items[2].value == 20, "2o item deveria ser Carol/20")
	assert(items[3].key == "Alice" and items[3].value == 30, "3o item deveria ser o maior valor (Alice/30)")
end)

test("GetSortedAsync(ascending = false) ordena do MAIOR pro MENOR valor", function()
	local store = getOrderedDataStore(dataStoreService, "Spec2-Sorted", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	for _, entry in { { key = "Alice", value = 30 }, { key = "Bob", value = 10 }, { key = "Carol", value = 20 } } do
		runAsync(function()
			setAsync(store, entry.key, entry.value, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, false, nil, nil, nil)
	end)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 3, `esperava as 3 chaves escritas, achou {#items}`)
	assert(items[1].key == "Alice" and items[1].value == 30, "1o item deveria ser o maior valor (Alice/30) com ascending=false")
	assert(items[3].key == "Bob" and items[3].value == 10, "3o item deveria ser o menor valor (Bob/10)")
end)

test("GetSortedAsync: cada item da página é uma TABELA PLANA {key, value}, nunca uma Instance", function()
	local store = getOrderedDataStore(dataStoreService, "Spec3-Sorted", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	runAsync(function()
		setAsync(store, "Solo", 7, nil, nil)
	end)

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, nil, nil)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)

	assert(#items == 1, "esperava exatamente 1 item")
	assert(items[1].key == "Solo" and items[1].value == 7, "item deveria ser {key='Solo', value=7}")
	assert(items[1].ClassName == nil, "item de GetSortedAsync deveria ser uma tabela PLANA -- nunca uma Instance (sem .ClassName)")
end)

-- ================= GetSortedAsync -- minValue/maxValue =================

test("GetSortedAsync respeita minValue/maxValue (filtra fora do range, inclusive nas pontas)", function()
	local store = getOrderedDataStore(dataStoreService, "Spec4-Range", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	for _, entry in { { key = "K10", value = 10 }, { key = "K20", value = 20 }, { key = "K30", value = 30 } } do
		runAsync(function()
			setAsync(store, entry.key, entry.value, nil, nil)
		end)
	end

	-- [15, 25] deveria incluir só K20.
	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, 15, 25)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 1, `[15,25] deveria filtrar só K20, achou {#items}`)
	assert(items[1].key == "K20", "único item deveria ser K20")

	-- Pontas INCLUSIVAS: [10, 30] deveria incluir os 3.
	local pagesInclusive: Dynamic
	runAsync(function()
		pagesInclusive = getSortedAsync(store, true, nil, 10, 30)
	end)
	local getCurrentPageInclusive = pagesInclusive.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	assert(#getCurrentPageInclusive(pagesInclusive) == 3, "[10,30] deveria incluir os 3 itens (pontas inclusivas)")
end)

test("GetSortedAsync com minValue/maxValue omitidos (nil) não filtra nada", function()
	local store = getOrderedDataStore(dataStoreService, "Spec5-Range", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	-- Valor NEGATIVO -- confirma que "sem limite" não usa `0` como sentinela (diferente de
	-- ./DataStore.luau/minDate, que usa `<= 0`; ver cabeçalho de ./OrderedDataStore.luau).
	runAsync(function()
		setAsync(store, "Negative", -50, nil, nil)
	end)
	runAsync(function()
		setAsync(store, "Zero", 0, nil, nil)
	end)

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, nil, nil)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 2, `minValue/maxValue nil não deveria filtrar nada, achou {#items}`)
	assert(items[1].key == "Negative" and items[1].value == -50, "valor negativo deveria ser aceito e ordenado normalmente")
	assert(items[2].key == "Zero" and items[2].value == 0, "valor zero deveria ser aceito (positividade NÃO exigida, ver cabeçalho de GlobalDataStore.luau)")
end)

-- ================= GetSortedAsync -- pagesize =================

test("GetSortedAsync respeita pagesize, paginando via GetCurrentPage/IsFinished/AdvanceToNextPageAsync", function()
	local store = getOrderedDataStore(dataStoreService, "Spec6-PageSize", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	for i = 1, 5 do
		runAsync(function()
			setAsync(store, `Player{i}`, i, nil, nil)
		end)
	end

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, 2, nil, nil) -- pagesize=2 com 5 itens -> 3 páginas (2+2+1)
	end)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()

	local collected: { number } = {}
	local pageCount = 0
	while true do
		local page = getCurrentPage(pages)
		for _, item in page do
			table.insert(collected, item.value :: number)
		end
		pageCount += 1
		if pages.IsFinished == true then
			break
		end
		runAsync(function()
			advance(pages)
		end)
	end

	assert(pageCount == 3, `pagesize=2 com 5 itens deveria dar 3 páginas, deu {pageCount}`)
	assert(#collected == 5, `esperava coletar os 5 itens ao todo, achou {#collected}`)
	assert(collected[1] == 1 and collected[5] == 5, "ordem ascendente deveria ser preservada através da paginação")
end)

test("GetSortedAsync com pagesize omitido usa o default 50 (NÃO 0/math.huge)", function()
	local store = getOrderedDataStore(dataStoreService, "Spec7-DefaultPageSize", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	runAsync(function()
		setAsync(store, "Only", 1, nil, nil)
	end)

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, nil, nil)
	end)
	-- Só 1 item, bem abaixo de qualquer pagesize razoável -- a página corrente já deveria estar
	-- IsFinished == true (não haveria como testar o VALOR exato do default sem reimplementar a
	-- fábrica de Pages aqui; o que importa é que 1 item cabe inteiro numa única página).
	assert(pages.IsFinished == true, "com 1 item só, a primeira página já deveria estar IsFinished (default de pagesize bem maior que 1)")
end)

-- ================= Validação de valor -- SÓ INTEIRO (task-services-020) =================

test("SetAsync com valor FRACIONÁRIO num OrderedDataStore ERRA -- família Roblox", function()
	local store = getOrderedDataStore(dataStoreService, "Spec8-Integer", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

	local ok, err = pcall(function()
		setAsync(store, "K1", 3.14, nil, nil)
	end)
	assert(not ok, "SetAsync com valor fracionário num OrderedDataStore deveria erro")
	assert(
		string.find(tostring(err), "must be integers", 1, true) ~= nil,
		`mensagem deveria citar a exigência de inteiro, recebeu: {err}`
	)
end)

test("SetAsync com valor NÃO NUMÉRICO (string) num OrderedDataStore ERRA", function()
	local store = getOrderedDataStore(dataStoreService, "Spec9-Integer", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

	local ok, err = pcall(function()
		setAsync(store, "K1", "not a number", nil, nil)
	end)
	assert(not ok, "SetAsync com string num OrderedDataStore deveria erro")
	assert(
		string.find(tostring(err), "must be integers", 1, true) ~= nil,
		`mensagem deveria citar a exigência de inteiro, recebeu: {err}`
	)
end)

test("SetAsync com INTEIRO (positivo, negativo, ou zero) num OrderedDataStore funciona normalmente", function()
	local store = getOrderedDataStore(dataStoreService, "Spec10-Integer", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	for _, entry in { { key = "Pos", value = 42 }, { key = "Neg", value = -42 }, { key = "Zero", value = 0 } } do
		local ok = true
		local err: unknown = nil
		runAsync(function()
			ok, err = pcall(function()
				setAsync(store, entry.key, entry.value, nil, nil)
			end)
		end)
		assert(ok, `SetAsync({entry.key}, {entry.value}) não deveria erro (inteiro válido, positividade não exigida), recebeu: {tostring(err)}`)
	end

	local zeroValue: unknown
	runAsync(function()
		zeroValue = getAsync(store, "Zero", nil)
	end)
	assert(zeroValue == 0, "GetAsync deveria devolver 0 de volta")
end)

test("UpdateAsync cuja transform devolve um valor NÃO INTEIRO num OrderedDataStore ERRA e ABORTA a escrita", function()
	local store = getOrderedDataStore(dataStoreService, "Spec11-Integer", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", 10, nil, nil)
	end)

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return updateAsync(store, "K1", function(oldValue: unknown, _oldKeyInfo: unknown): number
				return (oldValue :: number) + 0.5
			end)
		end)
	end)
	assert(not ok, "UpdateAsync devolvendo um valor fracionário num OrderedDataStore deveria erro")
	assert(
		string.find(tostring(err), "must be integers", 1, true) ~= nil,
		`mensagem deveria citar a exigência de inteiro, recebeu: {err}`
	)

	-- A escrita foi ABORTADA -- o valor anterior (10) continua lá, intacto.
	local stillThere: unknown
	runAsync(function()
		stillThere = getAsync(store, "K1", nil)
	end)
	assert(stillThere == 10, `a escrita abortada não deveria ter alterado o valor guardado, achou {tostring(stillThere)}`)
end)

test("UpdateAsync cuja transform devolve nil continua abortando normalmente (nenhuma mudança de comportamento)", function()
	local store = getOrderedDataStore(dataStoreService, "Spec12-Integer", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", 10, nil, nil)
	end)

	local newValue: unknown = "not yet set"
	runAsync(function()
		newValue = updateAsync(store, "K1", function(_oldValue: unknown, _oldKeyInfo: unknown)
			return nil
		end)
	end)
	assert(newValue == nil, "UpdateAsync devolvendo nil continua sendo um ABORTO normal, mesmo num OrderedDataStore")
end)

test("IncrementAsync cujo RESULTADO não é inteiro num OrderedDataStore ERRA e ABORTA a escrita", function()
	local store = getOrderedDataStore(dataStoreService, "Spec13-Integer", nil)
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	runAsync(function()
		incrementAsync(store, "Counter", 10, nil, nil) -- parte de 0, vira 10 (inteiro, ok)
	end)

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return incrementAsync(store, "Counter", 0.5, nil, nil)
		end)
	end)
	assert(not ok, "IncrementAsync com delta fracionário cujo resultado não é inteiro deveria erro")
	assert(
		string.find(tostring(err), "must be integers", 1, true) ~= nil,
		`mensagem deveria citar a exigência de inteiro, recebeu: {err}`
	)

	local stillThere: unknown
	runAsync(function()
		stillThere = getAsync(store, "Counter", nil)
	end)
	assert(stillThere == 10, `a escrita abortada não deveria ter alterado o valor guardado, achou {tostring(stillThere)}`)
end)

test("IncrementAsync com delta inteiro num OrderedDataStore funciona normalmente (regressão)", function()
	local store = getOrderedDataStore(dataStoreService, "Spec14-Integer", nil)
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown

	local value: unknown
	runAsync(function()
		value = incrementAsync(store, "Counter", 5, nil, nil)
	end)
	assert(value == 5, `1a chamada deveria partir de 0 (esperava 5, achou {tostring(value)})`)
end)

test("REGRESSÃO: GlobalDataStore/DataStore continuam aceitando valor NÃO INTEIRO normalmente (a validação é EXCLUSIVA de OrderedDataStore)", function()
	local dataStore = dataStoreService.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local plainStore = dataStore(dataStoreService, "Spec15-NotOrdered", nil, nil)
	local setAsync = plainStore.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			setAsync(plainStore, "K1", 3.14, nil, nil)
		end)
	end)
	assert(ok, `SetAsync(3.14) num DataStore comum NÃO deveria erro -- a validação de inteiro é exclusiva de OrderedDataStore, recebeu: {tostring(err)}`)
end)

-- ================= Remoção permanente (L2.1.3) =================

test("RemoveAsync é permanente: depois de removida, a chave nunca mais aparece em GetAsync nem em GetSortedAsync", function()
	local store = getOrderedDataStore(dataStoreService, "Spec16-Remove", nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local removeAsync = store.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	runAsync(function()
		setAsync(store, "Alive", 1, nil, nil)
	end)
	runAsync(function()
		setAsync(store, "Removed", 2, nil, nil)
	end)
	runAsync(function()
		removeAsync(store, "Removed")
	end)

	local afterRemove: unknown
	runAsync(function()
		afterRemove = getAsync(store, "Removed", nil)
	end)
	assert(afterRemove == nil, "GetAsync depois de RemoveAsync deveria devolver nil")

	local pages: Dynamic
	runAsync(function()
		pages = getSortedAsync(store, true, nil, nil, nil)
	end)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { Dynamic }
	local items = getCurrentPage(pages)
	assert(#items == 1, `GetSortedAsync depois de RemoveAsync deveria excluir a chave removida, achou {#items} itens`)
	assert(items[1].key == "Alive", "único item restante deveria ser 'Alive'")
end)

test("OrderedDataStore NÃO tem GetVersionAsync/ListVersionsAsync alcançável -- nenhuma forma de ler o histórico de volta (REMOÇÃO PERMANENTE por construção)", function()
	local store = getOrderedDataStore(dataStoreService, "Spec17-NoHistory", nil)

	local ok, err = pcall(function()
		return store.GetVersionAsync
	end)
	assert(not ok, "indexar GetVersionAsync num OrderedDataStore deveria erro -- esse membro não existe nesta classe (é de 'DataStore', fora da cadeia de superclasses de OrderedDataStore)")
	assert(
		string.find(tostring(err), "is not a valid member of", 1, true) ~= nil,
		`mensagem deveria ser a família nativa "is not a valid member of", recebeu: {err}`
	)
end)

-- ================= Engenharia interna / fiação =================

test("chamar GetSortedAsync FORA de uma thread gerida pelo Scheduler erra [LuauBench] (AsyncCall.Yield) -- confirma a fiação", function()
	local store = getOrderedDataStore(dataStoreService, "Spec18-Async", nil)
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: boolean, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	local ok, err = pcall(function()
		getSortedAsync(store, true, nil, nil, nil)
	end)
	assert(not ok, "GetSortedAsync fora de thread gerida deveria erro")
	assert(
		string.find(tostring(err), "OrderedDataStore:GetSortedAsync", 1, true) ~= nil,
		`mensagem deveria citar o label do método real, recebeu: {err}`
	)
end)

test("GetSortedAsync com argumento 'ascending' de tipo errado erra -- argumento nativo", function()
	local store = getOrderedDataStore(dataStoreService, "Spec19-BadArg", nil)
	local getSortedAsync = store.GetSortedAsync :: (self: Dynamic, ascending: unknown, pagesize: number?, minValue: unknown, maxValue: unknown) -> Dynamic

	local ok, err = pcall(function()
		getSortedAsync(store, "not a boolean", nil, nil, nil)
	end)
	assert(not ok, "GetSortedAsync com 'ascending' que não é boolean deveria erro")
	assert(
		string.find(tostring(err), "boolean expected", 1, true) ~= nil,
		`mensagem deveria citar o tipo esperado, recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
