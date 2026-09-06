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
	  7. Services.Bootstrap({ scheduler = scheduler, dataModel = game, AllowHttp = ...,
	     AllowHttpLocal = ..., OnHttpRequest = ... }) -- os três últimos campos são task-cli-026,
	     ver mais abaixo
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
	`../services`, `../valuetypes` (task-cli-025, item e -- só `Runtime.TypeNameResolver.Set(
	ValueTypes.TypeNameOf)`). NUNCA `../services/generated/**`/`behavior/**` (regra 03) nem um
	módulo interno de `runtime`/`valuetypes` por fora dos respectivos agregadores públicos (regra
	02/regra 06).

	FLAGS DE REDE (task-cli-026, par de task-services-026 -- arquiteto-services-2026-09-05.md,
	seção "L2.2 -- HttpService", L2.2.1/L2.2.4): `RunOptions.AllowHttp`/`AllowHttpLocal` espelham
	`Args.Command` 1:1 (default `false` -- rede desligada, igual `HttpEnabled` num lugar recém-
	criado no Roblox real) e são repassadas cruas para `Services.BootstrapOptions` no passo 7.
	`OnHttpRequest` é o canal NOVO desta tarefa: um callback `(method: string, host: string) -> ()`
	que `services` (`behavior/HttpService.luau`) chama de volta UMA VEZ por requisição de saída,
	ANTES de tocar a rede de verdade -- é o que permite este módulo (não `services`) decidir SE e
	COMO a linha de auditoria aparece (`options.Verbose`, `Messages.HttpRequestAuditLine`), sem que
	`services` precise conhecer `Messages.luau`/stdio (regra 03: `services` só usa a API pública de
	`runtime`, nunca formata output do CLI). Contrato coordenado em paralelo com `coder-services` --
	se `Services.BootstrapOptions` ainda não tiver estes três campos quando este arquivo for lido,
	é porque as duas tarefas estavam em voo ao mesmo tempo; o nome exato dos campos foi acertado
	entre os dois territórios ANTES de qualquer um escrever código (nunca adivinhado por um lado só).
]]

local Runtime = require("../runtime")
local Services = require("../services")
local ValueTypes = require("../valuetypes")
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
	-- task-cli-026 (par de task-services-026, arquiteto-services-2026-09-05.md, L2.2.1/L2.2.4):
	-- espelham `Args.Command` 1:1 ("run"), default `false` nos dois -- rede desligada por padrão,
	-- exatamente como `HttpEnabled` num lugar recém-criado no Roblox real. `AllowHttpLocal = true`
	-- sem `AllowHttp = true` nunca chega aqui: `Args.parseRunArgs` já garante a implicação (ver
	-- Args.luau, "--allow-http-local").
	AllowHttp: boolean,
	AllowHttpLocal: boolean,
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

