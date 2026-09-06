--!strict

--[[
	Ponto de entrada público do território `cli` (task-cli-001; arquiteto-cli-2026-09-05.md,
	seção "Módulos" -> "init.luau"). Existe para que `tests/scenarios/` (território do
	`testador`) rode um projeto de ponta a ponta chamando `Cli.Main(argv)` diretamente, sem
	disparar um processo `lune run` separado.

	GOTCHA DO LUNE (mesmo já documentado nos cabeçalhos de `src/runtime/init.luau` e
	`src/services/init.luau` -- repetido aqui porque `cli` só lê os próprios arquivos, nunca o
	desenho do arquiteto diretamente em tempo de execução): carregado no estilo "diretório"
	(`require("../cli")` de fora, ou `require("./")` de um arquivo irmão dentro do próprio
	`src/cli/`), o Lune identifica este chunk pelo caminho do PRÓPRIO DIRETÓRIO (`src/cli`), não
	por `src/cli/init`. Isso desloca a base de resolução dos `require` relativos ESCRITOS AQUI
	DENTRO em um nível: por isso os `require` abaixo usam `./cli/Args`/`./cli/Messages` (não
	`./Args`/`./Messages`) para alcançar os arquivos irmãos, e `./services` (não `../services`)
	para alcançar `src/services`. De FORA de `src/cli/` (um módulo de nome normal, ex.: um teste em
	`tests/scenarios/`), o caminho é o óbvio: `require("../cli")`.

	NUNCA `require("./init")`/`require("./init.luau")` de um irmão -- confirmado empiricamente
	pelo mesmo mecanismo já registrado em `runtime`/`services`: só a forma "estilo diretório"
	resolve.

	PIPELINE REAL LIGADO (task-cli-006; arquiteto-cli-2026-09-05.md, "Pipeline do `luaubench run
	[caminho]`" e Decisões 11/13). `Cli.Main` não implementa nada do pipeline por conta própria --
	traduz o `Command` de `Args.Parse` num `RunCommand.RunOptions` e delega inteiramente a
	`RunCommand.Execute` (`ProjectFile`/`TreePlanner`/`TreeMaterializer`/`ScriptRunner`/
	`OutputFormatter` já existem, território de `coder-cli` nas tarefas anteriores). `Cwd` vem de
	`process.cwd` (`RunCommand` nunca lê `process` diretamente -- só quem monta as `RunOptions`).
	`UseColor` resolve `--no-color` (`command.NoColor`) E a variável de ambiente `NO_COLOR`
	(Decisão 13 do desenho: "cor ligada por padrão, desligada por --no-color e pela env var
	NO_COLOR" -- presença da variável desliga a cor independente do valor, convenção de facto
	<https://no-color.org>, `process.env.NO_COLOR ~= nil` já cobre isso).

	`Cli.RunProject` (citado no desenho do arquiteto, "Módulos" -> "init.luau") existe agora que
	`RunCommand.luau` existe -- é o caminho que `tests/scenarios/` (território do `testador`) usa
	pra rodar um projeto de ponta a ponta com `RunOptions` já montadas (sem precisar reconstruir
	argv), sem disparar processo.

	`Messages.RunPipelineNotImplementedYet()` (Messages.luau) fica sem uso a partir desta tarefa --
	NÃO removida do arquivo (regra do board: Messages.luau é append-only) nem do módulo `Messages`
	em si (nenhuma linha apagada), só deixou de ser chamada aqui.
]]

local Args = require("./cli/Args")
local Messages = require("./cli/Messages")
local RunCommand = require("./cli/RunCommand")
local Services = require("./services")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

-- Versão do próprio LuauBench (distinta da versão do Roblox API Dump, que vem de
-- `Services.GetDumpVersion()`). Não existe ainda nenhuma fonte canônica no repositório (sem
-- `package.json`/tag semver publicada até esta tarefa -- ver CLAUDE.md, "Estado atual do
-- projeto") -- fixado aqui como o ponto único a atualizar até que uma fonte melhor exista
-- (ex.: gerado a partir de uma tag de release no empacotamento Rokit, ainda não desenhado).
local LUAUBENCH_VERSION = "0.1.0"

export type MainResult = {
	ExitCode: number,
	ErrorCount: number,
	WarningCount: number,
}

local Cli = {}

-- Exit codes fixados no desenho ("Pipeline do `luaubench run [caminho]`"): 0 sucesso; 1 o
-- script do usuário levantou erro não tratado; 2 erro de projeto ou de uso. Os três agora são
-- alcançáveis de verdade: 0/1 vêm de `RunCommand.Execute` (pipeline real, task-cli-006); 2
-- continua cobrindo tanto uso inválido (`Args`) quanto erro de projeto (`RunCommand`).
local EXIT_OK = 0
local EXIT_USAGE_OR_PROJECT_ERROR = 2

-- Decisão 13 do desenho: cor ligada por padrão, desligada por `--no-color` OU pela variável de
-- ambiente `NO_COLOR` -- convenção de facto (<https://no-color.org>): a MERA PRESENÇA da
-- variável desliga a cor, independente do valor que ela carrega (mesmo "" ou "0"), por isso o
-- teste é `~= nil`, nunca uma comparação de valor.
local function resolveUseColor(noColorFlag: boolean, noColorEnvValue: string?): boolean
	return not noColorFlag and noColorEnvValue == nil
end

function Cli.Main(argv: { string }): MainResult
	local command = Args.Parse(argv)

	if command.Kind == "help" then
		print(Messages.HelpText())
		return { ExitCode = EXIT_OK, ErrorCount = 0, WarningCount = 0 }
	end

	if command.Kind == "version" then
		local dump = Services.GetDumpVersion()
		print(Messages.VersionLine(LUAUBENCH_VERSION, dump.Version, dump.Commit))
		return { ExitCode = EXIT_OK, ErrorCount = 0, WarningCount = 0 }
	end

	if command.Kind == "error" then
		-- `stdio.ewrite` não adiciona nova linha (ver `@lune/stdio`, doc de `ewrite`) --
		-- diferente de `print`, que a adiciona sozinho.
		stdio.ewrite(command.Message .. "\n")
		return { ExitCode = EXIT_USAGE_OR_PROJECT_ERROR, ErrorCount = 1, WarningCount = 0 }
	end

	-- `command.Kind == "run"` é a única variante restante do union `Args.Command`. Traduz o
	-- `Command` já parseado em `RunCommand.RunOptions` e delega o pipeline inteiro -- `Cli.Main`
	-- não decide nada sobre `.project.json`/DataModel/scripts por conta própria (regra 01: um
	-- módulo, uma responsabilidade).
	return RunCommand.Execute({
		ProjectPath = command.ProjectPath,
		Cwd = process.cwd,
		Timeout = command.Timeout,
		UseColor = resolveUseColor(command.NoColor, process.env.NO_COLOR),
		Verbose = command.Verbose,
		-- task-cli-026: espelha `Command.AllowHttp`/`AllowHttpLocal` 1:1 -- `Cli.Main` não decide
		-- nada sobre a política de rede, só repassa (mesma disciplina de todos os outros campos
		-- desta chamada).
		AllowHttp = command.AllowHttp,
		AllowHttpLocal = command.AllowHttpLocal,
		-- task-cli-030: espelha `Command.NoPersist` 1:1, mesma disciplina das duas flags acima --
		-- `Cli.Main` não decide nada sobre persistência local do estado "cloud", só repassa.
		NoPersist = command.NoPersist,
	})
end

-- Citada no desenho do arquiteto ("Módulos" -> "init.luau") desde a task-cli-001, mas só
-- adicionada agora que `RunCommand.luau` (e o tipo `RunCommand.RunOptions` que sua assinatura
-- referencia) existe de verdade (task-cli-006). Caminho programático de `tests/scenarios/`
-- (território do `testador`) para rodar um projeto de ponta a ponta com `RunOptions` já
-- montadas, sem reconstruir argv nem disparar processo.
function Cli.RunProject(options: RunCommand.RunOptions): MainResult
	return RunCommand.Execute(options)
end

return Cli
