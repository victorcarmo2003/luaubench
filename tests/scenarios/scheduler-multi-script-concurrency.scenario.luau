--!strict

-- Cenário: vários "scripts" hipotéticos rodando concorrentemente sob o mesmo Scheduler --
-- um script que faz polling por task.wait, um que reage a Heartbeat, um que espera outra
-- Instance aparecer (WaitForChild) pra reagir tipo um "PlayerAdded" genérico, e um script com
-- bug (erro não tratado) -- confirma que um script quebrado não derruba os outros nem o laço
-- principal, um dos invariantes centrais da regra 02.
-- Origem: sintético (composição de idiomas -- task.spawn/task.wait/RunService.Heartbeat --
-- que o recon confirmou onipresentes nos jogos reais do usuário: RunService é o 2º Service
-- mais referenciado, 196 ocorrências; task.spawn/task.wait aparecem em dezenas de arquivos,
-- ex: Jogo Five/src/server/Services/ReconectService.luau, AnimeFallen/.../WaveService.luau).
-- Superfície exercitada: Scheduler.new/Spawn/Delay/Defer/Wait/Cancel/StepOnce/IsAlive,
-- scheduler.Heartbeat/Stepped/ThreadError, Instance.NewBase + ChildAdded/WaitForChild
-- compondo com o Scheduler.
-- Status: passa hoje.

local process = require("@lune/process")
local Scheduler = require("../../src/runtime/Scheduler")
local Instance = require("../../src/runtime/Instance")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("script A (task.wait em loop) + script B (Heartbeat) avançam juntos em StepOnce determinístico", function()
	local scheduler = Scheduler.new()

	-- Script A: como um sistema de dano-ao-longo-do-tempo, "acorda" a cada 0.1s por 3 vezes.
	local ticksA = 0
	scheduler:Spawn(function()
		for _ = 1, 3 do
			scheduler:Wait(0.1)
			ticksA += 1
		end
	end)

	-- Script B: um script "de câmera"/HUD que só reage a Heartbeat, sem nunca terminar
	-- sozinho -- típico de um script de UI que fica vivo o jogo inteiro.
	local heartbeatCount = 0
	scheduler.Heartbeat:Connect(function(_dt: number)
		heartbeatCount += 1
	end)

	assert(scheduler:IsAlive(), "logo após Spawn, deveria haver thread viva (script A suspenso)")

	-- 5 tiques de 0.1s cada: script A deveria ter completado os 3 task.wait(0.1) dentro disso.
	for _ = 1, 5 do
		scheduler:StepOnce(0.1)
	end

	assert(ticksA == 3, `script A deveria ter acordado 3 vezes, acordou {ticksA}`)
	assert(heartbeatCount == 5, `Heartbeat deveria ter disparado uma vez por StepOnce (5), disparou {heartbeatCount}`)
	-- Script B nunca desconecta -- IsAlive() continua true só por causa da conexão em Heartbeat,
	-- mesmo com o script A já morto (mesma semântica de um script real que fica "ouvindo" pra
	-- sempre).
	assert(scheduler:IsAlive(), "IsAlive() deveria continuar true: Heartbeat ainda tem uma conexão viva (script B)")
end)

test("script C (WaitForChild) reage a uma Instance criada por outro script, via ChildAdded em cascata", function()
	local scheduler = Scheduler.new()
	local playersFolder = Instance.NewBase("Folder", "PlayersFolder")

	-- Script C: o padrão "PlayerAdded" -- espera qualquer filho aparecer sob playersFolder e
	-- reage. Como ainda não existe Players/PlayerAdded real (falta ClassRegistry/DataModel),
	-- isso é simulado com WaitForChild + um Folder qualquer representando o jogador entrando.
	local reactedTo: { string } = {}
	scheduler:Spawn(function()
		while true do
			local child = playersFolder:WaitForChild(`Player{#reactedTo + 1}`, 1)
			if child == nil then
				break
			end
			table.insert(reactedTo, child.Name)
		end
	end)

	-- Script D: entra 3 "jogadores" em sequência, um por tique, como se cada um fosse um
	-- game:GetService("Players").PlayerAdded disparando em momentos diferentes.
	scheduler:Spawn(function()
		for i = 1, 3 do
			scheduler:Wait(0.05)
			local player = Instance.NewBase("Folder", `Player{i}`)
			player.Parent = playersFolder
		end
	end)

	for _ = 1, 10 do
		scheduler:StepOnce(0.05)
	end

	assert(#reactedTo == 3, `script C deveria ter reagido a 3 entradas, reagiu a {#reactedTo}`)
	assert(reactedTo[1] == "Player1" and reactedTo[2] == "Player2" and reactedTo[3] == "Player3", "script C deveria ter reagido na ordem de entrada")
end)

test("erro não tratado em um script (task.spawn) vira ThreadError e NÃO impede os outros de continuar", function()
	local scheduler = Scheduler.new()

	-- ThreadError precisa estar conectado ANTES do Spawn do script com bug: Scheduler:Spawn
	-- roda de forma síncrona até o primeiro yield ou término (documentado em Scheduler.luau),
	-- então um script que erra sem nunca dar yield já dispara ThreadError dentro da própria
	-- chamada de Spawn -- conectar depois perderia esse disparo. Confirmado rodando: a
	-- primeira versão deste cenário conectava depois e via 0 erros capturados.
	local capturedErrors: { string } = {}
	scheduler.ThreadError:Connect(function(_thread: thread, message: string)
		table.insert(capturedErrors, message)
	end)

	local buggyRan = false
	scheduler:Spawn(function()
		buggyRan = true
		error("bug no script do usuário: índice nil")
	end)

	local healthyTicks = 0
	scheduler:Spawn(function()
		for _ = 1, 3 do
			scheduler:Wait(0.05)
			healthyTicks += 1
		end
	end)

	for _ = 1, 5 do
		scheduler:StepOnce(0.05)
	end

	assert(buggyRan, "o script com bug deveria ter rodado até o error()")
	assert(#capturedErrors == 1, `ThreadError deveria ter capturado exatamente 1 erro, capturou {#capturedErrors}`)
	assert(string.find(capturedErrors[1], "bug no script do usuário") ~= nil, "a mensagem de ThreadError deveria conter o erro original")
	assert(healthyTicks == 3, `o script saudável deveria ter completado normalmente apesar do bug no outro, completou {healthyTicks} tiques`)
end)

test("Cancel em uma thread Delay pendente impede que ela rode, sem afetar outras threads", function()
	local scheduler = Scheduler.new()

	local cancelledRan = false
	local handle = scheduler:Delay(0.2, function()
		cancelledRan = true
	end)

	local normalRan = false
	scheduler:Delay(0.1, function()
		normalRan = true
	end)

	scheduler:StepOnce(0.05)
	scheduler:Cancel(handle)

	for _ = 1, 5 do
		scheduler:StepOnce(0.1)
	end

	assert(not cancelledRan, "a thread cancelada não deveria ter rodado")
	assert(normalRan, "a thread não cancelada deveria ter rodado normalmente")
	assert(not scheduler:IsAlive(), "sem conexões pendentes e sem threads vivas, IsAlive() deveria ficar false")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
