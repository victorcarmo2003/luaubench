--!strict

--[[
	Teste da task-runtime-004 (ClassRegistry: registro central de classes), migrado pela
	task-runtime-013 para o contrato novo de ClassDescriptor (Initialize opcional em vez de
	Construct — ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	pós-integração 2026-09-04 (2) — contrato ClassDescriptor.Construct").

	Cobre os quatro comportamentos originais do acceptance (Register rejeita ClassName
	duplicado; Get/IsRegistered refletem o estado do registro; new() erra claramente para
	classe não registrada e para classe abstrata, nunca nil silencioso; new() de uma classe com
	SuperClassName encadeado resolve a cadeia corretamente, testável via IsA), mais os testes
	novos exigidos pela correção de contrato:
	(a) regressão do achado ALTO — IsA de ancestral indireto responde certo DE DENTRO do
	    próprio Initialize (prova de que a ordem NewBase -> SetClassChain -> Initialize está
	    em vigor; teste desenhado para falhar se a ordem for revertida);
	(b) ciclo de herança mútuo captura erro via pcall, não trava;
	(c) auto-referência direta idem;
	(d) descriptor sem Initialize (campo nil) instancia normalmente;
	(e) Name default (ClassRegistry.new('X') -> Name=='X'; com nome explícito -> Name==nome).
	Mais os dois testes de robustez já existentes (ordem de registro fora de topológica,
	referência a superclasse nunca registrada).

	Roda com `lune run src/runtime/ClassRegistry.spec.luau`. Depende de Instance.luau
	(task-runtime-002, já presente) para os tipos/IsA usados nas asserções.
]]

local process = require("@lune/process")
local InstanceModule = require("./Instance")
local ClassRegistry = require("./ClassRegistry")

type Instance = InstanceModule.Instance
type ClassDescriptor = ClassRegistry.ClassDescriptor

local passedCount = 0
local totalCount = 0

-- Mesmo padrão de Instance.spec.luau/Signal.spec.luau: roda cada teste imediatamente e deixa
-- um assert que falhar estourar pra fora do chunk (traceback + exit code != 0 do próprio Lune).
local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Descriptor de teste no formato novo: Initialize é opcional e recebe a instância JÁ criada e
-- JÁ com a cadeia de classes aplicada por ClassRegistry.new — nunca cria nem devolve nada.
local function makeDescriptor(
	className: string,
	superClassName: string?,
	isAbstract: boolean,
	initialize: ((instance: Instance) -> ())?
): ClassDescriptor
	return {
		ClassName = className,
		SuperClassName = superClassName,
		IsAbstract = isAbstract,
		IsService = false,
		Initialize = initialize,
	}
end

-- Helper NOVO da task-runtime-016, usado só pelos testes de método de classe abaixo — não
-- reaproveita `makeDescriptor` de propósito, para não mudar a assinatura usada pelos 13 testes
-- já existentes (a tarefa só permite ACRESCENTAR teste novo, nunca alterar um existente).
local function makeDescriptorWithMethods(
	className: string,
	superClassName: string?,
	methods: InstanceModule.ClassMethods?,
	initialize: ((instance: Instance) -> ())?
): ClassDescriptor
	return {
		ClassName = className,
		SuperClassName = superClassName,
		IsAbstract = false,
		IsService = false,
		Methods = methods,
		Initialize = initialize,
	}
end

test("Register rejeita ClassName duplicado com erro claro", function()
	ClassRegistry.Register(makeDescriptor("TestDup", nil, false, nil))

	local ok, err = pcall(function()
		ClassRegistry.Register(makeDescriptor("TestDup", nil, false, nil))
	end)

	assert(not ok, "deveria erro ao registrar um ClassName já registrado")
	assert(string.find(tostring(err), "TestDup") ~= nil, `mensagem de erro deveria mencionar 'TestDup', recebeu: {err}`)
end)

test("Get/IsRegistered refletem o estado do registro", function()
	assert(not ClassRegistry.IsRegistered("TestNuncaRegistrada"), "classe nunca registrada não deveria constar")
	assert(ClassRegistry.Get("TestNuncaRegistrada") == nil, "Get de classe não registrada deveria ser nil")

	ClassRegistry.Register(makeDescriptor("TestReflect", nil, false, nil))

	assert(ClassRegistry.IsRegistered("TestReflect"), "IsRegistered deveria refletir o registro recém-feito")
	local descriptor = ClassRegistry.Get("TestReflect")
	assert(descriptor ~= nil, "Get deveria devolver o descriptor registrado")
	assert((descriptor :: ClassDescriptor).ClassName == "TestReflect", "descriptor devolvido deveria ter o ClassName certo")
end)

test("new() erra claramente para classe não registrada, nunca retorna nil silencioso", function()
	local ok, err = pcall(function()
		return ClassRegistry.new("TestClasseInexistente", nil)
	end)

	assert(not ok, "new() de classe não registrada deveria erro, não devolver nil")
	assert(
		string.find(tostring(err), "não registrada") ~= nil,
		`mensagem de erro deveria dizer 'não registrada', recebeu: {err}`
	)
end)

test("new() erra claramente para classe abstrata, nunca retorna nil silencioso", function()
	ClassRegistry.Register(makeDescriptor("TestAbstrata", nil, true, nil))

	local ok, err = pcall(function()
		return ClassRegistry.new("TestAbstrata", nil)
	end)

	assert(not ok, "new() de classe abstrata deveria erro, não devolver nil")
	assert(string.find(tostring(err), "abstrata") ~= nil, `mensagem de erro deveria dizer 'abstrata', recebeu: {err}`)
end)

test("new() de classe concreta sem SuperClassName devolve instância válida com Name/ClassName corretos", function()
	ClassRegistry.Register(makeDescriptor("TestConcreta", nil, false, nil))

	local instance = ClassRegistry.new("TestConcreta", "MinhaInstancia")
	assert(instance ~= nil, "new() de classe concreta registrada nunca deveria devolver nil")
	assert(instance.ClassName == "TestConcreta", "ClassName da instância deveria ser o da classe pedida")
	assert(instance.Name == "MinhaInstancia", "Name deveria ser o explícito passado")
	assert(instance:IsA("TestConcreta"), "IsA deveria bater com o próprio ClassName")
	assert(instance:IsA("Instance"), "IsA deveria bater com Instance (toda cadeia termina nela)")
end)

test("new() de classe com SuperClassName encadeado resolve a cadeia inteira (testável via IsA)", function()
	ClassRegistry.Register(makeDescriptor("TestGrandParent", nil, false, nil))
	ClassRegistry.Register(makeDescriptor("TestParent", "TestGrandParent", false, nil))
	ClassRegistry.Register(makeDescriptor("TestChild", "TestParent", false, nil))

	local instance = ClassRegistry.new("TestChild", nil)

	assert(instance:IsA("TestChild"), "deveria bater com o próprio ClassName")
	assert(instance:IsA("TestParent"), "deveria bater com a superclasse direta")
	assert(instance:IsA("TestGrandParent"), "deveria bater com a superclasse da superclasse")
	assert(instance:IsA("Instance"), "cadeia deveria terminar em Instance")
	assert(not instance:IsA("TestClasseNaoRelacionada"), "não deveria bater com classe fora da cadeia")
end)

test("new() resolve a cadeia mesmo com classes registradas fora de ordem topológica", function()
	-- Registra o filho ANTES do pai — a resolução da cadeia é lazy (em new(), não em
	-- Register()), então a ordem de registro não deveria importar.
	ClassRegistry.Register(makeDescriptor("TestOutOfOrderChild", "TestOutOfOrderParent", false, nil))
	ClassRegistry.Register(makeDescriptor("TestOutOfOrderParent", nil, false, nil))

	local instance = ClassRegistry.new("TestOutOfOrderChild", nil)
	assert(instance:IsA("TestOutOfOrderChild"), "deveria bater com o próprio ClassName")
	assert(instance:IsA("TestOutOfOrderParent"), "deveria resolver a superclasse registrada depois do filho")
end)

test("new() erra claramente se SuperClassName referencia uma classe nunca registrada", function()
	ClassRegistry.Register(makeDescriptor("TestSuperclasseOrfa", "TestSuperclasseInexistente", false, nil))

	local ok, err = pcall(function()
		return ClassRegistry.new("TestSuperclasseOrfa", nil)
	end)

	assert(not ok, "new() não deveria resolver silenciosamente uma cadeia com superclasse ausente")
	assert(
		string.find(tostring(err), "TestSuperclasseInexistente") ~= nil,
		`mensagem de erro deveria citar a superclasse ausente, recebeu: {err}`
	)
end)

-- (a) Regressão do achado ALTO da revisão de task-runtime-004: IsA de ancestral indireto tem
-- que responder certo DE DENTRO do próprio Initialize, porque a cadeia já foi aplicada por
-- ClassRegistry.new ANTES de chamar Initialize. Este teste é o que prova que a ordem
-- NewBase -> SetClassChain -> Initialize está em vigor — deve FALHAR se alguém reverter a
-- ordem para Initialize -> SetClassChain (ou reintroduzir Construct chamando NewBase por
-- dentro, sem a cadeia aplicada ainda). Confirmado localmente: revertendo a ordem em
-- ClassRegistry.new para chamar Initialize antes de SetClassChain, este teste falha (ver
-- relatório da tarefa).
test("IsA de ancestral indireto responde true DE DENTRO do Initialize (regressão achado ALTO)", function()
	ClassRegistry.Register(makeDescriptor("TestAltoA", nil, false, nil))
	ClassRegistry.Register(makeDescriptor("TestAltoB", "TestAltoA", false, nil))

	local sawIsAA = false
	local sawIsAB = false
	ClassRegistry.Register(
		makeDescriptor("TestAltoC", "TestAltoB", false, function(instance: Instance)
			sawIsAA = instance:IsA("TestAltoA")
			sawIsAB = instance:IsA("TestAltoB")
		end)
	)

	ClassRegistry.new("TestAltoC", nil)

	assert(sawIsAA, "instance:IsA('TestAltoA') deveria ser true DENTRO do Initialize de TestAltoC")
	assert(sawIsAB, "instance:IsA('TestAltoB') deveria ser true DENTRO do Initialize de TestAltoC")
end)

-- (b) Ciclo de herança mútuo: A.Super = "B", B.Super = "A". Precisa ser capturável por pcall,
-- nunca travar o processo num laço infinito.
test("ciclo de herança mútuo captura erro via pcall, não trava", function()
	ClassRegistry.Register(makeDescriptor("TestCicloMutuoA", "TestCicloMutuoB", false, nil))
	ClassRegistry.Register(makeDescriptor("TestCicloMutuoB", "TestCicloMutuoA", false, nil))

	local ok, err = pcall(function()
		return ClassRegistry.new("TestCicloMutuoA", nil)
	end)

	assert(not ok, "new() de um ciclo de herança mútuo deveria erro, nunca travar")
	assert(
		string.find(tostring(err), "ciclo de herança") ~= nil,
		`mensagem de erro deveria mencionar 'ciclo de herança', recebeu: {err}`
	)
end)

-- (c) Auto-referência direta: A.Super = "A". Mesmo caminho de guarda de ciclo, caso degenerado.
test("auto-referência direta (SuperClassName == ClassName) captura erro via pcall, não trava", function()
	ClassRegistry.Register(makeDescriptor("TestAutoReferencia", "TestAutoReferencia", false, nil))

	local ok, err = pcall(function()
		return ClassRegistry.new("TestAutoReferencia", nil)
	end)

	assert(not ok, "new() de uma classe que referencia a si mesma como superclasse deveria erro, nunca travar")
	assert(
		string.find(tostring(err), "ciclo de herança") ~= nil,
		`mensagem de erro deveria mencionar 'ciclo de herança', recebeu: {err}`
	)
end)

-- (d) Descriptor sem Initialize (campo nil): instancia normalmente, sem erro.
test("descriptor sem Initialize (campo nil) instancia normalmente", function()
	ClassRegistry.Register(makeDescriptor("TestSemInitialize", nil, false, nil))

	local instance = ClassRegistry.new("TestSemInitialize", nil)
	assert(instance ~= nil, "new() de descriptor sem Initialize deveria devolver uma instância válida")
	assert(instance.ClassName == "TestSemInitialize", "ClassName deveria ser o da classe pedida")
	assert(instance:IsA("TestSemInitialize"), "IsA deveria bater com o próprio ClassName mesmo sem Initialize")
end)

-- (e) Name default: sem nome explícito, Name cai para o ClassName (default resolvido por
-- Instance.NewBase, chamado por ClassRegistry.new); com nome explícito, Name é o nome passado.
test("Name default cai para ClassName sem nome explícito, e usa o nome explícito quando dado", function()
	ClassRegistry.Register(makeDescriptor("TestNameDefault", nil, false, nil))

	local semNome = ClassRegistry.new("TestNameDefault", nil)
	assert(semNome.Name == "TestNameDefault", `Name deveria cair para o ClassName por default, recebeu: {semNome.Name}`)

	local comNome = ClassRegistry.new("TestNameDefault", "foo")
	assert(comNome.Name == "foo", `Name deveria ser o nome explícito passado, recebeu: {comNome.Name}`)
end)

--[[
	Testes NOVOS da task-runtime-016 (ClassDescriptor.Methods + achatamento em ClassRegistry).
	Ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-04 (3) — acesso a membro". Nenhum dos 13 testes acima foi alterado.
]]

test(
	"método herdado de uma superclasse registrada é servido igual a método próprio (indistinguível do lado do script)",
	function()
		local parentMethods: InstanceModule.ClassMethods = {
			Foo = function(): string
				return "parent-foo"
			end,
		}
		table.freeze(parentMethods)
		ClassRegistry.Register(makeDescriptorWithMethods("TestMethodsParent", nil, parentMethods, nil))
		ClassRegistry.Register(makeDescriptorWithMethods("TestMethodsChild", "TestMethodsParent", nil, nil))

		local instance = ClassRegistry.new("TestMethodsChild", nil)
		type WithFoo = Instance & { Foo: (self: Instance) -> string }
		local typed = (instance :: unknown) :: WithFoo
		assert(typed:Foo() == "parent-foo", "método herdado da superclasse deveria ser servido igual a método próprio")
	end
)

test("classe mais concreta sobrescreve método de mesmo nome da superclasse no achatamento", function()
	local parentMethods: InstanceModule.ClassMethods = {
		Foo = function(): string
			return "parent"
		end,
	}
	table.freeze(parentMethods)
	local childMethods: InstanceModule.ClassMethods = {
		Foo = function(): string
			return "child"
		end,
	}
	table.freeze(childMethods)
	ClassRegistry.Register(makeDescriptorWithMethods("TestOverrideParent", nil, parentMethods, nil))
	ClassRegistry.Register(makeDescriptorWithMethods("TestOverrideChild", "TestOverrideParent", childMethods, nil))

	local instance = ClassRegistry.new("TestOverrideChild", nil)
	type WithFoo = Instance & { Foo: (self: Instance) -> string }
	local typed = (instance :: unknown) :: WithFoo
	assert(typed:Foo() == "child", "classe mais concreta deveria sobrescrever o método da superclasse no achatamento")
end)

test("método de classe é chamável de DENTRO do próprio Initialize", function()
	local sawGreeting: string? = nil
	local methods: InstanceModule.ClassMethods = {
		Greet = function(): string
			return "hi"
		end,
	}
	table.freeze(methods)
	ClassRegistry.Register(
		makeDescriptorWithMethods("TestMethodInsideInitialize", nil, methods, function(instance: Instance)
			type WithGreet = Instance & { Greet: (self: Instance) -> string }
			local typed = (instance :: unknown) :: WithGreet
			sawGreeting = typed:Greet()
		end)
	)

	ClassRegistry.new("TestMethodInsideInitialize", nil)
	assert(sawGreeting == "hi", "método de classe deveria ser chamável de dentro do próprio Initialize")
end)

test("classe sem Methods em nenhum elo da cadeia mantém classMethods nil (comportamento de hoje)", function()
	ClassRegistry.Register(makeDescriptor("TestNoMethodsAtAll", nil, false, nil))
	local instance = ClassRegistry.new("TestNoMethodsAtAll", nil)

	-- Sem nenhuma classe com Methods na cadeia, ler um nome desconhecido continua caindo no
	-- fallback de properties (nil) — nunca acha nada em classMethods porque SetClassMethods nunca
	-- foi chamado para esta instância (resolveClassMethods devolveu nil).
	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.QualquerCoisa == nil, "sem Methods na cadeia, ler nome desconhecido deveria devolver nil")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
