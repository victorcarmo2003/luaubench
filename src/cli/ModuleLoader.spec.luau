--!strict

--[[
	Teste da task-cli-005 (`ModuleLoader.luau`). Cobre o acceptance completo do board:

	- `require(m)` devolve o valor do módulo e cacheia (segunda chamada não re-executa).
	- ciclo A->B->A erra com a mensagem de recursão.
	- módulo sem `return` erra.
	- `require(Folder)` erra.
	- `require(123)` erra com prefixo `[LuauBench]`.
	- módulo que faz `task.wait()` no topo suspende quem chamou, e um segundo requerente em outra
	  thread espera pelo MESMO resultado (sem reexecutar o módulo).
	- erro dentro do módulo é capturável por `pcall` no script chamador.
	- `_G` escrito por um script é lido por outro do mesmo run (via `ScriptEnvironment`, já coberto
	  em `ScriptEnvironment.spec.luau` -- não repetido aqui).
	- CRITÉRIO ADICIONAL (achado MÉDIO da revisão de task-runtime-025): `task.spawn` no CORPO de um
	  módulo requerido gera exatamente 1 `OutputRecord` de erro no Script que fez o require
	  original.

	Instances construídas em memória via `Services.new` (nenhum `.project.json`/fixture em disco
	necessário -- este território testa semântica de `require`, não parsing de projeto Rojo).

	Roda com `lune run src/cli/ModuleLoader.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../runtime")
local Services = require("../services")
local ModuleLoader = require("./ModuleLoader")
local ScriptEnvironment = require("./ScriptEnvironment")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Harness comum: Scheduler/DataModel reais (via `Services.Bootstrap`, idempotente -- mesmo padrão
-- de `TreeMaterializer.spec.luau`), ReplicatedStorage real como container dos módulos de teste, e
-- um `ModuleLoader` "de um Script fictício" já pronto para os testes que não precisam também de um
-- `Sandbox.Run` real em volta.
type Harness = {
	Scheduler: Runtime.Scheduler,
	Game: Runtime.DataModel,
	Workspace: Runtime.Instance,
	ReplicatedStorage: Runtime.Instance,
	GlobalTable: { [string]: unknown },
	SharedTable: { [string]: unknown },
	Records: { Runtime.OutputRecord },
	Cache: ModuleLoader.ModuleCache,
	Loader: ModuleLoader.ModuleLoader,
}

local function newHarness(scriptName: string): Harness
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local workspace = game:GetService("Workspace")
	local replicatedStorage = game:GetService("ReplicatedStorage")

	local records: { Runtime.OutputRecord } = {}
	local cache = ModuleLoader.NewCache()
	local loader = ModuleLoader.new({
		Scheduler = scheduler,
		ScriptName = scriptName,
		OnOutput = function(record: Runtime.OutputRecord)
			table.insert(records, record)
		end,
		Cache = cache,
		Game = game,
		Workspace = workspace,
		GlobalTable = {},
		SharedTable = {},
	})

	return {
		Scheduler = scheduler,
		Game = game,
		Workspace = workspace,
		ReplicatedStorage = replicatedStorage,
		GlobalTable = {},
		SharedTable = {},
		Records = records,
		Cache = cache,
		Loader = loader,
	}
end

local function newModule(harness: Harness, name: string, source: string): Runtime.Instance
	local mod = Services.new("ModuleScript", name)
	Runtime.Instance.SetPropertyRaw(mod, "Source", source)
	mod.Parent = harness.ReplicatedStorage
	return mod
end

--------------------------------------------------------------------------------------------------
-- Caminho feliz: devolve o valor do módulo e cacheia (segunda chamada não re-executa)
--------------------------------------------------------------------------------------------------

test("Require: devolve o valor do módulo e cacheia -- segunda chamada NÃO re-executa (contador)", function()
	local harness = newHarness("ServerScriptService.Main")
	local counterTable: { [string]: unknown } = {}
	harness.Loader = ModuleLoader.new({
		Scheduler = harness.Scheduler,
		ScriptName = "ServerScriptService.Main",
		OnOutput = function(record)
			table.insert(harness.Records, record)
		end,
		Cache = harness.Cache,
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = counterTable,
		SharedTable = {},
	})

	local mod = newModule(harness, "Counter", [[
		local count = (_G.executionCount :: number?) or 0
		_G.executionCount = count + 1
		return { marker = "the-value" }
	]])

	local first = harness.Loader:Require(mod)
	local second = harness.Loader:Require(mod)

	assert(first == second, "as duas chamadas deveriam devolver o MESMO valor (identidade de tabela) -- cache por Instance")
	assert(counterTable.executionCount == 1, `o módulo deveria ter executado exatamente 1 vez, executou {tostring(counterTable.executionCount)} vez(es)`)

	local resultTable = (first :: unknown) :: { marker: string }
	assert(resultTable.marker == "the-value", "o valor devolvido deveria ser exatamente o que o módulo retornou")
end)

--------------------------------------------------------------------------------------------------
-- Ciclo A->B->A erra com a mensagem de recursão
--------------------------------------------------------------------------------------------------

test("Require: ciclo A->B->A erra com a mensagem de recursão ('Requested module was required recursively')", function()
	local harness = newHarness("ServerScriptService.Main")

	local moduleA = newModule(harness, "ModuleA", [[ return require(script.Parent.ModuleB) ]])
	newModule(harness, "ModuleB", [[ return require(script.Parent.ModuleA) ]])

	local ok, err = pcall(function()
		return harness.Loader:Require(moduleA)
	end)

	assert(not ok, "requerer um ciclo A->B->A deveria errar")
	assert(string.find(tostring(err), "required recursively", 1, true) ~= nil, `mensagem deveria citar 'required recursively', recebeu: {tostring(err)}`)
end)

test("Require: auto-referência direta (A requer A) também erra com a mensagem de recursão", function()
	local harness = newHarness("ServerScriptService.Main")
	local moduleA = newModule(harness, "SelfRef", [[ return require(script) ]])

	local ok, err = pcall(function()
		return harness.Loader:Require(moduleA)
	end)

	assert(not ok, "um módulo requerendo a si mesmo deveria errar")
	assert(string.find(tostring(err), "required recursively", 1, true) ~= nil, `mensagem deveria citar 'required recursively', recebeu: {tostring(err)}`)
end)

--------------------------------------------------------------------------------------------------
-- Módulo sem `return` erra
--------------------------------------------------------------------------------------------------

test("Require: módulo sem return erra ('Module code did not return exactly one value')", function()
	local harness = newHarness("ServerScriptService.Main")
	local mod = newModule(harness, "NoReturn", [[ local x = 1 + 1 ]])

	local ok, err = pcall(function()
		return harness.Loader:Require(mod)
	end)

	assert(not ok, "módulo sem return deveria errar")
	assert(string.find(tostring(err), "did not return exactly one value", 1, true) ~= nil, `mensagem deveria citar a família certa, recebeu: {tostring(err)}`)
end)

test("Require: módulo que retorna DOIS valores também erra (não é 'exatamente um')", function()
	local harness = newHarness("ServerScriptService.Main")
	local mod = newModule(harness, "TwoReturns", [[ return 1, 2 ]])

	local ok, err = pcall(function()
		return harness.Loader:Require(mod)
	end)

	assert(not ok, "módulo com dois valores de retorno deveria errar")
	assert(string.find(tostring(err), "did not return exactly one value", 1, true) ~= nil, `mensagem deveria citar a família certa, recebeu: {tostring(err)}`)
end)

--------------------------------------------------------------------------------------------------
-- require(Folder) erra
--------------------------------------------------------------------------------------------------

test("Require: require(Folder) erra ('Attempted to call require with invalid argument(s).')", function()
	local harness = newHarness("ServerScriptService.Main")
	local folder = Services.new("Folder", "NotAModule")
	folder.Parent = harness.ReplicatedStorage

	local ok, err = pcall(function()
		return harness.Loader:Require(folder)
	end)

	assert(not ok, "require(Folder) deveria errar")
	assert(string.find(tostring(err), "Attempted to call require with invalid argument", 1, true) ~= nil, `mensagem deveria citar a família certa, recebeu: {tostring(err)}`)
end)

test("Require: require(nil)/require(\"string\")/require(newproxy())/require(true) também erram com a mesma família", function()
	local harness = newHarness("ServerScriptService.Main")

	-- Deliberadamente NÃO usa uma tabela `{ nil, ... }` pra reunir os casos: um `nil` literal como
	-- elemento de um construtor de tabela nunca fica lá para ser iterado (não existe entrada pra
	-- iterar) -- cada alvo inválido é testado como uma chamada própria, pra garantir que `nil` seja
	-- de fato exercitado, não silenciosamente pulado.
	local function assertInvalid(target: unknown, label: string)
		local ok, err = pcall(function()
			return harness.Loader:Require(target)
		end)
		assert(not ok, `require(...) para um alvo inválido ({label}) deveria errar`)
		assert(string.find(tostring(err), "Attempted to call require with invalid argument", 1, true) ~= nil, `mensagem deveria citar a família certa para {label}, recebeu: {tostring(err)}`)
	end

	assertInvalid(nil, "nil")
	assertInvalid("a-string", "string")
	assertInvalid(newproxy(true), "newproxy(true) cru (não é uma Instance do LuauBench)")
	assertInvalid(true, "boolean")
end)

--------------------------------------------------------------------------------------------------
-- require(123) erra com prefixo [LuauBench]
--------------------------------------------------------------------------------------------------

test("Require: require(123) (asset id numérico) erra com prefixo '[LuauBench]'", function()
	local harness = newHarness("ServerScriptService.Main")

	local ok, err = pcall(function()
		return harness.Loader:Require(123)
	end)

	assert(not ok, "require(123) deveria errar")
	local message = tostring(err)
	assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {message}`)
	assert(string.find(message, "asset id", 1, true) ~= nil, `mensagem deveria citar 'asset id', recebeu: {message}`)
end)

