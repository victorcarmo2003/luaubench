--!strict

--[[
	Sandbox de execução de Script/LocalScript/ModuleScript do usuário: carrega e roda o
	`Source` como UMA thread gerida pelo `Scheduler` (nunca `coroutine.resume` solto fora
	dele), com uma whitelist fixa de globals — nunca `fs`/`net`/`process`/`serde`/`io`/
	`require` crus do Lune.

	Contrato congelado em .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção
	"Sandbox.luau".

	Mecanismo de isolamento de globals: `@lune/luau`'s `luau.load(source, loadOptions)` com
	`loadOptions.environment` (tabela de ambiente customizada) e `loadOptions.injectGlobals =
	false`. API exata (assinatura de `LoadOptions`, comportamento de `injectGlobals`,
	confirmação de que `getfenv`/`setfenv` não são um caminho viável) confirmada em
	.claude/agents-memory/pesquisa-sandbox-globals-lune-2026-09-04.md — ler antes de mexer
	neste arquivo. Pontos-chave dessa pesquisa que este módulo depende:

	- `injectGlobals = false` é o que garante que NENHUM global padrão do Lune (incluindo
	  `require`, que abriria `require("@lune/fs")`/`@lune/process`/etc.) vaza para dentro do
	  chunk — sem isso, o isolamento não existe. É o ponto mais fácil de errar (pesquisa,
	  seção "Limites e pegadinhas"), por isso fica marcado explicitamente aqui também.
	- A tabela passada em `environment` é COPIADA chave-a-chave pelo Lune para uma tabela nova
	  interna — mutar `environment` depois de chamar `luau.load` não afeta o chunk já
	  carregado (não fazemos isso aqui, mas vale documentar).
	- `debugName` vira o "chunkname" usado pelo VM do Luau ao formatar mensagens de erro —
	  para um chunk carregado de código-fonte (não de arquivo), isso aparece como
	  `[string "debugName"]:line: mensagem`. Usamos `options.scriptName` como `debugName` de
	  propósito: é o que permite `splitErrorMessage` abaixo separar `line` de `message` sem
	  precisar da biblioteca `debug` (que não está na whitelist). Formato exato confirmado
	  empiricamente para esta task (não estava na pesquisa salva) — ver comentário de
	  `splitErrorMessage`.
	- `setmetatable` NUNCA é chamado sobre a tabela `environment` que construímos aqui —
	  indexar uma chave ausente (`fs`, `net`, `process`, `serde`, `io`, `require`, ...) devolve
	  `nil` puro, sem nenhum `__index` custom, exatamente como indexar uma tabela comum sem
	  aquela chave (acceptance: "nunca nil explícito enganoso").

	Todo erro (de compilação do `source` OU de execução do chunk já carregado) acontece DENTRO
	da thread gerida por `options.scheduler:Spawn` — cai no ponto único de `coroutine.resume`
	de Scheduler.luau, que converte em `ThreadError:Fire(thread, message)` e nunca derruba o
	processo (mesma garantia central documentada em Scheduler.luau). Este módulo se inscreve em
	`options.scheduler.ThreadError` e traduz para `OutputRecord{level="error", ...}` antes de
	repassar a `options.onOutput` -- só para as threads que ELE mesmo criou (`ownThreads`,
	populado no momento do Spawn/Delay/Defer, inclusive por `task.spawn`/`task.delay`/
	`task.defer` internos ao script do usuário), nunca para erros de outros scripts que
	porventura compartilhem o mesmo `Scheduler`.

	Depende de: Scheduler.luau (tipos), @lune/luau.
	Usado por: `cli` (uma chamada por Script/LocalScript/ModuleScript do projeto).

	-- task-runtime-026: whitelist completada -- fica registrado aqui, no cabeçalho, porque
	-- afeta a leitura do módulo inteiro (não só um trecho isolado).

	Desenho completo em .claude/agents-memory/arquiteto-cli-2026-09-05.md, Decisão 12. Adições:
	`setmetatable`/`getmetatable`/`rawget`/`rawset`/`rawequal`/`rawlen`/`newproxy` (Luau puro),
	`buffer` (biblioteca padrão do Luau), `os.date`/`os.difftime` somando ao `os` já restrito,
	os globais depreciados mas onipresentes `wait`/`spawn`/`delay`/`tick`/`time`, e `unpack`.
	Cada adição tem seu comentário pontual mais abaixo, no ponto exato onde é montada em
	`buildEnvironment`. `unpack` estava condicionado, na descrição original desta tarefa, a
	`task-cli-007` confirmar que o Roblox real mantém o global (a Decisão 12 do arquiteto listava
	como incerto se seria só um alias depreciado ou removido) — `task-cli-007`, rodando em
	paralelo, confirmou contra fonte primária que `unpack` existe no Roblox real e NÃO é
	depreciado (diferente do Lua 5.2+ vanilla, onde `unpack` vira `table.unpack`), então entra
	aqui como global de primeira classe, não como alias marcado "legado". `debug` fica
	DELIBERADAMENTE fora (precisa de análise própria do que `debug.info`/`traceback` revelam do
	host de dentro de um chunk sandboxed). `_G`/`shared` também ficam fora: são estado por
	execução, injetados por `cli` via `extraGlobals`, nunca constantes da whitelist fixa deste
	módulo.

	RISCO RESIDUAL DECLARADO (regra 00 -- toda divergência é documentada, nunca silenciosa),
	descoberto ao completar esta whitelist, fora do território desta tarefa para corrigir:
	`Instance` (Instance.luau) é uma tabela Luau comum com metatable
	(`setmetatable({}, InstanceMeta)`), cujo `__index`/`__newindex` fazem toda a validação de
	schema/hierarquia/eventos, e `InstanceMeta` NÃO define `__metatable` (não está travada). Um
	script agora pode chamar `getmetatable(alvo)` sobre qualquer Instance que já tenha referência
	(lê o `InstanceMeta` real, incluindo os fechamentos internos de `__index`/`__newindex`) e
	`setmetatable(alvo, {})` (troca a metatable de uma Instance JÁ EXISTENTE E COMPARTILHADA,
	quebrando a simulação para TODO script que segure a mesma referência dali em diante -- não é
	um efeito isolado ao script que chamou). No Roblox real isso é IMPOSSÍVEL: Instance é
	userdata, não tabela -- `setmetatable(workspace, {})` erra "table expected, got Instance" e
	`getmetatable(workspace)` devolve `nil`. É uma divergência de FIDELIDADE (não uma concessão
	de acesso ao host -- por isso não bloqueia esta tarefa, cujo critério declarado é exatamente
	"não concede acesso ao host"), mas séria o bastante para precisar de mitigação futura em
	`Instance.luau` (fora do escopo desta tarefa, que é só Sandbox.luau/Sandbox.spec.luau):
	caminho óbvio é travar `InstanceMeta.__metatable`, espelhando o comportamento real de
	userdata. Reportado como pendência de acompanhamento na mesma seção do relatório desta
	tarefa, não corrigido aqui.
]]

