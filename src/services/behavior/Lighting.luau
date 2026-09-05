--!strict

--[[
	Behavior de `Lighting` -- task-services-024. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, seção "L2.5 -- Grupo 4", subseção
	"L2.5.2 -- `Lighting`: um núcleo de estado acoplado, o resto é dado inerte", e
	.claude/agents-memory/pesquisa-lighting-sound-physics-2026-09-05.md, seção B ("B1"/"B2"/"B3"),
	ANTES de mexer aqui -- o desenho abaixo segue as duas ao pé da letra.

	`Lighting` já está coberta desde a leva 1 (20 propriedades no schema gerado, sem `Behavior`,
	ver `../generated/classes/Lighting.luau`). O que faltava era o ÚNICO acoplamento real da
	classe: `ClockTime`, `TimeOfDay` e `Get`/`SetMinutesAfterMidnight` são TRÊS VISTAS DO MESMO
	ESTADO (citação direta do doc oficial de `ClockTime`, pesquisa B1: "Changing `TimeOfDay` or
	using `SetMinutesAfterMidnight()` will also change this property." -- e o inverso, citado no
	doc de `TimeOfDay`). Sem este módulo, `lighting.ClockTime = 6` deixava `TimeOfDay` congelado no
	default `"14:00:00"` -- divergência silenciosa, proibida pela regra 00.

	MECANISMO: `runtime` não expõe nenhum "hook" de escrita por propriedade a `services` (só
	`Instance.Changed`, disparado DEPOIS da escrita já ter acontecido -- ver
	`src/runtime/Instance.luau`, `InstanceMeta.__newindex`, passo 7). Este `Initialize` conecta em
	`instance.Changed` e, quando a propriedade que mudou é `ClockTime` OU `TimeOfDay`, recalcula a
	FONTE ÚNICA interna (segundos desde meia-noite, nunca guardada num campo à parte -- é sempre
	derivada de `ClockTime`, a própria propriedade do schema) e reescreve a VISTA que ficou
	desatualizada via `Runtime.Instance.SetPropertyRaw` (a via de engenharia que ignora
	`ClassSchema.ReadOnly`/dispara `Changed` incondicionalmente -- mesmo padrão de
	`behavior/RunService.luau`). Como `SetPropertyRaw` dispara `Changed` de novo, a própria escrita
	de sincronização reentra neste MESMO listener -- a flag `syncing` (upvalue por INSTÂNCIA, uma
	closure fresca por chamada de `Initialize`) impede recomputar a fonte de novo a partir da vista
	que ACABAMOS de escrever, sem impedir esse segundo `Changed` de contar para `LightingChanged`
	(ver mais abaixo) -- Lua é single-threaded, então a reentrância acontece inteiramente dentro da
	MESMA pilha de chamada, antes de `syncing` voltar a `false`.

	`SetMinutesAfterMidnight` (Método, não Propriedade) REUTILIZA esse mesmo mecanismo: grava só
	`ClockTime` via `SetPropertyRaw` e deixa o `Changed:Connect` acima propagar para `TimeOfDay`
	sozinho -- evita duplicar a lógica de conversão minutos->HH:MM:SS num segundo lugar.

	APROXIMAÇÃO DE BOA-FÉ, DECLARADA (regra 00) -- confirmada só PARCIALMENTE pela pesquisa (B1):
	- CONFIRMADO: `TimeOfDay` aceita escrita curta sem segundos (`"11:00"`, `"21:30"`).
	- CONFIRMADO: `SetMinutesAfterMidnight` faz WRAP para valores > 24h ("also allows values
	  greater than 24 hours that correspond to times in the next day").
	- NÃO CONFIRMADO: zero-padding na LEITURA de volta de uma hora de um dígito escrita por
	  extenso, e wrap/clamp/erro na escrita DIRETA de `ClockTime`/`TimeOfDay` fora de [0, 24h) (só
	  confirmado para `SetMinutesAfterMidnight`). Decisão do arquiteto (L2.5.2): adotar a MESMA
	  regra para as três vistas -- forma canônica `HH:MM:SS` com zero-padding na leitura, e WRAP
	  (nunca erro/clamp) para qualquer valor fora de alcance, em QUALQUER uma das três portas de
	  entrada. Também NÃO CONFIRMADO: sinal do wrap para minutos NEGATIVOS -- a decisão estende o
	  mesmo wrap por analogia (módulo com divisor positivo nunca devolve negativo em Luau/Lua,
	  então "meia-noite menos 10 minutos" vira "23:50:00" em vez de erro).
]]

local Runtime = require("../../runtime")
local Types = require("../Types")
local LightingGenerated = require("../generated/classes/Lighting")

local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR

-- Fonte única de "quais nomes SÃO propriedade de Lighting" -- derivada do schema gerado
-- (`../generated/classes/Lighting.luau`, a fonte única do Roblox API Dump para esta classe, regra
-- 03), nunca uma lista duplicada à mão que pudesse divergir do gerador. Usado só para decidir o
-- que dispara `LightingChanged` abaixo: o doc oficial (pesquisa B2) diz "Fired when a property of
-- Lighting changes" -- `Name`/`Parent`/`ClassName` (campos fixos de `Instance`, não do schema de
-- `Lighting`) ficam de fora POR CONSTRUÇÃO, sem precisar de uma exclusão explícita para eles.
local LIGHTING_PROPERTY_NAMES: { [string]: boolean } = {}
for memberName, descriptor in LightingGenerated.Schema do
	if descriptor.Kind == "Property" then
		LIGHTING_PROPERTY_NAMES[memberName] = true
	end
