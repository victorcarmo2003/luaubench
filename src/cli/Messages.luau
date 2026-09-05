--!strict

--[[
	TODAS as strings voltadas ao usuário do território `cli` vivem neste arquivo -- nenhum outro
	módulo de `src/cli/` constrói uma mensagem literal por conta própria (regra 04 + desenho
	.claude/agents-memory/arquiteto-cli-2026-09-05.md, "Decisão 13"). Módulo folha: não requer
	nenhum outro módulo de `cli` (evita ciclo -- `Diagnostics.luau`/`Args.luau` dependem DESTE
	arquivo, nunca o contrário).

	IDIOMA (Decisão 13 do desenho, "Decisão que precisa do usuário" -- AINDA NÃO CONFIRMADA pelo
	usuário nesta tarefa): estas strings estão em INGLÊS, pela recomendação do arquiteto --
	LuauBench é publicado no Rokit para o ecossistema Roblox, cuja saída de motor (mensagens da
	família Roblox, prefixo `[LuauBench]` de `services`) já é inglês; misturar um erro de projeto
	em pt-BR com um erro de motor em inglês na mesma tela seria pior que qualquer das duas opções
	sozinha. Isolar tudo aqui é o que torna essa decisão reversível a custo de um arquivo só, caso
	o usuário prefira pt-BR -- NÃO é uma decisão fechada, é a recomendação registrada.

	Sem lógica de ramificação além de formatação simples (montar uma linha a partir de parâmetros)
	-- qualquer decisão sobre O QUE mostrar (qual severidade, qual código, se usa cor) é de quem
	chama (`Diagnostics.luau`, `Args.luau`, `init.luau`).
]]

local Messages = {}

-- Reexportado por Diagnostics.luau (`export type Severity = Messages.Severity`) -- Messages é a
-- fonte única do vocabulário de severidade (regra: nenhuma string de usuário fora daqui), então
-- é este arquivo que define o tipo, nunca o contrário (evitaria o ciclo Diagnostics<->Messages).
export type Severity = "error" | "warning" | "info"

-- Reexportado por Diagnostics.luau pelo mesmo motivo do `Severity` acima -- os quatro rótulos de
-- localização ("node"/"field"/"file"/"project") são prosa em inglês que aparece palavra por
-- palavra na linha final (`Messages.LocationSegment`), então precisam da mesma fonte única que
-- qualquer outra string de usuário (achado ALTO da revisão de task-cli-001: esses rótulos viviam
-- soltos em `Diagnostics.luau`, quebrando a promessa de "trocar o idioma custa um arquivo só").
export type LocationKind = "node" | "field" | "file" | "project"

--------------------------------------------------------------------------------------------------
-- Ajuda / versão
--------------------------------------------------------------------------------------------------

function Messages.HelpText(): string
	return table.concat({
		"luaubench -- runs a Roblox (Rojo) project outside Roblox Studio.",
		"",
		"USAGE:",
		"    luaubench [run] [path] [flags]",
		"    luaubench version",
		"    luaubench help",
		"",
		"ARGUMENTS:",
		"    [path]                Path to a Rojo project file or folder (defaults to the current directory).",
		"",
		"FLAGS:",
		"    --timeout <seconds>   Stop the run loop after this many seconds of wall-clock time.",
		"    --no-color            Disable ANSI colors in the output.",
		"    --verbose             Show extra diagnostics (e.g. info-level messages).",
		"    --watch               Recognized, but not supported yet -- see the error message for why.",
		"    --help                Show this help text.",
		"    --version             Show the LuauBench version and the Roblox API Dump version it targets.",
	}, "\n")
end

function Messages.VersionLine(cliVersion: string, dumpVersion: string, dumpCommit: string): string
	return `luaubench {cliVersion}\nRoblox API Dump: {dumpVersion} (commit {dumpCommit})`
end

--------------------------------------------------------------------------------------------------
-- Erros de uso (Args.Parse)
--------------------------------------------------------------------------------------------------

function Messages.UnknownFlag(flag: string): string
	return `Unknown flag "{flag}". Run "luaubench --help" to see the available flags.`
end

function Messages.MissingFlagValue(flag: string): string
	return `Missing value for flag "{flag}".`