-- task-cli-032 (BUG achado independentemente por coder/revisor de task-cli-031, já commitada):
-- um `error()` dentro de um callback de `game:BindToClose(fn)` saía por `scheduler.ThreadError`
-- (mesmo canal de qualquer outra thread gerida, ver Scheduler.luau/`resumeThread`) mas NENHUM
-- listener estava conectado para essas threads especificamente -- `Sandbox.Run` só se inscreve
-- para as threads que ELE MESMO cria (`ownThreads`, ver cabeçalho de `Sandbox.luau`), e as
-- threads de `RunBindToCloseCallbacks` nascem direto ali dentro via `scheduler:Spawn`, fora de
-- qualquer `Sandbox.Run`. Resultado: erro real (ex.: falha ao salvar a sessão final de um
-- ProfileStore dentro de `BindToClose`) virava sucesso aparente (exit 0, "0 error(s)").
--
-- Esta função extrai `(scriptName, line, message)` da mensagem CRUA de um `ThreadError` dessas
-- threads -- mesma convenção documentada em `Sandbox.splitErrorMessage` (corta na primeira
-- quebra de linha, procura o marcador `[string "..."]:<n>: ` do VM do Luau) e em
-- `OutputFormatter.tryReattributeModuleError` (busca NÃO ANCORADA a um nome esperado, porque um
-- callback de `BindToClose` pode ter sido registrado por QUALQUER Script do projeto -- este
-- módulo só descobre qual lendo a própria mensagem). Reescrita AQUI, e não reexportada de
-- nenhum dos dois módulos citados, porque nenhum dos dois expõe essa lógica publicamente e o
-- território desta tarefa (task-cli-032) é só este arquivo/spec -- ver "API faltante" no
-- relatório da tarefa: o ideal de longo prazo é uma única função exportada compartilhada pelos
-- três lugares, para as três cópias nunca divergirem em silêncio (regra 01).
local function parseBindToCloseThreadError(raw: string): (string?, number?, string)
	local firstLine = raw
	local newlineIndex = string.find(raw, "\n")
	if newlineIndex ~= nil then
		firstLine = string.sub(raw, 1, newlineIndex - 1)
	end

	local scriptName, lineText, message = string.match(firstLine, '%[string "(.-)"%]:(%d+): (.*)$')
	if scriptName == nil or lineText == nil or message == nil then
		-- Marcador não encontrado (formato de erro que não reconhecemos) -- degrada para a
		-- primeira linha crua, sem nome/linha, nunca falha (mesmo protocolo de
		-- `Sandbox.splitErrorMessage`).
		return nil, nil, firstLine
	end
	return scriptName, tonumber(lineText), message
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

	-- task-cli-024: as três funções são injetadas (nunca `require("../services")` dentro de
	-- `TreePlanner` -- ver cabeçalho do módulo). `IsEngineFixedChild`/`IsEngineOnlyClass` já são
	-- puras e seguras de chamar aqui, ANTES de `Services.Bootstrap` (passo 7, mais abaixo) --
	-- arquiteto-cli-2026-09-05.md, Decisão 17, "Contrato entre territórios (delta)".
	local plan = TreePlanner.Plan(project, {
		IsServiceClass = Services.IsServiceClass,
		IsEngineFixedChild = Services.IsEngineFixedChild,
		IsEngineOnlyClass = Services.IsEngineOnlyClass,
	}, bag)
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

	-- task-cli-026 (contrato coordenado com task-services-026, arquiteto-services-2026-09-05.md,
	-- L2.2.4, último parágrafo: "--verbose passa a imprimir uma linha por requisição de saída
	-- (método + host, nunca corpo)"): `services` chama este callback de volta UMA VEZ por
	-- requisição HTTP de saída, ANTES de efetivamente falar com a rede (`HttpService.behavior`,
	-- território de `coder-services`) -- este módulo só decide SE imprime (`options.Verbose`) e
	-- COMO formata a linha (`Messages.HttpRequestAuditLine`, que nunca recebe corpo/headers --
	-- `method`/`host` são os dois únicos parâmetros do canal, de propósito: a auditoria não pode
	-- vazar o que a regra 00/07 já proíbe expor). Vai para stderr (`stdio.ewrite`), mesmo canal dos
	-- diagnósticos de projeto -- stdout continua reservado só para o que o SCRIPT do usuário
	-- imprimiu (ver `printDiagnostics`, acima).
	local function onHttpRequest(method: string, host: string): ()
		if not options.Verbose then
			return
		end
		stdio.ewrite(Messages.HttpRequestAuditLine(method, host) .. "\n")
	end

	Services.Bootstrap({
		scheduler = scheduler,
		dataModel = game,
		AllowHttp = options.AllowHttp,
		AllowHttpLocal = options.AllowHttpLocal,
		OnHttpRequest = onHttpRequest,
	})

	-- task-cli-025 (item e, arquiteto-valuetypes-2026-09-05.md, seção 3.4 "cli" / Decisão 4 do
	-- desenho de valuetypes): `cli` é o composition root -- o ÚNICO lugar do projeto que ata
	-- `runtime <- valuetypes`, ao lado do `Services.Bootstrap` acima que já ata `runtime <-
	-- services`. Sem isto, `typeof(Vector3.new(1, 2, 3))` dentro do sandbox continuaria devolvendo
	-- o `typeof` nativo do Luau ("userdata"), nunca "Vector3" -- ver `Sandbox.luau`,
	-- `resolveTypeName`, e `TypeNameResolver.luau` (task-runtime-032). Uma vez por processo, sem
	-- reset -- mesmo precedente de `Runtime.UnknownClassResolver.Set` (chamado dentro de
	-- `Services.Bootstrap`).
	Runtime.TypeNameResolver.Set(ValueTypes.TypeNameOf)

	for _, className in Services.GetSimulatedServiceClasses() do
		game:GetService(className)
	end

	local tree = TreeMaterializer.Materialize(plan, game, bag)

	local formatter = OutputFormatter.new(options.UseColor)

	-- Ripple de tipo de task-runtime-030 (`DataModel:GetService` passou de `-> Instance` para
	-- `-> Instance?` -- ver .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão
	-- pós-integração 2026-09-05 (5)", subseção "Consequência de tipo"): o ramo `nil` abaixo é
	-- INALCANÇÁVEL em produção -- o laço logo acima (passo 8: `for _, className in
	-- Services.GetSimulatedServiceClasses() do game:GetService(className) end`) já criou o
	-- singleton de TODA classe coberta por `services`, "Workspace" incluída (leva 1 de cobertura,
	-- ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Prioridade de cobertura"). Se
	-- isto disparar mesmo assim, é uma invariante interna de `services`/`ClassRegistry` quebrada
	-- (ex.: "Workspace" deixou de estar registrada como Service coberta), nunca um erro do
	-- `.project.json` do usuário -- por isso a mensagem é de ENGENHARIA INTERNA em português (mesmo
	-- registro de `DataModel.GetService`/`Services.Context`), NUNCA um `Diagnostic` de projeto
	-- (não há `NodePath` nenhum a citar) nem um `[LuauBench] ... not simulated yet` (não é falta de
	-- cobertura declarada, é bug). NUNCA `::` para apagar o `nil`: o `if` abaixo é o único
	-- estreitamento válido em `--!strict` sem `any`, e é ele que devolve `Runtime.Instance` de
	-- verdade para `ScriptRunner.Options.Workspace` (não-opcional) logo adiante. Sem exit code
	-- novo -- deixa o `error()` propagar cru, como qualquer outra invariante interna quebrada do
	-- motor (ex.: `ClassRegistry.new` com classe não registrada). Nível padrão (1, omitido --
	-- mesmo estilo de `ClassRegistry.luau`, "ciclo de herança detectado..."), não 0: aqui o
	-- `error()` está formando a mensagem pela primeira vez (não re-lançando uma que já carrega
	-- localização, como `ThreadBroker`/`Signal` fazem com `error(err, 0)`), então manter a
	-- localização default aponta exatamente para esta linha de `RunCommand.luau`.
	local workspaceInstance = game:GetService("Workspace")
	if workspaceInstance == nil then
		error("RunCommand: game:GetService(\"Workspace\") devolveu nil -- Workspace deveria estar sempre coberta por services e registrada como Service em ClassRegistry nesta altura do pipeline (depois do laço de GetSimulatedServiceClasses); isto é uma invariante interna quebrada, não um erro de projeto do usuário")
	end

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

	-- task-cli-031 (gap achado pelo arquiteto durante o desenho de persistência, INDEPENDENTE
	-- dela -- ver cabeçalho de `DataModel.luau`, task-runtime-033, linhas 63-87, para a semântica
	-- completa): `game:BindToClose(fn)` só REGISTRA -- é `DataModel.RunBindToCloseCallbacks` quem
	-- de fato DISPARA e ESPERA cada callback registrado, cada um na sua própria thread do
	-- `scheduler`, inclusive quando o callback yielda (`Scheduler:Wait` dentro dele -- o padrão
	-- real do ProfileStore, `while ... do task.wait() end` esperando jobs de save terminarem).
	-- Antes desta tarefa, nenhum chamador existia em `src/cli/**`: o callback era registrado e
	-- JAMAIS disparava, pulando silenciosamente o passo mais importante do ciclo de vida de um
	-- data manager real. Encaixado DEPOIS de `scheduler:Run` (passo 11) e ANTES do sumário final
	-- (passo 12) -- exatamente como o pipeline de doze passos do cabeçalho já reserva: o processo
	-- só é dado como "de fato encerrado" depois que todo callback de fechamento terminou.
	-- No-op garantido (sem custo, sem chamada a `scheduler:Run` de novo por dentro) quando nenhum
	-- script chamou `BindToClose` -- ver `DataModel.RunBindToCloseCallbacks`, "callbacks == nil or
	-- #callbacks == 0" -- então um projeto sem `BindToClose` continua com output/exit code
	-- idênticos ao de antes desta tarefa. Erro dentro de um callback já sai por `ThreadError` do
	-- próprio `scheduler` (mesma proteção de `resumeThread`/`fireProtected` que qualquer outra
	-- thread gerida) -- nunca propaga para cá, nunca derruba o processo, nunca impede os demais
	-- callbacks de rodar (ver DataModel.luau, task-runtime-033).
	--
	-- task-cli-032: conecta ao MESMO `scheduler.ThreadError` que `Sandbox.Run` já escuta pras
	-- threads do script principal, e traduz para o MESMO `formatter` (contagem de erro +
	-- formatação, `Messages.OutputErrorLine`, idêntico a um erro de Script de topo) -- reusa o
	-- mecanismo existente em vez de abrir um segundo caminho de erro paralelo (ver
	-- `parseBindToCloseThreadError`, acima, para o porquê de precisar de um parser próprio aqui).
	-- Conectado só durante esta janela (Connect antes da chamada, Disconnect logo depois): o
	-- listener não precisa sobreviver além dela -- `Execute` já está a três linhas do fim.
	--
	-- LIMITAÇÃO CONHECIDA, documentada (regra 00): diferente de `Sandbox.Run` (que filtra por
	-- `ownThreads`, populado no momento de cada `Spawn`), este listener NÃO filtra por
	-- identidade de thread -- `DataModel.RunBindToCloseCallbacks` devolve `()`, sem expor os
	-- `thread` handles que cria por dentro (API pública de `runtime`, task-runtime-033), então
	-- não há como este módulo saber, de antemão, quais threads são "de BindToClose". Na prática
	-- isto só importa se `--timeout` (passo 11) expirou com uma thread do SCRIPT PRINCIPAL ainda
	-- suspensa (ex.: um `task.wait()` no meio de um script que nunca terminou): o
	-- `scheduler:Run(anyStillAlive)` interno de `RunBindToCloseCallbacks` drena TODAS as threads
	-- vivas do Scheduler (não só as de BindToClose, comportamento já existente desde
	-- task-cli-031) -- se essa thread antiga for retomada e errar NESTA janela específica, o
	-- erro sairia contado duas vezes (uma pelo `Sandbox.Run` original daquele Script, que nunca
	-- desconecta, e uma por este listener). Cenário estreito (timeout + thread ainda suspensa +
	-- erro exatamente nesta janela) fora do escopo desta tarefa para corrigir -- exigiria
	-- `RunBindToCloseCallbacks` devolver os handles que cria, mudança em `runtime`. Reportado
	-- como pendência, não escondido; nenhum dos cenários do acceptance desta tarefa (callback
	-- SEM erro / callback COM erro / múltiplos callbacks) o alcança.
	local bindToCloseErrorConnection: Runtime.Connection = scheduler.ThreadError:Connect(function(_erroredThread: thread, message: string)
		local scriptName, line, cleanMessage = parseBindToCloseThreadError(message)
		local record: Runtime.OutputRecord = {
			level = "error",
			message = cleanMessage,
			scriptName = scriptName,
			line = line,
			timestamp = os.time(),
		}
		formatter:Emit(record)
	end)

	Runtime.DataModel.RunBindToCloseCallbacks(game, scheduler)

	bindToCloseErrorConnection:Disconnect()

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
