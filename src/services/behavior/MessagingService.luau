--!strict

--[[
	Behavior de `MessagingService` -- task-services-021. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, seção "L2.3 -- `MessagingService`: o
	eco local é fiel, não é uma concessão" (L2.3.1/L2.3.2/L2.3.3) INTEIRA antes de mexer aqui.

	SUPERFÍCIE (confirmada no dump, .claude/agents-memory/pesquisa-http-messaging-2026-09-05.md,
	seção A): só `PublishAsync(topic, message)` e `SubscribeAsync(topic, callback)`, ambos com a
	tag `Yields`. Nenhuma propriedade, nenhum evento -- o recebimento é um CALLBACK LUAU PURO
	passado direto a `SubscribeAsync`, nunca um `RBXScriptSignal` reemitido por uma Instance.

	## O ECO LOCAL É FIEL (L2.3.1) -- NUNCA FILTRAR O PRÓPRIO PUBLISHER

	Pesquisa confirma por evidência forte de comunidade (dois threads DevForum independentes, um
	com sintoma observado e correção testada por filtro de `game.JobId`): o servidor que publica
	RECEBE O PRÓPRIO ECO quando está inscrito no mesmo tópico. Um LuauBench de processo único é
	portanto uma simulação FIEL de um jogo Roblox com exatamente um servidor -- `PublishAsync` num
	tópico que ESTE MESMO processo assina DEVE entregar a todos os callbacks inscritos, inclusive
	os que o próprio código que chamou `PublishAsync` registrou. Por isso este módulo NÃO faz
	nenhuma checagem de identidade/origem antes de despachar -- ausência de filtro é a decisão
	certa, não uma omissão.

	## ENTREGA ASSÍNCRONA (nunca síncrona dentro de PublishAsync)

	`PublishAsync` valida os argumentos, yielda UM passo via `../AsyncCall.luau`
	(`Context.GetScheduler():Wait(0)`), e só DEPOIS de retomado despacha cada callback inscrito
	via `scheduler:Spawn(...)` -- uma COROUTINE NOVA por callback, nunca uma chamada direta dentro
	do frame de `PublishAsync`. Isto não é só fidelidade decorativa: no Roblox real a entrega passa
	pela rede, então um script com reentrância (ex.: o próprio callback chamando `PublishAsync` de
	volta, ou fazendo algo que dependeria de não estar "dentro" da chamada original) se comporta
	igual aqui e lá -- entregar de forma síncrona faria esse tipo de código passar no LuauBench e
	falhar em produção real. `Scheduler.Spawn` roda a nova coroutine imediatamente até o primeiro
	yield (confirmado em `src/runtime/Scheduler.luau`), então o callback pode terminar de rodar
	ainda dentro do mesmo `scheduler:StepOnce`/tique que resolveu o `Wait(0)` de `PublishAsync` --
	mas SEMPRE na sua PRÓPRIA thread, isolada da thread que chamou `PublishAsync`. É essa separação
	de thread, não uma latência de parede, que a tarefa pede ("nunca síncrono dentro do
	PublishAsync") -- mesma disciplina de latência simulada zero já documentada no cabeçalho de
	`../AsyncCall.luau`.

	## ISOLAMENTO DE ERRO ENTRE CALLBACKS -- DE GRAÇA, PELO PRÓPRIO SCHEDULER

	Cada callback roda na sua própria coroutine, criada por `scheduler:Spawn`. Erro dentro dela
	NUNCA propaga para `PublishAsync` nem para os callbacks seguintes: `Scheduler.resumeThread`
	(mecanismo já existente, não deste módulo) captura a falha, dispara `ThreadError` e segue --
	exatamente a garantia central do runtime (regra 02: "erro não tratado dentro de uma
	coroutine/task.spawn não derruba o processo"). Este módulo não precisa de nenhum `pcall`
	próprio para isso -- envolver o callback num `pcall` manual DUPLICARIA a proteção que o
	Scheduler já dá e esconderia o erro do mecanismo real de `ThreadError` (regra 01: "nunca pcall
	silencioso que engole erro sem logar ou repassar").

	## ORDEM DE ENTREGA -- ORDEM DE INSCRIÇÃO (APROXIMAÇÃO DECLARADA)

	`subscriptionsByTopic[topic]` é uma lista, nunca um conjunto -- `PublishAsync` despacha na
	ordem em que `SubscribeAsync` foi chamado. O Roblox real NÃO garante ordem de entrega entre
	assinantes (mensagens cruzam servidores por uma infraestrutura distribuída) -- esta é uma
	APROXIMAÇÃO DECLARADA (regra 00), determinística e testável, não uma garantia do Roblox.

	## SEM CROSS-SERVER

	`subscriptionsByTopic` é estado ÚNICO de processo (module-local) -- não existe conceito de
	"outro servidor" no LuauBench. Divergência já aceita pelo projeto (L2.3.2, tabela): um
	`PublishAsync` daqui NUNCA alcança "outro servidor" porque não existe outro.

	## VALIDAÇÃO -- SÓ TAMANHO DA MENSAGEM E TAMANHO DO TÓPICO

	Confirmado pela doc oficial (pesquisa, seção C.4): mensagem <= 1 kB, tópico entre 1 e 80
	caracteres. Ambos síncronos, ANTES do `AsyncCall.Yield` -- mesma disciplina já usada por
	`GlobalDataStore.luau` (validar argumento antes de "yieldar pra rede": um erro de argumento não
	deveria depender de um round-trip). Mensagens de erro são APROXIMAÇÃO DE BOA-FÉ, família
	Roblox (inglês, sem prefixo `[LuauBench]` -- este erro TEM contraparte real, só a string exata
	não está confirmada por citação viva, mesma disciplina de `../datastore/Value.luau`).

	## AUDITORIA -- `OnMessagePublished`, task-services-032 (SEM PERSISTÊNCIA -- decisão do
	## arquiteto)

	LER `.claude/agents-memory/arquiteto-persistencia-cloud-2026-09-06.md`, seção 7, INTEIRA antes
	de mexer nesta seção. Resumo: `MessagingService` NÃO ganha persistência nenhuma entre execuções
	do `luaubench run` -- e isso é FIDELIDADE, não economia de escopo. No Roblox real o pub/sub é
	efêmero: `PublishAsync` entrega só a quem já está inscrito NAQUELE MOMENTO, não existe mensagem
	pendente, fila nem backlog. Persistir "mensagens pendentes" inventaria um comportamento que a
	classe real NÃO TEM dentro do namespace da classe real -- proibido pela regra 00, invariante 1.

	O que serve a intenção de observabilidade sem mentir sobre o comportamento real é um canal de
	AUDITORIA, MESMO padrão exato já usado por `HttpService.luau`/`Context.NotifyHttpRequest`
	(`OnHttpRequest`, task-services-026/task-cli-026): `Context.NotifyMessagePublished(topic,
	byteSize)`, chamada UMA VEZ por `PublishAsync` bem-sucedido -- DEPOIS que `assertValidTopic`/
	`assertValidMessage` já deixaram passar (uma publicação que ERRA na validação nunca chega a
	chamar isto -- nada foi publicado de verdade, nada para auditar), e ANTES do `AsyncCall.Yield`
	-- mesma posição relativa que `auditOutgoingRequest` ocupa em `HttpService.luau` (validação ->
	auditoria -> yield -> efeito de verdade).

	`byteSize` é o MESMO valor que `assertValidMessage` já calculou via `Value.EstimateByteSize`
	para decidir se a mensagem passa do limite de 1024 bytes -- `assertValidMessage` passou a
	DEVOLVER esse número (em vez de `()`) para que a auditoria reaproveite a MESMA medição, nunca
	recalculando-a uma segunda vez.

	NUNCA o corpo da mensagem: `topic`/`byteSize` são os dois ÚNICOS parâmetros -- mesma disciplina
	de `OnHttpRequest` nunca logar corpo/headers (regra 00/07, dado do usuário não sai do LuauBench
	por um canal que o script não pediu). `Types.BootstrapOptions.OnMessagePublished` é `nil` por
	padrão -- `Context.NotifyMessagePublished` vira NO-OP nesse caso, nunca erro.

	NÃO VALIDADO DE PROPÓSITO (fora do acceptance desta tarefa, e a pesquisa não confirma a lista
	exata de tipos aceitos por `message` além de string -- ver pesquisa, seção C.5, "NÃO
	CONFIRMADO"): este módulo não rejeita `message` de tipo função/thread/userdata. `message` é
	entregue como está (depois de `Value.DeepCopy`, ver abaixo) -- se um script passar um valor que
	o Roblox real rejeitaria, o LuauBench diverge por OMISSÃO aqui (aceita algo que o Roblox real
	recusaria), não por comissão. Registrado como pendência para quando a pesquisa confirmar a
	lista exata.

	Tamanho da mensagem: reaproveita `../datastore/Value.luau` (`EstimateByteSize`/`DeepCopy`) --
	módulo-folha, sem `Instance`, já testado, já é a fonte única de "quantos bytes um valor Luau
	ocuparia serializado" no território. Reimplementar essa estimativa aqui duplicaria a mesma
	lógica recursiva por um segundo limite de tamanho (1 kB em vez de 4 MiB) -- a MENSAGEM de erro
	usada é a de `MessagingService`, própria deste módulo (nunca a de `DataStore` que
	`Value.AssertByteSize` produziria) -- só a MEDIÇÃO é reaproveitada, nunca o texto.

	## DEEP COPY POR ASSINANTE

	Cada assinante recebe sua PRÓPRIA cópia profunda de `message` (`Value.DeepCopy`, chamada uma
	vez por callback despachado, não uma vez por `PublishAsync`) -- fiel ao Roblox real, onde a
	mensagem atravessa serialização/desserialização de rede para CADA servidor que a recebe: dois
	assinantes nunca compartilham a mesma referência de tabela, e nenhum deles compartilha
	referência com o valor original que o publisher passou. Sem isto, um assinante mutando
	`message.Data` vazaria a mutação para os assinantes seguintes (ainda não despachados) e para o
	publisher -- exatamente o alias silencioso que `../datastore/Value.luau` já documenta evitar
	para DataStore (regra 00).

	## LIMITES DE TAXA -- NÃO SIMULADOS (mesma conta de L2.1.4)

	`600 + 240*jogadores` publicações/min, `20 + 8*jogadores` assinaturas/min etc. NÃO são
	simulados: a fórmula soma um termo por jogador e o LuauBench tem ZERO jogadores por decisão já
	tomada (`Players.GetPlayers() == {}`) -- simular a fórmula real daria o orçamento MÍNIMO e
	quebraria código que roda folgado em produção (falha por comissão, pior que a omissão).

	## ASSINATURA VIVA NÃO MANTÉM O SCHEDULER VIVO

	Verificado por leitura de `src/runtime/Scheduler.luau`, `Scheduler.IsAlive`: só considera o
	Scheduler vivo se houver (a) alguma thread em `liveThreads`, ou (b) conexão viva em
	`Heartbeat`/`Stepped`. `subscriptionsByTopic` (este módulo) é uma tabela module-local comum --
	nunca registra uma thread, nunca é uma Connection de `Heartbeat`/`Stepped`. Por construção,
	nenhuma assinatura de `MessagingService`, por mais tempo que fique aberta, mantém
	`Scheduler:Run(...)` rodando -- exatamente o comportamento pedido ("senão um SubscribeAsync
	solto travaria o luaubench run para sempre"), sem precisar de nenhum código extra aqui para
	garantir isso.

	## BLOQUEIO REPORTADO (fora do território desta tarefa) -- `MessagingService` NÃO está em
	`tools/coverage.luau` nem em `src/services/generated/**` ainda (confirmado nesta tarefa: nem o
	nome aparece em `tools/coverage.luau`, nem existe `generated/classes/MessagingService.luau`,
	nem uma entrada em `generated/Index.luau` -- só a entrada `Covered = false` herdada do
	manifesto de 916 classes). Território desta tarefa é só `behavior/MessagingService.luau` +
	spec + `behavior/Index.luau`/spec -- `tools/`/`generated/` estão EXPLICITAMENTE fora do escopo
	desta task. Consequência PRÁTICA: `Services.Register()` (`src/services/init.luau`) itera só
	`generated/Index.luau`, então a entrada `MessagingService` que este arquivo acrescenta em
	`behavior/Index.luau` fica PRONTA MAS INERTE até uma tarefa futura (regeneração via
	`lune run tools/generate-services`, depois de acrescentar `"MessagingService"` a
	`tools/coverage.luau`) criar `generated/classes/MessagingService.luau` -- nesse momento o
	`Behavior` já registrado aqui passa a ser lido automaticamente por `Services.Register()`, sem
	precisar tocar este arquivo de novo. Até lá, `game:GetService("MessagingService")` continua
	errando `[LuauBench] MessagingService exists in the Roblox API Dump ... but is not simulated by
	LuauBench yet` (comportamento correto e intencional da regra 03 -- nunca stub silencioso).
	`./MessagingService.spec.luau` testa este `Behavior` de ponta a ponta usando o MESMO padrão já
	estabelecido em `../InstanceState.spec.luau`/`../init.spec.luau` para exercitar uma classe
	via `ClassBuilder.Build` + `Runtime.ClassRegistry.Register` construída à mão dentro do próprio
	spec (nunca em `generated/`) -- a `GeneratedClass` usada lá reflete o dump REAL desta classe
	(`Schema = {}`, `MethodNames = { "PublishAsync", "SubscribeAsync" }`, `IsService = true`,
	`IsAbstract = true`), não uma classe fictícia inventada.

	Depende de: `../../runtime` (tipos), `../Types` (`Behavior`), `../Context` (Scheduler do
	processo; `NotifyMessagePublished`, NOVO em task-services-032), `../AsyncCall` (ponto único de
	yield), `../datastore/Value` (estimativa de tamanho + deep copy, reaproveitados). Estado:
	`subscriptionsByTopic`, module-local -- `MessagingService`
	é Service singleton (só entra em `InstanceState` quem precisa de estado POR INSTÂNCIA, que não
	é o caso aqui -- mesma disciplina de `DataStoreService.luau`/`GlobalDataStore.luau`).
]]

local Runtime = require("../../runtime")
local Types = require("../Types")
local Context = require("../Context")
local AsyncCall = require("../AsyncCall")
local Value = require("../datastore/Value")

-- Doc oficial (pesquisa, seção C.4): "Topics are developer-defined strings (1-80 characters)".
local MIN_TOPIC_LENGTH = 1
local MAX_TOPIC_LENGTH = 80

-- Doc oficial (pesquisa, seção C.4): tamanho máximo de mensagem, 1 kB. Interpretado como 1024
-- bytes (binário) -- mesma convenção já adotada em `../datastore/Value.luau` para o limite de
-- valor de DataStore ("4 MB" da doc virou 4194304 = 4 MiB) -- NÃO CONFIRMADO se o Roblox usa
-- decimal (1000) ou binário (1024) para "1 kB" especificamente nesta classe; adotado o mesmo
-- critério já em uso no território para consistência interna, documentado aqui como suposição.
local MAX_MESSAGE_BYTES = 1024

-- Formato confirmado na doc oficial (pesquisa, seção C.1): "Data" (o payload) e "Sent" (Unix time
-- em segundos).
type MessagePayload = { Data: unknown, Sent: number }
type MessageCallback = (message: MessagePayload) -> ()

-- `Active` -- ver `Disconnect`, abaixo: desativa a assinatura na hora do cancelamento, ANTES de
-- (tentar) removê-la da lista, para que um despacho já em andamento (snapshot tirado antes do
-- Disconnect) nunca chame um callback cancelado -- mesmo padrão de `Listener.Connected` em
-- `src/runtime/Signal.luau`.
type Subscription = {
	Callback: MessageCallback,
	Active: boolean,
}

-- Estado module-local do singleton -- ver cabeçalho, "Depende de". `MessagingService` não tem
-- múltiplas instâncias que façam sentido distinguir (é um Service, sempre 1 por processo), então
-- não há "por instância" a isolar aqui -- ao contrário de `InstanceState`, que existe para o caso
-- oposto (DataStore/Pages/Tween, ver `../InstanceState.luau`).
local subscriptionsByTopic: { [string]: { Subscription } } = {}

-- Nível 2: culpa quem chamou esta função diretamente (`Methods.PublishAsync`/`Methods.
-- SubscribeAsync`, abaixo) -- mesma convenção já em uso por `Value.AssertNameLength`/
-- `checkIntegerForOrderedDataStore` em `./GlobalDataStore.luau` para validação chamada direto de
-- dentro de um método behavior, sem camada intermediária.
local function assertValidTopic(topic: string): ()
	local length = string.len(topic)
	if length < MIN_TOPIC_LENGTH or length > MAX_TOPIC_LENGTH then
		error(
			`Topics are developer-defined strings between {MIN_TOPIC_LENGTH} and {MAX_TOPIC_LENGTH} characters long (got {length} characters)`,
			2
		)
	end
end

-- Nível 2, mesma convenção acima. Mede via `Value.EstimateByteSize` (reaproveitado, ver
-- cabeçalho) -- a MENSAGEM de erro é própria de `MessagingService`, nunca a de `DataStore`.
-- DEVOLVE o tamanho medido (task-services-032): `PublishAsync`, abaixo, reaproveita este MESMO
-- número para `Context.NotifyMessagePublished` -- nunca recalcula `Value.EstimateByteSize` uma
-- segunda vez só para a auditoria.
local function assertValidMessage(message: unknown): number
	local size = Value.EstimateByteSize(message)
	if size > MAX_MESSAGE_BYTES then
		error(`MessagingService message exceeds the maximum size of {MAX_MESSAGE_BYTES} bytes (got {size} bytes, serialized)`, 2)
	end
	return size
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/
-- `DataStoreService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	--[[
		Doc oficial: `MessagingService:PublishAsync(topic, message): ()` -- Yields. Ver cabeçalho
		do módulo para: eco local (nunca filtrado), entrega assíncrona via `scheduler:Spawn`, deep
		copy por assinante, ordem de entrega, isolamento de erro (de graça, via Scheduler).
	]]
	PublishAsync = function(_self: Runtime.Instance, topic: string, message: unknown): ()
		assertValidTopic(topic)
		local byteSize = assertValidMessage(message)

		-- Canal de auditoria (task-services-032, ver cabeçalho "AUDITORIA -- OnMessagePublished")
		-- -- DEPOIS que a validação de tópico/tamanho já passou, ANTES do yield -- MESMA posição
		-- relativa que `auditOutgoingRequest` ocupa em `HttpService.luau`. NUNCA o corpo da
		-- mensagem, só `topic`/`byteSize`. No-op se `Types.BootstrapOptions.OnMessagePublished`
		-- não foi passado a `Services.Bootstrap`.
		Context.NotifyMessagePublished(topic, byteSize)

		AsyncCall.Yield("MessagingService:PublishAsync")

		local subscribers = subscriptionsByTopic[topic]
		if subscribers == nil then
			return
		end

		-- Snapshot ANTES de despachar: um `SubscribeAsync`/`Disconnect` chamado durante este
		-- despacho (por um dos próprios callbacks, por exemplo) não afeta esta rodada -- mesma
		-- garantia que `Runtime.Signal.Fire` já dá para `Connect`/`Disconnect` no meio de um
		-- disparo.
		local snapshot: { Subscription } = {}
		for _, subscription in subscribers do
			table.insert(snapshot, subscription)
		end

		-- Capturado UMA VEZ por publicação -- todos os assinantes desta rodada recebem o MESMO
		-- `Sent` (representa quando o backend simulado aceitou a publicação, não quando cada
		-- assinante individualmente processou -- fiel à semântica real, onde `Sent` vem do
		-- backend, não do relógio de cada servidor receptor).
		local sentAt = os.time()
		local scheduler = Context.GetScheduler()

		for _, subscription in snapshot do
			scheduler:Spawn(function()
				-- Rechecado no momento do despacho (não só no snapshot): cobre o caso de um
				-- callback anterior, no MESMO despacho, ter cancelado este -- ver cabeçalho do
				-- tipo `Subscription`, campo `Active`.
				if subscription.Active then
					subscription.Callback({ Data = Value.DeepCopy(message), Sent = sentAt })
				end
			end)
		end
	end,

	--[[
		Doc oficial: `MessagingService:SubscribeAsync(topic, callback): RBXScriptConnection` --
		Yields ("it yields until the subscription is properly registered"). A assinatura só entra
		em `subscriptionsByTopic` DEPOIS do yield -- fiel à ideia de "registrado só depois do
		round-trip simulado".
	]]
	SubscribeAsync = function(_self: Runtime.Instance, topic: string, callback: unknown): Runtime.Connection
		assertValidTopic(topic)

		-- Mesma disciplina de `UpdateAsync` em `./GlobalDataStore.luau`: `callback` chega como
		-- `unknown` (o script pode passar qualquer coisa) -- validado explicitamente em vez de
		-- deixar a chamada de `subscription.Callback(...)` falhar depois, sem contexto, dentro de
		-- uma coroutine despachada por `PublishAsync`.
		if type(callback) ~= "function" then
			error(`invalid argument #2 to 'SubscribeAsync' (function expected, got {type(callback)})`, 2)
		end
		local messageCallback = callback :: MessageCallback

		AsyncCall.Yield("MessagingService:SubscribeAsync")

		local subscription: Subscription = { Callback = messageCallback, Active = true }
		local list = subscriptionsByTopic[topic]
		if list == nil then
			list = {}
			subscriptionsByTopic[topic] = list
		end
		table.insert(list, subscription)

		-- Forward-declare -- `Disconnect` referencia `connection` (para o guard de idempotência)
		-- antes de a tabela terminar de ser construída. Mesmo padrão de `local listener; listener
		-- = {...}` em `src/runtime/Signal.luau`.
		local connection: Runtime.Connection
		connection = {
			Connected = true,
			Disconnect = function(_self: Runtime.Connection): ()
				if not connection.Connected then
					return
				end
				connection.Connected = false
				-- Desativa ANTES de tentar remover -- ver cabeçalho do tipo `Subscription`: cobre
				-- o caso de `Disconnect` ser chamado durante um despacho já em andamento (a lista
				-- `list` é a MESMA referência que o snapshot de `PublishAsync` foi tirado de, mas
				-- o snapshot já capturou o item -- só `Active` decide se ele ainda dispara).
				subscription.Active = false
				local index = table.find(list, subscription)
				if index then
					table.remove(list, index)
				end
			end,
		}
		return connection
	end,
}

local MessagingServiceBehavior: Types.Behavior = {
	Methods = Methods,
}

return MessagingServiceBehavior
