--!strict

--[[
	Teste da task-services-001 (esqueleto de `services`: ClassBuilder.luau). Cobre o acceptance
	do board item a item:
	- `Build` REJEITA com erro alto (português) um `Behavior` cujo `Methods` declara um nome fora
	  de `MethodNames` -- a invariante 1 da regra 00 verificada mecanicamente.
	- `Build` completa `MethodNames` sem implementação com um stub que ERRA ao ser chamado, com a
	  mensagem `[LuauBench] ... is not simulated by LuauBench yet` exata.
	- a tabela de métodos devolvida está congelada (`table.freeze`).
	- método implementado por `Behavior` é usado como está, nunca substituído por stub.
	- tradução `Superclass -> SuperClassName` ("Instance" vira nil; qualquer outro nome passa
	  direto).
	- `IsAbstract`/`IsService`/`Schema` passam direto de `GeneratedClass` para `ClassDescriptor`.
	- `Initialize` vem de `Behavior.Initialize` (ou nil, se `Behavior` for nil).

	Roda com `lune run src/services/ClassBuilder.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Types = require("./Types")
local ClassBuilder = require("./ClassBuilder")

type ClassSchema = Runtime.ClassSchema
type MemberKind = Runtime.MemberKind

local passedCount = 0
local totalCount = 0

-- Mesmo padrão dos specs de `runtime`: roda cada teste imediatamente, deixa um `assert` que
-- falhar estourar pra fora do chunk (traceback + exit code != 0 do próprio Lune).
local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function makeGeneratedClass(
	className: string,
	superclass: string,
	isService: boolean,
	isAbstract: boolean,
	schema: ClassSchema,
	methodNames: { string }
): Types.GeneratedClass
	return {
		ClassName = className,
		Superclass = superclass,
		IsService = isService,
		IsAbstract = isAbstract,
		Schema = schema,
		MethodNames = methodNames,
	}
end

local EMPTY_SCHEMA: ClassSchema = {}
table.freeze(EMPTY_SCHEMA)

test("Build REJEITA um Behavior cujo Methods declara nome fora de MethodNames (invariante 1 da regra 00)", function()
	local generated = makeGeneratedClass("TestCBReject", "Instance", false, false, EMPTY_SCHEMA, { "Foo" })
	-- `methods` tipado explicitamente como `{ [string]: unknown }` -- um literal de tabela com
	-- campo de função concreta (`{| Bar: () -> () |}`) NÃO é estruturalmente compatível com o
	-- indexador de `Types.Behavior.Methods` sem essa anotação (Luau infere um record "sealed",
	-- não um mapa indexado por string).
	local methods: { [string]: unknown } = {
		Bar = function(): () end,
	}
	local behavior: Types.Behavior = {
		Methods = methods,
	}

	local ok, err = pcall(function()
		return ClassBuilder.Build(generated, behavior)
	end)

	assert(not ok, "Build deveria erro alto quando behavior.Methods declara um nome fora de MethodNames")
	local message = tostring(err)
	assert(string.find(message, "'Bar'", 1, true) ~= nil, `mensagem deveria citar o método inventado 'Bar', recebeu: {message}`)
	assert(
		string.find(message, "'TestCBReject'", 1, true) ~= nil,
		`mensagem deveria citar a classe 'TestCBReject', recebeu: {message}`
	)
	assert(
		string.find(message, "não existe em", 1, true) ~= nil,
		`mensagem deveria dizer 'não existe em' (português, erro de engenharia interna), recebeu: {message}`
	)
end)

test("Build completa MethodNames sem implementação com stub que ERRA com a mensagem [LuauBench] exata", function()
	local generated = makeGeneratedClass("TestCBStub", "Instance", false, false, EMPTY_SCHEMA, { "Raycast" })

	local descriptor = ClassBuilder.Build(generated, nil)
	local methods = descriptor.Methods
	assert(methods ~= nil, "descriptor.Methods não deveria ser nil quando generated.MethodNames não é vazio")

	local stub = (methods :: { [string]: unknown })["Raycast"] :: (...unknown) -> ()
	assert(typeof(stub) == "function", "método sem implementação deveria virar uma função stub, nunca nil")

	-- Chamado dentro de um closure (não `pcall(stub)` direto): mesmo padrão já usado nos specs de
	-- `runtime` para envolver uma chamada que não devolve valor -- `pcall` de uma função cujo tipo
	-- devolve `()` diretamente resolve como aridade fixa de 1 (só o boolean), o que o luau-lsp
	-- rejeita ao destruturar em `ok, err`.
	local ok, err = pcall(function()
		stub()
	end)
	assert(not ok, "chamar o stub de um método não simulado deveria erro, nunca devolver silenciosamente")
	-- Substring, não igualdade exata (acceptance do board): error(msg, 2) legitimamente prefixa a
	-- posição de quem CHAMOU o stub -- é o comportamento certo (regra 01: mensagem de erro traz
	-- contexto de onde no script isso aconteceu), não ruído a esconder do teste.
	local message = tostring(err)
	assert(
		string.find(message, "[LuauBench] TestCBStub:Raycast() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem do stub deveria conter o prefixo [LuauBench] + Classe:Método(), recebeu: {message}`
	)
	assert(
		string.find(message, "is not simulated by LuauBench yet", 1, true) ~= nil,
		`mensagem do stub deveria conter a substring exigida pelo acceptance, recebeu: {message}`
	)
end)

