--!strict

--[[
	O `require` simulado (arquiteto-cli-2026-09-05.md, Decisão 5, "`require` simulado
	(`src/cli/ModuleLoader.luau`)"). LER a Decisão 5 inteira, mais o cabeçalho de
	`src/runtime/Sandbox.luau` (task-runtime-025, `Sandbox.Load`) antes de mexer aqui.

	Cache por identidade de Instance, ciclo detectado por thread, espera cross-thread por módulo em
	voo, e -- CRITÉRIO ADICIONAL desta tarefa (achado MÉDIO real da revisão de task-runtime-025,
	.claude/agents-memory/arquiteto-cli-2026-09-05.md, "Riscos e decisões": "erro dentro de
	`task.spawn` no corpo de um módulo require-ado hoje desaparece sem gerar nenhum `OutputRecord`,
	porque `Sandbox.Load` não se inscreve em `ThreadError` por design") -- atribuição de erro
	assíncrono (`task.spawn`/`spawn`/`task.delay`/`task.defer` chamados de DENTRO do corpo de um
	módulo) ao Script que originou a cadeia de `require`.

	--------------------------------------------------------------------------------------------
	POR QUE `ModuleLoader` É UMA INSTÂNCIA POR SCRIPT (não uma instância única por `run`)
	--------------------------------------------------------------------------------------------

	`Sandbox.Load` (runtime) DELIBERADAMENTE não se inscreve em `scheduler.ThreadError` -- um erro
	SÍNCRONO no corpo do módulo propaga via `pcall`/erro Lua normal, o que já resolve o caso comum
	(ver cabeçalho de `Sandbox.luau`). O caso que sobra -- e que esta tarefa fecha -- é uma thread
	NOVA criada de dentro do módulo (`task.spawn(function() error(...) end)`): essa thread nunca é
	`ownThread` de nenhum `Sandbox.Run`, então seu erro dispara `ThreadError` no `Scheduler`
	compartilhado sem que ninguém traduza para `OutputRecord`.

	A correção replica, em `cli`, EXATAMENTE o mesmo mecanismo que `Sandbox.Run` já usa para o
	`Script` de topo (buildTaskGlobal + `ownThreads` fraco por chave + `ThreadError:Connect`
	filtrado por `ownThreads[thread]`) -- mas para as threads que um MÓDULO cria, não as que o
	Script de topo cria. Para isso funcionar sem precisar de um registro global de "qual thread
	pertence a qual Script" (que exigiria threading de identidade por TODA a árvore de chamadas
	síncronas), `ModuleLoader.new` é chamado UMA VEZ POR SCRIPT que vai rodar (`RunCommand`/
	`ScriptRunner`, task-cli-006, cria um `ModuleLoader` por `Script`/`LocalScript` antes de
	`Sandbox.Run`), com o `ScriptName`/`OnOutput` DAQUELE Script gravados no construtor. Cada
	instância de `ModuleLoader`:

	  1. mantém seu PRÓPRIO `ownThreads` (chave fraca, mesma disciplina de `Sandbox.buildTaskGlobal`);
	  2. se inscreve UMA VEZ em `scheduler.ThreadError`, filtrando por esse `ownThreads`;
	  3. quando precisa executar um `ModuleScript` (via `Sandbox.Load`), sobrescreve
	     `task`/`spawn`/`delay` no `extraGlobals` daquele módulo com uma versão que registra a
	     thread nova NESTE `ownThreads` (nunca no `ownThreads` descartável que o próprio
	     `Sandbox.Load` cria internamente -- ver `Sandbox.luau`, `Sandbox.Load`, comentário sobre
	     por que aquele `ownThreads` "nunca precisa sobreviver além desta chamada": ninguém o
	     escuta).

	Como TODA cadeia SÍNCRONA de `require` (A requer B requer C, sem `task.spawn`/`task.wait` no
	meio) roda na MESMA coroutine (`Sandbox.Load` nunca cria thread -- é o ponto central da task-
	runtime-025), uma thread criada por `task.spawn` de DENTRO de C ainda é "filha" da mesma cadeia
	que começou no Script de topo -- por isso basta UM `ownThreads`/UMA assinatura de `ThreadError`
	por Script, nunca por módulo individual. O `Cache` de módulos (ver abaixo), ao contrário, É
	compartilhado entre TODAS as instâncias de `ModuleLoader` de um mesmo `run` (`ModuleLoader.
	NewCache()` cria UMA vez; `RunCommand` passa a MESMA referência para o `ModuleLoader.new` de
	cada Script) -- é isso que garante que dois Scripts diferentes, requerendo o MESMO `ModuleScript`,
	vejam o cache compartilhado (comportamento real do Roblox: `require` é memoizado por Instance,
	não por script chamador).

	--------------------------------------------------------------------------------------------
	SEMÂNTICA DE `Require(target)`
	--------------------------------------------------------------------------------------------

	- `target` numérico (asset id) -> `Messages.RequireAssetIdNotSupported()`, prefixo `[LuauBench]`
	  OBRIGATÓRIO (sem contraparte real -- local-first, regra 00/invariante 6).
	- `target` que não é uma `ModuleScript` (Instance de outra classe, ou não-Instance nenhuma) ->
	  `Messages.RequireInvalidArgument()` -- família Roblox, aproximação de boa-fé (task-cli-007
	  pesquisou; ver Messages.luau).
	- Cache por IDENTIDADE da Instance (`ModuleCache.Entries[instance]`), compartilhado entre todas
	  as instâncias de `ModuleLoader` do mesmo `run` (ver acima). Entrada existente com
	  `State == "loaded"` -> devolve `Value` direto, SEM re-executar (mesmo módulo pedido duas vezes
	  nunca roda o corpo duas vezes).
	- Entrada existente com `State == "loading"`:
	    - `LoadingThread == coroutine.running()` -> CICLO (mesma thread pedindo de novo, no meio da
	      própria cadeia síncrona que começou a carregar este módulo) -> erro
	      `Messages.RequireRecursedSameThread()`. Cobre A->A e A->B->A: como toda a cadeia síncrona
	      roda na MESMA coroutine (Sandbox.Load nunca cria thread), `LoadingThread` continua sendo a
	      mesma identidade em qualquer profundidade de aninhamento.
	    - `LoadingThread ~= coroutine.running()` -> outra thread está carregando este módulo AGORA
	      (ex.: dois Scripts diferentes, ou duas threads `task.spawn`adas do mesmo Script, requerendo
	      o mesmo módulo ao mesmo tempo) -> espera via `entry.Ready:Wait()` (um `Signal.new()` por
	      módulo em voo, exatamente como o desenho pede -- `:Wait()` já roteia pelo `ThreadBroker`
	      quando a thread chamadora é gerida por um `Scheduler`, sem nada novo a construir aqui).
	      Depois de acordar, relê `entry.State` (mutado pela thread que terminou de carregar) e
	      devolve o valor ou re-lança o erro cacheado.
	- Entrada existente com `State == "errored"` -> re-lança `entry.ErrorMessage` (o módulo NÃO é
	  re-executado numa segunda tentativa -- decisão não confirmada por pesquisador contra o Roblox
	  real, aproximação de boa-fé documentada aqui: cachear o erro é consistente com "cache por
	  identidade de Instance" e evita reexecutar um módulo com efeito colateral parcial já aplicado).
	- Módulo carregado com sucesso, mas o chunk não devolve EXATAMENTE 1 valor (`table.pack(chunk())
	  .n ~= 1`) -> `Messages.RequireDidNotReturnOneValue()`.
	- Executa o módulo via `Runtime.Sandbox.Load` chamado NA THREAD CORRENTE (nunca cria thread
	  própria -- é o que dá ao `require` a semântica síncrona real: um `task.wait()` no topo do
	  módulo suspende quem pediu; um erro no corpo do módulo propaga por `pcall` normal), com
	  `extraGlobals` PRÓPRIOS montados por `ScriptEnvironment.Build` (`script` = o `ModuleScript`
	  sendo carregado), sobrepostos com o override de `task`/`spawn`/`delay` deste `ModuleLoader`
	  (ver acima).

	Depende de: `../runtime` (`Sandbox.Load`, `Signal.new`, `Instance.GetPropertyRaw`, tipos),
	`ScriptEnvironment.luau`, `Messages.luau`. NUNCA `../services` diretamente (não precisa: quem
	decide `Instance.new`/`game`/`workspace`/`_G`/`shared` é `ScriptEnvironment.luau`).
]]

local Runtime = require("../runtime")
local ScriptEnvironment = require("./ScriptEnvironment")
local Messages = require("./Messages")

export type OnOutput = (record: Runtime.OutputRecord) -> ()

type CacheState = "loading" | "loaded" | "errored"

-- Estado de UM módulo dentro do `ModuleCache` -- nunca exposto fora deste arquivo.
type CacheEntry = {
	State: CacheState,
	-- Identidade da thread que está executando o corpo do módulo agora (só relevante enquanto
	-- State == "loading"). `nil` depois que o carregamento termina (sucesso ou erro) -- ninguém
	-- mais compara contra ela.
	LoadingThread: thread?,
	-- Válido quando State == "loaded" -- o único valor que o chunk devolveu.
	Value: unknown,
	-- Válido quando State == "errored" -- mensagem já pronta pra re-`error()`, sem reformatar.
	ErrorMessage: string?,
	-- Dispara (sem argumentos -- quem acorda relê `State`/`Value`/`ErrorMessage` direto da mesma
	-- entrada, por referência) quando este módulo sai de "loading" -- é o que faz um segundo
	-- requerente, em outra thread, esperar pelo MESMO resultado em vez de recarregar.
	Ready: Runtime.FireableSignal<>,
}

-- Compartilhado entre TODAS as instâncias de `ModuleLoader` do mesmo `run` -- ver cabeçalho,
-- "por que uma instância por Script". `RunCommand` (task-cli-006) cria UM `ModuleCache` por
-- `luaubench run` e passa a MESMA referência para cada `ModuleLoader.new`.
export type ModuleCache = {
	Entries: { [Runtime.Instance]: CacheEntry },
}

export type ModuleLoaderOptions = {
	Scheduler: Runtime.Scheduler,
	-- Nome do Script (GetFullName) que originou esta cadeia de `require` -- é o `scriptName` de
	-- TODO `OutputRecord` de erro assíncrono que este `ModuleLoader` gerar (ver cabeçalho: "no
	-- Script que fez o require original", acceptance do board). Nunca o nome do módulo que de fato
	-- errou -- essa distinção (qual módulo, qual linha) mora na MENSAGEM (formatada por
	-- `OutputFormatter`, task-cli-006), não em `OutputRecord.scriptName`, mesma convenção que
	-- `Sandbox.Run` já usa para erro síncrono de qualquer `require` mal tratado.
	ScriptName: string,
	OnOutput: OnOutput,
	Cache: ModuleCache,
	-- Repassados adiante para `ScriptEnvironment.Build` de cada `ModuleScript` carregado por este
	-- loader -- `ModuleLoader` nunca decide sozinho o que um módulo enxerga além da whitelist do
	-- `runtime`; isso é sempre `ScriptEnvironment.luau` (regra 00: um único lugar decide).
	Game: Runtime.DataModel,
	Workspace: Runtime.Instance,
	GlobalTable: { [string]: unknown },
	SharedTable: { [string]: unknown },
}

export type ModuleLoader = {
	Require: (self: ModuleLoader, target: unknown) -> unknown,
}

local ModuleLoader = {}

-- UMA vez por `luaubench run` -- ver `ModuleLoaderOptions.Cache`, acima.
function ModuleLoader.NewCache(): ModuleCache
	return { Entries = {} }
end

-- `target: unknown` pode ser QUALQUER coisa que o script do usuário passar -- número, string,
-- tabela, Instance de outra classe, nil. Só devolve não-nil quando `target` é de fato uma
-- `Runtime.Instance` cuja `ClassName` (via cadeia de `IsA`) é "ModuleScript".
--
-- `typeof(target) == "userdata"`: desde task-runtime-027, toda `Runtime.Instance` é userdata de
-- verdade (`newproxy(true)`, nunca mais uma tabela comum) -- ver Instance.luau, `Instance.NewBase`.
-- `pcall` em volta de `candidate:IsA(...)` cobre o caso de um userdata que NÃO é uma Instance do
-- LuauBench (ex.: um `newproxy(true)` cru que o próprio script criou -- `newproxy` está na
-- whitelist desde task-runtime-026 -- ou um `buffer`, embora `buffer` tenha `type()` próprio,
-- "buffer", nunca "userdata"): indexar `.IsA` nesse userdata sem a metatable/`__index` que
-- `Instance.luau` instala erra "attempt to index userdata", capturado aqui e tratado como
-- "não é ModuleScript", nunca deixado escapar como um erro cru e confuso pro script chamador.
local function asModuleScript(target: unknown): Runtime.Instance?
	if typeof(target) ~= "userdata" then
		return nil
	end

	local candidate = (target :: unknown) :: Runtime.Instance
	local ok, isModuleScript = pcall(function(): boolean
		return candidate:IsA("ModuleScript")
	end)

	if ok and isModuleScript then
		return candidate
	end
	return nil
end

-- Mesmo recorte que `Sandbox.splitErrorMessage` aplica ao `message` de um `OutputRecord` (nunca
-- deixa a stack traceback multi-linha entrar em `message` -- "perda documentada", ver cabeçalho de
-- `Sandbox.luau`) -- só a parte de cortar na primeira quebra de linha, sem tentar reencontrar
-- `scriptName:line:` (essa função é privada em `Sandbox.luau`; `OutputFormatter`, task-cli-006, já
-- é o lugar documentado que faz essa segunda passada sobre a mensagem crua de qualquer erro,
-- reatribuindo módulo/linha -- este helper só garante o mesmo FORMATO de `message` que o resto do
-- pipeline já produz, nunca duplica a lógica de parsing de scriptName).
local function firstLine(raw: string): string
	local newlineIndex = string.find(raw, "\n")
	if newlineIndex == nil then
		return raw
	end
	return string.sub(raw, 1, newlineIndex - 1)
end

-- Forma da tabela `task`/`spawn`/`delay` que ESTE `ModuleLoader` injeta na `extraGlobals` de todo
-- módulo que ele carrega -- réplica funcional de `Sandbox.buildTaskGlobal` (privada em
-- `Sandbox.luau`, não reexportável), mas registrando as threads novas no `ownThreads` DESTE
-- `ModuleLoader` (o do Script que originou a cadeia), nunca no `ownThreads` descartável que o
-- `Sandbox.Load` do próprio módulo constrói (que ninguém escuta -- ver cabeçalho do módulo).
type ModuleTaskGlobal = {
	spawn: <A...>(fn: (A...) -> (), A...) -> thread,
	wait: (seconds: number?) -> number,
	delay: <A...>(seconds: number, fn: (A...) -> (), A...) -> thread,
	defer: <A...>(fn: (A...) -> (), A...) -> thread,
	cancel: (handle: thread) -> (),
}

-- `spawn`/`delay`/`defer` são os três pontos que criam thread nova -- os únicos que precisam
-- registrar em `ownThreads` para que o `ThreadError:Connect` de `ModuleLoader.new` (abaixo) consiga
-- atribuir um erro assíncrono ao Script certo. `wait`/`cancel` operam sobre a thread/handle
-- corrente e não precisam de tratamento especial (delegam direto pro `Scheduler`, mesma semântica
-- de sempre).
--
-- `spawn` replica a mesma correção de corrida documentada em `Sandbox.buildTaskGlobal`:
-- `Scheduler:Spawn` roda a função SINCRONAMENTE até o primeiro yield/erro antes de devolver o
-- handle -- se registrássemos `ownThreads[handle] = true` só DEPOIS de `scheduler:Spawn` retornar,
-- um erro imediato dentro da função spawnada já teria disparado `ThreadError` ANTES do registro
-- existir. A saída é a mesma: registrar a PRÓPRIA thread (`coroutine.running()`, chamado de DENTRO
-- da thread nova, como primeira linha) antes de rodar a função real.
local function buildModuleTaskGlobal(scheduler: Runtime.Scheduler, ownThreads: { [thread]: boolean }): ModuleTaskGlobal
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
			-- Sem a corrida de `spawn`: `Delay` só enfileira, o handle já existe e está correto
			-- antes de qualquer erro ser possível (mesma razão documentada em `Sandbox.luau`).
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

function ModuleLoader.new(options: ModuleLoaderOptions): ModuleLoader
	-- Chave fraca -- mesma disciplina de `Sandbox.buildTaskGlobal`/`internals` de Instance.luau:
	-- uma thread morta e sem mais referências pode ser coletada pelo GC sem exigir limpeza
	-- explícita deste `ModuleLoader`.
	local ownThreads: { [thread]: boolean } =
		(setmetatable({}, { __mode = "k" }) :: unknown) :: { [thread]: boolean }

	-- Inscrição ÚNICA, para a vida inteira deste `ModuleLoader` (== a vida do Script que o
	-- possui) -- CRITÉRIO ADICIONAL desta tarefa. Filtra por `ownThreads[erroredThread]` (mesmo
	-- padrão de `Sandbox.Run`): só threads que ESTE loader marcou (via `buildModuleTaskGlobal`,
	-- abaixo) geram `OutputRecord` aqui -- erro de outro Script/`ModuleLoader` compartilhando o
	-- mesmo `Scheduler` é ignorado (múltiplos `Connect` no mesmo `ThreadError` coexistem sem
	-- conflito, cada um só reage ao que é seu -- mesma garantia que `Sandbox.spec.luau` já prova
	-- para duas chamadas de `Sandbox.Run` no mesmo `Scheduler`).
	options.Scheduler.ThreadError:Connect(function(erroredThread: thread, message: string)
		if not ownThreads[erroredThread] then
			return
		end
		options.OnOutput({
			level = "error",
			message = firstLine(message),
			scriptName = options.ScriptName,
			line = nil,
			timestamp = os.time(),
		})
	end)

	local moduleTaskGlobal = buildModuleTaskGlobal(options.Scheduler, ownThreads)

	-- Declarado antes de definido: `requireModule` se referencia recursivamente (chamadas
	-- aninhadas de `require` dentro de um módulo) e é capturado por `moduleContext.Require`,
	-- abaixo, antes do `local function` terminar de ser lido -- padrão padrão de função local
	-- auto-recursiva em Lua/Luau, sem necessidade de forward-declare adicional.
	local function requireModule(target: unknown): unknown
		if typeof(target) == "number" then
			error(Messages.RequireAssetIdNotSupported(), 0)
		end

		local moduleInstance = asModuleScript(target)
		if moduleInstance == nil then
			error(Messages.RequireInvalidArgument(), 0)
		end
		local instance = moduleInstance :: Runtime.Instance

		local cache = options.Cache
		local entry = cache.Entries[instance]

		if entry == nil then
			-- Primeiro requerente -- registra a entrada ANTES de compilar/rodar, para que uma
			-- chamada recursiva (mesma thread) ou concorrente (outra thread) durante o carregamento
			-- encontre `State == "loading"` de verdade.
			local ready: Runtime.FireableSignal<> = Runtime.Signal.new()
			local newEntry: CacheEntry = {
				State = "loading",
				LoadingThread = coroutine.running(),
				Value = nil,
				ErrorMessage = nil,
				Ready = ready,
			}
			cache.Entries[instance] = newEntry

			local rawSource = Runtime.Instance.GetPropertyRaw(instance, "Source")
			local sourceText: string
			if typeof(rawSource) == "string" then
				sourceText = rawSource
			else
				-- `Source` nunca escrito (módulo criado só em memória, ex.: teste) -- trata como
				-- corpo vazio em vez de propagar um `nil` pro compilador; um chunk vazio não
				-- devolve nada, então cai naturalmente no erro "did not return exactly one value"
				-- abaixo, em vez de um erro de tipo cru.
				sourceText = ""
			end

			local moduleFullName = instance:GetFullName()

			-- `moduleContext.Require`: a MESMA `requireModule` deste `ModuleLoader` -- requires
			-- aninhados (módulo requerendo outro módulo) continuam na mesma instância, então
			-- reusam o mesmo `Cache`/`ownThreads`/assinatura de `ThreadError`, sem precisar
			-- reconstruir nada por nível de aninhamento (ver cabeçalho, "por que uma instância por
			-- Script").
			local moduleContext: ScriptEnvironment.EnvironmentContext = {
				Game = options.Game,
				Workspace = options.Workspace,
				GlobalTable = options.GlobalTable,
				SharedTable = options.SharedTable,
				Require = function(nestedTarget: unknown): unknown
					return requireModule(nestedTarget)
				end,
			}
			local moduleGlobals = ScriptEnvironment.Build(moduleContext, instance)

			-- Sobrescreve o `task`/`spawn`/`delay` da whitelist do `runtime` (que `Sandbox.Load`
			-- construiria sozinho, fechado sobre um `ownThreads` descartável que ninguém escuta --
			-- ver cabeçalho) com a versão deste `ModuleLoader`, fechada sobre o `ownThreads`/
			-- `Scheduler` que a assinatura de `ThreadError` acima de fato observa. `task.defer`
			-- também cria thread nova (ver `buildModuleTaskGlobal`) mas não tem alias legado
			-- (`defer()` cru não existe no Roblox) -- só `task.defer`, coberto porque `task` inteiro
			-- foi substituído.
			moduleGlobals.task = moduleTaskGlobal
			moduleGlobals.spawn = moduleTaskGlobal.spawn
			moduleGlobals.delay = moduleTaskGlobal.delay

			local loadOk, chunkOrError = pcall(function(): unknown
				return Runtime.Sandbox.Load({
					scriptName = moduleFullName,
					source = sourceText,
					scheduler = options.Scheduler,
					extraGlobals = moduleGlobals,
					onOutput = options.OnOutput,
				})
			end)

			if not loadOk then
				-- Erro de COMPILAÇÃO -- `Sandbox.Load` propaga como erro Lua direto (nunca
				-- `OutputRecord`, ver cabeçalho de `Sandbox.luau`). A mensagem já vem formatada
				-- pelo próprio VM (inclui `[string "moduleFullName"]:linha:` -- OutputFormatter,
				-- task-cli-006, reformata isso na apresentação; aqui só cacheamos/relançamos).
				local errorMessage = tostring(chunkOrError)
				newEntry.State = "errored"
				newEntry.ErrorMessage = errorMessage
				newEntry.LoadingThread = nil
				ready:Fire()
				error(errorMessage, 0)
			end

			local chunk = chunkOrError :: () -> ...unknown

			-- `table.pack(chunk())` -- se o corpo do módulo ceder (`task.wait()` no topo), este
			-- `pcall` inteiro (e a `coroutine.running()` corrente, seja o Script de topo ou uma
			-- thread `task.spawn`ada) fica suspenso aqui até o `Scheduler` retomar -- é exatamente
			-- a semântica síncrona que `Sandbox.Load` promete (ver cabeçalho de `Sandbox.luau`).
			local runOk, resultOrError = pcall(function(): { n: number, [number]: unknown }
				return table.pack(chunk())
			end)

			if not runOk then
				-- Erro de EXECUÇÃO síncrona do corpo do módulo -- propaga por `pcall` normal (nunca
				-- `OutputRecord` aqui: se ninguém tratar, sobe até a thread do Script que originou
				-- a cadeia, que É `ownThread` do `Sandbox.Run` dele -- reportado lá, uma vez só,
				-- exatamente como o desenho documenta).
				local errorMessage = tostring(resultOrError)
				newEntry.State = "errored"
				newEntry.ErrorMessage = errorMessage
				newEntry.LoadingThread = nil
				ready:Fire()
				error(errorMessage, 0)
			end

			local packed = resultOrError :: { n: number, [number]: unknown }
			if packed.n ~= 1 then
				local errorMessage = Messages.RequireDidNotReturnOneValue()
				newEntry.State = "errored"
				newEntry.ErrorMessage = errorMessage
				newEntry.LoadingThread = nil
				ready:Fire()
				error(errorMessage, 0)
			end

			newEntry.State = "loaded"
			newEntry.Value = packed[1]
			newEntry.LoadingThread = nil
			ready:Fire()
			return newEntry.Value
		end

		-- Entrada já existe -- outra chamada (mesma thread ou outra) já viu este módulo antes.
		if entry.State == "loading" then
			if entry.LoadingThread == coroutine.running() then
				error(Messages.RequireRecursedSameThread(), 0)
			end
			-- Outra thread está carregando -- espera o `Ready` disparar (ver `CacheEntry.Ready`).
			-- `entry` continua sendo a MESMA referência de tabela que a thread carregadora está
			-- mutando -- ler os campos de novo depois do `Wait()` enxerga o estado final.
			entry.Ready:Wait()

			-- ACHADO DE TOOLING (mesma classe documentada em `TreePlanner.luau`/`Diagnostics.luau`:
			-- `luau-lsp` 1.69.0 mantém a narrowing de `entry.State == "loading"` do `if` externo
			-- mesmo depois de `entry.Ready:Wait()` ceder e retomar -- não tem como saber que outra
			-- thread mutou o campo enquanto esta estava suspensa, e reporta "loading" nunca poder
			-- ser comparado com "errored" mais abaixo. `lune run` sempre lê o valor real em tempo de
			-- execução; é só a análise estática que precisa deste re-read explicitamente tipado
			-- (`CacheState` completo, não a literal estreitada) pra "resetar" a narrowing.
			local finalState: CacheState = entry.State
			if finalState == "errored" then
				error(entry.ErrorMessage :: string, 0)
			end
			return entry.Value
		elseif entry.State == "errored" then
			error(entry.ErrorMessage :: string, 0)
		end

		-- entry.State == "loaded"
		return entry.Value
	end

	local self: ModuleLoader = {
		Require = function(_self: ModuleLoader, target: unknown): unknown
			return requireModule(target)
		end,
	}
	return self
end

return ModuleLoader
