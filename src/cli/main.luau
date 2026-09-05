--!strict

--[[
	Executável fino do LuauBench (task-cli-001; arquiteto-cli-2026-09-05.md, seção "Módulos" ->
	"main.luau"). Lê `process.args`, chama `Cli.Main`, chama `process.exit(code)` -- nada mais.
	Toda a lógica de parsing/dispatch vive em `init.luau`/`Args.luau`; este arquivo não decide
	nada por conta própria (é o que permite `tests/scenarios/` chamar `Cli.Main` direto, sem
	precisar reproduzir o que está aqui).

	Requer `./` (estilo diretório), NUNCA `./init`/`./init.luau`: mesmo gotcha de resolução do
	Lune já documentado no cabeçalho de `init.luau` (e, antes disso, em
	`src/runtime/init.luau`/`src/services/init.luau`) -- só a forma "estilo diretório" carrega o
	`init.luau` real a partir de um arquivo irmão.

	Sem `.spec.luau` correspondente: chamar `Cli.Main` e depois `process.exit` não é logica
	testável isoladamente (o próprio `process.exit` encerraria o runner de specs) -- é só uso
	direto de duas APIs já cobertas em outro lugar (`Args.spec.luau`/`init.spec.luau` cobrem
	`Cli.Main`; `process.exit` é confiado como Lune nativo, não algo que `cli` implementa). Regra
	01: "teste o que for prático" -- rodar `lune run src/cli/main.luau --help`/`--version`
	manualmente é a verificação real deste arquivo (ver relatório da tarefa).
]]

local process = require("@lune/process")
local Cli = require("./")

local result = Cli.Main(process.args)
process.exit(result.ExitCode)
