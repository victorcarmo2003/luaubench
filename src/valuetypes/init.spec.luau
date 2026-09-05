--!strict

--[[
	Teste da task-valuetypes-007 (init.luau -- superfície pública única do território). Cobre o
	acceptance verbatim do board (.claude/tasks.json, task-valuetypes-007):

	1. `BuildGlobals()` devolve uma tabela NOVA a cada chamada (duas chamadas não compartilham a
	   mesma referência).
	2. As chaves de `BuildGlobals()` batem EXATAMENTE com `Catalog.SimulatedNames()` (nem mais, nem
	   menos).

	Cobre também: `TypeNameOf` delega pra `Userdata.TypeNameOf` de verdade (fidelidade dos 7 tipos
	simulados + `nil` pra valor comum), `Decode`/`Catalog` reexportados são os módulos REAIS (não
	cópias fantasmas), e que cada construtor devolvido por `BuildGlobals()` funciona de fato (não é
	só uma chave presente com valor incorreto).

	`require("./")`, NÃO `require("./init")`/`require("./init.luau")`: mesmo gotcha de resolução do
	Lune 0.10.5 já documentado em `src/runtime/init.spec.luau`/`src/cli/init.spec.luau`/
	`src/services/init.spec.luau` -- de um IRMÃO no MESMO diretório, `require("./init")` dá erro
	("could not resolve child component 'init' (ambiguous)"), confirmado empiricamente nesta
	tarefa. `require("./")` é a forma que resolve.

	PENDÊNCIA DE TOOLING (mesmo achado já registrado em `src/runtime/init.spec.luau`, reproduzido
	aqui, não do Lune nem deste código): `luau-lsp analyze` 1.69.0 devolve falso-positivo
	("Unknown require") nas três linhas de `require("./...")` logo abaixo, mesmo com a forma
	correta -- confirmado empiricamente que o gatilho é o NOME deste arquivo começar por "init"
	(`init.spec.luau`), não o conteúdo: `luau-lsp` generaliza demais a convenção "arquivo
	`init.luau` representa o diretório" pra QUALQUER arquivo cujo nome comece assim. O Lune executa
	este arquivo corretamente (10/10 abaixo) -- é um bug isolado da ferramenta de análise estática.

	Roda com `lune run src/valuetypes/init.spec.luau`.
]]

