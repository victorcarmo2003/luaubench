--!strict

--[[
	Teste da task-runtime-005 (DataModel: raiz da árvore, equivalente a `game`).

	`ClassDescriptor` de teste registrado ad-hoc usa o formato NOVO de ClassRegistry
	(`Initialize: ((instance) -> ())?`, sem `Construct` — ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-04 (2)"), já em vigor desde task-runtime-013.

	Cobre o acceptance completo: `DataModel.new()` cria uma raiz válida com a cadeia de classe
	decidida explicitamente (DataModel -> ServiceProvider -> Instance, não o default de
	`NewBase`); `GetService` cria o singleton na primeira chamada, parenteia direto sob a raiz
	com Name == ClassName, e devolve o MESMO objeto em chamadas seguintes; `GetService` de uma
	classe registrada com `IsService = false` erra claramente; `GetService` de uma classe nunca
	registrada erra claramente; `FindService` nunca cria (nil antes da criação), só consulta
	(mesmo singleton depois); GetService/FindService ficam protegidos contra sobrescrita
	(mesma disciplina de SetClassMethods usada por classe de `services`, task-runtime-016).

	Roda com `lune run src/runtime/DataModel.spec.luau`. Depende de Instance.luau
	(task-runtime-002) e ClassRegistry.luau (task-runtime-004/013), ambos já presentes.
]]

local process = require("@lune/process")
local InstanceModule = require("./Instance")
local ClassRegistry = require("./ClassRegistry")
local DataModel = require("./DataModel")

type Instance = InstanceModule.Instance
type ClassDescriptor = ClassRegistry.ClassDescriptor
type DataModel = DataModel.DataModel

local passedCount = 0
local totalCount = 0

-- Mesmo padrão dos demais specs do runtime: roda cada teste imediatamente, deixa um assert que
-- falhar estourar pra fora do chunk (traceback + exit code != 0 do próprio Lune).
local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Descriptor de teste no formato NOVO: `Initialize` é opcional, recebe a instância JÁ criada e
-- JÁ com a cadeia de classes aplicada por `ClassRegistry.new` — nunca cria nem devolve nada.
local function makeServiceDescriptor(className: string, isService: boolean): ClassDescriptor
	return {
		ClassName = className,
		SuperClassName = nil,
		IsAbstract = false,
		IsService = isService,
		Initialize = nil,
	}
end

test("DataModel.new() cria uma raiz válida com Name/ClassName corretos", function()
	local dataModel = DataModel.new()
	assert(dataModel ~= nil, "DataModel.new() nunca deveria devolver nil")
	assert(dataModel.ClassName == "DataModel", "ClassName da raiz deveria ser 'DataModel'")
	assert(dataModel.Name == "DataModel", `Name deveria cair para o ClassName por default, recebeu: {dataModel.Name}`)
	assert(dataModel.Parent == nil, "a raiz não tem Parent")
end)

test("cadeia de classe da raiz é DataModel -> ServiceProvider -> Instance, decidida explicitamente (não o default de NewBase)", function()
	local dataModel = DataModel.new()
	assert(dataModel:IsA("DataModel"), "deveria bater com o próprio ClassName")
	assert(
		dataModel:IsA("ServiceProvider"),
		"cadeia deveria incluir 'ServiceProvider' (decisão explícita desta tarefa) -- se isto falhar, o default de NewBase ({'DataModel','Instance'}) voltou a valer implicitamente"
	)
	assert(dataModel:IsA("Instance"), "cadeia deveria terminar em Instance")
	assert(not dataModel:IsA("TestClasseNaoRelacionada"), "não deveria bater com classe fora da cadeia")
end)

test("GetService cria o singleton na primeira chamada e devolve o mesmo objeto em chamadas seguintes", function()
	ClassRegistry.Register(makeServiceDescriptor("TestServiceSingleton", true))
	local dataModel = DataModel.new()

	local first = dataModel:GetService("TestServiceSingleton")
	assert(first ~= nil, "GetService nunca deveria devolver nil para um Service válido")
	assert(first.ClassName == "TestServiceSingleton", "ClassName do singleton deveria ser o da classe pedida")
	assert(first.Name == "TestServiceSingleton", "Name do singleton deveria cair para o ClassName (Name == ClassName)")
	assert(first.Parent == dataModel, "o singleton deveria ser parenteado direto sob a raiz")
	assert(dataModel:FindFirstChild("TestServiceSingleton") == first, "o singleton deveria aparecer como filho direto da raiz")

	local second = dataModel:GetService("TestServiceSingleton")
	assert(second == first, "chamadas seguintes de GetService deveriam devolver o MESMO objeto, não recriar")
end)

test("GetService de uma classe registrada com IsService = false erra claramente", function()
	ClassRegistry.Register(makeServiceDescriptor("TestNaoService", false))
	local dataModel = DataModel.new()

	local ok, err = pcall(function()
		return dataModel:GetService("TestNaoService")
	end)

	assert(not ok, "GetService de uma classe com IsService = false deveria erro, nunca devolver silenciosamente")
	assert(
		string.find(tostring(err), "não é um Service") ~= nil,
		`mensagem de erro deveria dizer que a classe não é um Service, recebeu: {err}`
	)
end)

test("GetService de uma classe nunca registrada erra claramente", function()
	local dataModel = DataModel.new()

	local ok, err = pcall(function()
		return dataModel:GetService("TestClasseInexistenteParaService")
	end)

	assert(not ok, "GetService de classe não registrada deveria erro, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(err), "não registrada") ~= nil,
		`mensagem de erro deveria dizer 'não registrada', recebeu: {err}`
	)
end)

test("FindService nunca cria: nil antes de qualquer GetService, mesmo singleton depois", function()
	ClassRegistry.Register(makeServiceDescriptor("TestServiceFind", true))
	local dataModel = DataModel.new()

	assert(dataModel:FindService("TestServiceFind") == nil, "FindService não deveria criar nada antes de GetService")

	local created = dataModel:GetService("TestServiceFind")
	assert(dataModel:FindService("TestServiceFind") == created, "FindService deveria devolver o singleton já criado por GetService")
end)

test("FindService de uma classe nunca instanciada continua nil, mesmo se registrada como Service", function()
	ClassRegistry.Register(makeServiceDescriptor("TestServiceNuncaCriado", true))
	local dataModel = DataModel.new()

	assert(dataModel:FindService("TestServiceNuncaCriado") == nil, "FindService nunca cria -- classe registrada mas nunca pedida via GetService continua ausente")
end)

test("cada DataModel.new() é uma raiz independente -- GetService de uma não vaza para a outra", function()
	ClassRegistry.Register(makeServiceDescriptor("TestServiceIsolamento", true))
	local dataModelA = DataModel.new()
	local dataModelB = DataModel.new()

	local serviceA = dataModelA:GetService("TestServiceIsolamento")
	assert(dataModelB:FindService("TestServiceIsolamento") == nil, "singleton de uma raiz não deveria aparecer na outra")
	assert(serviceA.Parent == dataModelA, "singleton deveria continuar parenteado só sob a raiz que o criou")
end)

test("GetService/FindService ficam protegidos contra sobrescrita (mesma disciplina de SetClassMethods)", function()
	local dataModel = DataModel.new()

	local dynamic = (dataModel :: unknown) :: { [string]: unknown }
	local ok, err = pcall(function()
		dynamic.GetService = nil
	end)

	assert(not ok, "sobrescrever GetService deveria erro, igual a qualquer outro método de Instance")
	assert(
		string.find(tostring(err), "GetService") ~= nil,
		`mensagem de erro deveria mencionar 'GetService', recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
