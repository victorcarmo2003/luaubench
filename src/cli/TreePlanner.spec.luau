--!strict

--[[
	Teste da task-cli-003 (TreePlanner.luau). Cobre o acceptance do board: `InstancePlan` de um
	fixture com Service inferido sem `$className`, `Folder` por pasta, `ModuleScript` por
	arquivo, `init.luau` virando pasta-`ModuleScript`, projeto aninhado, `$path` opcional
	ausente; ciclo de projeto aninhado; `$path` obrigatório ausente; `$properties`
	primitivo/não-primitivo; arquivo não suportado; e confirma por leitura que este módulo nunca
	requer `runtime`/`services`.

	`options.IsServiceClass` é uma função FALSA, fixa neste spec (nunca `require("../services")`)
	-- é exatamente o que o desenho pede: `TreePlanner` testável sem `DataModel`/`Bootstrap`.

	Roda com `lune run src/cli/TreePlanner.spec.luau`.
]]

local process = require("@lune/process")
local Diagnostics = require("./Diagnostics")
local ProjectFile = require("./ProjectFile")
local TreePlanner = require("./TreePlanner")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local FIXTURES_ROOT = process.cwd .. "src/cli/fixtures/tree-planner"

local function fixturePath(name: string): string
	return `{FIXTURES_ROOT}/{name}`
end

-- As três classes "Service" fixas pra todo este spec -- nunca vem de `services` de verdade
-- (Decisão 3/4: `IsServiceClass` é sempre injetada).
local FAKE_SERVICE_CLASSES: { [string]: boolean } = {
	ReplicatedStorage = true,
	ServerScriptService = true,
	Workspace = true,
}

local FAKE_OPTIONS: TreePlanner.PlanOptions = {
	IsServiceClass = function(className: string): boolean
		return FAKE_SERVICE_CLASSES[className] == true
	end,
}

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

local function findChildByName(node: TreePlanner.PlanNode, name: string): TreePlanner.PlanNode?
	for _, child in node.Children do
		if child.Name == name then
			return child
		end
	end
	return nil
end

local function findRootByName(plan: TreePlanner.InstancePlan, name: string): TreePlanner.PlanNode?
	for _, root in plan.Roots do
		if root.Name == name then
			return root
		end
	end
	return nil
end

local function planFixture(name: string): (TreePlanner.InstancePlan?, Diagnostics.Bag)
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath(name) .. "/default.project.json", bag)
	assert(project ~= nil, `fixture '{name}': ProjectFile.Read deveria ter conseguido ler o projeto (bag: {#bag:All()} diagnostic(s))`)
	if project == nil then
		return nil, bag
	end
	local plan = TreePlanner.Plan(project, FAKE_OPTIONS, bag)
	return plan, bag
end

--------------------------------------------------------------------------------------------------
-- Não requer runtime/services (verificável por leitura/grep -- confirmado aqui também via teste,
-- não só no relatório)
--------------------------------------------------------------------------------------------------

test("TreePlanner.luau não contém nenhum require de '../runtime' ou '../services'", function()
	local source = require("@lune/fs").readFile("src/cli/TreePlanner.luau")
	assert(string.find(source, "require(\"../runtime\")", 1, true) == nil, "TreePlanner NUNCA deveria requerer runtime")
	assert(string.find(source, "require(\"../services\")", 1, true) == nil, "TreePlanner NUNCA deveria requerer services")
end)

--------------------------------------------------------------------------------------------------
-- Caso feliz: Service inferido sem $className, Folder por pasta, ModuleScript por arquivo,
-- init.luau virando pasta-ModuleScript, $path opcional ausente (omitido em silêncio + info)
--------------------------------------------------------------------------------------------------