--------------------------------------------------------------------------------------------------
-- task.wait() no topo suspende quem chamou; segundo requerente em outra thread espera o MESMO
-- resultado (sem reexecutar)
--------------------------------------------------------------------------------------------------

test("Require: task.wait() no topo do módulo suspende a thread chamadora; segundo requerente em outra thread espera o mesmo resultado", function()
	local harness = newHarness("ServerScriptService.Main")
	local sharedGlobals: { [string]: unknown } = {}
	harness.Loader = ModuleLoader.new({
		Scheduler = harness.Scheduler,
		ScriptName = "ServerScriptService.Main",
		OnOutput = function(record)
			table.insert(harness.Records, record)
		end,
		Cache = harness.Cache,
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = sharedGlobals,
		SharedTable = {},
	})

	local mod = newModule(harness, "SlowModule", [[
		local count = (_G.executionCount :: number?) or 0
		_G.executionCount = count + 1
		task.wait(0.05)
		return "done"
	]])

	local firstResult: unknown = nil
	local firstDone = false
	local secondResult: unknown = nil
	local secondDone = false

	harness.Scheduler:Spawn(function()
		firstResult = harness.Loader:Require(mod)
		firstDone = true
	end)

	assert(not firstDone, "o primeiro requerente deveria ter sido suspenso pelo task.wait() do módulo, antes de qualquer StepOnce")

	-- Segundo requerente, OUTRA thread, pedindo o MESMO módulo enquanto ele ainda está "loading".
	harness.Scheduler:Spawn(function()
		secondResult = harness.Loader:Require(mod)
		secondDone = true
	end)

	assert(not secondDone, "o segundo requerente também deveria estar suspenso, esperando o primeiro terminar")

	harness.Scheduler:StepOnce(0.02)
	assert(not firstDone and not secondDone, "0.02s ainda não deveria ser suficiente para o task.wait(0.05) do módulo")

	harness.Scheduler:StepOnce(0.02)
	harness.Scheduler:StepOnce(0.02)

	assert(firstDone, "o primeiro requerente deveria ter sido retomado depois do task.wait(0.05) resolver")
	assert(secondDone, "o segundo requerente deveria ter sido retomado junto (Ready:Fire acorda quem esperava)")
	assert(firstResult == "done", "o primeiro requerente deveria ter recebido o valor do módulo")
	assert(secondResult == "done", "o segundo requerente deveria ter recebido o MESMO valor do módulo")
	assert(sharedGlobals.executionCount == 1, `o módulo deveria ter executado exatamente 1 vez mesmo com dois requerentes concorrentes, executou {tostring(sharedGlobals.executionCount)} vez(es)`)
end)