local luau = require("@lune/luau")
local SchedulerModule = require("./Scheduler")

type Scheduler = SchedulerModule.Scheduler

export type OutputLevel = "print" | "warn" | "error"

export type OutputRecord = {
	level: OutputLevel,
	message: string,
	scriptName: string?,
	line: number?,
	timestamp: number,
}

export type SandboxGlobals = { [string]: unknown }

export type SandboxOptions = {
	scriptName: string,
	source: string,
	scheduler: Scheduler,
	extraGlobals: SandboxGlobals?,
	onOutput: (record: OutputRecord) -> (),
}

export type SandboxResult = {
	thread: thread,
}

-- Forma interna da tabela `task` exposta ao script do usuário -- fechada sobre o `scheduler`
-- real recebido em `options`, nunca sobre `@lune/task` cru. Não exportado: é um detalhe de
-- implementação deste módulo, invisível para `services`/`cli`.
type TaskGlobal = {
	spawn: <A...>(fn: (A...) -> (), A...) -> thread,
	wait: (seconds: number?) -> number,
	delay: <A...>(seconds: number, fn: (A...) -> (), A...) -> thread,
	defer: <A...>(fn: (A...) -> (), A...) -> thread,
	cancel: (handle: thread) -> (),
}

-- Restrito a `.clock`/`.time`/`.date`/`.difftime` -- nunca o `os` inteiro do Lune. `date`/
-- `difftime` somam nesta tarefa (task-runtime-026, Decisão 12): existem no Roblox real
-- (`os.date`/`os.difftime` fazem parte da biblioteca `os` documentada da Roblox) e não
-- concedem acesso ao host -- só formatam/comparam o relógio que `os.time`/`os.clock` já
-- expunham. `os.getenv`/`os.exit`/`os.remove`/`os.rename`/`os.tmpname` continuam FORA de
-- propósito: vazariam variável de ambiente, encerrariam o processo host ou tocariam o
-- filesystem do host por fora do que o Roblox real permitiria (regra 00, execução de código
-- arbitrário). `date`/`difftime` tipados via `typeof(...)` (em vez de reescrever a assinatura
-- na mão) porque a sobrecarga real de `os.date` (formato `"*t"` devolve tabela, outro formato
-- devolve string) já vem corretamente resolvida pelos globals embutidos do Luau -- reescrever
-- arriscaria divergir do tipo real ou precisar de `any` para cobrir as duas formas.
type RestrictedOs = {
	clock: () -> number,
	time: () -> number,
	date: typeof(os.date),
	difftime: typeof(os.difftime),
}