end

function Messages.InvalidFlagValue(flag: string, value: string): string
	return `Invalid value for flag "{flag}": "{value}" is not a number.`
end

function Messages.UnexpectedArgument(value: string): string
	return `Unexpected argument "{value}". "luaubench run" accepts at most one project path.`
end

-- Decisão 9 do desenho: `--watch` é RECONHECIDO e devolve o motivo técnico real, nunca "flag
-- desconhecida" -- Lune 0.10.5 (fixado em rokit.toml) não expõe observador de filesystem, e
-- regra 04 proíbe polling como substituto.
function Messages.WatchNotSupported(): string
	return "--watch is not supported yet: Lune 0.10.5 (the version pinned in rokit.toml) does not "
		.. "expose a filesystem watcher, and LuauBench does not do polling instead (see "
		.. ".claude/rules/04-cli-rokit.md)."
end

-- task-cli-001 é só o esqueleto do território (main/init/Args/Messages/Diagnostics) -- o
-- pipeline real de `luaubench run` (ProjectFile/TreePlanner/TreeMaterializer/ScriptRunner) é
-- construído nas tarefas seguintes (task-cli-002 em diante). Cli.Main já reconhece o comando
-- "run" e devolve ESTA mensagem em vez de fingir sucesso (regra 00: nunca "tudo concluído"
-- silencioso) -- some assim que RunCommand.luau existir (task-cli-006).
function Messages.RunPipelineNotImplementedYet(): string
	return '"luaubench run" is not wired up yet in this build: the project-loading pipeline '
		.. "(.project.json parsing, tree materialization, script execution) has not landed yet. "
		.. "This is expected during incremental development of LuauBench."
end

--------------------------------------------------------------------------------------------------
-- Diagnósticos de projeto (Diagnostics.Render)
--------------------------------------------------------------------------------------------------

function Messages.SeverityLabel(severity: Severity): string
	if severity == "error" then
		return "error"
	elseif severity == "warning" then
		return "warning"
	end
	return "info"
end

-- Rótulo de cada tipo de localização que `Diagnostics.buildLocationSuffix` pode montar, na ordem
-- do mais específico (nó/campo dentro da árvore) para o mais geral (arquivo/projeto de origem).
-- Ramificação explícita (não tabela indexada por união de literais) pelo mesmo motivo de
-- `colorForSeverity`/`SeverityLabel`: evita o achado de tooling do luau-lsp 1.69.0 documentado em
-- `Diagnostics.luau` (indexação por união de literais widening para `string`).
function Messages.LocationLabel(kind: LocationKind): string
	if kind == "node" then
		return "node"
	elseif kind == "field" then
		return "field"
	elseif kind == "file" then
		return "file"
	end
	return "project"
end

-- Um segmento de localização dentro dos parênteses de uma linha de diagnóstico, ex.:
-- Messages.LocationSegment(Messages.LocationLabel("node"), "tree.ReplicatedStorage") ->
-- "node: tree.ReplicatedStorage".
function Messages.LocationSegment(label: string, value: string): string
	return `{label}: {value}`
end

-- Monta a linha final de UM diagnóstico, sem cor (`Diagnostics.Render` decide se envolve o
-- resultado em ANSI). `locationSuffix` já vem pronto (com o " (...)" incluído, ou "" se nenhum
-- campo de localização estava presente) -- ver `Diagnostics.luau`.
function Messages.DiagnosticLine(severityLabel: string, code: string, message: string, locationSuffix: string): string
	return `{severityLabel}: [{code}] {message}{locationSuffix}`
end

--------------------------------------------------------------------------------------------------
-- JSON (JsonValue.luau) -- task-cli-002
--------------------------------------------------------------------------------------------------

-- `parserError` já vem LIMPO de stack traceback (JsonValue.Decode corta na primeira quebra de
-- linha antes de chamar isto -- regra 04: nunca stack trace cru do parser) -- este wrapper só
-- garante que a mensagem final sempre cita o arquivo de origem.
function Messages.MalformedJson(sourcePath: string, parserError: string): string
	return `Failed to parse "{sourcePath}" as JSON: {parserError}`
end