end

-- CONFIRMADO pela doc oficial (pesquisa B2, citação verbatim): "`GlobalShadows` does not fire the
-- event" e "`FogColor`, `FogStart`, `FogEnd` ... do not fire the event" -- recomendação oficial
-- para esses quatro é usar `Object.Changed`/`GetPropertyChangedSignal` em vez de `LightingChanged`.
-- Pegadinha real: uma simulação ingênua que disparasse `LightingChanged` para toda propriedade
-- divergiria do Roblox real nestes quatro nomes especificamente.
local EXCLUDED_FROM_LIGHTING_CHANGED: { [string]: boolean } = {
	GlobalShadows = true,
	FogColor = true,
	FogStart = true,
	FogEnd = true,
}

-- Arredonda para o inteiro mais próximo (Luau não tem `math.round`) -- usado para converter
-- horas/minutos fracionários em segundos inteiros antes do wrap, evitando que resíduo de ponto
-- flutuante (`14.5 * 3600 == 52199.999999999`) produza um segundo a menos no `HH:MM:SS` formatado.
local function roundToInteger(value: number): number
	return math.floor(value + 0.5)
end

-- WRAP (nunca erro/clamp) para a faixa [0, 86400) -- decisão do arquiteto (L2.5.2), estendendo por
-- analogia o wrap CONFIRMADO de `SetMinutesAfterMidnight` (pesquisa B1) às outras duas portas de
-- entrada. `%` em Luau/Lua com divisor POSITIVO sempre devolve um resultado não-negativo em
-- [0, divisor) mesmo para `totalSeconds` negativo (semântica de módulo por divisão inteira para
-- baixo, não a de `fmod` de C) -- por isso um único `%` já cobre "meia-noite menos 10 minutos" sem
-- precisar de um `+ SECONDS_PER_DAY` extra antes.
local function wrapSeconds(totalSeconds: number): number
	return totalSeconds % SECONDS_PER_DAY
end

-- `ClockTime` (horas fracionárias) -> segundos desde meia-noite, já com wrap.
local function secondsFromClockTime(hoursValue: number): number
	return wrapSeconds(roundToInteger(hoursValue * SECONDS_PER_HOUR))
end

-- Minutos (usado por `Get`/`SetMinutesAfterMidnight`) -> segundos desde meia-noite, já com wrap.
local function secondsFromMinutes(minutesValue: number): number
	return wrapSeconds(roundToInteger(minutesValue * SECONDS_PER_MINUTE))
end