local process = require("@lune/process")
local ValueTypes = require("./")
local Catalog = require("./Catalog")
local Userdata = require("./Userdata")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function toSet(names: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, name in names do
		set[name] = true
	end
	return set
end

local function countKeys(t: { [string]: unknown }): number
	local count = 0
	for _ in t do
		count += 1
	end
	return count
end

-- ================================================================================================
-- ACCEPTANCE 1: BuildGlobals() devolve tabela NOVA a cada chamada.
-- ================================================================================================

test("BuildGlobals() devolve uma tabela NOVA a cada chamada (duas chamadas não compartilham referência)", function()
	local first = ValueTypes.BuildGlobals()
	local second = ValueTypes.BuildGlobals()
	assert(first ~= second, "duas chamadas de BuildGlobals() deveriam devolver tabelas DIFERENTES (não a mesma referência)")

	-- Mutar a primeira não pode vazar pra segunda nem pra uma terceira chamada -- confirma que não
	-- é só uma referência superficialmente diferente por cima do mesmo estado interno.
	first["Fantasma"] = "valor invasor"
	local third = ValueTypes.BuildGlobals()
	assert(third["Fantasma"] == nil, "mutar o resultado de uma chamada não deveria vazar para uma chamada seguinte")
end)

-- ================================================================================================
-- ACCEPTANCE 2: as chaves de BuildGlobals() batem EXATAMENTE com Catalog.SimulatedNames().
-- ================================================================================================

test("as chaves de BuildGlobals() batem EXATAMENTE com Catalog.SimulatedNames() (nem mais, nem menos)", function()
	local globals = ValueTypes.BuildGlobals()
	local simulatedNames = Catalog.SimulatedNames()
	local simulatedSet = toSet(simulatedNames)

	assert(
		countKeys(globals) == #simulatedNames,
		`BuildGlobals() tem {countKeys(globals)} chaves, Catalog.SimulatedNames() tem {#simulatedNames} nomes -- deveriam bater`
	)

	for key in globals do
		assert(simulatedSet[key], `BuildGlobals() tem a chave '{key}', que NÃO está em Catalog.SimulatedNames()`)
	end
	for _, name in simulatedNames do
		assert(globals[name] ~= nil, `Catalog.SimulatedNames() tem '{name}', mas BuildGlobals() não tem essa chave`)
	end
end)

test("BuildGlobals() tem exatamente os 7 nomes da leva 1 (CFrame, Color3, Enum, UDim, UDim2, Vector2, Vector3)", function()
	-- Fixa a leva 1 nomeando os 7 nomes -- se uma tarefa futura (leva 2) virar mais uma entrada do
	-- Catalog em Simulated=true sem registrar o construtor em init.luau, o teste ACIMA (que compara
	-- contra Catalog.SimulatedNames() dinamicamente) já pega o drift; este aqui é só uma segunda
	-- garantia, mais legível, específica desta tarefa.
	local globals = ValueTypes.BuildGlobals()
	local expectedNames = { "CFrame", "Color3", "Enum", "UDim", "UDim2", "Vector2", "Vector3" }
	assert(countKeys(globals) == #expectedNames, `esperava {#expectedNames} chaves, recebeu {countKeys(globals)}`)
	for _, name in expectedNames do
		assert(globals[name] ~= nil, `BuildGlobals() deveria conter '{name}'`)
	end
end)

-- ================================================================================================
-- Cada construtor devolvido por BuildGlobals() FUNCIONA de fato (não é só uma chave presente).
-- ================================================================================================

type CallableNew = { new: (...unknown) -> unknown }
local function asCallableNew(value: unknown): CallableNew
	return value :: CallableNew
end

test("BuildGlobals()['Vector3'].new(1,2,3) produz um Vector3 real utilizável", function()
	local globals = ValueTypes.BuildGlobals()
	local v = asCallableNew(globals["Vector3"]).new(1, 2, 3)
	assert(Userdata.TypeNameOf(v) == "Vector3", `esperava Vector3, recebeu {tostring(Userdata.TypeNameOf(v))}`)
end)

test("BuildGlobals()['Color3'].new(1,0,0) produz um Color3 real utilizável", function()
	local globals = ValueTypes.BuildGlobals()
	local c = asCallableNew(globals["Color3"]).new(1, 0, 0)
	assert(Userdata.TypeNameOf(c) == "Color3", `esperava Color3, recebeu {tostring(Userdata.TypeNameOf(c))}`)
end)

test("BuildGlobals()['Enum'] é o mesmo objeto global Enum (typeof == \"Enums\")", function()
	local globals = ValueTypes.BuildGlobals()
	assert(Userdata.TypeNameOf(globals["Enum"]) == "Enums", `esperava "Enums", recebeu {tostring(Userdata.TypeNameOf(globals["Enum"]))}`)
end)

-- ================================================================================================
-- ValueTypes.TypeNameOf -- bridge com runtime (Decisão 4 do desenho). Delega pra
-- Userdata.TypeNameOf de verdade, não uma reimplementação paralela.
-- ================================================================================================

test("ValueTypes.TypeNameOf identifica corretamente os 7 tipos simulados", function()
	assert(ValueTypes.TypeNameOf(ValueTypes.Vector3.new(1, 2, 3)) == "Vector3")
	assert(ValueTypes.TypeNameOf(ValueTypes.Vector2.new(1, 2)) == "Vector2")
	assert(ValueTypes.TypeNameOf(ValueTypes.Color3.new(1, 0, 0)) == "Color3")
	assert(ValueTypes.TypeNameOf(ValueTypes.UDim.new(0, 8)) == "UDim")
	assert(ValueTypes.TypeNameOf(ValueTypes.UDim2.new()) == "UDim2")
	assert(ValueTypes.TypeNameOf(ValueTypes.CFrame.new()) == "CFrame")
	assert(ValueTypes.TypeNameOf(ValueTypes.Enum) == "Enums")
end)

test("ValueTypes.TypeNameOf devolve nil para valor comum (não é value type nosso)", function()
	assert(ValueTypes.TypeNameOf(5) == nil)
	assert(ValueTypes.TypeNameOf("x") == nil)
	assert(ValueTypes.TypeNameOf({}) == nil)
	assert(ValueTypes.TypeNameOf(nil) == nil)
end)

-- ================================================================================================
-- Decode/Catalog reexportados são os módulos REAIS (mesma referência, não cópia fantasma).
-- ================================================================================================

test("ValueTypes.Catalog é o MESMO módulo Catalog (mesma referência)", function()
	assert(ValueTypes.Catalog == Catalog, "init.luau deveria reexportar a MESMA referência de Catalog, não uma cópia")
end)

test("ValueTypes.Decode.FromRojoJson funciona através da superfície reexportada", function()
	local result = ValueTypes.Decode.FromRojoJson("Vector3", "DataType", { 1, 2, 3 })
	assert(result.Ok, "Decode.FromRojoJson deveria ter sucesso para um Vector3 válido")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