--------------------------------------------------------------------------------------------------
-- Erro dentro do módulo é capturável por pcall no script chamador
--------------------------------------------------------------------------------------------------

test("erro SÍNCRONO dentro do módulo é capturável por pcall(require, m) no script chamador", function()
	local harness = newHarness("ServerScriptService.Main")
	local mod = newModule(harness, "Erroring", [[ error("module boom") ]])

	local scriptInstance = Services.new("Script", "Main")
	scriptInstance.Parent = harness.Game:GetService("ServerScriptService")

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = harness.GlobalTable,
		SharedTable = harness.SharedTable,
		Require = function(target: unknown): unknown
			return harness.Loader:Require(target)
		end,
	}
	local extraGlobals = ScriptEnvironment.Build(context, scriptInstance)

	local captured: { ok: boolean, message: string }? = nil
	local extra = extraGlobals
	extra.targetModule = mod
	extra.report = function(ok: boolean, message: string)
		captured = { ok = ok, message = message }
	end

	Runtime.Sandbox.Run({
		scriptName = scriptInstance:GetFullName(),
		source = [[
			local ok, err = pcall(function()
				return require(targetModule)
			end)
			report(ok, tostring(err))
		]],
		scheduler = harness.Scheduler,
		extraGlobals = extra,
		onOutput = function(record)
			table.insert(harness.Records, record)
		end,
	})

	assert(captured ~= nil, "o script chamador deveria ter completado e chamado report()")
	local result = captured :: { ok: boolean, message: string }
	assert(not result.ok, "pcall(require, modulo-que-erra) deveria devolver ok=false")
	assert(string.find(result.message, "module boom", 1, true) ~= nil, `pcall deveria capturar a mensagem original do módulo, recebeu: {result.message}`)

	-- Erro TRATADO por pcall no próprio script -- não deveria ter gerado NENHUM OutputRecord de
	-- erro (nem duplicado, nem nenhum -- o script lidou com ele por conta própria).
	for _, record in harness.Records do
		assert(record.level ~= "error", `pcall no script deveria ter engolido o erro -- não esperava OutputRecord de erro, recebeu: {record.message}`)
	end