-- Interpreta `TimeOfDay` em `"H:MM"`/`"HH:MM"`/`"HH:MM:SS"` (a escrita curta sem segundos É
-- confirmada pela pesquisa B1) e devolve o total de segundos desde meia-noite -- SEM wrap ainda
-- (o chamador decide quando aplicar `wrapSeconds`, mesmo padrão de `secondsFromClockTime`/
-- `secondsFromMinutes` acima). Componente fora de alcance (`"25:70:99"`) é aceito aqui -- vira um
-- total de segundos grande, que o `wrapSeconds` do chamador resolve (decisão do arquiteto,
-- L2.5.2: wrap, nunca erro, para valor numericamente fora de alcance).
--
-- Erro `[LuauBench]` (nunca a família Roblox sem prefixo) para uma string que não bate com nenhum
-- dos três formatos: a pesquisa (B1) achou um relato de comunidade de 2017 de um erro real
-- ("bad lexical cast...") para componente >= 65536, mas SEM confirmação de que ainda reproduz na
-- engine atual -- reproduzir aquela string exata aqui seria fingir uma fonte que não temos (regra
-- 00: não adivinhar comportamento de motor real sem confirmação).
local function parseTimeOfDay(value: string): number
	local hoursText, minutesText, secondsText = string.match(value, "^(%d+):(%d+):(%d+)$")
	if hoursText == nil then
		hoursText, minutesText = string.match(value, "^(%d+):(%d+)$")
		secondsText = "0"
	end
	if hoursText == nil or minutesText == nil or secondsText == nil then
		error(
			`[LuauBench] Lighting.TimeOfDay: "{value}" não bate com nenhum formato reconhecido ("H:MM", "HH:MM" ou "HH:MM:SS") -- string de erro real do Roblox para entrada malformada não confirmada nesta sessão, ver pesquisa-lighting-sound-physics-2026-09-05.md, seção B1`,
			0
		)
	end

	-- `%d+` garante dígitos puros -- `tonumber` nunca falha aqui, os `:: number` abaixo só
	-- estreitam o `number?` que a assinatura de `tonumber` devolve (mesmo padrão de cast direto já
	-- usado no território, ver `Runtime.Instance.GetPropertyRaw(...) :: T` em InstanceState.luau).
	local hours = tonumber(hoursText) :: number
	local minutes = tonumber(minutesText) :: number
	local seconds = tonumber(secondsText) :: number
	return hours * SECONDS_PER_HOUR + minutes * SECONDS_PER_MINUTE + seconds
end

