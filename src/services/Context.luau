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

return Context