-- Monta o `task.spawn/wait/delay/defer/cancel` que o script do usuário enxerga. Cada função
-- que cria uma thread nova (`spawn`/`delay`/`defer`) registra o handle resultante em
-- `ownThreads` -- é assim que um erro dentro de um `task.spawn` interno ao script chega
-- corretamente identificado como "deste script" quando `Sandbox.Run` traduz `ThreadError`
-- para `OutputRecord` mais abaixo.
--
-- `spawn` precisa de um cuidado extra que `delay`/`defer` não precisam: `Scheduler:Spawn` roda
-- a função recebida de forma SÍNCRONA (até o primeiro yield/término) antes de devolver o
-- handle -- se a função spawnada errar na hora, o `ThreadError` já dispara ANTES de `spawn`
-- conseguir registrar o handle devolvido em `ownThreads` (corrida). A saída é registrar a
-- própria thread (via `coroutine.running()`, chamado de DENTRO da thread recém-criada, como
-- primeiríssima linha) antes de rodar a função real do usuário -- isso nunca corre com o
-- `ThreadError`, porque só pode disparar depois que a função começou a rodar.
local function buildTaskGlobal(scheduler: Scheduler, ownThreads: { [thread]: boolean }): TaskGlobal
	return {
		spawn = function<A...>(fn: (A...) -> (), ...: A...): thread
			local wrapped = function(...: A...)
				ownThreads[coroutine.running()] = true
				fn(...)
			end
			return scheduler:Spawn(wrapped, ...)
		end,

		wait = function(seconds: number?): number
			return scheduler:Wait(seconds)
		end,

		delay = function<A...>(seconds: number, fn: (A...) -> (), ...: A...): thread
			-- Sem a corrida do `spawn` acima: `Delay` só enfileira, nunca roda a função na
			-- hora -- o handle já existe e está correto antes de qualquer erro ser possível.
			local handle = scheduler:Delay(seconds, fn, ...)
			ownThreads[handle] = true
			return handle
		end,

		defer = function<A...>(fn: (A...) -> (), ...: A...): thread
			local handle = scheduler:Defer(fn, ...)
			ownThreads[handle] = true
			return handle
		end,

		cancel = function(handle: thread): ()
			scheduler:Cancel(handle)
		end,
	}
end

-- `print`/`warn` do Roblox real concatenam os argumentos com tab, convertidos via `tostring`
-- -- mesma semântica aqui, só que o destino nunca é o stdout/stderr cru do processo Lune
-- (que rodaria por baixo do terminal do LuauBench sem formatação nenhuma): tudo vira
-- `OutputRecord` entregue a `options.onOutput`, que decide como imprimir (regra 00: comportamento
-- do script do usuário nunca escapa como comportamento do próprio LuauBench).
--
-- Sem `line`: exigiria a biblioteca `debug` (`debug.info`), que não está na whitelist fixa
-- desta tarefa -- diferente de `error` (ver `splitErrorMessage`), que ganha `line` de graça
-- through do próprio formato de mensagem do VM, sem precisar de `debug`.
local function makeOutputFunction(level: OutputLevel, scriptName: string, onOutput: (OutputRecord) -> ()): (...unknown) -> ()
	return function(...: unknown)
		local packed = table.pack(...)
		local parts: { string } = {}
		for i = 1, packed.n do
			table.insert(parts, tostring(packed[i]))
		end
		onOutput({
			level = level,
			message = table.concat(parts, "\t"),
			scriptName = scriptName,
			line = nil,
			timestamp = os.time(),
		})
	end
