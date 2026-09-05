--!strict

--[[
	Behavior de `RunService` -- task-services-004. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 5" e "Fidelidade vs.
	pragmatismo", e a seção "Revisão pós-integração 2026-09-05 -- Capabilities e RenderStepped",
	parte B, ANTES de mexer aqui -- o desenho abaixo segue essas seções ao pé da letra.

	RunService é a classe #2 mais usada no recon do `testador` (196 usos) e a ponte real com o
	Scheduler do runtime: `Heartbeat`/`Stepped` NÃO são um evento próprio de `services` que
	reemite o do Scheduler (o que criaria dois relógios e risco de dessincronia) -- são o MESMO
	objeto `Signal` que `Runtime.Scheduler.new()` já expõe, instalado por cima da entrada do
	schema. `RunService.Heartbeat` e `scheduler.Heartbeat` são, depois deste Initialize,
	literalmente a mesma referência (`rawequal` verdadeiro) -- não um proxy, não uma cópia.

	MECANISMO: `Runtime.ClassRegistry.new`/`NewEngineInstance` semeia um `Signal.new()` FRESCO por
	instância para cada entrada `Kind == "Event"` do schema achatado ANTES de chamar este
	`Initialize` (arquiteto-services-2026-09-05.md, "Decisão 6", item 1) -- é por isso que basta
	SOBRESCREVER a entrada aqui dentro, via `Runtime.Instance.SetPropertyRaw` (a via de
	engenharia que NUNCA consulta o schema, ver o mesmo desenho, "Decisão 6", item 2): o Signal
	seedado é descartado (nunca teve listener conectado a tempo -- Initialize roda antes de
	qualquer script do usuário alcançar a instância) e substituído pelo do Scheduler.
	`Context.GetScheduler()` é como este módulo alcança QUAL Scheduler é esse -- `Initialize`
	só recebe `instance` (contrato de `Runtime.ClassDescriptor`).

	RenderStepped: ver `../RejectingSignal.luau` para o mecanismo e a justificativa completa
	(mesma decisão do arquiteto, parte B). Resumo: conectar erra ("RenderStepped event can only
	be used from local scripts", família Roblox sem prefixo -- tem contraparte real, ainda que a
	string exata seja aproximação de boa-fé de bug trackers 2014-2024, não verificada ao vivo em
	2026); LER a propriedade NÃO erra (devolve o objeto -- o motor real só checa na conexão, não
	na leitura). `PreRender` (o nome moderno de RenderStepped, também presente no dump) NÃO
	recebe este tratamento -- fica com o Signal seedado pelo schema, existe e nunca dispara,
	porque não há evidência de que erre no servidor e errar sem confirmação falha por COMISSÃO
	(quebraria código válido) -- o pior dos dois lados errados possíveis (arquiteto-services,
	parte B.4).

	IsServer()->true / IsClient()->false / IsStudio()->false / IsRunning()->true: o LuauBench se
	apresenta como SERVIDOR RODANDO -- escolha deliberada, não uma consulta a contexto nenhum
	(não existe RunContext simulado nesta leva). Motivo: o uso medido pelo `testador` é dominado
	por lógica de servidor (ProfileStore, DataStore) -- um `--client` é tarefa futura própria,
	nunca implícito aqui.

	Os demais 7 métodos do dump que sobraram em `MethodNames` depois do filtro de Security/
	Capabilities (BindToRenderStep, BindToSimulation, GetPredictionStatus, IsResimulating,
	IsRunMode, SetPredictionMode, UnbindFromRenderStep -- ver
	generated/classes/RunService.luau) ficam SEM `Methods` aqui de propósito: `ClassBuilder.Build`
	já completa qualquer `MethodNames` sem implementação com o stub `[LuauBench] ... not
	simulated by LuauBench yet` (regra 03) -- nenhum deles tem comportamento real definido por
	este desenho. `Pause`/`Run`/`Stop`/`Reset`/`IsEdit` e os demais RobloxScriptSecurity NÃO
	aparecem nem em `MethodNames` (o gerador já os excluiu -- ver "Revisão pós-integração
	2026-09-05", parte C, do desenho): chamá-los erra "não é membro válido", não `[LuauBench]` --
	é a mensagem correta, porque um script comum no Roblox real também não os vê.

	`RunService.FrameNumber`/`RunService.Misprediction` NÃO estão no schema gerado (excluídos
	pelo eixo Capabilities -- `InternalTest`/`PluginOrOpenCloud` respectivamente, ver o mesmo
	desenho, parte A.4) -- lê-los erra como membro inexistente. Esperado, não regressão.
]]

local Runtime = require("../../runtime")
local Types = require("../Types")
local Context = require("../Context")
local RejectingSignal = require("../RejectingSignal")

-- Aproximação de boa-fé (regra de idioma dos erros: tem contraparte real -> família Roblox, em
-- inglês, SEM prefixo "[LuauBench]"): texto coletado de bug trackers de 2014-2024
-- (Anaminus/roblox-bug-tracker #636 e #365, ROBLOX/Studio-Tools #14, citados no relatório de
-- pesquisa que motivou esta decisão), NÃO verificado ao vivo em 2026 -- mesmo protocolo já usado
-- para a mensagem de `Instance.new` de classe inexistente.
local RENDER_STEPPED_MESSAGE = "RenderStepped event can only be used from local scripts"

-- Anotação explícita de `{ [string]: unknown }` necessária para o literal de tabela com campos
-- de função concreta ser aceito onde `Types.Behavior.Methods` espera um mapa indexado por
-- string, não um record "sealed" -- mesmo padrão já usado em `ClassBuilder.spec.luau`.
local Methods: { [string]: unknown } = {
	IsServer = function(_self: Runtime.Instance): boolean
		return true
	end,

	IsClient = function(_self: Runtime.Instance): boolean
		return false
	end,

	IsStudio = function(_self: Runtime.Instance): boolean
		return false
	end,

	IsRunning = function(_self: Runtime.Instance): boolean
		return true
	end,
}

local RunServiceBehavior: Types.Behavior = {
	Methods = Methods,

	Initialize = function(instance: Runtime.Instance): ()
		local scheduler = Context.GetScheduler()

		-- Ligação REAL, sem proxy: instala a MESMA referência que `scheduler.Heartbeat`/
		-- `scheduler.Stepped` já são -- não um Signal novo que reemite o do Scheduler. É isso
		-- que garante `rawequal(runService.Heartbeat, scheduler.Heartbeat) == true` (acceptance
		-- desta tarefa) e evita qualquer dessincronia entre os dois relógios.
		Runtime.Instance.SetPropertyRaw(instance, "Heartbeat", scheduler.Heartbeat)
		Runtime.Instance.SetPropertyRaw(instance, "Stepped", scheduler.Stepped)

		-- Ver `../RejectingSignal.luau` para o mecanismo completo. Só RenderStepped recebe este
		-- tratamento -- `PreRender` fica com o Signal seedado pelo schema (existe, nunca
		-- dispara), ver cabeçalho deste arquivo.
		Runtime.Instance.SetPropertyRaw(instance, "RenderStepped", RejectingSignal.new(RENDER_STEPPED_MESSAGE))
	end,
}

return RunServiceBehavior
