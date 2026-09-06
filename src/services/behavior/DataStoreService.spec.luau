--!strict

--[[
	Teste dedicado de `./DataStoreService.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). `./GlobalDataStore.spec.luau` cobre o comportamento de leitura/escrita em si -- este
	arquivo cobre a fábrica/memoização/singleton de `DataStoreService`.

	Roda com `lune run src/services/behavior/DataStoreService.spec.luau`.
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

local function makeDataStoreService(): Dynamic
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return (game:GetService("DataStoreService") :: unknown) :: Dynamic
end

test("game:GetService('DataStoreService') devolve uma instância -- singleton do processo (Service, NotCreatable)", function()
	local dss = makeDataStoreService()
	assert(dss ~= nil, "DataStoreService deveria existir depois de Bootstrap")
	local instance = (dss :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "DataStoreService", "ClassName deveria ser DataStoreService")
end)

test("GetDataStore(name, scope) duas vezes com o MESMO (name, scope) devolve a MESMA instância", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

	local store1 = getDataStore(dss, "Players", "v1", nil)
	local store2 = getDataStore(dss, "Players", "v1", nil)
	assert(rawequal(store1, store2), "GetDataStore com o mesmo (name, scope) deveria devolver a MESMA Instance -- doc oficial: 'subsequent calls return the same object'")
end)

test("GetDataStore com scope OMITIDO usa o default 'global' -- memoiza igual a passar 'global' explicitamente", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

	local implicitScope = getDataStore(dss, "DefaultScopeTest", nil, nil)
	local explicitScope = getDataStore(dss, "DefaultScopeTest", "global", nil)
	assert(rawequal(implicitScope, explicitScope), "scope omitido deveria memoizar como 'global', a MESMA Instance de passar 'global' explicitamente")
end)

test("GetDataStore com name OU scope diferente devolve instâncias DIFERENTES", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

	local base = getDataStore(dss, "A", "s1", nil)
	local differentName = getDataStore(dss, "B", "s1", nil)
	local differentScope = getDataStore(dss, "A", "s2", nil)

	assert(not rawequal(base, differentName), "nomes diferentes deveriam produzir instâncias diferentes")
	assert(not rawequal(base, differentScope), "scopes diferentes deveriam produzir instâncias diferentes")
end)

test("GetOrderedDataStore(name, scope) é memoizado no MESMO mapa de cache, mas é instância DIFERENTE de GetDataStore(name, scope)", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local getOrderedDataStore = dss.GetOrderedDataStore :: (self: Dynamic, name: string, scope: string?) -> Dynamic

	local regular = getDataStore(dss, "Shared", "s1", nil)
	local ordered1 = getOrderedDataStore(dss, "Shared", "s1")
	local ordered2 = getOrderedDataStore(dss, "Shared", "s1")

	assert(not rawequal(regular, ordered1), "GetOrderedDataStore('Shared','s1') deveria ser DIFERENTE de GetDataStore('Shared','s1') mesmo com o mesmo (name, scope)")
	assert(rawequal(ordered1, ordered2), "GetOrderedDataStore duas vezes com o mesmo (name, scope) deveria devolver a MESMA Instance")

	local orderedInstance = (ordered1 :: unknown) :: Runtime.Instance
	assert(orderedInstance.ClassName == "OrderedDataStore", "GetOrderedDataStore deveria devolver ClassName == OrderedDataStore")
end)

test("GetGlobalDataStore() é memoizado (mesma instância em duas chamadas) e tem ClassName == 'DataStore' -- ambiguidade do dump, seguida ao pé da letra", function()
	local dss = makeDataStoreService()
	local getGlobalDataStore = dss.GetGlobalDataStore :: (self: Dynamic) -> Dynamic
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

	local global1 = getGlobalDataStore(dss)
	local global2 = getGlobalDataStore(dss)
	assert(rawequal(global1, global2), "GetGlobalDataStore duas vezes deveria devolver a MESMA Instance")

	local globalInstance = (global1 :: unknown) :: Runtime.Instance
	assert(globalInstance.ClassName == "DataStore", "GetGlobalDataStore deveria devolver ClassName == DataStore (ambiguidade do dump, L2.1.7)")

	-- Nunca colide com um GetDataStore(name, scope) escolhido pelo script -- ver DataStoreService.luau,
	-- cabeçalho ("MEMOIZAÇÃO").
	local otherStore = getDataStore(dss, "", "", nil)
	assert(not rawequal(global1, otherStore), "GetGlobalDataStore() deveria viver num namespace de cache separado de GetDataStore('', '')")
end)

test("GetRequestBudgetForRequestType devolve uma constante grande e fixa -- nunca math.huge, nunca 0, independente do requestType", function()
	local dss = makeDataStoreService()
	local getRequestBudget = dss.GetRequestBudgetForRequestType :: (self: Dynamic, requestType: unknown) -> number

	local budgetA = getRequestBudget(dss, "GetAsync")
	local budgetB = getRequestBudget(dss, "SetIncrementSortedAsync")
	local budgetNil = getRequestBudget(dss, nil)

	assert(budgetA > 0, "o orçamento nunca deveria ser 0")
	assert(budgetA ~= math.huge, "o orçamento nunca deveria ser math.huge")
	assert(budgetA == budgetB and budgetB == budgetNil, "o orçamento deveria ser a MESMA constante independente do requestType (nenhum é inspecionado)")
end)

test("SetRateLimitForRequestType é aceito e IGNORADO -- não erra, e não muda o orçamento devolvido depois", function()
	local dss = makeDataStoreService()
	local setRateLimit = dss.SetRateLimitForRequestType :: (self: Dynamic, requestType: unknown, baseLimit: number, perPlayerLimit: number) -> ()
	local getRequestBudget = dss.GetRequestBudgetForRequestType :: (self: Dynamic, requestType: unknown) -> number

	local before = getRequestBudget(dss, "GetAsync")
	local ok = pcall(function()
		setRateLimit(dss, "GetAsync", 1, 1)
	end)
	assert(ok, "SetRateLimitForRequestType não deveria erro")

	local after = getRequestBudget(dss, "GetAsync")
	assert(before == after, "SetRateLimitForRequestType deveria ser um no-op puro -- o orçamento não deveria mudar")
end)

test("GetDataStore/GetOrderedDataStore com name ou scope > 50 caracteres erra -- família de limite de tamanho (Value.luau)", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local getOrderedDataStore = dss.GetOrderedDataStore :: (self: Dynamic, name: string, scope: string?) -> Dynamic
	local longName = string.rep("x", 51)

	local okName, errName = pcall(function()
		getDataStore(dss, longName, nil, nil)
	end)
	assert(not okName, "GetDataStore com name > 50 caracteres deveria erro")
	assert(
		string.find(tostring(errName), "must be less than or equal to 50 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 50 caracteres, recebeu: {errName}`
	)

	local okScope, errScope = pcall(function()
		getDataStore(dss, "OK", longName, nil)
	end)
	assert(not okScope, "GetDataStore com scope > 50 caracteres deveria erro")
	assert(
		string.find(tostring(errScope), "must be less than or equal to 50 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 50 caracteres, recebeu: {errScope}`
	)

	local okOrdered = pcall(function()
		getOrderedDataStore(dss, longName, nil)
	end)
	assert(not okOrdered, "GetOrderedDataStore com name > 50 caracteres deveria erro")
end)

test("GetDataStore/GetGlobalDataStore/GetOrderedDataStore são SÍNCRONOS -- funcionam FORA de uma thread gerida pelo Scheduler (sem Yields no dump)", function()
	local dss = makeDataStoreService()
	local getDataStore = dss.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local getGlobalDataStore = dss.GetGlobalDataStore :: (self: Dynamic) -> Dynamic
	local getOrderedDataStore = dss.GetOrderedDataStore :: (self: Dynamic, name: string, scope: string?) -> Dynamic

	-- Chamado direto na thread principal do processo do spec -- se qualquer um destes três
	-- yieldasse via AsyncCall.Yield, isto erraria com a mensagem [LuauBench] de thread não gerida.
	local ok = pcall(function()
		getDataStore(dss, "SyncTest", nil, nil)
		getGlobalDataStore(dss)
		getOrderedDataStore(dss, "SyncTest", nil)
	end)

	assert(ok, "GetDataStore/GetGlobalDataStore/GetOrderedDataStore não deveriam precisar de uma thread gerida -- são síncronos no dump (confirmado por pesquisa-datastore-2026-09-05.md)")
end)

test("DataStoreService:ListDataStoresAsync() (não implementado nesta leva) erra com o stub [LuauBench] do ClassBuilder", function()
	local dss = makeDataStoreService()
	local listDataStoresAsync = dss.ListDataStoresAsync :: (self: Dynamic, prefix: string?, pageSize: number?, cursor: string?) -> unknown

	local ok, err = pcall(function()
		listDataStoresAsync(dss, nil, nil, nil)
	end)

	assert(not ok, "ListDataStoresAsync não tem Methods em behavior/DataStoreService.luau -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(err), "[LuauBench] DataStoreService:ListDataStoresAsync() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {err}`
	)
end)

test("duas Bootstrap/DataModel diferentes têm CADA UMA seu próprio game:GetService('DataStoreService') singleton -- mas o CACHE de (name,scope)->Instance é module-local (L2.0.2), então as DUAS enxergam o MESMO DataStore para o mesmo (name,scope)", function()
	local dss1 = makeDataStoreService()
	local dss2 = makeDataStoreService()
	assert(not rawequal(dss1, dss2), "duas DataModel diferentes deveriam ter singletons de DataStoreService DIFERENTES (um por DataModel)")

	-- `cache`/`store` (aqui e em GlobalDataStore.luau) são `local` de MÓDULO, não por instância de
	-- DataStoreService -- decisão EXPLÍCITA de L2.0.2 ("Serviço que é singleton... guarda estado em
	-- local de módulo... um processo tem exatamente uma instância por processo", e o desenho
	-- documenta que múltiplos DataModel no MESMO processo é um cenário de TESTE, não de produção
	-- suportada -- "não há caso de uso de 'desregistrar uma classe'"/watch mode reiniciando o
	-- DataModel é um GATILHO REGISTRADO para o arquiteto revisitar, não algo já suportado hoje).
	-- Por isso, embora dss1/dss2 sejam Instances DIFERENTES, o MESMO (name,scope) devolve a MESMA
	-- Instance de DataStore -- comportamento intencional, não um vazamento acidental de estado.
	local getDataStore1 = dss1.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local getDataStore2 = dss2.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic
	local store1 = getDataStore1(dss1, "CrossDataModel", nil, nil)
	local store2 = getDataStore2(dss2, "CrossDataModel", nil, nil)

	assert(
		rawequal(store1, store2),
		"o cache de (name,scope)->Instance é module-local (um processo, um DataStoreService de verdade) -- duas DataModel no mesmo processo Lune COMPARTILHAM o mesmo DataStore para o mesmo (name,scope), por design (L2.0.2)"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
