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

	Testes NOVOS da task-runtime-023 (dois construtores -- `ClassRegistry.new`/
	`ClassRegistry.NewEngineInstance` -- ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md,
	"Revisão pós-integração 2026-09-05 (4)"), no final do arquivo: (f) `NewEngineInstance` sucede
	num descriptor `IsAbstract = true` e devolve instância COMPLETA (cadeia, métodos, schema,
	Signal fresco por Event, Initialize executado); (g) `NewEngineInstance` de classe não
	registrada continua errando; (h) `NewEngineInstance` com/sem `name` explícito; (i)/(j) os
	erros de ciclo de herança e superclasse órfã disparam com a mesma mensagem pelas DUAS
	entradas. Nenhum dos testes acima (exceto a mensagem esperada de "TestAbstrata", atualizada)
	foi alterado.
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

-- Mensagem atualizada por task-runtime-023 (ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md,
-- "Revisão pós-integração 2026-09-05 (4)"): a via pública (`ClassRegistry.new`) continua
-- rejeitando `IsAbstract`, mas a mensagem agora nomeia a tag NotCreatable do dump e a saída
-- (`ClassRegistry.NewEngineInstance`) em vez de dizer só "é abstrata".
test("new() erra claramente para classe abstrata (NotCreatable), nunca retorna nil silencioso", function()
	ClassRegistry.Register(makeDescriptor("TestAbstrata", nil, true, nil))

	local ok, err = pcall(function()
		return ClassRegistry.new("TestAbstrata", nil)
	end)

	assert(not ok, "new() de classe abstrata deveria erro, não devolver nil")
	assert(
		string.find(tostring(err), "não é criável por script") ~= nil,
		`mensagem de erro deveria dizer 'não é criável por script', recebeu: {err}`
	)
	assert(
		string.find(tostring(err), "NotCreatable") ~= nil,
		`mensagem de erro deveria citar a tag 'NotCreatable' do Roblox API Dump, recebeu: {err}`
	)
	assert(
		string.find(tostring(err), "NewEngineInstance") ~= nil,
		`mensagem de erro deveria nomear a saída 'ClassRegistry.NewEngineInstance', recebeu: {err}`
	)
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

--[[
	Testes NOVOS da task-runtime-018 (ClassDescriptor.Schema + achatamento/wiring em
	ClassRegistry.new). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 3"/
	"Decisão 4"/"Decisão 6". Nenhum dos 17 testes acima foi alterado. Mecânica de __index/
	__newindex (modo estrito/leniente, mensagens de erro) já é coberta em Instance.spec.luau, via
	Instance.SetClassSchema direto — aqui o foco é achatamento entre classes e o wiring automático
	de ClassRegistry.new (SetClassSchema chamada, defaults semeados, Signal fresco por instância).
]]

-- Helper NOVO da task-runtime-018, no mesmo espírito de `makeDescriptorWithMethods`: não
-- reaproveita `makeDescriptor` de propósito, para não alterar a assinatura usada pelos 17 testes
-- já existentes.
local function makeDescriptorWithSchema(
	className: string,
	superClassName: string?,
	schema: InstanceModule.ClassSchema?,
	initialize: ((instance: Instance) -> ())?
): ClassDescriptor
	return {
		ClassName = className,
		SuperClassName = superClassName,
		IsAbstract = false,
		IsService = false,
		Schema = schema,
		Initialize = initialize,
	}
end

-- Mesmo helper de Instance.spec.luau (duplicado de propósito: as duas suítes são independentes,
-- mesma razão de `makeDescriptorWithMethods` já não reaproveitar `makeDescriptor`).
local function makeSchema(
	entries: { [string]: { Kind: InstanceModule.MemberKind, Default: unknown?, ReadOnly: boolean? } }
): InstanceModule.ClassSchema
	local schema: InstanceModule.ClassSchema = {}
	for key, entry in entries do
		schema[key] = {
			Kind = entry.Kind,
			Default = entry.Default,
			ReadOnly = if entry.ReadOnly ~= nil then entry.ReadOnly else false,
		}
	end
	table.freeze(schema)
	return schema
end

test("new() de classe com Schema instala o modo estrito: ler nome fora do schema erra", function()
	ClassRegistry.Register(
		makeDescriptorWithSchema(
			"TestSchemaWiredUnknown",
			nil,
			makeSchema({
				Gravity = { Kind = "Property", Default = 196.2 },
			}),
			nil
		)
	)

	local instance = ClassRegistry.new("TestSchemaWiredUnknown", nil)
	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic

	local ok, err = pcall(function()
		return dynamic.NomeQueNaoExiste
	end)
	assert(not ok, "instância de classe com Schema deveria errar ao ler nome desconhecido")
	assert(
		string.find(tostring(err), "is not a valid member of", 1, true) ~= nil,
		`mensagem deveria conter 'is not a valid member of', recebeu: {err}`
	)
end)

test("new() semeia o Default do schema automaticamente, sem disparar Changed", function()
	ClassRegistry.Register(
		makeDescriptorWithSchema(
			"TestSchemaWiredDefault",
			nil,
			makeSchema({
				Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
			}),
			nil
		)
	)

	local instance = ClassRegistry.new("TestSchemaWiredDefault", nil)
	local fired = false
	instance.Changed:Connect(function()
		fired = true
	end)

	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Gravity == 196.2, "Gravity deveria ter sido semeada com o Default pelo próprio ClassRegistry.new")
	assert(
		not fired,
		"Changed não deveria ter disparado por causa da semeadura (que aconteceu ANTES desta Connection, dentro de new())"
	)
end)