-- Formato único para as cinco funções As*/AsArray de `JsonValue`. `expectedKind`/`actualKind`
-- são um dos seis rótulos que `JsonValue.luau` decide via `typeof` ("null"/"boolean"/"number"/
-- "string"/"array"/"object") -- a decisão de QUAL rótulo mora lá, nunca aqui.
function Messages.JsonTypeMismatch(path: string, expectedKind: string, actualKind: string): string
	return `Expected {expectedKind} at "{path}", found {actualKind}.`
end

--------------------------------------------------------------------------------------------------
-- Projeto Rojo (.project.json) -- ProjectFile.luau, task-cli-002
--------------------------------------------------------------------------------------------------

function Messages.ProjectPathNotFound(path: string): string
	return `The path "{path}" does not exist.`
end

function Messages.ProjectFileNotFound(searchedDirectory: string): string
	return `Could not find a Rojo project file ("default.project.json" or "default.project.jsonc") in "{searchedDirectory}".`
end

function Messages.ProjectFileNotReadable(filePath: string, ioError: string): string
	return `Could not read the project file "{filePath}": {ioError}`
end

function Messages.ProjectInvalidRoot(): string
	return "The root of a Rojo project file must be a JSON object."
end

-- Decisão 14 do desenho: espelha o `deny_unknown_fields` do Rojo no nível raiz -- a mensagem
-- nomeia a chave inválida E lista as chaves válidas (é o que garante, na prática, que "tre" em
-- vez de "tree" não passe silenciosamente como projeto vazio).
function Messages.ProjectUnknownField(fieldName: string, validFields: { string }): string
	return `Unknown field "{fieldName}" at the project root. Expected one of: {table.concat(validFields, ", ")}.`
end

function Messages.ProjectMissingField(fieldName: string): string
	return `The project is missing the required field "{fieldName}".`
end

function Messages.ProjectEmitLegacyScriptsFalse(): string
	return '"emitLegacyScripts": false is not modeled by LuauBench (it does not simulate RunContext yet) -- '
		.. "the .server.lua/.client.lua -> Script/LocalScript mapping will not change, and behavior may diverge."
end

function Messages.ProjectGlobIgnorePathsUnsupported(globs: { string }): string
	return `"globIgnorePaths" is not applied yet -- LuauBench will still load files matching: {table.concat(globs, ", ")}.`
end

function Messages.ProjectSyncRulesUnsupported(count: number): string
	return `"syncRules" ({count} rule(s)) is not applied yet -- LuauBench uses its built-in file-to-class conventions only.`
end

function Messages.ProjectNodeIdUnsupported(): string
	return '"$id" is not supported yet (Ref/attribute-reference semantics depend on value types, a future wave).'
end

function Messages.ProjectUnknownDollarKey(key: string): string
	return `Unrecognized reserved key "{key}" (keys starting with "$" are reserved by Rojo) -- ignored.`
end

function Messages.ProjectInvalidPathValue(): string
	return '"$path" must be a string, or an object of the form { "optional": "<path>" }.'
end

--------------------------------------------------------------------------------------------------
-- SyncRules / TreePlanner (arquivo/pasta -> ClassName, resolução de $path e projetos aninhados)
-- -- task-cli-003
--------------------------------------------------------------------------------------------------

-- Decisão 6: TODO arquivo classificado como "Unsupported" (reconhecido pela tabela do Rojo, fora
-- da leva 1) vira warning citando o caminho REAL -- nunca omissão silenciosa (regra 03).
function Messages.SyncUnsupportedExtension(absolutePath: string): string
	return `"{absolutePath}" has a file extension that LuauBench recognizes but does not simulate yet -- it was skipped.`
end

function Messages.PlanRequiredPathNotFound(nodePath: string, absolutePath: string): string
	return `"$path" for "{nodePath}" points to "{absolutePath}", which does not exist on disk.`
end

-- Severidade "info" (Decisão 8) -- $path opcional ausente omite o nó em silêncio, sem ser erro.
function Messages.PlanOptionalPathOmitted(nodePath: string, absolutePath: string): string
	return `"{nodePath}" was omitted: its optional "$path" ("{absolutePath}") does not exist on disk, and no other source of ClassName (explicit "$className", or Service inference) was available.`
