--!strict

--[[
	Teste dedicado de `./RunService.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	`../Integration.spec.luau`, seção "1b", já cobre a superfície GENÉRICA de Service
	(ClassName/Parent/singleton) para `RunService` via `game:GetService` -- este arquivo cobre a
	superfície ESPECÍFICA desta classe: a ligação real com o Scheduler, o RejectingSignal sobre
	RenderStepped, PreRender intacto, e os 4 métodos implementados.

	`require("../../runtime")`/`require("../")`: caminho normal de fora de `src/runtime`/
	`src/services` (nenhum dos dois é literalmente chamado `init.luau` deste ponto de vista --
	`require("../")` carrega `src/services/init.luau` "estilo diretório", mesmo padrão de
	`../Integration.spec.luau`/`StarterPlayer.spec.luau`).

	Roda com `lune run src/services/behavior/RunService.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Idempotente (guarda local em ../init.luau) -- seguro mesmo que outro spec do processo já tenha
-- chamado.
Services.Register()

-- Monta um `RunService` de verdade, ligado a UM scheduler conhecido, via o caminho de produção
-- inteiro: `Services.Bootstrap` (Register + Context.Set) seguido de `game:GetService`.
local function makeRunService(): (Runtime.Instance, Runtime.Scheduler)
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local runService = game:GetService("RunService")
	return runService, scheduler
end

test("RunService.Heartbeat é rawequal a scheduler.Heartbeat -- MESMA instância, nunca um proxy", function()
	local runService, scheduler = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	assert(
		rawequal(runServiceDynamic.Heartbeat, scheduler.Heartbeat),
		"RunService.Heartbeat deveria ser EXATAMENTE o mesmo objeto que scheduler.Heartbeat -- instalado por SetPropertyRaw no Initialize, sem proxy nem reemissão"
	)
end)

test("RunService.Stepped é rawequal a scheduler.Stepped -- mesma disciplina de Heartbeat", function()
	local runService, scheduler = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	assert(
		rawequal(runServiceDynamic.Stepped, scheduler.Stepped),
		"RunService.Stepped deveria ser EXATAMENTE o mesmo objeto que scheduler.Stepped"
	)
end)

test("conectar em RunService.Heartbeat e chamar scheduler:StepOnce dispara o callback com deltaTime", function()
	local runService, scheduler = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic
	local heartbeat = runServiceDynamic.Heartbeat :: Runtime.Signal<number>

	local fired = false
	local receivedDt: number? = nil
	local connection = heartbeat:Connect(function(dt: number)
		fired = true
		receivedDt = dt
	end)

	scheduler:StepOnce(1 / 30)

	assert(fired, "o callback conectado em RunService.Heartbeat deveria disparar quando scheduler:StepOnce roda -- é o MESMO Signal")
	assert(receivedDt == 1 / 30, `deltaTime recebido deveria ser exatamente o passado a StepOnce (1/30), recebeu {tostring(receivedDt)}`)

	connection:Disconnect()
end)

test(
	"conectar em RunService.RenderStepped ERRA com a mensagem exata (RejectingSignal) -- família Roblox, sem prefixo [LuauBench]",
	function()
		local runService = makeRunService()
		local runServiceDynamic = (runService :: unknown) :: Dynamic
		local renderStepped = runServiceDynamic.RenderStepped :: Runtime.Signal<...unknown>

		local ok, err = pcall(function()
			renderStepped:Connect(function() end)
		end)

		assert(not ok, "conectar em RunService.RenderStepped deveria erro -- LuauBench simula a produção (RCC), não o bug do Studio (ver arquiteto-services-2026-09-05.md, parte B)")
		local message = tostring(err)
		assert(
			string.find(message, "RenderStepped event can only be used from local scripts", 1, true) ~= nil,
			`mensagem deveria bater com a aproximação de boa-fé (família Roblox), recebeu: {message}`
		)
		assert(
			string.find(message, "[LuauBench]", 1, true) == nil,
			"NÃO deveria ter o prefixo [LuauBench] -- este erro TEM contraparte real (regra de idioma dos erros)"
		)
	end
)

test("LER RunService.RenderStepped NÃO erra -- devolve o objeto (só Connect/Once/Wait erram)", function()
	local runService = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	local ok, value = pcall(function()
		return runServiceDynamic.RenderStepped
	end)

	assert(ok, "ler RunService.RenderStepped não deveria erro -- o motor real só checa na CONEXÃO, não na leitura")
	assert(value ~= nil, "RunService.RenderStepped deveria devolver o objeto RejectingSignal, nunca nil")
end)

test("RunService.PreRender continua conectável e NUNCA dispara sob N StepOnce -- NÃO recebe o mesmo tratamento de RenderStepped", function()
	local runService, scheduler = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic
	local preRender = runServiceDynamic.PreRender :: Runtime.Signal<number>

	local ok = pcall(function()
		preRender:Connect(function() end)
	end)
	assert(ok, "conectar em RunService.PreRender NÃO deveria erro -- decisão fechada (arquiteto-services-2026-09-05.md, parte B.5): PreRender fica no balde client-only não varrido, RenderStepped é a única exceção do tamanho da evidência que a sustenta")

	local fired = false
	preRender:Connect(function()
		fired = true
	end)

	for _ = 1, 10 do
		scheduler:StepOnce(1 / 60)
	end

	assert(not fired, "RunService.PreRender NUNCA deveria disparar -- sem render, mesma divergência já declarada para RenderStepped antes desta revisão")
end)

test("IsServer() -> true, IsClient() -> false, IsStudio() -> false, IsRunning() -> true", function()
	local runService = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	local isServer = runServiceDynamic.IsServer :: (self: Dynamic) -> boolean
	local isClient = runServiceDynamic.IsClient :: (self: Dynamic) -> boolean
	local isStudio = runServiceDynamic.IsStudio :: (self: Dynamic) -> boolean
	local isRunning = runServiceDynamic.IsRunning :: (self: Dynamic) -> boolean

	assert(isServer(runServiceDynamic) == true, "IsServer() deveria ser true -- LuauBench se apresenta como servidor")
	assert(isClient(runServiceDynamic) == false, "IsClient() deveria ser false")
	assert(isStudio(runServiceDynamic) == false, "IsStudio() deveria ser false -- LuauBench simula produção (RCC), não o Studio")
	assert(isRunning(runServiceDynamic) == true, "IsRunning() deveria ser true")
end)

test("escrever sobre RunService.Heartbeat erra 'is an event of RunService and cannot be reassigned'", function()
	local runService = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	local ok, err = pcall(function()
		runServiceDynamic.Heartbeat = 1
	end)

	assert(not ok, "escrever sobre um Event do schema deveria erro -- Heartbeat não é reatribuível")
	assert(
		string.find(tostring(err), "is an event of RunService and cannot be reassigned", 1, true) ~= nil,
		`mensagem deveria bater com o formato confirmado (Kind == "Event"), recebeu: {err}`
	)
end)

test("RunService:BindToRenderStep() (sem implementação de behavior) erra com a mensagem [LuauBench]", function()
	local runService = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	local ok, err = pcall(function()
		-- Chamada como ESTATEMENT, sem `return`: o cast fixa o retorno em `()` (zero valores) --
		-- `return` de uma chamada assim comprometeria o retorno da própria closure com `()`,
		-- e `pcall<A..., R...>` com `R... = ()` devolveria só `(boolean)`, quebrando a
		-- atribuição a `ok, err` (mesmo raciocínio já documentado em Signal.luau para
		-- `pcall(listener.callback, ...)`).
		local bindToRenderStep = runServiceDynamic.BindToRenderStep :: (self: Dynamic, name: string, priority: number, callback: unknown) -> ()
		bindToRenderStep(runServiceDynamic, "Test", 1, function() end)
	end)

	assert(not ok, "BindToRenderStep não tem Methods em behavior/RunService.luau -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(err), "[LuauBench] RunService:BindToRenderStep() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {err}`
	)
end)

test(
	"RunService:Pause() erra como MEMBRO INEXISTENTE, não [LuauBench] -- excluído de MethodNames pelo filtro de Security (RobloxScriptSecurity/PluginSecurity), não 'não implementado ainda'",
	function()
		local runService = makeRunService()
		local runServiceDynamic = (runService :: unknown) :: Dynamic

		local ok, err = pcall(function()
			-- Chamada como ESTATEMENT, sem `return` -- mesmo raciocínio do comentário em
			-- BindToRenderStep acima (`() -> ()` comprometeria o retorno de pcall).
			local pause = runServiceDynamic.Pause :: (self: Dynamic) -> ()
			pause(runServiceDynamic)
		end)

		assert(not ok, "Pause não está em MethodNames (gerador já filtrou por Security) -- deveria erro como membro inexistente")
		local message = tostring(err)
		assert(
			string.find(message, "Pause is not a valid member of RunService", 1, true) ~= nil,
			`deveria errar como membro inexistente, recebeu: {message}`
		)
		assert(
			string.find(message, "[LuauBench]", 1, true) == nil,
			"NÃO deveria ter o prefixo [LuauBench] -- Pause nunca chega a existir para um script comum, nem no Roblox real"
		)
	end
)

test("RunService.FrameNumber e RunService.Misprediction NÃO estão no schema -- ler erra como membro inexistente", function()
	local runService = makeRunService()
	local runServiceDynamic = (runService :: unknown) :: Dynamic

	local okFrame, errFrame = pcall(function()
		return runServiceDynamic.FrameNumber
	end)
	assert(not okFrame, "FrameNumber foi excluído do schema pelo eixo Capabilities (InternalTest) -- ler deveria erro")
	assert(
		string.find(tostring(errFrame), "FrameNumber is not a valid member of RunService", 1, true) ~= nil,
		`mensagem deveria bater com o formato de membro inexistente, recebeu: {errFrame}`
	)

	local okMisprediction, errMisprediction = pcall(function()
		return runServiceDynamic.Misprediction
	end)
	assert(not okMisprediction, "Misprediction foi excluído do schema pelo eixo Capabilities (PluginOrOpenCloud) -- ler deveria erro")
	assert(
		string.find(tostring(errMisprediction), "Misprediction is not a valid member of RunService", 1, true) ~= nil,
		`mensagem deveria bater com o formato de membro inexistente, recebeu: {errMisprediction}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
