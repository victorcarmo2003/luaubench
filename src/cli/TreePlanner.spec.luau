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

local fs = require("@lune/fs")
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

-- As classes "Service" fixas pra todo este spec -- nunca vem de `services` de verdade
-- (Decisão 3/4: `IsServiceClass` é sempre injetada). `StarterPlayer` adicionada pra task-cli-014
-- (é Service real no dump -- `Manifest.luau` confirma `IsService = true` -- precisa resolver como
-- filho direto do DataModel pra que os testes de StarterPlayerScripts/StarterCharacterScripts,
-- que são filhos DELA, façam sentido).
local FAKE_SERVICE_CLASSES: { [string]: boolean } = {
	ReplicatedStorage = true,
	ServerScriptService = true,
	Workspace = true,
	StarterPlayer = true,
}

-- task-cli-024 (Decisão 17): filhos fixos do motor fingidos pra este spec -- espelha o par
-- (pai, nome, classe) que `services/EngineFixedChildren.luau` de verdade declara, exigindo os TRÊS
-- baterem (não só a classe) pela mesma razão do real: `"MyScripts": {"$className":
-- "StarterPlayerScripts"}` (nome errado) precisa DEVOLVER `false` aqui, pra cair no caminho normal
-- e a guarda `plan/engine-only-class` disparar -- exatamente o bug que esta task fecha.
local function fakeIsEngineFixedChild(parentClassName: string, name: string, className: string): boolean
	if parentClassName == "StarterPlayer" then
		return name == className and (className == "StarterPlayerScripts" or className == "StarterCharacterScripts")
	elseif parentClassName == "Workspace" then
		return name == className and className == "Terrain"
	end
	return false
end

-- task-cli-024 (Decisão 17): classes "só o motor cria, e este build sabe simular" fingidas pra
-- este spec -- os quatro Services fake acima (excluídos pela guarda via `isServiceRoot`),
-- StarterPlayerScripts/StarterCharacterScripts (excluídos via `isEngineFixedChild`) e
-- "Instance"/"DataModel" (nunca legítimos num nó de projeto). "Terrain" fica DE FORA de propósito,
-- espelhando o recorte real de `Services.IsEngineOnlyClass` (`Covered == false` pra "Terrain" no
-- manifesto real -- Decisão 17, "A armadilha nº 2") -- é o que garante, em qualquer parentesco
-- errado que uma fixture futura venha a testar, que "Terrain" continue caindo na mensagem "not
-- simulated yet" do `Materialize`, nunca em `plan/engine-only-class`.
local FAKE_ENGINE_ONLY_CLASSES: { [string]: boolean } = {
	ReplicatedStorage = true,
	ServerScriptService = true,
	Workspace = true,
	StarterPlayer = true,
	StarterPlayerScripts = true,
	StarterCharacterScripts = true,
	Instance = true,
	DataModel = true,
}

