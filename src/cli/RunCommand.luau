--!strict

--[[
	Orquestra o pipeline inteiro de `luaubench run [caminho]` (arquiteto-cli-2026-09-05.md, seção
	"Pipeline do `luaubench run [caminho]`" -- LER A SEÇÃO INTEIRA, mais as Decisões 3, 4, 5, 7,
	11 e 13, antes de mexer aqui). É o módulo que finalmente liga `.project.json` -> `DataModel`
	real -> scripts executando de verdade -- consome `ProjectFile`/`TreePlanner`/
	`TreeMaterializer`/`ScriptRunner`/`OutputFormatter`/`ModuleLoader` (todos já existentes), sem
	reimplementar nada deles.

	OS DOZE PASSOS (copiados aqui do desenho, verbatim, porque é este arquivo que os implementa):

	  1. Args.Parse(process.args)                          -> Command            (feito por quem
	     chama -- `init.luau`/`Cli.Main` -- que já traduziu o `Command` em `RunOptions` antes de
	     chegar aqui; `RunCommand` nunca lê `process.args`/`Args.luau` diretamente)
	  2. ProjectFile.Locate(caminho, process.cwd)          -> caminho absoluto do .project.json
	  3. ProjectFile.Read(path, bag)                       -> Project (campos de topo validados)
	  4. TreePlanner.Plan(project, {IsServiceClass=...}, bag) -> InstancePlan
	         (lê o filesystem; NENHUMA Instance criada ainda)
	  5. bag:HasErrors()  ->  imprime TODOS os diagnósticos e sai (exit 2)
	  6. scheduler = Runtime.Scheduler.new();  game = Runtime.DataModel.new()
	  7. Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	  8. para cada c em Services.GetSimulatedServiceClasses(): game:GetService(c)
	  9. TreeMaterializer.Materialize(plan, game, bag)     -> MaterializedTree
	 10. ScriptRunner.Run(tree, ctx)                       -> um Sandbox.Run por Script elegível
	 11. scheduler:Run(shouldContinue)                      -- shouldContinue = deadline de --timeout
	 12. imprime sumário (warnings, LocalScripts não executados, erros) e devolve o exit code

	"PASSOS 4 E 7 NA ORDEM CERTA" (citação direta do desenho): planejar (passo 4) ANTES de
	registrar (passo 7) é de propósito -- um projeto inválido é recusado com o mundo ainda não
	construído (Decisão 3, "falha antes de mutar"). O gate do passo 5 acontece ANTES de qualquer
	`Runtime.Scheduler.new()`/`Runtime.DataModel.new()` -- nenhuma Instance existe se o projeto for
	rejeitado ali.

	EXIT CODES (verbatim do desenho): `0` sucesso; `1` o script do usuário levantou ao menos um
	erro não tratado; `2` erro de projeto ou de uso. Um erro de projeto (`bag:HasErrors()`) tem
	PRIORIDADE sobre um erro de script: mesmo que `TreeMaterializer.Materialize` (passo 9) só
	adicione um erro DEPOIS que alguns scripts já rodaram (ex.: `$properties` inválido num nó
	tardio da árvore -- TreeMaterializer nunca aborta a árvore inteira por um nó, ver
	`TreeMaterializer.luau`), o exit code final ainda reflete "erro de projeto" (2), nunca "erro de
	script" (1) -- é o sinal mais acionável: algo no `.project.json`/filesystem está errado,
	independente de scripts terem rodado ou não.

	`--timeout` (Decisão 11, "Riscos e decisões"): `shouldContinue` é uma REDE DE SEGURANÇA para o
	script que CEDE (`while true do task.wait() end`), NUNCA um watchdog -- `Scheduler:Run` só
	consulta `shouldContinue` ENTRE tiques (ver `Scheduler.luau`, `Scheduler.Run`); um
	`while true do end` sem yield nenhum trava o laço de `coroutine.resume` de verdade e este
	deadline nunca chega a ser consultado. Limitação já aceita no desenho do `runtime`, documentada
	aqui de novo porque é este módulo que constrói o `shouldContinue`.

	Depende de: `ProjectFile.luau`, `TreePlanner.luau`, `TreeMaterializer.luau`, `ScriptRunner.luau`,
	`OutputFormatter.luau`, `ModuleLoader.luau`, `Diagnostics.luau`, `Messages.luau`, `../runtime`,
	`../services`. NUNCA `../services/generated/**`/`behavior/**` (regra 03) nem um módulo interno
	de `runtime` por fora de `require("../runtime")` (regra 02).
]]

local Runtime = require("../runtime")
local Services = require("../services")
local Diagnostics = require("./Diagnostics")
local Messages = require("./Messages")
local ModuleLoader = require("./ModuleLoader")
local OutputFormatter = require("./OutputFormatter")
local ProjectFile = require("./ProjectFile")
local ScriptRunner = require("./ScriptRunner")
local TreeMaterializer = require("./TreeMaterializer")
local TreePlanner = require("./TreePlanner")
local stdio = require("@lune/stdio")

export type RunOptions = {
	ProjectPath: string?,
	Cwd: string,
	Timeout: number?,
	UseColor: boolean,
	Verbose: boolean,
}

