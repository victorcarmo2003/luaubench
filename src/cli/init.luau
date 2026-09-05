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
	para alcançar `src/services`. De FORA de `src/cli/` (um módulo de nome normal, ex.: uma
	futura `RunCommand.luau` chamando de volta, ou um teste em `tests/scenarios/`), o caminho é o
	óbvio: `require("../cli")`.

	NUNCA `require("./init")`/`require("./init.luau")` de um irmão -- confirmado empiricamente
	pelo mesmo mecanismo já registrado em `runtime`/`services`: só a forma "estilo diretório"
	resolve.

	ESCOPO DESTA TAREFA (task-cli-001, "esqueleto do território"): só os cinco módulos de base
	existem ainda -- `ProjectFile`/`TreePlanner`/`TreeMaterializer`/`ScriptRunner`/`RunCommand`
	(o pipeline real de `luaubench run`) são tarefas seguintes (task-cli-002 em diante, ver
	arquiteto-cli-2026-09-05.md, "Pipeline do `luaubench run [caminho]`"). Por isso `Cli.Main`
	JÁ reconhece e valida o comando "run" via `Args.Parse`, mas ainda não tem como executá-lo de
	verdade -- devolve `Messages.RunPipelineNotImplementedYet()` em vez de fingir sucesso (regra
	00: nunca "tudo concluído" silencioso). `Cli.RunProject` (citado no desenho do arquiteto,
	"Módulos" -> "init.luau") NÃO é adicionado aqui de propósito: sua assinatura documentada
	referencia `RunCommand.RunOptions`, um tipo de um módulo que ainda não existe neste território
	-- será acrescentado quando `RunCommand.luau` existir (task-cli-006), não antes.
]]

local Args = require("./cli/Args")
local Messages = require("./cli/Messages")
local Services = require("./services")
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
-- script do usuário levantou erro não tratado; 2 erro de projeto ou de uso. Nesta tarefa só o
-- código 2 é alcançável (uso inválido via Args, ou o placeholder de "run" ainda não implementado)
-- -- 0 (help/version) e 1 (erro do script do usuário) ficam para quando o pipeline real existir.
local EXIT_OK = 0
local EXIT_USAGE_OR_PROJECT_ERROR = 2

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

	-- `command.Kind == "run"` é a única variante restante do union `Args.Command` -- ver nota de
	-- escopo no cabeçalho deste arquivo.
	stdio.ewrite(Messages.RunPipelineNotImplementedYet() .. "\n")
	return { ExitCode = EXIT_USAGE_OR_PROJECT_ERROR, ErrorCount = 1, WarningCount = 0 }
end

return Cli