local FAKE_OPTIONS: TreePlanner.PlanOptions = {
	IsServiceClass = function(className: string): boolean
		return FAKE_SERVICE_CLASSES[className] == true
	end,
	IsEngineFixedChild = fakeIsEngineFixedChild,
	IsEngineOnlyClass = function(className: string): boolean
		return FAKE_ENGINE_ONLY_CLASSES[className] == true
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
-- $path ABSOLUTO (task-cli-021) -> Diagnostic dedicado, detectado ANTES de tocar o filesystem
-- (nunca um erro cru do SO -- "os error 123"/ERROR_INVALID_NAME no Windows é a manifestação
-- prática original; sem a correção, este teste sequer chegaria a `assert`, ele quebraria com um
-- erro nativo do Lune vazando pro terminal).
--------------------------------------------------------------------------------------------------

test("Plan: $path absoluto estilo Windows (barra e contrabarra) produz Diagnostic dedicado, nunca erro cru do SO", function()
	local plan, bag = planFixture("absolute-path-windows")
	assert(plan == nil, "$path absoluto deveria impedir Plan de devolver um InstancePlan")

	local diagnostics: { Diagnostics.Diagnostic } = {}
	for _, diagnostic in bag:All() do
		if diagnostic.Code == "plan/absolute-path-not-allowed" then
			table.insert(diagnostics, diagnostic)
		end
	end
	assert(#diagnostics == 2, `esperava 2 Diagnostic(s) 'plan/absolute-path-not-allowed' (barra e contrabarra), recebeu {#diagnostics}`)

	local sawForwardSlash = false
	local sawBackslash = false
	for _, diagnostic in diagnostics do
		assert(diagnostic.Severity == "error", "$path absoluto deveria ser Severity 'error'")
		assert(diagnostic.Field == "$path", "Diagnostic deveria nomear o CAMPO ($path)")
		if diagnostic.NodePath == "tree.ReplicatedStorage" then
			assert(string.find(diagnostic.Message, "C:/outra/pasta", 1, true) ~= nil, "Message deveria citar o $path literal (barra)")
			sawForwardSlash = true
		elseif diagnostic.NodePath == "tree.ServerScriptService" then
			assert(string.find(diagnostic.Message, "C:\\outra\\pasta", 1, true) ~= nil, "Message deveria citar o $path literal (contrabarra)")
			sawBackslash = true
		end
	end
	assert(sawForwardSlash, "deveria haver um Diagnostic para o nó com $path 'C:/outra/pasta'")
	assert(sawBackslash, "deveria haver um Diagnostic para o nó com $path 'C:\\outra\\pasta'")
end)

test("Plan: $path absoluto estilo Unix (barra inicial) produz Diagnostic dedicado, nunca erro cru do SO", function()
	local plan, bag = planFixture("absolute-path-unix")
	assert(plan == nil, "$path absoluto deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/absolute-path-not-allowed")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/absolute-path-not-allowed'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "$path absoluto deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.ReplicatedStorage", "Diagnostic deveria nomear o NÓ")
		assert(diagnostic.Field == "$path", "Diagnostic deveria nomear o CAMPO ($path)")
		assert(string.find(diagnostic.Message, "/etc/algo", 1, true) ~= nil, "Message deveria citar o $path literal")
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
-- $properties primitivo E não-primitivo entram no plano intactos (task-cli-025 -- decodificar um
-- array/objeto deixou de ser decisão de TreePlanner, ver TreePlanner.PlanPropertyValue);
-- $attributes sempre warning
--------------------------------------------------------------------------------------------------

test("Plan: $properties primitivo e não-primitivo entram no plano intactos (task-cli-025); $attributes sempre warning", function()
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

	-- task-cli-025: o array bruto do JSON ATRAVESSA o plano intacto agora -- só TreeMaterializer
	-- (que conhece o MemberDescriptor da classe REAL) decide se "Position" é um Vector3/Color3/
	-- outra coisa, ou se não é decodificável. TreePlanner nunca mais filtra isto.
	local positionRaw = replicatedStorage.Properties["Position"]
	assert(typeof(positionRaw) == "table", "$properties.Position (array) deveria atravessar o plano como tabela bruta, nunca mais ser filtrado")
	if typeof(positionRaw) == "table" then
		local asArray = (positionRaw :: unknown) :: { unknown }
		assert(asArray[1] == 1 and asArray[2] == 2 and asArray[3] == 3, "o array bruto deveria manter os valores originais do JSON, sem reinterpretação")
	end

	local nonPrimitiveDiagnostic = findByCode(bag, "plan/non-primitive-property")
	assert(nonPrimitiveDiagnostic == nil, "TreePlanner NUNCA MAIS deveria emitir 'plan/non-primitive-property' -- a decisão migrou para TreeMaterializer (task-cli-025)")

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
-- task-cli-018 (Decisão 15, Parte 1 -- BUG ALTO): a raiz de TODO projeto aninhado (todo pacote
-- Wally com default.project.json próprio -- ProfileStore, Jecs, Promise, Sera, Fusion) perdia o
-- próprio Source/SourcePath/Properties em silêncio (`planProjectTree` só devolvia `ClassName`).
-- Cobre as TRÊS formas reais de raiz de projeto aninhado encontradas nos pacotes do usuário
-- (arquiteto-cli-2026-09-05.md, Decisão 15, tabela de $path real por pacote).
--------------------------------------------------------------------------------------------------

test("Plan: raiz de projeto aninhado -- forma 1/3, raiz É O PRÓPRIO ARQUIVO ($path: 'Mod.luau') -> ModuleScript COM Source (task-cli-018)", function()
	local plan, bag = planFixture("nested-project-root-is-file")
	assert(plan ~= nil, "fixture 'nested-project-root-is-file' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "fixture válida não deveria produzir nenhum erro")

	local pkg = findRootByName(plan, "Pkg")
	assert(pkg ~= nil, "deveria haver uma root 'Pkg' (o nó cujo $path aponta pro projeto aninhado)")
	if pkg == nil then
		return
	end

	assert(pkg.ClassName == "ModuleScript", `Pkg (raiz É o arquivo) deveria ser ModuleScript, recebeu {pkg.ClassName}`)
	local expectedSource = require("@lune/fs").readFile(fixturePath("nested-project-root-is-file") .. "/pkg/Mod.luau")
	assert(pkg.Source == expectedSource, "Pkg.Source deveria ser o CONTEÚDO REAL de Mod.luau -- ANTES desta correção era nil (bug ALTO: pacote Wally materializava vazio)")
	assert(pkg.SourcePath ~= nil and string.find(pkg.SourcePath, "Mod.luau", 1, true) ~= nil, "Pkg.SourcePath deveria citar 'Mod.luau'")
	assert(#pkg.Children == 0, "raiz-arquivo não tem filhos (não é diretório)")
end)

test("Plan: raiz de projeto aninhado -- forma 2/3, raiz é DIRETÓRIO COM init.* ($path: 'src', src/init.luau) -> ModuleScript COM Source e com os irmãos como filhos (task-cli-018)", function()
	local plan, bag = planFixture("nested-project-root-is-init-dir")
	assert(plan ~= nil, "fixture 'nested-project-root-is-init-dir' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "fixture válida não deveria produzir nenhum erro")

	local pkg = findRootByName(plan, "Pkg")
	assert(pkg ~= nil, "deveria haver uma root 'Pkg'")
	if pkg == nil then
		return
	end

	assert(pkg.ClassName == "ModuleScript", `Pkg (pasta com init.luau) deveria ser ModuleScript, recebeu {pkg.ClassName}`)
	local expectedSource = require("@lune/fs").readFile(fixturePath("nested-project-root-is-init-dir") .. "/pkg/src/init.luau")
	assert(pkg.Source == expectedSource, "Pkg.Source deveria ser o CONTEÚDO REAL de src/init.luau")
	assert(pkg.SourcePath ~= nil and string.find(pkg.SourcePath, "init.luau", 1, true) ~= nil, "Pkg.SourcePath deveria citar 'init.luau'")

	local sibling = findChildByName(pkg, "Sibling")
	assert(sibling ~= nil, "Pkg deveria ter um filho 'Sibling' (irmão de init.luau, descoberto no filesystem da PRÓPRIA raiz do projeto aninhado)")
	if sibling ~= nil then
		assert(sibling.ClassName == "ModuleScript", "'Sibling.luau' deveria materializar como ModuleScript")
	end
end)

test("Plan: raiz de projeto aninhado -- forma 3/3, raiz é diretório SEM init.* ($path: 'src') -> Folder, Source continua nil (task-cli-018)", function()
	local plan, bag = planFixture("nested-project-root-is-plain-folder")
	assert(plan ~= nil, "fixture 'nested-project-root-is-plain-folder' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "fixture válida não deveria produzir nenhum erro")

	local pkg = findRootByName(plan, "Pkg")
	assert(pkg ~= nil, "deveria haver uma root 'Pkg'")
	if pkg == nil then
		return
	end

	assert(pkg.ClassName == "Folder", `Pkg (pasta SEM init.*) deveria ser Folder, recebeu {pkg.ClassName}`)
	assert(pkg.Source == nil, "Pkg.Source deveria continuar nil -- uma pasta sem init.* nunca tem Source, com ou sem a correção")
	assert(pkg.SourcePath == nil, "Pkg.SourcePath deveria continuar nil pelo mesmo motivo")

	local sibling = findChildByName(pkg, "Sibling")
	assert(sibling ~= nil, "Pkg (Folder) deveria ter um filho 'Sibling'")
	if sibling ~= nil then
		assert(sibling.ClassName == "ModuleScript", "'Sibling.luau' deveria materializar como ModuleScript")
	end
end)

test("Plan: $properties da raiz do projeto aninhado é aplicado, e o $properties do nó EXTERNO vence em chave repetida (task-cli-018)", function()
	local plan, bag = planFixture("nested-project-root-properties-merge")
	assert(plan ~= nil, "fixture 'nested-project-root-properties-merge' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "fixture válida não deveria produzir nenhum erro")

	local pkg = findRootByName(plan, "Pkg")
	assert(pkg ~= nil, "deveria haver uma root 'Pkg'")
	if pkg == nil then
		return
	end

	assert(pkg.Properties["FromPackage"] == true, "'FromPackage' (só declarado na raiz do projeto aninhado) deveria sobreviver -- ANTES desta correção a tabela começava vazia e isto se perdia")
	assert(pkg.Properties["FromOuter"] == true, "'FromOuter' (só declarado no nó externo) deveria continuar aplicado, como já era antes")
	assert(pkg.Properties["Shared"] == "fromOuter", "'Shared' está nos dois lados -- o nó EXTERNO deveria vencer (comportamento já shipado, preservado por esta correção)")
end)

--------------------------------------------------------------------------------------------------
-- task-cli-018 (Decisão 15, Parte 2): $properties da raiz de TOPO é aplicado (InstancePlan.
-- RootProperties, testado do lado de TreeMaterializer.spec.luau -- aqui só confirma que
-- TreePlanner.Plan preenche o campo); Source de uma raiz DataModel explícita não tem onde ser
-- aplicado -> warning plan/root-source-ignored em vez de silêncio.
--------------------------------------------------------------------------------------------------

test("Plan: InstancePlan.RootProperties é preenchido com o $properties da raiz de TOPO (task-cli-018)", function()
	local plan, bag = planFixture("properties-and-attributes")
	assert(plan ~= nil, "fixture 'properties-and-attributes' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "fixture já coberta por outro teste -- não deveria produzir erro")
	-- Esta fixture não declara $properties NA RAIZ (só em 'ReplicatedStorage') -- confirma que o
	-- campo novo existe e fica vazio quando não há nada pra preencher, sem quebrar nada existente.
	assert(next(plan.RootProperties) == nil, "RootProperties deveria ficar vazio quando a raiz de topo não declara $properties")
end)

test("Plan: raiz explícita \"DataModel\" cujo \"$path\" também produz Source -- Source fica sem destino, warning 'plan/root-source-ignored' (task-cli-018, Decisão 15)", function()
	local plan, bag = planFixture("root-source-ignored")
	assert(plan ~= nil, `fixture 'root-source-ignored' deveria produzir um InstancePlan válido (bag: {#bag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end
	assert(not bag:HasErrors(), "Source perdido na raiz é warning, nunca erro")
	assert(plan.RootClassName == "DataModel", `RootClassName deveria continuar 'DataModel' (a classe explícita vence), recebeu '{plan.RootClassName}'`)

	-- ACHADO (task-cli-018): sem uma exceção estreita (isRoot + $className "DataModel" explícito)
	-- na checagem PRÉ-EXISTENTE "$className + $path só é legal se $path resolver pra Folder"
	-- (`plan/class-name-conflict`), este warning seria CÓDIGO MORTO -- nenhum "$path" que produz
	-- Source (Script/LocalScript/ModuleScript) jamais resolve pra "Folder". Ver comentário em
	-- `resolveCore`, TreePlanner.luau, e o relatório desta task para o arquiteto revisar a
	-- exceção (é uma leitura de comportamento sobre uma guarda já testada, fora do "sem mudança de
	-- contrato" literal da Parte 1).
	assert(findByCode(bag, "plan/class-name-conflict") == nil, "NÃO deveria haver 'plan/class-name-conflict' aqui -- a exceção da raiz deveria ter evitado esse erro")

	local diagnostic = findByCode(bag, "plan/root-source-ignored")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/root-source-ignored'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "warning", "Source perdido na raiz deveria ser Severity 'warning', nunca erro nem silêncio")
		assert(diagnostic.Field == "$path", "Diagnostic deveria nomear o campo '$path'")
		assert(string.find(diagnostic.Message, "DataModel", 1, true) ~= nil, "Message deveria citar 'DataModel' (a classe que não tem onde aplicar Source)")
		assert(string.find(diagnostic.Message, "algo.lua", 1, true) ~= nil, "Message deveria citar o arquivo cujo conteúdo foi ignorado ('algo.lua')")
	end
end)

--------------------------------------------------------------------------------------------------
-- task-cli-020 (Decisão 16, achado MÉDIO de revisor-cli-rootsource-2026-09-05.md, seção 7.2): a
-- exceção "plan/root-source-ignored" (task-cli-018) estava condicionada só a `isRoot`, que TAMBÉM
-- vale pra raiz de QUALQUER projeto aninhado -- não só pra raiz do PLANO INTEIRO, o único caso que
-- a Decisão 15 (Parte 2) desenhou. Um "$className": "DataModel" só é uma classe legal na raiz do
-- projeto MAIS EXTERNO; na raiz de um projeto aninhado continua sendo "plan/class-name-conflict",
-- como era antes da task-cli-018 abrir a exceção larga demais.
--------------------------------------------------------------------------------------------------

test("Plan: raiz explícita \"DataModel\" + \"$path\" com Source NA RAIZ DE UM PROJETO ANINHADO continua 'plan/class-name-conflict' (task-cli-020, Decisão 16)", function()
	local plan, bag = planFixture("nested-project-root-datamodel-conflict")
	assert(plan == nil, "raiz de projeto aninhado com DataModel + $path de Source deveria impedir Plan de devolver um InstancePlan -- a exceção da task-cli-018 NÃO se aplica aqui")

	local diagnostic = findByCode(bag, "plan/class-name-conflict")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/class-name-conflict' na raiz do projeto ANINHADO -- a exceção de 'root-source-ignored' é exclusiva da raiz do plano inteiro (Decisão 16)")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "conflito na raiz do projeto aninhado deveria continuar Severity 'error'")
		assert(diagnostic.NodePath == "tree", "Diagnostic deveria nomear a raiz DO PROJETO ANINHADO ('tree' -- NodePath da raiz de qualquer arquivo de projeto lido isoladamente, ver teste 'root-missing-class-name')")
	end

	assert(findByCode(bag, "plan/root-source-ignored") == nil, "NÃO deveria haver 'plan/root-source-ignored' aqui -- essa exceção é exclusiva da raiz do plano INTEIRO, nunca de uma raiz de projeto aninhado qualquer")
end)

test("Plan: raiz de TOPO ainda é reconhecida como 'outermost' mesmo com project.FilePath não-canônico (\"./\"/\"\\\") (task-cli-020, Decisão 16)", function()
	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(fixturePath("root-source-ignored") .. "/default.project.json", bag)
	assert(project ~= nil, "fixture 'root-source-ignored' deveria ler normalmente")
	if project == nil then
		return
	end

	-- Constrói a MESMA `Project` só com um `FilePath` "sujo" -- separador "\" e um segmento "."
	-- redundante injetado antes do nome do arquivo -- pra provar que `resolveCore` RE-normaliza
	-- `currentProjectFilePath` antes de comparar contra `ctx.OutermostProjectFilePath` (que já
	-- chega pré-normalizado). Comparar a string CRUA contra a já normalizada quebraria exatamente
	-- neste caso -- é a regressão que este teste impede.
	local dirtyFilePath = (string.gsub(project.FilePath, "/", "\\"))
	dirtyFilePath = (string.gsub(dirtyFilePath, "\\([^\\]+)$", "\\.\\%1"))
	assert(string.find(dirtyFilePath, "\\.\\", 1, true) ~= nil, "sanity: o FilePath sujo construído pelo teste deveria conter um segmento './' (aqui como '\\.\\')")

	local dirtyProject: ProjectFile.Project = {
		Name = project.Name,
		Tree = project.Tree,
		FilePath = dirtyFilePath,
		FolderPath = project.FolderPath,
		EmitLegacyScripts = project.EmitLegacyScripts,
		GlobIgnorePaths = project.GlobIgnorePaths,
		HasSyncRules = project.HasSyncRules,
	}

	local dirtyBag = Diagnostics.newBag()
	local plan = TreePlanner.Plan(dirtyProject, FAKE_OPTIONS, dirtyBag)
	assert(plan ~= nil, `Plan deveria continuar funcionando com um FilePath não-canônico (bag: {#dirtyBag:All()} diagnostic(s))`)
	if plan == nil then
		return
	end
	assert(not dirtyBag:HasErrors(), "Source perdido na raiz é warning, nunca erro -- mesmo com FilePath sujo")
	assert(findByCode(dirtyBag, "plan/class-name-conflict") == nil, "raiz de topo com FilePath sujo AINDA deveria ser reconhecida como 'outermost' -- não deveria cair em class-name-conflict")
	assert(findByCode(dirtyBag, "plan/root-source-ignored") ~= nil, "deveria continuar emitindo 'plan/root-source-ignored' -- prova de que a exceção da raiz de topo funcionou mesmo com FilePath sujo")
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

--------------------------------------------------------------------------------------------------
-- CORREÇÃO task-cli-014 (pesquisa-formato-projeto-rojo-2026-09-05.md, seção "Correção
-- 2026-09-05"): inferência de ClassName pra filhos fixos conhecidos --
-- StarterPlayer->{StarterPlayerScripts, StarterCharacterScripts} e Workspace->Terrain -- os dois
-- ramos que faltavam de `infer_class_name`, além do já existente DataModel->Service. Bug real
-- bloqueava 17/17 dos .project.json reais do usuário (todo projeto Rojo com StarterPlayerScripts
-- populado, o padrão universal de `rojo init`).
--------------------------------------------------------------------------------------------------

test("Plan: StarterPlayer->StarterPlayerScripts/StarterCharacterScripts e Workspace->Terrain são inferidos SEM $className -- repro exato do bug real (17/17 projetos do usuário)", function()
	local plan, bag = planFixture("fixed-children")
	assert(not bag:HasErrors(), `fixture 'fixed-children' NÃO deveria produzir nenhum erro -- bag: {#bag:All()} diagnostic(s)`)
	assert(plan ~= nil, "fixture 'fixed-children' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end

	local starterPlayer = findRootByName(plan, "StarterPlayer")
	assert(starterPlayer ~= nil, "deveria haver uma root 'StarterPlayer' (Service inferido -- ramo já existente, não é o novo)")
	if starterPlayer == nil then
		return
	end
	assert(starterPlayer.ClassName == "StarterPlayer", "StarterPlayer deveria manter seu próprio ClassName (Service)")
	assert(starterPlayer.IsServiceRoot == true, "StarterPlayer sob a raiz É um Service de verdade -- IsServiceRoot deveria ser true")

	local starterPlayerScripts = findChildByName(starterPlayer, "StarterPlayerScripts")
	assert(starterPlayerScripts ~= nil, "StarterPlayer deveria ter um filho 'StarterPlayerScripts' SEM $className explícito (bug real)")
	if starterPlayerScripts ~= nil then
		assert(starterPlayerScripts.ClassName == "StarterPlayerScripts", `ClassName deveria ser inferido como 'StarterPlayerScripts', recebeu '{starterPlayerScripts.ClassName}'`)
		assert(starterPlayerScripts.IsServiceRoot == false, "StarterPlayerScripts NÃO é um Service real (IsService=false no dump) -- IsServiceRoot deveria ficar false")
	end

	local starterCharacterScripts = findChildByName(starterPlayer, "StarterCharacterScripts")
	assert(starterCharacterScripts ~= nil, "StarterPlayer deveria ter um filho 'StarterCharacterScripts' SEM $className explícito")
	if starterCharacterScripts ~= nil then
		assert(starterCharacterScripts.ClassName == "StarterCharacterScripts", `ClassName deveria ser inferido como 'StarterCharacterScripts', recebeu '{starterCharacterScripts.ClassName}'`)
		assert(starterCharacterScripts.IsServiceRoot == false, "StarterCharacterScripts também não é Service")
	end

	local workspaceNode = findRootByName(plan, "Workspace")
	assert(workspaceNode ~= nil, "deveria haver uma root 'Workspace'")
	if workspaceNode == nil then
		return
	end

	local terrain = findChildByName(workspaceNode, "Terrain")
	assert(terrain ~= nil, "Workspace deveria ter um filho 'Terrain' SEM $className explícito (segundo par fixo confirmado)")
	if terrain ~= nil then
		assert(terrain.ClassName == "Terrain", `ClassName deveria ser inferido como 'Terrain', recebeu '{terrain.ClassName}'`)
		assert(terrain.IsServiceRoot == false, "Terrain não é um Service -- IsServiceRoot deveria ficar false")
	end
end)

test("Plan: $className explícito vence a inferência de filho fixo (mesma precedência do Service)", function()
	local plan, bag = planFixture("fixed-child-explicit-override")
	assert(not bag:HasErrors(), "explicit $className não deveria produzir erro")
	assert(plan ~= nil, "fixture 'fixed-child-explicit-override' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end

	local starterPlayer = findRootByName(plan, "StarterPlayer")
	assert(starterPlayer ~= nil, "deveria haver uma root 'StarterPlayer'")
	if starterPlayer == nil then
		return
	end

	local child = findChildByName(starterPlayer, "StarterPlayerScripts")
	assert(child ~= nil, "deveria haver um filho 'StarterPlayerScripts'")
	if child ~= nil then
		assert(child.ClassName == "Folder", `$className explícito ('Folder') deveria vencer a inferência de filho fixo ('StarterPlayerScripts') -- recebeu '{child.ClassName}'`)
	end
end)

test("Plan: $path que resolve a Folder sob um pai com filho fixo reconhecido -- a inferência VENCE o Folder genérico (mesma precedência do Service)", function()
	local plan, bag = planFixture("fixed-child-path-folder")
	assert(not bag:HasErrors(), "$path resolvendo a Folder não deveria produzir erro")
	assert(plan ~= nil, "fixture 'fixed-child-path-folder' deveria produzir um InstancePlan válido")
	if plan == nil then
		return
	end

	local workspaceNode = findRootByName(plan, "Workspace")
	assert(workspaceNode ~= nil, "deveria haver uma root 'Workspace'")
	if workspaceNode == nil then
		return
	end

	local terrain = findChildByName(workspaceNode, "Terrain")
	assert(terrain ~= nil, "deveria haver um filho 'Terrain'")
	if terrain ~= nil then
		assert(terrain.ClassName == "Terrain", `'$path' resolvendo pra Folder puro NÃO deveria vencer a inferência de filho fixo -- recebeu '{terrain.ClassName}'`)
	end
end)

test("Plan: par pai->filho fixo é MUTUAMENTE EXCLUSIVO por parentClassName -- 'Terrain' sob 'StarterPlayer' (pai errado) NÃO é inferido, produz erro 'faltou informação'", function()
	local plan, bag = planFixture("fixed-child-wrong-parent")
	assert(plan == nil, "'Terrain' sob 'StarterPlayer' (pai errado -- só é filho fixo de 'Workspace') deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/missing-class-name")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/missing-class-name' -- a inferência de filho fixo NUNCA deveria disparar pro pai errado")
	if diagnostic ~= nil then
		assert(diagnostic.NodePath == "tree.StarterPlayer.Terrain", "Diagnostic deveria nomear o nó certo")
	end
end)

--------------------------------------------------------------------------------------------------
-- task-cli-008: limite duro de profundidade de recursão -- rede de segurança COMPLEMENTAR ao
-- cycleGuard/normalizePath testado acima (aquele só cobre CICLO DE PROJETO ANINHADO; o vetor de
-- PASTA COMUM -- filhos descobertos por `fs.readDir`, sem nenhum "$path" novo a cada nível -- não
-- tinha NENHUMA proteção de ciclo antes desta tarefa; é o que um symlink/junction de pasta
-- apontando de volta pra um ancestral produziria). Ver `TreePlanner.MAX_PLAN_DEPTH`, no módulo,
-- pro número escolhido e a justificativa completa.
--------------------------------------------------------------------------------------------------

test("Plan: cadeia de pastas reais mais funda que TreePlanner.MAX_PLAN_DEPTH aborta com 'plan/max-depth-exceeded', nunca hang nem stack overflow cru", function()
	-- Gerada em disco EM TEMPO DE TESTE, fora de `src/cli/fixtures/` (mesma disciplina da
	-- investigação do revisor em revisor-cli-cycle-fix-2026-09-05.md -- scratch fora do
	-- território, removido por completo ao final): um fixture ESTÁTICO com 200+ pastas
	-- aninhadas seria um artefato de repositório absurdo (caminho gigante, risco de MAX_PATH do
	-- Windows em quem clonar sem long paths habilitado).
	local tempRoot = process.env.TEMP or process.env.TMP
	assert(tempRoot ~= nil, "TEMP/TMP precisa existir no ambiente pra este teste gerar a cadeia de pastas")
	if tempRoot == nil then
		return
	end

	local scratchRoot = `{tempRoot}/luaubench-treeplanner-max-depth-spec`
	-- Limpa resíduo de uma rodada anterior que talvez tenha abortado antes da limpeza.
	if fs.isDir(scratchRoot) then
		fs.removeDir(scratchRoot)
	end
	fs.writeDir(scratchRoot)

	-- Cadeia de pastas comuns (SEM "$path" em nenhum nível -- descobertas por `fs.readDir`,
	-- exatamente o vetor sem proteção nenhuma antes desta tarefa) -- 10 níveis além do limite,
	-- pra provar que o contador para ANTES do fim da árvore real, não por coincidência de tamanho.
	local deepBase = scratchRoot .. "/deep"
	fs.writeDir(deepBase)
	local currentPath = deepBase
	local levelsToCreate = TreePlanner.MAX_PLAN_DEPTH + 10
	for _ = 1, levelsToCreate do
		currentPath = currentPath .. "/lvl"
		fs.writeDir(currentPath)
	end

	fs.writeFile(
		scratchRoot .. "/default.project.json",
		[[{
	"name": "MaxDepthProbe",
	"tree": {
		"$className": "DataModel",
		"Vendor": {
			"$path": "deep"
		}
	}
}]]
	)

	local bag = Diagnostics.newBag()
	local project = ProjectFile.Read(scratchRoot .. "/default.project.json", bag)
	assert(project ~= nil, `ProjectFile.Read deveria ter conseguido ler o projeto gerado (bag: {#bag:All()} diagnostic(s))`)
	if project == nil then
		fs.removeDir(scratchRoot)
		return
	end

	-- `pcall` aqui não é só estilo -- é PARTE do que este teste prova: se a implementação tivesse
	-- um bug e deixasse a recursão passar do limite, o próprio Luau lançaria um erro cru de
	-- "stack overflow" (reproduzido isoladamente fora deste módulo, com a mesma forma de
	-- recursão mútua, antes de implementar a correção -- ver comentário de `MAX_PLAN_DEPTH` em
	-- `TreePlanner.luau`) -- SEM isto, esse erro derrubaria o spec inteiro sem limpar
	-- `scratchRoot`. `TreePlanner.Plan` NUNCA deveria lançar -- deveria sempre devolver `nil` com
	-- um Diagnostic (regra 04).
	local planOk, planResultOrError = pcall(function()
		return TreePlanner.Plan(project :: ProjectFile.Project, FAKE_OPTIONS, bag)
	end)

	-- Limpeza ANTES dos asserts que podem reprovar o teste -- nunca deixa resíduo em disco, mesmo
	-- se alguma asserção abaixo falhar.
	fs.removeDir(scratchRoot)

	assert(planOk, `Plan NUNCA deveria lançar um erro cru (ex.: stack overflow nativo) -- deveria devolver nil com um Diagnostic. Erro: {tostring(planResultOrError)}`)

	local plan = planResultOrError :: TreePlanner.InstancePlan?
	assert(plan == nil, "profundidade além do limite deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/max-depth-exceeded")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/max-depth-exceeded'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "estourar o limite de profundidade deveria ser Severity 'error'")
		assert(
			string.find(diagnostic.Message, tostring(TreePlanner.MAX_PLAN_DEPTH), 1, true) ~= nil,
			`Message deveria citar o número do limite ({TreePlanner.MAX_PLAN_DEPTH}). Message: {diagnostic.Message}`
		)
	end
end)

--------------------------------------------------------------------------------------------------
-- Case-insensitivity de path no Windows (achado do revisor, revisor-cli-cycle-fix-2026-09-05.md,
-- "Julgamento da pendência declarada"): duas pastas reais diferindo só em maiúscula/minúscula na
-- REFERÊNCIA (nunca no nome real em disco -- NTFS proíbe dois nomes que só diferem em case no
-- mesmo diretório), cada uma apontando "de volta" pra outra via "$path" com "..".
--
-- MUDANÇA DE CÓDIGO (achado ao rodar esta suite pra task-cli-024, nunca assumido -- ver "Rode você
-- mesmo lune run" no board): antes da guarda `plan/engine-only-class` (Decisão 17), este cenário
-- convergia em ~4 saltos via o `cycleGuard` PRÉ-EXISTENTE (comentário antigo, preservado no
-- histórico do git). Com a guarda nova, ele converge ANTES disso, em só 2 saltos, e com um
-- Diagnostic DIFERENTE: `isOutermostRoot` (`TreePlanner.luau`, `resolveCore`) compara a forma
-- NORMALIZADA de `currentProjectFilePath` contra `ctx.OutermostProjectFilePath` por IGUALDADE DE
-- STRING -- `normalizePath` NÃO faz lowercase (limitação JÁ DECLARADA no cabeçalho do arquivo,
-- "não cobre... diferença de maiúscula/minúscula em path case-insensitive do Windows"). Na segunda
-- vez que "CaseA" é visitado (via "../casea", em minúsculas, dentro de "CaseB/Back"), o caminho
-- resultante aponta pro MESMO arquivo físico, mas como STRING difere de `ctx.OutermostProjectFilePath`
-- (que guardou a forma com maiúscula, da chamada ORIGINAL) -- `isOutermostRoot` dá `false` pra essa
-- segunda visita. Essa segunda raiz declara `"$className": "DataModel"` (é o MESMO `default.
-- project.json` de "CaseA"), e "DataModel" fora da raiz mais externa é EXATAMENTE o que
-- `plan/engine-only-class` existe pra pegar (é o mesmo mecanismo do bug original, task-cli-022) --
-- a guarda dispara e devolve `nil` ANTES de "CaseA" (revisitado) sequer chegar a expandir seu
-- filho "Vendor" de novo, que é o passo que precisaria de mais 2 saltos pra fechar o ciclo via
-- `cycleGuard` como antes. NÃO é uma regressão de comportamento -- é um resultado tecnicamente
-- válido (ainda impede o hang, ainda como `error`), só que MAIS CEDO e com um código diferente;
-- documentado aqui, e no relatório da task-cli-024, por ser um efeito colateral que a Decisão 17
-- não previu explicitamente (só nomeou "TreeMaterializer.spec.luau:812" como teste que mudaria de
-- fase). O teste ACIMA (cadeia de pastas comuns) continua provando o limite de profundidade em si,
-- pro vetor que nem o `cycleGuard` nem `plan/engine-only-class` cobrem (pasta comum, sem "$path"
-- repetido nenhum).
--------------------------------------------------------------------------------------------------

test("Plan: duas pastas diferindo só em maiúscula/minúscula (Windows) apontando uma pra outra não trava -- converge via 'plan/engine-only-class' (task-cli-024), mais cedo que o cycleGuard de antes", function()
	local startClock = os.clock()
	local plan, bag = planFixture("nested-project-cycle-case-insensitive/CaseA")
	local elapsedSeconds = os.clock() - startClock

	assert(plan == nil, "ciclo via case-insensitivity deveria impedir Plan de devolver um InstancePlan")
	assert(elapsedSeconds < 10, `Plan não deveria demorar mais que alguns segundos -- levou {elapsedSeconds}s (indício de hang)`)

	-- Ver comentário grande acima: a guarda nova (`plan/engine-only-class`) agora fecha este caso
	-- ANTES do `cycleGuard` pré-existente (`plan/nested-project-cycle`) ter a chance de disparar --
	-- nunca `plan/max-depth-exceeded` (esse cenário nem chega perto do limite, converge em 2 saltos).
	local engineOnlyDiagnostic = findByCode(bag, "plan/engine-only-class")
	assert(engineOnlyDiagnostic ~= nil, "deveria haver um Diagnostic 'plan/engine-only-class' -- a guarda nova (task-cli-024) fecha este caso mais cedo que o cycleGuard pré-existente")
	assert(findByCode(bag, "plan/nested-project-cycle") == nil, "NÃO deveria mais haver 'plan/nested-project-cycle' aqui -- 'plan/engine-only-class' dispara ANTES, na segunda visita a 'CaseA' (revisitado com case diferente)")
	assert(findByCode(bag, "plan/max-depth-exceeded") == nil, "este cenário NÃO deveria alcançar o limite de profundidade -- converge em poucos saltos")

	if engineOnlyDiagnostic ~= nil then
		assert(engineOnlyDiagnostic.Severity == "error", "classe só-do-motor em posição de nó deveria ser Severity 'error'")
		assert(string.find(engineOnlyDiagnostic.Message, "DataModel", 1, true) ~= nil, "Message deveria citar a classe 'DataModel' -- é o mesmo default.project.json de 'CaseA', revisitado")
	end
end)

--------------------------------------------------------------------------------------------------
-- task-cli-024 (arquiteto-cli-2026-09-05.md, Decisão 17): 'plan/engine-only-class' -- o `Plan`
-- antecipa que `TreeMaterializer.createInstance` cairia no ramo `Services.new` pra um nó cuja
-- classe é `NotCreatable` no dump E que este build sabe simular ("this build" = `FAKE_OPTIONS`,
-- não `services` de verdade -- ver comentário de `FAKE_ENGINE_ONLY_CLASSES`, acima).
--------------------------------------------------------------------------------------------------

test("Plan: raiz de projeto ANINHADO com \"$className\": \"DataModel\" + pasta sem init.* -> 'plan/engine-only-class' citando o .project.json ANINHADO (o bug original, task-cli-022)", function()
	local plan, bag = planFixture("nested-project-root-engine-only-class")
	assert(plan == nil, "raiz de projeto aninhado resolvendo pra 'DataModel' deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/engine-only-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/engine-only-class'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "classe só-do-motor em posição de nó deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree", "Diagnostic deveria nomear a raiz DO PROJETO ANINHADO ('tree' -- NodePath da raiz de qualquer arquivo de projeto lido isoladamente)")
		assert(diagnostic.Field == "$className", "Diagnostic deveria nomear o CAMPO ($className) -- a classe veio de um $className explícito")
		assert(
			diagnostic.FilePath ~= nil and string.find(diagnostic.FilePath, "nested-project-root-engine-only-class/pkg", 1, true) ~= nil,
			`FilePath deveria citar o .project.json ANINHADO ('pkg/default.project.json'), não o da raiz do plano -- é o ganho real sobre 'materialize/invalid-class' (só tem NodePath). FilePath: {tostring(diagnostic.FilePath)}`
		)
		assert(string.find(diagnostic.Message, "DataModel", 1, true) ~= nil, "Message deveria citar a classe 'DataModel'")
		assert(string.find(diagnostic.Message, "outermost", 1, true) ~= nil, "Message deveria ter a frase extra pra 'DataModel' (Decisão 17: só dentro de Messages.PlanEngineOnlyClass, um Code só)")
	end
end)

test("Plan: \"$className\": \"Instance\" num nó comum (não é raiz, Service, nem filho fixo) -> 'plan/engine-only-class'", function()
	local plan, bag = planFixture("engine-only-class-instance")
	assert(plan == nil, "'$className': 'Instance' num nó comum deveria impedir Plan de devolver um InstancePlan")

	local diagnostic = findByCode(bag, "plan/engine-only-class")
	assert(diagnostic ~= nil, "deveria haver um Diagnostic 'plan/engine-only-class'")
	if diagnostic ~= nil then
		assert(diagnostic.Severity == "error", "'Instance' em posição de nó deveria ser Severity 'error'")
		assert(diagnostic.NodePath == "tree.ReplicatedStorage.Bad", "Diagnostic deveria nomear o nó exato")
		assert(diagnostic.Field == "$className", "Diagnostic deveria nomear o CAMPO ($className)")
		assert(string.find(diagnostic.Message, "Instance", 1, true) ~= nil, "Message deveria citar a classe 'Instance'")
		assert(string.find(diagnostic.Message, "NotCreatable", 1, true) ~= nil, "Message deveria citar a tag 'NotCreatable' do Roblox API Dump como justificativa")
		assert(string.find(diagnostic.Message, "outermost", 1, true) == nil, "Message NÃO deveria ter a frase extra de 'DataModel' -- essa classe é 'Instance', não 'DataModel'")
	end
end)

test("Plan: REGRESSÃO -- Service como filho direto da raiz ('basic') e StarterPlayerScripts/Terrain ('fixed-children') continuam SEM 'plan/engine-only-class'", function()
	local basicPlan, basicBag = planFixture("basic")
	assert(basicPlan ~= nil, "fixture 'basic' deveria continuar produzindo um InstancePlan válido")
	assert(findByCode(basicBag, "plan/engine-only-class") == nil, "Service ('ReplicatedStorage') como filho direto da raiz NUNCA deveria disparar 'plan/engine-only-class' -- é a exclusão isServiceRoot")

	local fixedPlan, fixedBag = planFixture("fixed-children")
	assert(fixedPlan ~= nil, "fixture 'fixed-children' deveria continuar produzindo um InstancePlan válido")
	assert(not fixedBag:HasErrors(), "fixture 'fixed-children' NÃO deveria produzir nenhum erro -- é o repro exato do bug real (17/17 projetos do usuário)")
	assert(findByCode(fixedBag, "plan/engine-only-class") == nil, "StarterPlayerScripts/StarterCharacterScripts/Terrain (filhos fixos do motor) NUNCA deveriam disparar 'plan/engine-only-class' -- é a exclusão isEngineFixedChild")
end)

test("Plan: REGRESSÃO -- raiz de TOPO 'DataModel' + pasta sem init.* ('root-source-ignored') continua passando SEM 'plan/engine-only-class', só o warning de sempre", function()
	local plan, bag = planFixture("root-source-ignored")
	assert(plan ~= nil, "fixture 'root-source-ignored' deveria continuar produzindo um InstancePlan válido")
	assert(not bag:HasErrors(), "raiz de TOPO com 'DataModel' explícito NUNCA deveria produzir erro -- é a exclusão isOutermostRoot")
	assert(findByCode(bag, "plan/engine-only-class") == nil, "raiz de TOPO NUNCA deveria disparar 'plan/engine-only-class' -- é a exclusão isOutermostRoot")
	assert(findByCode(bag, "plan/root-source-ignored") ~= nil, "deveria continuar emitindo só o warning 'plan/root-source-ignored' de sempre (task-cli-018)")
end)

test("Plan: REGRESSÃO -- raiz de projeto aninhado 'DataModel' + \"$path\" de ARQUIVO continua 'plan/class-name-conflict' (Decisão 16 dispara ANTES da guarda nova)", function()
	local plan, bag = planFixture("nested-project-root-datamodel-conflict")
	assert(plan == nil, "raiz de projeto aninhado com DataModel + $path de Source deveria continuar impedindo Plan de devolver um InstancePlan")
	assert(findByCode(bag, "plan/class-name-conflict") ~= nil, "deveria continuar 'plan/class-name-conflict' -- guarda pré-existente (Decisão 16) dispara e retorna nil ANTES de chegar na guarda nova (task-cli-024)")
	assert(findByCode(bag, "plan/engine-only-class") == nil, "NÃO deveria haver 'plan/engine-only-class' aqui -- 'plan/class-name-conflict' já retornou nil antes")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