test("Plan: Service inferido por nome, Folder por pasta, ModuleScript por arquivo e por init.luau, $path opcional ausente omite o nó", function()
	local plan, bag = planFixture("basic")
	assert(plan ~= nil, "fixture 'basic' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end

	assert(plan.RootClassName == "DataModel", `RootClassName deveria ser 'DataModel', recebeu '{plan.RootClassName}'`)
	assert(#plan.Roots == 1, `esperava exatamente 1 root (OptionalStuff deveria ser omitido) -- recebeu {#plan.Roots}`)

	local replicatedStorage = findRootByName(plan, "ReplicatedStorage")
	assert(replicatedStorage ~= nil, "deveria haver uma root chamada 'ReplicatedStorage'")
	if replicatedStorage == nil then
		return
	end
	assert(replicatedStorage.ClassName == "ReplicatedStorage", "ClassName deveria ser inferido como 'ReplicatedStorage' SEM $className explícito")
	assert(replicatedStorage.IsServiceRoot == true, "ReplicatedStorage sob a raiz deveria ter IsServiceRoot = true")
	assert(replicatedStorage.Source == nil, "ReplicatedStorage não tem Source (não é um arquivo de script)")

	local utils = findChildByName(replicatedStorage, "Utils")
	assert(utils ~= nil, "deveria haver um filho 'Utils' (ModuleScript por arquivo)")
	if utils ~= nil then
		assert(utils.ClassName == "ModuleScript", `Utils.lua deveria virar ModuleScript, recebeu {utils.ClassName}`)
		assert(utils.IsServiceRoot == false, "Utils não é um Service")
		assert(utils.Source ~= nil and string.find(utils.Source, "return {}", 1, true) ~= nil, "Utils.Source deveria conter o texto do arquivo")
		assert(#utils.Children == 0, "Utils (arquivo simples) não deveria ter filhos")
	end

	local data = findChildByName(replicatedStorage, "Data")
	assert(data ~= nil, "deveria haver um filho 'Data' (Folder por pasta)")
	if data ~= nil then
		assert(data.ClassName == "Folder", `Data/ deveria virar Folder, recebeu {data.ClassName}`)
		assert(data.Source == nil, "Folder não tem Source")
		assert(#data.Children == 0, "Data só tem um arquivo 'Ignored' (readme.md) dentro -- zero filhos no plano")
	end

	local modules = findChildByName(replicatedStorage, "Modules")
	assert(modules ~= nil, "deveria haver um filho 'Modules' (pasta com init.luau)")
	if modules ~= nil then
		assert(modules.ClassName == "ModuleScript", `Modules/ (init.luau) deveria virar ModuleScript, recebeu {modules.ClassName}`)
		assert(modules.Source ~= nil and string.find(modules.Source, "return {}", 1, true) ~= nil, "Modules.Source deveria vir do init.luau")
		local sub = findChildByName(modules, "Sub")
		assert(sub ~= nil, "Modules/ deveria ter um filho 'Sub' (Sub.lua, irmão do init.luau)")
		if sub ~= nil then
			assert(sub.ClassName == "ModuleScript", "Sub.lua deveria virar ModuleScript")
		end
	end

	local optionalStuff = findRootByName(plan, "OptionalStuff")
	assert(optionalStuff == nil, "'OptionalStuff' deveria ter sido OMITIDO ($path opcional ausente, sem outra fonte de classe)")

	local infoDiagnostic = findByCode(bag, "plan/optional-path-omitted")
	assert(infoDiagnostic ~= nil, "deveria haver um Diagnostic 'plan/optional-path-omitted'")
	if infoDiagnostic ~= nil then
		assert(infoDiagnostic.Severity == "info", "$path opcional ausente deveria ser Severity 'info', nunca erro")
		assert(infoDiagnostic.NodePath == "tree.OptionalStuff", "Diagnostic deveria apontar o NodePath certo")
	end
end)

--------------------------------------------------------------------------------------------------
-- $path obrigatório ausente -> erro nomeando nó/campo/caminho
--------------------------------------------------------------------------------------------------

test("Plan: $path obrigatório ausente em disco produz erro nomeando nó/campo/caminho, e Plan devolve nil", function()
	local plan, bag = planFixture("required-path-missing")
	assert(plan == nil, "$path obrigatório ausente deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/required-path-not-found")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/required-path-not-found'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "path obrigatório ausente deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.ReplicatedStorage", "Diagnostic deveria nomear o NÓ")
		assert(diagnostic.Field == "$path", "Diagnostic deveria nomear o CAMPO ($path)")
		assert(string.find(diagnostic.Message, "does-not-exist", 1, true) ~= nil, "Message deveria citar o CAMINHO absoluto tentado")
	end
end)

--------------------------------------------------------------------------------------------------
-- Conflito $className + $path (path não resolve pra Folder) -> erro
--------------------------------------------------------------------------------------------------

test("Plan: $className + $path que NÃO resolve pra Folder produz erro de conflito", function()
	local plan, bag = planFixture("class-name-conflict")
	assert(plan == nil, "conflito de $className/$path deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/class-name-conflict")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/class-name-conflict'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "conflito deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.Something", "Diagnostic deveria nomear o nó em conflito")
	end
end)

--------------------------------------------------------------------------------------------------
-- Service com Name != ClassName sob a raiz -> erro (Decisão 4: divergência declarada do Rojo)
--------------------------------------------------------------------------------------------------

test("Plan: Service sob a raiz com Name != ClassName produz erro dedicado", function()
	local plan, bag = planFixture("service-name-mismatch")
	assert(plan == nil, "service com nome divergente deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/service-name-mismatch")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/service-name-mismatch'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.NotWorkspace", "Diagnostic deveria nomear o nó")
	end
end)

--------------------------------------------------------------------------------------------------
-- $properties primitivo entra no plano; não-primitivo vira warning; $attributes sempre warning
--------------------------------------------------------------------------------------------------

test("Plan: $properties primitivo entra no plano, não-primitivo vira warning, $attributes sempre warning", function()
	local plan, bag = planFixture("properties-and-attributes")
	assert(plan ~= nil, "warnings não deveriam impedir Plan de devolver um InstancePlan válido")
	if plan == nil then
		return
	end

	local replicatedStorage = findRootByName(plan, "ReplicatedStorage")
	assert(replicatedStorage ~= nil, "deveria haver uma root 'ReplicatedStorage'")
	if replicatedStorage == nil then
		return
	end

	assert(replicatedStorage.Properties["Foo"] == true, "$properties.Foo (boolean) deveria entrar no plano")
	assert(replicatedStorage.Properties["Position"] == nil, "$properties.Position (array -- Vector3 ambíguo) NUNCA deveria entrar no plano")

	local nonPrimitiveDiagnostic = findByCode(bag, "plan/non-primitive-property")
	assert(nonPrimitiveDiagnostic ~= nil, "deveria haver um Diagnostic 'plan/non-primitive-property'")
	if nonPrimitiveDiagnostic ~= nil then
		assert(nonPrimitiveDiagnostic.Severity == "warning", "propriedade não-primitiva deveria ser Severity 'warning', nunca erro")
		assert(nonPrimitiveDiagnostic.Field == "Position", "Diagnostic deveria nomear a propriedade 'Position'")
	end

	local attributesDiagnostic = findByCode(bag, "plan/attributes-unsupported")
	assert(attributesDiagnostic ~= nil, "deveria haver um Diagnostic 'plan/attributes-unsupported'")
	if attributesDiagnostic ~= nil then
		assert(attributesDiagnostic.Severity == "warning", "$attributes deveria ser sempre Severity 'warning'")
		assert(string.find(attributesDiagnostic.Message, "Level", 1, true) ~= nil, "Message deveria listar o atributo 'Level'")
		assert(string.find(attributesDiagnostic.Message, "Tag", 1, true) ~= nil, "Message deveria listar o atributo 'Tag'")
	end
end)

--------------------------------------------------------------------------------------------------
-- Arquivo não suportado (reconhecido pela tabela do Rojo, fora da leva 1) -> warning com o
-- caminho real, nunca omissão silenciosa
--------------------------------------------------------------------------------------------------

test("Plan: arquivo Unsupported dentro de um $path de diretório vira warning com o caminho real, e é excluído do plano", function()
	local plan, bag = planFixture("unsupported-file")
	assert(plan ~= nil, "warning não deveria impedir Plan de devolver um InstancePlan válido")
	if plan == nil then
		return
	end

	local replicatedStorage = findRootByName(plan, "ReplicatedStorage")
	assert(replicatedStorage ~= nil, "deveria haver uma root 'ReplicatedStorage'")
	if replicatedStorage == nil then
		return
	end

	assert(findChildByName(replicatedStorage, "Foo") ~= nil, "'Foo' (ModuleScript válido) deveria continuar no plano")
	assert(findChildByName(replicatedStorage, "Data") == nil, "'Data.model.json' (Unsupported) NUNCA deveria virar um PlanNode")

	local diagnostic = findByCode(bag, "sync/unsupported-extension")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'sync/unsupported-extension'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "arquivo Unsupported deveria ser Severity 'warning', nunca omissão silenciosa")
		assert(string.find(diagnostic.Message, "Data.model.json", 1, true) ~= nil, "Message deveria citar o CAMINHO REAL do arquivo Unsupported")
	end
end)

--------------------------------------------------------------------------------------------------
-- Projeto aninhado (default.project.json alcançado via $path de diretório)
--------------------------------------------------------------------------------------------------

test("Plan: projeto aninhado materializa a árvore do PROJETO ANINHADO, não filhos nomeados do nó que apontou pra ele", function()
	local plan, bag = planFixture("nested-project")
	assert(plan ~= nil, "projeto aninhado válido deveria produzir um InstancePlan (bag: %s diagnostics)")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "projeto aninhado válido não deveria produzir nenhum erro")

	assert(findRootByName(plan, "ReplicatedStorage") ~= nil, "'ReplicatedStorage' (não aninhado) deveria continuar normal")

	local vendor = findRootByName(plan, "Vendor")
	assert(vendor ~= nil, "deveria haver uma root 'Vendor' (o nó cujo $path aponta pro projeto aninhado)")
	if vendor == nil then
		return
	end

	assert(vendor.ClassName == "Folder", `Vendor deveria assumir o ClassName da RAIZ do projeto aninhado ('Folder'), recebeu {vendor.ClassName}`)
	assert(vendor.IsServiceRoot == false, "um projeto aninhado nunca vira IsServiceRoot (limitação declarada)")

	local sub = findChildByName(vendor, "Sub")
	assert(sub ~= nil, "Vendor deveria ter um filho 'Sub', vindo da árvore do PRÓPRIO projeto aninhado")
	if sub ~= nil then
		assert(sub.ClassName == "Folder", "Sub (definido no projeto aninhado) deveria ser Folder")
	end
end)

--------------------------------------------------------------------------------------------------
-- Ciclo de projeto aninhado -> erro listando a cadeia completa
--
-- CORREÇÃO (revisor-cli-treeplanner-2026-09-05.md, achado GRAVE): a fixture antiga (`$path: ""`,
-- auto-referência degenerada) foi SUBSTITUÍDA por um ciclo REAL entre dois/três arquivos de
-- projeto distintos via "$path" relativo com ".." (o jeito normal de um pacote vendorizado/
-- monorepo se referenciar "pra cima") -- é o único cenário que de fato exercitava o bug (o path
-- crescendo sem limite porque o `cycleGuard` usava a string NÃO normalizada como chave).
--------------------------------------------------------------------------------------------------

-- Conta ocorrências NÃO sobrepostas de `needle` em `haystack` -- usado abaixo pra provar que a
-- cadeia do ciclo cita cada arquivo de projeto exatamente uma vez por visita (3 pro ciclo de 2
-- projetos: A, B, A -- não milhares), nunca um path gigante repetido.
local function countOccurrences(haystack: string, needle: string): number
	local count = 0
	local searchFrom = 1
	while true do
		local foundStart = string.find(haystack, needle, searchFrom, true)
		if foundStart == nil then
			break
		end
		count += 1
		searchFrom = foundStart + #needle
	end
	return count
end

test("Plan: ciclo REAL de dois projetos (A --$path:\"../b\"--> B --$path:\"../a\"--> A) dispara o diagnóstico IMEDIATAMENTE, sem o path crescer, listando a cadeia A -> B -> A", function()
	local plan, bag = planFixture("nested-project-cycle/a")
	assert(plan == nil, "ciclo de projeto aninhado deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/nested-project-cycle")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/nested-project-cycle'")
	if diagnostic == nil then
		return
	end

	assert(diagnostic.Severity == "error", "ciclo deveria ser Severity 'error'")
	assert(string.find(diagnostic.Message, "->", 1, true) ~= nil, "Message deveria listar a CADEIA (separador '->')")

	-- "sem o path crescer": a cadeia cita cada arquivo de projeto envolvido em CADA visita (3
	-- visitas: A, B, A -- nunca um caminho gigante "a/../b/../a/..." repetido ~5000 vezes), e a
	-- mensagem inteira fica curta -- prova direta de que a normalização entrou em vigor.
	local occurrences = countOccurrences(diagnostic.Message, "default.project.json")
	assert(occurrences == 3, `Message deveria citar exatamente 3 arquivos de projeto na cadeia (A, B, A) -- recebeu {occurrences}. Message: {diagnostic.Message}`)
	assert(string.find(diagnostic.Message, "..", 1, true) == nil, "Message NUNCA deveria conter '..' -- prova que os caminhos foram normalizados antes de virar a cadeia")
	assert(#diagnostic.Message < 500, `Message deveria ser curta (path normalizado, não crescido) -- recebeu {#diagnostic.Message} caracteres`)

	-- Sufixo RELATIVO (não o caminho absoluto inteiro construído por `fixturePath`) -- `process.cwd`
	-- do Lune 0.10.5 devolve barra invertida (Windows) enquanto `normalizePath`/`joinPath` sempre
	-- produzem barra normal; comparar só o sufixo evita depender do separador que `process.cwd`
	-- calha de usar nesta plataforma e ainda assim confirma a forma CANÔNICA (sem "..").
	local expectedA = "nested-project-cycle/a/default.project.json"
	local expectedB = "nested-project-cycle/b/default.project.json"
	assert(string.find(diagnostic.Message, expectedA, 1, true) ~= nil, "Message deveria citar o arquivo de projeto 'a' pelo caminho CANÔNICO (sem '..')")
	assert(string.find(diagnostic.Message, expectedB, 1, true) ~= nil, "Message deveria citar o arquivo de projeto 'b' pelo caminho CANÔNICO (sem '..')")

	-- Cadeia real A -> B -> A: 'a' aparece nas duas pontas, 'b' no meio -- confirma a ORDEM da
	-- recursão, não só que os dois arquivos aparecem em algum lugar da mensagem.
	local aFirstIndex = string.find(diagnostic.Message, expectedA, 1, true)
	local bIndex = string.find(diagnostic.Message, expectedB, 1, true)
	local aSecondIndex = nil
	if aFirstIndex ~= nil then
		aSecondIndex = string.find(diagnostic.Message, expectedA, aFirstIndex + #expectedA, true)
	end
	assert(aFirstIndex ~= nil and bIndex ~= nil and aSecondIndex ~= nil, "Message deveria citar 'a' duas vezes (início e fim da cadeia) e 'b' uma vez (meio)")
	if aFirstIndex ~= nil and bIndex ~= nil and aSecondIndex ~= nil then
		assert(aFirstIndex < bIndex and bIndex < aSecondIndex, "Cadeia deveria estar na ordem A -> B -> A, não em outra ordem")
	end
end)

test("Plan: ciclo REAL de TRÊS projetos (A -> B -> C -> A) também dispara o diagnóstico -- não é só o caso de 2", function()
	local plan, bag = planFixture("nested-project-cycle-triple/a")
	assert(plan == nil, "ciclo de 3 projetos aninhados deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/nested-project-cycle")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/nested-project-cycle'")
	if diagnostic == nil then
		return
	end

	assert(diagnostic.Severity == "error", "ciclo deveria ser Severity 'error'")
	local occurrences = countOccurrences(diagnostic.Message, "default.project.json")
	assert(occurrences == 4, `Message deveria citar exatamente 4 arquivos de projeto na cadeia (A, B, C, A) -- recebeu {occurrences}. Message: {diagnostic.Message}`)
	assert(string.find(diagnostic.Message, "..", 1, true) == nil, "Message NUNCA deveria conter '..' -- prova que os caminhos foram normalizados mesmo com 3 projetos na cadeia")
end)

--------------------------------------------------------------------------------------------------
-- $className explícito + $path que resolve pra projeto aninhado -> $className NUNCA pode ser
-- descartado em SILÊNCIO (achado MÉDIO, revisor-cli-treeplanner-2026-09-05.md)
--------------------------------------------------------------------------------------------------

test("Plan: $className explícito + $path de projeto aninhado usa a classe do projeto aninhado, mas AVISA (não descarta em silêncio)", function()
	local plan, bag = planFixture("nested-project-class-name-ignored")
	assert(plan ~= nil, "fixture 'nested-project-class-name-ignored' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "className ignorado é warning, nunca erro")

	local something = findRootByName(plan, "Something")
	assert(something ~= nil, "deveria haver uma root 'Something'")
	if something ~= nil then
		assert(something.ClassName == "Folder", `'Something' deveria assumir o ClassName da RAIZ do projeto aninhado ('Folder'), recebeu {something.ClassName}`)
	end

	local diagnostic = findByCode(bag, "plan/nested-project-class-name-ignored")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/nested-project-class-name-ignored' -- '$className' NUNCA pode ser descartado em silêncio")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "className ignorado deveria ser Severity 'warning', nunca erro nem silêncio")
		assert(diagnostic.NodePath == "tree.Something", "Diagnostic deveria nomear o nó certo")
		assert(diagnostic.Field == "$className", "Diagnostic deveria nomear o campo '$className'")
		assert(string.find(diagnostic.Message, "Model", 1, true) ~= nil, "Message deveria citar o '$className' descartado ('Model')")
	end
end)

--------------------------------------------------------------------------------------------------
-- Meta files: <nome>.meta.json adjacente aplica properties; init.meta.json aplica properties E
-- className (só quando a pasta é Folder puro)
--------------------------------------------------------------------------------------------------

test("Plan: <nome>.meta.json adjacente aplica $properties ao arquivo irmão", function()
	local plan, bag = planFixture("meta-files")
	assert(plan ~= nil, "fixture 'meta-files' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "meta files válidos não deveriam produzir nenhum erro")

	local replicatedStorage = findRootByName(plan, "ReplicatedStorage")
	assert(replicatedStorage ~= nil, "deveria haver uma root 'ReplicatedStorage'")
	if replicatedStorage == nil then
		return
	end

	local foo = findChildByName(replicatedStorage, "Foo")
	assert(foo ~= nil, "deveria haver um filho 'Foo'")
	if foo ~= nil then
		assert(foo.Properties["Disabled"] == true, "'Foo.meta.json' adjacente deveria ter aplicado $properties.Disabled")
	end
end)

test("Plan: init.meta.json aplica $properties E className quando a pasta resolveu pra Folder puro", function()
	local plan = planFixture("meta-files")
	assert(plan ~= nil, "fixture 'meta-files' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end

	local replicatedStorage = findRootByName(plan, "ReplicatedStorage")
	assert(replicatedStorage ~= nil, "deveria haver uma root 'ReplicatedStorage'")
	if replicatedStorage == nil then
		return
	end

	local sub = findChildByName(replicatedStorage, "Sub")
	assert(sub ~= nil, "deveria haver um filho 'Sub'")
	if sub ~= nil then
		assert(sub.ClassName == "Configuration", `'init.meta.json' deveria ter sobrescrito o ClassName pra 'Configuration', recebeu {sub.ClassName}`)
		assert(sub.Properties["Flag"] == true, "'init.meta.json' deveria ter aplicado $properties.Flag")
	end
end)

--------------------------------------------------------------------------------------------------
-- init.meta.json tentando sobrescrever className quando a pasta NÃO é Folder puro -> erro
--------------------------------------------------------------------------------------------------

test("Plan: init.meta.json com className numa pasta que já resolveu via init.luau (não é Folder puro) produz erro", function()
	local plan, bag = planFixture("meta-class-conflict")
	assert(plan == nil, "conflito de className via init.meta.json deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/meta-class-name-conflict")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/meta-class-name-conflict'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.ReplicatedStorage.Sub", "Diagnostic deveria nomear o nó certo")
	end
end)

--------------------------------------------------------------------------------------------------
-- Tier 4 (Decisão 4): nada resolve a classe -> erro nomeando o nó (filho e raiz)
--------------------------------------------------------------------------------------------------

test("Plan: nó sem $className, $path ou nome de Service produz erro 'faltou informação'", function()
	local plan, bag = planFixture("missing-class-name")
	assert(plan == nil, "nó sem nenhuma fonte de ClassName deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/missing-class-name")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/missing-class-name'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.Mystery", "Diagnostic deveria nomear o nó 'tree.Mystery'")
	end
end)

test("Plan: raiz sem $className e sem $path também produz erro 'faltou informação' (não é omitida)", function()
	local plan, bag = planFixture("root-missing-class-name")
	assert(plan == nil, "raiz sem nenhuma fonte de ClassName deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/missing-class-name")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/missing-class-name' pra raiz")
	if diagnostic ~= nil then
		assert(diagnostic.NodePath == "tree", "Diagnostic deveria nomear a raiz ('tree')")
	end
end)

--------------------------------------------------------------------------------------------------
-- InstancePlan.Diagnostics espelha o bag (conveniência pro consumidor não precisar do Bag)
--------------------------------------------------------------------------------------------------

test("InstancePlan.Diagnostics contém os mesmos diagnostics acumulados no Bag", function()
	local plan, bag = planFixture("basic")
	assert(plan ~= nil, "fixture 'basic' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(#plan.Diagnostics == #bag:All(), "InstancePlan.Diagnostics deveria ter o mesmo tamanho que bag:All()")
	assert(countByCode(bag, "plan/optional-path-omitted") == 1, "sanity check: exatamente 1 diagnostic de path opcional omitido")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