end

-- Separa `scriptName`/`line`/`message` da string bruta que chega via `ThreadError` (disparado
-- por `coroutine.resume` dentro de Scheduler.luau -- ver Scheduler.resumeThread). Confirmado
-- empiricamente para esta task (rodando `luau.load`/`coroutine.resume` isolados, sem
-- depender de memória): diferente de um `pcall` direto sobre o chunk (que devolveria só
-- `[string "NOME"]:LINHA: mensagem`), uma falha entregue via `coroutine.resume` no Lune SEMPRE
-- vem prefixada com um rótulo de categoria do próprio Lune (`"runtime error: "` para erro em
-- tempo de execução, `"syntax error: "` para `source` que não compila -- luau.load lança
-- direto do `entry`, dentro da mesma thread gerida, então cai no mesmo mecanismo) e sempre
-- seguida de `"\nstack traceback:\n\t..."` multi-linha. Em vez de tentar casar cada rótulo de
-- prefixo um a um (frágil a rótulos futuros do Lune), procuramos o marcador
-- `[string "scriptName"]:` em qualquer posição da primeira linha (com `plain=true`, já que
-- `[`/`]`/`"` são caracteres mágicos de pattern do Lua) -- o que vier ANTES dele (rótulo de
-- categoria ou nada) é descartado, e a stack traceback (linhas seguintes) também não entra em
-- `message` (não existe campo pra isso em `OutputRecord` -- perda documentada no relatório,
-- não escondida). Só funciona porque `debugName` foi setado para `scriptName` em
-- `Sandbox.Run`. Se o marcador não for encontrado (ex.: erro não-string, ou um formato que
-- não reconhecemos), devolve a primeira linha crua e `line = nil` -- nunca falha, só degrada.
local function splitErrorMessage(scriptName: string, raw: string): (string, number?)
	local firstLine = raw
	local newlineIndex = string.find(raw, "\n")
	if newlineIndex ~= nil then
		firstLine = string.sub(raw, 1, newlineIndex - 1)
	end

	local marker = `[string "{scriptName}"]:`
	local _markerStart, markerEnd = string.find(firstLine, marker, 1, true)
	if markerEnd == nil then
		return firstLine, nil
	end
	local rest = string.sub(firstLine, markerEnd + 1)
	local lineText, message = string.match(rest, "^(%d+): (.*)$")
	if lineText == nil or message == nil then
		return firstLine, nil
	end
	return message, tonumber(lineText)
end

