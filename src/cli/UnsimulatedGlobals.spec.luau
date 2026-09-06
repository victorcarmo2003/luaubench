--!strict

--[[
	Teste da task-cli-005 (`UnsimulatedGlobals.luau`), REVISADO por task-cli-025 (arquiteto-
	valuetypes-2026-09-05.md, seção 3.4 "cli", item (d)). Cobre o acceptance do board: acessar/
	gravar qualquer nome da lista erra com o prefixo `[LuauBench]` nomeando a lacuna EXATA, nunca
	"attempt to index nil with 'new'" -- dentro de um `Sandbox.Run` de verdade, o mesmo jeito que um
	script real chamaria `TweenInfo.new(...)`; e o acceptance NOVO desta tarefa: a lista é DERIVADA
	de `ValueTypes.Catalog.UnsimulatedGlobalNames()`, e nunca lista um nome que o Catalog já diz
	`Simulated = true` (Vector3/Vector2/Color3/CFrame/UDim/UDim2/Enum, leva 1 de `valuetypes`).

	Antes desta tarefa, este arquivo hardcodava as 23 strings da Decisão 12 (incluindo Vector3/
	CFrame/Color3/UDim/UDim2/Enum) e testava que TODAS erravam como sentinela -- isso deixou de ser
	verdade: essas 6 (+Enum) agora são globais REAIS (ver `ScriptEnvironment.spec.luau`, que cobre
	o lado "funciona de verdade"). Os testes que continuam precisando de UM nome concreto usam
	"TweenInfo"/"Rect" -- ainda `Simulated = false` em `Catalog.luau` nesta leva -- em vez de
	hardcodar a lista inteira.

	Roda com `lune run src/cli/UnsimulatedGlobals.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("../runtime/Scheduler")
local Sandbox = require("../runtime/Sandbox")
local ValueTypes = require("../valuetypes")
local UnsimulatedGlobals = require("./UnsimulatedGlobals")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Build() é EXATAMENTE derivado de ValueTypes.Catalog.UnsimulatedGlobalNames() -- mesmo conjunto de chaves, nenhuma a mais/a menos (task-cli-025)", function()
	local expectedNames = ValueTypes.Catalog.UnsimulatedGlobalNames()
	local expectedSet: { [string]: boolean } = {}
	for _, name in expectedNames do
		expectedSet[name] = true
	end

	local globals = UnsimulatedGlobals.Build()

	local actualCount = 0
	for name in globals do
		actualCount += 1
		assert(expectedSet[name] == true, `UnsimulatedGlobals.Build() devolveu a chave '{name}', que Catalog.UnsimulatedGlobalNames() não lista`)
	end
	assert(actualCount == #expectedNames, `UnsimulatedGlobals.Build() deveria ter exatamente {#expectedNames} entradas (o tamanho de Catalog.UnsimulatedGlobalNames()), achou {actualCount}`)

	for _, name in expectedNames do
		assert(globals[name] ~= nil, `UnsimulatedGlobals.Build() deveria conter uma entrada para '{name}' (Catalog diz Simulated=false, HasGlobalConstructor=true)`)
	end
end)

test("Build() NUNCA lista um nome que o Catalog já diz Simulated=true (task-cli-025, item d)", function()
	local simulatedNames = ValueTypes.Catalog.SimulatedNames()
	-- sanity check: esta asserção só é significativa se o Catalog de fato marcar algo como
	-- simulado nesta altura do projeto (leva 1 de valuetypes já entregou Vector3/Vector2/Color3/
	-- CFrame/UDim/UDim2/Enum) -- um `#simulatedNames == 0` tornaria o teste abaixo vazio de
	-- conteúdo.
	assert(#simulatedNames > 0, "sanity check: Catalog deveria ter ao menos um nome Simulated=true nesta altura do projeto (Vector3 e companhia)")

	local globals = UnsimulatedGlobals.Build()
	for _, name in simulatedNames do
		assert(globals[name] == nil, `UnsimulatedGlobals.Build() NÃO deveria conter '{name}' -- Catalog.luau já diz Simulated=true (deveria virar global REAL via ValueTypes.BuildGlobals, não sentinela)`)
	end
end)

test("Build() devolve uma tabela NOVA a cada chamada (mutar o resultado de uma chamada não afeta outra)", function()
	local first = UnsimulatedGlobals.Build()
	local second = UnsimulatedGlobals.Build()
	assert(first ~= second, "duas chamadas a Build() deveriam devolver tabelas OUTER distintas")

	-- Mutar a primeira (como ScriptEnvironment.Build faz, sobrepondo game/workspace/script/...)
	-- não pode vazar pra segunda -- cada Script/ModuleScript precisa da sua própria tabela base.
	-- `Build()` já devolve `{ [string]: unknown }` -- sem cast nenhum necessário aqui.
	first.game = "fake"
	assert(second.game == nil, "mutar o resultado de uma chamada a Build() não deveria afetar outra chamada")
end)

test("acessar TweenInfo.new (via __index) erra com '[LuauBench]' nomeando 'TweenInfo', nunca 'attempt to index nil'", function()
	local globals = UnsimulatedGlobals.Build()
	local tweenInfo = (globals.TweenInfo :: unknown) :: { new: unknown }

	local ok, err = pcall(function()
		return tweenInfo.new
	end)

	assert(not ok, "indexar TweenInfo.new deveria errar")
	local message = tostring(err)
	assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {message}`)
	assert(string.find(message, "TweenInfo", 1, true) ~= nil, `mensagem deveria citar 'TweenInfo', recebeu: {message}`)
	assert(string.find(message, "not simulated", 1, true) ~= nil, `mensagem deveria seguir a família 'not simulated yet', recebeu: {message}`)
	assert(string.find(message, "index nil", 1, true) == nil, `mensagem NUNCA deveria ser o erro genérico 'attempt to index nil', recebeu: {message}`)
end)

test("gravar sobre um global não simulado (Rect.Foo = 1) também erra, nomeando 'Rect'", function()
	local globals = UnsimulatedGlobals.Build()
	local rectTable = (globals.Rect :: unknown) :: { [string]: unknown }

	local ok, err = pcall(function()
		rectTable.Foo = 1
	end)

	assert(not ok, "gravar sobre o global não simulado 'Rect' deveria errar")
	local message = tostring(err)
	assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {message}`)
	assert(string.find(message, "Rect", 1, true) ~= nil, `mensagem deveria citar 'Rect', recebeu: {message}`)
end)

test("dentro de um Sandbox.Run de verdade, TweenInfo.new(1) erra do mesmo jeito e é capturável por pcall", function()
	local scheduler = Scheduler.new()
	local captured: { ok: boolean, message: string }? = nil

	Sandbox.Run({
		scriptName = "Workspace.UnsimulatedFixture",
		source = [[
			local ok, err = pcall(function()
				return TweenInfo.new(1)
			end)
			report(ok, tostring(err))
		]],
		scheduler = scheduler,
		extraGlobals = (function()
			local extra = UnsimulatedGlobals.Build()
			extra.report = function(ok: boolean, message: string)
				captured = { ok = ok, message = message }
			end
			return extra
		end)(),
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado e chamado report()")
	local result = captured :: { ok: boolean, message: string }
	assert(not result.ok, "TweenInfo.new(...) deveria ter falhado, capturável por pcall no script do usuário")
	assert(string.find(result.message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {result.message}`)
	assert(string.find(result.message, "TweenInfo", 1, true) ~= nil, `mensagem deveria citar 'TweenInfo', recebeu: {result.message}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
