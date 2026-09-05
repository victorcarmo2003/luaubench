--!strict

--[[
	Globais de VALOR do Roblox que ainda não existem no LuauBench (`Vector3`/`CFrame`/`Color3`/
	`Enum`/... -- leva 3 de `services`, "tipos de valor", ainda não desenhada). Desenho completo em
	.claude/agents-memory/arquiteto-cli-2026-09-05.md, Decisão 12, "Globais de valor não simulados:
	erro nomeado, nunca `nil`".

	Extensão do LuauBench FORA do namespace de qualquer classe real (regra 00 permite isso
	explicitamente, desde que viva em módulo próprio -- nunca dentro do schema/comportamento de uma
	classe simulada). Mesma disciplina da regra 03 ("Service não coberto ainda não é stub
	silencioso que finge funcionar"): sem este módulo, `Vector3.new(1, 2, 3)` num script do usuário
	erraria `attempt to index nil with 'new'` -- tecnicamente correto (Vector3 não existe), mas
	inútil para quem está depurando um script real (ProfileStore e companhia usam Vector3/CFrame o
	tempo todo). Em vez disso, cada nome desta lista vira uma tabela cujo `__index`/`__newindex`
	erram nomeando explicitamente a lacuna, com o prefixo `[LuauBench]` (Messages.UnsimulatedGlobal)
	-- OBRIGATÓRIO porque isto NÃO tem contraparte real (no Roblox, `Vector3` funciona) -- é o
	LuauBench que está incompleto, nunca o Roblox (regra de idioma dos erros, mesma disciplina de
	`Services.new`).

	Lista fechada nesta leva (a mesma da Decisão 12, verbatim -- não adicionar nome aqui sem
	revisitar o desenho): Vector3, Vector2, CFrame, Color3, UDim, UDim2, Rect, Region3, Ray,
	NumberRange, NumberSequence, ColorSequence, BrickColor, TweenInfo, PhysicalProperties, Faces,
	Axes, Random, DateTime, Font, RaycastParams, OverlapParams, Enum.

	Erra com `error(message, 2)`: nível 2 atribui a posição ao CÓDIGO DO SCRIPT que indexou/gravou
	o global (o ponto de chamada de `__index`/`__newindex`, ex.: `Vector3.new(...)`), nunca a este
	arquivo -- mesma convenção de erro "voltado ao usuário" já usada em `Instance.luau`
	(`error(..., 2)` em todo `__index`/`__newindex`).

	`Build()` devolve uma tabela NOVA a cada chamada (para que `ScriptEnvironment.Build`, que usa o
	resultado como base mutável antes de sobrepor `game`/`workspace`/`script`/..., nunca mute um
	estado compartilhado por engano) -- mas os 23 SENTINELS internos (as tabelas que de fato erram)
	são construídos uma ÚNICA vez, no load deste módulo, e reaproveitados por referência em toda
	chamada: são completamente sem estado (só erram, nunca guardam nada), então compartilhá-los
	entre execuções/scripts é seguro e evita reconstruir 23 tabelas+metatables a cada Script/
	ModuleScript executado (regra 01, nota de performance -- mesmo espírito da que se aplica a
	`services` não reparsear o dump a cada `luaubench run`, aplicado aqui por analogia).
]]

local Messages = require("./Messages")

-- Lista fechada -- ver cabeçalho. Ordem alfabética por conveniência de leitura, sem significado.
local UNSIMULATED_GLOBAL_NAMES: { string } = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"DateTime",
	"Enum",
	"Faces",
	"Font",
	"NumberRange",
	"NumberSequence",
	"OverlapParams",
	"PhysicalProperties",
	"Random",
	"Ray",
	"RaycastParams",
	"Rect",
	"Region3",
	"TweenInfo",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector3",
}

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
