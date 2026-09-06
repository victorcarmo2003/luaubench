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
	classe registrada com `IsService = false` devolve `nil`, sem erro (task-runtime-030, ver
	abaixo); `GetService` de uma classe nunca registrada, sem resolvedor instalado, erra com
	mensagem de engenharia interna; `FindService` nunca cria (nil antes da criação), só consulta
	(mesmo singleton depois); GetService/FindService ficam protegidos contra sobrescrita
	(mesma disciplina de SetClassMethods usada por classe de `services`, task-runtime-016).

	Roda com `lune run src/runtime/DataModel.spec.luau`. Depende de Instance.luau
	(task-runtime-002) e ClassRegistry.luau (task-runtime-004/013), ambos já presentes.

	Testes NOVOS da task-runtime-023 (ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md,
	"Revisão pós-integração 2026-09-05 (4)"), no final do arquivo: `makeServiceDescriptor` deixou
	de hardcodar `IsAbstract = false` (o fixture impossível que deixou o bug passar por três
	revisões -- ver comentário da função) e os testes de GetService já rodam contra a forma
	realista por causa disso; os 4 novos cobrem, explicitamente: (k) regressão nomeada pelo bug
	-- GetService constrói o singleton com IsAbstract=true (a forma real de toda Service); (l)
	ClassRegistry.new sobre o MESMO descriptor continua errando; (m) a forma StarterPlayerScripts
	(IsAbstract=true, IsService=false) -- construível por NewEngineInstance, rejeitada por .new,
	GetService continua errando por IsService==false.

	MUDANÇAS da task-runtime-030 (ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md,
	"Revisão pós-integração 2026-09-05 (5)"): `GetService` passa a devolver `Instance?`, não mais
	`Instance` -- uma classe registrada com `IsService = false` não erra mais, devolve `nil` (é o
	comportamento real do Roblox, confirmado por fonte primária). Isso inverte DOIS testes
	pré-existentes, marcados abaixo como TESTE-GATILHO: o de `IsService = false` (era erro, agora
	`nil`) e o de classe nunca registrada (o spec de `runtime` roda sem `services`, logo sem
	`UnknownClassResolver` instalado -- o veredito não pode ser calculado e o erro muda para a
	mensagem de engenharia interna que nomeia `Services.Bootstrap`). Um TERCEIRO teste
	pré-existente também precisou ser ajustado por decorrência direta da mesma mudança de
	comportamento -- não estava listado nominalmente na tarefa, mas é a MESMA forma
	(`IsService = false`, registrada) do primeiro teste-gatilho, então infringiria a suíte se
	deixado como estava: o teste (m) (`TestStarterPlayerScriptsShape`), cujo último bloco também
	esperava erro e passa a esperar `nil`. Cobertura NOVA no final do arquivo: um resolvedor FALSO
	instalado só a partir daquele ponto (por isso os testes-gatilho acima, que dependem de RODAR
	sem resolvedor, continuam antes dele na ordem do arquivo) cobrindo os três vereditos de
	`UnknownClassVerdict`, mais o teste de sequestro (`Folder` filho direto da raiz não é mais
	devolvido por `GetService`/`FindService`).
]]

local process = require("@lune/process")
local InstanceModule = require("./Instance")
local ClassRegistry = require("./ClassRegistry")
local DataModel = require("./DataModel")
local UnknownClassResolver = require("./UnknownClassResolver")
local Scheduler = require("./Scheduler")