-- Monta a whitelist fixa de globals (ver cabeçalho do módulo) e mescla `options.extraGlobals`
-- por cima -- `extraGlobals` pode até sobrescrever uma entrada da whitelist (ex.: um `print`
-- diferente), decisão de quem chama (`cli`/`services`), nunca deste módulo.
local function buildEnvironment(options: SandboxOptions, ownThreads: { [thread]: boolean }): SandboxGlobals
	local env: SandboxGlobals = {}

	local taskGlobal = buildTaskGlobal(options.scheduler, ownThreads)
	env.task = taskGlobal
	env.coroutine = coroutine
	env.math = math
	env.string = string
	env.table = table
	env.os = ({ clock = os.clock, time = os.time, date = os.date, difftime = os.difftime } :: RestrictedOs)
	env.bit32 = bit32
	env.utf8 = utf8
	env.typeof = typeof
	env.tostring = tostring
	env.tonumber = tonumber
	env.pcall = pcall
	env.xpcall = xpcall
	env.assert = assert
	env.select = select
	env.pairs = pairs
	env.ipairs = ipairs
	env.next = next
	env.print = makeOutputFunction("print", options.scriptName, options.onOutput)
	env.warn = makeOutputFunction("warn", options.scriptName, options.onOutput)
	-- `error` cru (mesma função-base do Lune, capturada por upvalue -- não uma reimplementação
	-- nossa): precisa continuar lançando de verdade (nunca só logar e seguir), senão `pcall`
	-- dentro do script do usuário pararia de funcionar (regra 01: erro nunca é engolido). O
	-- "redirecionamento pra onOutput" acontece depois, via ThreadError, não aqui.
	env.error = error

	-- task-runtime-026, Decisão 12: `setmetatable`/`getmetatable`/`rawget`/`rawset`/
	-- `rawequal`/`rawlen`/`newproxy` são Luau puro -- operam só sobre valores que o PRÓPRIO
	-- script já tem referência (o que ele criou, ou o que `extraGlobals`/`cli` decidiu expor).
	-- Não abrem nenhum caminho novo até `fs`/`net`/`process`/`serde`/`io`/`require` do host, que
	-- continuam ausentes por construção (nunca copiados para `env`). Ausência anterior quebrava
	-- o caso de uso central do projeto: todo módulo OOP do ecossistema Roblox (ProfileStore,
	-- state managers, proxytable) depende de `setmetatable`/`__index`.
	--
	-- Ver RISCO RESIDUAL DECLARADO no cabeçalho do módulo: como `Instance` (Instance.luau) é
	-- implementado como tabela Luau comum com `InstanceMeta` destravada (sem `__metatable`),
	-- estas funções permitem a um script ler (`getmetatable`) ou substituir
	-- (`setmetatable(instancia, {})`) a metatable real de uma Instance JÁ existente e
	-- compartilhada -- algo impossível no Roblox real (Instance é userdata, não tabela). Não é
	-- concessão de acesso ao host (critério desta tarefa), é divergência de fidelidade
	-- registrada para acompanhamento em Instance.luau, fora deste território.
	env.setmetatable = setmetatable
	env.getmetatable = getmetatable
	env.rawget = rawget
	env.rawset = rawset
	env.rawequal = rawequal
	env.rawlen = rawlen
	env.newproxy = newproxy

	-- `unpack`: existe no Roblox real como global de primeira classe (não depreciado -- ver
	-- comentário do cabeçalho do módulo, confirmado por task-cli-007 contra fonte primária) e é
	-- Luau puro (mesma função-base de `table.unpack`, capturada por upvalue) -- não abre nenhum
	-- caminho novo ao host.
	env.unpack = unpack

	-- `buffer`: biblioteca padrão do Luau (presente no Roblox moderno) para bytes crus em
	-- memória do PRÓPRIO processo do script -- não é I/O, não toca disco/rede/processo do host,
	-- então não concede acesso a nada que a whitelist já bloqueia.
	env.buffer = buffer

	-- Globais depreciados mas onipresentes em código real do ecossistema Roblox (tutoriais,
	-- addons antigos, ProfileStore em versões mais velhas). `wait`/`spawn`/`delay` reaproveitam
	-- LITERALMENTE as mesmas funções que `task.wait`/`task.spawn`/`task.delay` (mesma closure
	-- fechada sobre `options.scheduler`/`ownThreads`, ver `buildTaskGlobal` acima) -- nunca uma
	-- segunda implementação, nunca `@lune/task` cru. Isso também garante que um erro dentro de
	-- um `spawn(...)` legado seja atribuído a este script exatamente como um `task.spawn` seria
	-- (mesmo registro em `ownThreads`).
	--
	-- Divergência documentada, não escondida (regra 00): no Roblox real, o `spawn` legado NÃO
	-- roda a função imediatamente -- ela só é retomada no próximo resumption cycle, diferente de
	-- `task.spawn` (síncrono até o primeiro yield). Essa nuance de timing exata não foi
	-- confirmada por pesquisador nesta tarefa (fora do escopo desta task, que pede
	-- explicitamente "rotear pelo options.scheduler exatamente como task.* já faz hoje") -- por
	-- isso `spawn`/`wait`/`delay` aqui são, de propósito, aliases 1:1 dos equivalentes `task.*`,
	-- e não uma reimplementação com timing diferente adivinhado.
	env.wait = taskGlobal.wait
	env.spawn = taskGlobal.spawn
	env.delay = taskGlobal.delay

	-- `tick`/`time` não pertencem à família `task.*` (não cedem/retomam coroutine -- são só
	-- leituras de relógio) e o `Scheduler` não expõe um relógio simulado publicamente (só
	-- Spawn/Defer/Delay/Wait/Cancel/Heartbeat/Stepped/ThreadError/Run/StepOnce/IsAlive) --
	-- então usam o mesmo relógio do processo host que `Scheduler.Run` já usa para medir `dt`
	-- entre tiques (`os.clock()`, ver Scheduler.luau), em vez de inventar acesso novo.
	--
	-- Divergências documentadas (regra 00): no Roblox real, `time()` é o tempo decorrido desde
	-- que o jogo começou a rodar (relógio do motor, não exposto aqui) -- `os.clock()` do
	-- processo host aproxima (monotônico, crescente desde o início do processo) sem ser
	-- literalmente o mesmo relógio. `tick()` no Roblox real é a época Unix com fração de
	-- segundo -- `os.time()` do Lune só dá segundos inteiros (perde a fração, mantém a base de
	-- época correta, diferente de `os.clock()`, que não é relativo à época).
	env.time = function(): number
		return os.clock()
	end
	env.tick = function(): number
		return os.time()
	end

	if options.extraGlobals ~= nil then
		local extra = options.extraGlobals :: SandboxGlobals
		for key, value in extra do
			env[key] = value
		end
	end

	return env
