--!strict

--[[
	Globais de VALOR do Roblox que o LuauBench AINDA NÃO simula (ex.: `Rect`/`NumberRange`/
	`TweenInfo` -- leva 2 de `src/valuetypes/`). Desenho original em .claude/agents-memory/
	arquiteto-cli-2026-09-05.md, Decisão 12, "Globais de valor não simulados: erro nomeado, nunca
	`nil`"; REVISADO por task-cli-025 (arquiteto-valuetypes-2026-09-05.md, seção 3.1 "Catalog.luau"
	e seção 3.4 "cli", item (d)) -- ver "Lista DERIVADA", abaixo.

	Extensão do LuauBench FORA do namespace de qualquer classe real (regra 00 permite isso
	explicitamente, desde que viva em módulo próprio -- nunca dentro do schema/comportamento de uma
	classe simulada). Mesma disciplina da regra 03 ("Service não coberto ainda não é stub
	silencioso que finge funcionar"): sem este módulo, `Rect.new(0, 0, 100, 100)` num script do
	usuário erraria `attempt to index nil with 'new'` -- tecnicamente correto (Rect não existe),
	mas inútil para quem está depurando um script real. Em vez disso, cada nome desta lista vira
	uma tabela cujo `__index`/`__newindex` erram nomeando explicitamente a lacuna, com o prefixo
	`[LuauBench]` (Messages.UnsimulatedGlobal) -- OBRIGATÓRIO porque isto NÃO tem contraparte real
	(no Roblox, `Rect` funciona) -- é o LuauBench que está incompleto, nunca o Roblox (regra de
	idioma dos erros, mesma disciplina de `Services.new`).

	Lista DERIVADA de `ValueTypes.Catalog.UnsimulatedGlobalNames()` (task-cli-025, item d) -- NUNCA
	mais mantida à mão aqui. Antes desta tarefa, este arquivo tinha as 23 strings da Decisão 12
	escritas literalmente; agora `src/valuetypes/Catalog.luau` é a fonte ÚNICA de "o que existe como
	global de valor no Roblox" e "o que já simulamos" (`CatalogEntry.Simulated`) -- este módulo só
	pergunta "quais NÃO estão simuladas ainda" (`Simulated = false` E `HasGlobalConstructor = true`,
	ver `Catalog.luau`). Consequência que vale mais que a economia de duplicar uma lista pequena:
	quando `src/valuetypes/types/Rect.luau` (leva 2) existir e `Catalog.luau` virar `Simulated =
	true` pra "Rect", a sentinela correspondente desaparece SOZINHA na próxima carga deste módulo
	-- sem que ninguém precise lembrar de editar dois territórios no mesmo commit. `Vector3`/
	`Vector2`/`Color3`/`CFrame`/`UDim`/`UDim2`/`Enum` (leva 1, já simulados) NÃO aparecem mais
	aqui -- viram global REAL via `ValueTypes.BuildGlobals()`, sobreposto por cima deste módulo em
	`ScriptEnvironment.Build` (ver aquele módulo, item (c)).

	Erra com `error(message, 2)`: nível 2 atribui a posição ao CÓDIGO DO SCRIPT que indexou/gravou
	o global (o ponto de chamada de `__index`/`__newindex`, ex.: `Rect.new(...)`), nunca a este
	arquivo -- mesma convenção de erro "voltado ao usuário" já usada em `Instance.luau`
	(`error(..., 2)` em todo `__index`/`__newindex`).

	`Build()` devolve uma tabela NOVA a cada chamada (para que `ScriptEnvironment.Build`, que usa o
	resultado como base mutável antes de sobrepor `ValueTypes.BuildGlobals()`/`game`/`workspace`/
	`script`/..., nunca mute um estado compartilhado por engano) -- mas os SENTINELS internos (as
	tabelas que de fato erram) são construídos uma ÚNICA vez, no load deste módulo, e reaproveitados
	por referência em toda chamada: são completamente sem estado (só erram, nunca guardam nada),
	então compartilhá-los entre execuções/scripts é seguro e evita reconstruir N tabelas+metatables
	a cada Script/ModuleScript executado (regra 01, nota de performance -- mesmo espírito da que se
	aplica a `services` não reparsear o dump a cada `luaubench run`, aplicado aqui por analogia).
]]

local ValueTypes = require("../valuetypes")
local Messages = require("./Messages")

-- Lista DERIVADA -- ver cabeçalho, "Lista DERIVADA". Nunca mais uma lista literal mantida à mão
-- aqui: `Catalog.UnsimulatedGlobalNames()` já devolve uma tabela NOVA a cada chamada, então usá-la
-- diretamente (sem cópia própria) é seguro -- este `local` só é lido, uma vez, no load do módulo.
local UNSIMULATED_GLOBAL_NAMES: { string } = ValueTypes.Catalog.UnsimulatedGlobalNames()

-- Uma tabela vazia cujo __index/__newindex erram citando `name`, congelada DEPOIS de
-- `setmetatable` (nunca antes -- confirmado em Instance.luau/task-runtime-027:
-- `setmetatable`/`debug.setmetatable` sobre uma tabela JÁ congelada falha com "attempt to modify a
-- readonly table", então a ordem certa é montar a metatable primeiro e congelar por cima).
-- `table.freeze` é defesa em profundidade (mesma disciplina de ClassMethods/ClassSchema em
-- Instance.luau): mesmo que um script consiga contornar o erro de __newindex por algum caminho não
-- antecipado (`rawset`, por exemplo -- disponível desde task-runtime-026), `table.freeze` marca a
-- tabela como readonly no nível da VM, e `rawset` sobre uma tabela readonly também erra.
local function buildSentinel(name: string): unknown
	local message = Messages.UnsimulatedGlobal(name)
	local sentinel = setmetatable({}, {
		__index = function(_self, _key): unknown
			error(message, 2)
		end,
		__newindex = function(_self, _key, _value): ()
			error(message, 2)
		end,
	})
	table.freeze(sentinel)
	return sentinel
end

-- Construídos uma única vez no load do módulo -- ver cabeçalho, "sem estado, seguro de
-- compartilhar".
local SENTINELS: { [string]: unknown } = {}
for _, name in UNSIMULATED_GLOBAL_NAMES do
	SENTINELS[name] = buildSentinel(name)
end

local UnsimulatedGlobals = {}

function UnsimulatedGlobals.Build(): { [string]: unknown }
	local result: { [string]: unknown } = {}
	for name, sentinel in SENTINELS do
		result[name] = sentinel
	end
	return result
end

return UnsimulatedGlobals
