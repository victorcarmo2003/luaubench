--!strict

--[[
	O Scheduler/DataModel do processo corrente do LuauBench -- existe porque o `Initialize` de
	uma classe de service (contrato de Runtime.ClassDescriptor) só recebe `instance`, e algumas
	classes precisam alcançar o Scheduler/DataModel de fora disso (caso central citado no desenho:
	`behavior/RunService.luau`, task futura, conecta `RunService.Heartbeat` ao Signal REAL do
	Scheduler corrente -- só descobre QUAL Scheduler é esse por aqui). Ver
	.claude/agents-memory/arquiteto-services-2026-09-05.md, seção "Módulos" ->
	"src/services/Context.luau".

	Mesma invariante já documentada em Runtime.ClassRegistry (ver src/runtime/ClassRegistry.luau,
	cabeçalho: "ClassRegistry assume um processo por execução do LuauBench -- não há desregistro
	nem reset"): um processo por execução, sem reset. `cli` chama `Services.Bootstrap` (que chama
	`Context.Set` por baixo -- ver init.luau) uma única vez, no bootstrap, ANTES de qualquer
	`GetService`. `Services.Register`/`Services.Bootstrap` são idempotentes por guarda local (ver
	init.luau) -- uma segunda chamada a `Context.Set` (efeito de uma segunda chamada a
	`Bootstrap`) simplesmente sobrescreve a mesma referência: não existe cenário legítimo de troca
	de Scheduler/DataModel no meio de um processo, então não há necessidade de rejeitar a segunda
	chamada -- só de nunca ficar sem NENHUMA (daí os dois `Get*` abaixo errarem antes do primeiro
	`Set`).

	REJEITADO EXPLICITAMENTE pelo arquiteto: popular o contexto por efeito colateral de `require`.
	Seria frágil (o resultado dependeria da ORDEM dos `require`, nunca de uma chamada explícita) e
	intestável (não dá pra simular "Bootstrap ainda não foi chamado" sem reiniciar o processo
	inteiro) -- o desenho do `runtime` já pagou o preço de contrato implícito nesse mesmo formato
	mais de uma vez (histórico de revisão de Signal/ThreadBroker). `Context.Set` é SEMPRE uma
	chamada explícita, feita só por `Services.Bootstrap`.

	Erros abaixo são de ENGENHARIA INTERNA (uso errado da API por `services`/`cli` -- `cli`
	esqueceu de chamar `Bootstrap` antes de tentar alcançar um Service), nunca observáveis por um
	script do usuário comum -- por isso em português, pela regra de idioma dos erros (Decisão 5 do
	desenho de `services`).

	Depende de: Types.luau (BootstrapOptions), ../runtime (só tipos: Scheduler/DataModel). Usado
	por: init.luau (Services.Bootstrap) e, futuramente, behavior/*.luau (task-services-00x).
]]

local Types = require("./Types")
local Runtime = require("../runtime")

type BootstrapOptions = Types.BootstrapOptions

local Context = {}

-- Estado privado do módulo -- um processo por execução do LuauBench, sem função de reset (mesma
-- invariante de ClassRegistry, ver cabeçalho acima).
local current: BootstrapOptions? = nil

-- Chamado só por `Services.Bootstrap` (init.luau) -- nunca direto por `cli`/`behavior`.
-- Sobrescreve silenciosamente numa segunda chamada (ver cabeçalho acima); não existe
-- `Context.Reset`/`Context.Unset`.
function Context.Set(options: BootstrapOptions): ()
	current = options
end

function Context.IsSet(): boolean
	return current ~= nil
end

function Context.GetScheduler(): Runtime.Scheduler
	if current == nil then
		error(
			"Context.GetScheduler: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	return current.scheduler
end

function Context.GetDataModel(): Runtime.DataModel
	if current == nil then
		error(
			"Context.GetDataModel: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	return current.dataModel
end

-- task-services-026: lida por `behavior/HttpService.luau` (`Initialize`, para decidir se
-- `HttpEnabled` nasce `true`). `BootstrapOptions.AllowHttp` é `boolean?` -- `nil`/omitido vira
-- `false` aqui, nunca um terceiro estado "não configurado" que `HttpService` precisaria tratar
-- separadamente. Mesma guarda de engenharia interna (português, nunca observável por um script
-- de usuário comum) que `GetScheduler`/`GetDataModel` já usam: erra se `Bootstrap` ainda não
-- rodou, nunca adivinha um default silencioso para quem esqueceu de inicializar o Context.
function Context.IsHttpAllowed(): boolean
	if current == nil then
		error(
			"Context.IsHttpAllowed: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	return current.AllowHttp == true
end

-- task-services-026: lida por `behavior/HttpService.luau` (a checagem de destino loopback/
-- link-local/privado em `GetAsync`/`PostAsync`/`RequestAsync`). Mesma normalização e mesma
-- guarda de `IsHttpAllowed`, acima -- `AllowHttpLocal` é consultado independentemente de
-- `AllowHttp` aqui; é a ORDEM em que `behavior/HttpService.luau` os usa (`assertHttpEnabled`
-- sempre primeiro) que garante que a permissão local nunca abre rede sem a permissão geral, não
-- nenhuma lógica de OR entre as duas neste módulo.
function Context.IsHttpLocalAllowed(): boolean
	if current == nil then
		error(
			"Context.IsHttpLocalAllowed: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	return current.AllowHttpLocal == true
end

-- Correção coordenada com `task-cli-026` (par de `task-services-026`): chamada por
-- `behavior/HttpService.luau` UMA VEZ por requisição de saída de `GetAsync`/`PostAsync`/
-- `RequestAsync`, ANTES de tocar `net.request` de verdade -- é o canal de auditoria que permite
-- `cli` (não `services`) decidir SE e COMO imprimir a linha (`--verbose`), sem que este
-- território precise conhecer `Messages.luau`/stdio (regra 03: `services` só usa a API pública
-- de `runtime`, nunca formata output do CLI). `BootstrapOptions.OnHttpRequest` é `nil` por
-- padrão (sem `cli` passar nada) -- NO-OP nesse caso, nunca erro: ao contrário de
-- `IsHttpAllowed`/`IsHttpLocalAllowed` (que SEMPRE têm um valor, `boolean`, depois de
-- `Bootstrap`), a ausência do callback é um estado normal e frequente (qualquer chamador de
-- `Services.Bootstrap` que não passe `OnHttpRequest`), não um erro de engenharia interna.
function Context.NotifyHttpRequest(method: string, host: string): ()
	if current == nil then
		error(
			"Context.NotifyHttpRequest: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	local callback = current.OnHttpRequest
	if callback ~= nil then
		callback(method, host)
	end
end

-- task-services-032 (decisão do arquiteto, `.claude/agents-memory/arquiteto-persistencia-cloud-
-- 2026-09-06.md`, seção 7): canal de auditoria de `MessagingService:PublishAsync`, MESMO padrão
-- de `Context.NotifyHttpRequest`, acima. Chamado por `behavior/MessagingService.luau` UMA VEZ por
-- publicação bem-sucedida, DEPOIS que a validação de tópico/tamanho já passou -- nunca para uma
-- publicação que erra na validação (nada foi publicado de verdade). `BootstrapOptions.
-- OnMessagePublished` é `nil` por padrão -- NO-OP nesse caso, nunca erro (mesma disciplina de
-- `NotifyHttpRequest`: ausência do callback é estado normal, não erro de engenharia interna).
-- `topic`/`byteSize` são os dois ÚNICOS parâmetros -- NUNCA o corpo da mensagem (regra 00/07).
function Context.NotifyMessagePublished(topic: string, byteSize: number): ()
	if current == nil then
		error(
			"Context.NotifyMessagePublished: Services.Bootstrap ainda não foi chamado neste processo -- cli precisa chamar Services.Bootstrap({ scheduler = ..., dataModel = ... }) antes de qualquer acesso a Service",
			2
		)
	end
	local callback = current.OnMessagePublished
	if callback ~= nil then
		callback(topic, byteSize)
	end
end

-- task-services-031 (arquiteto-persistencia-cloud-2026-09-06.md, seção 10): canal ÚNICO de leitura
-- de `BootstrapOptions.CloudPersistence` -- nenhum `behavior/*.luau` lê `BootstrapOptions` direto,
-- mesma disciplina de `IsHttpAllowed`/`NotifyHttpRequest` acima. Consumido por `../init.luau`
-- (`Services.Bootstrap`, para carregar o estado salvo antes de qualquer script rodar, e
-- `Services.FlushCloudState`, para decidir se há uma porta pra gravar).
--
-- DIFERENTE de `GetScheduler`/`GetDataModel`/`IsHttpAllowed`/`NotifyHttpRequest` (que ERRAM se
-- `Bootstrap` ainda não rodou neste processo -- chamar qualquer um deles antes disso é erro de
-- ENGENHARIA de `cli`, nunca esperado): esta função NUNCA erra, nem mesmo se `current == nil`
-- (Bootstrap nunca chamado). Decisão deliberada do arquiteto (seção 10 do desenho): a AUSÊNCIA do
-- port (seja porque `cli` nunca passou `CloudPersistence`, seja porque `Bootstrap` ainda nem
-- rodou) é um estado NORMAL e FREQUENTE -- `Services.FlushCloudState` é chamado por `cli` em
-- pontos de flush (fronteira de tique do scheduler, flush final) que precisam ser seguros de
-- chamar mesmo num cenário de erro anterior no pipeline, sem nunca derrubar a execução por causa
-- disso (regra 01: "erro não tratado ... nunca derruba o processo" -- aqui, mais forte ainda: nem
-- CHEGA a ser um erro).
function Context.GetCloudPersistence(): Types.CloudPersistence?
	if current == nil then
		return nil
	end
	return current.CloudPersistence
end

return Context
