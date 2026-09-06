--!strict

--[[
	Behavior de `SoundService` -- task-services-025. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.5.3 -- `SoundService`: superfície e
	nada mais, deliberadamente", ANTES de mexer aqui -- este arquivo é a ÚNICA exceção a essa
	decisão, e existe SÓ por causa dela.

	## Por que este arquivo existe, apesar de L2.5.3 dizer "sem Behavior próprio"

	A decisão original de L2.5.3 foi: 17 membros sobrevivem ao filtro (13 Property, 4 Function, 0
	Event); para o público-alvo do LuauBench (lógica pura, data manager, state machine) a classe é
	irrelevante, então PROPRIEDADES guardam e devolvem (dado morto) e os QUATRO métodos ficam com o
	stub genérico `[LuauBench] ... not simulated by LuauBench yet` do `ClassBuilder` -- SEM
	`Behavior` nenhum. A nota "b" daquela seção dizia explicitamente que `PlayLocalSound` NÃO
	ganharia tratamento tipo `RejectingSignal` porque a regra B.5.5 (metodologia de pesquisa)
	exige CITAÇÃO AO VIVO de erro real naquele membro específico para recortar uma exceção do balde
	"superfície client-only, comportamento não simulado" -- e na época só havia relato de
	comunidade sem string verbatim.

	Isso MUDOU: `task-services-028` (pesquisa dedicada às pendências da leva 2,
	`.claude/agents-memory/pesquisa-services-leva2-pendencias-2026-09-05.md`, seção 5) encontrou
	citação AO VIVO, de duas fontes independentes reproduzindo o mesmo texto atribuído a um autor
	nomeado (`Megaificent`) num thread do DevForum
	(https://devforum.roblox.com/t/playlocalsound-not-working-when-ontouched-event-is-triggered/562930):

		"SoundService:PlayLocalSound only works on a client."

	Com citação viva confirmada, a regra B.5.5 SE APLICA: `PlayLocalSound` deixa de ser "superfície
	sem behavior" e ganha a mensagem EXATA em vez do stub genérico -- mesma disciplina já usada para
	`ClassName`/eventos/etc (erro com contraparte real no Roblox usa a família do Roblox, em inglês,
	SEM prefixo `[LuauBench]`, ver `ClassBuilder.luau`, "REGRA DE IDIOMA DOS ERROS").

	## Por que isto é um `Behavior` e não outra coisa

	`Types.Behavior.Methods` (`../Types.luau`) é o ÚNICO mecanismo que `ClassBuilder.Build`
	("Módulos" -> "src/services/ClassBuilder.luau", passo b) usa para substituir o stub genérico de
	um método por uma implementação própria -- não existe campo em `Types.GeneratedClass`
	(o que o gerador emite a partir do dump) para uma mensagem de erro customizada por método, e
	inventar um seria misturar "o quê" (gerado) com "o como" (à mão), o que a regra 03 proíbe
	("o dump só dá a superfície, nunca o comportamento"). `RejectingSignal` (`../RejectingSignal.luau`)
	NÃO se aplica aqui: é estruturalmente compatível com `Runtime.Signal<...>` (Connect/Once/Wait/
	DisconnectAll), pensado para EVENTOS instalados como propriedade -- `PlayLocalSound` é um
	MÉTODO (`Function` no dump), não um Signal. Por isso este módulo é o mecanismo MAIS LEVE possível
	dentro do desenho existente: um `Types.Behavior` com `Methods` contendo SÓ esta uma entrada,
	nenhum `Initialize`, nenhum estado.

	## Escopo -- NADA MUDA para os outros 16 membros

	`GetListener`/`SetListener`/`GetMixerTime` (as outras 3 Function) continuam SEM entrada aqui --
	`ClassBuilder.Build` os cobre com o stub `[LuauBench] SoundService:{Método}() exists in the
	Roblox API Dump but is not simulated by LuauBench yet`, exatamente como a decisão original de
	L2.5.3 previu. As 13 Property continuam sem `Behavior`: guardam e devolvem via o mecanismo
	genérico de schema de `Runtime.Instance` (nenhum `Initialize` aqui as toca).

	Depende de: `../../runtime` (tipo `Instance`), `../Types` (`Types.Behavior`). Usado por:
	`./Index.luau` (registro em `BehaviorIndex.SoundService`).
]]

local Runtime = require("../../runtime")
local Types = require("../Types")

-- String EXATA confirmada por citação ao vivo (ver cabeçalho) -- nunca parafraseada. `error(...,
-- 2)` culpa o call site do script do usuário, mesma convenção já usada por `RejectingSignal`/
-- `ClassBuilder.makeUnsimulatedMethodStub`.
local PLAY_LOCAL_SOUND_CLIENT_ONLY_MESSAGE = "SoundService:PlayLocalSound only works on a client."

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `PhysicsService.luau`/
-- `RunService.luau`.
local Methods: { [string]: unknown } = {
	-- O LuauBench é servidor fixo (`RunService.IsServer() == true`, ver `../behavior/RunService.
	-- luau`) -- não existe um contexto de cliente em que este método pudesse ter sucesso nesta
	-- leva, então SEMPRE erra. Quando um `--client` existir um dia, é este corpo que passa a ser
	-- condicional (mesma nota já registrada no cabeçalho de `RejectingSignal.luau` para
	-- `RunService.RenderStepped`).
	PlayLocalSound = function(_self: Runtime.Instance, _sound: unknown): ()
		error(PLAY_LOCAL_SOUND_CLIENT_ONLY_MESSAGE, 2)
	end,
}

local SoundServiceBehavior: Types.Behavior = {
	Methods = Methods,
}

return SoundServiceBehavior
