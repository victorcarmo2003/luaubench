--!strict

--[[
	Teste da task-cli-004 (TreeMaterializer.luau). Cobre o acceptance do board: fixture com
	ReplicatedStorage/ServerScriptService/Folder/ModuleScript materializando de verdade contra um
	`Runtime.DataModel` real (`Services.Bootstrap` de verdade, nunca mock) e resolvendo
	`game.ReplicatedStorage.Modules.Foo` por acesso de ponto; `Source` gravado/recuperável via
	`GetPropertyRaw` e invisível ao script; `$properties` primitivo aplicado; `$properties` com
	nome inválido e propriedade somente-leitura virando `Diagnostic` sem derrubar o comando; raiz
	não-`DataModel` e Service com nome divergente errando com mensagem dedicada; ausência de
	`NewEngineInstance`; ordem determinística de `Scripts`.

	Os testes de "caminho feliz" (fixture "basic") e de `$properties` (fixture "properties") usam
	`TreePlanner.Plan` de verdade sobre um fixture em disco -- é o mesmo `InstancePlan` que
	`RunCommand` (task-cli-006) vai produzir de verdade, então prova a integração real entre os
	dois módulos, não só `TreeMaterializer` isolado.

	Os testes de defesa em profundidade (raiz não-DataModel, Service com nome divergente, Service
	marcado sem ser tag `Service` do dump) usam um `InstancePlan`/`PlanNode` MONTADO À MÃO -- de
	propósito: `TreePlanner` já barra essas três situações no caminho normal (plan/*-not-found
	acima dele), então o único jeito de exercitar a defesa PRÓPRIA de `TreeMaterializer` é
	alimentá-lo com um plano que nunca passaria por `TreePlanner.Plan` de verdade (ver comentário
	de cada `Messages.Materialize*` correspondente, em `Messages.luau`).

	Roda com `lune run src/cli/TreeMaterializer.spec.luau`.
]]

local process = require("@lune/process")
local Diagnostics = require("./Diagnostics")
local ProjectFile = require("./ProjectFile")
local Runtime = require("../runtime")
local Services = require("../services")
local TreeMaterializer = require("./TreeMaterializer")
local TreePlanner = require("./TreePlanner")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local FIXTURES_ROOT = process.cwd .. "src/cli/fixtures/tree-materializer"

local function fixturePath(name: string): string
	return `{FIXTURES_ROOT}/{name}`
end

local function findByCode(bag: Diagnostics.Bag, code: string): Diagnostics.Diagnostic?
	for _, diagnostic in bag:All() do
		if diagnostic.Code == code then
			return diagnostic
		end
	end
	return nil
end

local function countByCode(bag: Diagnostics.Bag, code: string): number
	local count = 0
	for _, diagnostic in bag:All() do
		if diagnostic.Code == code then
			count += 1
		end
	end
	return count
end

-- `Services.IsServiceClass` REAL (nunca a função falsa de TreePlanner.spec.luau) -- este território
-- exercita a integração de verdade entre `TreePlanner` e `services`.
local REAL_PLAN_OPTIONS: TreePlanner.PlanOptions = {
	IsServiceClass = Services.IsServiceClass,
}

-- Planeja um fixture em disco (TreePlanner de verdade) -- usado pelos testes de caminho feliz.
local function planFixture(name: string): (TreePlanner.InstancePlan?, Diagnostics.Bag)
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath(name) .. "/default.project.json", bag)
	assert(project ~= nil, `fixture '{name}': ProjectFile.Read deveria ter conseguido ler o projeto (bag: {#bag:All()} diagnostic(s))`)
	if project == nil then
		return nil, bag
	end
	local plan = TreePlanner.Plan(project, REAL_PLAN_OPTIONS, bag)
	return plan, bag
end

-- `Services.Bootstrap` é idempotente (guarda `registered` local em `services/init.luau`) -- seguro
-- de chamar em todo teste, cada um com seu próprio Scheduler/DataModel (isolamento entre testes:
-- cada `game` é uma raiz nova, sem filhos compartilhados com o teste anterior).
local function newGame(): Runtime.DataModel
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return game
end

local function findChild(instance: Runtime.Instance, name: string): Runtime.Instance?
	return instance:FindFirstChild(name)
end

--------------------------------------------------------------------------------------------------
-- cli NUNCA chama Runtime.ClassRegistry.NewEngineInstance (verificável por grep, critério do board)
--------------------------------------------------------------------------------------------------

test("TreeMaterializer.luau nunca CHAMA Runtime.ClassRegistry.NewEngineInstance", function()
	local source = require("@lune/fs").readFile("src/cli/TreeMaterializer.luau")
	-- Grep pela SINTAXE DE CHAMADA ("NewEngineInstance(", com parêntese de abertura), não pela
	-- palavra crua -- o cabeçalho deste próprio arquivo CITA "NewEngineInstance" em prosa (entre
	-- crases, explicando por que NUNCA é chamada), e um `string.find` pela palavra nua acusaria a
	-- própria explicação como se fosse uma chamada real. Mesmo protocolo de
	-- `TreePlanner.spec.luau` (que evita repetir a string exata grepada no próprio texto do
	-- cabeçalho de `TreePlanner.luau`), adaptado aqui porque este cabeçalho precisa mesmo citar o
	-- nome da função proibida para explicar a proibição.
	assert(string.find(source, "NewEngineInstance(", 1, true) == nil, "TreeMaterializer NUNCA deveria CHAMAR NewEngineInstance")
end)

--------------------------------------------------------------------------------------------------
-- Caminho feliz: ReplicatedStorage/ServerScriptService/Folder/ModuleScript materializam de
-- verdade; acesso por ponto; Source gravado/recuperável e invisível ao script; ordem de Scripts
--------------------------------------------------------------------------------------------------

test("Materialize: fixture 'basic' materializa Service/Folder/Script/ModuleScript e resolve por acesso de ponto", function()
	local plan, planBag = planFixture("basic")
	assert(plan ~= nil, `fixture 'basic' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(not bag:HasErrors(), `materialização de 'basic' não deveria produzir erro (bag: {#bag:All()} diagnostic(s))`)

	-- Acesso de ponto de verdade, exatamente como o acceptance pede: game.ReplicatedStorage.Modules.Foo
	local replicatedStorage = game:FindFirstChildOfClass("ReplicatedStorage")
	assert(replicatedStorage ~= nil, "game deveria ter um ReplicatedStorage depois de Materialize")
	if replicatedStorage == nil then
		return
	end
	assert(replicatedStorage.ClassName == "ReplicatedStorage", "o Service materializado deveria ser mesmo ReplicatedStorage")

	local modules = findChild(replicatedStorage, "Modules")
	assert(modules ~= nil, "ReplicatedStorage deveria ter um filho 'Modules'")
	if modules == nil then
		return
	end
	assert(modules.ClassName == "Folder", "'Modules' (pasta sem init.*) deveria materializar como Folder")

	local foo = findChild(modules, "Foo")
	assert(foo ~= nil, "Modules deveria ter um filho 'Foo'")
	if foo == nil then
		return
	end
	assert(foo.ClassName == "ModuleScript", "'Foo.lua' deveria materializar como ModuleScript")

	-- Confirma que o MESMO objeto é alcançável por navegação de ponto encadeada (game.ReplicatedStorage.Modules.Foo)
	local rsDot = (replicatedStorage :: unknown) :: { [string]: unknown }
	local modulesDot = rsDot["Modules"]
	assert(modulesDot == modules, "ReplicatedStorage.Modules (via __index) deveria devolver o MESMO Folder achado por FindFirstChild")
	local modulesAsTable = (modules :: unknown) :: { [string]: unknown }
	local fooDot = modulesAsTable["Foo"]
	assert(fooDot == foo, "Modules.Foo (via __index) deveria devolver o MESMO ModuleScript achado por FindFirstChild")

	-- ServerScriptService + Script, Source gravado/recuperável e invisível ao script
	local serverScriptService = game:FindFirstChildOfClass("ServerScriptService")
	assert(serverScriptService ~= nil, "game deveria ter um ServerScriptService depois de Materialize")
	if serverScriptService == nil then
		return
	end

	local mainScript = findChild(serverScriptService, "Main")
	assert(mainScript ~= nil, "ServerScriptService deveria ter um filho 'Main'")
	if mainScript == nil then
		return
	end
	assert(mainScript.ClassName == "Script", "'Main.server.lua' deveria materializar como Script")

	-- Comparado contra o CONTEÚDO REAL do arquivo (lido de novo aqui, nunca um literal hardcoded no
	-- teste) -- prova fidelidade byte a byte sem acoplar o teste ao texto exato do comentário do
	-- fixture.
	local expectedMainSource = require("@lune/fs").readFile(fixturePath("basic") .. "/server/Main.server.lua")
	local rawSource = Runtime.Instance.GetPropertyRaw(mainScript, "Source")
	assert(rawSource == expectedMainSource, "Source de 'Main' deveria ser recuperável por GetPropertyRaw, igual ao conteúdo do arquivo")

	-- Invisível ao script: Source está FORA do ClassSchema de Script -- __index estrito erra
	-- "is not a valid member" para quem tenta ler mainScript.Source como o script do usuário faria.
	local sourceReadOk = pcall(function()
		local mainScriptDot = (mainScript :: unknown) :: { [string]: unknown }
		return mainScriptDot["Source"]
	end)
	assert(not sourceReadOk, "Source NÃO deveria ser legível por acesso normal (__index) -- só por GetPropertyRaw")

	-- Ordem determinística de Scripts: pré-ordem sobre o plano já ordenado por nome -- Foo
	-- (ReplicatedStorage.Modules.Foo, "R" < "S") vem antes de Main (ServerScriptService.Main).
	assert(#tree.Scripts == 2, `esperava exatamente 2 scripts materializados (ModuleScript Foo + Script Main), achou {#tree.Scripts}`)
	assert(tree.Scripts[1].Node.Name == "Foo", `primeiro script deveria ser 'Foo', achou '{tree.Scripts[1].Node.Name}'`)
	assert(tree.Scripts[1].Instance == foo, "MaterializedScript[1].Instance deveria ser o MESMO objeto que game.ReplicatedStorage.Modules.Foo")
	assert(tree.Scripts[2].Node.Name == "Main", `segundo script deveria ser 'Main', achou '{tree.Scripts[2].Node.Name}'`)
	assert(tree.Scripts[2].Instance == mainScript, "MaterializedScript[2].Instance deveria ser o MESMO objeto que game.ServerScriptService.Main")
	assert(string.find(tree.Scripts[2].FullName, "Main", 1, true) ~= nil, "FullName deveria citar o nome do script")

	assert(tree.Game == game, "MaterializedTree.Game deveria ser o MESMO DataModel passado a Materialize")
end)

--------------------------------------------------------------------------------------------------
-- $properties (Decisão 7): primitivo válido aplicado; nome inválido e propriedade somente-leitura
-- viram Diagnostic sem derrubar o comando nem impedir o resto do nó de existir
--------------------------------------------------------------------------------------------------

test("Materialize: $properties primitivo válido é aplicado; nome inválido e propriedade somente-leitura viram Diagnostic (não derrubam o comando)", function()
	local plan, planBag = planFixture("properties")
	assert(plan ~= nil, `fixture 'properties' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	-- Materialize NÃO propaga erro nenhum como exceção Lua -- chegar até aqui já é parte do teste.
	local replicatedStorage = game:FindFirstChildOfClass("ReplicatedStorage")
	assert(replicatedStorage ~= nil, "game deveria ter ReplicatedStorage")
	if replicatedStorage == nil then
		return
	end

	local badProps = findChild(replicatedStorage, "BadProps")
	assert(badProps ~= nil, "a Instance 'BadProps' deveria existir mesmo com $properties parcialmente inválido -- só a propriedade individual falha, não o nó inteiro")
	if badProps == nil then
		return
	end
	assert(badProps.ClassName == "Folder", "BadProps deveria ser um Folder")

	-- $properties primitivo válido (archivable: false) -- aplicado pela via pública de verdade.
	local badPropsDot = (badProps :: unknown) :: { [string]: unknown }
	assert(badPropsDot["archivable"] == false, "'archivable' deveria ter sido aplicado como false via $properties")

	-- Nome inválido ("Gravty" não é membro de Folder/Instance) -> Diagnostic, nunca crash.
	local invalidNameDiagnostic = findByCode(bag, "materialize/invalid-property")
	assert(invalidNameDiagnostic ~= nil, "deveria haver ao menos um Diagnostic 'materialize/invalid-property'")
	assert(countByCode(bag, "materialize/invalid-property") == 2, `esperava exatamente 2 diagnostics de propriedade inválida (nome desconhecido + somente-leitura), achou {countByCode(bag, "materialize/invalid-property")}`)

	local gravtyDiagnostic: Diagnostics.Diagnostic? = nil
	local classNameDiagnostic: Diagnostics.Diagnostic? = nil
	for _, diagnostic in bag:All() do
		if diagnostic.Code == "materialize/invalid-property" and diagnostic.Field == "Gravty" then
			gravtyDiagnostic = diagnostic
		elseif diagnostic.Code == "materialize/invalid-property" and diagnostic.Field == "className" then
			classNameDiagnostic = diagnostic
		end
	end

	assert(gravtyDiagnostic ~= nil, "deveria haver um Diagnostic citando o campo 'Gravty' (nome inválido)")
	if gravtyDiagnostic ~= nil then
		assert(gravtyDiagnostic.Severity == "error", "propriedade inválida deveria ser Severity 'error'")
		assert(gravtyDiagnostic.NodePath ~= nil and string.find(gravtyDiagnostic.NodePath, "BadProps", 1, true) ~= nil, "Diagnostic deveria citar o NodePath de 'BadProps'")
		assert(string.find(gravtyDiagnostic.Message, "Gravty", 1, true) ~= nil, "mensagem deveria citar a propriedade 'Gravty'")
	end

	-- Propriedade real, porém somente-leitura ("className", alias legado herdado de Instance).
	assert(classNameDiagnostic ~= nil, "deveria haver um Diagnostic citando o campo 'className' (somente-leitura)")
	if classNameDiagnostic ~= nil then
		assert(classNameDiagnostic.Severity == "error", "propriedade somente-leitura deveria ser Severity 'error'")
		assert(string.find(classNameDiagnostic.Message, "read only", 1, true) ~= nil, "mensagem deveria citar o erro real do motor ('read only')")
	end

	-- A propriedade somente-leitura NUNCA foi de fato sobrescrita -- continua o valor original
	-- ("Folder", o ClassName real), nunca "Hacked".
	assert(badProps.ClassName == "Folder", "ClassName real nunca deveria ter sido sobrescrito pelo $properties inválido")

	assert(#tree.Scripts == 0, "fixture 'properties' não tem nenhum Script/LocalScript/ModuleScript")
end)

--------------------------------------------------------------------------------------------------
-- task-cli-010 (correção de revisão): erro de $properties inválido NUNCA vaza caminho absoluto de
-- disco nem "TreeMaterializer:NNN:" (o call site interno do pcall, via error(msg, 2) do __newindex
-- real) -- só NodePath/Field/a mensagem real do motor. Achado MÉDIO de
-- revisor-cli-runcommand-2026-09-05.md, reproduzido por mim (thread principal) antes da correção:
-- sem o strip, `gravtyDiagnostic.Message` continha literalmente o caminho de instalação do
-- LuauBench em disco (ex.: "D:\UserData\Documents\GitHub\luaubench\src\cli\TreeMaterializer:136: ").
--------------------------------------------------------------------------------------------------

test("Materialize: erro de $properties inválido não vaza caminho absoluto de disco nem 'TreeMaterializer:NNN:' (task-cli-010)", function()
	local plan, planBag = planFixture("properties")
	assert(plan ~= nil, `fixture 'properties' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	local propertyDiagnostics: { Diagnostics.Diagnostic } = {}
	for _, diagnostic in bag:All() do
		if diagnostic.Code == "materialize/invalid-property" then
			table.insert(propertyDiagnostics, diagnostic)
		end
	end
	assert(#propertyDiagnostics == 2, `esperava 2 diagnostics de propriedade inválida, achou {#propertyDiagnostics}`)

	for _, diagnostic in propertyDiagnostics do
		-- Padrão genérico de path absoluto do Windows ("<letra>:\") -- não hardcoda o drive da
		-- máquina de quem roda o teste (poderia ser C:, D:, etc).
		assert(
			string.match(diagnostic.Message, "%a:\\") == nil,
			`mensagem de '{diagnostic.Field}' NÃO deveria conter um caminho absoluto de disco (letra:\\), achou: {diagnostic.Message}`
		)
		assert(
			string.find(diagnostic.Message, ".luau:", 1, true) == nil,
			`mensagem de '{diagnostic.Field}' NÃO deveria conter '.luau:' (chunk interno vazando), achou: {diagnostic.Message}`
		)
		assert(
			string.find(diagnostic.Message, "TreeMaterializer:", 1, true) == nil,
			`mensagem de '{diagnostic.Field}' NÃO deveria conter 'TreeMaterializer:' (call site interno do pcall vazando), achou: {diagnostic.Message}`
		)
	end

	-- A mensagem real do motor continua presente e acionável -- o strip só remove o PREFIXO de
	-- localização interna, nunca o texto que ajuda o usuário a corrigir o .project.json.
	local gravty: Diagnostics.Diagnostic? = nil
	local classNameProp: Diagnostics.Diagnostic? = nil
	for _, diagnostic in propertyDiagnostics do
		if diagnostic.Field == "Gravty" then
			gravty = diagnostic
		elseif diagnostic.Field == "className" then
			classNameProp = diagnostic
		end
	end

	assert(gravty ~= nil, "deveria haver um diagnostic para o campo 'Gravty'")
	if gravty ~= nil then
		assert(string.find(gravty.Message, "is not a valid member of", 1, true) ~= nil, "mensagem real do motor ('is not a valid member of') deveria continuar presente")
	end

	assert(classNameProp ~= nil, "deveria haver um diagnostic para o campo 'className'")
	if classNameProp ~= nil then
		assert(string.find(classNameProp.Message, "read only", 1, true) ~= nil, "mensagem real do motor ('read only') deveria continuar presente")
	end
end)

--------------------------------------------------------------------------------------------------
-- Raiz com $className != DataModel -> erro dedicado (Decisão 14) -- InstancePlan montado à mão,
-- porque TreePlanner nunca valida isto (ele só resolve ClassName, não decide se serve pra `game`).
--------------------------------------------------------------------------------------------------

test("Materialize: raiz com RootClassName != 'DataModel' produz Diagnostic dedicado e não materializa nada", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakePackageProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "Model",
		Roots = {
			{
				Name = "SomeChild",
				ClassName = "Folder",
				IsServiceRoot = false,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {},
				NodePath = "tree.SomeChild",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "raiz que não resolve para DataModel deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/root-not-datamodel")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/root-not-datamodel'")
	if diagnostic ~= nil then
		assert(string.find(diagnostic.Message, "Model", 1, true) ~= nil, "mensagem deveria citar a classe real da raiz ('Model')")
	end

	assert(#tree.Scripts == 0, "nenhum script deveria ter sido materializado -- Materialize aborta antes de tocar nos Roots")
	assert(game:FindFirstChildOfClass("Folder") == nil, "nenhuma Instance deveria ter sido criada -- 'falha antes de mutar'")
end)

--------------------------------------------------------------------------------------------------
-- Service com Name != ClassName -> erro claro (Decisão 4) -- defesa em profundidade: TreePlanner
-- já barra isto (plan/service-name-mismatch); este InstancePlan é montado à mão para provar que
-- TreeMaterializer TAMBÉM recusa, mesmo se alimentado por fora de TreePlanner.Plan.
--------------------------------------------------------------------------------------------------

test("Materialize: Service com Name != ClassName produz Diagnostic e não cria o Service", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeMismatchProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		Roots = {
			{
				Name = "NotWorkspace",
				ClassName = "Workspace",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {},
				NodePath = "tree.NotWorkspace",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "Service com nome divergente deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/service-name-mismatch")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/service-name-mismatch'")

	assert(game:FindService("Workspace") == nil, "o Workspace NUNCA deveria ter sido criado a partir de um nó com nome divergente")
	assert(#tree.Scripts == 0, "nenhum script deveria ter sido materializado")
end)

--------------------------------------------------------------------------------------------------
-- Defesa em profundidade: IsServiceRoot numa classe que o dump não marca como Service
--------------------------------------------------------------------------------------------------

test("Materialize: IsServiceRoot numa classe que não é Service produz Diagnostic 'materialize/not-a-service'", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeNotAServiceProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		Roots = {
			{
				Name = "Folder",
				ClassName = "Folder",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {},
				NodePath = "tree.Folder",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "IsServiceRoot numa classe que não é Service deveria produzir um erro")
	assert(findByCode(bag, "materialize/not-a-service") ~= nil, "deveria haver um Diagnostic 'materialize/not-a-service'")
end)

--------------------------------------------------------------------------------------------------
-- Service real do dump ainda não coberto por esta leva de `services` ("Teams") -> Diagnostic
-- "[LuauBench] ... not simulated yet", nunca o erro interno em português de DataModel.GetService
--------------------------------------------------------------------------------------------------

test("Materialize: Service tag do dump ainda não simulado ('Teams') produz Diagnostic '[LuauBench] ... not simulated yet'", function()
	assert(Services.IsServiceClass("Teams"), "sanity check: 'Teams' deveria ser uma classe Service no manifesto")
	assert(not Services.IsSimulatedClass("Teams"), "sanity check: 'Teams' não deveria estar coberta por esta leva de services")

	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeTeamsProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		Roots = {
			{
				Name = "Teams",
				ClassName = "Teams",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {},
				NodePath = "tree.Teams",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "Service não simulado deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/service-not-simulated")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/service-not-simulated'")
	if diagnostic ~= nil then
		assert(string.find(diagnostic.Message, "[LuauBench]", 1, true) ~= nil, "mensagem deveria ter o prefixo [LuauBench] (sem contraparte real -- é o LuauBench que está incompleto)")
		assert(string.find(diagnostic.Message, "not simulated", 1, true) ~= nil, "mensagem deveria seguir a família 'not simulated yet'")
	end
end)

--------------------------------------------------------------------------------------------------
-- Classe inválida/não registrada em $className explícito -> Diagnostic, nunca crash cru
--------------------------------------------------------------------------------------------------

test("Materialize: \"$className\" apontando para uma classe inexistente produz Diagnostic 'materialize/invalid-class' (nunca crash)", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeTypoProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		Roots = {
			{
				Name = "ReplicatedStorage",
				ClassName = "ReplicatedStorage",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {
					{
						Name = "Typo",
						ClassName = "Frmae",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {},
						Children = {},
						NodePath = "tree.ReplicatedStorage.Typo",
					},
				},
				NodePath = "tree.ReplicatedStorage",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "classe inexistente em $className explícito deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/invalid-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/invalid-class'")

	-- O ReplicatedStorage (Service válido, irmão do nó problemático na hierarquia -- na verdade
	-- ancestral) continua existindo -- só a subárvore do nó inválido é pulada, o resto do plano
	-- continua sendo materializado (regra 00: nunca derrubar o comando inteiro).
	assert(game:FindService("ReplicatedStorage") ~= nil, "ReplicatedStorage deveria continuar existindo mesmo com um filho inválido")
	assert(#tree.Scripts == 0, "nenhum Script/LocalScript/ModuleScript nesta fixture")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