end)

--------------------------------------------------------------------------------------------------
-- CRITÉRIO ADICIONAL: task.spawn no CORPO de um módulo requerido gera exatamente 1 OutputRecord de
-- erro no Script que fez o require original (achado MÉDIO da revisão de task-runtime-025)
--------------------------------------------------------------------------------------------------

test("CRÍTICO: task.spawn(error(...)) no corpo de um módulo requerido gera exatamente 1 OutputRecord de erro no Script que fez o require original", function()
	local harness = newHarness("ServerScriptService.Main")

	local scriptInstance = Services.new("Script", "Main")
	scriptInstance.Parent = harness.Game:GetService("ServerScriptService")
	local scriptFullName = scriptInstance:GetFullName()

	-- ModuleLoader construído com o ScriptName/OnOutput do Script REAL de cima -- mesma coisa que
	-- RunCommand (task-cli-006) fará por Script antes de chamar Sandbox.Run.
	local records: { Runtime.OutputRecord } = {}
	local loader = ModuleLoader.new({
		Scheduler = harness.Scheduler,
		ScriptName = scriptFullName,
		OnOutput = function(record: Runtime.OutputRecord)
			table.insert(records, record)
		end,
		Cache = harness.Cache,
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = {},
		SharedTable = {},
	})

	local mod = newModule(harness, "SpawnsAndErrors", [[
		task.spawn(function()
			error("boom-in-module-spawn")
		end)
		return true
	]])

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = function(target: unknown): unknown
			return loader:Require(target)
		end,
	}
	local extraGlobals = ScriptEnvironment.Build(context, scriptInstance)
	extraGlobals.targetModule = mod

	Runtime.Sandbox.Run({
		scriptName = scriptFullName,
		source = [[ require(targetModule) ]],
		scheduler = harness.Scheduler,
		extraGlobals = extraGlobals,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 1, `esperava EXATAMENTE 1 OutputRecord de erro, recebeu {#records} (a lacuna que esta tarefa fecha: sem o override de task.spawn no ModuleLoader, este erro desapareceria sem gerar nenhum OutputRecord)`)
	assert(records[1].level == "error", "o único OutputRecord deveria ser level='error'")
	assert(records[1].scriptName == scriptFullName, `OutputRecord.scriptName deveria ser o Script que fez o require original ('{scriptFullName}'), recebeu '{tostring(records[1].scriptName)}'`)
	assert(string.find(records[1].message, "boom-in-module-spawn", 1, true) ~= nil, `mensagem deveria conter a causa original do erro dentro do task.spawn, recebeu: {records[1].message}`)
end)