test("classe mais concreta sobrescreve entrada do schema de mesmo nome da superclasse", function()
	ClassRegistry.Register(
		makeDescriptorWithSchema(
			"TestSchemaOverrideParent",
			nil,
			makeSchema({
				Foo = { Kind = "Property", Default = "parent", ReadOnly = false },
			}),
			nil
		)
	)
	ClassRegistry.Register(
		makeDescriptorWithSchema(
			"TestSchemaOverrideChild",
			"TestSchemaOverrideParent",
			makeSchema({
				Foo = { Kind = "Property", Default = "child", ReadOnly = false },
			}),
			nil
		)
	)

	local instance = ClassRegistry.new("TestSchemaOverrideChild", nil)
	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Foo == "child", "classe mais concreta deveria sobrescrever o Default herdado da superclasse")
end)

test("entrada do schema herdada de uma superclasse registrada é servida igual a entrada própria", function()
	ClassRegistry.Register(
		makeDescriptorWithSchema(
			"TestSchemaInheritedParent",
			nil,
			makeSchema({
				Bar = { Kind = "Property", Default = "from-parent", ReadOnly = false },
			}),
			nil
		)
	)
	ClassRegistry.Register(makeDescriptorWithSchema("TestSchemaInheritedChild", "TestSchemaInheritedParent", nil, nil))

	local instance = ClassRegistry.new("TestSchemaInheritedChild", nil)
	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Bar == "from-parent", "propriedade herdada do schema da superclasse deveria ser servida igual a uma própria")

	-- O modo estrito também se aplica quando o schema vem só da superclasse, não só quando é
	-- próprio da classe concreta.
	local ok = pcall(function()
		return dynamic.NomeQueNaoExisteEmLugarNenhum
	end)
	assert(not ok, "modo estrito herdado deveria continuar errando para nome fora do schema")
end)

test("classe sem Schema em nenhum elo da cadeia mantém o modo leniente (comportamento de hoje)", function()
	ClassRegistry.Register(makeDescriptor("TestSchemaNoneAtAll", nil, false, nil))
	local instance = ClassRegistry.new("TestSchemaNoneAtAll", nil)

	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.QualquerCoisa == nil, "sem Schema na cadeia, ler nome desconhecido deveria continuar devolvendo nil, sem erro")
end)