test("tabela de métodos devolvida por Build está congelada", function()
	local generated = makeGeneratedClass("TestCBFrozen", "Instance", false, false, EMPTY_SCHEMA, { "Foo", "Bar" })
	local descriptor = ClassBuilder.Build(generated, nil)

	assert(descriptor.Methods ~= nil, "descriptor.Methods não deveria ser nil")
	assert(table.isfrozen(descriptor.Methods :: { [string]: unknown }), "Methods deveria estar table.freeze()ada")
end)

test("método implementado por Behavior é usado como está, nunca substituído pelo stub", function()
	local generated = makeGeneratedClass("TestCBImplemented", "Instance", false, false, EMPTY_SCHEMA, { "Greet" })
	-- Mesma anotação explícita de `{ [string]: unknown }` do teste acima -- necessária para o
	-- literal de tabela com campo de função concreta ser aceito onde `Types.Behavior.Methods`
	-- espera um mapa indexado por string, não um record "sealed".
	local implementedMethods: { [string]: unknown } = {
		Greet = function(): string
			return "oi"
		end,
	}
	local behavior: Types.Behavior = {
		Methods = implementedMethods,
	}

	local descriptor = ClassBuilder.Build(generated, behavior)
	local methods = descriptor.Methods :: { [string]: unknown }
	local greet = methods["Greet"] :: () -> string

	assert(greet() == "oi", "método implementado por behavior.Methods deveria ser usado como está, sem stub")
end)

test("SuperClassName: Superclass == 'Instance' vira nil (raiz simulada); qualquer outro nome passa direto", function()
	local generatedRoot = makeGeneratedClass("TestCBRoot", "Instance", false, false, EMPTY_SCHEMA, {})
	local descriptorRoot = ClassBuilder.Build(generatedRoot, nil)
	assert(descriptorRoot.SuperClassName == nil, "Superclass == 'Instance' deveria virar SuperClassName == nil")

	local generatedChild = makeGeneratedClass("TestCBChild", "TestCBParent", false, false, EMPTY_SCHEMA, {})
	local descriptorChild = ClassBuilder.Build(generatedChild, nil)
	assert(
		descriptorChild.SuperClassName == "TestCBParent",
		`Superclass diferente de 'Instance' deveria passar direto para SuperClassName, recebeu: {descriptorChild.SuperClassName}`
	)
end)

test("IsAbstract/IsService/Schema passam direto de GeneratedClass para ClassDescriptor", function()
	local schema: ClassSchema = {
		Gravity = { Kind = "Property" :: MemberKind, Default = 196.2, ReadOnly = false },
	}
	table.freeze(schema)

	local generated = makeGeneratedClass("TestCBPassthrough", "Instance", true, true, schema, {})
	local descriptor = ClassBuilder.Build(generated, nil)

	assert(descriptor.IsAbstract == true, "IsAbstract deveria passar direto de GeneratedClass")
	assert(descriptor.IsService == true, "IsService deveria passar direto de GeneratedClass")
	assert(descriptor.Schema == schema, "Schema deveria passar direto (mesma referência) de GeneratedClass")
end)