end

-- Família de mensagem do Rojo real (pesquisa-formato-projeto-rojo-2026-09-05.md, seção 4) --
-- reproduzida com fidelidade de UX (aproximação de boa-fé, string não confirmada byte-a-byte,
-- mesmo protocolo já usado em services pra mensagens de `require`).
function Messages.PlanMissingClassName(nodePath: string): string
	return `Instance "{nodePath}" is missing some required information. One of the following must be true: `
		.. '- "$className" must be set, '
		.. '- "$path" must be set to an existing file or folder, or '
		.. "- the instance must be a known service, like ReplicatedStorage."
end

function Messages.PlanClassNameConflict(nodePath: string): string
	return `"{nodePath}" has both "$className" and a "$path" that resolves to something other than a Folder -- only a Folder path may be combined with an explicit "$className".`
end

function Messages.PlanServiceNameMismatch(nodePath: string, name: string, className: string): string
	return `"{nodePath}" resolves to the service class "{className}", but is named "{name}" -- LuauBench requires a service directly under the DataModel to be named exactly like its class (DataModel:GetService owns the singleton's name).`
end

function Messages.PlanNonPrimitiveProperty(nodePath: string, propertyName: string, foundKind: string): string
	return `"$properties.{propertyName}" at "{nodePath}" is a {foundKind}, not a boolean/number/string -- LuauBench does not have value types yet (planned: value-types wave), so it was skipped.`
end

function Messages.PlanAttributesUnsupported(nodePath: string, attributeNames: { string }): string
	return `"$attributes" at "{nodePath}" is not applied yet (Instance:SetAttribute is not simulated) -- ignored: {table.concat(attributeNames, ", ")}.`
end

function Messages.PlanNestedProjectCycle(chain: { string }): string
	return `Cyclic nested project detected: {table.concat(chain, " -> ")}.`
end

function Messages.PlanNestedProjectChildrenIgnored(nodePath: string): string
	return `"{nodePath}" has both a "$path" that resolves to a nested project and its own named children in the project file -- only the nested project's own tree is used; the named children were ignored.`
end

-- Mesmo padrão de `PlanNestedProjectChildrenIgnored`, acima, pra outra informação do usuário
-- descartada pelo mesmo ramo de projeto aninhado (achado MÉDIO, revisor-cli-treeplanner-2026-09-
-- 05.md): um "$className" explícito não sobrevive quando o "$path" do mesmo nó resolve pra um
-- projeto aninhado -- a classe final vem SEMPRE da raiz do projeto aninhado.
function Messages.PlanNestedProjectClassNameIgnored(nodePath: string, ignoredClassName: string): string
	return `"{nodePath}" has both an explicit "$className" ("{ignoredClassName}") and a "$path" that resolves to a nested project -- only the nested project's own root class is used; the explicit "$className" was ignored.`
end

function Messages.PlanMetaClassNameConflict(nodePath: string, actualKind: string): string
	return `"init.meta.json" for "{nodePath}" sets "className", but the directory already resolved to {actualKind} (via an init.* file) -- "className" may only override a plain Folder.`
end

function Messages.PlanMetaFieldUnsupported(nodePath: string, fieldName: string): string
	return `"{fieldName}" in a meta file for "{nodePath}" is not supported yet -- ignored.`
end

function Messages.PlanIoError(nodePath: string, path: string, ioError: string): string
	return `Could not read "{path}" (for "{nodePath}"): {ioError}`
end

--------------------------------------------------------------------------------------------------
-- TreeMaterializer (InstancePlan -> DataModel real) -- task-cli-004, arquiteto-cli-2026-09-05.md,
-- Decisões 4, 5 e 7.
--------------------------------------------------------------------------------------------------

-- Decisão 14 do desenho: "luaubench run" executa place projects; um projeto cuja raiz resolve
-- para outra classe (ex.: "Model", "Package") não tem `game`. Mensagem própria, não o erro
-- genérico de classe -- é um caso comum (projeto de biblioteca/pacote) e merece explicação.
function Messages.MaterializeRootNotDataModel(rootClassName: string): string
	return `The project's root resolves to "{rootClassName}", not "DataModel" -- "luaubench run" executes place projects, and a project whose root is a model or package has no "game".`
