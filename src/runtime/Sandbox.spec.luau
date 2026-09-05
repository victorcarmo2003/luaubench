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
local InstanceModule = require("./Instance")
local SignalModule = require("./Signal")
local TypeNameResolverModule = require("./TypeNameResolver")

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

--[[
	Testes da task-runtime-026 (completar a whitelist de globals do Sandbox). Desenho em
	.claude/agents-memory/arquiteto-cli-2026-09-05.md, Decisão 12.
]]

test("fixture com setmetatable/__index (padrão OOP real do ecossistema Roblox, ex.: ProfileStore) roda dentro do Sandbox", function()
	local scheduler = Scheduler.new()
	local captured: { count: number, name: string }? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(count: number, name: string)
			captured = { count = count, name = name }
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.OopFixture",
		source = [[
			-- Mesmo padrão de classe usado por ProfileStore/state managers reais: setmetatable
			-- + __index simulando herança de métodos -- exatamente o caso de uso central citado
			-- no CLAUDE.md que a whitelist antiga (sem setmetatable) bloqueava por completo.
			local Counter = {}
			Counter.__index = Counter

			function Counter.new(name)
				return setmetatable({ name = name, count = 0 }, Counter)
			end

			function Counter:increment()
				self.count += 1
				return self.count
			end

			local counter = Counter.new("Combat")
			counter:increment()
			counter:increment()
			local finalCount = counter:increment()

			report(finalCount, counter.name)
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado o fixture OOP e chamado report()")
	local result = captured :: { count: number, name: string }
	assert(result.count == 3, `increment() via metatable deveria acumular estado real, recebeu {result.count}`)
	assert(result.name == "Combat", "self.name deveria estar acessível através de __index")
end)

test("getmetatable/rawget/rawset/rawequal/rawlen/newproxy/buffer disponíveis e funcionalmente corretos", function()
	local scheduler = Scheduler.new()
	local captured: { [string]: unknown }? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(fields: { [string]: unknown })
			captured = fields
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.RawFamily",
		source = [[
			local target = setmetatable({}, { __index = function() return "via-metamethod" end })

			-- getmetatable devolve a metatable real (não travada nesta task -- ver RISCO
			-- RESIDUAL DECLARADO no cabeçalho de Sandbox.luau).
			local mt = getmetatable(target)

			-- rawset grava direto; rawget deveria IGNORAR __index (diferente de indexar
			-- `target.missing` normalmente, que passa pelo metamétodo).
			rawset(target, "direct", "raw-value")

			local b = buffer.create(4)
			buffer.writeu8(b, 0, 65)

			report({
				metatableType = typeof(mt),
				metatableIsPresent = mt ~= nil,
				indexedViaMetamethod = target.missing,
				rawGetBypassesMetamethod = rawget(target, "missing"),
				rawGetSeesDirectWrite = rawget(target, "direct"),
				rawEqualSelf = rawequal(target, target),
				rawEqualOther = rawequal(target, {}),
				rawLenOfArray = rawlen({ 1, 2, 3 }),
				proxyType = typeof(newproxy(true)),
				bufferReadback = buffer.readu8(b, 0),
			})
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado e chamado report()")
	local fields = captured :: { [string]: unknown }
	assert(fields.metatableType == "table", "getmetatable deveria devolver a metatable real (table)")
	assert(fields.metatableIsPresent == true, "getmetatable não deveria devolver nil para uma tabela com metatable")
	assert(fields.indexedViaMetamethod == "via-metamethod", "indexação normal deveria passar pelo __index")
	assert(fields.rawGetBypassesMetamethod == nil, "rawget deveria ignorar __index e devolver nil de verdade")
	assert(fields.rawGetSeesDirectWrite == "raw-value", "rawget deveria enxergar o valor gravado por rawset")
	assert(fields.rawEqualSelf == true, "rawequal(x, x) deveria ser true")
	assert(fields.rawEqualOther == false, "rawequal(x, y) para tabelas distintas deveria ser false")
	assert(fields.rawLenOfArray == 3, "rawlen de um array de 3 elementos deveria ser 3")
	assert(fields.proxyType == "userdata", "newproxy(true) deveria devolver userdata")
	assert(fields.bufferReadback == 65, "buffer.readu8 deveria ler de volta o byte escrito por buffer.writeu8")
end)

test("os.date/os.difftime disponíveis; os.getenv/os.exit/os.remove/os.rename/os.tmpname ausentes", function()
	local scheduler = Scheduler.new()
	local captured: { [string]: unknown }? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(fields: { [string]: unknown })
			captured = fields
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.OsFamily",
		source = [[
			report({
				dateType = typeof(os.date),
				difftimeType = typeof(os.difftime),
				dateResultType = typeof(os.date("*t", os.time())),
				difftimeResult = os.difftime(100, 40),
				getenvType = typeof(os.getenv),
				exitType = typeof(os.exit),
				removeType = typeof(os.remove),
				renameType = typeof(os.rename),
				tmpnameType = typeof(os.tmpname),
			})
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado e chamado report()")
	local fields = captured :: { [string]: unknown }
	assert(fields.dateType == "function", "os.date deveria estar disponível")
	assert(fields.difftimeType == "function", "os.difftime deveria estar disponível")
	assert(fields.dateResultType == "table", "os.date('*t', ...) deveria devolver uma tabela de campos de data")
	assert(fields.difftimeResult == 60, `os.difftime(100, 40) deveria devolver 60, recebeu {fields.difftimeResult}`)
	assert(fields.getenvType == "nil", "os.getenv NÃO deveria estar disponível (vazaria variável de ambiente do host)")
	assert(fields.exitType == "nil", "os.exit NÃO deveria estar disponível (derrubaria o processo host)")
	assert(fields.removeType == "nil", "os.remove NÃO deveria estar disponível (tocaria filesystem do host)")
	assert(fields.renameType == "nil", "os.rename NÃO deveria estar disponível (tocaria filesystem do host)")
	assert(fields.tmpnameType == "nil", "os.tmpname NÃO deveria estar disponível (tocaria filesystem do host)")
end)

test("wait/spawn/delay/tick/time disponíveis e roteiam pelo Scheduler (StepOnce determinístico, nunca sleep de SO)", function()
	local scheduler = Scheduler.new()
	local types: { [string]: unknown }? = nil
	local clocks: { tick: unknown, time: unknown }? = nil
	local spawnRan = false
	local delayRan = false
	local waitCompleted = false
	local waitElapsed: number? = nil

	local extra: Sandbox.SandboxGlobals = {
		reportTypes = function(fields: { [string]: unknown })
			types = fields
		end,
		reportClocks = function(tickValue: number, timeValue: number)
			clocks = { tick = tickValue, time = timeValue }
		end,
		onSpawnRan = function()
			spawnRan = true
		end,
		onDelayRan = function()
			delayRan = true
		end,
		reportWaitElapsed = function(elapsed: number)
			waitCompleted = true
			waitElapsed = elapsed
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.LegacyGlobals",
		source = [[
			reportTypes({
				wait = typeof(wait),
				spawn = typeof(spawn),
				delay = typeof(delay),
				tick = typeof(tick),
				time = typeof(time),
			})

			reportClocks(tick(), time())

			-- spawn/delay precisam rotear pelo MESMO Scheduler que task.spawn/task.delay usam
			-- (nunca @lune/task cru) -- ver comentário em Sandbox.luau: são aliases 1:1.
			spawn(function()
				onSpawnRan()
			end)

			delay(0.03, function()
				onDelayRan()
			end)

			local elapsed = wait(0.05)
			reportWaitElapsed(elapsed)
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(types ~= nil, "o script deveria ter reportado os typeof antes de chegar no wait")
	local fields = types :: { [string]: unknown }
	assert(fields.wait == "function", "wait deveria estar disponível")
	assert(fields.spawn == "function", "spawn deveria estar disponível")
	assert(fields.delay == "function", "delay deveria estar disponível")
	assert(fields.tick == "function", "tick deveria estar disponível")
	assert(fields.time == "function", "time deveria estar disponível")

	assert(clocks ~= nil, "tick()/time() deveriam ter sido chamados com sucesso")
	local clockFields = clocks :: { tick: unknown, time: unknown }
	assert(typeof(clockFields.tick) == "number", "tick() deveria devolver um number")
	assert(typeof(clockFields.time) == "number", "time() deveria devolver um number")

	-- `spawn` (alias 1:1 de task.spawn) roda de forma síncrona até o primeiro yield -- já
	-- deveria ter rodado antes mesmo do primeiro StepOnce.
	assert(spawnRan, "spawn(...) deveria rodar de forma síncrona, igual a task.spawn")

	assert(not delayRan, "delay(0.03, ...) não deveria ter rodado antes de nenhum StepOnce")
	assert(not waitCompleted, "wait(0.05) não deveria ter resolvido antes de nenhum StepOnce (nunca sleep de SO)")

	scheduler:StepOnce(0.02)
	assert(not delayRan, "0.02s acumulados ainda não deveria ser suficiente para delay(0.03, ...)")
	assert(not waitCompleted, "0.02s acumulados ainda não deveria ser suficiente para wait(0.05)")

	scheduler:StepOnce(0.02)
	assert(delayRan, "0.04s acumulados deveria ter disparado delay(0.03, ...) via StepOnce do Scheduler")
	assert(not waitCompleted, "0.04s acumulados ainda não deveria ser suficiente para wait(0.05)")

	scheduler:StepOnce(0.02)
	assert(waitCompleted, "0.06s acumulados deveria ter resolvido wait(0.05) via StepOnce do Scheduler, não sleep de SO")
	assert(waitElapsed ~= nil and (waitElapsed :: number) > 0, "wait(0.05) deveria devolver o tempo decorrido (roteado por Scheduler:Wait)")
end)

test("regressão de isolamento: fs/net/process/serde/io/require continuam ausentes mesmo com a whitelist expandida", function()
	local scheduler = Scheduler.new()
	local captured: { [string]: string }? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(fields: { [string]: string })
			captured = fields
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.RegressaoIsolamento",
		source = [[
			report({
				fs = typeof(fs),
				net = typeof(net),
				process = typeof(process),
				serde = typeof(serde),
				io = typeof(io),
				require = typeof(require),
				debug = typeof(debug),
			})
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado e chamado report()")
	local fields = captured :: { [string]: string }
	assert(fields.fs == "nil", "fs continua inalcançável")
	assert(fields.net == "nil", "net continua inalcançável")
	assert(fields.process == "nil", "process continua inalcançável")
	assert(fields.serde == "nil", "serde continua inalcançável")
	assert(fields.io == "nil", "io continua inalcançável")
	assert(fields.require == "nil", "require continua inalcançável")
	assert(fields.debug == "nil", "debug fica deliberadamente fora desta tarefa (Decisão 12)")
end)

test("unpack disponível e funcionalmente correto (confirmado por task-cli-007: global de primeira classe no Roblox real, não depreciado)", function()
	local scheduler = Scheduler.new()
	local captured: { a: unknown, b: unknown, c: unknown }? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(a: unknown, b: unknown, c: unknown)
			captured = { a = a, b = b, c = c }
		end,
	}

	Sandbox.Run({
		scriptName = "Workspace.Unpack",
		source = [[
			report(unpack({ "x", "y", "z" }))
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(captured ~= nil, "o script deveria ter completado e chamado report()")
	local fields = captured :: { a: unknown, b: unknown, c: unknown }
	assert(fields.a == "x" and fields.b == "y" and fields.c == "z", "unpack deveria expandir os três elementos do array na ordem certa")
end)

--[[
	Testes da task-runtime-025 (Sandbox.Load: compilar um chunk sem criar thread). Desenho em
	.claude/agents-memory/arquiteto-cli-2026-09-05.md, Decisão 5.
]]

test("Sandbox.Load não cria thread -- o chunk roda na MESMA coroutine que o chamou", function()
	local scheduler = Scheduler.new()
	local innerThreadRef: thread? = nil

	local extra: Sandbox.SandboxGlobals = {
		report = function(co: thread)
			innerThreadRef = co
		end,
	}

	local chunkFn = Sandbox.Load({
		scriptName = "Modules.ThreadIdentity",
		source = [[
			report(coroutine.running())
			return true
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(_record) end,
	})

	assert(typeof(chunkFn) == "function", "Sandbox.Load deveria devolver a função do chunk, não uma thread")

	local outerThreadRef = coroutine.running()
	chunkFn()

	assert(
		innerThreadRef == outerThreadRef,
		"o chunk carregado por Sandbox.Load deveria rodar na MESMA coroutine que o chamou -- nenhuma thread nova deveria ter sido criada"
	)
end)

test("Sandbox.Load usa a MESMA whitelist de Sandbox.Run (fs/net/process/serde/io/require ausentes; setmetatable disponível)", function()
	local scheduler = Scheduler.new()

	local chunkFn = Sandbox.Load({
		scriptName = "Modules.WhitelistParity",
		source = [[
			-- setmetatable presente confirma que é a MESMA buildEnvironment de Sandbox.Run (com a
			-- whitelist completada por task-runtime-026), nunca uma segunda cópia reduzida.
			local proxied = setmetatable({}, { __index = function() return "via-metamethod" end })
			return {
				fs = typeof(fs),
				net = typeof(net),
				process = typeof(process),
				serde = typeof(serde),
				io = typeof(io),
				require = typeof(require),
				setmetatableType = typeof(setmetatable),
				proxiedValue = proxied.anything,
			}
		]],
		scheduler = scheduler,
		onOutput = function(_record) end,
	})

	local moduleResult = chunkFn()
	local fields = moduleResult :: { [string]: unknown }
	assert(fields.fs == "nil", "fs deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.net == "nil", "net deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.process == "nil", "process deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.serde == "nil", "serde deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.io == "nil", "io deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.require == "nil", "require (cru do Lune) deveria continuar inalcançável dentro de um chunk carregado por Sandbox.Load")
	assert(fields.setmetatableType == "function", "setmetatable deveria estar disponível -- mesma whitelist completa de Sandbox.Run")
	assert(fields.proxiedValue == "via-metamethod", "setmetatable/__index deveria funcionar de ponta a ponta dentro do chunk")
end)

test("chamar o chunk devolve o valor de retorno do módulo", function()
	local scheduler = Scheduler.new()

	local chunkFn = Sandbox.Load({
		scriptName = "Modules.ReturnValue",
		source = [[
			local Module = { greeting = "hello", count = 42 }
			return Module
		]],
		scheduler = scheduler,
		onOutput = function(_record) end,
	})

	local result = chunkFn()
	local moduleTable = result :: { greeting: string, count: number }
	assert(moduleTable.greeting == "hello", "o valor devolvido pelo chunk deveria ser exatamente o que o módulo retornou")
	assert(moduleTable.count == 42, "o valor devolvido pelo chunk deveria ser exatamente o que o módulo retornou")
end)

test("erro de EXECUÇÃO dentro do chunk propaga para o chamador via pcall e NÃO vira OutputRecord duplicado", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	local chunkFn = Sandbox.Load({
		scriptName = "Modules.RequireErra",
		source = [[ error("erro dentro do modulo requerido") ]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	local ok, err = pcall(chunkFn)

	assert(not ok, "o erro dentro do chunk deveria propagar via retorno de pcall, nunca ser engolido")
	assert(string.find(tostring(err), "erro dentro do modulo requerido") ~= nil, `pcall deveria capturar a mensagem original, recebeu: {tostring(err)}`)
	assert(#records == 0, `Sandbox.Load não se inscreve em ThreadError -- não deveria ter gerado nenhum OutputRecord, recebeu {#records}`)
end)

test("erro de COMPILAÇÃO (source Luau inválido) propaga direto do próprio Sandbox.Load via pcall, nunca vira OutputRecord", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	local ok, err = pcall(function()
		return Sandbox.Load({
			scriptName = "Modules.CompilacaoInvalida",
			source = "this is not )( valid luau {{{",
			scheduler = scheduler,
			onOutput = function(record)
				table.insert(records, record)
			end,
		})
	end)

	assert(not ok, "Sandbox.Load deveria propagar erro de compilação como erro Lua direto, capturável por pcall em volta da própria chamada")
	assert(tostring(err) ~= "", "a mensagem de erro de compilação não deveria vir vazia")
	assert(#records == 0, "erro de compilação em Sandbox.Load não deveria gerar nenhum OutputRecord")
end)

test("task.wait no topo de um chunk carregado por Sandbox.Load suspende a thread CHAMADORA (cooperativo via Scheduler, nunca sleep de SO)", function()
	local scheduler = Scheduler.new()
	local waitCompleted = false
	local resultValue: string? = nil

	local chunkFn = Sandbox.Load({
		scriptName = "Modules.WaitTopLevel",
		source = [[
			task.wait(0.05)
			return "done-after-wait"
		]],
		scheduler = scheduler,
		onOutput = function(_record) end,
	})

	-- Chama o chunk DENTRO de uma thread gerida pelo Scheduler -- é o que Sandbox.Load promete
	-- (rodar na thread chamadora): se `task.wait` no topo do módulo criasse/suspendesse uma
	-- thread própria em vez da corrente, esta atribuição a `resultValue`/`waitCompleted` só
	-- aconteceria depois, sem depender do StepOnce abaixo.
	scheduler:Spawn(function()
		-- `chunkFn()` devolve `...unknown` (tipo público de `Sandbox.Load`) -- estreitado aqui
		-- com um único cast (a origem já é `unknown`, não `any`), só para a asserção abaixo.
		resultValue = chunkFn() :: string?
		waitCompleted = true
	end)

	assert(not waitCompleted, "task.wait no topo do módulo deveria ter suspendido a thread chamadora imediatamente, antes de qualquer StepOnce")

	scheduler:StepOnce(0.06)

	assert(waitCompleted, "StepOnce deveria ter retomado a MESMA thread chamadora depois do task.wait, via Scheduler (nunca sleep de SO)")
	assert(resultValue == "done-after-wait", "chunkFn() deveria devolver o valor do módulo depois de retomar do task.wait")
end)

test("Sandbox.Run continua com o comportamento de hoje -- Sandbox.Load não introduz regressão (repete o cenário de erro síncrono de Sandbox.Run)", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	local result = Sandbox.Run({
		scriptName = "Workspace.RegressaoRun",
		source = [[ error("ainda funciona") ]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(typeof(result.thread) == "thread", "Sandbox.Run continua devolvendo { thread: thread }")
	assert(#records == 1, `Sandbox.Run deveria continuar reportando exatamente 1 OutputRecord de erro, recebeu {#records}`)
	assert(records[1].level == "error", "Sandbox.Run deveria continuar reportando nível 'error'")
	assert(records[1].scriptName == "Workspace.RegressaoRun", "Sandbox.Run deveria continuar identificando o scriptName corretamente")
end)

-- task-runtime-032: ver bloco "task-runtime-032" no cabeçalho do módulo e Decisão 4 do desenho
-- de arquitetura de Value Types simulados. IMPORTANTE: `TypeNameResolverModule.Set` é estado
-- global mutável de PROCESSO (mesma invariante de UnknownClassResolver -- sem Reset/Unset) --
-- por isso o teste "sem resolvedor instalado" abaixo roda ANTES do teste que instala um
-- resolvedor, nesta mesma ordem, neste mesmo arquivo (cada `lune run` é um processo isolado dos
-- outros arquivos de spec, mas não dos outros testes DESTE arquivo).
test("typeof: Instance/Signal/Connection resolvem para os nomes reais do Roblox mesmo sem nenhum resolvedor de Value Types instalado (task-runtime-032, passos 1-3 e fallback nativo)", function()
	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	local realInstance = InstanceModule.NewBase("Folder", "Injected")
	local realSignal = SignalModule.new()
	local realConnection = realSignal:Connect(function() end)

	-- Tipado explicitamente como `Sandbox.SandboxGlobals` ANTES de passar para `Sandbox.Run` --
	-- mesmo padrão do teste "extraGlobals é mesclado por cima da whitelist fixa", acima: um
	-- literal inline aqui faria o checker tentar unificar estruturalmente contra os tipos
	-- recursivos de Signal/Connection em vez de simplesmente aceitar `unknown`.
	local extra: Sandbox.SandboxGlobals = {
		injectedInstance = realInstance,
		injectedSignal = realSignal,
		injectedConnection = realConnection,
	}

	Sandbox.Run({
		scriptName = "Workspace.TypeofFidelidade",
		source = [[
			print(typeof(injectedInstance))
			print(typeof(injectedSignal))
			print(typeof(injectedConnection))
			print(typeof(5))
			print(typeof("oi"))
			print(typeof(nil))
			print(typeof({}))
		]],
		scheduler = scheduler,
		extraGlobals = extra,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 7, `esperava 7 linhas de print, recebeu {#records}`)
	assert(records[1].message == "Instance", `typeof(Instance) deveria ser "Instance", recebeu {records[1].message}`)
	assert(records[2].message == "RBXScriptSignal", `typeof(Signal) deveria ser "RBXScriptSignal", recebeu {records[2].message}`)
	assert(records[3].message == "RBXScriptConnection", `typeof(Connection) deveria ser "RBXScriptConnection", recebeu {records[3].message}`)
	assert(records[4].message == "number", "typeof(5) deveria continuar 'number' (fallback nativo)")
	assert(records[5].message == "string", "typeof(\"oi\") deveria continuar 'string' (fallback nativo)")
	assert(records[6].message == "nil", "typeof(nil) deveria continuar 'nil' (fallback nativo)")
	assert(records[7].message == "table", "typeof({}) deveria continuar 'table' (fallback nativo -- não é Instance/Signal/Connection nossa)")

	realInstance:Destroy()
end)

test("typeof: resolvedor de Value Types injetado responde para o que reconhece e o resto continua caindo no nativo (task-runtime-032, passo 4 e Decisão 4)", function()
	TypeNameResolverModule.Set(function(value: unknown): string?
		if value == "marcador-vector3" then
			return "Vector3"
		end
		return nil
	end)

	local scheduler = Scheduler.new()
	local records: { Sandbox.OutputRecord } = {}

	Sandbox.Run({
		scriptName = "Workspace.TypeofResolvedorInjetado",
		source = [[
			print(typeof("marcador-vector3"))
			print(typeof(5))
			print(typeof("outra string qualquer"))
		]],
		scheduler = scheduler,
		onOutput = function(record)
			table.insert(records, record)
		end,
	})

	assert(#records == 3, `esperava 3 linhas de print, recebeu {#records}`)
	assert(records[1].message == "Vector3", "typeof deveria devolver o nome que o resolvedor de Value Types injetado reconheceu")
	assert(records[2].message == "number", "typeof(5) deveria continuar 'number' mesmo com um resolvedor instalado -- Resolve devolve nil para o que ele não reconhece, e o wrapper cai no nativo")
	assert(records[3].message == "string", "idem para uma string que o resolvedor instalado não reconhece")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