--[[
	Testes de task-services-003: achado confirmado empiricamente durante aquela tarefa --
	`generated/classes/Instance.luau` (task-services-002) inclui, corretamente, vários nomes que
	o Roblox API Dump declara como Function reais de "Instance" (FindFirstChild/Destroy/IsA/etc)
	mas que `src/runtime/Instance.luau` já implementa NATIVAMENTE (os "13 métodos base") -- e
	`Instance.SetClassMethods` REJEITA qualquer `ClassDescriptor.Methods` que tente redeclarar essa
	superfície fixa (mensagem: "colide com a superfície fixa de Instance ... corrigir lá [em
	services]"). Reproduzido de verdade nesta tarefa: registrar "Instance" sem este filtro e
	instanciar "Folder" (que herda o Methods achatado) errava exatamente essa colisão dentro de
	`Runtime.ClassRegistry.new`. `ClassBuilder.Build` filtra isso na origem -- ver
	`RESERVED_INSTANCE_SURFACE` em ClassBuilder.luau para a lista completa e a fonte de cada nome.
]]
test(
	"Build OMITE da tabela Methods qualquer nome da superfície fixa de Instance (FindFirstChild/Destroy/IsA/Changed), mesmo que MethodNames os declare",
	function()
		local generated = makeGeneratedClass(
			"TestCBReserved",
			"Instance",
			false,
			false,
			EMPTY_SCHEMA,
			{ "FindFirstChild", "Destroy", "IsA", "Changed", "ClassName", "MinhaFuncaoNormal" }
		)

		local descriptor = ClassBuilder.Build(generated, nil)
		local methods = descriptor.Methods :: { [string]: unknown }

		assert(methods["FindFirstChild"] == nil, "FindFirstChild é método base nativo -- não deveria virar stub")
		assert(methods["Destroy"] == nil, "Destroy é método base nativo -- não deveria virar stub")
		assert(methods["IsA"] == nil, "IsA é método base nativo -- não deveria virar stub")
		assert(methods["Changed"] == nil, "Changed é um dos 5 sinais fixos -- não deveria virar stub de método")
		assert(methods["ClassName"] == nil, "ClassName é campo fixo -- não deveria virar stub de método")
		assert(
			typeof(methods["MinhaFuncaoNormal"]) == "function",
			"um nome que NÃO colide com a superfície fixa deveria continuar recebendo o stub normalmente"
		)
	end
)

test("Build REJEITA um Behavior tentando implementar um nome da superfície fixa de Instance (ex: Destroy)", function()
	local generated = makeGeneratedClass("TestCBReservedBehavior", "Instance", false, false, EMPTY_SCHEMA, { "Destroy" })
	local methods: { [string]: unknown } = {
		Destroy = function(): () end,
	}
	local behavior: Types.Behavior = {
		Methods = methods,
	}

	local ok, err = pcall(function()
		return ClassBuilder.Build(generated, behavior)
	end)

	assert(not ok, "Build deveria erro alto quando behavior.Methods tenta reimplementar um nome da superfície fixa")
	local message = tostring(err)
	assert(
		string.find(message, "'Destroy'", 1, true) ~= nil,
		`mensagem deveria citar o nome reservado 'Destroy', recebeu: {message}`
	)
	assert(
		string.find(message, "superfície fixa nativa de Runtime.Instance", 1, true) ~= nil,
		`mensagem deveria explicar que é superfície fixa nativa (português, erro de engenharia interna), recebeu: {message}`
	)
end)

test("Initialize vem de Behavior.Initialize; nil quando Behavior é nil", function()
	local generated = makeGeneratedClass("TestCBInitialize", "Instance", false, false, EMPTY_SCHEMA, {})

	local descriptorSemBehavior = ClassBuilder.Build(generated, nil)
	assert(descriptorSemBehavior.Initialize == nil, "Initialize deveria ser nil quando Behavior é nil")

	local behavior: Types.Behavior = {
		Initialize = function(_instance) end,
	}
	local descriptorComBehavior = ClassBuilder.Build(generated, behavior)
	assert(
		descriptorComBehavior.Initialize == behavior.Initialize,
		"Initialize deveria ser exatamente o de behavior.Initialize quando fornecido"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