test(
	"cada new() da mesma classe com evento no schema recebe um Signal PRÓPRIO (não compartilhado entre instâncias)",
	function()
		ClassRegistry.Register(
			makeDescriptorWithSchema(
				"TestSchemaWiredFreshSignal",
				nil,
				makeSchema({
					PlayerAdded = { Kind = "Event", Default = nil, ReadOnly = true },
				}),
				nil
			)
		)

		local instanceA = ClassRegistry.new("TestSchemaWiredFreshSignal", nil)
		local instanceB = ClassRegistry.new("TestSchemaWiredFreshSignal", nil)

		type Dynamic = { [string]: unknown }
		local dynamicA = (instanceA :: unknown) :: Dynamic
		local dynamicB = (instanceB :: unknown) :: Dynamic

		assert(dynamicA.PlayerAdded ~= nil, "PlayerAdded deveria existir em instanceA")
		assert(dynamicB.PlayerAdded ~= nil, "PlayerAdded deveria existir em instanceB")
		assert(
			dynamicA.PlayerAdded ~= dynamicB.PlayerAdded,
			"cada instância deveria ter seu próprio Signal, mesmo vindo do MESMO schema achatado e cacheado por ClassName"
		)
	end
)

test("Methods e Schema coexistem na mesma classe sem interferência (task-runtime-016 + task-runtime-018)", function()
	local methods: InstanceModule.ClassMethods = {
		Greet = function(): string
			return "oi"
		end,
	}
	table.freeze(methods)

	ClassRegistry.Register({
		ClassName = "TestMethodsAndSchema",
		SuperClassName = nil,
		IsAbstract = false,
		IsService = false,
		Methods = methods,
		Schema = makeSchema({
			Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
		}),
		Initialize = nil,
	})

	local instance = ClassRegistry.new("TestMethodsAndSchema", nil)
	type WithGreet = Instance & { Greet: (self: Instance) -> string }
	local typed = (instance :: unknown) :: WithGreet
	assert(typed:Greet() == "oi", "método de classe deveria continuar funcionando com Schema instalado também")

	type Dynamic = { [string]: unknown }
	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Gravity == 196.2, "propriedade do schema deveria continuar funcionando com Methods instalado também")

	local ok = pcall(function()
		dynamic.NomeQueNaoExisteNoSchemaNemEmMethods = 1
	end)
	assert(not ok, "modo estrito deveria continuar valendo para escrita de nome desconhecido")
end)

