--!strict

-- Cenário: o padrão mais comum do ecossistema Roblox -- vários "scripts" concorrentes usando
-- `game:GetService("RunService").Heartbeat:Connect(function(dt) ... end)` DE VERDADE, via
-- bootstrap real de `services` (Runtime.DataModel.new() -> Services.Bootstrap({scheduler,
-- dataModel}) -> dataModel:GetService("RunService")) -- em vez de conectar direto no
-- `Scheduler` cru do `runtime`, como a 1ª rodada deste testador fazia (aquele cenário,
-- tests/scenarios/scheduler-multi-script-concurrency.scenario.luau, continua válido como está
-- e cobre o `Scheduler` isolado; este cenário cobre o caminho de ponta a ponta que só existe
-- agora que RunService/Players foram implementados e aprovados, task-services-004). Também
-- exercita o segundo padrão mais comum catalogado no recon: um Folder real aninhado sob
-- `game:GetService("ReplicatedStorage")` (`rs.Modules.Combat`), resolvido por WaitForChild em
-- cascata entre dois scripts concorrentes.
-- Origem: sintético (composição dos mesmos idiomas já catalogados na 1ª rodada -- RunService é
-- o 2º Service mais referenciado no recon de C:\Users\hakor\Documents\Roblox-Games, 196
-- ocorrências; `rs.Modules.Combat` é o padrão de módulo compartilhado citado explicitamente pelo
-- arquiteto de `services` como exemplo motivador de resolução de filho por nome --
-- src/services/Integration.spec.luau, cabeçalho, "Onde a acceptance do board pede
-- rs.Modules.Combat...").
-- Superfície exercitada: Runtime.DataModel.new, Runtime.Scheduler.new, Services.Register,
-- Services.Bootstrap, dataModel:GetService("RunService"|"ReplicatedStorage"),
-- RunService.Heartbeat:Connect (obtido via GetService, MESMA referência que scheduler.Heartbeat),
-- scheduler:Spawn/Wait/StepOnce/IsAlive/ThreadError, Services.new("Folder", ...) + .Parent,
-- Instance:WaitForChild sem timeout (via ChildAdded/ThreadBroker) e resolução de filho por nome
-- (rs.Modules.Combat).
-- Status: passa hoje.

local process = require("@lune/process")
local Runtime = require("../../src/runtime")
local Services = require("../../src/services")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Services.Register()/Bootstrap são idempotentes (guarda local em src/services/init.luau) --
-- seguro chamar de novo mesmo que outro spec/cenário do mesmo processo já tenha chamado.
Services.Register()

test(
	"script A (HUD via game:GetService('RunService').Heartbeat real) + script B (task.wait via Scheduler cru) avançam juntos sob o mesmo bootstrap",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local runService = game:GetService("RunService")

		-- Confirma a decisão de behavior/RunService.luau (comentário lá: "RunService.Heartbeat e
		-- scheduler.Heartbeat são, depois deste Initialize, literalmente a mesma referência"):
		-- não é um proxy, é o MESMO Signal -- é isso que garante zero dessincronia entre "quem
		-- conectou via GetService" (o caminho real de um script de jogo) e "quem conectou via
		-- Scheduler cru" (o caminho que a 1ª rodada deste testador exercitava).
		local runServiceDynamic = (runService :: unknown) :: Dynamic
		local heartbeatSignal = (runServiceDynamic.Heartbeat :: unknown) :: Runtime.Signal<number>
		assert(
			rawequal(heartbeatSignal, scheduler.Heartbeat),
			"game:GetService('RunService').Heartbeat deveria ser rawequal a scheduler.Heartbeat"
		)

		-- Script A: um script "de HUD/câmera" típico -- só reage a Heartbeat, nunca termina
		-- sozinho, obtido 100% pelo caminho real de um script de jogo (game:GetService).
		local heartbeatCount = 0
		heartbeatSignal:Connect(function(_dt: number)
			heartbeatCount += 1
		end)

		-- Script B: um sistema de dano-ao-longo-do-tempo concorrente, via scheduler:Wait puro --
		-- prova que RunService (obtido por `services`) e Scheduler (cru, `runtime`) continuam
		-- interoperando no mesmo processo, exatamente como um script real que mistura os dois
		-- idiomas (game:GetService de um lado, task.wait/task.spawn do outro).
		local ticksB = 0
		scheduler:Spawn(function()
			for _ = 1, 3 do
				scheduler:Wait(0.1)
				ticksB += 1
			end
		end)

		assert(scheduler:IsAlive(), "logo após conectar Heartbeat + Spawn, deveria haver trabalho pendente")

		for _ = 1, 5 do
			scheduler:StepOnce(0.1)
		end

		assert(
			heartbeatCount == 5,
			`Heartbeat obtido via GetService deveria ter disparado uma vez por StepOnce (5), disparou {heartbeatCount}`
		)
		assert(ticksB == 3, `script B deveria ter acordado 3 vezes via scheduler:Wait, acordou {ticksB}`)
		-- Script A nunca desconecta -- IsAlive() continua true só pela conexão em Heartbeat, mesmo
		-- com script B já morto (mesma asserção da 1ª rodada, agora atravessando o caminho real de
		-- `services`).
		assert(
			scheduler:IsAlive(),
			"IsAlive() deveria continuar true: RunService.Heartbeat (via GetService) ainda tem uma conexão viva (script A)"
		)
	end
)

test(
	"erro não tratado num listener de RunService.Heartbeat (via GetService) não derruba o listener vizinho nem um script concorrente via scheduler:Wait",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local runService = game:GetService("RunService")
		local runServiceDynamic = (runService :: unknown) :: Dynamic
		local heartbeatSignal = (runServiceDynamic.Heartbeat :: unknown) :: Runtime.Signal<number>

		-- ThreadError precisa estar conectado ANTES do primeiro StepOnce que dispara Heartbeat --
		-- mesma disciplina já confirmada pela 1ª rodada (Signal.Fire isola cada listener por
		-- pcall individual, mas quem acumula/relança o erro do listener sem dono é o Fire da
		-- própria chamada, capturado por Scheduler.fireProtected -- ver src/runtime/Signal.luau,
		-- comentário de `Fire`, e src/runtime/Scheduler.luau, `fireProtected`).
		local capturedErrors: { string } = {}
		scheduler.ThreadError:Connect(function(_thread: thread, message: string)
			table.insert(capturedErrors, message)
		end)

		-- Script com bug: como um sistema mal escrito que indexa algo nil dentro do Heartbeat.
		heartbeatSignal:Connect(function(_dt: number)
			error("bug no script do usuário: índice nil dentro de Heartbeat")
		end)

		-- Script saudável NO MESMO Heartbeat: prova que Signal.Fire isola listener por listener
		-- (pcall individual, ver Signal.luau) -- o vizinho quebrado não impede este de rodar.
		local healthyHeartbeats = 0
		heartbeatSignal:Connect(function(_dt: number)
			healthyHeartbeats += 1
		end)

		-- Script concorrente via idioma diferente (scheduler:Wait) -- prova que o laço principal
		-- (tick) continua de pé mesmo com o erro acima sendo relançado a cada Heartbeat.
		local waitTicks = 0
		scheduler:Spawn(function()
			for _ = 1, 3 do
				scheduler:Wait(0.1)
				waitTicks += 1
			end
		end)

		for _ = 1, 5 do
			scheduler:StepOnce(0.1)
		end

		assert(
			#capturedErrors == 5,
			`cada um dos 5 StepOnce deveria ter relançado 1 ThreadError (o listener com bug erra a cada Heartbeat), capturou {#capturedErrors}`
		)
		assert(
			string.find(capturedErrors[1], "bug no script do usuário") ~= nil,
			"a mensagem de ThreadError deveria conter o erro original do listener"
		)
		assert(
			healthyHeartbeats == 5,
			`o listener saudável no MESMO Heartbeat deveria continuar contando apesar do vizinho quebrado, contou {healthyHeartbeats}`
		)
		assert(
			waitTicks == 3,
			`o script concorrente via scheduler:Wait deveria ter completado normalmente apesar do bug no Heartbeat, completou {waitTicks}`
		)
	end
)

test(
	"padrão rs.Modules.Combat: script que monta a hierarquia sob game:GetService('ReplicatedStorage') após delay + script consumidor com WaitForChild em cascata (sem timeout)",
	function()
		local scheduler = Runtime.Scheduler.new()
		local game = Runtime.DataModel.new()
		Services.Bootstrap({ scheduler = scheduler, dataModel = game })

		local rs = game:GetService("ReplicatedStorage")

		-- Script "carregador de módulos": monta ReplicatedStorage.Modules.Combat só depois de um
		-- tempo (ex: um script de bootstrap que gera/organiza conteúdo compartilhado) -- padrão
		-- real: outro script depende de WaitForChild pra não correr na frente dele.
		scheduler:Spawn(function()
			scheduler:Wait(0.2)
			local modules = Services.new("Folder", "Modules")
			modules.Parent = rs

			scheduler:Wait(0.1)
			local combat = Services.new("Folder", "Combat")
			combat.Parent = modules
		end)

		-- Script consumidor: o padrão típico de um script de servidor que espera o módulo
		-- aparecer antes de seguir -- WaitForChild SEM timeout (espera de verdade via
		-- ChildAdded/ThreadBroker, nunca poll bloqueante nem retorno de nil precoce).
		local resolvedName: string? = nil
		local resolvedViaDotAccess = false
		scheduler:Spawn(function()
			local modules = rs:WaitForChild("Modules")
			if modules == nil then
				return
			end
			local combat = modules:WaitForChild("Combat")
			if combat == nil then
				return
			end
			resolvedName = combat.Name

			-- Confirma que, depois de resolvido via WaitForChild, o MESMO Folder também resolve
			-- por acesso de ponto encadeado (`rs.Modules.Combat`), como um script real
			-- normalmente escreveria depois que a hierarquia já existe (mesmo mecanismo já
			-- coberto em src/services/Integration.spec.luau, seção 2, agora atravessando
			-- GetService de verdade em vez de dois Folders soltos).
			local rsDynamic = (rs :: unknown) :: Dynamic
			local modulesDynamic = (rsDynamic.Modules :: unknown) :: Dynamic
			resolvedViaDotAccess = modulesDynamic.Combat == combat
		end)

		for _ = 1, 5 do
			scheduler:StepOnce(0.1)
		end

		assert(
			resolvedName == "Combat",
			`script consumidor deveria ter resolvido Combat via WaitForChild em cascata, resolveu {resolvedName}`
		)
		assert(
			resolvedViaDotAccess,
			"depois de resolvido, rs.Modules.Combat (acesso de ponto encadeado) deveria apontar pro MESMO Folder que o WaitForChild resolveu"
		)
	end
)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
