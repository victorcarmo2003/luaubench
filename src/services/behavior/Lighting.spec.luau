--!strict

--[[
	Teste dedicado de `./Lighting.luau` (regra 01: teste na mesma tarefa da lógica que cobre;
	regra 03: "toda classe de Service simulada tem teste cobrindo instanciação, ao menos uma
	propriedade lida/escrita, e ao menos um evento disparando na ordem certa"). `../Integration.
	spec.luau` já cobre a superfície GENÉRICA de Service (ClassName/Parent/singleton) para
	`Lighting` via `game:GetService` -- este arquivo cobre a superfície ESPECÍFICA desta classe:
	a sincronia ClockTime/TimeOfDay/minutos, as exclusões de `LightingChanged` e os três métodos
	implementados.

	Roda com `lune run src/services/behavior/Lighting.spec.luau`.
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

-- Monta um `Lighting` de verdade pelo caminho de produção inteiro: `Services.Bootstrap`
-- (Register + Context.Set) seguido de `game:GetService` -- mesmo padrão de `RunService.spec.luau`.
local function makeLighting(): Runtime.Instance
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	local lighting = game:GetService("Lighting")
	assert(lighting ~= nil, "game:GetService(\"Lighting\") não deveria devolver nil -- Lighting é Service coberto")
	return lighting :: Runtime.Instance
end

test("defaults do schema já nascem coerentes: ClockTime=14, TimeOfDay=\"14:00:00\", GetMinutesAfterMidnight()=840", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	assert(dynamic.ClockTime == 14, `ClockTime default deveria ser 14, recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "14:00:00", `TimeOfDay default deveria ser "14:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)

	local getMinutes = dynamic.GetMinutesAfterMidnight :: (self: Dynamic) -> number
	assert(getMinutes(dynamic) == 840, `GetMinutesAfterMidnight() default deveria ser 840 (14*60), recebeu {tostring(getMinutes(dynamic))}`)
end)

test("escrever ClockTime atualiza TimeOfDay e GetMinutesAfterMidnight (direção 1 de 3)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.ClockTime = 6

	assert(dynamic.TimeOfDay == "06:00:00", `TimeOfDay deveria ter sido sincronizado para "06:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
	local getMinutes = dynamic.GetMinutesAfterMidnight :: (self: Dynamic) -> number
	assert(getMinutes(dynamic) == 360, `GetMinutesAfterMidnight() deveria ser 360 (6*60), recebeu {tostring(getMinutes(dynamic))}`)
end)

test("escrever TimeOfDay (\"HH:MM:SS\") atualiza ClockTime e GetMinutesAfterMidnight (direção 2 de 3)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.TimeOfDay = "18:30:00"

	assert(dynamic.ClockTime == 18.5, `ClockTime deveria ter sido sincronizado para 18.5, recebeu {tostring(dynamic.ClockTime)}`)
	local getMinutes = dynamic.GetMinutesAfterMidnight :: (self: Dynamic) -> number
	assert(getMinutes(dynamic) == 1110, `GetMinutesAfterMidnight() deveria ser 1110 (18*60+30), recebeu {tostring(getMinutes(dynamic))}`)
end)

test("TimeOfDay aceita escrita curta \"H:MM\" e volta zero-padded na leitura", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.TimeOfDay = "9:05"

	assert(dynamic.TimeOfDay == "09:05:00", `TimeOfDay deveria ter sido canonicalizado para "09:05:00", recebeu {tostring(dynamic.TimeOfDay)}`)
	assert(dynamic.ClockTime == 9 + 5 / 60, `ClockTime deveria refletir 9h05, recebeu {tostring(dynamic.ClockTime)}`)
end)

test("SetMinutesAfterMidnight atualiza ClockTime e TimeOfDay (direção 3 de 3)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local setMinutes = dynamic.SetMinutesAfterMidnight :: (self: Dynamic, minutes: number) -> ()
	setMinutes(dynamic, 90)

	assert(dynamic.ClockTime == 1.5, `ClockTime deveria ser 1.5 (90 min = 1h30), recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "01:30:00", `TimeOfDay deveria ser "01:30:00", recebeu {tostring(dynamic.TimeOfDay)}`)
end)

test("SetMinutesAfterMidnight faz WRAP para valores > 24h (confirmado pela doc oficial)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local setMinutes = dynamic.SetMinutesAfterMidnight :: (self: Dynamic, minutes: number) -> ()
	-- 25h = 1500 min -> wrap para 1h (60 min).
	setMinutes(dynamic, 1500)

	assert(dynamic.ClockTime == 1, `ClockTime deveria ter dado wrap para 1 (25h -> 1h), recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "01:00:00", `TimeOfDay deveria ter dado wrap para "01:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
	local getMinutes = dynamic.GetMinutesAfterMidnight :: (self: Dynamic) -> number
	assert(getMinutes(dynamic) == 60, `GetMinutesAfterMidnight() deveria refletir o wrap (60), recebeu {tostring(getMinutes(dynamic))}`)
end)

test("escrever ClockTime >= 24 faz RESET A 0 (revisado em task-services-024-fix, ver cabeçalho de Lighting.luau)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.ClockTime = 25

	assert(dynamic.ClockTime == 0, `ClockTime deveria ter dado RESET para 0 (não wrap para 1), recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "00:00:00", `TimeOfDay deveria ter dado RESET para "00:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
end)

test("escrever ClockTime negativo faz RESET A 0 (revisado em task-services-024-fix, ver cabeçalho de Lighting.luau)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.ClockTime = -5

	assert(dynamic.ClockTime == 0, `ClockTime deveria ter dado RESET para 0 (não wrap para 19), recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "00:00:00", `TimeOfDay deveria ter dado RESET para "00:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
end)

test("escrever TimeOfDay com componente de hora >= 24 faz RESET A 0 (mesma revisão, mesmo estado único)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	dynamic.TimeOfDay = "25:70:99"

	assert(dynamic.TimeOfDay == "00:00:00", `TimeOfDay deveria ter dado RESET para "00:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
	assert(dynamic.ClockTime == 0, `ClockTime deveria ter dado RESET para 0, recebeu {tostring(dynamic.ClockTime)}`)
end)

test("SetMinutesAfterMidnight continua fazendo WRAP mesmo depois da revisão (via oficialmente confirmada, sem mudança)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local setMinutes = dynamic.SetMinutesAfterMidnight :: (self: Dynamic, minutes: number) -> ()
	-- 25h = 1500 min -> continua indo para 1h (wrap), NÃO para 0 -- `SetMinutesAfterMidnight` não
	-- foi afetado pela revisão de task-services-024-fix (só ClockTime/TimeOfDay diretos mudaram).
	setMinutes(dynamic, 1500)

	assert(dynamic.ClockTime == 1, `ClockTime deveria continuar com WRAP para 1 (25h -> 1h), recebeu {tostring(dynamic.ClockTime)}`)
	assert(dynamic.TimeOfDay == "01:00:00", `TimeOfDay deveria continuar com WRAP para "01:00:00", recebeu {tostring(dynamic.TimeOfDay)}`)
end)

test("LightingChanged dispara para Ambient e Brightness", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic
	local lightingChanged = dynamic.LightingChanged :: Runtime.Signal<boolean>

	local ambientFired = false
	local ambientSkyChanged: boolean? = nil
	local connectionAmbient = lightingChanged:Connect(function(skyChanged: boolean)
		ambientFired = true
		ambientSkyChanged = skyChanged
	end)
	dynamic.Ambient = "qualquer valor"
	connectionAmbient:Disconnect()
	assert(ambientFired, "LightingChanged deveria disparar quando Ambient muda")
	assert(ambientSkyChanged == false, `skyChanged deveria ser false (sem Sky/Atmosphere simulado), recebeu {tostring(ambientSkyChanged)}`)

	local brightnessFired = false
	local connectionBrightness = lightingChanged:Connect(function(_skyChanged: boolean)
		brightnessFired = true
	end)
	dynamic.Brightness = 2
	connectionBrightness:Disconnect()
	assert(brightnessFired, "LightingChanged deveria disparar quando Brightness muda")
end)

test("LightingChanged NÃO dispara para GlobalShadows/FogColor/FogStart/FogEnd (exclusão documentada oficialmente)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic
	local lightingChanged = dynamic.LightingChanged :: Runtime.Signal<boolean>

	local fired = false
	local connection = lightingChanged:Connect(function(_skyChanged: boolean)
		fired = true
	end)

	dynamic.GlobalShadows = true
	assert(not fired, "LightingChanged NÃO deveria disparar para GlobalShadows")

	dynamic.FogColor = "qualquer valor"
	assert(not fired, "LightingChanged NÃO deveria disparar para FogColor")

	dynamic.FogStart = 10
	assert(not fired, "LightingChanged NÃO deveria disparar para FogStart")

	dynamic.FogEnd = 200
	assert(not fired, "LightingChanged NÃO deveria disparar para FogEnd")

	connection:Disconnect()
end)

test("LightingChanged dispara EXATAMENTE 2x para ClockTime não-canônico (task-services-024, ver cabeçalho de Lighting.luau)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic
	local lightingChanged = dynamic.LightingChanged :: Runtime.Signal<boolean>

	local fireCount = 0
	local connection = lightingChanged:Connect(function(_skyChanged: boolean)
		fireCount += 1
	end)

	dynamic.ClockTime = 6

	connection:Disconnect()
	-- Multiplicador EXATO confirmado rodando este teste (não é fidelidade contra o Roblox real, só
	-- contra a própria simulação -- ver cabeçalho de `Lighting.luau`): 1 fire do rewrite reentrante
	-- de `TimeOfDay` (síncrono, dentro de `applyCanonical`) + 1 fire do `Changed` original de
	-- `ClockTime`.
	assert(fireCount == 2, `LightingChanged deveria disparar exatamente 2x para ClockTime não-canônico, recebeu {fireCount}`)
end)

test("LightingChanged dispara EXATAMENTE 3x para TimeOfDay em forma curta não-canônica (task-services-024)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic
	local lightingChanged = dynamic.LightingChanged :: Runtime.Signal<boolean>

	local fireCount = 0
	local connection = lightingChanged:Connect(function(_skyChanged: boolean)
		fireCount += 1
	end)

	dynamic.TimeOfDay = "9:05"

	connection:Disconnect()
	-- Multiplicador EXATO confirmado rodando este teste -- ver cabeçalho de `Lighting.luau`: 1 fire
	-- do rewrite reentrante de `ClockTime` + 1 fire do rewrite reentrante de `TimeOfDay` (a forma
	-- RAW "9:05" difere da canônica "09:05:00", então a segunda `SetPropertyRaw` de
	-- `applyCanonical` também executa) + 1 fire do `Changed` original de `TimeOfDay`.
	assert(fireCount == 3, `LightingChanged deveria disparar exatamente 3x para TimeOfDay em forma curta não-canônica, recebeu {fireCount}`)
end)

test("LightingChanged dispara EXATAMENTE 2x para TimeOfDay já em forma canônica (task-services-024)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic
	local lightingChanged = dynamic.LightingChanged :: Runtime.Signal<boolean>

	local fireCount = 0
	local connection = lightingChanged:Connect(function(_skyChanged: boolean)
		fireCount += 1
	end)

	dynamic.TimeOfDay = "09:05:00"

	connection:Disconnect()
	-- Multiplicador EXATO confirmado rodando este teste -- ver cabeçalho de `Lighting.luau`: aqui só
	-- 2x (não 3x como na forma curta), porque `TimeOfDay` já chega RAW igual à forma canônica -- a
	-- segunda `SetPropertyRaw` de `applyCanonical` (a de `TimeOfDay`) nem executa, só a de
	-- `ClockTime` (rewrite reentrante) + o `Changed` original de `TimeOfDay`.
	assert(fireCount == 2, `LightingChanged deveria disparar exatamente 2x para TimeOfDay já canônico, recebeu {fireCount}`)
end)

test("GetMoonPhase() sempre devolve 0.75", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local getMoonPhase = dynamic.GetMoonPhase :: (self: Dynamic) -> number
	assert(getMoonPhase(dynamic) == 0.75, `GetMoonPhase() deveria ser sempre 0.75, recebeu {tostring(getMoonPhase(dynamic))}`)

	dynamic.ClockTime = 20
	assert(getMoonPhase(dynamic) == 0.75, "GetMoonPhase() deveria continuar 0.75 independente de ClockTime")
end)

test("GetSunDirection()/GetMoonDirection() erram com o stub [LuauBench] -- sem fórmula pública (pesquisa B3)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	-- Chamada como ESTATEMENT, sem `return` (mesmo raciocínio de `RunService.spec.luau`, teste de
	-- `BindToRenderStep`): o stub `[LuauBench]` do `ClassBuilder` sempre erra, nunca devolve valor
	-- -- tipar/chamar como `() -> ()` evita comprometer o retorno da própria closure passada a
	-- `pcall`, que quebraria a atribuição a `ok, err`.
	local okSun, errSun = pcall(function()
		local getSunDirection = dynamic.GetSunDirection :: (self: Dynamic) -> ()
		getSunDirection(dynamic)
	end)
	assert(not okSun, "GetSunDirection não tem Methods em behavior/Lighting.luau -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(errSun), "[LuauBench] Lighting:GetSunDirection() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {errSun}`
	)

	local okMoon, errMoon = pcall(function()
		local getMoonDirection = dynamic.GetMoonDirection :: (self: Dynamic) -> ()
		getMoonDirection(dynamic)
	end)
	assert(not okMoon, "GetMoonDirection não tem Methods em behavior/Lighting.luau -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(errMoon), "[LuauBench] Lighting:GetMoonDirection() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench] (regra 03), recebeu: {errMoon}`
	)
end)

test("getMinutesAfterMidnight/setMinutesAfterMidnight (aliases deprecated) erram com o stub [LuauBench] -- decisão deliberada (regra 03)", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local ok, err = pcall(function()
		local getMinutesLower = dynamic.getMinutesAfterMidnight :: (self: Dynamic) -> ()
		getMinutesLower(dynamic)
	end)
	assert(not ok, "getMinutesAfterMidnight (alias deprecated) não tem Methods -- deveria cair no stub do ClassBuilder")
	assert(
		string.find(tostring(err), "[LuauBench] Lighting:getMinutesAfterMidnight() exists in the Roblox API Dump", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench], recebeu: {err}`
	)
end)

test("escrever TimeOfDay com string malformada erra [LuauBench] em vez de travar em silêncio", function()
	local lighting = makeLighting()
	local dynamic = (lighting :: unknown) :: Dynamic

	local ok, err = pcall(function()
		dynamic.TimeOfDay = "não é uma hora"
	end)
	assert(not ok, "TimeOfDay malformado deveria erro, não ser aceito em silêncio")
	assert(
		string.find(tostring(err), "[LuauBench] Lighting.TimeOfDay:", 1, true) ~= nil,
		`mensagem deveria ter o prefixo [LuauBench], recebeu: {err}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
