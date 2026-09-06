--!strict

--[[
	Teste dedicado de `./SoundService.luau` (regra 01: teste na mesma tarefa da lógica que cobre;
	regra 03: "toda classe de Service simulada tem teste cobrindo instanciação, ao menos uma
	propriedade lida/escrita, e ao menos um evento disparando na ordem certa"). `SoundService` tem
	ZERO Event sobrevivente ao filtro do gerador (confirmado em `../generated/classes/SoundService.
	luau` -- 13 Property, 4 Function, 0 Event, ver `.claude/agents-memory/arquiteto-services-
	2026-09-05.md`, "L2.5.3") -- a parte "evento disparando" da regra 03 não se aplica a esta
	classe, nada a cobrir aqui por construção, não por omissão.

	Cobre, nesta ordem:
	  1. instanciação via `game:GetService("SoundService")`.
	  2. as 13 Property lendo o Default exato do schema gerado (inclusive `RespectFilteringEnabled`
	     -- DISCREPÂNCIA dump x doc, ver `./SoundService.luau`/coverage.luau: o dump diz `false`, a
	     doc oficial diz `true`; o dump vence, regra 03).
	  3. as 12 Property WRITÁVEIS aceitando escrita (leitura de volta bate com o valor escrito).
	  4. a 13ª Property (`CharacterSoundsUseNewApi`) é ReadOnly de verdade -- escrever erra com a
	     string confirmada (`Write = "PluginSecurity"` no dump, só Studio/plugin escreve).
	  5. os 3 métodos SEM `Behavior` (`GetListener`/`SetListener`/`GetMixerTime`) erram com o stub
	     genérico `[LuauBench]` do `ClassBuilder`.
	  6. `PlayLocalSound` erra com a string EXATA confirmada por citação ao vivo (task-services-028),
	     SEM o prefixo `[LuauBench]` -- é um erro com contraparte real, não uma lacuna do LuauBench.

	Roda com `lune run src/services/behavior/SoundService.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local ValueTypes = require("../../valuetypes")
local Services = require("../")

type Dynamic = { [string]: unknown }

-- `ValueTypes.Enum` é tipado como `Enums` (a "vitrine" estática só declara `GetEnums`, ver
-- `src/valuetypes/types/Enum.luau`) -- não tem índice `[string]: Enum` no tipo, então
-- `ValueTypes.Enum.ReverbType` NÃO compila em modo estrito por acesso direto (mesmo motivo pelo
-- qual `Enum.spec.luau`, no próprio território `valuetypes`, usa um helper igual a este em vez de
-- acesso pontilhado). `enumItem` resolve `Enum.<Nome>.<Item>` como dois lookups por STRING sobre
-- `unknown`, devolvendo `unknown` -- comparável direto com `==`/`rawequal` contra o valor lido de
-- uma Property (também `unknown`, via `Dynamic`), sem precisar do tipo nominal `EnumItem`.
type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function member(container: unknown, name: string): unknown
	return (container :: StringIndexableProbe)[name]
end
local function enumItem(enumName: string, itemName: string): unknown
	return member(member(ValueTypes.Enum, enumName), itemName)
end

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

-- Monta um `SoundService` de verdade pelo caminho de produção inteiro: `Services.Bootstrap`
-- (Register + Context.Set) seguido de `game:GetService` -- mesmo padrão de `Lighting.spec.luau`/
-- `PhysicsService.spec.luau`. `SoundService` é `Service`+`NotCreatable` (IsAbstract == true) no
-- dump -- só alcançável por `GetService`, nunca por `Services.new` direto.
local function makeSoundService(): Dynamic
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local soundService = game:GetService("SoundService")
	assert(soundService ~= nil, 'game:GetService("SoundService") não deveria devolver nil -- SoundService é Service coberto')
	return (soundService :: unknown) :: Dynamic
end

--------------------------------------------------------------------------------------------------
-- 1. Instanciação
--------------------------------------------------------------------------------------------------

test('game:GetService("SoundService") devolve uma instância -- singleton do processo (Service, NotCreatable)', function()
	local soundService = makeSoundService()
	local instance = (soundService :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "SoundService", `ClassName deveria ser SoundService, recebeu {instance.ClassName}`)

	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local first = game:GetService("SoundService")
	local second = game:GetService("SoundService")
	assert(rawequal(first, second), "a segunda chamada a GetService('SoundService') deveria devolver o MESMO objeto (singleton)")
end)

--------------------------------------------------------------------------------------------------
-- 2. As 13 Property leem o Default EXATO do schema gerado (../generated/classes/SoundService.luau).
--------------------------------------------------------------------------------------------------

test("as 8 Property Primitive leem o Default exato do dump", function()
	local soundService = makeSoundService()

	assert(soundService.AcousticSimulationEnabled == false, `AcousticSimulationEnabled default deveria ser false, recebeu {tostring(soundService.AcousticSimulationEnabled)}`)
	assert(soundService.DiffractionEnabled == true, `DiffractionEnabled default deveria ser true, recebeu {tostring(soundService.DiffractionEnabled)}`)
	assert(soundService.DistanceFactor == 3.32999992, `DistanceFactor default deveria ser 3.32999992, recebeu {tostring(soundService.DistanceFactor)}`)
	assert(soundService.DopplerScale == 1, `DopplerScale default deveria ser 1, recebeu {tostring(soundService.DopplerScale)}`)
	assert(soundService.OcclusionEnabled == true, `OcclusionEnabled default deveria ser true, recebeu {tostring(soundService.OcclusionEnabled)}`)
	assert(soundService.ReverbEnabled == true, `ReverbEnabled default deveria ser true, recebeu {tostring(soundService.ReverbEnabled)}`)
	assert(soundService.RolloffScale == 1, `RolloffScale default deveria ser 1, recebeu {tostring(soundService.RolloffScale)}`)
end)

test('RespectFilteringEnabled lê false -- DISCREPÂNCIA dump ("false") x doc oficial ("true"), o dump vence (regra 03)', function()
	local soundService = makeSoundService()
	assert(
		soundService.RespectFilteringEnabled == false,
		`RespectFilteringEnabled default deveria ser false (Default do dump, não o "true" da doc oficial), recebeu {tostring(soundService.RespectFilteringEnabled)}`
	)
end)

test("as 3 Property Enum leem o EnumItem correto (AmbientReverb=NoReverb, ListenerType=Camera, CharacterSoundsUseNewApi=Default)", function()
	local soundService = makeSoundService()

	assert(
		rawequal(soundService.AmbientReverb, enumItem("ReverbType", "NoReverb")),
		`AmbientReverb default deveria ser Enum.ReverbType.NoReverb, recebeu {tostring(soundService.AmbientReverb)}`
	)

	assert(
		rawequal(soundService.ListenerType, enumItem("ListenerType", "Camera")),
		`ListenerType default deveria ser Enum.ListenerType.Camera, recebeu {tostring(soundService.ListenerType)}`
	)

	assert(
		rawequal(soundService.CharacterSoundsUseNewApi, enumItem("RolloutState", "Default")),
		`CharacterSoundsUseNewApi default deveria ser Enum.RolloutState.Default, recebeu {tostring(soundService.CharacterSoundsUseNewApi)}`
	)
end)

test("ListenerCFrame lê a identidade (CFrame.new(0, 0, 0)) -- Default do dump 'posição + matriz identidade'", function()
	local soundService = makeSoundService()
	-- `luau-lsp analyze` (confirmado nesta tarefa) REJEITA `unknown == CFrame` mesmo `CFrame`
	-- declarando `__eq` na vitrine -- o checker exige que os DOIS lados já sejam o tipo nominal
	-- antes de resolver o operador. Cast explícito ÚNICO de `unknown` (o valor de uma Property via
	-- `Dynamic`) para `ValueTypes.CFrame` -- depois disso `==` compila e compara por VALOR (12
	-- componentes, exato).
	local listenerCFrame = soundService.ListenerCFrame :: ValueTypes.CFrame
	assert(
		listenerCFrame == ValueTypes.CFrame.new(0, 0, 0),
		`ListenerCFrame default deveria ser CFrame.new(0, 0, 0), recebeu {tostring(listenerCFrame)}`
	)
end)

test("ListenerObject lê nil -- ValueType Class, sentinela não representável (Decisão 3)", function()
	local soundService = makeSoundService()
	assert(soundService.ListenerObject == nil, `ListenerObject default deveria ser nil, recebeu {tostring(soundService.ListenerObject)}`)
end)

--------------------------------------------------------------------------------------------------
-- 3. As 12 Property WRITÁVEIS (todas menos CharacterSoundsUseNewApi, ver seção 4) aceitam escrita.
--------------------------------------------------------------------------------------------------

test("as 6 Property boolean aceitam escrita (leitura de volta bate com o valor escrito)", function()
	local soundService = makeSoundService()

	soundService.AcousticSimulationEnabled = true
	assert(soundService.AcousticSimulationEnabled == true, "AcousticSimulationEnabled deveria aceitar escrita")

	soundService.DiffractionEnabled = false
	assert(soundService.DiffractionEnabled == false, "DiffractionEnabled deveria aceitar escrita")

	soundService.OcclusionEnabled = false
	assert(soundService.OcclusionEnabled == false, "OcclusionEnabled deveria aceitar escrita")

	soundService.RespectFilteringEnabled = true
	assert(soundService.RespectFilteringEnabled == true, "RespectFilteringEnabled deveria aceitar escrita (não é ReadOnly no dump)")

	soundService.ReverbEnabled = false
	assert(soundService.ReverbEnabled == false, "ReverbEnabled deveria aceitar escrita")
end)

test("as 3 Property numéricas (float) aceitam escrita", function()
	local soundService = makeSoundService()

	soundService.DistanceFactor = 5
	assert(soundService.DistanceFactor == 5, "DistanceFactor deveria aceitar escrita")

	soundService.DopplerScale = 2
	assert(soundService.DopplerScale == 2, "DopplerScale deveria aceitar escrita")

	soundService.RolloffScale = 10
	assert(soundService.RolloffScale == 10, "RolloffScale deveria aceitar escrita")
end)

test("as 2 Property Enum WRITÁVEIS (AmbientReverb/ListenerType) aceitam escrita", function()
	local soundService = makeSoundService()

	local bathroom = enumItem("ReverbType", "Bathroom")
	soundService.AmbientReverb = bathroom
	assert(
		rawequal(soundService.AmbientReverb, bathroom),
		`AmbientReverb deveria aceitar escrita, recebeu {tostring(soundService.AmbientReverb)}`
	)

	local cframeListener = enumItem("ListenerType", "CFrame")
	soundService.ListenerType = cframeListener
	assert(
		rawequal(soundService.ListenerType, cframeListener),
		`ListenerType deveria aceitar escrita, recebeu {tostring(soundService.ListenerType)}`
	)
end)

test("ListenerCFrame (DataType CFrame) aceita escrita", function()
	local soundService = makeSoundService()
	soundService.ListenerCFrame = ValueTypes.CFrame.new(1, 2, 3)
	-- Mesmo cast explícito de `unknown` -> `ValueTypes.CFrame` do teste de leitura acima --
	-- necessário pro `==` compilar (ver comentário lá).
	local listenerCFrame = soundService.ListenerCFrame :: ValueTypes.CFrame
	assert(
		listenerCFrame == ValueTypes.CFrame.new(1, 2, 3),
		`ListenerCFrame deveria aceitar escrita, recebeu {tostring(listenerCFrame)}`
	)
end)

test("ListenerObject (Class -- Instance qualquer) aceita escrita", function()
	local soundService = makeSoundService()
	local folder = Services.new("Folder", "Cam")
	soundService.ListenerObject = folder
	assert(rawequal(soundService.ListenerObject, folder), "ListenerObject deveria aceitar escrita de uma Instance qualquer")
end)

--------------------------------------------------------------------------------------------------
-- 4. CharacterSoundsUseNewApi é ReadOnly de verdade (Write = "PluginSecurity" no dump -- só
--    Studio/plugin escreve, script comum só lê) -- escrever erra com a string CONFIRMADA
--    (task-runtime-018), mesma família já usada para ClassName/etc.
--------------------------------------------------------------------------------------------------

test("escrever CharacterSoundsUseNewApi erra -- ReadOnly (Write=PluginSecurity no dump)", function()
	local soundService = makeSoundService()
	local ok, err = pcall(function()
		soundService.CharacterSoundsUseNewApi = enumItem("RolloutState", "Enabled")
	end)
	assert(not ok, "escrever CharacterSoundsUseNewApi deveria erro -- ReadOnly no schema gerado")
	assert(
		string.find(tostring(err), "Unable to assign property CharacterSoundsUseNewApi. Property is read only", 1, true) ~= nil,
		`mensagem deveria bater com a string confirmada (task-runtime-018), recebeu: {err}`
	)
end)

--------------------------------------------------------------------------------------------------
-- 5. Os 3 métodos SEM Behavior (GetListener/SetListener/GetMixerTime) erram com o stub genérico
--    [LuauBench] do ClassBuilder -- decisão original de L2.5.3, inalterada por esta tarefa.
--------------------------------------------------------------------------------------------------

local unimplementedMethodNames: { string } = { "GetListener", "SetListener", "GetMixerTime" }

for _, methodName in unimplementedMethodNames do
	test(`SoundService:{methodName}() ERRA com o stub [LuauBench] do ClassBuilder -- não implementado nesta tarefa`, function()
		local soundService = makeSoundService()
		local method = soundService[methodName] :: (...unknown) -> ...unknown

		local ok, err = pcall(function()
			return method(soundService, "qualquer", "qualquer")
		end)
		assert(not ok, `SoundService:{methodName}() deveria erro -- sem Behavior nesta tarefa`)
		local message = tostring(err)
		assert(
			string.find(message, `[LuauBench] SoundService:{methodName}() exists in the Roblox API Dump`, 1, true) ~= nil,
			`mensagem deveria trazer o prefixo [LuauBench] (regra 03), recebeu: {message}`
		)
		assert(
			string.find(message, "not simulated by LuauBench yet", 1, true) ~= nil,
			`mensagem deveria trazer "not simulated by LuauBench yet", recebeu: {message}`
		)
	end)
end

--------------------------------------------------------------------------------------------------
-- 6. PlayLocalSound erra com a string EXATA confirmada (task-services-028) -- SEM o prefixo
--    [LuauBench]: tem contraparte real no Roblox (client-only), não é lacuna do LuauBench.
--------------------------------------------------------------------------------------------------

test("SoundService:PlayLocalSound(sound) erra com a string EXATA confirmada, sem prefixo [LuauBench]", function()
	local soundService = makeSoundService()
	local playLocalSound = soundService.PlayLocalSound :: (self: Dynamic, sound: unknown) -> ()

	local ok, err = pcall(function()
		playLocalSound(soundService, nil)
	end)
	assert(not ok, "PlayLocalSound deveria erro -- LuauBench é servidor fixo, nunca há contexto de cliente")
	local message = tostring(err)
	assert(
		string.find(message, "SoundService:PlayLocalSound only works on a client.", 1, true) ~= nil,
		`mensagem deveria bater com a string EXATA confirmada por citação ao vivo (task-services-028), recebeu: {message}`
	)
	assert(
		string.find(message, "[LuauBench]", 1, true) == nil,
		"NÃO deveria ter o prefixo [LuauBench] -- este erro tem contraparte real confirmada no Roblox, não é lacuna do LuauBench"
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
