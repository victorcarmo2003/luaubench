--!strict

--[[
	Módulo-folha do território `runtime`: diz quem é o dono (driver) de uma thread e roteia
	retomada/agendamento/erro para esse dono, com fallback correto quando não há dono.

	Motivação (revisão pós-integração 2026-09-04, ver
	.claude/agents-memory/arquiteto-runtime-2026-09-04.md, seção "Revisão pós-integração
	2026-09-04 — contrato Wait/resume"): o desenho original definiu um ponto único de
	`coroutine.resume` dentro de Scheduler.luau, mas não definiu um ponto único de
	`coroutine.yield` — quem precisa suspender uma thread (Signal:Wait, Instance:WaitForChild
	com timeout) não podia falar com o Scheduler sem importá-lo, e a proibição de importar
	(evita ciclo de require) estava certa, mas forçava cada módulo a inventar seu próprio par
	yield/resume. Isso quebrava o bookkeeping de `liveThreads` do Scheduler (thread gerida
	terminava por fora do seu ponto único de resume) e atribuía erro à thread errada em
	ThreadError. ThreadBroker resolve isso por identidade de thread: quem suspende pergunta
	"esta thread tem dono?" e o dono aparece sozinho — a mesma inversão de dependência que o
	desenho já usa para IsA (Instance.SetClassChain em vez de Instance -> ClassRegistry).

	SEM NENHUMA dependência de módulo do runtime (nem de Scheduler.luau, nem de @lune/task) —
	é o driver (hoje só Scheduler.luau) que se registra aqui, nunca o contrário. Isso mantém o
	grafo de dependências do território acíclico: ThreadBroker.luau -> nada; Signal.luau ->
	ThreadBroker; Instance.luau -> Signal, ThreadBroker (+ @lune/task só no caminho standalone
	de WaitForChild); Scheduler.luau -> Signal, ThreadBroker (+ @lune/task).

	NÃO reexportado por src/runtime/init.luau — é plumbing interno de `runtime`; `services`/
	`cli` nunca o tocam nem sabem que existe.

	task-runtime-011 (achado MÉDIO de task-runtime-008, ver
	.claude/agents-memory/revisor-runtime-patch-threadbroker-2026-09-04.md): `Scheduler:Cancel`
	só desfazia o bookkeeping do próprio Scheduler — uma Connection que a thread cancelada
	tinha registrado num Signal alheio (ex: ChildAdded de um WaitForChild com timeout, ou o
	listener interno de Signal:Wait) ficava pendurada até o evento disparar de novo (ou para
	sempre). RegisterCleanup/RunCleanups (abaixo) fecham essa lacuna por identidade de thread,
	com o MESMO padrão de mapa fraco já usado para `drivers`: quem cria uma Connection "em
	nome" de uma thread gerida pode registrar aqui como desfazê-la, e o driver (hoje só
	Scheduler:Cancel, mas também os pontos de poda por morte natural/erro em Scheduler.luau)
	chama RunCleanups no momento em que a thread deixa de poder ser retomada — nunca espera o
	evento disparar de novo.

	PENDÊNCIA DECLARADA (regra 00 — divergência/limitação nunca silenciosa): esta tarefa
	entrega o mecanismo dentro do território `Scheduler.luau`/`ThreadBroker.luau` e prova ele
	com teste em Scheduler.spec.luau, mas os dois pontos de PRODUÇÃO que hoje vazam de verdade
	— Instance.luau (WaitForChild ramo B, Connection de `data.childAdded:Connect`) e
	Signal.luau (`Wait`, listener interno) — estão fora do território desta tarefa e por isso
	NÃO foram alterados para chamar `ThreadBroker.RegisterCleanup`. O mecanismo está pronto,
	testado e não quebra nada existente (é no-op para qualquer thread que nunca registrar uma
	limpeza, que é o caso de 100% do código de produção hoje) — mas só fecha de fato o
	vazamento relatado pelo revisor quando uma tarefa de acompanhamento, com permissão para
	tocar Instance.luau/Signal.luau, ligar os dois pontos de criação de Connection a este
	registro. Ver relatório de task-runtime-011.
]]

-- Argumentos empacotados (mesmo formato interno que Scheduler.luau já usa em Delay/Defer).
-- Trafegar os args como TABELA, e não como pack variádico, é deliberado: mantém o tipo
-- honesto (`unknown`, nunca `any`) sem tentar casar um pack genérico `T...` com `...unknown`.
export type PackedArgs = { n: number, [number]: unknown }

-- Implementado por Scheduler.luau (hoje o único driver do projeto). ThreadBroker NUNCA
-- importa Scheduler.luau — é o driver que se registra, invertendo a dependência.
export type Driver = {
	-- Retoma `co` pelo ponto único de resume do driver. Contrato obrigatório:
	-- (a) NUNCA propaga erro para quem chamou (converte em ThreadError e segue);
	-- (b) é no-op silencioso se `coroutine.status(co) ~= "suspended"` (corrida entre
	--     deadline e evento não pode virar erro espúrio de "cannot resume dead coroutine");
	-- (c) `args == nil` significa retomar sem argumentos.
	Resume: (co: thread, args: PackedArgs?) -> (),

	-- Agenda a retomada de `co` daqui a `seconds` NO RELÓGIO DO DRIVER (nunca em timer
	-- nativo do Lune). Devolve um cancelador idempotente; cancelar depois de já ter
	-- acordado é no-op.
	WakeAfter: (co: thread, seconds: number) -> (() -> ()),

	-- Canal central de erro do driver (vira ThreadError no Scheduler).
	ReportError: (co: thread, message: string) -> (),
}

