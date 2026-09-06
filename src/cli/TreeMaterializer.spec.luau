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
local ValueTypes = require("../valuetypes")
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

-- task-cli-028-fix: a fixture 'value-types' passou a ter DUAS propriedades que produzem
-- 'materialize/undecodable-property' (StarterPlayer.DevCameraOcclusionMode + Workspace.BadPosition.
-- Position) -- `findByCode` sozinho (primeiro match) já não basta pra distinguir qual é qual. Filtra
-- também por `Field`, mesmo padrão de busca já usado manualmente em vários testes acima (loop com
-- `diagnostic.Field == "..."`), só extraído pra função reusável.
local function findByCodeAndField(bag: Diagnostics.Bag, code: string, field: string): Diagnostics.Diagnostic?
	for _, diagnostic in bag:All() do
		if diagnostic.Code == code and diagnostic.Field == field then
			return diagnostic
		end
	end
	return nil
end

-- `Services.IsServiceClass`/`IsEngineFixedChild`/`IsEngineOnlyClass` REAIS (nunca as funções falsas
-- de TreePlanner.spec.luau) -- este território exercita a integração de verdade entre `TreePlanner`
-- e `services`. `IsEngineFixedChild`/`IsEngineOnlyClass` entraram na task-cli-024 (Decisão 17) --
-- ver "VERIFICAR" no comentário de cabeçalho: com elas reais, `TreePlanner.Plan` agora barra ANTES
-- (`plan/engine-only-class`) alguns casos que antes só o `Materialize` pegava
-- (`materialize/invalid-class`) -- os testes de defesa em profundidade, abaixo, continuam
-- alcançáveis porque montam o `InstancePlan`/`PlanNode` À MÃO, nunca via `TreePlanner.Plan`.
local REAL_PLAN_OPTIONS: TreePlanner.PlanOptions = {
	IsServiceClass = Services.IsServiceClass,
	IsEngineFixedChild = Services.IsEngineFixedChild,
	IsEngineOnlyClass = Services.IsEngineOnlyClass,
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
-- task-cli-025: classe FICTÍCIA de teste, registrada DIRETO em Runtime.ClassRegistry (nunca via
-- Services.Register -- "Part"/"BasePart" ainda não existem em services, leva 2 de services). Mesmo
-- padrão já usado por `services/init.spec.luau` ("classe FICTÍCIA de teste de ponta a ponta") e
-- `runtime/ClassRegistry.spec.luau` -- `Services.new` consulta `Runtime.ClassRegistry.Get` ANTES
-- de consultar o manifesto de `services` (ver `src/services/init.luau`, `Services.new`), então uma
-- classe registrada assim é instanciável pelo caminho de PRODUÇÃO normal
-- (`TreeMaterializer.createInstance`, ramo 3), sem nenhum atalho de teste.
--
-- Prova a ambiguidade real que motivou todo o desenho de `ValueTypes.Decode`: o MESMO array
-- `[0, -10, 0]` em "TreeMaterializerSpecPart.Position" precisa virar `Vector3`, exatamente como
-- `[0.5, 0.5, 0.5]` em "Lighting.Ambient" (classe REAL, já coberta por `services`) precisa virar
-- `Color3` -- só o `MemberDescriptor` de cada propriedade diz qual é qual. "Region" (`ValueType =
-- "Rect"`) exercita `materialize/property-type-not-simulated`: nenhuma classe REAL hoje coberta
-- por `services` tem uma propriedade não-simulada com forma de array (ver relatório da tarefa).
--------------------------------------------------------------------------------------------------
local FIXTURE_PART_CLASS_NAME = "TreeMaterializerSpecPart"

local fixturePartSchema: Runtime.ClassSchema = {
	Position = {
		Kind = "Property" :: Runtime.MemberKind,
		Default = nil,
		ReadOnly = false,
		ValueType = "Vector3",
		ValueCategory = "DataType" :: Runtime.MemberValueCategory,
	},
	-- "Rect" continua Simulated=false em `ValueTypes.Catalog.luau` nesta leva (leva 2).
	Region = {
		Kind = "Property" :: Runtime.MemberKind,
		Default = nil,
		ReadOnly = false,
		ValueType = "Rect",
		ValueCategory = "DataType" :: Runtime.MemberValueCategory,
	},
}
table.freeze(fixturePartSchema)

Runtime.ClassRegistry.Register({
	ClassName = FIXTURE_PART_CLASS_NAME,
	SuperClassName = nil,
	IsAbstract = false,
	IsService = false,
	Methods = nil,
	Schema = fixturePartSchema,
	Initialize = nil,
})

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
-- task-cli-018 (Decisão 15, Parte 2): $properties da raiz de TOPO (InstancePlan.RootProperties,
-- campo ADITIVO -- antes descartado em silêncio por TreePlanner.planProjectTree, que só devolvia
-- ClassName) é aplicado no `game` -- prova de integração real TreePlanner.Plan -> Materialize,
-- não um InstancePlan montado à mão.
--------------------------------------------------------------------------------------------------

test("Materialize: $properties da raiz de TOPO (InstancePlan.RootProperties) é aplicado no game (task-cli-018)", function()
	local plan, planBag = planFixture("root-properties")
	assert(plan ~= nil, `fixture 'root-properties' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end
	assert(next(plan.RootProperties) ~= nil, "InstancePlan.RootProperties deveria conter o \"$properties\" da raiz de topo (não descartado em silêncio)")

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(not bag:HasErrors(), `materialização não deveria produzir erro (bag: {#bag:All()} diagnostic(s))`)

	-- `game` (DataModel) nunca tem ClassSchema instalado (DataModel.luau -- construído à mão, nunca
	-- via ClassRegistry.new/SetClassSchema) -- permanece LENIENTE (Instance.luau, comentário de
	-- `ClassSchema`), então a leitura por acesso de ponto funciona igual a qualquer propriedade
	-- genérica (ao contrário de `Source`, que é gravado fora do schema via SetPropertyRaw e por
	-- isso É ilegível por acesso normal -- não é o caso aqui: "$properties" sempre vai pela via
	-- pública).
	local gameDot = (game :: unknown) :: { [string]: unknown }
	assert(gameDot["archivable"] == false, "'archivable' deveria ter sido aplicado no game via $properties da raiz de topo")
end)

--------------------------------------------------------------------------------------------------
-- task-cli-027 (achado ALTO de revisão, revisor confirmando por experimento): a guarda
-- `IsRegistered(className)` em `findMemberDescriptor` (ver comentário daquela função, acima) NUNCA
-- tinha teste de regressão cobrindo o branch que ela protege -- o revisor comprovou isso removendo a
-- guarda temporariamente e rodando a suíte inteira: 27/27 continuou passando, nenhum teste exercitava
-- este caminho.
--
-- Sem a guarda, `Runtime.ClassRegistry.GetFlattenedSchema("DataModel")` ERRA (nível 2 -- "classe
-- 'DataModel' não registrada") porque a raiz NUNCA passa por `ClassRegistry.Register` (é construída à
-- mão por `DataModel.luau`, ver o próprio comentário de `findMemberDescriptor`). Esse erro NÃO está
-- dentro de NENHUM `pcall` em `resolvePropertyValue`/`applyProperties` -- só a ESCRITA final
-- (`writable[key] = valueToWrite`) está em `pcall`, nunca a RESOLUÇÃO do MemberDescriptor -- então ele
-- se propagaria cru, sem tratamento nenhum, derrubando `Materialize` inteiro com um erro do LuauBench
-- vazando caminho absoluto em disco (`D:\...\TreeMaterializer:273: classe 'DataModel' não
-- registrada`) para um `.project.json` de usuário perfeitamente válido (qualquer `$properties`
-- não-primitivo -- array/objeto -- na raiz de topo) -- exatamente a classe de bug que task-cli-010/011
-- (documentadas no cabeçalho deste arquivo) existem para evitar, violando a regra 00 ("nunca stack
-- trace cru", "nunca crash por entrada não confiável").
--
-- `$properties` NÃO-PRIMITIVO (array) na RAIZ (`InstancePlan.RootProperties`, mecanismo já usado pelo
-- teste "$properties da raiz de TOPO" acima, task-cli-018 -- mas ali com um valor PRIMITIVO,
-- `archivable: false`) é o único jeito de alcançar `findMemberDescriptor("DataModel", ...)`: toda
-- OUTRA Instance que chega em `resolvePropertyValue` veio de `game:GetService(...)`/adoção de filho
-- fixo/`Services.new(...)` -- as três exigem classe já registrada (ver o comentário de
-- `findMemberDescriptor` para o raciocínio completo).
--
-- O teste envolve a chamada a `Materialize` num `pcall` PRÓPRIO -- nunca deixa o crash real
-- (inalcançável sem a guarda) derrubar o script de teste inteiro sem diagnóstico legível. Com a
-- guarda: `ok == true`. SEM a guarda (removida manualmente para confirmar, depois restaurada): `ok ==
-- false`, e o `assert(ok, ...)` abaixo falha com uma mensagem clara -- é essa asserção que faz ESTE
-- teste falhar caso a guarda seja removida de novo no futuro (confirmado por mim antes deste
-- relatório: comentei a guarda, rodei só este teste, `assert(ok, ...)` falhou citando o erro cru de
-- `GetFlattenedSchema`; restaurei a guarda, o teste voltou a passar).
--------------------------------------------------------------------------------------------------

test("Materialize: $properties NÃO-PRIMITIVO na raiz (DataModel, sem ClassSchema registrado) vira 'materialize/property-shape-unknown', NUNCA crasha (task-cli-027)", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeRootNonPrimitiveProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {
			Capabilities = { 1, 2, 3 },
		},
		Roots = {},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()

	-- `pcall` PRÓPRIO deste teste (não o `assert` cru de dentro de `applyProperties`/`test()`) -- é o
	-- que transforma "o processo inteiro crasha sem diagnóstico nenhum" (o bug real, sem a guarda)
	-- numa FALHA DE TESTE legível (`ok == false`) em vez de um crash opaco levando o resto da suíte
	-- junto.
	local ok, treeOrError = pcall(function(): TreeMaterializer.MaterializedTree
		return TreeMaterializer.Materialize(plan, game, bag)
	end)

	assert(ok, `Materialize NUNCA deveria crashar por $properties não-primitivo na raiz sem ClassSchema registrado -- crashou com: {tostring(treeOrError)}`)
	if not ok then
		return
	end
	local tree = treeOrError :: TreeMaterializer.MaterializedTree

	-- Warning esperado (comportamento LENIENTE já documentado para a raiz sem schema instalado) --
	-- NUNCA erro, e a propriedade nunca deveria ter sido escrita crua.
	local diagnostic = findByCodeAndField(bag, "materialize/property-shape-unknown", "Capabilities")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/property-shape-unknown' para 'Capabilities' na raiz")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "forma desconhecida na raiz deveria ser Severity 'warning', nunca erro")
		assert(diagnostic.NodePath == "tree", "Diagnostic da raiz deveria citar NodePath 'tree' (mesmo valor usado por Materialize para $properties da raiz de topo)")

		-- Mesma disciplina de task-cli-010/011: nunca vaza caminho absoluto de disco nem
		-- "TreeMaterializer:NNN:" -- confirma que, mesmo com a guarda funcionando, a mensagem de
		-- warning em si continua limpa.
		assert(string.match(diagnostic.Message, "%a:\\") == nil, `mensagem NÃO deveria conter um caminho absoluto de disco (letra:\\), achou: {diagnostic.Message}`)
		assert(string.find(diagnostic.Message, ".luau:", 1, true) == nil, `mensagem NÃO deveria conter '.luau:' (chunk interno vazando), achou: {diagnostic.Message}`)
		assert(string.find(diagnostic.Message, "TreeMaterializer:", 1, true) == nil, `mensagem NÃO deveria conter 'TreeMaterializer:' (call site interno vazando), achou: {diagnostic.Message}`)
	end

	-- `game` nunca deveria ter "Capabilities" gravado cru (array bruto do JSON) -- modo LENIENTE
	-- significa "propriedade pulada com warning", nunca "escrita sem checar tipo".
	local gameDot = (game :: unknown) :: { [string]: unknown }
	assert(gameDot["Capabilities"] == nil, "'Capabilities' NUNCA deveria ter sido gravado cru no game -- a propriedade deveria ter sido pulada")

	assert(#tree.Scripts == 0, "nenhum Root nesta fixture -- nenhum script deveria ter sido materializado")
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
		RootProperties = {},
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
		RootProperties = {},
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
		RootProperties = {},
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
		RootProperties = {},
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
		RootProperties = {},
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

--------------------------------------------------------------------------------------------------
-- task-cli-011 (correção de revisão, achado ALTO de revisor-cli-pathleak-fix-2026-09-05.md): a
-- MESMA classe de vazamento de task-cli-010 (path absoluto de disco + "TreeMaterializer:NNN:" do
-- call site interno do pcall, via error(msg, 2)) também acontecia no caminho
-- materialize/invalid-class ($className com typo, ex.: "Frmae" -> Services.new levanta o erro
-- real). Reproduzido antes da correção: a mensagem final citava literalmente
-- "D:\...\TreeMaterializer:252: Unable to create an Instance of type \"Frmae\"". Mesmo padrão de
-- grep do teste de task-cli-010, acima.
--------------------------------------------------------------------------------------------------

test("Materialize: erro de \"$className\" inválido não vaza caminho absoluto de disco nem 'TreeMaterializer:NNN:' (task-cli-011)", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeTypoProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
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
	TreeMaterializer.Materialize(plan, game, bag)

	local diagnostic = findByCode(bag, "materialize/invalid-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/invalid-class'")
	if diagnostic == nil then
		return
	end

	-- Padrão genérico de path absoluto do Windows ("<letra>:\") -- não hardcoda o drive da máquina
	-- de quem roda o teste (poderia ser C:, D:, etc).
	assert(
		string.match(diagnostic.Message, "%a:\\") == nil,
		`mensagem de '$className' inválido NÃO deveria conter um caminho absoluto de disco (letra:\\), achou: {diagnostic.Message}`
	)
	assert(
		string.find(diagnostic.Message, ".luau:", 1, true) == nil,
		`mensagem de '$className' inválido NÃO deveria conter '.luau:' (chunk interno vazando), achou: {diagnostic.Message}`
	)
	assert(
		string.find(diagnostic.Message, "TreeMaterializer:", 1, true) == nil,
		`mensagem de '$className' inválido NÃO deveria conter 'TreeMaterializer:' (call site interno do pcall vazando), achou: {diagnostic.Message}`
	)

	-- A mensagem real do motor continua presente e acionável -- o strip só remove o PREFIXO de
	-- localização interna, nunca o texto que ajuda o usuário a corrigir o "$className".
	assert(
		string.find(diagnostic.Message, "Unable to create an Instance of type", 1, true) ~= nil,
		`mensagem real do motor ('Unable to create an Instance of type') deveria continuar presente, achou: {diagnostic.Message}`
	)
	assert(string.find(diagnostic.Message, "Frmae", 1, true) ~= nil, "mensagem deveria citar a classe inválida 'Frmae'")
end)

--------------------------------------------------------------------------------------------------
-- task-cli-016: terceiro ramo de createInstance ADOTA filho fixo do motor (StarterPlayerScripts/
-- StarterCharacterScripts dentro de StarterPlayer), nunca cria -- arquiteto-cli-2026-09-05.md,
-- seção "task-cli-015". Fixture 'fixed-children' tem um LocalScript real dentro de cada um dos
-- dois filhos fixos, mais $properties no nó StarterPlayerScripts, pra provar o caminho ponta a
-- ponta (é o repro direto do bug de duplicação de StarterPlayerScripts que motivou "adotar, não
-- criar").
--------------------------------------------------------------------------------------------------

test("Materialize: fixture 'fixed-children' ADOTA StarterPlayerScripts/StarterCharacterScripts (rawequal com o filho pré-criado pelo motor, EXATAMENTE uma instância de cada, $properties aplicado)", function()
	local plan, planBag = planFixture("fixed-children")
	assert(plan ~= nil, `fixture 'fixed-children' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(not bag:HasErrors(), `materialização de 'fixed-children' não deveria produzir erro (bag: {#bag:All()} diagnostic(s))`)

	local starterPlayer = game:FindService("StarterPlayer")
	assert(starterPlayer ~= nil, "game deveria ter um StarterPlayer depois de Materialize")
	if starterPlayer == nil then
		return
	end

	-- Repro direto do bug de duplicação que motivou "adotar, não criar": EXATAMENTE UMA instância
	-- chamada StarterPlayerScripts (e uma StarterCharacterScripts) dentro de StarterPlayer -- não
	-- duas (a pré-criada pelo motor + uma segunda criada por engano).
	local starterPlayerScriptsCount = 0
	local starterCharacterScriptsCount = 0
	for _, child in starterPlayer:GetChildren() do
		if child.Name == "StarterPlayerScripts" then
			starterPlayerScriptsCount += 1
		elseif child.Name == "StarterCharacterScripts" then
			starterCharacterScriptsCount += 1
		end
	end
	assert(starterPlayerScriptsCount == 1, `esperava EXATAMENTE 1 filho chamado StarterPlayerScripts dentro de StarterPlayer, achou {starterPlayerScriptsCount}`)
	assert(starterCharacterScriptsCount == 1, `esperava EXATAMENTE 1 filho chamado StarterCharacterScripts dentro de StarterPlayer, achou {starterCharacterScriptsCount}`)

	local starterPlayerScripts = starterPlayer:FindFirstChild("StarterPlayerScripts")
	local starterCharacterScripts = starterPlayer:FindFirstChild("StarterCharacterScripts")
	assert(starterPlayerScripts ~= nil, "StarterPlayer deveria ter StarterPlayerScripts")
	assert(starterCharacterScripts ~= nil, "StarterPlayer deveria ter StarterCharacterScripts")
	if starterPlayerScripts == nil or starterCharacterScripts == nil then
		return
	end

	-- Prova que ADOTOU, não criou: o MESMO objeto que game:GetService('StarterPlayer'):FindFirstChild(...) devolve (rawequal, não só ==).
	-- Reusa o `starterPlayer` já estreitado acima (via game:FindService, linha 644) em vez de
	-- chamar `game:GetService("StarterPlayer")` de novo aqui -- é o MESMO singleton (StarterPlayer
	-- só existe uma vez sob `game`), e evita reintroduzir um `Instance?` não estreitado
	-- (DataModel:GetService passou de `-> Instance` para `-> Instance?`, task-runtime-030).
	assert(rawequal(starterPlayerScripts, starterPlayer:FindFirstChild("StarterPlayerScripts")), "StarterPlayerScripts deveria ser o MESMO objeto pré-criado pelo motor (rawequal)")
	assert(rawequal(starterCharacterScripts, starterPlayer:FindFirstChild("StarterCharacterScripts")), "StarterCharacterScripts deveria ser o MESMO objeto pré-criado pelo motor (rawequal)")

	assert(starterPlayerScripts.ClassName == "StarterPlayerScripts", "StarterPlayerScripts adotado deveria manter seu ClassName real")
	assert(starterCharacterScripts.ClassName == "StarterCharacterScripts", "StarterCharacterScripts adotado deveria manter seu ClassName real")

	-- $properties aplicado NA INSTÂNCIA DO MOTOR (Decisão 7 -- via pública, __newindex real, não SetPropertyRaw).
	local starterPlayerScriptsDot = (starterPlayerScripts :: unknown) :: { [string]: unknown }
	assert(starterPlayerScriptsDot["archivable"] == false, "'archivable' deveria ter sido aplicado como false via $properties na instância ADOTADA (do motor)")

	-- Camera.client.luau / Equip.client.luau materializados de verdade DENTRO dos filhos adotados.
	local camera = starterPlayerScripts:FindFirstChild("Camera")
	assert(camera ~= nil, "StarterPlayerScripts (adotado) deveria ter um filho 'Camera'")
	if camera ~= nil then
		assert(camera.ClassName == "LocalScript", "'Camera.client.luau' deveria materializar como LocalScript")
	end

	local equip = starterCharacterScripts:FindFirstChild("Equip")
	assert(equip ~= nil, "StarterCharacterScripts (adotado) deveria ter um filho 'Equip'")
	if equip ~= nil then
		assert(equip.ClassName == "LocalScript", "'Equip.client.luau' deveria materializar como LocalScript")
	end

	assert(#tree.Scripts == 2, `esperava exatamente 2 scripts materializados (Camera + Equip), achou {#tree.Scripts}`)
end)

test("Materialize: adoção de filho fixo do motor NÃO dispara ChildAdded/ChildRemoved/AncestryChanged espúrios (task-cli-016)", function()
	local plan, planBag = planFixture("fixed-children")
	assert(plan ~= nil, `fixture 'fixed-children' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()

	-- Cria o singleton StarterPlayer (e os dois filhos fixos, via behavior/StarterPlayer.Initialize)
	-- ANTES de conectar os eventos -- só nos interessa o que acontece durante a ADOÇÃO em
	-- Materialize, nunca a criação inicial do motor no bootstrap.
	-- `DataModel:GetService` passou de `-> Instance` para `-> Instance?` (task-runtime-030) --
	-- "StarterPlayer" está sempre coberta pelo `Bootstrap` de `newGame()`, então o `nil` é
	-- inalcançável aqui.
	local starterPlayer = game:GetService("StarterPlayer")
	assert(starterPlayer ~= nil, "sanity check: StarterPlayer deveria estar coberto pelo Bootstrap deste teste")
	if starterPlayer == nil then
		return
	end
	local starterPlayerScripts = starterPlayer:FindFirstChild("StarterPlayerScripts")
	local starterCharacterScripts = starterPlayer:FindFirstChild("StarterCharacterScripts")
	assert(starterPlayerScripts ~= nil and starterCharacterScripts ~= nil, "sanity check: StarterPlayer deveria já ter os dois filhos fixos pré-criados pelo motor")
	if starterPlayerScripts == nil or starterCharacterScripts == nil then
		return
	end

	local events: { string } = {}
	local childAddedConn = starterPlayer.ChildAdded:Connect(function(child: Runtime.Instance)
		table.insert(events, `ChildAdded({child.Name})`)
	end)
	local childRemovedConn = starterPlayer.ChildRemoved:Connect(function(child: Runtime.Instance)
		table.insert(events, `ChildRemoved({child.Name})`)
	end)
	local playerScriptsAncestryConn = starterPlayerScripts.AncestryChanged:Connect(function(instance: Runtime.Instance)
		table.insert(events, `AncestryChanged({instance.Name})`)
	end)
	local characterScriptsAncestryConn = starterCharacterScripts.AncestryChanged:Connect(function(instance: Runtime.Instance)
		table.insert(events, `AncestryChanged({instance.Name})`)
	end)

	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	childAddedConn:Disconnect()
	childRemovedConn:Disconnect()
	playerScriptsAncestryConn:Disconnect()
	characterScriptsAncestryConn:Disconnect()

	assert(not bag:HasErrors(), `materialização não deveria produzir erro (bag: {#bag:All()} diagnostic(s))`)
	assert(#events == 0, `nenhum evento deveria disparar na adoção do filho fixo (ChildAdded/ChildRemoved em StarterPlayer, AncestryChanged nos filhos adotados), achou: {table.concat(events, ", ")}`)
end)

--------------------------------------------------------------------------------------------------
-- Nó com Name divergente do trio exigido ("MyScripts" com $className "StarterPlayerScripts" sob
-- StarterPlayer) NÃO é adotado -- Services.IsEngineFixedChild exige Name E ClassName batendo, então
-- cai no ramo normal (Services.new) e erra a família Roblox real, igual ao Roblox faria.
--
-- MUDANÇA DE FASE (task-cli-024, arquiteto-cli-2026-09-05.md, Decisão 17, seção "Riscos" -- este é
-- exatamente o teste ":812 (ramo normal Services.new)" que a Decisão previu que mudaria): com
-- `Services.IsEngineFixedChild`/`IsEngineOnlyClass` REAIS agora injetadas em `REAL_PLAN_OPTIONS`
-- (acima), `TreePlanner.Plan` passou a barrar este MESMO cenário mais cedo, com
-- 'plan/engine-only-class' -- o teste abaixo ("Plan: ...") prova isso. O teste ORIGINAL, aqui embaixo,
-- FOI ADAPTADO (não removido) pra continuar provando que a defesa em profundidade do PRÓPRIO
-- `TreeMaterializer` (o `pcall(Services.new)` no ramo normal) segue intacta e alcançável -- com um
-- `InstancePlan` MONTADO À MÃO, nunca via `TreePlanner.Plan` de verdade (mesma disciplina já usada
-- pelas defesas em profundidade acima, ex.: "$className" -> "Frmae"). Decisão 17, "O que
-- deliberadamente NÃO fazer agora": "não mover a guarda para TreeMaterializer nem remover de lá a
-- defesa em profundidade -- as duas camadas coexistem como já coexistem para service-name-mismatch".
--------------------------------------------------------------------------------------------------

test("Materialize (defesa em profundidade -- InstancePlan montado à mão): \"$className\" explícito com Name divergente ('MyScripts') sob StarterPlayer NÃO é adotado -- erra via Services.new normal, família Roblox real", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeFixedChildNameMismatch",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
		Roots = {
			{
				Name = "StarterPlayer",
				ClassName = "StarterPlayer",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {
					{
						Name = "MyScripts",
						ClassName = "StarterPlayerScripts",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {},
						Children = {},
						NodePath = "tree.StarterPlayer.MyScripts",
					},
				},
				NodePath = "tree.StarterPlayer",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "'MyScripts' com $className 'StarterPlayerScripts' deveria falhar -- Name não bate o filho fixo declarado")
	local diagnostic = findByCode(bag, "materialize/invalid-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/invalid-class' (ramo normal Services.new, não o de adoção)")
	if diagnostic ~= nil then
		assert(string.find(diagnostic.Message, "Unable to create an Instance of type", 1, true) ~= nil, "mensagem deveria ser a família Roblox real 'Unable to create an Instance of type ...'")
		assert(string.find(diagnostic.Message, "StarterPlayerScripts", 1, true) ~= nil, "mensagem deveria citar a classe 'StarterPlayerScripts'")
	end

	assert(findByCode(bag, "materialize/fixed-child-missing") == nil, "NÃO deveria ter passado pelo ramo de adoção -- Name diverge do trio exigido")
	assert(findByCode(bag, "materialize/fixed-child-class-mismatch") == nil, "NÃO deveria ter passado pelo ramo de adoção -- Name diverge do trio exigido")

	local starterPlayer = game:FindService("StarterPlayer")
	assert(starterPlayer ~= nil, "StarterPlayer (Service real, sem relação com o filho inválido) deveria continuar existindo")
	if starterPlayer ~= nil then
		assert(starterPlayer:FindFirstChild("MyScripts") == nil, "'MyScripts' nunca deveria ter sido criado")
	end
end)

test("Plan: \"$className\" explícito com Name divergente ('MyScripts') sob StarterPlayer é barrado em TreePlanner.Plan -- 'plan/engine-only-class' (task-cli-024, muda de fase em relação ao teste acima)", function()
	local plan, planBag = planFixture("fixed-child-name-mismatch")
	assert(plan == nil, "'MyScripts' com $className 'StarterPlayerScripts' deveria impedir TreePlanner.Plan de devolver um InstancePlan -- a guarda nova (Decisão 17) dispara ANTES de Materialize")

	local diagnostic = findByCode(planBag, "plan/engine-only-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/engine-only-class'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "classe só-do-motor em posição de nó deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.StarterPlayer.MyScripts", "Diagnostic deveria nomear o nó exato")
		assert(diagnostic.Field == "$className", "Diagnostic deveria nomear o CAMPO ($className)")
		assert(string.find(diagnostic.Message, "StarterPlayerScripts", 1, true) ~= nil, "Message deveria citar a classe 'StarterPlayerScripts'")
		assert(string.find(diagnostic.Message, "NotCreatable", 1, true) ~= nil, "Message deveria citar a tag 'NotCreatable' do Roblox API Dump como justificativa")
	end

	assert(findByCode(planBag, "materialize/invalid-class") == nil, "NÃO deveria haver 'materialize/invalid-class' -- 'plan/engine-only-class' já retornou nil antes de Materialize sequer rodar")
end)

--------------------------------------------------------------------------------------------------
-- Regressão: Workspace.Terrain (Covered=false, services NÃO pré-cria) continua errando com a
-- família "[LuauBench] ... not simulated yet" -- NÃO é tratado como filho fixo do motor
-- (EngineFixedChildren só declara StarterPlayer -- Workspace nunca é chave dessa tabela, ver
-- arquiteto-cli-2026-09-05.md, "Onde vive a lista fechada, e por que não é a mesma de SyncRules").
-- Reusa a fixture 'fixed-children' JÁ EXISTENTE de TreePlanner (task-cli-014,
-- src/cli/fixtures/tree-planner/fixed-children/, que já tem Workspace/Terrain) -- não duplica
-- fixture só para isto.
--------------------------------------------------------------------------------------------------

test("Materialize: Workspace.Terrain continua errando com '[LuauBench] ... not simulated yet' (não regride, não passa a mentir que foi adotado)", function()
	local treePlannerFixturesRoot = process.cwd .. "src/cli/fixtures/tree-planner"
	local planBag = Diagnostics.newBag()
	local project = ProjectFile.Read(treePlannerFixturesRoot .. "/fixed-children/default.project.json", planBag)
	assert(project ~= nil, `fixture 'tree-planner/fixed-children' deveria ler (bag: {#planBag:All()} diagnostic(s))`)
	if project == nil then
		return
	end
	local plan = TreePlanner.Plan(project, REAL_PLAN_OPTIONS, planBag)
	assert(plan ~= nil, "fixture 'tree-planner/fixed-children' deveria planejar sem erro")
	assert(not planBag:HasErrors(), `TreePlanner não deveria produzir erro pra esta fixture (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- StarterPlayer continua sendo adotado sem erro -- a mesma fixture cobre os dois casos ao
	-- mesmo tempo, provando que os dois ramos (adoção e "not simulated yet") coexistem sem
	-- interferência.
	assert(findByCode(bag, "materialize/fixed-child-missing") == nil, "StarterPlayer não deveria ter erro de filho fixo faltando")
	assert(findByCode(bag, "materialize/fixed-child-class-mismatch") == nil, "StarterPlayer não deveria ter erro de classe divergente")

	local terrainDiagnostic = findByCode(bag, "materialize/invalid-class")
	assert(terrainDiagnostic ~= nil, "Workspace.Terrain deveria produzir 'materialize/invalid-class' (services não pré-cria Terrain, Covered=false)")
	if terrainDiagnostic ~= nil then
		assert(string.find(terrainDiagnostic.Message, "[LuauBench]", 1, true) ~= nil, "mensagem deveria ter o prefixo [LuauBench] (LuauBench incompleto, não o Roblox)")
		assert(string.find(terrainDiagnostic.Message, "not simulated", 1, true) ~= nil, "mensagem deveria seguir a família 'not simulated yet'")
	end

	local workspaceService = game:FindService("Workspace")
	assert(workspaceService ~= nil, "Workspace deveria continuar existindo mesmo com Terrain falhando")
	if workspaceService ~= nil then
		assert(workspaceService:FindFirstChild("Terrain") == nil, "Terrain NUNCA deveria ter sido criado -- LuauBench não pode fingir que simula")
	end
end)

--------------------------------------------------------------------------------------------------
-- Defesa em profundidade (task-cli-016): os dois diagnósticos novos só são alcançáveis se a
-- instância que o motor pré-criou for removida/substituída DEPOIS do bootstrap -- não há como
-- reproduzir isto com `services`/`behavior/StarterPlayer.luau` reais (task-services-010 garante
-- coerência entre EngineFixedChildren e Initialize: para toda entrada declarada,
-- game:GetService(pai):FindFirstChild(nome) sempre existe com o ClassName certo). Simulado aqui
-- manipulando o singleton StarterPlayer JÁ CRIADO, só com API PÚBLICA (game:GetService, Destroy,
-- Services.new, .Parent) -- mesma disciplina dos outros diagnósticos de defesa em profundidade
-- deste arquivo (NUNCA chama NewEngineInstance -- proibido em todo src/cli/**, inclusive specs).
--------------------------------------------------------------------------------------------------

test("Materialize: 'materialize/fixed-child-missing' quando o filho pré-criado pelo motor foi removido antes da adoção", function()
	local game = newGame()
	-- `DataModel:GetService` passou de `-> Instance` para `-> Instance?` (task-runtime-030) --
	-- "StarterPlayer" está sempre coberta pelo `Bootstrap` de `newGame()`, então o `nil` é
	-- inalcançável aqui.
	local starterPlayer = game:GetService("StarterPlayer")
	assert(starterPlayer ~= nil, "sanity check: StarterPlayer deveria estar coberto pelo Bootstrap deste teste")
	if starterPlayer == nil then
		return
	end
	local existing = starterPlayer:FindFirstChild("StarterPlayerScripts")
	assert(existing ~= nil, "sanity check: StarterPlayer deveria nascer com StarterPlayerScripts pré-criado pelo motor")
	if existing ~= nil then
		existing:Destroy()
	end
	assert(starterPlayer:FindFirstChild("StarterPlayerScripts") == nil, "sanity check: StarterPlayerScripts deveria ter sido removido")

	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeFixedChildMissingProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
		Roots = {
			{
				Name = "StarterPlayer",
				ClassName = "StarterPlayer",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {
					{
						Name = "StarterPlayerScripts",
						ClassName = "StarterPlayerScripts",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {},
						Children = {},
						NodePath = "tree.StarterPlayer.StarterPlayerScripts",
					},
				},
				NodePath = "tree.StarterPlayer",
			},
		},
		Diagnostics = {},
	}

	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "filho fixo faltando deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/fixed-child-missing")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/fixed-child-missing'")
	if diagnostic ~= nil then
		assert(string.find(diagnostic.Message, "StarterPlayerScripts", 1, true) ~= nil, "mensagem deveria citar a classe 'StarterPlayerScripts'")
		assert(string.find(diagnostic.Message, "StarterPlayer", 1, true) ~= nil, "mensagem deveria citar o pai 'StarterPlayer'")
	end
end)

test("Materialize: 'materialize/fixed-child-class-mismatch' quando a instância achada tem ClassName diferente do esperado", function()
	local game = newGame()
	-- `DataModel:GetService` passou de `-> Instance` para `-> Instance?` (task-runtime-030) --
	-- "StarterPlayer" está sempre coberta pelo `Bootstrap` de `newGame()`, então o `nil` é
	-- inalcançável aqui.
	local starterPlayer = game:GetService("StarterPlayer")
	assert(starterPlayer ~= nil, "sanity check: StarterPlayer deveria estar coberto pelo Bootstrap deste teste")
	if starterPlayer == nil then
		return
	end
	local existing = starterPlayer:FindFirstChild("StarterPlayerScripts")
	assert(existing ~= nil, "sanity check: StarterPlayer deveria nascer com StarterPlayerScripts pré-criado pelo motor")
	if existing ~= nil then
		existing:Destroy()
	end

	-- Impostor: mesmo Name, ClassName diferente -- só alcançável se EngineFixedChildren/Initialize
	-- divergirem de verdade (nunca via um .project.json legítimo).
	local impostor = Services.new("Folder", "StarterPlayerScripts")
	impostor.Parent = starterPlayer
	assert(starterPlayer:FindFirstChild("StarterPlayerScripts") == impostor, "sanity check: o impostor deveria estar parenteado como 'StarterPlayerScripts'")

	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeFixedChildMismatchProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
		Roots = {
			{
				Name = "StarterPlayer",
				ClassName = "StarterPlayer",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {
					{
						Name = "StarterPlayerScripts",
						ClassName = "StarterPlayerScripts",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {},
						Children = {},
						NodePath = "tree.StarterPlayer.StarterPlayerScripts",
					},
				},
				NodePath = "tree.StarterPlayer",
			},
		},
		Diagnostics = {},
	}

	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	assert(bag:HasErrors(), "ClassName divergente na instância achada deveria produzir um erro")
	local diagnostic = findByCode(bag, "materialize/fixed-child-class-mismatch")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/fixed-child-class-mismatch'")
	if diagnostic ~= nil then
		assert(string.find(diagnostic.Message, "StarterPlayerScripts", 1, true) ~= nil, "mensagem deveria citar o ClassName esperado 'StarterPlayerScripts'")
		assert(string.find(diagnostic.Message, "Folder", 1, true) ~= nil, "mensagem deveria citar o ClassName real achado 'Folder'")
	end
end)

--------------------------------------------------------------------------------------------------
-- task-cli-025 (arquiteto-valuetypes-2026-09-05.md, seção 3.4 "cli" / Decisão 5, seção 7):
-- $properties não-primitivo decodifica pelo MemberDescriptor da classe REAL -- mesmo array [x,y,z]
-- vira Color3 numa propriedade e Vector3 noutra; tipo ainda não simulado vira warning [LuauBench];
-- forma malformada vira erro citando o motivo do Decode; propriedade sem MemberDescriptor
-- conhecido nunca escreve a tabela crua.
--------------------------------------------------------------------------------------------------

test("Materialize: [0.5,0.5,0.5] em Lighting.Ambient vira Color3 e o MESMO formato em Baseplate.Position vira Vector3 (task-cli-025)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	local lighting = game:FindFirstChildOfClass("Lighting")
	assert(lighting ~= nil, "game deveria ter um Lighting depois de Materialize")
	if lighting == nil then
		return
	end
	local lightingDot = (lighting :: unknown) :: { [string]: unknown }
	local ambient = lightingDot["Ambient"]
	assert(ValueTypes.TypeNameOf(ambient) == "Color3", `Lighting.Ambient deveria ter virado um Color3 real, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(ambient))}`)
	assert(tostring(ambient) == "0.5, 0.5, 0.5", `Lighting.Ambient deveria ser Color3.new(0.5, 0.5, 0.5), tostring deu "{tostring(ambient)}"`)

	local workspaceInstance = game:FindFirstChildOfClass("Workspace")
	assert(workspaceInstance ~= nil, "game deveria ter um Workspace depois de Materialize")
	if workspaceInstance == nil then
		return
	end
	local baseplate = findChild(workspaceInstance, "Baseplate")
	assert(baseplate ~= nil, "Workspace deveria ter um filho 'Baseplate'")
	if baseplate == nil then
		return
	end
	local baseplateDot = (baseplate :: unknown) :: { [string]: unknown }
	local position = baseplateDot["Position"]
	assert(ValueTypes.TypeNameOf(position) == "Vector3", `Baseplate.Position deveria ter virado um Vector3 real, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(position))}`)
	assert(tostring(position) == "0, -10, 0", `Baseplate.Position deveria ser Vector3.new(0, -10, 0), tostring deu "{tostring(position)}"`)
end)

test("Materialize: ValueType ainda não simulado (Rect) vira warning '[LuauBench] ... not simulated' e a propriedade não é escrita (task-cli-025)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	local diagnostic = findByCode(bag, "materialize/property-type-not-simulated")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/property-type-not-simulated'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "tipo não simulado deveria ser Severity 'warning', nunca erro")
		assert(diagnostic.Field == "Region", "Diagnostic deveria citar a propriedade 'Region'")
		assert(string.find(diagnostic.Message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {diagnostic.Message}`)
		assert(string.find(diagnostic.Message, "Rect", 1, true) ~= nil, "mensagem deveria citar o ValueType 'Rect'")
	end

	local workspaceInstance = game:FindFirstChildOfClass("Workspace")
	assert(workspaceInstance ~= nil, "game deveria ter Workspace")
	if workspaceInstance == nil then
		return
	end
	local baseplate = findChild(workspaceInstance, "Baseplate")
	assert(baseplate ~= nil, "deveria haver um 'Baseplate'")
	if baseplate == nil then
		return
	end
	local baseplateDot = (baseplate :: unknown) :: { [string]: unknown }
	assert(baseplateDot["Region"] == nil, "Region deveria ter mantido o Default (nil) do schema -- nunca gravar o array cru")
end)

test("Materialize: forma indecodificável (array de tamanho errado) vira erro 'materialize/undecodable-property' citando o motivo (task-cli-025)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- task-cli-028-fix: `findByCode` sozinho não basta mais -- a fixture agora tem OUTRO
	-- 'materialize/undecodable-property' (StarterPlayer.DevCameraOcclusionMode). Filtra também por
	-- `Field` pra continuar mirando especificamente em 'Position'.
	local diagnostic = findByCodeAndField(bag, "materialize/undecodable-property", "Position")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/undecodable-property' para o campo 'Position'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "forma indecodificável deveria ser Severity 'error'")
		assert(string.find(diagnostic.Message, "Vector3", 1, true) ~= nil, "mensagem deveria citar o ValueType alvo 'Vector3'")
		assert(diagnostic.NodePath ~= nil and string.find(diagnostic.NodePath, "BadPosition", 1, true) ~= nil, "Diagnostic deveria citar o nó 'BadPosition'")
	end

	local workspaceInstance = game:FindFirstChildOfClass("Workspace")
	assert(workspaceInstance ~= nil, "game deveria ter Workspace")
	if workspaceInstance == nil then
		return
	end
	local badPosition = findChild(workspaceInstance, "BadPosition")
	assert(badPosition ~= nil, "deveria haver um 'BadPosition' mesmo com a propriedade malformada -- só a propriedade falha, não o nó inteiro")
	if badPosition == nil then
		return
	end
	local badPositionDot = (badPosition :: unknown) :: { [string]: unknown }
	assert(badPositionDot["Position"] == nil, "Position deveria ter mantido o Default (nil) -- nunca gravar a forma malformada")
end)

test("Materialize: propriedade não-primitiva sem MemberDescriptor conhecido vira warning 'materialize/property-shape-unknown' (task-cli-025)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	local diagnostic = findByCode(bag, "materialize/property-shape-unknown")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/property-shape-unknown'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "forma desconhecida deveria ser Severity 'warning', nunca erro")
		assert(diagnostic.Field == "Mystery", "Diagnostic deveria citar a propriedade 'Mystery'")
		assert(string.find(diagnostic.Message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {diagnostic.Message}`)
	end

	local workspaceInstance = game:FindFirstChildOfClass("Workspace")
	assert(workspaceInstance ~= nil, "game deveria ter Workspace")
	if workspaceInstance == nil then
		return
	end
	local unknownShape = findChild(workspaceInstance, "UnknownShape")
	assert(unknownShape ~= nil, "deveria haver um 'UnknownShape' mesmo com a propriedade não-decodificável -- só a propriedade falha, não o nó inteiro")
	if unknownShape ~= nil then
		assert(unknownShape.ClassName == "Folder", "UnknownShape deveria ser um Folder")
	end
end)

--------------------------------------------------------------------------------------------------
-- task-cli-027 (task-runtime-036 expôs Runtime.ClassRegistry.GetFlattenedSchema publicamente):
-- propriedade HERDADA (declarada só numa SUPERCLASSE da cadeia, nunca redeclarada pela classe
-- concreta) precisa resolver o MemberDescriptor CERTO -- diagnóstico ESPECÍFICO (aqui,
-- property-type-not-simulated, porque "SecurityCapabilities"/"ContentId" continuam leva-2 em
-- ValueTypes.Catalog), NUNCA mais o genérico 'property-shape-unknown' que a limitação antiga
-- (findMemberDescriptor só olhando o schema PRÓPRIO da classe) produzia para os dois casos abaixo.
-- InstancePlan MONTADO À MÃO (mesma disciplina das defesas em profundidade acima) -- não precisa de
-- fixture em disco, só exercitar findMemberDescriptor com uma classe REAL cuja propriedade é
-- herdada.
--------------------------------------------------------------------------------------------------

test("Materialize: propriedade HERDADA de Instance (Folder.Capabilities, Generated.Schema de Folder é vazio) resolve o MemberDescriptor certo -- 'materialize/property-type-not-simulated', NUNCA o genérico 'property-shape-unknown' (task-cli-027)", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeInheritedPropertyProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
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
						-- "Capabilities" NUNCA é declarada por "Folder" (Generated.Schema vazio, ver
						-- src/services/generated/classes/Folder.luau) -- só existe na cadeia via
						-- "Instance" (a superclasse universal, ver generated/classes/Instance.luau). Um
						-- array (não-primitivo) força resolvePropertyValue a consultar
						-- findMemberDescriptor -- boolean/number bypassariam sem nunca exercitar o bug.
						Name = "InheritedPropsFolder",
						ClassName = "Folder",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {
							Capabilities = { "CoreScript" },
						},
						Children = {},
						NodePath = "tree.ReplicatedStorage.InheritedPropsFolder",
					},
				},
				NodePath = "tree.ReplicatedStorage",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- ANTES desta tarefa: findMemberDescriptor só olhava ClassRegistry.Get("Folder").Schema (vazio)
	-- -- "Capabilities" caía sempre no diagnóstico genérico, mesmo sendo uma propriedade real e
	-- conhecida (só herdada). Prova que isso não acontece mais.
	assert(findByCodeAndField(bag, "materialize/property-shape-unknown", "Capabilities") == nil, "'Capabilities' (herdada de Instance) NÃO deveria mais cair no diagnóstico genérico 'property-shape-unknown'")

	-- "SecurityCapabilities" (o ValueType real de Instance.Capabilities no dump) continua leva-2 em
	-- ValueTypes.Catalog -- o diagnóstico ESPECÍFICO correto, agora que o MemberDescriptor herdado é
	-- encontrado, é o de tipo ainda não simulado (warning, nunca erro).
	local diagnostic = findByCodeAndField(bag, "materialize/property-type-not-simulated", "Capabilities")
	assert(diagnostic ~= nil, "'Capabilities' deveria produzir 'materialize/property-type-not-simulated', citando o ValueType real herdado de Instance")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "tipo não simulado deveria ser Severity 'warning', nunca erro")
		assert(string.find(diagnostic.Message, "SecurityCapabilities", 1, true) ~= nil, `mensagem deveria citar o ValueType herdado 'SecurityCapabilities', recebeu: {diagnostic.Message}`)
	end

	local replicatedStorage = game:FindService("ReplicatedStorage")
	assert(replicatedStorage ~= nil, "game deveria ter ReplicatedStorage")
	if replicatedStorage == nil then
		return
	end
	local folder = findChild(replicatedStorage, "InheritedPropsFolder")
	assert(folder ~= nil, "deveria haver um 'InheritedPropsFolder' mesmo com a propriedade herdada ainda não simulada -- só a propriedade falha, não o nó inteiro")
	if folder ~= nil then
		local folderDot = (folder :: unknown) :: { [string]: unknown }
		assert(folderDot["Capabilities"] == nil, "Capabilities deveria ter mantido o Default (nil) -- nunca gravar o array cru")
	end
end)

test("Materialize: propriedade HERDADA de BaseScript (Script.LinkedSource, superclasse direta na cadeia) resolve o MemberDescriptor certo -- 'materialize/property-type-not-simulated', NUNCA o genérico 'property-shape-unknown' (task-cli-027)", function()
	local plan: TreePlanner.InstancePlan = {
		ProjectName = "FakeInheritedScriptPropertyProject",
		ProjectPath = "fake/default.project.json",
		RootClassName = "DataModel",
		RootProperties = {},
		Roots = {
			{
				Name = "ServerScriptService",
				ClassName = "ServerScriptService",
				IsServiceRoot = true,
				Source = nil,
				SourcePath = nil,
				Properties = {},
				Children = {
					{
						-- "LinkedSource" é declarada por "BaseScript" (a SUPERCLASSE DIRETA de "Script",
						-- `Script.Superclass == "BaseScript"`, ver src/services/generated/classes/
						-- Script.luau), NUNCA redeclarada em Script.Generated.Schema (vazio) -- 1 hop na
						-- cadeia, não 2: CORREÇÃO de comentário anterior que afirmava erroneamente "dois
						-- níveis acima"/"além do pai direto" (achado MÉDIO de revisão, task-cli-027).
						-- BaseScript já É o pai direto de Script; um exemplo de achatamento
						-- GENUINAMENTE multi-hop (vários níveis reais) seria Workspace.Capabilities
						-- (Workspace -> WorldRoot -> Model -> PVInstance -> Instance, 4 hops).
						Name = "InheritedPropsScript",
						ClassName = "Script",
						IsServiceRoot = false,
						Source = nil,
						SourcePath = nil,
						Properties = {
							LinkedSource = { "rbxassetid://0" },
						},
						Children = {},
						NodePath = "tree.ServerScriptService.InheritedPropsScript",
					},
				},
				NodePath = "tree.ServerScriptService",
			},
		},
		Diagnostics = {},
	}

	local game = newGame()
	local bag = Diagnostics.newBag()
	local tree = TreeMaterializer.Materialize(plan, game, bag)

	assert(findByCodeAndField(bag, "materialize/property-shape-unknown", "LinkedSource") == nil, "'LinkedSource' (herdada da superclasse direta BaseScript) NÃO deveria mais cair no diagnóstico genérico 'property-shape-unknown'")

	-- "ContentId" (o ValueType real de BaseScript.LinkedSource no dump) continua leva-2 em
	-- ValueTypes.Catalog -- mesmo raciocínio do teste de "Capabilities" acima.
	local diagnostic = findByCodeAndField(bag, "materialize/property-type-not-simulated", "LinkedSource")
	assert(diagnostic ~= nil, "'LinkedSource' deveria produzir 'materialize/property-type-not-simulated', citando o ValueType real herdado de BaseScript")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "tipo não simulado deveria ser Severity 'warning', nunca erro")
		assert(string.find(diagnostic.Message, "ContentId", 1, true) ~= nil, `mensagem deveria citar o ValueType herdado 'ContentId', recebeu: {diagnostic.Message}`)
	end

	-- O Script continua materializando e sendo listado em Scripts -- só a propriedade herdada falha,
	-- nunca o nó inteiro (mesma disciplina de "nunca derrubar o resto por uma propriedade").
	assert(#tree.Scripts == 1, "o Script deveria continuar sendo materializado e listado em Scripts mesmo com LinkedSource não simulado")
end)

--------------------------------------------------------------------------------------------------
-- task-cli-028-fix (BUG REAL, testador + orquestrador confirmando por leitura de código):
-- `resolvePropertyValue` tratava QUALQUER `string` como primitivo sem checar `ValueCategory`,
-- pulando o decode de Enum inteiramente -- `StarterPlayer.CameraMode = "LockFirstPerson"` (forma
-- Rojo padrão pra Enum via `$properties`) virava uma STRING LUA CRUA na árvore materializada, não
-- `EnumItem`, sem erro/warning nenhum. Reproduzido ANTES desta correção (revertendo só
-- `TreeMaterializer.luau` e rodando este mesmo teste): `typeof(cameraMode) == "string"` e
-- `cameraMode == "LockFirstPerson"`, nunca um `EnumItem` -- confirmado no relatório da tarefa.
--
-- Reusa a fixture 'value-types' (mesma que já cobre DataType via MemberDescriptor) -- StarterPlayer
-- é uma classe REAL já coberta por `services` (task-services-015) com duas propriedades Enum reais:
-- "CameraMode" (caso feliz, item válido) e "DevCameraOcclusionMode" (caso de item inexistente).
--------------------------------------------------------------------------------------------------

test("Materialize: StarterPlayer.CameraMode = \"LockFirstPerson\" ($properties) vira Enum.CameraMode.LockFirstPerson REAL, não string crua (task-cli-028-fix, BUG REAL)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- "CameraMode" é um item válido -- NÃO deveria produzir 'materialize/undecodable-property'
	-- (só 'DevCameraOcclusionMode', item inexistente, e 'Position', array de tamanho errado --
	-- ver os outros dois testes desta fixture -- deveriam).
	assert(findByCodeAndField(bag, "materialize/undecodable-property", "CameraMode") == nil, "'CameraMode' com item VÁLIDO não deveria produzir 'materialize/undecodable-property'")

	local starterPlayer = game:FindService("StarterPlayer")
	assert(starterPlayer ~= nil, "game deveria ter um StarterPlayer depois de Materialize")
	if starterPlayer == nil then
		return
	end

	local starterPlayerDot = (starterPlayer :: unknown) :: { [string]: unknown }
	local cameraMode = starterPlayerDot["CameraMode"]

	-- O BUG: antes da correção, isto era `typeof(cameraMode) == "string"` e `cameraMode ==
	-- "LockFirstPerson"` -- corrupção silenciosa de tipo, sem NENHUM Diagnostic no bag.
	assert(typeof(cameraMode) ~= "string", `StarterPlayer.CameraMode NÃO deveria mais ser uma string Lua crua -- typeof devolveu "{typeof(cameraMode)}"`)
	assert(ValueTypes.TypeNameOf(cameraMode) == "EnumItem", `StarterPlayer.CameraMode deveria ter virado um EnumItem real, TypeNameOf devolveu {tostring(ValueTypes.TypeNameOf(cameraMode))}`)
	assert(tostring(cameraMode) == "Enum.CameraMode.LockFirstPerson", `esperava tostring "Enum.CameraMode.LockFirstPerson", recebeu "{tostring(cameraMode)}"`)

	-- `== Enum.CameraMode.LockFirstPerson` precisa BATER -- é exatamente o `==` que o bug relatado
	-- dizia "nunca bate" (comparando contra uma string crua nunca seria igual a um EnumItem).
	local enumRootDot = (ValueTypes.Enum :: unknown) :: { [string]: unknown }
	local cameraModeEnumDot = (enumRootDot["CameraMode"] :: unknown) :: { [string]: unknown }
	local lockFirstPerson = cameraModeEnumDot["LockFirstPerson"]
	assert(cameraMode == lockFirstPerson, "StarterPlayer.CameraMode deveria ser o MESMO EnumItem que Enum.CameraMode.LockFirstPerson (== precisa bater)")
end)

test("Materialize: string de Enum com item INEXISTENTE (StarterPlayer.DevCameraOcclusionMode = \"NotARealItem\") gera 'materialize/undecodable-property', nunca grava string crua (task-cli-028-fix)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- `findByCodeAndField` (não só `findByCode`) -- a fixture agora tem OUTRO
	-- 'materialize/undecodable-property' (Workspace.BadPosition.Position, teste dedicado acima).
	local diagnostic = findByCodeAndField(bag, "materialize/undecodable-property", "DevCameraOcclusionMode")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'materialize/undecodable-property' para o campo 'DevCameraOcclusionMode'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "item de Enum inexistente deveria ser Severity 'error'")
		assert(string.find(diagnostic.Message, "NotARealItem", 1, true) ~= nil, `mensagem deveria citar a entrada inválida 'NotARealItem', recebeu: {diagnostic.Message}`)
		assert(diagnostic.NodePath ~= nil and string.find(diagnostic.NodePath, "StarterPlayer", 1, true) ~= nil, "Diagnostic deveria citar o NodePath de StarterPlayer")
	end

	local starterPlayer = game:FindService("StarterPlayer")
	assert(starterPlayer ~= nil, "game deveria ter um StarterPlayer depois de Materialize")
	if starterPlayer == nil then
		return
	end

	-- NUNCA gravou a string crua "NotARealItem" -- a propriedade manteve o Default real do schema
	-- (`enumDefault("DevCameraOcclusionMode", "Zoom")`, ver generated/classes/StarterPlayer.luau).
	local starterPlayerDot = (starterPlayer :: unknown) :: { [string]: unknown }
	local occlusionMode = starterPlayerDot["DevCameraOcclusionMode"]
	assert(typeof(occlusionMode) ~= "string", `DevCameraOcclusionMode NUNCA deveria ter virado a string crua "NotARealItem" -- typeof devolveu "{typeof(occlusionMode)}"`)
	assert(ValueTypes.TypeNameOf(occlusionMode) == "EnumItem", "DevCameraOcclusionMode deveria continuar sendo o EnumItem Default (nunca a string inválida)")
	assert(tostring(occlusionMode) == "Enum.DevCameraOcclusionMode.Zoom", `esperava o Default "Enum.DevCameraOcclusionMode.Zoom" preservado, recebeu "{tostring(occlusionMode)}"`)
end)

test("Materialize: string primitiva normal SEM MemberDescriptor de Enum (Folder.Name via $properties) continua idêntica a antes -- regressão (task-cli-028-fix)", function()
	local plan, planBag = planFixture("value-types")
	assert(plan ~= nil, `fixture 'value-types' deveria produzir um InstancePlan válido (bag: {#planBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end

	local game = newGame()
	local bag = Diagnostics.newBag()
	TreeMaterializer.Materialize(plan, game, bag)

	-- NUNCA `not bag:HasErrors()` aqui -- esta MESMA fixture 'value-types' tem outros nós que
	-- deliberadamente produzem erro (BadPosition.Position, StarterPlayer.DevCameraOcclusionMode,
	-- ver os testes acima). O que importa pra ESTE teste é que 'RenameMe'/'Name' especificamente
	-- não produziu Diagnostic nenhum.
	assert(findByCodeAndField(bag, "materialize/invalid-property", "Name") == nil, "'Name' não deveria produzir Diagnostic 'materialize/invalid-property'")
	assert(findByCodeAndField(bag, "materialize/undecodable-property", "Name") == nil, "'Name' não deveria produzir Diagnostic 'materialize/undecodable-property'")
	assert(findByCodeAndField(bag, "materialize/property-shape-unknown", "Name") == nil, "'Name' não deveria produzir Diagnostic 'materialize/property-shape-unknown'")

	local workspaceInstance = game:FindFirstChildOfClass("Workspace")
	assert(workspaceInstance ~= nil, "game deveria ter Workspace")
	if workspaceInstance == nil then
		return
	end

	-- "RenameMe" (nome original do nó no .project.json) não deveria mais existir -- $properties.Name
	-- renomeou de verdade, via a via pública (__newindex real, ramo "Name" de Instance.luau).
	assert(workspaceInstance:FindFirstChild("RenameMe") == nil, "'RenameMe' não deveria mais existir depois do $properties.Name renomear a Instance")

	local renamed = workspaceInstance:FindFirstChild("RenamedViaProperties")
	assert(renamed ~= nil, "'RenamedViaProperties' deveria existir -- Name (string SEM MemberDescriptor, tratada pelo Instance base) continua indo pelo caminho primitivo direto")
	if renamed ~= nil then
		assert(renamed.ClassName == "Folder", "a Instance renomeada deveria continuar sendo o mesmo Folder")
		assert(renamed.Name == "RenamedViaProperties", "Instance.Name deveria refletir o valor aplicado via $properties")
	end
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