test("CRÍTICO (variação): legado spawn(...) (não task.spawn) no corpo do módulo TAMBÉM é atribuído ao Script original", function()
	local harness = newHarness("ServerScriptService.Main")

	local scriptInstance = Services.new("Script", "Main")
	scriptInstance.Parent = harness.Game:GetService("ServerScriptService")
	local scriptFullName = scriptInstance:GetFullName()

	local records: { Runtime.OutputRecord } = {}
	local loader = ModuleLoader.new({
		Scheduler = harness.Scheduler,
		ScriptName = scriptFullName,
		OnOutput = function(record: Runtime.OutputRecord)
			table.insert(records, record)
		end,
		Cache = harness.Cache,
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = {},
		SharedTable = {},
	})

	local mod = newModule(harness, "LegacySpawnErrors", [[
		spawn(function()
			error("boom-in-legacy-spawn")
		end)
		return true
	]])

	local context: ScriptEnvironment.EnvironmentContext = {
		Game = harness.Game,
		Workspace = harness.Workspace,
		GlobalTable = {},
		SharedTable = {},
		Require = function(target: unknown): unknown
			return loader:Require(target)
		end,
	}
	local extraGlobals = ScriptEnvironment.Build(context, scriptInstance)
	extraGlobals.targetModule = mod

	Runtime.Sandbox.Run({
		scriptName = scriptFullName,
		source = [[ require(targetModule) ]],
		scheduler = harness.Scheduler,
		extraGlobals = extraGlobals,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 1, `esperava EXATAMENTE 1 OutputRecord (legado spawn() precisa do MESMO tratamento de task.spawn), recebeu {#records}`)
	assert(records[1].scriptName == scriptFullName, "OutputRecord.scriptName deveria ser o Script original mesmo para o global legado spawn()")
	assert(string.find(records[1].message, "boom-in-legacy-spawn", 1, true) ~= nil, "mensagem deveria conter a causa original")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