--[[
	Testes NOVOS da task-runtime-023 (ClassRegistry.NewEngineInstance -- ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, "Revisão pós-integração 2026-09-05
	(4) — `NotCreatable` vs. abstrata: dois construtores em `ClassRegistry`"). Nenhum dos testes
	acima foi alterado (exceto a mensagem esperada de "TestAbstrata", já atualizada acima).
]]

-- (f) NewEngineInstance sucede num descriptor IsAbstract = true e devolve instância COMPLETA --
-- verifica as cinco coisas exigidas pelo acceptance, não só "não errou": cadeia aplicada,
-- métodos de classe instalados e chamáveis, schema instalado com default semeado, Signal fresco
-- por instância para entrada Kind == "Event", e Initialize executado.
test(
	"NewEngineInstance sucede num descriptor com IsAbstract = true e devolve instância COMPLETA (cadeia, métodos, schema, Signal fresco, Initialize)",
	function()
		local sawInitialize = false
		local methods: InstanceModule.ClassMethods = {
			Greet = function(): string
				return "engine-hi"
			end,
		}
		table.freeze(methods)
		local schema = makeSchema({
			Gravity = { Kind = "Property", Default = 196.2, ReadOnly = false },
			Added = { Kind = "Event", Default = nil, ReadOnly = true },
		})

		ClassRegistry.Register(makeDescriptor("TestEngineParent", nil, true, nil))
		ClassRegistry.Register({
			ClassName = "TestEngineInstanceFull",
			SuperClassName = "TestEngineParent",
			IsAbstract = true,
			IsService = false,
			Methods = methods,
			Schema = schema,
			Initialize = function(_instance: Instance)
				sawInitialize = true
			end,
		})

		local instance = ClassRegistry.NewEngineInstance("TestEngineInstanceFull", nil)
		assert(instance ~= nil, "NewEngineInstance de um descriptor IsAbstract=true nunca deveria devolver nil")

		-- (1) cadeia aplicada: IsA de um ancestral indireto responde true.
		assert(instance:IsA("TestEngineParent"), "cadeia deveria ter sido aplicada -- IsA do ancestral deveria ser true")
		assert(instance:IsA("Instance"), "cadeia deveria terminar em Instance")

		-- (2) métodos de classe instalados e chamáveis.
		type WithGreet = Instance & { Greet: (self: Instance) -> string }
		local typed = (instance :: unknown) :: WithGreet
		assert(typed:Greet() == "engine-hi", "método de classe deveria estar instalado e chamável")

		-- (3) schema instalado com default semeado.
		type Dynamic = { [string]: unknown }
		local dynamic = (instance :: unknown) :: Dynamic
		assert(dynamic.Gravity == 196.2, "schema deveria estar instalado com o Default semeado")

		-- (4) Signal fresco por instância para entrada Kind == "Event".
		assert(dynamic.Added ~= nil, "entrada Kind == 'Event' do schema deveria ter sido semeada com um Signal")
		local otherInstance = ClassRegistry.NewEngineInstance("TestEngineInstanceFull", nil)
		local otherDynamic = (otherInstance :: unknown) :: Dynamic
		assert(dynamic.Added ~= otherDynamic.Added, "cada instância deveria ter seu próprio Signal, nunca compartilhado")

		-- (5) Initialize executado.
		assert(sawInitialize, "Initialize deveria ter sido executado por NewEngineInstance")
	end
)

-- (g) A guarda de "classe não registrada" NÃO é pulada por NewEngineInstance -- só a guarda de
-- IsAbstract é exclusiva de ClassRegistry.new.
test("NewEngineInstance de classe não registrada continua errando (a guarda de registro não é pulada)", function()
	local ok, err = pcall(function()
		return ClassRegistry.NewEngineInstance("TestEngineClasseInexistente", nil)
	end)

	assert(not ok, "NewEngineInstance de classe não registrada deveria erro, não devolver nil")
	assert(
		string.find(tostring(err), "não registrada") ~= nil,
		`mensagem de erro deveria dizer 'não registrada', recebeu: {err}`
	)
end)

-- (h) name explícito vs. default, pela via do motor.
test("NewEngineInstance com name explícito honra o nome; sem name, Name cai para o ClassName", function()
	ClassRegistry.Register(makeDescriptor("TestEngineNameDefault", nil, true, nil))

	local semNome = ClassRegistry.NewEngineInstance("TestEngineNameDefault", nil)
	assert(semNome.Name == "TestEngineNameDefault", `Name deveria cair para o ClassName por default, recebeu: {semNome.Name}`)

	local comNome = ClassRegistry.NewEngineInstance("TestEngineNameDefault", "foo")
	assert(comNome.Name == "foo", `Name deveria ser o nome explícito passado, recebeu: {comNome.Name}`)
end)

-- (i) Erro de ciclo de herança dispara com a mesma mensagem pelas DUAS entradas -- é isto que
-- fixa a mudança de nível de erro de resolveClassChain (nível 3 -> nível 1): o prefixo
-- "arquivo:linha:" muda, mas nenhuma asserção aqui casa com esse prefixo, só com o conteúdo.
test("erro de ciclo de herança dispara com a mesma mensagem pelas duas entradas (new e NewEngineInstance)", function()
	ClassRegistry.Register(makeDescriptor("TestEngineCicloA", "TestEngineCicloB", false, nil))
	ClassRegistry.Register(makeDescriptor("TestEngineCicloB", "TestEngineCicloA", false, nil))

	local okNew, errNew = pcall(function()
		return ClassRegistry.new("TestEngineCicloA", nil)
	end)
	assert(not okNew, "new() de um ciclo de herança deveria erro")
	assert(
		string.find(tostring(errNew), "ciclo de herança") ~= nil,
		`mensagem de erro (via new) deveria mencionar 'ciclo de herança', recebeu: {errNew}`
	)

	local okEngine, errEngine = pcall(function()
		return ClassRegistry.NewEngineInstance("TestEngineCicloA", nil)
	end)
	assert(not okEngine, "NewEngineInstance de um ciclo de herança deveria erro")
	assert(
		string.find(tostring(errEngine), "ciclo de herança") ~= nil,
		`mensagem de erro (via NewEngineInstance) deveria mencionar 'ciclo de herança', recebeu: {errEngine}`
	)
end)

-- (j) Erro de superclasse órfã dispara com a mesma mensagem pelas DUAS entradas. Nomes de classe
-- distintos para cada entrada (registry é global, sem reset por processo -- ver cabeçalho de
-- ClassRegistry.luau) para não colidir com nenhum outro teste deste arquivo.
test("erro de superclasse órfã dispara com a mesma mensagem pelas duas entradas (new e NewEngineInstance)", function()
	ClassRegistry.Register(makeDescriptor("TestEngineOrfaA", "TestEngineSuperInexistenteA", false, nil))
	ClassRegistry.Register(makeDescriptor("TestEngineOrfaB", "TestEngineSuperInexistenteB", false, nil))

	local okNew, errNew = pcall(function()
		return ClassRegistry.new("TestEngineOrfaA", nil)
	end)
	assert(not okNew, "new() com superclasse órfã deveria erro")
	assert(
		string.find(tostring(errNew), "TestEngineSuperInexistenteA") ~= nil,
		`mensagem de erro (via new) deveria citar a superclasse ausente, recebeu: {errNew}`
	)

	local okEngine, errEngine = pcall(function()
		return ClassRegistry.NewEngineInstance("TestEngineOrfaB", nil)
	end)
	assert(not okEngine, "NewEngineInstance com superclasse órfã deveria erro")
	assert(
		string.find(tostring(errEngine), "TestEngineSuperInexistenteB") ~= nil,
		`mensagem de erro (via NewEngineInstance) deveria citar a superclasse ausente, recebeu: {errEngine}`
	)
end)

--[[
	Testes NOVOS da task-runtime-036 (`ClassRegistry.GetFlattenedSchema` -- achado do revisor-cli
	em task-cli-025, ver .claude/agents-memory/revisor-cli-task-cli-025-2026-09-05.md). Nenhum dos
	testes acima foi alterado.
]]

test("GetFlattenedSchema erra claramente para classe não registrada, nunca devolve tabela vazia silenciosa", function()
	local ok, err = pcall(function()
		return ClassRegistry.GetFlattenedSchema("TestFlattenedClasseInexistente")
	end)

	assert(not ok, "GetFlattenedSchema de classe não registrada deveria erro, não devolver tabela vazia")
	assert(
		string.find(tostring(err), "não registrada") ~= nil,
		`mensagem de erro deveria dizer 'não registrada', recebeu: {err}`
	)
end)

test("GetFlattenedSchema de classe sem Schema em nenhum elo da cadeia devolve tabela vazia, nunca nil", function()
	ClassRegistry.Register(makeDescriptor("TestFlattenedEmpty", nil, false, nil))

	local schema = ClassRegistry.GetFlattenedSchema("TestFlattenedEmpty")
	assert(
		next(schema) == nil,
		"GetFlattenedSchema de classe sem Schema em nenhum elo da cadeia deveria devolver tabela vazia (contrato público difere de propósito do `nil` que resolveClassSchema devolve internamente -- ver comentário de GetFlattenedSchema em ClassRegistry.luau)"
	)
end)

-- Reproduz a cadeia real Script -> BaseScript -> LuaSourceContainer -> Instance citada no achado
-- do revisor-cli (task-cli-025): uma propriedade herdada de um ancestral DISTANTE (aqui,
-- "TestFlattenedRoot" no papel de "Instance", contribuindo "Capabilities") e uma propriedade
-- herdada de um ancestral IMEDIATO ("TestFlattenedBaseScriptLike" no papel de "BaseScript",
-- contribuindo "LinkedSource") precisam as duas aparecer no schema achatado da classe FOLHA
-- ("TestFlattenedScriptLike", no papel de "Script"), que não declara nenhuma das duas por si --
-- exatamente como o Script real não redeclara LinkedSource/Capabilities, só herda.
--
-- Nomes de teste prefixados com "TestFlattened" em vez dos nomes reais "Script"/"BaseScript"/
-- "LuaSourceContainer"/"Instance" É DE PROPÓSITO: registrar literalmente "Instance" no
-- ClassRegistry global deste processo mudaria o schema achatado de QUALQUER OUTRO teste deste
-- arquivo cuja cadeia termine em "Instance" (todas terminam, `resolveClassChain` sempre insere o
-- literal "Instance" no fim) -- o achatamento consulta `registry["Instance"]` de verdade quando
-- ela existe (é assim que `services` propaga `Capabilities` para toda classe na vida real, ver
-- `src/services/generated/classes/Instance.luau`). Como todos os testes deste arquivo rodam num
-- único processo Lune persistente compartilhando o mesmo `registry` module-level, registrar
-- "Instance" de verdade poluiria silenciosamente testes anteriores (dependente de ordem). Nomes
-- isolados evitam o efeito colateral sem abrir mão de provar a profundidade de herança exata (4
-- elos) e a forma exata do achado original.
test(
	"GetFlattenedSchema inclui propriedade herdada de ancestral distante E de ancestral imediato (cadeia de 4 níveis, cenário real Script/BaseScript/LuaSourceContainer/Instance)",
	function()
		ClassRegistry.Register(
			makeDescriptorWithSchema(
				"TestFlattenedRoot",
				nil,
				makeSchema({
					Capabilities = { Kind = "Property", Default = nil, ReadOnly = false },
				}),
				nil
			)
		)
		ClassRegistry.Register(makeDescriptorWithSchema("TestFlattenedLuaSourceContainerLike", "TestFlattenedRoot", nil, nil))
		ClassRegistry.Register(
			makeDescriptorWithSchema(
				"TestFlattenedBaseScriptLike",
				"TestFlattenedLuaSourceContainerLike",
				makeSchema({
					LinkedSource = { Kind = "Property", Default = "", ReadOnly = false },
				}),
				nil
			)
		)
		ClassRegistry.Register(makeDescriptorWithSchema("TestFlattenedScriptLike", "TestFlattenedBaseScriptLike", nil, nil))

		local schema = ClassRegistry.GetFlattenedSchema("TestFlattenedScriptLike")

		local linkedSource = schema.LinkedSource
		assert(linkedSource ~= nil, "schema achatado deveria incluir LinkedSource, herdada do ancestral imediato (papel de BaseScript)")
		assert(linkedSource.Kind == "Property", "LinkedSource deveria ser Kind == 'Property'")

		local capabilities = schema.Capabilities
		assert(
			capabilities ~= nil,
			"schema achatado deveria incluir Capabilities, herdada do ancestral distante (papel de Instance)"
		)
		assert(capabilities.Kind == "Property", "Capabilities deveria ser Kind == 'Property'")

		-- A própria classe folha (TestFlattenedScriptLike) não declara Schema próprio -- prova de
		-- que as duas entradas acima vieram MESMO da cadeia herdada, não de um Schema local
		-- inventado pelo teste.
		local ownDescriptor = ClassRegistry.Get("TestFlattenedScriptLike")
		assert(ownDescriptor ~= nil, "Get deveria devolver o descriptor registrado")
		assert(
			(ownDescriptor :: ClassDescriptor).Schema == nil,
			"classe folha não deveria declarar Schema próprio neste cenário -- as entradas têm que vir só da herança"
		)
	end
)

test(
	"GetFlattenedSchema aplica a mesma semântica de override (classe mais concreta vence) que resolveClassSchema já usa internamente -- prova de que não há lógica duplicada/divergente",
	function()
		ClassRegistry.Register(
			makeDescriptorWithSchema(
				"TestFlattenedOverrideParent",
				nil,
				makeSchema({
					Foo = { Kind = "Property", Default = "parent", ReadOnly = false },
				}),
				nil
			)
		)
		ClassRegistry.Register(
			makeDescriptorWithSchema(
				"TestFlattenedOverrideChild",
				"TestFlattenedOverrideParent",
				makeSchema({
					Foo = { Kind = "Property", Default = "child", ReadOnly = false },
				}),
				nil
			)
		)

		local schema = ClassRegistry.GetFlattenedSchema("TestFlattenedOverrideChild")
		local foo = schema.Foo
		assert(foo ~= nil, "Foo deveria estar presente no schema achatado")
		assert(
			foo.Default == "child",
			"classe mais concreta deveria vencer no achatamento -- mesma semântica de resolveClassSchema/ClassRegistry.new"
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
