--!strict

--[[
	Teste dedicado de `./GlobalDataStore.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Cobre o núcleo do acceptance de task-services-018: GetAsync/SetAsync/UpdateAsync/
	RemoveAsync/IncrementAsync, deep copy de ponta a ponta, detecção de yield na transform de
	UpdateAsync, e a propagação de metadata via DataStoreSetOptions/DataStoreIncrementOptions.

	Todo método `*Async` passa por `../AsyncCall.luau` (`Context.GetScheduler():Wait(0)`) -- por
	isso todo teste que chama um deles roda dentro de `scheduler:Spawn(...)` seguido de
	`scheduler:StepOnce(0)` (um único passo basta -- mesmo padrão de `AsyncCall.spec.luau`).

	`store` (o dado de verdade) é MÓDULO-LOCAL em `GlobalDataStore.luau` -- um único processo, um
	único store, para SEMPRE (mesma invariante de `DataStoreService` ser singleton, L2.0.2). Por
	isso cada teste abaixo usa um NOME de DataStore (ou uma CHAVE) exclusivo -- dois testes
	reutilizando o mesmo `(name, scope, key)` compartilhariam dado de verdade, exatamente como dois
	scripts no MESMO servidor real compartilhariam.

	Roda com `lune run src/services/behavior/GlobalDataStore.spec.luau`.
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

-- Um scheduler/game/DataStoreService compartilhado pelo arquivo inteiro -- mesma disciplina de
-- `RunService.spec.luau` (que cria um por teste); aqui um só basta porque nenhum teste depende de
-- estado do SCHEDULER entre si, só do STORE (que já é module-local, então nem um scheduler novo
-- por teste isolaria o dado).
local scheduler = Runtime.Scheduler.new()
local game = Runtime.DataModel.new()
Services.Bootstrap({ scheduler = scheduler, dataModel = game })
local dataStoreService = (game:GetService("DataStoreService") :: unknown) :: Dynamic
local getDataStore = dataStoreService.GetDataStore :: (self: Dynamic, name: string, scope: string?, options: unknown?) -> Dynamic

-- Chama `body` dentro de uma thread gerida pelo Scheduler e avança exatamente um passo -- basta
-- para o único `AsyncCall.Yield` que cada método `*Async` faz (Wait(0), ver `AsyncCall.luau`).
local function runAsync(body: () -> ()): ()
	scheduler:Spawn(body)
	scheduler:StepOnce(0)
end

test("GetAsync de chave inexistente devolve (nil, nil)", function()
	local store = getDataStore(dataStoreService, "Spec1", nil, nil)
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	local value: unknown, keyInfo: unknown
	runAsync(function()
		value, keyInfo = getAsync(store, "missing", nil)
	end)

	assert(value == nil, "GetAsync de chave inexistente deveria devolver value nil")
	assert(keyInfo == nil, "GetAsync de chave inexistente deveria devolver keyInfo nil")
end)

test("SetAsync devolve uma string de versão, e GetAsync depois devolve (value, keyInfo não-nil)", function()
	local store = getDataStore(dataStoreService, "Spec2", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	local version: string
	runAsync(function()
		version = setAsync(store, "K1", { a = 1 }, nil, nil)
	end)
	assert(type(version) == "string", `SetAsync deveria devolver string, devolveu {type(version)}`)

	local value: unknown, keyInfo: unknown
	runAsync(function()
		value, keyInfo = getAsync(store, "K1", nil)
	end)

	local valueTable = value :: { [string]: unknown }
	assert(valueTable.a == 1, "GetAsync deveria devolver o valor gravado por SetAsync")
	assert(keyInfo ~= nil, "GetAsync deveria devolver keyInfo não-nil para chave existente")
end)

test("deep copy DE PONTA A PONTA: mutar o valor depois de SetAsync, e mutar o valor devolvido por GetAsync, não afeta o valor guardado", function()
	local store = getDataStore(dataStoreService, "Spec3", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	local original = { count = 1 }
	runAsync(function()
		setAsync(store, "K1", original, nil, nil)
	end)
	original.count = 999 -- mutação DEPOIS de SetAsync -- não deveria alcançar o store

	local firstRead: unknown
	runAsync(function()
		firstRead = getAsync(store, "K1", nil)
	end)
	local firstReadTable = firstRead :: { [string]: unknown }
	assert(firstReadTable.count == 1, `mutar o original depois de SetAsync não deveria afetar o store, achou {tostring(firstReadTable.count)}`)

	firstReadTable.count = 555 -- mutação do valor DEVOLVIDO -- não deveria alcançar o store

	local secondRead: unknown
	runAsync(function()
		secondRead = getAsync(store, "K1", nil)
	end)
	local secondReadTable = secondRead :: { [string]: unknown }
	assert(secondReadTable.count == 1, `mutar o retorno de GetAsync não deveria afetar o store, achou {tostring(secondReadTable.count)}`)
end)

test("UpdateAsync: transform recebe (oldValue, keyInfo), devolve (newValue, newKeyInfo)", function()
	local store = getDataStore(dataStoreService, "Spec4", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", { count = 10 }, nil, nil)
	end)

	local receivedOldValue: unknown, receivedOldKeyInfo: unknown
	local newValue: unknown, newKeyInfo: unknown
	runAsync(function()
		newValue, newKeyInfo = updateAsync(store, "K1", function(oldValue: unknown, oldKeyInfo: unknown): { [string]: unknown }
			receivedOldValue = oldValue
			receivedOldKeyInfo = oldKeyInfo
			local old = oldValue :: { [string]: unknown }
			return { count = (old.count :: number) + 5 }
		end)
	end)

	local receivedOldValueTable = receivedOldValue :: { [string]: unknown }
	assert(receivedOldValueTable.count == 10, "a transform deveria receber o valor corrente como 1o argumento")
	assert(receivedOldKeyInfo ~= nil, "a transform deveria receber keyInfo como 2o argumento, não-nil (a chave já existia)")

	local newValueTable = newValue :: { [string]: unknown }
	assert(newValueTable.count == 15, `UpdateAsync deveria devolver o novo valor, achou {tostring(newValueTable.count)}`)
	assert(newKeyInfo ~= nil, "UpdateAsync deveria devolver newKeyInfo não-nil")
end)

test("UpdateAsync sobre chave inexistente: transform recebe (nil, nil)", function()
	local store = getDataStore(dataStoreService, "Spec5", nil, nil)
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown

	local receivedOldValue: unknown = "not yet set"
	local receivedOldKeyInfo: unknown = "not yet set"
	runAsync(function()
		updateAsync(store, "NeverSet", function(oldValue: unknown, oldKeyInfo: unknown): { [string]: unknown }
			receivedOldValue = oldValue
			receivedOldKeyInfo = oldKeyInfo
			return { fresh = true }
		end)
	end)

	assert(receivedOldValue == nil, "transform sobre chave inexistente deveria receber oldValue nil")
	assert(receivedOldKeyInfo == nil, "transform sobre chave inexistente deveria receber oldKeyInfo nil")
end)

test("UpdateAsync aborta a escrita quando a transform devolve nil -- devolve (nil, nil), sem criar versão nova", function()
	local store = getDataStore(dataStoreService, "Spec6", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", { count = 1 }, nil, nil)
	end)

	local abortedNewValue: unknown = "not yet set"
	local abortedNewKeyInfo: unknown = "not yet set"
	runAsync(function()
		abortedNewValue, abortedNewKeyInfo = updateAsync(store, "K1", function(_oldValue: unknown, _oldKeyInfo: unknown)
			return nil
		end)
	end)

	assert(abortedNewValue == nil, "UpdateAsync deveria devolver newValue nil quando a transform aborta")
	assert(abortedNewKeyInfo == nil, "UpdateAsync deveria devolver newKeyInfo nil quando a transform aborta")

	-- O valor guardado continua o de ANTES da tentativa abortada.
	local stillThere: unknown
	runAsync(function()
		stillThere = getAsync(store, "K1", nil)
	end)
	local stillThereTable = stillThere :: { [string]: unknown }
	assert(stillThereTable.count == 1, "a escrita abortada não deveria ter alterado o valor guardado")
end)

test("UpdateAsync ERRA quando a transform yielda (coroutine.yield dentro dela) -- 'The callback function cannot yield'", function()
	local store = getDataStore(dataStoreService, "Spec7", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", { count = 1 }, nil, nil)
	end)

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return updateAsync(store, "K1", function(_oldValue: unknown, _oldKeyInfo: unknown)
				coroutine.yield()
				return { count = 2 }
			end)
		end)
	end)

	assert(ok == false, "UpdateAsync deveria erro quando a transform yielda")
	local message = tostring(err)
	assert(
		string.find(message, "The callback function cannot yield", 1, true) ~= nil,
		`mensagem deveria citar a proibição de yield (doc oficial, L2.1.5), recebeu: {message}`
	)
end)

test("UpdateAsync repassa um erro real DENTRO da transform (sem yield) tal como veio", function()
	local store = getDataStore(dataStoreService, "Spec8", nil, nil)
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: (unknown, unknown) -> ...unknown) -> ...unknown

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return updateAsync(store, "K1", function(_oldValue: unknown, _oldKeyInfo: unknown)
				error("boom from transform")
			end)
		end)
	end)

	assert(ok == false, "UpdateAsync deveria propagar um erro real levantado dentro da transform")
	assert(
		string.find(tostring(err), "boom from transform", 1, true) ~= nil,
		`mensagem deveria conter a mensagem original da transform, recebeu: {err}`
	)
end)

test("UpdateAsync(transformFunction que não é função) erra -- argumento nativo", function()
	local store = getDataStore(dataStoreService, "Spec9", nil, nil)
	local updateAsync = store.UpdateAsync :: (self: Dynamic, key: string, transform: unknown) -> ...unknown

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return updateAsync(store, "K1", "not a function")
		end)
	end)

	assert(ok == false, "UpdateAsync com transform que não é função deveria erro")
	assert(
		string.find(tostring(err), "function expected", 1, true) ~= nil,
		`mensagem deveria citar o tipo esperado, recebeu: {err}`
	)
end)

test("RemoveAsync devolve (valorAnterior, keyInfo) e GetAsync depois devolve nil -- RemoveAsync sobre chave já ausente é no-op (nil, nil)", function()
	local store = getDataStore(dataStoreService, "Spec10", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local removeAsync = store.RemoveAsync :: (self: Dynamic, key: string) -> ...unknown
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	runAsync(function()
		setAsync(store, "K1", { count = 1 }, nil, nil)
	end)

	local previousValue: unknown, previousKeyInfo: unknown
	runAsync(function()
		previousValue, previousKeyInfo = removeAsync(store, "K1")
	end)
	local previousValueTable = previousValue :: { [string]: unknown }
	assert(previousValueTable.count == 1, "RemoveAsync deveria devolver o valor anterior")
	assert(previousKeyInfo ~= nil, "RemoveAsync deveria devolver o keyInfo anterior")

	local afterRemove: unknown
	runAsync(function()
		afterRemove = getAsync(store, "K1", nil)
	end)
	assert(afterRemove == nil, "GetAsync depois de RemoveAsync deveria devolver nil")

	local secondRemoveValue: unknown = "not yet set"
	local secondRemoveKeyInfo: unknown = "not yet set"
	runAsync(function()
		secondRemoveValue, secondRemoveKeyInfo = removeAsync(store, "K1")
	end)
	assert(secondRemoveValue == nil, "RemoveAsync sobre chave já removida deveria ser no-op idempotente (nil)")
	assert(secondRemoveKeyInfo == nil, "RemoveAsync sobre chave já removida deveria devolver keyInfo nil")
end)

test("IncrementAsync: primeira chamada parte de 0, chamadas seguintes acumulam", function()
	local store = getDataStore(dataStoreService, "Spec11", nil, nil)
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown

	local firstValue: unknown
	runAsync(function()
		firstValue = incrementAsync(store, "Counter", 5, nil, nil)
	end)
	assert(firstValue == 5, `1a chamada deveria partir de 0 (esperava 5, achou {tostring(firstValue)})`)

	local secondValue: unknown
	runAsync(function()
		secondValue = incrementAsync(store, "Counter", 3, nil, nil)
	end)
	assert(secondValue == 8, `2a chamada deveria acumular (esperava 8, achou {tostring(secondValue)})`)
end)

test("IncrementAsync sem delta explícito usa 1 (default do Roblox real)", function()
	local store = getDataStore(dataStoreService, "Spec12", nil, nil)
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown

	local value: unknown
	runAsync(function()
		value = incrementAsync(store, "Counter", nil, nil, nil)
	end)
	assert(value == 1, `delta default deveria ser 1, achou {tostring(value)}`)
end)

test("IncrementAsync erra quando o valor corrente NÃO é número", function()
	local store = getDataStore(dataStoreService, "Spec13", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown

	runAsync(function()
		setAsync(store, "NotANumber", "hello", nil, nil)
	end)

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return incrementAsync(store, "NotANumber", 1, nil, nil)
		end)
	end)

	assert(ok == false, "IncrementAsync deveria erro quando o valor corrente não é número")
	assert(
		string.find(tostring(err), "is not a number and cannot be incremented", 1, true) ~= nil,
		`mensagem deveria citar a incompatibilidade de tipo, recebeu: {err}`
	)
end)

test("chave/nome maior que 50 caracteres erra em GetAsync/SetAsync, ANTES de qualquer yield", function()
	local store = getDataStore(dataStoreService, "Spec14", nil, nil)
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown
	local longKey = string.rep("x", 51)

	-- Chamado FORA de scheduler:Spawn de propósito: se a validação de comprimento rodasse DEPOIS
	-- do AsyncCall.Yield, este teste erraria com a mensagem de engenharia interna de
	-- AsyncCall/Scheduler.Wait em vez da mensagem de limite de tamanho -- confirma a ORDEM
	-- (validar antes de yieldar).
	local ok, err = pcall(function()
		getAsync(store, longKey, nil)
	end)

	assert(not ok, "GetAsync com chave > 50 caracteres deveria erro")
	assert(
		string.find(tostring(err), "must be less than or equal to 50 characters", 1, true) ~= nil,
		`mensagem deveria citar o limite de 50 caracteres (Value.luau), recebeu: {err}`
	)
end)

test("SetAsync com valor não serializável (função) erra, ANTES de qualquer yield", function()
	local store = getDataStore(dataStoreService, "Spec15", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string

	local ok, err = pcall(function()
		setAsync(store, "K1", function() end, nil, nil)
	end)

	assert(not ok, "SetAsync com valor não serializável (função) deveria erro")
	assert(
		string.find(tostring(err), "cannot be stored in a DataStore", 1, true) ~= nil,
		`mensagem deveria citar a família de erro de serializabilidade (Value.luau), recebeu: {err}`
	)
end)

test("SetAsync(options = DataStoreSetOptions com metadata) propaga até DataStoreKeyInfo:GetMetadata()", function()
	local store = getDataStore(dataStoreService, "Spec16", nil, nil)
	local setAsync = store.SetAsync :: (self: Dynamic, key: string, value: unknown, userIds: unknown?, options: unknown?) -> string
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	local setOptions = (Services.new("DataStoreSetOptions", nil) :: unknown) :: Dynamic
	local setMetadata = setOptions.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	setMetadata(setOptions, { origin = "spec16" })

	runAsync(function()
		setAsync(store, "WithMeta", 42, nil, setOptions)
	end)

	local keyInfo: unknown
	runAsync(function()
		local _value, ki = getAsync(store, "WithMeta", nil)
		keyInfo = ki
	end)

	local keyInfoDynamic = keyInfo :: Dynamic
	local getMetadata = keyInfoDynamic.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local metadata = getMetadata(keyInfoDynamic)
	assert(metadata.origin == "spec16", `metadata deveria ter sido propagada de DataStoreSetOptions até DataStoreKeyInfo, achou {tostring(metadata.origin)}`)
end)

test("IncrementAsync(options = DataStoreIncrementOptions com metadata) também propaga metadata", function()
	local store = getDataStore(dataStoreService, "Spec17", nil, nil)
	local incrementAsync = store.IncrementAsync :: (self: Dynamic, key: string, delta: number?, userIds: unknown?, options: unknown?) -> ...unknown

	local incrementOptions = (Services.new("DataStoreIncrementOptions", nil) :: unknown) :: Dynamic
	local setMetadata = incrementOptions.SetMetadata :: (self: Dynamic, metadata: unknown) -> ()
	setMetadata(incrementOptions, { reason = "spec17" })

	local keyInfo: unknown
	runAsync(function()
		local _value, ki = incrementAsync(store, "Counter", 1, nil, incrementOptions)
		keyInfo = ki
	end)

	local keyInfoDynamic = keyInfo :: Dynamic
	local getMetadata = keyInfoDynamic.GetMetadata :: (self: Dynamic) -> { [string]: unknown }
	local metadata = getMetadata(keyInfoDynamic)
	assert(metadata.reason == "spec17", `metadata deveria ter sido propagada de DataStoreIncrementOptions, achou {tostring(metadata.reason)}`)
end)

test("chamar GetAsync FORA de uma thread gerida pelo Scheduler erra [LuauBench] (AsyncCall.Yield) -- confirma a fiação", function()
	local store = getDataStore(dataStoreService, "Spec18", nil, nil)
	local getAsync = store.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	-- Chamado direto na thread principal do processo do spec -- nunca passou por scheduler:Spawn.
	local ok, err = pcall(function()
		getAsync(store, "K1", nil)
	end)

	assert(not ok, "GetAsync fora de thread gerida deveria erro")
	assert(
		string.find(tostring(err), "[LuauBench]", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (AsyncCall.Yield), recebeu: {err}`
	)
	assert(
		string.find(tostring(err), "GlobalDataStore:GetAsync", 1, true) ~= nil,
		`mensagem deveria citar o label do método real, recebeu: {err}`
	)
end)

test("engenharia interna: um GlobalDataStore construído FORA de DataStoreService (sem _LuauBenchStoreId) erra em português ao chamar GetAsync", function()
	-- Via de engenharia (nunca alcançável por um script comum -- DataStoreService é a ÚNICA
	-- fábrica pública) -- confirma que `storeIdOf` não falha silenciosamente/com nil.
	local rawInstance = (Runtime.ClassRegistry.NewEngineInstance("GlobalDataStore", nil) :: unknown) :: Dynamic
	local getAsync = rawInstance.GetAsync :: (self: Dynamic, key: string, options: unknown?) -> ...unknown

	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			return getAsync(rawInstance, "K1", nil)
		end)
	end)

	assert(ok == false, "GetAsync sobre uma instância sem _LuauBenchStoreId deveria erro")
	assert(
		string.find(tostring(err), "_LuauBenchStoreId", 1, true) ~= nil,
		`mensagem de engenharia interna deveria citar a chave ausente, recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
