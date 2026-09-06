--!strict

--[[
	Teste da task-services-001 (esqueleto de `services`: Context.luau). Cobre o acceptance do
	board: "Context erra claro quando consultado antes de Bootstrap" -- e, além disso, o
	comportamento positivo (Set armazena, Get* devolve o que foi passado, Set de novo apenas
	sobrescreve).

	Roda com `lune run src/services/Context.spec.luau`. Testes ordenados de propósito: o de
	"antes de Set" precisa rodar ANTES de qualquer `Context.Set`, já que Context é estado de
	módulo sem reset (mesma invariante de ClassRegistry) -- este arquivo roda como processo Lune
	próprio (`lune run` por spec), então não há vazamento de estado entre specs diferentes.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Context = require("./Context")
local Types = require("./Types")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("IsSet() é false e GetScheduler/GetDataModel erram claramente ANTES de qualquer Set", function()
	assert(not Context.IsSet(), "IsSet() deveria ser false antes de qualquer Context.Set")

	local okScheduler, errScheduler = pcall(function()
		return Context.GetScheduler()
	end)
	assert(not okScheduler, "GetScheduler() deveria erro antes de Bootstrap/Set, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(errScheduler), "Bootstrap", 1, true) ~= nil,
		`mensagem de erro deveria mencionar 'Bootstrap', recebeu: {errScheduler}`
	)

	local okDataModel, errDataModel = pcall(function()
		return Context.GetDataModel()
	end)
	assert(not okDataModel, "GetDataModel() deveria erro antes de Bootstrap/Set, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(errDataModel), "Bootstrap", 1, true) ~= nil,
		`mensagem de erro deveria mencionar 'Bootstrap', recebeu: {errDataModel}`
	)

	-- task-services-031: DIFERENTE de GetScheduler/GetDataModel acima, GetCloudPersistence NUNCA
	-- erra -- nem mesmo ANTES de qualquer Context.Set (Bootstrap nunca chamado). A ausência do port
	-- é estado normal, não erro de engenharia (ver o comentário de Context.GetCloudPersistence).
	local okCloudPersistence, cloudPersistence = pcall(function()
		return Context.GetCloudPersistence()
	end)
	assert(okCloudPersistence, `GetCloudPersistence() NUNCA deveria erro, mesmo antes de Bootstrap/Set, recebeu erro: {tostring(cloudPersistence)}`)
	assert(cloudPersistence == nil, "GetCloudPersistence() antes de qualquer Set deveria devolver nil")
end)

test("Set armazena e GetScheduler/GetDataModel devolvem exatamente os valores passados", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()

	Context.Set({ scheduler = scheduler, dataModel = dataModel })

	assert(Context.IsSet(), "IsSet() deveria ser true depois de Context.Set")
	assert(Context.GetScheduler() == scheduler, "GetScheduler() deveria devolver exatamente o Scheduler passado a Set")
	assert(Context.GetDataModel() == dataModel, "GetDataModel() deveria devolver exatamente o DataModel passado a Set")

	-- task-services-031: `CloudPersistence` OMITIDO nas options acima -- `nil`/omitido é o
	-- comportamento de hoje ("--no-persist"), nunca um erro.
	assert(Context.GetCloudPersistence() == nil, "GetCloudPersistence() deveria devolver nil quando BootstrapOptions.CloudPersistence foi omitido")
end)

-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10): Context.GetCloudPersistence
-- é o canal ÚNICO de leitura de BootstrapOptions.CloudPersistence -- confirma que devolve
-- EXATAMENTE a referência passada a Set (mesma disciplina de GetScheduler/GetDataModel acima),
-- quando o port É passado.
test("Set com CloudPersistence presente: GetCloudPersistence devolve exatamente o port passado", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()

	local fakeCloudPersistence: Types.CloudPersistence = {
		Load = function(_document: string): string?
			return nil
		end,
		Save = function(_document: string, _contents: string): () end,
	}

	Context.Set({ scheduler = scheduler, dataModel = dataModel, CloudPersistence = fakeCloudPersistence })

	assert(Context.GetCloudPersistence() == fakeCloudPersistence, "GetCloudPersistence() deveria devolver exatamente o port passado a Set")
end)

test("uma segunda chamada a Set apenas sobrescreve a referência, nunca erra", function()
	local schedulerA = Runtime.Scheduler.new()
	local dataModelA = Runtime.DataModel.new()
	Context.Set({ scheduler = schedulerA, dataModel = dataModelA })

	local schedulerB = Runtime.Scheduler.new()
	local dataModelB = Runtime.DataModel.new()

	local ok = pcall(function()
		Context.Set({ scheduler = schedulerB, dataModel = dataModelB })
	end)
	assert(ok, "uma segunda chamada a Context.Set não deveria erro (Bootstrap precisa ser seguro de chamar de novo)")

	assert(Context.GetScheduler() == schedulerB, "depois da segunda chamada, GetScheduler() deveria devolver o valor mais recente")
	assert(Context.GetDataModel() == dataModelB, "depois da segunda chamada, GetDataModel() deveria devolver o valor mais recente")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