-- Forma ESTRUTURALMENTE idêntica a `Cli.MainResult` (`src/cli/init.luau`) -- de propósito, NÃO um
-- `require("./")`/`require("./init")` de volta para `init.luau` (isso criaria um require
-- circular: `init.luau` já requer este arquivo para poder chamá-lo -- regra 01, "dependência
-- circular entre módulos é erro de design"). O Luau compara tipos de tabela ESTRUTURALMENTE, não
-- por nome -- `init.luau` devolve o valor deste tipo diretamente como `Cli.MainResult` sem
-- nenhum cast, porque as formas batem campo a campo.
export type Result = {
	ExitCode: number,
	ErrorCount: number,
	WarningCount: number,
}

local RunCommand = {}

local EXIT_OK = 0
local EXIT_SCRIPT_ERROR = 1
local EXIT_PROJECT_ERROR = 2

-- Diagnósticos de PROJETO (erro/aviso/info do `.project.json`/filesystem -- nunca do script do
-- usuário, que passa por `OutputFormatter`) sempre vão para stderr -- mesmo canal que
-- `Cli.Main` já usa para erro de uso (`Messages.UnknownFlag`, etc. em `init.luau`). Mantém stdout
-- reservado para o que o SCRIPT do usuário de fato imprimiu (`print`), o que é o que faz
-- `luaubench run > saida.txt` capturar só a "saída de dados" real, não o ruído de diagnóstico do
-- próprio CLI. Severidade "info" só aparece com `--verbose` (Decisão 8 do desenho, "`$path`
-- opcional ausente").
local function printDiagnostics(bag: Diagnostics.Bag, useColor: boolean, verbose: boolean): ()
	for _, diagnostic in bag:All() do
		if diagnostic.Severity == "info" and not verbose then
			continue
		end
		stdio.ewrite(Diagnostics.Render(diagnostic, useColor) .. "\n")
	end
end

-- `shouldContinue` de `--timeout` (ver cabeçalho, "Riscos e decisões"). `nil` (sem `--timeout`)
-- devolve `nil` -- `Scheduler:Run(nil)` roda até `IsAlive()` virar `false` por conta própria,
-- comportamento de sempre.
local function buildShouldContinue(timeoutSeconds: number?): (() -> boolean)?
	if timeoutSeconds == nil then
		return nil
	end
	local deadline = os.clock() + timeoutSeconds
	return function(): boolean
		return os.clock() < deadline
	end
end

-- Passos 2-5: localizar, ler e planejar. Devolve `nil` (com os diagnósticos já dentro de `bag`)
-- se qualquer um dos três falhar -- quem chama já sabe, nesse caso, que o mundo nunca deve ser
-- construído (Decisão 3).
local function locateAndPlan(options: RunOptions, bag: Diagnostics.Bag): TreePlanner.InstancePlan?
	local projectPath, locateDiagnostic = ProjectFile.Locate(options.ProjectPath, options.Cwd)
	if locateDiagnostic ~= nil then
		bag:Add(locateDiagnostic)
	end
	if projectPath == nil then
		return nil
	end

	local project = ProjectFile.Read(projectPath, bag)
	if project == nil or bag:HasErrors() then
		return nil
	end

	local plan = TreePlanner.Plan(project, { IsServiceClass = Services.IsServiceClass }, bag)
	if plan == nil or bag:HasErrors() then
		return nil
	end

	return plan
end

-- API pública. Único ponto de entrada do território pra rodar o pipeline inteiro (passos 6-12
-- inline aqui -- ver cabeçalho do módulo; não fatorado em uma função separada porque `formatter`
-- precisa continuar vivo até o cálculo do exit code final, e Lua não tem "out params").
function RunCommand.Execute(options: RunOptions): Result
	local bag = Diagnostics.newBag()

	local plan = locateAndPlan(options, bag)
	if plan == nil then
		printDiagnostics(bag, options.UseColor, options.Verbose)
		return {
			ExitCode = EXIT_PROJECT_ERROR,
			ErrorCount = bag:CountOf("error"),
			WarningCount = bag:CountOf("warning"),
		}
	end

	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })

	for _, className in Services.GetSimulatedServiceClasses() do
		game:GetService(className)
	end

	local tree = TreeMaterializer.Materialize(plan, game, bag)

	local formatter = OutputFormatter.new(options.UseColor)
	local workspaceInstance = game:GetService("Workspace")
	local globalTable: { [string]: unknown } = {}
	local sharedTable: { [string]: unknown } = {}

	local summary = ScriptRunner.Run(tree, {
		Scheduler = scheduler,
		Game = game,
		Workspace = workspaceInstance,
		GlobalTable = globalTable,
		SharedTable = sharedTable,
		ModuleCache = ModuleLoader.NewCache(),
		OnOutput = function(record: Runtime.OutputRecord)
			formatter:Emit(record)
		end,
		Policy = ScriptRunner.DefaultPolicy(),
	})

	scheduler:Run(buildShouldContinue(options.Timeout))

	printDiagnostics(bag, options.UseColor, options.Verbose)
	print(Messages.SummaryLine(summary.Executed, summary.SkippedLocalScripts, summary.SkippedByContainer, summary.SkippedDisabled))
	local totalErrorCount = bag:CountOf("error") + formatter:ErrorCount()
	print(Messages.DiagnosticCountLine(totalErrorCount, bag:CountOf("warning")))

	local exitCode: number
	if bag:HasErrors() then
		exitCode = EXIT_PROJECT_ERROR
	elseif formatter:ErrorCount() > 0 then
		exitCode = EXIT_SCRIPT_ERROR
	else
		exitCode = EXIT_OK
	end

	return {
		ExitCode = exitCode,
		ErrorCount = totalErrorCount,
		WarningCount = bag:CountOf("warning"),
	}
end

return RunCommand
