--!strict

--[[
	Teste dedicado de `./InstanceState.luau` (regra 01: teste na mesma tarefa da lógica que
	cobre). Cobre o acceptance de task-services-016: `InstanceState` guarda e lê valor tipado
	INVISÍVEL ao script (leitura direta da chave na instância erra "is not a valid member of");
	prefixo `_LuauBench` validado; isolamento entre instâncias e entre chaves diferentes.

	Classe FICTÍCIA de teste, registrada direto via `Runtime.ClassRegistry` -- MESMO padrão de
	`src/services/init.spec.luau` ("Classe FICTÍCIA de teste de ponta a ponta"): GeneratedClass +
	Behavior -> ClassBuilder.Build -> Runtime.ClassRegistry.Register -> Runtime.ClassRegistry.new.
	Schema não-vazio (`Label`) só para deixar claro que a instância está no MODO ESTRITO (ver
	ClassRegistry.luau, `resolveClassSchema`: `hasAny` fica `true` assim que QUALQUER elo da
	cadeia declara `Schema`, mesmo `{}` -- então bastaria uma tabela vazia, mas uma entrada real
	deixa o teste mais legível).

	Roda com `lune run src/services/InstanceState.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Types = require("./Types")
local ClassBuilder = require("./ClassBuilder")

type ClassSchema = Runtime.ClassSchema
type MemberKind = Runtime.MemberKind

local InstanceState = require("./InstanceState")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Acesso dinâmico a um nome de propriedade arbitrário -- mesmo padrão de `Dynamic` já usado em
-- `src/services/init.spec.luau` para exercitar `instance.<Nome>` sob `--!strict` sem `any`.
type Dynamic = { [string]: unknown }

local WIDGET_CLASS_NAME = "InstanceStateSpecWidget"
local widgetSchema: ClassSchema = {
	Label = { Kind = "Property" :: MemberKind, Default = "widget", ReadOnly = false },
}
table.freeze(widgetSchema)

local widgetGenerated: Types.GeneratedClass = {
	ClassName = WIDGET_CLASS_NAME,
	Superclass = "Instance",
	IsService = false,
	IsAbstract = false,
	Schema = widgetSchema,
	MethodNames = {},
}
Runtime.ClassRegistry.Register(ClassBuilder.Build(widgetGenerated, nil))

test("InstanceState.new REJEITA uma chave sem o prefixo _LuauBench (erro de engenharia interna, em português)", function()
	local ok, err = pcall(function()
		return InstanceState.new("StoreId")
	end)

	assert(not ok, "InstanceState.new deveria erro alto para chave sem o prefixo _LuauBench")
	local message = tostring(err)
	assert(string.find(message, "'StoreId'", 1, true) ~= nil, `mensagem deveria citar a chave rejeitada, recebeu: {message}`)
	assert(
		string.find(message, "_LuauBench", 1, true) ~= nil,
		`mensagem deveria citar o prefixo exigido '_LuauBench', recebeu: {message}`
	)
	assert(
		string.find(message, "precisa começar com", 1, true) ~= nil,
		`mensagem deveria estar em português (erro de engenharia interna), recebeu: {message}`
	)
end)

test("InstanceState.new ACEITA uma chave com o prefixo _LuauBench", function()
	local ok = pcall(function()
		return InstanceState.new("_LuauBenchStoreId")
	end)
	assert(ok, "InstanceState.new não deveria erro para uma chave que começa com _LuauBench")
end)

test("Get devolve nil antes de qualquer Set", function()
	local instance = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W1")
	local state = InstanceState.new("_LuauBenchNeverSet")

	assert(state.Get(instance) == nil, "Get deveria devolver nil para uma chave que nunca recebeu Set nesta instância")
end)

test("Set/Get fazem round-trip de um valor tipado, e o valor fica INVISÍVEL como propriedade normal do script", function()
	local instance = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W2")
	local state = InstanceState.new("_LuauBenchStoreId")

	state.Set(instance, "PlayerData")
	assert(state.Get(instance) == "PlayerData", "Get deveria devolver exatamente o valor gravado por Set")

	-- A instância está no MODO ESTRITO (widgetSchema não-vazio instalado) -- '_LuauBenchStoreId'
	-- não está em NENHUM ClassSchema, então um acesso normal de propriedade (o que um script do
	-- usuário faria) precisa cair no fallback de erro real do Roblox, nunca expor o valor.
	local dynamic = (instance :: unknown) :: Dynamic
	local ok, err = pcall(function()
		return dynamic._LuauBenchStoreId
	end)
	assert(not ok, "ler a chave _LuauBenchStoreId diretamente na instância deveria erro -- ela não está em nenhum ClassSchema")
	assert(
		string.find(tostring(err), "is not a valid member of", 1, true) ~= nil,
		`mensagem deveria ser a família real do Roblox 'is not a valid member of', recebeu: {err}`
	)

	local okWrite = pcall(function()
		dynamic._LuauBenchStoreId = "hijacked"
	end)
	assert(not okWrite, "escrever a chave _LuauBenchStoreId diretamente na instância também deveria erro, mesmo modo estrito")
end)

test("duas chaves diferentes na MESMA instância não colidem", function()
	local instance = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W3")
	local storeIdState = InstanceState.new("_LuauBenchStoreId")
	local cursorState = InstanceState.new("_LuauBenchCursor")

	storeIdState.Set(instance, "Inventory")
	cursorState.Set(instance, 42)

	assert(storeIdState.Get(instance) == "Inventory", "chave StoreId não deveria ser afetada por Set em outra chave")
	assert(cursorState.Get(instance) == 42, "chave Cursor deveria guardar seu próprio valor, independente de StoreId")
end)

test("a MESMA chave em duas instâncias diferentes não compartilha estado", function()
	local instanceA = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W4A")
	local instanceB = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W4B")
	local state = InstanceState.new("_LuauBenchShared")

	state.Set(instanceA, "A-value")
	state.Set(instanceB, "B-value")

	assert(state.Get(instanceA) == "A-value", "instância A deveria manter seu próprio valor")
	assert(state.Get(instanceB) == "B-value", "instância B deveria manter seu próprio valor, sem vazar de A")
end)

test("Set sobrescreve um valor anterior na mesma chave/instância", function()
	local instance = Runtime.ClassRegistry.new(WIDGET_CLASS_NAME, "W5")
	local state = InstanceState.new("_LuauBenchOverwrite")

	state.Set(instance, 1)
	assert(state.Get(instance) == 1, "primeiro Set deveria valer")
	state.Set(instance, 2)
	assert(state.Get(instance) == 2, "segundo Set deveria sobrescrever o primeiro")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
