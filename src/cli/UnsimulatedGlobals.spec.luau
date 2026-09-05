--!strict

--[[
	Teste da task-cli-005 (`UnsimulatedGlobals.luau`). Cobre o acceptance do board: acessar/gravar
	qualquer nome da lista fechada (Decisão 12) erra com o prefixo `[LuauBench]` nomeando a lacuna
	EXATA, nunca "attempt to index nil with 'new'" -- dentro de um `Sandbox.Run` de verdade, o
	mesmo jeito que um script real chamaria `Vector3.new(...)`.

	Roda com `lune run src/cli/UnsimulatedGlobals.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("../runtime/Scheduler")
local Sandbox = require("../runtime/Sandbox")
local UnsimulatedGlobals = require("./UnsimulatedGlobals")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Build() devolve as 23 entradas da lista fechada, nenhuma nil", function()
	local names = {
		"Vector3",
		"Vector2",
		"CFrame",
		"Color3",
		"UDim",
		"UDim2",
		"Rect",
		"Region3",
		"Ray",
		"NumberRange",
		"NumberSequence",
		"ColorSequence",
		"BrickColor",
		"TweenInfo",
		"PhysicalProperties",
		"Faces",
		"Axes",
		"Random",
		"DateTime",
		"Font",
		"RaycastParams",
		"OverlapParams",
		"Enum",
	}

	local globals = UnsimulatedGlobals.Build()
	assert(#names == 23, "sanity check: a lista do teste deveria ter as 23 entradas do desenho")
	for _, name in names do
		assert(globals[name] ~= nil, `UnsimulatedGlobals.Build() deveria conter uma entrada para '{name}'`)
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

test("acessar Vector3.new (via __index) erra com '[LuauBench]' nomeando 'Vector3', nunca 'attempt to index nil'", function()
	local globals = UnsimulatedGlobals.Build()
	local vector3 = (globals.Vector3 :: unknown) :: { new: unknown }

	local ok, err = pcall(function()
		return vector3.new
	end)

	assert(not ok, "indexar Vector3.new deveria erra")
	local message = tostring(err)
	assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {message}`)
	assert(string.find(message, "Vector3", 1, true) ~= nil, `mensagem deveria citar 'Vector3', recebeu: {message}`)
	assert(string.find(message, "not simulated", 1, true) ~= nil, `mensagem deveria seguir a família 'not simulated yet', recebeu: {message}`)
	assert(string.find(message, "index nil", 1, true) == nil, `mensagem NUNCA deveria ser o erro genérico 'attempt to index nil', recebeu: {message}`)
end)

test("gravar sobre um global não simulado (Enum.Foo = 1) também erra, nomeando 'Enum'", function()
	local globals = UnsimulatedGlobals.Build()
	local enumTable = (globals.Enum :: unknown) :: { [string]: unknown }

	local ok, err = pcall(function()
		enumTable.Foo = 1
	end)

	assert(not ok, "gravar sobre o global não simulado 'Enum' deveria errar")
	local message = tostring(err)
	assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {message}`)
	assert(string.find(message, "Enum", 1, true) ~= nil, `mensagem deveria citar 'Enum', recebeu: {message}`)
end)

test("dentro de um Sandbox.Run de verdade, Vector3.new(1, 2, 3) erra do mesmo jeito e é capturável por pcall", function()
	local scheduler = Scheduler.new()
	local captured: { ok: boolean, message: string }? = nil

	Sandbox.Run({
		scriptName = "Workspace.UnsimulatedFixture",
		source = [[
			local ok, err = pcall(function()
				return Vector3.new(1, 2, 3)
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
	assert(not result.ok, "Vector3.new(...) deveria ter falhado, capturável por pcall no script do usuário")
	assert(string.find(result.message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter o prefixo [LuauBench], recebeu: {result.message}`)
	assert(string.find(result.message, "Vector3", 1, true) ~= nil, `mensagem deveria citar 'Vector3', recebeu: {result.message}`)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