-- Formata segundos desde meia-noite (JÁ com wrap aplicado pelo chamador) como `"HH:MM:SS"` com
-- zero-padding -- forma CANÔNICA adotada pela decisão do arquiteto (L2.5.2) para a leitura de
-- `TimeOfDay`, independente do formato usado na escrita (`"9:00"` escrito vira `"09:00:00"` lido
-- de volta -- não confirmado pela pesquisa que é exatamente isto que o Roblox real faz, mas é a
-- forma mais coerente com o `Default` do dump, que já nasce `"14:00:00"`, sempre com dois dígitos).
local function formatTimeOfDay(secondsSinceMidnight: number): string
	local wrapped = wrapSeconds(secondsSinceMidnight)
	local hours = math.floor(wrapped / SECONDS_PER_HOUR)
	local remainderAfterHours = wrapped - hours * SECONDS_PER_HOUR
	local minutes = math.floor(remainderAfterHours / SECONDS_PER_MINUTE)
	local seconds = roundToInteger(remainderAfterHours - minutes * SECONDS_PER_MINUTE)
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- Métodos implementados de verdade (os outros 5 sobreviventes de `MethodNames` --
-- `GetMoonDirection`/`GetSunDirection`/`getMinutesAfterMidnight`/`setMinutesAfterMidnight` --
-- ficam com o stub `[LuauBench] ... not simulated by LuauBench yet` do `ClassBuilder`, de
-- propósito: ver os comentários específicos abaixo e o cabeçalho deste arquivo).
--
-- Anotação explícita de `{ [string]: unknown }` necessária para o literal de tabela com campos de
-- função concreta ser aceito onde `Types.Behavior.Methods` espera um mapa indexado por string, não
-- um record "sealed" -- mesmo padrão já usado em `RunService.luau`/`Players.luau`.
local Methods: { [string]: unknown } = {
	-- "nearly identical to ClockTime multiplied by 60" (pesquisa B1) -- aqui é EXATAMENTE
	-- `ClockTime * 60` (via segundos, para o mesmo arredondamento que a leitura de `ClockTime`/
	-- `TimeOfDay` já usa), nunca um valor guardado à parte que pudesse dessincronizar.
	GetMinutesAfterMidnight = function(self: Runtime.Instance): number
		local clockTimeValue = Runtime.Instance.GetPropertyRaw(self, "ClockTime") :: number
		local seconds = secondsFromClockTime(clockTimeValue)
		return seconds / SECONDS_PER_MINUTE
	end,

	-- CONFIRMADO (pesquisa B1): aceita valores > 24h e faz WRAP -- nunca erro nem clamp. Só grava
	-- `ClockTime` via `SetPropertyRaw`: o `Changed:Connect` instalado em `Initialize` (abaixo)
	-- propaga para `TimeOfDay` sozinho -- ver o mecanismo completo no cabeçalho deste arquivo.
	SetMinutesAfterMidnight = function(self: Runtime.Instance, minutes: number): ()
		local seconds = secondsFromMinutes(minutes)
		Runtime.Instance.SetPropertyRaw(self, "ClockTime", seconds / SECONDS_PER_HOUR)
	end,

	-- CONFIRMADO pela doc oficial (pesquisa B3): "always returns 0.75" -- não há como mudar a fase
	-- da lua no motor real hoje. Fidelidade de graça, nenhuma aproximação necessária aqui.
	GetMoonPhase = function(_self: Runtime.Instance): number
		return 0.75
	end,

	-- `GetSunDirection`/`GetMoonDirection` DELIBERADAMENTE NÃO entram aqui: a doc oficial (pesquisa
	-- B3) descreve só o contrato (`Vector3` a partir da origem, aponta abaixo do horizonte após o
	-- "pôr") sem publicar NENHUMA fórmula envolvendo `GeographicLatitude`/`ClockTime`. Mesmo depois
	-- de `Vector3` existir (leva de Value Types), os dois PERMANECEM com o stub `[LuauBench]` do
	-- `ClassBuilder` -- inventar uma fórmula aproximada mentiria sobre a direção real (regra 00);
	-- isto é uma DIVERGÊNCIA DECLARADA, não uma dívida técnica a ser "quitada" depois.

	-- `getMinutesAfterMidnight`/`setMinutesAfterMidnight` (aliases minúsculos, tag `Deprecated` no
	-- dump, `PreferredDescriptorName` apontando para as versões corretas acima -- pesquisa, seção
	-- A) DELIBERADAMENTE NÃO entram aqui: regra 03, "Propriedade marcada como Deprecated no dump é
	-- implementada só se algum projeto real ainda depender dela" -- API pré-lowerCamelCase de
	-- versões antigas do Roblox, sem sinal de uso real esperado num projeto atual. Ficam com o
	-- stub `[LuauBench]` do `ClassBuilder`; sinalizado no relatório desta tarefa, não implementado
	-- às cegas.
}

