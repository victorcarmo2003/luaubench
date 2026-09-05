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

return Messages
