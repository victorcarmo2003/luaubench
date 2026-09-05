--!strict

--[[
	Ponto ÚNICO de suspensão (yield) de `services` -- extensão do LuauBench, portanto FORA do
	namespace simulado de qualquer classe real (regra 00), ao lado de RejectingSignal.luau/
	Context.luau. Toda a leva 3 do plano de cobertura (DataStore/HttpService/MessagingService/
	TweenService) é feita de métodos com a tag `Yields` no dump (`GetAsync`, `SetAsync`,
	`UpdateAsync`, `RemoveAsync`, `PublishAsync`, `SubscribeAsync`, `RequestAsync`,
	`AdvanceToNextPageAsync`, ...) -- no Roblox real eles suspendem a thread chamadora; no
	LuauBench a única primitiva de suspensão é `Runtime.Scheduler:Wait(seconds)`. Ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.0.1 -- src/services/AsyncCall.luau:
	o único ponto de yield de services", desenho completo.

	COMPORTAMENTO de `AsyncCall.Yield`:
	1. `Context.GetScheduler():Wait(0)` -- um passo de scheduler, LATÊNCIA SIMULADA ZERO.
	2. Se a thread corrente não é gerida pelo Scheduler, `Scheduler.Wait` erra em português --
	   mensagem de ENGENHARIA INTERNA (ver src/runtime/Scheduler.luau, `Scheduler.Wait`: "...só
	   pode ser chamado de dentro de uma thread gerida pelo Scheduler..."). Esse erro é CAPTURADO
	   e RETRADUZIDO para uma mensagem `[LuauBench]` em inglês, NÍVEL 3 (culpa o call site do
	   SCRIPT que chamou o método real, ex.: `store:GetAsync(...)`, não o call site deste módulo
	   nem o do método que o envolve) -- a string em português NUNCA vaza para o Output do
	   usuário. Isto NÃO é o "pcall silencioso" que a regra 01 proíbe ("nunca pcall que engole
	   erro sem logar ou repassar"): o erro é sempre REPASSADO logo abaixo, só que reescrito --
	   mesmo padrão que `RejectingSignal.luau` já usa para outra família de mensagem que não pode
	   vazar para o script do usuário.

	POR QUE NÍVEL 3, NÃO 2: a pilha nesta chamada é [AsyncCall.Yield] <- [método real de
	`services`, ex. `GlobalDataStore.GetAsync`] <- [call site do script do usuário]. O `error()`
	de retradução roda direto no corpo de `AsyncCall.Yield` (fora do fechamento passado a
	`pcall`), então a contagem de nível não é afetada pelo frame extra que o `pcall` insere --
	nível 1 é a própria `AsyncCall.Yield`, nível 2 é quem a chamou (o método real), nível 3 é quem
	chamou o método real (o script). Mesmo raciocínio de contagem de frames já documentado em
	`src/runtime/ClassRegistry.luau` para os níveis de `SetClassMethods`/`SetClassSchema`.

	POR QUE LATÊNCIA ZERO, E NÃO UMA LATÊNCIA "REALISTA" (divergência declarada -- regra 00,
	invariante 2): `Scheduler.Run` avança o relógio por `os.clock()` REAL (`Scheduler.luau`) --
	`task.wait(n)` custa `n` segundos de parede de verdade. Injetar 50-200 ms por chamada de
	DataStore transformaria um cenário de ProfileStore com dezenas de operações em dezenas de
	segundos de espera por execução de `luaubench run`, e introduziria variação de tempo em
	testes que devem ser determinísticos. O valor de simular latência é pegar bug de corrida; o
	custo é tornar a ferramenta lenta e os testes instáveis. Um passo de scheduler é o mínimo
	honesto: o ponto de suspensão existe de verdade (outra thread roda no meio, `task.wait`
	concorrente intercala, código que assume atomicidade entre leitura e escrita quebra aqui
	como quebraria no Roblox) -- só não custa tempo de parede.

	DIVERGÊNCIA DECLARADA: nenhuma chamada async do LuauBench tem latência de rede -- uma corrida
	que só se manifesta com uma janela de centenas de milissegundos não é reproduzida aqui. Um
	modo `--async-latency <ms>` fica REGISTRADO COMO EXTENSÃO FUTURA do LuauBench, e precisa
	viver fora do namespace de qualquer classe simulada (regra 00) -- ex.: uma flag de `cli`
	injetada via `Context`/`BootstrapOptions`, nunca uma propriedade dentro de uma classe do dump.

	CONSEQUÊNCIA PARA A LIVENESS DO SCHEDULER: `Wait(0)` enfileira a thread em `self.waiting` (ver
	`Scheduler.luau`), logo `Scheduler.IsAlive` continua verdadeiro e o laço principal a acorda no
	tique seguinte -- nenhuma chamada async "perde" a thread do usuário.

	Todo método com a tag `Yields` no Roblox API Dump passa por aqui (tarefas futuras da leva 2/3
	de `services`, ex.: `GlobalDataStore.luau`, `HttpService.luau`, `MessagingService.luau`,
	`TweenService.luau`).

	Depende só de `./Context` (para alcançar o Scheduler do processo corrente). Não guarda estado
	próprio de módulo -- é plumbing fina sobre Context+Scheduler.
]]

local Context = require("./Context")

local AsyncCall = {}

-- `label` é o nome qualificado do método real (ex.: "GlobalDataStore:GetAsync") -- só aparece na
-- mensagem de erro do caso patológico (thread não gerida pelo Scheduler); no caminho feliz não é
-- usado para nada além de documentar, para quem lê o comportamento, qual chamada real está
-- suspendendo.
function AsyncCall.Yield(label: string): ()
	local scheduler = Context.GetScheduler()

	-- pcall aqui NÃO é o "pcall silencioso" que a regra 01 proíbe: o erro capturado é SEMPRE
	-- repassado abaixo (reescrito, nunca descartado). O `error()` final fica FORA deste
	-- fechamento de propósito -- ver "POR QUE NÍVEL 3" no cabeçalho para o porquê disso importar
	-- para a contagem de frames.
	local ok = pcall(function()
		scheduler:Wait(0)
	end)

	if not ok then
		error(
			`[LuauBench] {label} can only yield from a thread managed by LuauBench's scheduler (a Script's main thread, or a thread started via task.spawn/task.delay) -- it was called from a thread the scheduler does not track (e.g. a raw coroutine.create/coroutine.wrap, or code running outside any scheduled thread)`,
			3
		)
	end
end

return AsyncCall
