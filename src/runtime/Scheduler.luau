--!strict

--[[
	Scheduler cooperativo do LuauBench: dá semântica de `task.spawn/wait/delay/defer/cancel`
	e de `RunService.Heartbeat`/`Stepped` a scripts de usuário, sem nenhum `coroutine.resume`
	fora do ponto único definido aqui (função `resumeThread`, ver abaixo) — é essa disciplina
	que garante que erro de script nunca derruba o processo do LuauBench (regra 00/02).

	Contrato congelado em .claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção
	"Scheduler.luau". Depende de Signal.luau, ThreadBroker.luau e @lune/task.

	Divergências documentadas do Roblox real (regra 00 exige declarar, nunca esconder):

	- `task.wait`/`Heartbeat` não têm resolução fixa no Roblox real (pesquisa confirmada em
	  .claude/agents-memory/pesquisa-scheduler-lune-2026-09-04.md, seção 2: "não existe... um
	  número fixo de resolução mínima"). Aqui, quando não há nenhum `task.delay`/`task.wait`
	  pendente mais cedo, `Run()` faz o processo cochilar (via `@lune/task`, nunca `os`
	  bloqueante) por até `DEFAULT_FRAME_INTERVAL` segundos entre tiques — um teto arbitrário
	  de engenharia (~60Hz) para não girar a CPU a 100% à toa, não uma tentativa de replicar
	  vsync real.
	- Sem física real, não existe "PreSimulation"/"PostSimulation" para ancorar `Stepped`/
	  `Heartbeat`. A ordem relativa adotada por tique (`Stepped` antes, `Heartbeat` depois) só
	  aproxima a ordem documentada do Roblox (Stepped/PreSimulation antes da simulação,
	  Heartbeat depois de PostSimulation) — ver `tick`.
	- `task.defer` no Roblox/Lune real roda "no fim do resume point atual", um conceito mais
	  granular que uma iteração inteira do laço principal. Aqui, um tique inteiro (`tick`) é
	  tratado como um único "resume point": a fila de deferred é drenada uma vez por tique,
	  e um `task.defer` chamado a partir de outro `task.defer` do mesmo tique roda ainda
	  dentro do mesmo tique (não espera o próximo). Aproximação documentada, não Roblox exato.
	- Sem preempção de coroutine travada (`while true do end` sem yield trava `Run()` inteiro,
	  já que o laço de `coroutine.resume` é síncrono) — risco já registrado pelo arquiteto,
	  aceito nesta fase, não mitigado aqui (não há hook de interrupção de VM confirmado).
	- `Cancel` fecha a thread pendente com `coroutine.close` (nunca deixa retomar de novo,
	  manual ou pelo scheduler) — segue a doc do Roblox real ("cancels a thread and closes
	  it"), que é mais específica que a do Lune (`task.cancel` do Lune não documenta se fecha
	  a coroutine ou só remove da fila).

	Risco de integração RESOLVIDO nesta revisão (era achado GRAVE 2 + ALTO 4 da revisão
	pós-integração 2026-09-04 — ver
	.claude/agents-memory/revisor-runtime-signal-instance-scheduler-2026-09-04.md):
	`Signal:Wait()` (implementação real em Signal.luau) resumia a thread suspensa com um
	`coroutine.resume` direto, um segundo ponto de resume fora deste módulo — `liveThreads`
	nunca era podado para essa thread (`Scheduler:Run()` nunca terminava sozinho) e
	`ThreadError` atribuía o erro à thread hospedeira de `Fire`, não à thread que de fato
	errou. A correção vive em ThreadBroker.luau (módulo-folha, ver esse arquivo): toda thread
	gerida por este Scheduler é adotada (`ThreadBroker.Adopt`) no momento em que é criada
	(`trackThread`), e `Signal.luau:Wait()` passa a rotear a retomada por
	`ThreadBroker.Resume`, que encontra o driver aqui registrado e chama de volta em
	`resumeThread` — o ponto único de `coroutine.resume` deste módulo continua sendo,
	de fato, o único lugar que resume uma thread gerida, mesmo quando quem pediu a suspensão
	foi `Signal:Wait()`/`Instance:WaitForChild` de fora deste arquivo.

	`fireProtected` (ver abaixo) continua existindo como rede de segunda linha: ele já não
	precisa lidar com o erro de CONTINUAÇÃO de um `Wait()` (que agora vira ThreadError direto
	via o driver), só com erro genuíno de callback de listener quando `Signal.Fire` não
	encontra dono para a thread hospedeira.

	Achado MÉDIO RESOLVIDO nesta revisão (task-runtime-011, ver
	.claude/agents-memory/revisor-runtime-patch-threadbroker-2026-09-04.md): `Cancel` desfazia
	só o bookkeeping do próprio Scheduler (fila/liveThreads/driver), nunca a Connection que a
	thread cancelada tinha registrado num Signal alheio (ChildAdded de um WaitForChild com
	timeout, listener interno de Signal:Wait) — o listener ficava pendurado até o Signal
	disparar de novo, ou para sempre. `resumeThread`/`Cancel`/`IsAlive` agora chamam
	`ThreadBroker.RunCleanups(co)` em todo ponto em que já podavam `liveThreads`/`driver` por a
	thread não poder mais ser retomada — ver ThreadBroker.luau para o mecanismo
	(RegisterCleanup/RunCleanups) e a PENDÊNCIA DECLARADA lá: o mecanismo está pronto e testado
	aqui, mas Instance.luau/Signal.luau (fora do território desta tarefa) ainda não chamam
	`ThreadBroker.RegisterCleanup` nos dois pontos de criação de Connection que vazam — fechar
	o vazamento relatado de fato exige uma tarefa de acompanhamento que toque esses arquivos.
]]

local Signal = require("./Signal")
local ThreadBroker = require("./ThreadBroker")
local LuneTask = require("@lune/task")

export type TaskHandle = thread

type PackedArgs = { n: number, [number]: unknown }

type DelayedEntry = {
	thread: thread,
	wakeAt: number,
	args: PackedArgs,
}

type WaitingEntry = {
	thread: thread,
	wakeAt: number,
	-- Cancelado por identidade da própria entrada (nunca por thread — ver comentário em
	-- Scheduler.new/driver.WakeAfter). Fecha a corrida em que um evento (ex: ChildAdded)
	-- resolve o waiter DEPOIS que `resumeDueWaiting` já tirou a entrada da fila viva para a
	-- lista local `due`, mas antes de `resumeThread` ser chamado para ela.
	cancelled: boolean,
}

type DeferredEntry = {
	thread: thread,
	args: PackedArgs,
}

-- Estado interno do Scheduler: nunca exposto fora deste módulo (o tipo público é
-- `Scheduler`, mais abaixo, que só declara os métodos/sinais que services/cli consomem).
type Internal = {
	time: number,
	delayed: { DelayedEntry },
	waiting: { WaitingEntry },
	deferred: { DeferredEntry },
	liveThreads: { [thread]: boolean },
	running: boolean,
	heartbeatSignal: Signal.FireableSignal<number>,
	steppedSignal: Signal.FireableSignal<number, number>,
	threadErrorSignal: Signal.FireableSignal<thread, string>,
	heartbeatHasConnections: () -> boolean,
	steppedHasConnections: () -> boolean,
	Heartbeat: Signal.Signal<number>,
	Stepped: Signal.Signal<number, number>,
	ThreadError: Signal.Signal<thread, string>,
	-- Driver que este Scheduler registra em ThreadBroker para toda thread que ele cria — ver
	-- ThreadBroker.luau e o comentário de risco no topo deste módulo.
	driver: ThreadBroker.Driver,
}

export type Scheduler = {
	Spawn: <A...>(self: Scheduler, fn: (A...) -> (), A...) -> TaskHandle,
	Defer: <A...>(self: Scheduler, fn: (A...) -> (), A...) -> TaskHandle,
	Delay: <A...>(self: Scheduler, seconds: number, fn: (A...) -> (), A...) -> TaskHandle,
	Wait: (self: Scheduler, seconds: number?) -> number,
	Cancel: (self: Scheduler, handle: TaskHandle) -> (),

	Heartbeat: Signal.Signal<number>,
	Stepped: Signal.Signal<number, number>,
	ThreadError: Signal.Signal<thread, string>,

	Run: (self: Scheduler, shouldContinue: (() -> boolean)?) -> (),
	StepOnce: (self: Scheduler, dt: number) -> (),
	IsAlive: (self: Scheduler) -> boolean,
}

-- Teto de espera ociosa do laço principal entre tiques (ver comentário do módulo acima) --
-- não é uma tentativa de replicar frame rate real do Roblox, que não tem resolução fixa.
local DEFAULT_FRAME_INTERVAL = 1 / 60

-- Embrulha um Signal real (dono é este módulo) numa fachada que só reexpõe Connect/Once/
-- Wait/DisconnectAll (nunca Fire — capacidade de disparo fica só com quem chama Signal.new
-- aqui dentro, nunca no valor devolvido publicamente) e, por cima, rastreia as Connections
-- devolvidas para responder "há conexão viva?" sem precisar que Signal.luau exponha isso:
-- a lista interna é só podada (via o campo público `Connected`, que Signal mantém
-- corretamente em Connect/Once/Disconnect/DisconnectAll/Once-auto-disconnect) sob demanda.
local function wrapTrackedSignal<T...>(underlying: Signal.FireableSignal<T...>): (Signal.Signal<T...>, () -> boolean)
	local connections: { Signal.Connection } = {}

	local function trackedConnect(_self: Signal.Signal<T...>, callback: (T...) -> ()): Signal.Connection
		local connection = underlying:Connect(callback)
		table.insert(connections, connection)
		return connection
	end

	local function trackedOnce(_self: Signal.Signal<T...>, callback: (T...) -> ()): Signal.Connection
		local connection = underlying:Once(callback)
		table.insert(connections, connection)
		return connection
	end

	local function passthroughWait(_self: Signal.Signal<T...>): T...
		return underlying:Wait()
	end

	local function passthroughDisconnectAll(_self: Signal.Signal<T...>)
		underlying:DisconnectAll()
	end

	local proxy: Signal.Signal<T...> = {
		Connect = trackedConnect,
		Once = trackedOnce,
		Wait = passthroughWait,
		DisconnectAll = passthroughDisconnectAll,
	}

	local function hasLiveConnections(): boolean
		local alive: { Signal.Connection } = {}
		for _, connection in connections do
			if connection.Connected then
				table.insert(alive, connection)
			end
		end
		connections = alive
		return #alive > 0
	end

	return proxy, hasLiveConnections
end

-- Dispara um FireableSignal protegido por pcall: ver risco de integração documentado no
-- topo do módulo. Uma continuação de `Signal:Wait()` que erra propaga o erro de volta para
-- este Fire (não é engolida por Signal.luau, de propósito) -- sem esta proteção, esse erro
-- vazaria para dentro de `tick`/`Run()` e derrubaria o laço principal.
local function fireProtected<T...>(threadErrorSignal: Signal.FireableSignal<thread, string>, signal: Signal.FireableSignal<T...>, ...: T...)
	local ok, err = pcall(function(...: T...)
		signal:Fire(...)
	end, ...)
	if not ok then
		threadErrorSignal:Fire(coroutine.running(), tostring(err))
	end
end

-- Ponto único de `coroutine.resume` de threads geridas pelo Scheduler (Spawn/Delay/Defer/
-- Wait). Se a retomada falhar, dispara ThreadError e segue -- nunca propaga, nunca derruba
-- quem chamou `resumeThread`. É esta função, sozinha, que sustenta a garantia central da
-- tarefa: erro de script nunca derruba `Run()`.
local function resumeThread<A...>(self: Internal, co: thread, ...: A...)
	if coroutine.status(co) ~= "suspended" then
		-- Já retomada/morta por outro caminho (corrida deadline x evento, ex: WaitForChild
		-- com timeout resolvido por ChildAdded no mesmo tique em que o deadline também
		-- venceria — ver ThreadBroker.luau e o `cancelled` de WaitingEntry). Só poda o
		-- bookkeeping -- NUNCA dispara ThreadError espúrio de "cannot resume dead coroutine".
		if coroutine.status(co) == "dead" then
			self.liveThreads[co] = nil
			ThreadBroker.Release(co)
			-- task-runtime-011: por simetria com Cancel (ver comentário de topo do módulo),
			-- roda também aqui qualquer limpeza pendente de uma thread que morreu por um
			-- caminho que não passou por Cancel -- no-op para quem nunca registrou nada.
			ThreadBroker.RunCleanups(co)
		end
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		self.liveThreads[co] = nil
		ThreadBroker.Release(co)
		ThreadBroker.RunCleanups(co)
		self.threadErrorSignal:Fire(co, tostring(err))
		return
	end
	if coroutine.status(co) == "dead" then
		self.liveThreads[co] = nil
		ThreadBroker.Release(co)
		ThreadBroker.RunCleanups(co)
	end
end

local function trackThread(self: Internal, co: thread)
	self.liveThreads[co] = true
	ThreadBroker.Adopt(co, self.driver)
end

local function resumeDueDelayed(self: Internal)
	local due: { DelayedEntry } = {}
	local remaining: { DelayedEntry } = {}
	for _, entry in self.delayed do
		if entry.wakeAt <= self.time then
			table.insert(due, entry)
		else
			table.insert(remaining, entry)
		end
	end
	self.delayed = remaining
	for _, entry in due do
		resumeThread(self, entry.thread, table.unpack(entry.args, 1, entry.args.n))
	end
end

local function resumeDueWaiting(self: Internal)
	local due: { WaitingEntry } = {}
	local remaining: { WaitingEntry } = {}
	for _, entry in self.waiting do
		if entry.wakeAt <= self.time then
			table.insert(due, entry)
		else
			table.insert(remaining, entry)
		end
	end
	self.waiting = remaining
	for _, entry in due do
		-- Entrada cancelada entre ser extraída para `due` (acima) e chegar aqui (ex: um
		-- ChildAdded resolveu o mesmo WaitForChild pela via de evento, chamando o
		-- cancelador de WakeAfter, que marca `cancelled` na própria entrada por identidade
		-- em vez de tentar removê-la de `self.waiting`, onde ela já não está mais). Pular
		-- evita um resumeThread redundante sobre uma coroutine já retomada/morta.
		if not entry.cancelled then
			resumeThread(self, entry.thread)
		end
	end
end

-- Drena a fila de `task.defer` até esvaziar, inclusive itens deferidos por um deferred que
-- rodou nesta mesma drenagem (ver aproximação de "resume point" documentada no topo).
local function drainDeferred(self: Internal)
	while #self.deferred > 0 do
		local entry = table.remove(self.deferred, 1)
		if entry then
			resumeThread(self, entry.thread, table.unpack(entry.args, 1, entry.args.n))
		end
	end
end

local function removeFromQueues(self: Internal, handle: TaskHandle)
	local delayed: { DelayedEntry } = {}
	for _, entry in self.delayed do
		if entry.thread ~= handle then
			table.insert(delayed, entry)
		end
	end
	self.delayed = delayed

	local waiting: { WaitingEntry } = {}
	for _, entry in self.waiting do
		if entry.thread ~= handle then
			table.insert(waiting, entry)
		end
	end
	self.waiting = waiting

	local deferred: { DeferredEntry } = {}
	for _, entry in self.deferred do
		if entry.thread ~= handle then
			table.insert(deferred, entry)
		end
	end
	self.deferred = deferred
end

-- Avança um tique: retoma o que já venceu, dispara Stepped, drena deferred, dispara
-- Heartbeat. Usado tanto por `Run` (dt medido de verdade) quanto por `StepOnce` (dt
-- controlado pelo chamador, determinístico -- é o que os testes usam).
local function tick(self: Internal, dt: number)
	self.time += dt

	resumeDueDelayed(self)
	resumeDueWaiting(self)

	-- Stepped antes de Heartbeat: aproxima a ordem relativa real do Roblox (Stepped/
	-- PreSimulation roda antes da simulação de física; Heartbeat roda depois de
	-- PostSimulation) -- não há física aqui, então é só uma ordem coerente, documentada.
	fireProtected(self.threadErrorSignal, self.steppedSignal, self.time, dt)

	drainDeferred(self)

	fireProtected(self.threadErrorSignal, self.heartbeatSignal, dt)
end

-- Quanto tempo o laço principal pode cochilar (via `@lune/task`, nunca sleep bloqueante do
-- SO) até o próximo tique ser útil: até a próxima wake time pendente, com teto de
-- DEFAULT_FRAME_INTERVAL para Heartbeat/Stepped continuarem pulsando mesmo sem nada
-- agendado (ex: script só conectado em Heartbeat, sem task.wait/delay pendente).
local function nextWakeInterval(self: Internal): number
	local earliest: number? = nil
	for _, entry in self.delayed do
		if earliest == nil or entry.wakeAt < earliest then
			earliest = entry.wakeAt
		end
	end
	for _, entry in self.waiting do
		if earliest == nil or entry.wakeAt < earliest then
			earliest = entry.wakeAt
		end
	end
	if earliest == nil then
		return DEFAULT_FRAME_INTERVAL
	end
	local remaining = earliest - self.time
	if remaining < 0 then
		remaining = 0
	end
	return math.min(remaining, DEFAULT_FRAME_INTERVAL)
end

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.Spawn<A...>(self: Internal, fn: (A...) -> (), ...: A...): TaskHandle
	local co = coroutine.create(fn)
	trackThread(self, co)
	-- task.spawn roda imediatamente, de forma síncrona, até o primeiro yield ou término --
	-- confirmado tanto para o Roblox real quanto para o Lune (pesquisa, seção 1).
	resumeThread(self, co, ...)
	return co
end

function Scheduler.Defer<A...>(self: Internal, fn: (A...) -> (), ...: A...): TaskHandle
	local co = coroutine.create(fn)
	trackThread(self, co)
	local args = table.pack(...) :: PackedArgs
	table.insert(self.deferred, { thread = co, args = args })
	return co
end

function Scheduler.Delay<A...>(self: Internal, seconds: number, fn: (A...) -> (), ...: A...): TaskHandle
	local co = coroutine.create(fn)
	trackThread(self, co)
	local args = table.pack(...) :: PackedArgs
	table.insert(self.delayed, { thread = co, wakeAt = self.time + seconds, args = args })
	return co
end

function Scheduler.Wait(self: Internal, seconds: number?): number
	local duration = if seconds and seconds > 0 then seconds else 0
	local co = coroutine.running()
	if not self.liveThreads[co] then
		error("Scheduler:Wait só pode ser chamado de dentro de uma thread gerida pelo Scheduler (task.spawn/task.delay/script principal)", 2)
	end
	local startedAt = self.time
	table.insert(self.waiting, { thread = co, wakeAt = self.time + duration, cancelled = false })
	coroutine.yield()
	return self.time - startedAt
end

function Scheduler.Cancel(self: Internal, handle: TaskHandle)
	removeFromQueues(self, handle)
	self.liveThreads[handle] = nil
	ThreadBroker.Release(handle)
	-- task-runtime-011: desconecta, no MOMENTO do cancelamento, toda Connection que a thread
	-- cancelada registrou via ThreadBroker.RegisterCleanup -- não espera o Signal de origem
	-- disparar de novo (ver ThreadBroker.luau para o mecanismo e a pendência declarada sobre
	-- Instance.luau/Signal.luau ainda não chamarem RegisterCleanup nos pontos que vazam hoje).
	ThreadBroker.RunCleanups(handle)
	local status = coroutine.status(handle)
	if status ~= "running" and status ~= "normal" then
		-- Segue a doc do Roblox real: Cancel fecha a thread, nunca deixa retomar de novo
		-- (manualmente ou pelo scheduler). "dead" também é seguro de fechar (vira no-op).
		coroutine.close(handle)
	end
end

function Scheduler.IsAlive(self: Internal): boolean
	-- Rede de segurança (pedida pelo revisor): com o roteamento por ThreadBroker, podar aqui
	-- não é mais o mecanismo principal que mantém `liveThreads` correto (resumeThread já poda
	-- na hora), mas protege contra qualquer coroutine gerida que tenha morrido por um
	-- caminho que este módulo não previu.
	for co in self.liveThreads do
		if coroutine.status(co) == "dead" then
			self.liveThreads[co] = nil
			ThreadBroker.Release(co)
			ThreadBroker.RunCleanups(co)
		end
	end
	if next(self.liveThreads) ~= nil then
		return true
	end
	if self.heartbeatHasConnections() or self.steppedHasConnections() then
		return true
	end
	return false
end

function Scheduler.StepOnce(self: Internal, dt: number)
	tick(self, dt)
end

function Scheduler.Run(self: Internal, shouldContinue: (() -> boolean)?)
	self.running = true
	local lastClock = os.clock()
	while Scheduler.IsAlive(self) and (shouldContinue == nil or shouldContinue()) do
		local now = os.clock()
		local dt = now - lastClock
		lastClock = now
		tick(self, dt)

		if not (Scheduler.IsAlive(self) and (shouldContinue == nil or shouldContinue())) then
			break
		end

		local sleepFor = nextWakeInterval(self)
		if sleepFor > 0 then
			-- Cochilo real via timer assíncrono do Lune (nunca `os`/sleep bloqueante do SO --
			-- pesquisa seção 1 confirma que `task.wait` do Lune é um `Timer::after` async, não
			-- um `Sleep` de SO). Isto paceia só o laço principal; `task.wait` do script do
			-- usuário nunca chama isto diretamente -- passa por `Scheduler:Wait` acima.
			LuneTask.wait(sleepFor)
		end
	end
	self.running = false
end

function Scheduler.new(): Scheduler
	local heartbeatFireable: Signal.FireableSignal<number> = Signal.new()
	local steppedFireable: Signal.FireableSignal<number, number> = Signal.new()
	local threadErrorFireable: Signal.FireableSignal<thread, string> = Signal.new()

	local heartbeatPublic, heartbeatHasConnections = wrapTrackedSignal(heartbeatFireable)
	local steppedPublic, steppedHasConnections = wrapTrackedSignal(steppedFireable)

	-- Forward-declare de `raw` (mesmo padrão de `local self: FireableSignal<T...>` em
	-- Signal.new): as três closures do driver capturam `raw` por upvalue e só são chamadas
	-- depois que `raw` já foi de fato atribuído, mais abaixo -- construir o driver antes do
	-- `Internal` é necessário porque `Internal.driver` exige o driver pronto.
	local raw: Internal
	local driver: ThreadBroker.Driver = {
		Resume = function(co: thread, args: ThreadBroker.PackedArgs?)
			if args == nil then
				resumeThread(raw, co)
			else
				resumeThread(raw, co, table.unpack(args, 1, args.n))
			end
		end,

		WakeAfter = function(co: thread, seconds: number): () -> ()
			local entry: WaitingEntry = { thread = co, wakeAt = raw.time + math.max(seconds, 0), cancelled = false }
			table.insert(raw.waiting, entry)
			local cancelled = false
			return function()
				if cancelled then
					return
				end
				cancelled = true
				-- Remove por IDENTIDADE DA ENTRADA, nunca por thread -- `removeFromQueues`
				-- (usado por Cancel) continua removendo por thread; as duas disciplinas não
				-- podem se confundir (uma mesma thread poderia, em tese, ter mais de uma
				-- entrada pendente em cenários futuros).
				entry.cancelled = true
				local index = table.find(raw.waiting, entry)
				if index then
					table.remove(raw.waiting, index)
				end
			end
		end,

		ReportError = function(co: thread, message: string)
			raw.threadErrorSignal:Fire(co, message)
		end,
	}

	raw = {
		time = 0,
		delayed = {},
		waiting = {},
		deferred = {},
		liveThreads = {},
		running = false,
		heartbeatSignal = heartbeatFireable,
		steppedSignal = steppedFireable,
		threadErrorSignal = threadErrorFireable,
		heartbeatHasConnections = heartbeatHasConnections,
		steppedHasConnections = steppedHasConnections,
		Heartbeat = heartbeatPublic,
		Stepped = steppedPublic,
		-- ThreadError não precisa de rastreio de conexões (IsAlive só olha Heartbeat/
		-- Stepped, conforme o desenho) -- exposto direto; a capacidade de Fire fica só no
		-- `threadErrorFireable` interno, nunca no tipo público `Signal<thread, string>`.
		ThreadError = threadErrorFireable :: Signal.Signal<thread, string>,
		driver = driver,
	}

	-- `Internal` (dados) e `Scheduler` (dados públicos + métodos resolvidos via metatable
	-- __index) não têm overlap estrutural suficiente para o checker aceitar um `::` direto
	-- -- os métodos só existem via despacho de metatable, invisível para a análise
	-- estrutural. Cast em duas etapas via `unknown` (nunca `any`, regra 01 -- achado MÉDIO 5
	-- da revisão pós-integração 2026-09-04, mesmo padrão já usado em Instance.luau:74/
	-- ThreadBroker.luau para `internals`/`drivers`): nenhuma assinatura pública fica com
	-- `unknown`/`any`, só a mecânica interna deste cast.
	local self = (setmetatable(raw, Scheduler) :: unknown) :: Scheduler
	return self
end

return Scheduler