end

local Sandbox = {}

function Sandbox.Run(options: SandboxOptions): SandboxResult
	-- Chaves fracas: uma thread deste script sem mais referências externas (já morta, handle
	-- descartado por quem chamou) pode ser coletada pelo GC sem exigir limpeza explícita --
	-- mesmo padrão de Instance.luau/ThreadBroker.luau (regra 01, sem `any`, cast em duas
	-- etapas via `unknown`).
	local ownThreads: { [thread]: boolean } =
		(setmetatable({}, { __mode = "k" }) :: unknown) :: { [thread]: boolean }

	local environment = buildEnvironment(options, ownThreads)

	-- `LoadOptions.environment` é tipado como `{ [string]: any }?` no stub do próprio Lune
	-- (crates/lune-std-luau/types.d.luau, ver pesquisa-sandbox-globals-lune-2026-09-04.md) --
	-- isso não é nosso: é a fronteira declarada pela biblioteca externa. Cast pontual aqui,
	-- só neste boundary de chamada; `SandboxGlobals` (`{ [string]: unknown }`) continua sendo
	-- o tipo público deste módulo, sem `any` em lugar nenhum da nossa própria API.
	local loadOptions = {
		debugName = options.scriptName,
		environment = (environment :: unknown) :: { [string]: any },
		injectGlobals = false,
	}

	-- Se inscreve nesta chamada de Run, não globalmente no módulo: cada script que roda tem
	-- sua própria Connection e seu próprio `ownThreads`, então erros de OUTRO script rodando
	-- no mesmo `Scheduler` (cenário normal quando `cli` executa vários Scripts) são ignorados
	-- aqui -- cada Sandbox.Run só reporta o que é seu.
	options.scheduler.ThreadError:Connect(function(erroredThread: thread, message: string)
		if not ownThreads[erroredThread] then
			return
		end
		local cleanMessage, line = splitErrorMessage(options.scriptName, message)
		options.onOutput({
			level = "error",
			message = cleanMessage,
			scriptName = options.scriptName,
			line = line,
			timestamp = os.time(),
		})
	end)

	-- Registra a própria thread ANTES de carregar/rodar o source: cobre tanto um erro de
	-- COMPILAÇÃO (`luau.load` lança se `source` não for Luau válido -- confirmado na pesquisa:
	-- a assinatura Rust devolve `LuaResult<LuaFunction>`, erro vira erro Lua, nunca
	-- nil+mensagem) quanto um erro de EXECUÇÃO do chunk já carregado. Os dois caem no mesmo
	-- `coroutine.resume` protegido de Scheduler.luau -- nenhum tratamento especial extra
	-- precisa existir aqui além de garantir que `ownThreads` já sabe quem é esta thread antes
	-- de qualquer um dos dois poder acontecer.
	local function entry()
		ownThreads[coroutine.running()] = true
		local chunk = luau.load(options.source, loadOptions)
		chunk()
	end

	local handle = options.scheduler:Spawn(entry)

	return { thread = handle }
end

return Sandbox
