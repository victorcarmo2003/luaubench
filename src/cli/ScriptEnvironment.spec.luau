--!strict

--[[
	Teste da task-cli-005 (`ScriptEnvironment.luau`). Cobre o acceptance do board: `game`/
	`workspace`/`script`/`Instance.new`/`require`/`_G`/`shared` acessíveis de dentro de um
	`Sandbox.Run` de verdade; `_G` escrito por um script é lido por outro do mesmo run (mesma
	`GlobalTable`, passada por referência); `_G`/`shared` são tabelas SEPARADAS (correção
	task-cli-007); os `UnsimulatedGlobals` continuam presentes.

	Roda com `lune run src/cli/ScriptEnvironment.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Services = require("../services")
local ScriptEnvironment = require("./ScriptEnvironment")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Mesmo padrão de `TreeMaterializer.spec.luau`/`ModuleLoader.spec.luau` -- `Services.Bootstrap` é
-- idempotente, seguro de chamar em todo teste, cada um com seu próprio Scheduler/DataModel.
local function newGame(): (Runtime.Scheduler, Runtime.DataModel)
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return scheduler, game
end

local function noopRequire(_target: unknown): unknown
	return nil
end

test("Build() expõe game/workspace/script apontando para as Instances certas", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptInstance = Services.new("Script", "Main")
	scriptInstance.Parent = game:GetService("ServerScriptService")

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = noopRequire,
	}
	local globals = ScriptEnvironment.Build(context, scriptInstance)

	assert(globals.game == game, "globals.game deveria ser o MESMO DataModel do contexto")
	assert(globals.workspace == workspace, "globals.workspace deveria ser o MESMO Workspace do contexto")
	assert(globals.script == scriptInstance, "globals.script deveria ser a MESMA Instance passada a Build")
end)

test("Build() expõe Instance.new funcionando de ponta a ponta (cria uma Instance real via Services.new)", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptInstance = Services.new("Script", "Main")

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = noopRequire,
	}
	local globals = ScriptEnvironment.Build(context, scriptInstance)
	local instanceGlobal = (globals.Instance :: unknown) :: { new: (className: string, name: string?) -> Runtime.Instance }

	local created = instanceGlobal.new("Folder", "CreatedByExtraGlobals")
	assert(created.ClassName == "Folder", "Instance.new deveria criar uma Folder real via Services.new")
	assert(created.Name == "CreatedByExtraGlobals", "Instance.new deveria respeitar o Name pedido")
end)

test("Build() expõe require == context.Require (identidade -- Build nunca decide o require sozinho)", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptInstance = Services.new("Script", "Main")

	local calledWith: unknown = nil
	local customRequire = function(target: unknown): unknown
		calledWith = target
		return "require-result"
	end

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = customRequire,
	}
	local globals = ScriptEnvironment.Build(context, scriptInstance)
	local requireGlobal = (globals.require :: unknown) :: (unknown) -> unknown

	local result = requireGlobal("marker")
	assert(result == "require-result", "globals.require deveria ser EXATAMENTE context.Require, sem embrulho")
	assert(calledWith == "marker", "chamar globals.require deveria repassar o argumento direto pra context.Require")
end)

test("_G e shared são tabelas SEPARADAS (correção task-cli-007) -- escrever numa não afeta a outra", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptInstance = Services.new("Script", "Main")

	local globalTable: { [string]: unknown } = {}
	local sharedTable: { [string]: unknown } = {}

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = globalTable,
		SharedTable = sharedTable,
		Require = noopRequire,
	}
	local globals = ScriptEnvironment.Build(context, scriptInstance)

	assert(globals._G == globalTable, "globals._G deveria ser a MESMA tabela que context.GlobalTable")
	assert(globals.shared == sharedTable, "globals.shared deveria ser a MESMA tabela que context.SharedTable")
	assert(globals._G ~= globals.shared, "_G e shared NUNCA deveriam ser a mesma tabela (achado corrigido de task-cli-007)")

	globalTable.fromGlobal = "g"
	assert(sharedTable.fromGlobal == nil, "escrever em _G não deveria aparecer em shared")
end)

test("_G escrito por um script é lido por outro do mesmo run (mesma GlobalTable compartilhada)", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptA = Services.new("Script", "ScriptA")
	local scriptB = Services.new("Script", "ScriptB")

	-- UMA tabela por execução -- compartilhada entre os DOIS scripts do run, exatamente como o
	-- desenho pede (quem cria essa tabela e a repassa pra cada `EnvironmentContext` é quem monta o
	-- pipeline -- `RunCommand`, task-cli-006; este teste simula esse papel).
	local sharedGlobalTable: { [string]: unknown } = {}

	local contextA: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = sharedGlobalTable,
		SharedTable = {},
		Require = noopRequire,
	}
	local globalsA = ScriptEnvironment.Build(contextA, scriptA)

	local contextB: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = sharedGlobalTable,
		SharedTable = {},
		Require = noopRequire,
	}
	local globalsB = ScriptEnvironment.Build(contextB, scriptB)

	local gA = (globalsA._G :: unknown) :: { [string]: unknown }
	local gB = (globalsB._G :: unknown) :: { [string]: unknown }

	gA.writtenByA = "hello-from-a"
	assert(gB.writtenByA == "hello-from-a", "_G escrito por A deveria ser lido por B -- mesma tabela compartilhada entre os scripts do run")
end)

test("Build() ainda expõe os UnsimulatedGlobals (Vector3 presente, mas errando ao usar)", function()
	local _scheduler, game = newGame()
	local workspace = game:GetService("Workspace")
	local scriptInstance = Services.new("Script", "Main")

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = game,
		Workspace = workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = noopRequire,
	}
	local globals = ScriptEnvironment.Build(context, scriptInstance)

	assert(globals.Vector3 ~= nil, "Vector3 deveria estar presente em globals (nunca nil silencioso -- Decisão 12)")

	local vector3 = (globals.Vector3 :: unknown) :: { new: unknown }
	local ok, err = pcall(function()
		return vector3.new
	end)
	assert(not ok, "acessar Vector3.new deveria continuar errando")
	assert(string.find(tostring(err), "[LuauBench]", 1, true) ~= nil, "mensagem deveria ter o prefixo [LuauBench]")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