end

-- Defesa em profundidade (Decisão 4): o Rojo real permite um Service raiz com Name diferente da
-- classe; o LuauBench não, porque DataModel:GetService é dono da nomeação do singleton.
-- TreePlanner (plan/service-name-mismatch) já barra isto no caminho normal -- este diagnóstico
-- só é alcançável se alguém montar um InstancePlan à mão (fora de TreePlanner.Plan) com um nó
-- IsServiceRoot cujo Name diverge do ClassName, ex.: teste unitário de TreeMaterializer sozinho.
function Messages.MaterializeServiceNameMismatch(nodePath: string, name: string, className: string): string
	return `"{nodePath}" is marked as the service "{className}", but is named "{name}" -- LuauBench requires a service directly under the DataModel to be named exactly like its class (DataModel:GetService owns the singleton's name).`
end

-- Mesma disciplina de defesa em profundidade acima: só alcançável por um InstancePlan montado à
-- mão com IsServiceRoot = true numa classe que o Roblox API Dump não marca como Service --
-- TreePlanner só marca IsServiceRoot depois de confirmar Services.IsServiceClass.
function Messages.MaterializeNotAService(nodePath: string, className: string): string
	return `"{nodePath}" is marked as a service root, but "{className}" is not tagged as a Service in the Roblox API Dump -- this is a LuauBench-internal inconsistency, not a project error.`
end

-- Uma classe Service real (tag "Service" do dump, ex.: "Teams", "Chat") que este BUILD do
-- LuauBench ainda não simula (fora da leva de cobertura atual de `services`) -- família
-- "[LuauBench] ... not simulated yet" (mesma família de Services.new, regra de idioma:
-- SEM contraparte real, é o LuauBench que está incompleto, nunca o Roblox).
function Messages.MaterializeServiceNotSimulated(nodePath: string, className: string, dumpVersion: string): string
	return `[LuauBench] "{nodePath}" resolves to the service "{className}", which exists in the Roblox API Dump ({dumpVersion}) but is not simulated by LuauBench yet.`
end

-- `Services.new` já erra com uma mensagem de boa qualidade (família Roblox real, ou
-- "[LuauBench] ... not simulated yet" quando aplicável) -- este wrapper só garante que o
-- diagnóstico final cita o nó do projeto de onde veio o "$className" problemático, e nunca deixa
-- o erro cru derrubar o comando inteiro (regra 04).
function Messages.MaterializeInvalidClass(nodePath: string, className: string, engineError: string): string
	return `Could not create "{nodePath}" as "{className}": {engineError}`
end

-- Decisão 7: `$properties` grava pela via pública (o `__newindex` real do runtime), então um nome
-- inválido ou uma propriedade somente-leitura chega aqui como o ERRO DO MOTOR (pcall), não como
-- um diagnóstico inventado por `cli` -- este wrapper só garante a citação do nó/propriedade.
function Messages.MaterializePropertyAssignmentFailed(nodePath: string, propertyName: string, engineError: string): string
	return `Could not apply "$properties.{propertyName}" at "{nodePath}": {engineError}`
end

--------------------------------------------------------------------------------------------------
-- UnsimulatedGlobals (Vector3/CFrame/Color3/Enum/...) -- task-cli-005, arquiteto-cli-2026-09-05.md,
-- Decisão 12, "Globais de valor não simulados: erro nomeado, nunca nil".
--------------------------------------------------------------------------------------------------

-- Prefixo `[LuauBench]` OBRIGATÓRIO (regra 00/03): não tem contraparte real (no Roblox `Vector3`
-- funciona normalmente) -- é o LuauBench que ainda não simula tipos de valor (leva 3), nunca uma
-- lacuna do Roblox. String fixada verbatim pelo desenho -- não reformular por classe.
function Messages.UnsimulatedGlobal(name: string): string
	return `[LuauBench] {name} is not simulated by LuauBench yet (planned: value-types wave)`
end