local ThreadBroker = {}

-- Storage: mapa fraco por chave — uma thread sem mais referências externas (já morta e sem
-- ninguém segurando o handle) pode ser coletada pelo GC junto com sua entrada aqui, sem
-- precisar de Release() explícito para não vazar. Mesmo padrão (e mesmo cast em duas etapas
-- por `unknown`, nunca `any`, regra 01) já usado em Instance.luau:74 para `internals`.
local drivers: { [thread]: Driver } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [thread]: Driver }

-- Chamado pelo driver uma vez por thread que ele cria (Spawn/Defer/Delay).
function ThreadBroker.Adopt(co: thread, driver: Driver): ()
	drivers[co] = driver
end

function ThreadBroker.Release(co: thread): ()
	drivers[co] = nil
end

function ThreadBroker.DriverOf(co: thread): Driver?
	return drivers[co]
end

function ThreadBroker.IsManaged(co: thread): boolean
	return drivers[co] ~= nil
end

-- Retoma `co`: pelo driver dono se houver; senão `coroutine.resume` cru, re-lançando o erro
-- via `error(err, 0)` — exatamente o comportamento de hoje, que é o que mantém `Signal`
-- utilizável sem Scheduler (Signal.spec.luau, 6/6, não pode quebrar).
function ThreadBroker.Resume(co: thread, args: PackedArgs?): ()
	local driver = drivers[co]
	if driver ~= nil then
		driver.Resume(co, args)
		return
	end

	-- Fallback standalone (sem driver): mesmo comportamento de hoje. No-op silencioso se a
	-- thread não estiver suspensa (já retomada/morta por outro caminho) — nunca erro espúrio.
	if coroutine.status(co) ~= "suspended" then
		return
	end

	-- ATENÇÃO: um `if...then...else` de Luau é uma EXPRESSÃO de valor único — não repassa os
	-- dois retornos de `coroutine.resume` (verificado com luau-lsp: "Expression list has 1
	-- value, but 2 are required here" ao tentar `local ok, err = if args == nil then
	-- coroutine.resume(co) else coroutine.resume(co, ...)"). Por isso o branch fica como
	-- statement `if`, não como expressão.
	if args == nil then
		local ok, err = coroutine.resume(co)
		if not ok then
			error(err, 0)
		end
	else
		local ok, err = coroutine.resume(co, table.unpack(args, 1, args.n))
		if not ok then
			error(err, 0)
		end
	end
end

-- Entrega uma falha ao driver dono de `co`. Devolve `true` se algum driver assumiu o erro,
-- `false` se não há dono — nesse caso quem chamou decide (Signal acumula e re-lança DEPOIS
-- de rodar todos os listeners; ver patch de Fire em Signal.luau).
function ThreadBroker.ReportError(co: thread, message: string): boolean
	local driver = drivers[co]
	if driver ~= nil then
		driver.ReportError(co, message)
		return true
	end
	return false
end

-- Registro de limpeza por thread (task-runtime-011, ver comentário de topo do módulo) —
-- independente de `drivers`: funciona mesmo para uma thread sem driver (uso standalone de
-- Signal.luau), e sobrevive à ordem em que `Release`/`Adopt` são chamados. Mapa fraco por
-- chave, mesmo padrão de `drivers` acima: uma thread sem referência externa pode ser
-- coletada junto com sua lista de limpezas, sem precisar de RunCleanups explícito para não
-- vazar.
local cleanups: { [thread]: { () -> () } } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [thread]: { () -> () } }

-- Registra `cleanup` para rodar quando `co` deixar de poder ser retomada (ver RunCleanups).
-- Devolve um desregistro IDEMPOTENTE: quem registrou (ex: Instance.luau desconectando a
-- própria Connection pelo caminho normal, antes de qualquer cancelamento) pode chamá-lo para
-- remover a própria limpeza da lista, evitando um Disconnect duplicado (inofensivo, mas
-- redundante) quando a thread terminar por outro caminho depois.
function ThreadBroker.RegisterCleanup(co: thread, cleanup: () -> ()): () -> ()
	local list = cleanups[co]
	if list == nil then
		list = {}
		cleanups[co] = list
	end
	table.insert(list, cleanup)

	local unregistered = false
	return function()
		if unregistered then
			return
		end
		unregistered = true
		local currentList = cleanups[co]
		if currentList == nil then
			return
		end
		local index = table.find(currentList, cleanup)
		if index then
			table.remove(currentList, index)
		end
	end
end

-- Executa e descarta todas as limpezas pendentes de `co`. Chamado pelo driver no momento em
-- que a thread deixa de poder ser retomada (Cancel; e, por simetria/rede de segurança, morte
-- natural ou por erro — ver resumeThread/IsAlive em Scheduler.luau) — nunca espera o evento
-- de origem da limpeza disparar de novo. Cada limpeza roda isolada por pcall individual: erro
-- numa NUNCA impede as demais nem propaga para quem chamou RunCleanups (mesma disciplina de
-- Signal.Fire/resumeThread — limpeza jamais derruba quem a invoca). No-op silencioso se `co`
-- nunca registrou nenhuma limpeza (o caso de toda thread de produção hoje, ver PENDÊNCIA
-- DECLARADA no topo do módulo).
function ThreadBroker.RunCleanups(co: thread): ()
	local list = cleanups[co]
	if list == nil then
		return
	end
	cleanups[co] = nil
	for _, cleanup in list do
		pcall(cleanup)
	end
end

return ThreadBroker
