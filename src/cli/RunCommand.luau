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
	     E ALSO Services.FlushCloudState() (task-cli-030, ver abaixo)
	 12. imprime sumário (warnings, LocalScripts não executados, erros) e devolve o exit code

	PERSISTÊNCIA LOCAL DO ESTADO "CLOUD" (task-cli-030, par de task-cli-029/task-services-031;
	arquiteto-persistencia-cloud-2026-09-06.md, seções 6, 9 e 10 -- LER antes de mexer nisto):
	entre o passo 6 (scheduler/game recém-criados) e o passo 7 (`Services.Bootstrap`), este módulo
	abre `cloud = if options.NoPersist then nil else CloudStore.Open(directoryOf(plan.ProjectPath),
	onFirstCreate)` e repassa `CloudPersistence = cloud` em `Services.Bootstrap` -- é ali (dentro
	de `services`) que o documento "datastore" é LIDO, antes de qualquer script rodar. Falha de
	LEITURA propaga de `Services.Bootstrap` (por design, ver `services/init.luau`,
	`loadCloudStateIfPresent`) -- este módulo captura via `pcall` e vira erro de projeto (exit 2,
	política de erro (f) do desenho: "nunca recomeça do zero em silêncio").

	FLUSH COALESCIDO POR TIQUE, não síncrono por escrita (seção 6 do desenho, medição que
	justifica): `@lune/fs` não tem append, então toda escrita de `CloudStore.Save` é o arquivo
	INTEIRO -- persistir a cada `SetAsync` tornaria um laço de N escritas O(N²) (medido: ~46s para
	1000 escritas num store de 1000 chaves). Por isso `buildShouldContinue`, abaixo, TAMBÉM chama
	`Services.FlushCloudState()` a cada consulta -- `Scheduler:Run` já consulta `shouldContinue`
	DUAS VEZES POR TIQUE (`src/runtime/Scheduler.luau:449-470`, gancho que JÁ EXISTIA e JÁ É de
	`cli`, nenhuma API nova de `runtime`). Usar um predicado consultado pelo VALOR DE RETORNO
	também como gancho de EFEITO COLATERAL é legítimo aqui (`cli` é o dono dele) -- fica comentado
	explicitamente em `buildShouldContinue` para nunca parecer um acidente. Trade-off DECLARADO: a
	janela de durabilidade é UM TIQUE de scheduler (~16ms) -- um `kill -9` no meio de um tique
	perde as escritas daquele tique.

	FLUSH FORÇADO (síncrono, ignora a coalescência) em DOIS pontos de código -- que cobrem os TRÊS
	"pontos" do desenho, porque o caminho de saída por `--timeout` NUNCA é um código separado desta
	base: `--timeout` só faz `shouldContinue` devolver `false`, o que faz `scheduler:Run` RETORNAR
	normalmente (mesmo `return` de "script terminou sozinho") -- não existe um segundo caminho de
	saída para instrumentar:
	  (1) imediatamente depois de `scheduler:Run(...)` retornar (cobre TANTO o script terminando
	      sozinho QUANTO o `--timeout` expirando -- é o MESMO ponto de retorno nos dois casos);
	  (2) imediatamente depois de `Runtime.DataModel.RunBindToCloseCallbacks(...)` (a gravação
	      final de um `ProfileStore` dentro de `BindToClose`, se houver, precisa estar no disco
	      antes do sumário -- task-cli-031 já garante que o callback TERMINOU antes desta linha).

	POLÍTICA DE ERRO DE I/O (f): falha de LEITURA é erro de projeto (exit 2, arquivo nunca
	sobrescrito -- ver acima). Falha de ESCRITA é UM warning por EXECUÇÃO INTEIRA (nunca um por
	tique, mesmo que `Services.FlushCloudState()` seja chamada dezenas de vezes por segundo) e o
	script CONTINUA rodando com o estado em memória -- ver `makeFlushCloudState`, abaixo, para a
	guarda que garante isso.

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
	`OutputFormatter.luau`, `ModuleLoader.luau`, `Diagnostics.luau`, `Messages.luau`, `CloudStore.luau`
	(task-cli-030), `../runtime`, `../services`, `../valuetypes` (task-cli-025, item e -- só
	`Runtime.TypeNameResolver.Set(ValueTypes.TypeNameOf)`). NUNCA `../services/generated/**`/
	`behavior/**` (regra 03) nem um módulo interno de `runtime`/`valuetypes` por fora dos
	respectivos agregadores públicos (regra 02/regra 06).

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
local CloudStore = require("./CloudStore")
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
	-- task-cli-030 (arquiteto-persistencia-cloud-2026-09-06.md, "0. Resumo executivo", item 4):
	-- espelha `Args.Command.NoPersist` 1:1, default `false` -- persistência local do estado
	-- "cloud" (DataStoreService) LIGADA por padrão, comportamento natural. `true` desliga por
	-- completo: nem lê nem escreve `.luaubench/` (ver `RunCommand.Execute`, "cloud = if
	-- options.NoPersist then nil else CloudStore.Open(...)").
	NoPersist: boolean,
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

-- Deriva o diretório que contém `filePath` -- mesma operação que `ProjectFile.splitPath` já faz
-- para achar `Project.FolderPath`, deliberadamente NÃO compartilhada por `require` (mesma
-- disciplina já registrada em `ProjectFile.luau`/`CloudStore.luau`: cada módulo mantém sua própria
-- cópia local de dez linhas em vez de introduzir um acoplamento novo só para isto). Aceita "/" e
-- "\" como separador (Windows/Unix). `filePath` aqui é sempre `plan.ProjectPath` -- o `.project.
-- json` de TOPO resolvido por `ProjectFile.Locate` (nunca de um projeto aninhado -- `TreePlanner.
-- Plan` só grava `ProjectPath` uma vez, na raiz da recursão, ver `TreePlanner.luau` fim da função
-- `resolveCore` -- `ProjectPath = project.FilePath`), então o resultado ancora `CloudStore.Open`
-- exatamente onde a seção 3 do desenho de persistência exige.
local function directoryOf(filePath: string): string
	for index = #filePath, 1, -1 do
		local char = string.sub(filePath, index, index)
		if char == "/" or char == "\\" then
			return string.sub(filePath, 1, index - 1)
		end
	end
	return "."
end

-- Caminho do documento "datastore" -- reconstituído AQUI só para citá-lo em mensagens de erro
-- claras (política de erro (f) do desenho de persistência); NUNCA usado para tocar o disco por
-- conta própria -- só `CloudStore.luau` faz I/O (ver o cabeçalho daquele módulo, "ponto ÚNICO de
-- @lune/fs"). Layout fixo documentado em arquiteto-persistencia-cloud-2026-09-06.md, seção 3.
local function cloudDatastorePath(projectFolder: string): string
	return `{projectFolder}/.luaubench/cloud/datastore.json`
end

-- Corta a stack trace multi-linha que um erro nativo do Lune/Rust produz -- mesma disciplina já
-- usada em `CloudStore.luau`/`Snapshot.luau`/`ProjectFile.luau` para o mesmo tipo de erro (regra
-- 04: nunca stack trace cru). Usado só pelos dois pontos novos desta tarefa que cruzam a fronteira
-- de `pcall` contra `services`/`CloudStore` (falha de leitura do bootstrap, abaixo).
--
-- CORREÇÃO (achado ALTO de revisão de task-cli-030): esta função SÓ cortava a primeira quebra de
-- linha -- nunca removia o prefixo `<caminho absoluto>:<linha>: ` que `error(msg, <nível>)` do
-- Luau antepõe (`CloudStore.load`/`CloudStore.save` levantam com nível padrão 1, apontando pra
-- dentro de `CloudStore.luau`; `Snapshot.DecodeDocument` levanta com `error(msg, 2)`, apontando
-- pro CALL SITE dentro de `services/init.luau`, `loadCloudStateIfPresent`) -- vazando o caminho de
-- instalação do LuauBench em disco (ex.: `D:\...\src\services:335:`, `D:\...\CloudStore:227:`) nas
-- mensagens `[cloud/state-unreadable]`/`[cloud/save-failed]`, exatamente a categoria de vazamento
-- que `TreeMaterializer.stripEngineErrorLocation` já resolve para `applyProperties`/
-- `createInstance` (task-cli-010/011). Reproduzido ao vivo com um documento "cloud" corrompido
-- (`{ this is not valid json`) forçando `Snapshot.DecodeDocument` a errar, e com uma obstrução de
-- `.luaubench/` (arquivo no lugar do diretório) forçando `CloudStore.Save` a errar -- as duas
-- mensagens finais citavam o caminho absoluto de instalação antes desta correção.
--
-- Corrigido reusando a MESMA função já exportada por `TreeMaterializer` (`require`ido logo acima
-- só para os tipos `PlanNode`/`InstancePlan` até agora) em vez de escrever uma segunda
-- implementação (regra 01: duas cópias da mesma lógica é exatamente a divergência silenciosa que
-- a regra 00 proíbe) -- `firstLineOf` (renomeado só nos comentários, mantido como nome local por
-- não introduzir um alias extra) agora chama `TreeMaterializer.StripEngineErrorLocation` por
-- dentro, o que cobre AMBOS os cortes (quebra de linha E prefixo de localização) numa função só.
local function firstLineOf(err: unknown): string
	return TreeMaterializer.StripEngineErrorLocation(tostring(err))
end

-- task-cli-030 (arquiteto-persistencia-cloud-2026-09-06.md, seção 6, "Política de erro de I/O"):
-- fábrica do "gancho de flush" usado TANTO pelo `shouldContinue` (fronteira de tique, via
-- `buildShouldContinue` abaixo) QUANTO pelos dois flushes FORÇADOS de `RunCommand.Execute`
-- (depois de `scheduler:Run`, depois de `RunBindToCloseCallbacks`) -- a MESMA closure é
-- compartilhada entre os três usos de propósito: a garantia de erro é "UM warning por EXECUÇÃO
-- INTEIRA", nunca "um warning por chamador"/"um por tique", e só uma guarda `hasWarned`
-- compartilhada consegue essa garantia sem coordenação extra entre os três pontos de chamada.
--
-- `(true, nil)` (gravou) e `(false, nil)` (nada sujo -- `Services.FlushCloudState` nem chega a
-- serializar, ver o cabeçalho daquela função em `services/init.luau`) são os DOIS caminhos felizes
-- -- NUNCA viram warning. Só `(false, err ~= nil)` é falha de escrita de verdade.
-- CORREÇÃO (achado ALTO de revisão de task-cli-030, mesma raiz do `firstLineOf` acima):
-- `Services.FlushCloudState()` (`src/services/init.luau`) já aplica o SEU PRÓPRIO `firstLineOf`
-- interno antes de devolver `err` -- mas aquela cópia (fora do território desta correção pontual,
-- `src/services/**`, reportado e não corrigido aqui) tem a MESMA falha: só corta a primeira quebra
-- de linha, nunca o prefixo `<caminho absoluto>:<linha>: ` que `error()` antepõe (`CloudStore.save`
-- levanta com nível padrão 1, apontando pra dentro de `CloudStore.luau`) -- então `err`, aqui,
-- ainda pode carregar esse prefixo. `firstLineOf` (definido acima, já reusando
-- `TreeMaterializer.StripEngineErrorLocation`) é aplicado de novo AQUI, na fronteira final antes de
-- formatar `Messages.CloudStateSaveFailed` -- defesa em profundidade no lado de `cli` (o único lado
-- que esta tarefa pode corrigir) para que o usuário NUNCA veja o caminho de instalação, mesmo
-- enquanto o vazamento equivalente em `services/init.luau` não for corrigido.
local function makeFlushCloudState(bag: Diagnostics.Bag, cloudPath: string): () -> ()
	local hasWarned = false

	return function()
		local ok, err = Services.FlushCloudState()
		if ok or err == nil then
			return
		end
		if hasWarned then
			return
		end
		hasWarned = true
		bag:Add({
			Severity = "warning",
			Code = "cloud/save-failed",
			Message = Messages.CloudStateSaveFailed(cloudPath, firstLineOf(err)),
			FilePath = cloudPath,
		})
	end
end

-- `shouldContinue` de `--timeout` (ver cabeçalho, "Riscos e decisões") E do gancho de flush
-- coalescido por tique (task-cli-030, ver cabeçalho do arquivo, "PERSISTÊNCIA LOCAL DO ESTADO
-- 'CLOUD'"). `Scheduler:Run` consulta este predicado PELO VALOR DE RETORNO, duas vezes por tique
-- (`src/runtime/Scheduler.luau:449-470`) -- usá-lo TAMBÉM como gancho de EFEITO COLATERAL
-- (chamar `flushCloudState` a cada consulta) é LEGÍTIMO aqui, porque `cli` é o dono deste
-- predicado (`RunCommand.buildShouldContinue` é quem o constrói) -- mas fica este comentário aqui
-- de propósito, para nunca parecer um acidente de quem lê o código depois (arquiteto-persistencia-
-- cloud-2026-09-06.md, seção 10: "usá-lo também como gancho de efeito colateral é legítimo aqui...
-- mas precisa estar comentado no código, senão parece acidente").
--
-- `timeoutSeconds == nil` E `flushCloudState == nil` devolve `nil` -- preserva EXATAMENTE o
-- comportamento de antes desta tarefa (`Scheduler:Run(nil)` roda até `IsAlive()` virar `false` por
-- conta própria, sem NUNCA consultar este predicado -- nem para o efeito colateral). Qualquer um
-- dos dois presentes força um predicado real: o flush coalescido por tique precisa rodar em TODA
-- execução com persistência ligada, mesmo sem `--timeout` (é o caso comum -- a maioria das
-- execuções de `luaubench run` não passa `--timeout`).
local function buildShouldContinue(timeoutSeconds: number?, flushCloudState: (() -> ())?): (() -> boolean)?
	if timeoutSeconds == nil and flushCloudState == nil then
		return nil
	end

	local deadline: number? = if timeoutSeconds ~= nil then os.clock() + timeoutSeconds else nil

	return function(): boolean
		if flushCloudState ~= nil then
			flushCloudState()
		end
		if deadline == nil then
			return true
		end
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

	-- task-cli-030 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10, "Quem chama primeiro"):
	-- ANTES do passo 7 (`Services.Bootstrap`, logo abaixo) -- é ele quem LÊ o documento "datastore"
	-- ali dentro, antes de qualquer script rodar. `options.NoPersist` (`--no-persist`) devolve
	-- `nil` sem sequer chamar `CloudStore.Open` -- uma execução com persistência desligada nunca
	-- cria `.luaubench/`, nunca abre um `Store`, nunca passa perto do caminho de flush (ver
	-- `buildShouldContinue`/os dois flushes forçados, abaixo -- todos gated em `cloud ~= nil`).
	-- `directoryOf(plan.ProjectPath)` ancora no `.project.json` de TOPO resolvido por
	-- `ProjectFile.Locate` (ver comentário de `directoryOf`), NUNCA em `options.Cwd`/`process.cwd`
	-- -- mesma garantia que `CloudStore.luau` já documenta para `projectRoot`.
	local projectFolder = directoryOf(plan.ProjectPath)
	local cloudDocumentPath = cloudDatastorePath(projectFolder)
	local cloud: CloudStore.Store? = nil
	if not options.NoPersist then
		cloud = CloudStore.Open(projectFolder, function(path: string)
			-- Seção 9 do desenho: linha informativa, no stderr, UMA vez -- só quando
			-- `CloudStore` de fato criou ".luaubench/" agora (nunca numa execução onde o
			-- diretório já sobreviveu de uma execução anterior -- ver `CloudStore.Open`,
			-- garantia de `onFirstCreate`).
			stdio.ewrite(Messages.CloudStateDirectoryCreated(path) .. "\n")
		end)
	end

	local function bootstrapServices(): ()
		Services.Bootstrap({
			scheduler = scheduler,
			dataModel = game,
			AllowHttp = options.AllowHttp,
			AllowHttpLocal = options.AllowHttpLocal,
			OnHttpRequest = onHttpRequest,
			CloudPersistence = cloud,
		})
	end

	if cloud == nil then
		-- Sem persistência (--no-persist, ou nenhum port injetado): `services/init.luau`,
		-- `loadCloudStateIfPresent` devolve cedo (`Context.GetCloudPersistence() == nil`) e NUNCA
		-- lança por causa de estado "cloud" -- chama direto, SEM `pcall`, pra nunca mascarar uma
		-- invariante interna quebrada de verdade (ex.: bug em `Services.Register()`) atrás da
		-- mensagem `Messages.CloudStateUnreadable`, que não faria sentido nenhum aqui.
		bootstrapServices()
	else
		-- `cloud ~= nil`: `Services.Bootstrap` propaga sem `pcall` (por design, `services/init.luau`,
		-- `loadCloudStateIfPresent`) quando o documento "datastore" existe mas está
		-- ilegível/corrompido/com `SchemaVersion` futuro -- política de erro (f): erro de projeto
		-- claro apontando o arquivo, exit 2, ANTES de qualquer script rodar (nem `CloudStore.Load`
		-- nem `Snapshot.DecodeDocument` tocam o disco para escrita, então o arquivo nunca é
		-- sobrescrito por esta falha). `Register()`/`Context.Set()` (o resto do trabalho de
		-- `Bootstrap`) são invariantes de config-time que não falham a partir de entrada do
		-- usuário -- na prática, alcançar este `pcall` só acontece por causa do documento ilegível.
		local bootstrapOk, bootstrapErr = pcall(bootstrapServices)
		if not bootstrapOk then
			bag:Add({
				Severity = "error",
				Code = "cloud/state-unreadable",
				Message = Messages.CloudStateUnreadable(cloudDocumentPath, firstLineOf(bootstrapErr)),
				FilePath = cloudDocumentPath,
			})
			printDiagnostics(bag, options.UseColor, options.Verbose)
			return {
				ExitCode = EXIT_PROJECT_ERROR,
				ErrorCount = bag:CountOf("error"),
				WarningCount = bag:CountOf("warning"),
			}
		end
	end

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

	-- task-cli-030: `flushCloudState == nil` quando `cloud == nil` (--no-persist, ou nenhum
	-- diretório de persistência resolvido) -- `buildShouldContinue(options.Timeout, nil)` então
	-- preserva EXATAMENTE o comportamento de antes desta tarefa quando `options.Timeout` também é
	-- `nil` (`Scheduler:Run(nil)`, ver comentário de `buildShouldContinue`). Só existe quando
	-- `cloud ~= nil`, e a MESMA closure é reusada pelos dois flushes forçados abaixo (ver
	-- `makeFlushCloudState`, "a MESMA closure é compartilhada entre os três usos de propósito").
	local flushCloudState: (() -> ())? = if cloud ~= nil then makeFlushCloudState(bag, cloudDocumentPath) else nil

	scheduler:Run(buildShouldContinue(options.Timeout, flushCloudState))

	-- task-cli-030, FLUSH FORÇADO (1/2) -- ver cabeçalho do arquivo, "FLUSH FORÇADO": cobre TANTO
	-- o script terminando sozinho (`IsAlive() == false`) QUANTO `--timeout` expirando -- os dois
	-- fazem `scheduler:Run` retornar exatamente por AQUI, não existe um segundo caminho de saída
	-- para instrumentar separadamente. `flushCloudState == nil` (persistência desligada) é um
	-- no-op silencioso (nunca chama `Services.FlushCloudState`).
	if flushCloudState ~= nil then
		flushCloudState()
	end

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
	-- task-cli-035 (segunda metade do fix de task-cli-033/task-runtime-038 -- ver
	-- .claude/agents-memory/revisor-cli-task-cli-032-2026-09-06.md, "Verificação 5", para o achado
	-- original de contagem dupla, e o cabeçalho de `DataModel.luau`, task-runtime-038, para a causa
	-- raiz e o desenho do fix do lado `runtime`): a versão anterior desta tarefa (task-cli-032)
	-- conectava um listener PEGA-TUDO em `scheduler.ThreadError` ao redor da chamada -- sem filtrar
	-- por identidade de thread, um `error()` de uma thread ALHEIA (ex.: o script principal, ainda
	-- suspenso além de um `--timeout` expirado) retomada pelo laço genérico interno de
	-- `RunBindToCloseCallbacks` (que drena TODAS as threads vivas do Scheduler, não só as de
	-- BindToClose) batia TANTO no listener antigo de `Sandbox.Run` (que nunca desconecta, filtra
	-- por `ownThreads` daquele Script) QUANTO neste, contando 2x um erro só.
	--
	-- FIX: `DataModel.RunBindToCloseCallbacks` agora aceita `onCallbackError` (3º parâmetro
	-- opcional) e filtra ELA MESMA por identidade das threads que ela própria cria para os
	-- callbacks registrados (`ownThreads`, dentro de `runtime` -- ver cabeçalho de `DataModel.
	-- luau`) -- nunca repassa erro de thread alheia. Este módulo só PASSA o callback adiante, sem
	-- conectar/desconectar `scheduler.ThreadError` por conta própria -- a mesma lógica de tradução
	-- pra `OutputRecord`/`OutputFormatter` (`parseBindToCloseThreadError`, acima) é reusada sem
	-- mudança nenhuma, só COMO ela é conectada mudou.
	local function onBindToCloseCallbackError(_erroredThread: thread, message: string): ()
		local scriptName, line, cleanMessage = parseBindToCloseThreadError(message)
		local record: Runtime.OutputRecord = {
			level = "error",
			message = cleanMessage,
			scriptName = scriptName,
			line = line,
			timestamp = os.time(),
		}
		formatter:Emit(record)
	end

	Runtime.DataModel.RunBindToCloseCallbacks(game, scheduler, onBindToCloseCallbackError)

	-- task-cli-030, FLUSH FORÇADO (2/2) -- ver cabeçalho do arquivo, "FLUSH FORÇADO": a gravação
	-- final de um `ProfileStore`/data manager real costuma acontecer dentro de `BindToClose` (é
	-- exatamente o cenário que motivou `RunBindToCloseCallbacks` existir, task-cli-031) -- esta
	-- chamada garante que essa última escrita chega ao disco ANTES do sumário final, mesmo que o
	-- tique em que `BindToClose` rodou nunca tivesse chegado a consultar `shouldContinue` de novo.
	if flushCloudState ~= nil then
		flushCloudState()
	end

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
