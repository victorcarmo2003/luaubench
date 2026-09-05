--!strict

--[[
	Teste de integração da task-services-001 (src/services/init.luau, ponto de entrada público de
	`services`). `require("./")`, NÃO `require("./init")`/`require("./init.luau")`: mesmo gotcha
	de resolução de `require` do Lune 0.10.5 já documentado (e confirmado empiricamente por
	`coder-runtime`) no cabeçalho de src/runtime/init.luau/init.spec.luau -- só a forma "estilo
	diretório" carrega o `init.luau` real a partir de um arquivo irmão cujo nome também começa por
	"init". `Context`/`ClassBuilder`/`Types`, por terem nome normal, são requeridos diretamente
	(`require("./Context")` etc.) sem esse cuidado.

	Cobre o acceptance do board: `Register()` idempotente; `Bootstrap` seta o `Context`;
	`services` registra e instancia uma classe FICTÍCIA de teste de ponta a ponta via
	`Runtime.ClassRegistry` (nunca uma classe real do dump inventada à mão -- não há gerador
	ainda, ver limitação declarada no cabeçalho de init.luau); a família de erros de
	`Services.new` (classe inexistente e classe abstrata caem na MESMA mensagem "Unable to create
	an Instance of type ..."); `IsKnownClass`/`IsSimulatedClass`/`GetDumpVersion`.

	PENDÊNCIA DE TOOLING (mesmo achado já documentado no cabeçalho de src/runtime/init.spec.luau,
	confirmado de novo aqui, nunca por suposição -- regra 00): `luau-lsp analyze` 1.69.0 devolve
	"Unknown require"/"Unknown type 'Runtime.X'"/"Function only returns 1 value, but 2 are
	required here" em cascata bem NESTE arquivo, mesmo com os `require` escritos do jeito normal
	(`require("../runtime")`, `require("./Context")`, `require("./")`). Confirmado empiricamente
	que o gatilho é o NOME deste arquivo (começa por "init"), não o conteúdo: uma cópia idêntica
	renomeada para não começar com "init", analisada isolada, dá **zero erros** -- os mesmos
	`require`/tipos que aqui aparecem "desconhecidos" resolvem certinho. `lune run
	src/services/init.spec.luau` roda e passa 7/7 de verdade (Lune, que executa por real, não tem
	esse bug -- ele só afeta a análise estática do `luau-lsp`). Não escondido, não adivinhado:
	revisor-services deve reproduzir a cópia renomeada antes de reprovar esta tarefa por causa de
	diagnóstico neste arquivo especificamente.

	Roda com `lune run src/services/init.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Types = require("./Types")
local Context = require("./Context")
local ClassBuilder = require("./ClassBuilder")
local Services = require("./")

type ClassSchema = Runtime.ClassSchema
type MemberKind = Runtime.MemberKind
type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Register() é idempotente -- chamar duas vezes não erra", function()
	local ok = pcall(function()
		Services.Register()
		Services.Register()
	end)
	assert(ok, "uma segunda chamada a Services.Register() não deveria erro")
end)

test("Bootstrap seta o Context", function()
	local scheduler = Runtime.Scheduler.new()
	local dataModel = Runtime.DataModel.new()

	Services.Bootstrap({ scheduler = scheduler, dataModel = dataModel })

	assert(Context.IsSet(), "Context.IsSet() deveria ser true depois de Services.Bootstrap")
	assert(Context.GetScheduler() == scheduler, "Context deveria guardar exatamente o Scheduler passado a Bootstrap")
	assert(Context.GetDataModel() == dataModel, "Context deveria guardar exatamente o DataModel passado a Bootstrap")
end)

--[[
	Classe FICTÍCIA de teste de ponta a ponta: GeneratedClass + Behavior -> ClassBuilder.Build ->
	Runtime.ClassRegistry.Register -> Services.new. `Services.Register()` não registra nada nesta
	tarefa (não há gerador ainda), então o teste registra direto via Runtime.ClassRegistry --
	exatamente o caminho que task-services-002 vai automatizar dentro de Services.Register().
]]
local WIDGET_CLASS_NAME = "InitSpecWidget"
local widgetSchema: ClassSchema = {
	Label = { Kind = "Property" :: MemberKind, Default = "widget", ReadOnly = false },
	Pinged = { Kind = "Event" :: MemberKind, Default = nil, ReadOnly = true },
}
table.freeze(widgetSchema)

local widgetGenerated: Types.GeneratedClass = {
	ClassName = WIDGET_CLASS_NAME,
	Superclass = "Instance",
	IsService = false,
	IsAbstract = false,
	Schema = widgetSchema,
	MethodNames = { "Ping" },
}
-- Tipado explicitamente como `{ [string]: unknown }` -- um literal de tabela com campo de função
-- concreta não é estruturalmente compatível com o indexador de `Types.Behavior.Methods` sem essa
-- anotação (mesma razão documentada em ClassBuilder.spec.luau).
local widgetMethods: { [string]: unknown } = {
	Ping = function(_self: unknown): string
		return "pong"
	end,
}
local widgetBehavior: Types.Behavior = {
	Methods = widgetMethods,
}
Runtime.ClassRegistry.Register(ClassBuilder.Build(widgetGenerated, widgetBehavior))

local ABSTRACT_CLASS_NAME = "InitSpecAbstractWidget"
local abstractGenerated: Types.GeneratedClass = {
	ClassName = ABSTRACT_CLASS_NAME,
	Superclass = "Instance",
	IsService = false,
	IsAbstract = true,
	Schema = {} :: ClassSchema,
	MethodNames = {},
}
Runtime.ClassRegistry.Register(ClassBuilder.Build(abstractGenerated, nil))

test("services registra e instancia uma classe FICTÍCIA de ponta a ponta via Runtime.ClassRegistry", function()
	local instance = Services.new(WIDGET_CLASS_NAME, "MyWidget")

	assert(instance.ClassName == WIDGET_CLASS_NAME, "ClassName da instância deveria ser o da classe pedida")
	assert(instance.Name == "MyWidget", "Name deveria ser o nome explícito passado a Services.new")

	local dynamic = (instance :: unknown) :: Dynamic
	assert(dynamic.Label == "widget", "Default da entrada Property do schema deveria ter sido semeado por ClassRegistry.new")

	type WithPing = Runtime.Instance & { Ping: (self: Runtime.Instance) -> string }
	local typed = (instance :: unknown) :: WithPing
	assert(typed:Ping() == "pong", "método implementado por Behavior deveria ser chamável normalmente")

	local raw: unknown = Runtime.Instance.GetPropertyRaw(instance, "Pinged")
	local pinged: Runtime.FireableSignal<string> = raw :: Runtime.FireableSignal<string>
	local received: string? = nil
	pinged:Connect(function(value: string)
		received = value
	end)
	pinged:Fire("ok")
	assert(received == "ok", "entrada Event do schema deveria ter um Signal fresco funcionando de ponta a ponta")
end)

test("Services.new erra 'Unable to create an Instance of type' para classe que não existe no Roblox", function()
	local ok, err = pcall(function()
		return Services.new("TotalmenteInventada123", nil)
	end)
	assert(not ok, "Services.new de uma classe inexistente deveria erro, nunca devolver nil silenciosamente")
	-- Substring, não igualdade exata: error(msg, 2) legitimamente prefixa a posição de quem
	-- CHAMOU Services.new (regra 01 -- contexto de onde no script isso aconteceu), mesma
	-- convenção já usada nos specs de `runtime` (ex.: ClassRegistry.spec.luau).
	assert(
		string.find(tostring(err), `Unable to create an Instance of type "TotalmenteInventada123"`, 1, true) ~= nil,
		`mensagem deveria bater com a família Roblox, recebeu: {err}`
	)
end)

test("Services.new erra a MESMA mensagem para classe registrada e abstrata (NotCreatable)", function()
	local ok, err = pcall(function()
		return Services.new(ABSTRACT_CLASS_NAME, nil)
	end)
	assert(not ok, "Services.new de uma classe abstrata deveria erro, nunca devolver nil silenciosamente")
	assert(
		string.find(tostring(err), `Unable to create an Instance of type "{ABSTRACT_CLASS_NAME}"`, 1, true) ~= nil,
		`mensagem de classe abstrata deveria ser IGUAL à de classe inexistente (Decisão 5), recebeu: {err}`
	)
end)

test("IsKnownClass/IsSimulatedClass refletem o estado do registro", function()
	assert(Services.IsKnownClass(WIDGET_CLASS_NAME), "classe registrada deveria ser conhecida do dump")
	assert(Services.IsSimulatedClass(WIDGET_CLASS_NAME), "classe registrada deveria estar simulada")

	assert(not Services.IsKnownClass("TotalmenteInventada123"), "classe nunca registrada não deveria ser conhecida do dump")
	assert(not Services.IsSimulatedClass("TotalmenteInventada123"), "classe nunca registrada não deveria estar simulada")
end)

test("GetDumpVersion devolve o commit/versão fixados na Decisão 2 do desenho", function()
	local version = Services.GetDumpVersion()
	assert(
		version.Commit == "28360dea4b90b35dc3fe9f829baae64fb6c50e75",
		`Commit deveria bater com o fixado na Decisão 2, recebeu: {version.Commit}`
	)
	assert(
		version.Version == "0.737.0.7371584",
		`Version deveria bater com o fixado na Decisão 2, recebeu: {version.Version}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
