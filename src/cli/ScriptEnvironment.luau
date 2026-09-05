--!strict

--[[
	Monta o `extraGlobals` de UMA Instance de script (`Script`/`LocalScript`/`ModuleScript`) --
	`game`, `workspace`, `script`, `Instance = { new = Services.new }`, `require`, `_G`, `shared`,
	mais os `UnsimulatedGlobals`. Único lugar de `cli` que decide o que o script enxerga ALÉM da
	whitelist fixa do `runtime` (que não conhece nome de classe nenhum -- regra 02).

	Desenho completo em .claude/agents-memory/arquiteto-cli-2026-09-05.md, Decisão 5 e Decisão 12
	(seção "Módulos" -> "ScriptEnvironment.luau"). LER ANTES de mexer aqui.

	`_G`/`shared` são tabelas SEPARADAS -- achado corrigido pela pesquisa de task-cli-007 (ver
	arquiteto-cli-2026-09-05.md, "CORREÇÃO 2026-09-05 (task-cli-007)"): o desenho original propunha
	a MESMA tabela para os dois, mas não são a mesma tabela no Roblox real. Quem cria as duas
	tabelas (uma por execução/`run`, compartilhada entre TODOS os scripts do run) é quem monta o
	pipeline (`RunCommand`, task-cli-006, ainda não escrito) -- este módulo só recebe as duas via
	`EnvironmentContext` e as expõe, nunca as cria nem as mistura.

	`Instance.new` (`extraGlobals.Instance = { new = Services.new }`) é a ÚNICA forma de
	`Instance.new(...)` alcançar o script do usuário -- `Runtime.Sandbox.Run`/`Load` nunca expõem
	`Instance` por conta própria (whitelist fixa de globals, `runtime` não conhece nome de classe --
	regra 02). `services/init.luau` (cabeçalho, "SEQUÊNCIA DE BOOTSTRAP") já documenta este mesmo
	contrato do lado de `services`. Requer `../services` diretamente (o agregador público, nunca
	`generated/`/`behavior/` -- regra 03) só para isto.

	API FALTANTE (a reportar, não contornada): o desenho referencia `Runtime.SandboxGlobals` como
	tipo de retorno de `ScriptEnvironment.Build`, mas `src/runtime/init.luau` (task-runtime-007/025)
	NÃO reexporta esse tipo (só `SandboxOptions`/`SandboxResult`/`SandboxChunkOptions`/
	`OutputRecord`/`OutputLevel` -- ver cabeçalho de `runtime/init.luau`, lista de `export type`).
	`SandboxGlobals` é definido em `Sandbox.luau` como exatamente `{ [string]: unknown }` -- este
	módulo usa essa forma estrutural diretamente (`{ [string]: unknown }`), que é idêntica byte-a-
	byte e aceita sem cast em `SandboxOptions.extraGlobals`/`SandboxChunkOptions.extraGlobals` (o
	Luau compara estruturalmente) -- não há necessidade de contornar território nenhum para isto
	funcionar, só a conveniência de um nome `Runtime.SandboxGlobals` fica de fora.
]]

local Runtime = require("../runtime")
local Services = require("../services")
local UnsimulatedGlobals = require("./UnsimulatedGlobals")

export type EnvironmentContext = {
	Game: Runtime.DataModel,
	Workspace: Runtime.Instance,
	-- `_G` do run -- UMA tabela por execução, compartilhada entre todos os scripts do run (ver
	-- cabeçalho). Quem cria/injeta é quem monta o pipeline, nunca este módulo.
	GlobalTable: { [string]: unknown },
	-- `shared` do run -- tabela SEPARADA de `GlobalTable` (ver cabeçalho, correção task-cli-007).
	SharedTable: { [string]: unknown },
	-- `require` já pronto para ESTA Instance -- construído por quem monta o pipeline
	-- (`RunCommand`/`ModuleLoader`, ver ModuleLoader.luau), fechado sobre a origem certa para
	-- atribuição de erro assíncrono (task.spawn dentro de um módulo -- ver ModuleLoader.luau,
	-- cabeçalho). `ScriptEnvironment.luau` nunca decide isso sozinho.
	Require: (target: unknown) -> unknown,
}

local ScriptEnvironment = {}

-- `scriptInstance` vira o global `script` -- a MESMA Instance para todo `require`/`Sandbox.Run`
-- daquela Instance especifica (um `Script`/`LocalScript`/`ModuleScript` real do `MaterializedTree`,
-- task-cli-004, ou um `ModuleScript` sendo carregado por `ModuleLoader.Require`).
function ScriptEnvironment.Build(context: EnvironmentContext, scriptInstance: Runtime.Instance): { [string]: unknown }
	-- Base: os globais de VALOR não simulados (Vector3/CFrame/Color3/Enum/...), cada um errando
	-- nomeando a lacuna (Decisão 12) -- `UnsimulatedGlobals.Build()` já devolve uma tabela NOVA a
	-- cada chamada (ver cabeçalho daquele módulo), então sobrepor as chaves abaixo nunca muta
	-- estado compartilhado entre scripts.
	local globals: { [string]: unknown } = UnsimulatedGlobals.Build()

	globals.game = context.Game
	globals.workspace = context.Workspace
	globals.script = scriptInstance
	globals.Instance = { new = Services.new }
	globals.require = context.Require
	globals._G = context.GlobalTable
	globals.shared = context.SharedTable

	return globals
end

return ScriptEnvironment