--------------------------------------------------------------------------------------------------
-- ModuleLoader (o `require` simulado) -- task-cli-005, arquiteto-cli-2026-09-05.md, Decisão 5.
--
-- As três primeiras são família Roblox (inglês, SEM prefixo `[LuauBench]`) -- aproximação de
-- boa-fé, string NÃO confirmada byte-a-byte contra o Roblox real (task-cli-007 pesquisou a
-- pergunta -- ver .claude/agents-memory/pesquisa-cli-lune-build-2026-09-05.md), mesmo protocolo já
-- usado por `Services.new`/`Instance.luau` para mensagem de família Roblox não confirmada.
--------------------------------------------------------------------------------------------------

function Messages.RequireRecursedSameThread(): string
	return "Requested module was required recursively"
end

function Messages.RequireDidNotReturnOneValue(): string
	return "Module code did not return exactly one value"
end

function Messages.RequireInvalidArgument(): string
	return "Attempted to call require with invalid argument(s)."
end

-- SEM contraparte real (no Roblox, `require` por asset id funciona, buscando o asset via rede) --
-- prefixo `[LuauBench]` OBRIGATÓRIO, motivo é local-first (regra 00, invariante 6): o LuauBench
-- nunca faz chamada de rede para buscar asset do usuário.
function Messages.RequireAssetIdNotSupported(): string
	return "[LuauBench] require by asset id is not supported (LuauBench runs offline)"
end

--------------------------------------------------------------------------------------------------
-- OutputFormatter (OutputRecord -> stdout/stderr) -- task-cli-006, arquiteto-cli-2026-09-05.md,
-- Decisão 13 ("Formato do output e idioma").
--------------------------------------------------------------------------------------------------

-- `record.scriptName` é `string?` no tipo de `runtime` (OutputRecord) -- na prática sempre
-- preenchido por `Sandbox.Run`/`Sandbox.Load`/`ModuleLoader`, mas o formatter trata o caso `nil`
-- de forma honesta em vez de indexar uma string vazia sem explicação nenhuma.
function Messages.UnknownScriptName(): string
	return "<unknown script>"
end

function Messages.OutputPrintLine(scriptName: string, message: string): string
	return `{scriptName}: {message}`
end

-- "warn  " (duas espaços) alinha visualmente com "error " (um espaço) -- as duas etiquetas somam
-- 6 caracteres, então a coluna de `scriptName` começa na mesma posição nas duas linhas (Decisão
-- 13 do desenho, exemplo verbatim de saída).
function Messages.OutputWarnLine(scriptName: string, message: string): string
	return `warn  {scriptName}: {message}`
end

function Messages.OutputErrorLine(scriptName: string, line: number?, message: string): string
	if line == nil then
		return `error {scriptName}: {message}`
	end
	return `error {scriptName}:{line}: {message}`
end

-- Reatribuição de linha (Decisão 13): um erro que se originou dentro de um `ModuleScript`
-- requerido é renderizado citando o MÓDULO que de fato errou (nome + linha), mas também o Script
-- que originou a cadeia de `require` (`originScriptName`, o `scriptName` de `OutputRecord`, que
-- continua sendo o Script de topo -- ver OutputFormatter.luau).
function Messages.OutputErrorLineFromModule(moduleName: string, moduleLine: number?, message: string, originScriptName: string): string
	if moduleLine == nil then
		return `error {moduleName}: {message} (required by {originScriptName})`
	end
	return `error {moduleName}:{moduleLine}: {message} (required by {originScriptName})`
end

--------------------------------------------------------------------------------------------------
-- RunCommand (orquestração do pipeline `luaubench run`) -- task-cli-006, arquiteto-cli-2026-09-
-- 05.md, seção "Pipeline do `luaubench run [caminho]`".
--------------------------------------------------------------------------------------------------

function Messages.SummaryLine(executed: number, skippedLocalScripts: number, skippedByContainer: number, skippedDisabled: number): string
	return `{executed} Script(s) executed, {skippedLocalScripts} LocalScript(s) not executed (LuauBench runs as a server), {skippedByContainer} Script(s) skipped (not under a configured server container), {skippedDisabled} Script(s) skipped (Enabled = false).`
end

function Messages.DiagnosticCountLine(errorCount: number, warningCount: number): string
	return `{errorCount} error(s), {warningCount} warning(s).`
end

return Messages
