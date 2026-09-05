--!strict

--[[
	Teste da task-cli-006 (`ScriptRunner.luau`). Cobre o acceptance do board (Decisão 11):

	- `Script` sob um `ServerScriptContainers` com `Enabled ~= false` executa (contado em `Executed`).
	- `Script` fora de todo `ServerScriptContainers` é carregado mas nunca executa (`SkippedByContainer`).
	- `Script` com `Enabled = false` nunca executa (`SkippedDisabled`).
	- `LocalScript` NUNCA executa, contado em `SkippedLocalScripts` INDEPENDENTE de container.
	- `ModuleScript` nunca executa sozinho e não aparece em nenhum campo do `RunSummary`.
	- Ordem determinística: dois `Script`s no MESMO contêiner rodam na ordem em que aparecem em
	  `tree.Scripts` (profundidade+nome, já garantida por `TreeMaterializer`/`TreePlanner`).
	- Ordem por CONTÊINER: a ordem de execução segue `RunPolicy.ServerScriptContainers`, não a
	  ordem incidental de `tree.Scripts` -- testado com uma política que INVERTE a ordem default,
	  e um `tree.Scripts` construído à mão na ordem "errada" de propósito.

	Instances construídas em memória via `Services.new` (nenhum `.project.json`/fixture em disco
	necessário -- este território testa a POLÍTICA de execução, não parsing de projeto Rojo;
	fixtures reais em disco são testadas em `RunCommand.spec.luau`, que exercita o pipeline
	inteiro).

	Roda com `lune run src/cli/ScriptRunner.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Services = require("../services")
local ModuleLoader = require("./ModuleLoader")
local ScriptRunner = require("./ScriptRunner")
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

-- `PlanNode` mínimo, com todos os campos do tipo preenchidos com valores neutros -- `ScriptRunner`
-- só lê `Node.ClassName` de verdade; o resto existe só para satisfazer o tipo (`--!strict`, regra
-- 01: sem `any`, nenhum campo pode ficar de fora).
local function fakeNode(className: string): TreePlanner.PlanNode
	return {
		Name = className,
		ClassName = className,
		IsServiceRoot = false,
		Source = nil,
		SourcePath = nil,
		Properties = {},
		Children = {},
		NodePath = `tree.{className}`,
	}
end

type Harness = {
	Scheduler: Runtime.Scheduler,
	Game: Runtime.DataModel,
	Workspace: Runtime.Instance,
	ServerScriptService: Runtime.Instance,
	ReplicatedStorage: Runtime.Instance,
	Records: { Runtime.OutputRecord },
}

local function newHarness(): Harness
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })

	-- `DataModel:GetService` passou de `-> Instance` para `-> Instance?` (task-runtime-030) -- os
	-- três nomes abaixo estão sempre cobertos pelo `Bootstrap` acima, então o `nil` é inalcançável
	-- aqui; `assert` (nunca `::`) é o narrowing padrão já usado no resto deste arquivo de spec.
	local workspaceInstance = game:GetService("Workspace")
	local serverScriptService = game:GetService("ServerScriptService")
	local replicatedStorage = game:GetService("ReplicatedStorage")
	assert(workspaceInstance ~= nil, "Workspace deveria estar sempre coberta pelo Bootstrap deste teste")
	assert(serverScriptService ~= nil, "ServerScriptService deveria estar sempre coberta pelo Bootstrap deste teste")
	assert(replicatedStorage ~= nil, "ReplicatedStorage deveria estar sempre coberta pelo Bootstrap deste teste")

	return {
		Scheduler = scheduler,
		Game = game,
		Workspace = workspaceInstance,
		ServerScriptService = serverScriptService,
		ReplicatedStorage = replicatedStorage,
		Records = {},
	}
end

local function newContext(harness: Harness, policy: ScriptRunner.RunPolicy?): ScriptRunner.RunContext
	return {
		Scheduler = harness.Scheduler,
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = {},
		SharedTable = {},
		ModuleCache = ModuleLoader.NewCache(),
		OnOutput = function(record: Runtime.OutputRecord)
			table.insert(harness.Records, record)
		end,
		Policy = if policy ~= nil then policy else ScriptRunner.DefaultPolicy(),
	}
end

-- Instância de `className`, com `Source` (default `""`) e já parenteada -- devolve o par que
-- `TreeMaterializer.MaterializedScript` exige.
local function newScript(className: string, name: string, parent: Runtime.Instance, source: string?): TreeMaterializer.MaterializedScript
	local instance = Services.new(className, name)
	Runtime.Instance.SetPropertyRaw(instance, "Source", if source ~= nil then source else "")
	instance.Parent = parent
	return {
		Instance = instance,
		Node = fakeNode(className),
		FullName = instance:GetFullName(),
	}
end

--------------------------------------------------------------------------------------------------
-- Caminho feliz: Script elegível executa, é contado, e produz o print esperado
--------------------------------------------------------------------------------------------------

test("Script sob um ServerScriptContainers com Enabled ~= false executa e é contado em Executed", function()
	local harness = newHarness()
	local script = newScript("Script", "Main", harness.ServerScriptService, [[ print("ran") ]])

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { script } }
	local summary = ScriptRunner.Run(tree, newContext(harness))

	assert(summary.Executed == 1, `esperava Executed == 1, recebeu {summary.Executed}`)
	assert(summary.SkippedLocalScripts == 0, "não deveria haver LocalScript pulado")
	assert(summary.SkippedByContainer == 0, "não deveria haver Script pulado por container")
	assert(summary.SkippedDisabled == 0, "não deveria haver Script pulado por Enabled = false")

	assert(#harness.Records == 1, `esperava exatamente 1 OutputRecord, recebeu {#harness.Records}`)
	assert(harness.Records[1].level == "print", "o único record deveria ser um print")
	assert(harness.Records[1].message == "ran", `mensagem inesperada: {harness.Records[1].message}`)
end)

--------------------------------------------------------------------------------------------------
-- Script fora de todo ServerScriptContainers: carregado, nunca executado
--------------------------------------------------------------------------------------------------

test("Script fora de todo ServerScriptContainers (ex.: ReplicatedStorage) nunca executa -- SkippedByContainer", function()
	local harness = newHarness()
	local script = newScript("Script", "NotRun", harness.ReplicatedStorage, [[ print("THIS SHOULD NEVER RUN") ]])

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { script } }
	local summary = ScriptRunner.Run(tree, newContext(harness))

	assert(summary.Executed == 0, "não deveria ter executado nada")
	assert(summary.SkippedByContainer == 1, `esperava SkippedByContainer == 1, recebeu {summary.SkippedByContainer}`)
	assert(#harness.Records == 0, "nenhum OutputRecord deveria ter sido gerado (o script nunca rodou)")
end)

--------------------------------------------------------------------------------------------------
-- Script com Enabled = false: carregado, nunca executado
--------------------------------------------------------------------------------------------------

test("Script com Enabled = false nunca executa -- SkippedDisabled", function()
	local harness = newHarness()
	local script = newScript("Script", "Muted", harness.ServerScriptService, [[ print("THIS SHOULD NEVER RUN") ]])

	-- Cast de fronteira (mesmo padrão de `ScriptRunner.isScriptDisabled`): `Runtime.Instance` (o
	-- tipo de `MaterializedScript.Instance`) não declara "Enabled" -- só a interseção `BaseScript`
	-- que `services` monta internamente. A escrita ainda passa pelo `__newindex` real (que valida
	-- contra o `ClassSchema` de "Script").
	local writableScript = (script.Instance :: unknown) :: { Enabled: boolean }
	writableScript.Enabled = false

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { script } }
	local summary = ScriptRunner.Run(tree, newContext(harness))

	assert(summary.Executed == 0, "não deveria ter executado nada")
	assert(summary.SkippedDisabled == 1, `esperava SkippedDisabled == 1, recebeu {summary.SkippedDisabled}`)
	assert(#harness.Records == 0, "nenhum OutputRecord deveria ter sido gerado (o script nunca rodou)")
end)

--------------------------------------------------------------------------------------------------
-- LocalScript: NUNCA executa, independente de container
--------------------------------------------------------------------------------------------------

test("LocalScript nunca executa, mesmo dentro de um ServerScriptContainers -- SkippedLocalScripts", function()
	local harness = newHarness()
	local localScript = newScript("LocalScript", "ClientEntry", harness.ServerScriptService, [[ print("THIS SHOULD NEVER RUN") ]])

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { localScript } }
	local summary = ScriptRunner.Run(tree, newContext(harness))

	assert(summary.Executed == 0, "não deveria ter executado nada")
	assert(summary.SkippedLocalScripts == 1, `esperava SkippedLocalScripts == 1, recebeu {summary.SkippedLocalScripts}`)
	assert(summary.SkippedByContainer == 0, "LocalScript não é classificado por container")
	assert(#harness.Records == 0, "nenhum OutputRecord deveria ter sido gerado (o LocalScript nunca roda)")
end)

--------------------------------------------------------------------------------------------------
-- ModuleScript: nunca executa sozinho, não aparece em NENHUM campo do RunSummary
--------------------------------------------------------------------------------------------------

test("ModuleScript nunca executa sozinho e não é contado em nenhum campo do RunSummary", function()
	local harness = newHarness()
	local moduleScript = newScript("ModuleScript", "Foo", harness.ReplicatedStorage, [[ return {} ]])

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { moduleScript } }
	local summary = ScriptRunner.Run(tree, newContext(harness))

	assert(summary.Executed == 0, "ModuleScript não deveria contar como executado")
	assert(summary.SkippedLocalScripts == 0, "ModuleScript não é LocalScript")
	assert(summary.SkippedByContainer == 0, "ModuleScript não é classificado por container")
	assert(summary.SkippedDisabled == 0, "ModuleScript não é classificado por Enabled")
	assert(#harness.Records == 0, "nenhum OutputRecord deveria ter sido gerado (ModuleScript nunca roda sozinho)")
end)

--------------------------------------------------------------------------------------------------
-- Ordem determinística DENTRO do mesmo contêiner: segue a ordem de tree.Scripts
--------------------------------------------------------------------------------------------------

test("Dois Scripts no mesmo contêiner executam na ordem de tree.Scripts (profundidade+nome já garantidos por TreeMaterializer)", function()
	local harness = newHarness()
	local order: { string } = {}
	local globalTable: { [string]: unknown } = { order = order }

	local scriptA = newScript("Script", "A", harness.ServerScriptService, [[ table.insert(_G.order, "A") ]])
	local scriptB = newScript("Script", "B", harness.ServerScriptService, [[ table.insert(_G.order, "B") ]])

	local tree: TreeMaterializer.MaterializedTree = { Game = harness.Game, Scripts = { scriptA, scriptB } }
	local context = newContext(harness)
	context.GlobalTable = globalTable

	local summary = ScriptRunner.Run(tree, context)

	assert(summary.Executed == 2, `esperava Executed == 2, recebeu {summary.Executed}`)
	assert(#order == 2, `esperava 2 entradas em order, recebeu {#order}`)
	assert(order[1] == "A" and order[2] == "B", `ordem incorreta: {order[1]}, {order[2]}`)
end)

--------------------------------------------------------------------------------------------------
-- Ordem por CONTÊINER: segue RunPolicy.ServerScriptContainers, não a ordem incidental de
-- tree.Scripts
--------------------------------------------------------------------------------------------------

test("Ordem de execução segue RunPolicy.ServerScriptContainers, não a ordem de tree.Scripts", function()
	local harness = newHarness()
	local order: { string } = {}
	local globalTable: { [string]: unknown } = { order = order }

	-- tree.Scripts na ordem "errada" de propósito: ServerScriptService ANTES de Workspace --
	-- mas a política abaixo inverte (Workspace primeiro). Se ScriptRunner confiasse na ordem
	-- crua de tree.Scripts em vez de agrupar por contêiner na ordem da política, "SSS" rodaria
	-- antes de "WS" -- o teste falharia.
	local serverScriptServiceScript = newScript("Script", "SSS", harness.ServerScriptService, [[ table.insert(_G.order, "SSS") ]])
	local workspaceScript = newScript("Script", "WS", harness.Workspace, [[ table.insert(_G.order, "WS") ]])

	local tree: TreeMaterializer.MaterializedTree = {
		Game = harness.Game,
		Scripts = { serverScriptServiceScript, workspaceScript },
	}

	local invertedPolicy: ScriptRunner.RunPolicy = {
		ServerScriptContainers = { "Workspace", "ServerScriptService" },
		RunLocalScripts = false,
	}
	local context = newContext(harness, invertedPolicy)
	context.GlobalTable = globalTable

	local summary = ScriptRunner.Run(tree, context)

	assert(summary.Executed == 2, `esperava Executed == 2, recebeu {summary.Executed}`)
	assert(#order == 2, `esperava 2 entradas em order, recebeu {#order}`)
	assert(order[1] == "WS" and order[2] == "SSS", `ordem deveria seguir a política (Workspace antes de ServerScriptService), recebeu: {order[1]}, {order[2]}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