local LightingBehavior: Types.Behavior = {
	Methods = Methods,

	Initialize = function(instance: Runtime.Instance): ()
		-- Upvalue POR INSTÂNCIA (uma closure fresca a cada chamada de `Initialize`, uma por
		-- `Lighting` -- na prática só existe uma, o singleton do `DataModel`, mas o mecanismo é
		-- correto para qualquer número). Ver cabeçalho deste arquivo, "MECANISMO", para o porquê de
		-- precisar desta flag (reentrância síncrona de `Changed` disparado por `SetPropertyRaw`
		-- dentro do próprio handler de `Changed`).
		local syncing = false

		-- Reescreve `ClockTime`/`TimeOfDay` a partir de `secondsSinceMidnight` (JÁ com wrap
		-- aplicado pelo chamador) -- só grava (via `SetPropertyRaw`, que sempre dispara `Changed`)
		-- a vista que realmente mudou, para não gerar um `Changed`/`LightingChanged` supérfluo na
		-- vista que já estava canônica.
		local function applyCanonical(secondsSinceMidnight: number): ()
			local canonicalClockTime = secondsSinceMidnight / SECONDS_PER_HOUR
			local canonicalTimeOfDay = formatTimeOfDay(secondsSinceMidnight)

			local currentClockTime = Runtime.Instance.GetPropertyRaw(instance, "ClockTime") :: number
			local currentTimeOfDay = Runtime.Instance.GetPropertyRaw(instance, "TimeOfDay") :: string

			syncing = true
			if currentClockTime ~= canonicalClockTime then
				Runtime.Instance.SetPropertyRaw(instance, "ClockTime", canonicalClockTime)
			end
			if currentTimeOfDay ~= canonicalTimeOfDay then
				Runtime.Instance.SetPropertyRaw(instance, "TimeOfDay", canonicalTimeOfDay)
			end
			syncing = false
		end

		instance.Changed:Connect(function(propertyName: string)
			if not syncing then
				if propertyName == "ClockTime" then
					local clockTimeValue = Runtime.Instance.GetPropertyRaw(instance, "ClockTime") :: number
					applyCanonical(secondsFromClockTime(clockTimeValue))
				elseif propertyName == "TimeOfDay" then
					local timeOfDayValue = Runtime.Instance.GetPropertyRaw(instance, "TimeOfDay") :: string
					applyCanonical(wrapSeconds(parseTimeOfDay(timeOfDayValue)))
				end
			end

			-- CONFIRMADO (pesquisa B2): "Fired when a property of Lighting changes" -- restrito às
			-- propriedades DECLARADAS pelo schema de `Lighting` (`LIGHTING_PROPERTY_NAMES`, acima;
			-- `Name`/`Parent`/`ClassName` ficam fora por construção), exceto as quatro exclusões
			-- oficialmente documentadas (`EXCLUDED_FROM_LIGHTING_CHANGED`, acima).
			--
			-- `skyChanged` é SEMPRE `false` aqui -- DIVERGÊNCIA DECLARADA: a doc oficial (B2) diz
			-- que só vira `true` quando um `Sky` é adicionado/removido ou uma propriedade de `Sky`
			-- (exceto `SkyboxOrientation`) muda -- nenhum dos dois é possível nesta leva (não há
			-- `Sky`/`Atmosphere` simulado). `false` é o valor honesto para toda mudança que ESTE
			-- módulo consegue produzir.
			--
			-- Nº DE DISPAROS PARA UMA ESCRITA ACOPLADA (`ClockTime`/`TimeOfDay`) NÃO CONFIRMADO
			-- contra o Roblox real -- só o comportamento desta SIMULAÇÃO está fixado/testado abaixo
			-- (task-services-024, achado de revisão MÉDIO). Como a sincronia acima pode reescrever a
			-- OUTRA vista (disparando `Changed` de novo, reentrante), cada `Changed` genuíno de uma
			-- propriedade de `Lighting` gera um `LightingChanged` (sem tentar deduplicar por "ação
			-- lógica do usuário" -- conceito que não existe no Roblox real tampouco, `Changed` já é
			-- por propriedade, não por assignment), o que produz os multiplicadores EXATOS abaixo,
			-- confirmados rodando `Lighting.spec.luau` (nunca adivinhados por leitura do código):
			--   * `ClockTime = <valor não-canônico>` (ex.: `6`, com `TimeOfDay` ainda no default
			--     `"14:00:00"`): 2x -- 1 de `SetPropertyRaw("TimeOfDay", ...)` reentrante (dispara
			--     dentro de `applyCanonical`, com `syncing = true`) + 1 do próprio `Changed`
			--     original de `ClockTime` (fora do `if not syncing`, sempre executa).
			--   * `TimeOfDay = <forma curta não-canônica>` (ex.: `"9:05"`): 3x -- 1 do rewrite
			--     reentrante de `ClockTime` + 1 do rewrite reentrante de `TimeOfDay` para a forma
			--     `"09:05:00"` (a string RAW `"9:05"` difere da canônica, então as duas linhas de
			--     `SetPropertyRaw` em `applyCanonical` executam) + 1 do `Changed` original.
			--   * `TimeOfDay = <forma já canônica>` (ex.: `"09:05:00"`): 2x, NÃO 3x -- só o rewrite
			--     reentrante de `ClockTime` acontece (`currentTimeOfDay == canonicalTimeOfDay` já
			--     bate, então a segunda `SetPropertyRaw` de `applyCanonical` nem executa) + 1 do
			--     `Changed` original. Mesma contagem do caso `ClockTime` acima, mas por um caminho
			--     diferente (aqui é o rewrite de `ClockTime` que falta vs. o de `TimeOfDay`).
			-- Os três casos têm cobertura de `fireCount` exato em `Lighting.spec.luau`.
			if LIGHTING_PROPERTY_NAMES[propertyName] and not EXCLUDED_FROM_LIGHTING_CHANGED[propertyName] then
				local lightingChanged = Runtime.Instance.GetPropertyRaw(instance, "LightingChanged") :: Runtime.FireableSignal<boolean>
				lightingChanged:Fire(false)
			end
		end)
	end,
}

return LightingBehavior