type UnknownClassVerdict = UnknownClassResolver.UnknownClassVerdict

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
--
-- CORREÇÃO task-runtime-023 (O ACHADO MAIS IMPORTANTE da revisão que motivou esta tarefa -- ver
-- .claude/agents-memory/arquiteto-runtime-2026-09-04.md, "Revisão pós-integração 2026-09-05 (4)",
-- seção "O buraco de teste"): esta função hardcodava `IsAbstract = false` incondicionalmente. Um
-- `ClassDescriptor` com `IsService = true` E `IsAbstract = false` NÃO EXISTE no Roblox real --
-- nenhuma das 334 Services do dump tem essa forma (toda Service carrega a tag `NotCreatable`).
-- Os testes de GetService rodavam, verdes, contra um fixture que a realidade nunca produz -- é
-- por isso que três revisões não pegaram o bug de `GetService` chamando `ClassRegistry.new`
-- (que rejeita `IsAbstract` incondicionalmente).
--
-- Ganha o parâmetro `isAbstract` (opcional): quando omitido, o DEFAULT passa a ser `isService`
-- -- porque é exatamente o que um Service é (`IsService = true` -> `IsAbstract = true` por
-- default). Um Service com `IsAbstract = false` só aparece se algum teste passar o parâmetro
-- explicitamente, como exceção deliberada.
local function makeServiceDescriptor(className: string, isService: boolean, isAbstract: boolean?): ClassDescriptor
	return {
		ClassName = className,
		SuperClassName = nil,
		IsAbstract = if isAbstract ~= nil then isAbstract else isService,
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

-- TESTE-GATILHO (task-runtime-030): antes desta tarefa, esperava erro. Agora, igual ao Roblox
-- real (fonte primária: doc oficial, "will return nil if the className parameter is an existing
-- class, but the class is not a service") -- classe registrada, `IsService = false`, devolve
-- `nil` SEM erro. A inversão deste teste é o sinal de que a correção pegou.
test("GetService de uma classe registrada com IsService = false devolve nil, sem erro (igual ao Roblox real)", function()
	ClassRegistry.Register(makeServiceDescriptor("TestNaoService", false))
	local dataModel = DataModel.new()

	local result = dataModel:GetService("TestNaoService")
	assert(result == nil, `GetService de uma classe com IsService = false deveria devolver nil, recebeu: {result}`)
end)

-- TESTE-GATILHO (task-runtime-030): antes desta tarefa, esperava a mensagem "não registrada" em
-- português. Este spec de `runtime` roda sem `services` carregado, logo SEM
-- `UnknownClassResolver` instalado -- `GetService` de uma classe desconhecida agora passa pelo
-- ramo "nenhum resolvedor instalado", erro de ENGENHARIA INTERNA que nomeia
-- `Services.Register()`/`Services.Bootstrap()`. Precisa rodar ANTES de qualquer teste deste
-- arquivo instalar um resolvedor falso (ver cobertura nova no final) -- depois disso a mensagem
-- mudaria de novo, porque passaria a existir resolvedor.
test("GetService de uma classe nunca registrada, sem resolvedor instalado, erra com mensagem de engenharia interna citando Services.Bootstrap", function()
	local dataModel = DataModel.new()

	local ok, err = pcall(function()
		return dataModel:GetService("TestClasseInexistenteParaService")
	end)

	assert(not ok, "GetService de classe não registrada, sem resolvedor, deveria erro, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(err), "nenhum resolvedor de classe desconhecida instalado") ~= nil,
		`mensagem de erro deveria dizer 'nenhum resolvedor de classe desconhecida instalado', recebeu: {err}`
	)
	assert(
		string.find(tostring(err), "Services.Bootstrap") ~= nil,
		`mensagem de erro deveria citar Services.Bootstrap, recebeu: {err}`
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
	assert(serviceA ~= nil, "GetService nunca deveria devolver nil para um Service válido")
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

--[[
	Testes NOVOS da task-runtime-023 -- ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md,
	"Revisão pós-integração 2026-09-05 (4) — `NotCreatable` vs. abstrata: dois construtores em
	`ClassRegistry`". Nenhum dos testes acima foi alterado além de `makeServiceDescriptor`.
]]

-- (k) TESTE DE REGRESSÃO nomeado pelo bug: GetService constrói o singleton para um descriptor
-- com IsAbstract = true -- a forma real de TODA Service do Roblox (334/334 carregam a tag
-- NotCreatable). Este é o teste que falhava ANTES desta tarefa (GetService passava por
-- ClassRegistry.new, que rejeita IsAbstract incondicionalmente).
test(
	"REGRESSÃO (task-runtime-023): GetService constrói o singleton mesmo com IsAbstract = true, a forma real de toda Service do Roblox",
	function()
		ClassRegistry.Register(makeServiceDescriptor("TestServiceNotCreatable", true, true))
		local dataModel = DataModel.new()

		local service = dataModel:GetService("TestServiceNotCreatable")
		assert(service ~= nil, "GetService nunca deveria devolver nil para um Service real (IsService=true, IsAbstract=true)")
		assert(service.ClassName == "TestServiceNotCreatable", "ClassName do singleton deveria ser o da classe pedida")
		assert(service.Name == "TestServiceNotCreatable", "Name do singleton deveria cair para o ClassName")
		assert(service.Parent == dataModel, "o singleton deveria ser parenteado direto sob a raiz")

		local second = dataModel:GetService("TestServiceNotCreatable")
		assert(second == service, "chamadas seguintes deveriam devolver o MESMO objeto, não recriar")
	end
)

-- (l) ClassRegistry.new sobre o MESMO descriptor continua errando -- as duas vias divergirem é
-- o ponto inteiro da decisão do arquiteto (opção (b) refinada, não opção (a) de remover a
-- guarda).
test(
	"ClassRegistry.new sobre o MESMO descriptor (IsService=true, IsAbstract=true) continua errando -- as duas vias divergem de propósito",
	function()
		ClassRegistry.Register(makeServiceDescriptor("TestServiceNotCreatableDirectNew", true, true))

		local ok, err = pcall(function()
			return ClassRegistry.new("TestServiceNotCreatableDirectNew", nil)
		end)

		assert(not ok, "ClassRegistry.new de um Service (NotCreatable) deveria continuar errando -- é a via pública, com a guarda")
		assert(
			string.find(tostring(err), "NewEngineInstance") ~= nil,
			`mensagem de erro deveria citar 'NewEngineInstance', recebeu: {err}`
		)
	end
)

-- (m) Forma StarterPlayerScripts (IsAbstract=true, IsService=false): construível por
-- NewEngineInstance, rejeitada por .new. GetService dela NÃO erra mais (task-runtime-030) --
-- devolve `nil`, igual a qualquer classe registrada com IsService=false, porque a guarda de
-- GetService continua sendo IsService, nunca IsAbstract. AJUSTE task-runtime-030 (não estava
-- listado nominalmente na tarefa como teste-gatilho, mas é a MESMA forma do teste-gatilho
-- "IsService=false" acima -- deixar como estava quebraria a suíte): o bloco final passa de
-- "espera erro" para "espera nil".
test(
	"forma StarterPlayerScripts (IsAbstract=true, IsService=false): NewEngineInstance constrói, .new rejeita, GetService devolve nil (IsService==false, não erra mais)",
	function()
		ClassRegistry.Register(makeServiceDescriptor("TestStarterPlayerScriptsShape", false, true))
		local dataModel = DataModel.new()

		local instance = ClassRegistry.NewEngineInstance("TestStarterPlayerScriptsShape", nil)
		assert(instance ~= nil, "NewEngineInstance deveria construir a forma StarterPlayerScripts (IsAbstract=true, IsService=false)")

		local okNew = pcall(function()
			return ClassRegistry.new("TestStarterPlayerScriptsShape", nil)
		end)
		assert(not okNew, "ClassRegistry.new deveria rejeitar a forma StarterPlayerScripts -- é NotCreatable")

		local service = dataModel:GetService("TestStarterPlayerScriptsShape")
		assert(
			service == nil,
			`GetService de uma classe com IsService=false deveria devolver nil, mesmo sendo IsAbstract=true, recebeu: {service}`
		)
	end
)

--[[
	Cobertura NOVA da task-runtime-030 -- resolvedor FALSO instalado a partir DAQUI, de propósito
	depois dos dois testes-gatilho acima (que dependem de rodar SEM resolvedor instalado). A
	partir deste ponto do arquivo, toda classe desconhecida de `ClassRegistry` passa a ser
	classificada por esta função em vez de cair no ramo "nenhum resolvedor instalado" -- não há
	`UnknownClassResolver.Unset`, então a instalação vale para o resto do processo (mesma
	invariante documentada no cabeçalho do módulo).

	Pura e total (contrato obrigatório do resolvedor, ver UnknownClassResolver.luau): tabela fixa,
	sem efeito colateral, sem `error()`, resposta para qualquer string (o `else` final cobre até
	`""`).
]]
local FAKE_NOT_A_SERVICE: { [string]: boolean } = {
	-- "Frame" é o próprio exemplo usado no desenho/pesquisa: classe real do dump, sem tag Service.
	Frame = true,
}
local FAKE_NOT_SIMULATED: { [string]: string } = {
	-- Mensagem arbitrária para fins de teste -- `runtime` nunca formata isto, só repassa
	-- verbatim (ver GetService, ramo ServiceNotSimulated). O formato real vem de
	-- `services/init.luau:unsimulatedClassMessage`, fora do território desta tarefa.
	TestServiceAindaNaoSimulado = "[LuauBench] TestServiceAindaNaoSimulado exists in the Roblox API Dump but is not simulated by LuauBench yet",
}

UnknownClassResolver.Set(function(className: string): UnknownClassVerdict
	if FAKE_NOT_A_SERVICE[className] then
		return { Kind = "NotAService" } :: UnknownClassVerdict
	end
	local message = FAKE_NOT_SIMULATED[className]
	if message ~= nil then
		return { Kind = "ServiceNotSimulated", Message = message } :: UnknownClassVerdict
	end
	return { Kind = "NotAClass" } :: UnknownClassVerdict
end)

test("GetService com resolvedor instalado: veredito NotAClass erra com a família Roblox real ('X' is not a valid Service name)", function()
	local dataModel = DataModel.new()

	local ok, err = pcall(function()
		return dataModel:GetService("TestNomeQueNaoExisteNoDump")
	end)

	assert(not ok, "GetService de um nome que não é classe nenhuma deveria erro")
	assert(
		string.find(tostring(err), "'TestNomeQueNaoExisteNoDump' is not a valid Service name", 1, true) ~= nil,
		`mensagem de erro deveria ser exatamente a família Roblox real (aspas simples, sem prefixo), recebeu: {err}`
	)
end)

test("GetService com resolvedor instalado: veredito NotAService devolve nil, sem erro (classe real do dump, sem tag Service)", function()
	local dataModel = DataModel.new()

	local result = dataModel:GetService("Frame")
	assert(result == nil, `GetService('Frame') deveria devolver nil (classe real, sem Service), recebeu: {result}`)
end)

test("GetService com resolvedor instalado: veredito ServiceNotSimulated erra com a Message do veredito, verbatim", function()
	local dataModel = DataModel.new()

	local ok, err = pcall(function()
		return dataModel:GetService("TestServiceAindaNaoSimulado")
	end)

	assert(not ok, "GetService de uma Service real ainda não simulada deveria erro")
	assert(
		string.find(tostring(err), FAKE_NOT_SIMULATED.TestServiceAindaNaoSimulado, 1, true) ~= nil,
		`runtime deveria repassar a Message do veredito verbatim, sem reformatar, recebeu: {err}`
	)
end)

-- Teste de SEQUESTRO (task-runtime-030): antes da reordenação, `GetService`/`FindService`
-- devolviam o primeiro filho da raiz cujo CLASSNAME batesse, mesmo sem ser Service. Nomeado com
-- Name diferente de "Folder" de propósito -- prova que o gate é por ClassName, nunca por Name.
test("SEQUESTRO: um Folder filho direto da raiz não é devolvido por GetService nem por FindService", function()
	ClassRegistry.Register(makeServiceDescriptor("Folder", false))
	local dataModel = DataModel.new()

	local folder = ClassRegistry.new("Folder", "QualquerCoisa")
	folder.Parent = dataModel
	assert(dataModel:FindFirstChild("QualquerCoisa") == folder, "sanity check: o Folder deveria mesmo estar parentado sob a raiz")

	assert(
		dataModel:GetService("Folder") == nil,
		"GetService('Folder') deveria devolver nil -- nunca o Folder criado pelo usuário, mesmo ele existindo como filho direto da raiz"
	)
	assert(
		dataModel:FindService("Folder") == nil,
		"FindService('Folder') deveria devolver nil pelo mesmo motivo -- mesmo gate de GetService"
	)
end)

--[[
	Testes NOVOS da task-runtime-034 (JobId/PlaceId/GameId/PlaceVersion) -- ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.3.3".
]]

test("JobId/PlaceId/GameId/PlaceVersion têm os valores esperados", function()
	local dataModel = DataModel.new()
	assert(typeof(dataModel.JobId) == "string", `JobId deveria ser string, recebeu {typeof(dataModel.JobId)}`)
	assert(#dataModel.JobId > 0, "JobId não deveria ser string vazia")
	assert(dataModel.PlaceId == 0, `PlaceId deveria ser 0, recebeu {dataModel.PlaceId}`)
	assert(dataModel.GameId == 0, `GameId deveria ser 0, recebeu {dataModel.GameId}`)
	assert(dataModel.PlaceVersion == 0, `PlaceVersion deveria ser 0, recebeu {dataModel.PlaceVersion}`)
end)

test("JobId é estável dentro do processo -- duas raízes do MESMO processo compartilham o mesmo JobId", function()
	local dataModelA = DataModel.new()
	local dataModelB = DataModel.new()
	assert(
		dataModelA.JobId == dataModelB.JobId,
		`duas raízes do mesmo processo deveriam compartilhar o mesmo JobId, recebeu '{dataModelA.JobId}' e '{dataModelB.JobId}'`
	)
end)

test("escrever em JobId/PlaceId/GameId/PlaceVersion erra com a família Roblox real de propriedade somente-leitura", function()
	local dataModel = DataModel.new()
	local dynamic = (dataModel :: unknown) :: { [string]: unknown }

	for _, key in { "JobId", "PlaceId", "GameId", "PlaceVersion" } do
		local ok, err = pcall(function()
			dynamic[key] = "hijacked"
		end)
		assert(not ok, `escrever em {key} deveria erro -- é ReadOnly no dump`)
		assert(
			string.find(tostring(err), "Property is read only", 1, true) ~= nil,
			`mensagem de erro ao escrever em {key} deveria conter 'Property is read only', recebeu: {err}`
		)
	end
end)

--[[
	Testes NOVOS da task-runtime-033 (BindToClose + RunBindToCloseCallbacks) -- ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.8".
]]

test("RunBindToCloseCallbacks sem nenhum BindToClose registrado é no-op", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	-- Não deveria erro nem travar -- só devolve na hora, sem nenhum handle para esperar.
	DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
end)

test("BindToClose: callback simples roda antes de RunBindToCloseCallbacks devolver o controle", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local ran = false

	dataModel:BindToClose(function()
		ran = true
	end)

	DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
	assert(ran, "o callback simples deveria ter rodado")
end)

test("BindToClose: callback que yielda (Scheduler:Wait) só conta como terminado depois de retornar de verdade", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local finished = false

	dataModel:BindToClose(function()
		scheduler:Wait(0.01)
		finished = true
	end)

	DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
	assert(finished, "o callback deveria ter completado (inclusive o yield) antes de RunBindToCloseCallbacks devolver")
end)

test("BindToClose: dois callbacks registrados na mesma raiz rodam os dois", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local ranFirst = false
	local ranSecond = false

	dataModel:BindToClose(function()
		scheduler:Wait(0.01)
		ranFirst = true
	end)
	dataModel:BindToClose(function()
		ranSecond = true
	end)

	DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
	assert(ranFirst, "o primeiro callback (com yield) deveria ter rodado até o fim")
	assert(ranSecond, "o segundo callback deveria ter rodado até o fim")
end)

test("BindToClose: erro dentro de um callback não impede os demais de rodar nem propaga -- sai por ThreadError", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local erroredCallbackRan = false
	local otherCallbackRan = false
	local threadErrors: { string } = {}

	scheduler.ThreadError:Connect(function(_thread, message: string)
		table.insert(threadErrors, message)
	end)

	dataModel:BindToClose(function()
		erroredCallbackRan = true
		error("callback de BindToClose falhou de propósito (teste)")
	end)
	dataModel:BindToClose(function()
		scheduler:Wait(0.01)
		otherCallbackRan = true
	end)

	local ok = pcall(function()
		DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
	end)

	assert(ok, "RunBindToCloseCallbacks nunca deveria propagar o erro de um callback")
	assert(erroredCallbackRan, "o callback que erra deveria ter rodado (e errado) mesmo assim")
	assert(otherCallbackRan, "o outro callback deveria ter rodado até o fim, sem ser afetado pelo erro do primeiro")
	assert(#threadErrors == 1, `deveria ter reportado exatamente 1 ThreadError, recebeu {#threadErrors}`)
	assert(
		string.find(threadErrors[1], "callback de BindToClose falhou de propósito", 1, true) ~= nil,
		`ThreadError deveria conter a mensagem original do erro, recebeu: {threadErrors[1]}`
	)
end)

test("BindToClose fica protegido contra sobrescrita (mesma disciplina de GetService/FindService)", function()
	local dataModel = DataModel.new()
	local dynamic = (dataModel :: unknown) :: { [string]: unknown }
	local ok, err = pcall(function()
		dynamic.BindToClose = nil
	end)
	assert(not ok, "sobrescrever BindToClose deveria erro, igual a qualquer outro método de Instance")
	assert(
		string.find(tostring(err), "BindToClose") ~= nil,
		`mensagem de erro deveria mencionar 'BindToClose', recebeu: {err}`
	)
end)

--[[
	Testes NOVOS da task-runtime-038 (fix real do achado de task-cli-033 -- ver campo `result`
	daquela task em .claude/tasks.json e o bloco dedicado no cabeçalho de DataModel.luau).
	`onCallbackError` filtra por identidade de THREAD PRÓPRIA: só as threads que
	`RunBindToCloseCallbacks` cria via `scheduler:Spawn` para os callbacks de `BindToClose`
	registrados -- nunca uma thread alheia que por acaso seja retomada e erre durante a mesma
	janela (o cenário exato do bug: `scheduler:Run` dentro desta função é um laço GENÉRICO que
	drena TODAS as threads vivas do Scheduler recebido).
]]

test("onCallbackError OMITIDO: comportamento observável idêntico ao de antes (erro de callback ainda só sai por ThreadError, nada mais é chamado)", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local threadErrors: { string } = {}

	scheduler.ThreadError:Connect(function(_thread, message: string)
		table.insert(threadErrors, message)
	end)

	dataModel:BindToClose(function()
		error("callback de BindToClose falhou de propósito (teste onCallbackError omitido)")
	end)

	local ok = pcall(function()
		DataModel.RunBindToCloseCallbacks(dataModel, scheduler)
	end)

	assert(ok, "RunBindToCloseCallbacks nunca deveria propagar o erro de um callback, com ou sem onCallbackError")
	assert(#threadErrors == 1, `deveria ter reportado exatamente 1 ThreadError (via o listener externo do teste), recebeu {#threadErrors}`)
end)

test("onCallbackError FORNECIDO: erro de um callback de BindToClose registrado nesta mesma chamada dispara onCallbackError", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local captured: { { thread: thread, message: string } } = {}

	dataModel:BindToClose(function()
		error("callback de BindToClose falhou de propósito (teste onCallbackError fornecido)")
	end)

	DataModel.RunBindToCloseCallbacks(dataModel, scheduler, function(erroredThread: thread, message: string)
		table.insert(captured, { thread = erroredThread, message = message })
	end)

	assert(#captured == 1, `onCallbackError deveria ter sido chamado exatamente 1 vez, recebeu {#captured}`)
	assert(
		string.find(captured[1].message, "callback de BindToClose falhou de propósito", 1, true) ~= nil,
		`mensagem repassada a onCallbackError deveria conter o erro original, recebeu: {captured[1].message}`
	)
end)

test(
	"onCallbackError NUNCA dispara para erro de thread ALHEIA (não criada por esta chamada de RunBindToCloseCallbacks), mesmo resolvida durante a mesma janela",
	function()
		local scheduler = Scheduler.new()
		local dataModel = DataModel.new()
		local callbackErrorCalls = 0
		local foreignThreadErrors: { string } = {}

		-- Reproduz a causa raiz do bug de task-cli-033: uma thread ALHEIA (aqui, simulando o
		-- script principal) fica suspensa em `scheduler:Wait` e só é retomada (e erra) quando
		-- `scheduler:Run` roda de novo por dentro de `RunBindToCloseCallbacks` -- exatamente a
		-- janela em que o laço genérico de `Run` drena QUALQUER thread viva do Scheduler, não só
		-- as de BindToClose.
		scheduler:Spawn(function()
			scheduler:Wait(0.01)
			error("erro de thread alheia -- NÃO deveria disparar onCallbackError")
		end)

		-- Escuta o ThreadError cru só para confirmar que o erro alheio de fato ocorre (sanity
		-- check independente do filtro sob teste) -- não é o listener sob teste.
		scheduler.ThreadError:Connect(function(_thread, message: string)
			table.insert(foreignThreadErrors, message)
		end)

		-- Callback de BindToClose de verdade, que também yielda, para garantir que a janela de
		-- `RunBindToCloseCallbacks` continua aberta tempo suficiente para a thread alheia acima
		-- ser retomada e errar durante o mesmo `scheduler:Run`.
		dataModel:BindToClose(function()
			scheduler:Wait(0.02)
		end)

		DataModel.RunBindToCloseCallbacks(dataModel, scheduler, function(_erroredThread: thread, _message: string)
			callbackErrorCalls += 1
		end)

		assert(#foreignThreadErrors == 1, `sanity check: a thread alheia deveria mesmo ter errado durante a janela, recebeu {#foreignThreadErrors} ThreadError(s)`)
		assert(
			callbackErrorCalls == 0,
			`onCallbackError NUNCA deveria disparar para erro de thread alheia, recebeu {callbackErrorCalls} chamada(s)`
		)
	end
)

test("onCallbackError: desconecta seu próprio listener antes de devolver -- erro de thread alheia DEPOIS de RunBindToCloseCallbacks retornar não é mais observado por ele", function()
	local scheduler = Scheduler.new()
	local dataModel = DataModel.new()
	local callbackErrorCalls = 0

	dataModel:BindToClose(function() end)

	DataModel.RunBindToCloseCallbacks(dataModel, scheduler, function(_erroredThread: thread, _message: string)
		callbackErrorCalls += 1
	end)

	-- Depois que RunBindToCloseCallbacks já retornou: uma thread nova, alheia, que erra no mesmo
	-- scheduler não deveria acionar o listener já desconectado.
	scheduler:Spawn(function()
		error("erro depois da janela de BindToClose já ter fechado")
	end)

	assert(callbackErrorCalls == 0, `listener deveria ter sido desconectado ao final de RunBindToCloseCallbacks, recebeu {callbackErrorCalls} chamada(s) depois da janela`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
