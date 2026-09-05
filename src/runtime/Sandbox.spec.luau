--!strict

--[[
	Teste da task-runtime-006 (Sandbox: execução isolada de script de usuário). Cobre, na
	mesma tarefa da lógica que testa (regra 01): erro síncrono nunca derruba o processo e gera
	OutputRecord{level="error"} com scriptName/line corretos; erro dentro de um task.spawn
	interno ao script também é capturado pelo mesmo mecanismo (ThreadError); print/warn chegam
	em onOutput em vez de stdout cru do Lune; e que fs/net/process/serde/io/require são
	inalcançáveis dentro do sandbox, com o mesmo resultado de indexar uma tabela sem essa
	chave (nunca um nil "enganoso" via metatable/sentinel).

	Roda com `lune run src/runtime/Sandbox.spec.luau`.
]]

local process = require("@lune/process")
local Scheduler = require("./Scheduler")
local Sandbox = require("./Sandbox")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("erro síncrono no script nunca derruba o processo e gera OutputRecord de erro com scriptName correto", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	local result = Sandbox.Run({
		scriptName = "Workspace.Boom",
		source = [[
			error("deu ruim")
		]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(typeof(result.thread) == "thread", "SandboxResult.thread deveria ser uma thread real")
	assert(#records == 1, `esperava 1 OutputRecord, recebeu {#records}`)
	assert(records[1].level == "error", "nível deveria ser 'error'")
	assert(records[1].scriptName == "Workspace.Boom", "scriptName deveria ser o do script que errou")
	assert(string.find(records[1].message, "deu ruim") ~= nil, `mensagem deveria conter a causa original, recebeu: {records[1].message}`)
	assert(records[1].line ~= nil and records[1].line :: number > 0, "line deveria vir preenchida a partir do prefixo scriptName:line: do VM")

	-- Confirma que o processo/Scheduler continuam utilizáveis normalmente depois do erro.
	local stillWorks = false
	scheduler:Spawn(function()
		stillWorks = true
	end)
	assert(stillWorks, "scheduler deveria continuar funcionando normalmente após o erro do script")
end)

test("erro de compilação (source Luau inválido) também vira OutputRecord de erro, não derruba o processo", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	Sandbox.Run({
		scriptName = "Workspace.Invalido",
		source = "this is not )( valid luau {{{",
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 1, `esperava 1 OutputRecord de erro de compilação, recebeu {#records}`)
	assert(records[1].level == "error", "erro de compilação também deve ser level='error'")
end)

test("erro dentro de um task.spawn interno ao script é capturado pelo mesmo mecanismo (ThreadError)", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	Sandbox.Run({
		scriptName = "Workspace.SpawnInterno",
		source = [[
			task.spawn(function()
				error("erro dentro do spawn interno")
			end)
		]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 1, `esperava 1 OutputRecord vindo do task.spawn interno, recebeu {#records}`)
	assert(records[1].level == "error", "nível deveria ser 'error'")
	assert(records[1].scriptName == "Workspace.SpawnInterno", "scriptName deveria ser identificado corretamente mesmo vindo de uma thread aninhada")
	assert(string.find(records[1].message, "erro dentro do spawn interno") ~= nil, "mensagem deveria conter a causa original do spawn interno")
end)

test("print/warn chegam em onOutput em vez de stdout cru do Lune", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	Sandbox.Run({
		scriptName = "Workspace.Logs",
		source = [[
			print("ola", "mundo")
			warn("cuidado")
		]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 2, `esperava 2 OutputRecords (print + warn), recebeu {#records}`)
	assert(records[1].level == "print", "primeiro deveria ser print")
	assert(records[1].message == "ola\tmundo", `print deveria concatenar argumentos com tab, recebeu: {records[1].message}`)
	assert(records[1].scriptName == "Workspace.Logs", "print deveria carregar o scriptName")
	assert(records[2].level == "warn", "segundo deveria ser warn")
	assert(records[2].message == "cuidado", "warn deveria carregar a mensagem exata")
end)

test("script não alcança fs/net/process/serde/io/require -- mesmo resultado de indexar uma tabela sem essa chave", function()
	local scheduler = Scheduler.new()
	local captured: { [string]: string }? = nil

	-- Anotado explicitamente como `Sandbox.SandboxGlobals` (`{ [string]: unknown }`): um valor
	-- concretamente tipado (a função `report` abaixo) atribuído a um slot já declarado como
	-- `unknown` é sempre permitido -- diferente de passar um literal com campo concreto
	-- diretamente onde `SandboxOptions` é esperado, que o checker do Luau valida "exatamente"
	-- e rejeita (verificado com luau-lsp).
	local extra: Sandbox.SandboxGlobals = {
		report = function(fields: { [string]: string })
			captured = fields
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.SemFsNemNet2",
		source = [[
			local emptyControl = {}
			report({
				fs = typeof(fs),
				net = typeof(net),
				process = typeof(process),
				serde = typeof(serde),
				io = typeof(io),
				require = typeof(require),
				-- Mesmo tipo ("nil") que indexar uma chave ausente de uma tabela comum --
				-- não existe nenhum sentinel/metatable especial diferenciando os dois casos.
				controlEmptyTableKey = typeof(emptyControl.qualquerCoisaQueNaoExiste),
			})
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter chamado report() com sucesso")
	local fields = captured :: { [string]: string }
	assert(fields.fs == "nil", `fs deveria ser inalcançável (typeof nil), recebeu {fields.fs}`)
	assert(fields.net == "nil", `net deveria ser inalcançável (typeof nil), recebeu {fields.net}`)
	assert(fields.process == "nil", `process deveria ser inalcançável (typeof nil), recebeu {fields.process}`)
	assert(fields.serde == "nil", `serde deveria ser inalcançável (typeof nil), recebeu {fields.serde}`)
	assert(fields.io == "nil", `io deveria ser inalcançável (typeof nil), recebeu {fields.io}`)
	assert(fields.require == "nil", `require deveria ser inalcançável (typeof nil), recebeu {fields.require}`)
	assert(fields.fs == fields.controlEmptyTableKey, "indexar um global ausente deve dar exatamente o mesmo resultado que indexar uma chave ausente de tabela comum")
end)

test("extraGlobals é mesclado por cima da whitelist fixa (ex.: injeta game/workspace simulados)", function()
	local scheduler = Scheduler.new()
	local sawGame = false

	local extra: Sandbox.SandboxGlobals = {
		game = { fake = true },
		report = function(value: string)
			sawGame = (value == "table")
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.ComExtra",
		source = [[
			report(typeof(game))
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(sawGame, "extraGlobals.game deveria estar acessível dentro do script como uma tabela")
end)

test("erro dentro de dois scripts rodando no mesmo Scheduler não vaza scriptName de um pro outro", function()
	local scheduler = Scheduler.new()
	local recordsA: { Sandbox.OutputRecord } = {}
	local recordsB: { Sandbox.OutputRecord } = {}

	Sandbox.Run({
		scriptName = "Workspace.ScriptA",
		source = [[ error("erro do A") ]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(recordsA, record)
		end,
	})

	Sandbox.Run({
		scriptName = "Workspace.ScriptB",
		source = [[ error("erro do B") ]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(recordsB, record)
		end,
	})

	assert(#recordsA == 1 and recordsA[1].scriptName == "Workspace.ScriptA", "onOutput de A só deveria ver o erro de A")
	assert(#recordsB == 1 and recordsB[1].scriptName == "Workspace.ScriptB", "onOutput de B só deveria ver o erro de B")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
