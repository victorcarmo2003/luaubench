--!strict

--[[
	Lista FECHADA de todo global de VALOR do Roblox (task-valuetypes-002). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.1 ("Catalog.luau -- a lista
	fechada, fonte única") e seção 0.8 ("A lista de 22 nomes de UnsimulatedGlobals.luau está
	INCOMPLETA").

	EXTENSÃO DELIBERADA DO LUAUBENCH, NÃO CONTEÚDO DO DUMP (regra 00 permite isto explicitamente,
	desde que vivendo em módulo próprio, claramente distinto de qualquer classe simulada -- nunca
	dentro do namespace de uma classe real): `Full-API-Dump.json` não define datatypes, só os
	REFERENCIA por nome nos campos `ValueType`/`ReturnType` de membros de classe (ex.:
	`Part.Position` tem `ValueType.Name == "Vector3"`). Este módulo não é gerado a partir do dump --
	é uma lista mantida à mão, com a fonte de cada nome citada abaixo.

	## Fonte de cada grupo de nomes

	- **23 nomes originais** (`Axes`, `BrickColor`, `CFrame`, `Color3`, `ColorSequence`, `DateTime`,
	  `Enum`, `Faces`, `Font`, `NumberRange`, `NumberSequence`, `OverlapParams`,
	  `PhysicalProperties`, `Random`, `Ray`, `RaycastParams`, `Rect`, `Region3`, `TweenInfo`,
	  `UDim`, `UDim2`, `Vector2`, `Vector3`): herdados de `src/cli/UnsimulatedGlobals.luau`
	  (território `cli`, pesquisa já registrada em `.claude/agents-memory/arquiteto-cli-2026-09-05.md`,
	  "Decisão 12" -- lista de globais de valor do Roblox real, confirmada contra a documentação
	  oficial da Roblox Developer Hub). Todos existem como global CONSTRUTÍVEL no Roblox real
	  (`Vector3.new(...)`, `Enum` como namespace navegável, etc.) -- `HasGlobalConstructor = true`
	  em todos os 23.
	- **14 nomes novos**, que a lista de 23 acima ESQUECIA (seção 0.8 do desenho arquitetural desta
	  leva, fonte: documentação oficial de datatypes da Roblox Developer Hub +
	  `ValueType`/`ReturnType` do Full-API-Dump.json onde aplicável):
	  - `NumberSequenceKeypoint`, `ColorSequenceKeypoint`: pré-requisito de
	    `NumberSequence`/`ColorSequence` (que já estavam na lista original, mas sem eles não dá
	    pra CONSTRUIR nenhum dos dois -- `NumberSequence.new` recebe um array de
	    `NumberSequenceKeypoint`).
	  - `Vector3int16`, `Vector2int16`, `Region3int16`: variantes inteiras (int16) de
	    Vector3/Vector2/Region3, usadas por ex. em `Terrain`/`ChangeHistoryService`.
	  - `PathWaypoint`: elemento devolvido por `Path:GetWaypoints()`, mas também construtível via
	    `PathWaypoint.new(...)`.
	  - `CatalogSearchParams`: parâmetro de busca de `AvatarEditorService`, construtível via
	    `CatalogSearchParams.new()`.
	  - `FloatCurveKey`, `RotationCurveKey`: chaves de curva de animação (`Instance:AddKeyframe`/
	    `Animator` moderno), construtíveis via `.new(...)`.
	  - `Path2DControlPoint`: ponto de controle de `Path2D` (Roblox 2D UI paths), construtível via
	    `.new(...)`.
	  - `SharedTable`: CORRIGIDO em task-valuetypes-002-fix (achado ALTO de
	    `.claude/agents-memory/revisor-valuetypes-userdata-2026-09-05.md`) -- tem sim construtor
	    global real, confirmado contra a doc oficial (`create.roblox.com/docs/reference/engine/datatypes/SharedTable`):
	    `SharedTable.new()`/`SharedTable.new(t: table)`, chamável por script comum.
	    `HasGlobalConstructor = true`. Mutabilidade de `SharedTable` continua fora do escopo desta
	    leva (nenhum `types/SharedTable.luau` existe ainda), mas isso é questão de PRIORIZAÇÃO
	    (`Simulated = false`), não do que `HasGlobalConstructor` responde (o Roblox real expõe um
	    construtor chamável?).
	  - `Content`: CORRIGIDO em task-valuetypes-002-fix (mesmo achado ALTO) -- tem construtores
	    estáticos globais reais, confirmados contra a doc oficial
	    (`create.roblox.com/docs/reference/engine/datatypes/Content`): `Content.fromUri(uri)`,
	    `Content.fromAssetId(id)`, `Content.fromObject(obj)` e a constante `Content.none`, todos
	    chamáveis por script comum. `HasGlobalConstructor = true` -- mesmo padrão de namespace com
	    função estática em vez de `.new()` que `DateTime` (`DateTime.now()`) já recebe neste
	    catálogo.
	  - `Secret`, `RaycastResult`: EXISTEM como valor no Roblox real, mas **não têm construtor
	    global** -- `Secret` só chega via API do Engine (ex.: `HttpService:GetSecret(...)`
	    devolvendo um `Secret`), e `RaycastResult` só é devolvido por `WorldRoot:Raycast(...)` --
	    nenhum dos dois tem um global `X.new(...)`/função estática que um script comum possa
	    chamar. `HasGlobalConstructor = false` nestes dois: não viram NENHUM global no LuauBench
	    (nem valor real, nem sentinela de "não simulado") -- uma sentinela pra um nome que o
	    Roblox real também não expõe como global seria uma mensagem MENTIROSA (diria "LuauBench
	    não simula X" quando o certo, igual ao Roblox, é `X` nem existir como variável global
	    nenhuma).

	Todo `Simulated` desta leva é `false` -- task-valuetypes-002 é só a FÁBRICA (`Userdata.luau`) e
	esta lista; nenhum tipo concreto (`Vector3`, `Enum`, ...) foi implementado ainda. Tarefas
	futuras do mesmo território (`task-valuetypes-003` em diante) vão editar ESTE arquivo,
	virando `Simulated = true` nome a nome conforme cada `types/*.luau` for escrito -- nunca
	duplicando a lista em outro lugar (ver `src/cli/UnsimulatedGlobals.luau`, que passa a DERIVAR
	daqui em vez de manter sua própria lista de 23 nomes à mão -- task futura de `cli`, fora do
	território desta tarefa).

	Depende de: nada. Usado por: `src/cli/UnsimulatedGlobals.luau` (deriva `UnsimulatedGlobalNames()`
	-- task futura de `cli`), `src/valuetypes/init.luau` (deriva `BuildGlobals()`/`SimulatedNames()`
	-- task futura desta território).
]]

export type CatalogEntry = {
	-- Nome do global exatamente como o Roblox real expõe (`"Vector3"`, `"Enum"`, ...).
	Name: string,
	-- `true` quando existe um módulo em `types/` e o global funciona de verdade neste
	-- LuauBench. `false` = ainda vira sentinela nomeada em `cli/UnsimulatedGlobals.luau` (se
	-- `HasGlobalConstructor` também for `true`) -- nunca um stub silencioso (regra 03).
	Simulated: boolean,
	-- `false` para os dois nomes (`Secret`, `RaycastResult`) que existem como VALOR no Roblox mas
	-- não têm um `X.new(...)` (ou equivalente) que um script comum possa chamar como global --
	-- ver cabeçalho. Esses nomes NUNCA viram global nenhum no LuauBench, nem real nem sentinela:
	-- uma sentinela pra algo que o Roblox real também não expõe seria uma mensagem mentirosa.
	HasGlobalConstructor: boolean,
}

-- Lista base, ORDENADA alfabeticamente por conveniência de leitura (sem significado
-- funcional -- `Catalog.All`/`SimulatedNames`/`UnsimulatedGlobalNames` não dependem de ordem).
-- CONGELADA logo abaixo (cada entrada e o array em si) -- é dado compartilhado module-local,
-- nunca mutável depois do load (mesma disciplina de `SENTINELS` em
-- `src/cli/UnsimulatedGlobals.luau`).
local CATALOG: { CatalogEntry } = {
	-- 23 nomes originais (ver cabeçalho, fonte: arquiteto-cli-2026-09-05.md, Decisão 12).
	{ Name = "Axes", Simulated = false, HasGlobalConstructor = true },
	{ Name = "BrickColor", Simulated = false, HasGlobalConstructor = true },
	{ Name = "CFrame", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Color3", Simulated = false, HasGlobalConstructor = true },
	{ Name = "ColorSequence", Simulated = false, HasGlobalConstructor = true },
	{ Name = "DateTime", Simulated = false, HasGlobalConstructor = true },
	-- Simulated = true a partir de task-valuetypes-003: src/valuetypes/types/Enum.luau existe e
	-- implementa os três datatypes reais (Enums/Enum/EnumItem) por trás do global `Enum` -- ver
	-- cabeçalho deste arquivo, "Todo Simulated desta leva é false ... task-valuetypes-003 em
	-- diante vão editar ESTE arquivo, virando Simulated = true nome a nome".
	{ Name = "Enum", Simulated = true, HasGlobalConstructor = true },
	{ Name = "Faces", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Font", Simulated = false, HasGlobalConstructor = true },
	{ Name = "NumberRange", Simulated = false, HasGlobalConstructor = true },
	{ Name = "NumberSequence", Simulated = false, HasGlobalConstructor = true },
	{ Name = "OverlapParams", Simulated = false, HasGlobalConstructor = true },
	{ Name = "PhysicalProperties", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Random", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Ray", Simulated = false, HasGlobalConstructor = true },
	{ Name = "RaycastParams", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Rect", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Region3", Simulated = false, HasGlobalConstructor = true },
	{ Name = "TweenInfo", Simulated = false, HasGlobalConstructor = true },
	{ Name = "UDim", Simulated = false, HasGlobalConstructor = true },
	{ Name = "UDim2", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Vector2", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Vector3", Simulated = false, HasGlobalConstructor = true },

	-- 14 nomes novos que a lista original esquecia (ver cabeçalho, fonte: seção 0.8 do desenho
	-- arquitetural desta leva). 12 COM construtor global (SharedTable e Content corrigidos em
	-- task-valuetypes-002-fix -- ver cabeçalho, achado ALTO do revisor):
	{ Name = "NumberSequenceKeypoint", Simulated = false, HasGlobalConstructor = true },
	{ Name = "ColorSequenceKeypoint", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Vector3int16", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Vector2int16", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Region3int16", Simulated = false, HasGlobalConstructor = true },
	{ Name = "PathWaypoint", Simulated = false, HasGlobalConstructor = true },
	{ Name = "CatalogSearchParams", Simulated = false, HasGlobalConstructor = true },
	{ Name = "FloatCurveKey", Simulated = false, HasGlobalConstructor = true },
	{ Name = "RotationCurveKey", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Path2DControlPoint", Simulated = false, HasGlobalConstructor = true },
	{ Name = "SharedTable", Simulated = false, HasGlobalConstructor = true },
	{ Name = "Content", Simulated = false, HasGlobalConstructor = true },

	-- 2 SEM construtor global -- nunca viram global nenhum, nem real nem sentinela (ver
	-- cabeçalho). Presentes no catálogo só pra registrar que EXISTEM como valor no Roblox real
	-- e foram considerados deliberadamente, nunca esquecidos por omissão.
	{ Name = "Secret", Simulated = false, HasGlobalConstructor = false },
	{ Name = "RaycastResult", Simulated = false, HasGlobalConstructor = false },
}

-- Congela cada entrada individual E o array em si -- nenhum consumidor pode mutar o catálogo
-- module-local por engano (defesa em profundidade, mesmo espírito de `table.freeze(sentinel)`
-- em `UnsimulatedGlobals.luau`). Roda uma vez, no load do módulo.
for _, entry in CATALOG do
	table.freeze(entry)
end
table.freeze(CATALOG)

-- Guarda de integridade rodada uma vez no load: nome duplicado no array literal acima seria um
-- erro de cópia-e-cola que quebraria silenciosamente a garantia de disjunção entre
-- `SimulatedNames`/`UnsimulatedGlobalNames` (a mesma Name apareceria nos dois grupos se um dia
-- alguém duplicasse a entrada com `Simulated` diferente por engano). Erra alto e cedo, mesma
-- disciplina de `Userdata.Define` contra TypeName duplicado.
do
	local seen: { [string]: boolean } = {}
	for _, entry in CATALOG do
		if seen[entry.Name] then
			error(`Catalog.luau: nome duplicado '{entry.Name}' na lista CATALOG -- bug de cópia-e-cola`, 0)
		end
		seen[entry.Name] = true
	end
end

local Catalog = {}

-- Cópia NOVA a cada chamada (o array/entradas internas são congelados, mas devolver a
-- referência direta ainda deixaria um chamador tentar `table.insert` nela e falhar de um jeito
-- confuso -- uma cópia comum devolve um erro óbvio "index out of range"/permite uso normal sem
-- reexpor o estado interno). Custo desprezível: 37 entradas.
function Catalog.All(): { CatalogEntry }
	local result: { CatalogEntry } = table.create(#CATALOG)
	for i, entry in CATALOG do
		result[i] = entry
	end
	return result
end

-- Nomes com `Simulated = true` -- hoje vazio (task-valuetypes-002 não implementa nenhum tipo
-- concreto ainda, só a fábrica). Cresce conforme `task-valuetypes-003` em diante virarem `true`
-- as entradas correspondentes.
function Catalog.SimulatedNames(): { string }
	local result: { string } = {}
	for _, entry in CATALOG do
		if entry.Simulated then
			table.insert(result, entry.Name)
		end
	end
	return result
end

-- Nomes que `cli/UnsimulatedGlobals.luau` deve transformar em sentinela nomeada: ainda não
-- simulados MAS o Roblox real os expõe como global construtível (`HasGlobalConstructor`). Os 2
-- nomes sem construtor global (`Secret`/`RaycastResult`) NUNCA aparecem aqui -- ver cabeçalho,
-- "nem valor real, nem sentinela".
function Catalog.UnsimulatedGlobalNames(): { string }
	local result: { string } = {}
	for _, entry in CATALOG do
		if not entry.Simulated and entry.HasGlobalConstructor then
			table.insert(result, entry.Name)
		end
	end
	return result
end

return Catalog
