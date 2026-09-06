--!strict

--[[
	Behavior de `Pages` -- task-services-019. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6", ANTES de mexer aqui.

	BASE GENÉRICA da família de paginação inteira (`DataStoreVersionPages`, `DataStoreKeyPages`,
	`DataStoreListingPages`, `DataStorePages` -- todas `Superclass = "Pages"`, ver
	`generated/classes/*.luau`), registrada UMA VEZ sob "Pages" em `behavior/Index.luau` -- o
	achatamento de métodos que `Runtime.ClassRegistry.resolveClassMethods` já faz percorrendo a
	cadeia de classes (mesmo mecanismo de `./GlobalDataStore.luau`, ver o cabeçalho dele) entrega
	`GetCurrentPage`/`AdvanceToNextPageAsync`/`IsFinished` para QUALQUER subclasse sem precisar de
	entrada própria no mapa. `./DataStore.luau` (ÚNICO consumidor desta tarefa) só usa
	`DataStoreVersionPages`/`DataStoreKeyPages`; `DataStoreListingPages`/`DataStorePages` (usadas
	por `ListDataStoresAsync`/`GetSortedAsync`, fora do território desta tarefa) já ficam prontas
	para reusar exatamente esta mesma fábrica quando uma tarefa futura as implementar.

	MODELO: o CHAMADOR (`./DataStore.luau`) já materializa a lista COMPLETA de itens da consulta --
	já filtrada, ordenada e (no caso de `ListKeysAsync`) resolvida a partir do cursor de entrada --
	ANTES de construir uma `Pages`. `Pages.New` só FATIA essa lista em páginas de `pageSize` itens;
	este módulo não conhece `DataStore`/`Store`/query nenhuma -- seu território é só paginação
	genérica, igual ao dump real: `Pages`/`GetCurrentPage`/`AdvanceToNextPageAsync`/`IsFinished` não
	têm NADA específico de DataStore no schema (`generated/classes/Pages.luau`, `Schema` só com
	`IsFinished`).

	ESTADO PRIVADO por instância (L2.0.2, `InstanceState` -- nunca propriedade pública nem módulo
	compartilhado: cada `Pages` tem seu PRÓPRIO buffer/cursor, diferente de `DataStoreService`
	sozinho, que É singleton):
	- `_LuauBenchPagesItems`: TODOS os itens da consulta, já materializados (array; nunca mutado
	  depois de `Pages.New` -- cada página é uma CÓPIA fatiada dele, ver `loadPage`).
	- `_LuauBenchPagesPageSize`: tamanho de página efetivo (SEMPRE positivo -- `0`/omitido já
	  resolvido pelo CHAMADOR para o default antes de chegar aqui, ver `./DataStore.luau`,
	  `DEFAULT_PAGE_SIZE`; `Pages.New` erra -- engenharia interna -- se receber `<= 0`).
	- `_LuauBenchPagesCurrentPage`: a fatia (array) visível AGORA por `GetCurrentPage()`.
	- `_LuauBenchPagesNextStartIndex`: índice (1-based) do PRIMEIRO item que `AdvanceToNextPageAsync`
	  vai incluir na PRÓXIMA página.
	- `_LuauBenchPagesHasCursorProperty`: `true` só para as classes cujo schema REAL declara
	  `Cursor` (`DataStoreKeyPages`/`DataStoreListingPages` -- ver `generated/classes/
	  DataStoreKeyPages.luau`/`DataStoreListingPages.luau`); `DataStoreVersionPages`/
	  `DataStorePages` NÃO declaram `Cursor` (confirmado lendo os dois arquivos gerados: `Schema =
	  {}`) -- `Pages.New` nunca escreve essa propriedade nelas, decidido por quem chama
	  (`./DataStore.luau`), nunca adivinhado aqui.

	`IsFinished`/`Cursor` são propriedades REAIS do schema gerado (`ReadOnly = true`) -- escritas
	via `Runtime.Instance.SetPropertyRaw`, a mesma via de engenharia que `./DataStoreKeyInfo.luau`/
	`./RunService.luau`/`./Lighting.luau` já usam para `ReadOnly` (Decisão 6, item 2: `SetPropertyRaw`
	NUNCA consulta o schema, então ignora `ReadOnly = true` sem problema -- o enforcement de
	ESCRITA NORMAL do script continua vindo do próprio schema, via `__newindex`).

	`Cursor`: STRING opaca -- aqui, o índice 1-based de onde a PRÓXIMA página começaria (`""`
	quando `IsFinished`). FORMATO PRÓPRIO DO LUAUBENCH, DIVERGÊNCIA DECLARADA (regra 00): o cursor
	real do Roblox é opaco e não documentado publicamente; o que importa para um script real é só
	que seja uma STRING que, devolvida a uma chamada seguinte de `ListKeysAsync(prefix, pageSize,
	cursor, excludeDeleted)`, retome de onde parou -- é exatamente o que este formato garante
	DENTRO DE UM MESMO PROCESSO (sem garantia de estabilidade entre execuções diferentes do
	LuauBench, já que a lista subjacente pode ter mudado). Um cursor desconhecido/corrompido/de
	outra consulta é tratado como "começar do zero" (ver `decodeStartIndex`) -- aproximação de
	boa-fé, o Roblox real também não documenta o que acontece com um cursor incompatível.

	`AdvanceToNextPageAsync` tem a tag `Yields` no dump -- passa por `../AsyncCall.luau`, o ponto
	único de suspensão de `services` (L2.0.1). Chamado quando `IsFinished` já é `true`: ERRA
	(aproximação de boa-fé, família Roblox -- NÃO CONFIRMADA por fonte primária, nenhuma pesquisa
	desta leva cravou o texto exato) em vez de virar um no-op silencioso -- mesma disciplina de
	"nunca aceitar em silêncio fingindo que processou" que o resto desta leva já segue para outras
	lacunas (ver `./DataStore.luau`, "SORT DIRECTION").

	Depende de: `../../runtime` (`ClassRegistry.NewEngineInstance`, `Instance.SetPropertyRaw`/
	`GetPropertyRaw`), `../InstanceState` (L2.0.2), `../AsyncCall` (L2.0.1). Usado por:
	`./DataStore.luau` (`ListVersionsAsync`/`ListKeysAsync`, via `.New`) e, em tarefas futuras,
	por `./OrderedDataStore.luau`/`./DataStoreService.luau` (`GetSortedAsync`/`ListDataStoresAsync`).
]]

local Runtime = require("../../runtime")
local InstanceState = require("../InstanceState")
local AsyncCall = require("../AsyncCall")

local ItemsState = InstanceState.new("_LuauBenchPagesItems") :: InstanceState.InstanceStateAccessor<{ unknown }>
local PageSizeState = InstanceState.new("_LuauBenchPagesPageSize") :: InstanceState.InstanceStateAccessor<number>
local CurrentPageState = InstanceState.new("_LuauBenchPagesCurrentPage") :: InstanceState.InstanceStateAccessor<{ unknown }>
local NextStartIndexState = InstanceState.new("_LuauBenchPagesNextStartIndex") :: InstanceState.InstanceStateAccessor<number>
local HasCursorPropertyState = InstanceState.new("_LuauBenchPagesHasCursorProperty") :: InstanceState.InstanceStateAccessor<boolean>

-- Engenharia interna -- mesmo padrão de `storeIdOf` em `./GlobalDataStore.luau`: só `Pages.New`
-- (abaixo) cria instâncias desta classe, então uma leitura ausente é bug de `services`, nunca algo
-- que um script comum possa provocar.
local function requireState<T>(instance: Runtime.Instance, accessor: InstanceState.InstanceStateAccessor<T>, label: string): T
	local value = accessor.Get(instance)
	if value == nil then
		error(`engenharia interna: instância de Pages sem '{label}' -- só Pages.New (./Pages.luau) pode criar essas instâncias`, 2)
	end
	return value
end

-- Fatia `[startIndex, startIndex + pageSize)` do buffer completo, grava a página CORRENTE e
-- avança `_LuauBenchPagesNextStartIndex` -- ponto ÚNICO que materializa uma página, chamado tanto
-- por `Pages.New` (1a página, carregada de imediato -- o Roblox real também não exige um
-- `AdvanceToNextPageAsync` antes do primeiro `GetCurrentPage`, confirmado pelo uso real do
-- ProfileStore em `ProfileVersionQuery`, ver pesquisa-datastore-2026-09-05.md) quanto por
-- `Methods.AdvanceToNextPageAsync`.
local function loadPage(instance: Runtime.Instance, startIndex: number): ()
	local items = requireState(instance, ItemsState, "_LuauBenchPagesItems")
	local pageSize = requireState(instance, PageSizeState, "_LuauBenchPagesPageSize")

	local endIndexExclusive = math.min(startIndex + pageSize, #items + 1)
	local page: { unknown } = {}
	for index = startIndex, endIndexExclusive - 1 do
		table.insert(page, items[index])
	end

	local nextStartIndex = startIndex + pageSize
	local finished = nextStartIndex > #items

	CurrentPageState.Set(instance, page)
	NextStartIndexState.Set(instance, nextStartIndex)
	Runtime.Instance.SetPropertyRaw(instance, "IsFinished", finished)

	if HasCursorPropertyState.Get(instance) == true then
		Runtime.Instance.SetPropertyRaw(instance, "Cursor", if finished then "" else tostring(nextStartIndex))
	end
end

-- Ver cabeçalho, "Cursor" -- `nil`/`""`/não numérico/`< 1` tudo vira "começar do zero" (1),
-- aproximação de boa-fé para um cursor incompatível/de outra consulta.
local function decodeStartIndex(cursor: string?): number
	if cursor == nil or cursor == "" then
		return 1
	end
	local parsed = tonumber(cursor)
	if parsed == nil or parsed < 1 then
		return 1
	end
	return math.floor(parsed)
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `Pages:GetCurrentPage(): Array`. Cópia NOVA a cada chamada -- mesma disciplina
	-- de `Enum.GetEnumItems`/`Catalog.All`: nunca expor a referência interna (um script que faz
	-- `table.remove` no retorno não pode corromper o estado desta `Pages`).
	GetCurrentPage = function(self: Runtime.Instance): { unknown }
		local page = requireState(self, CurrentPageState, "_LuauBenchPagesCurrentPage")
		local copy: { unknown } = table.create(#page)
		for index, item in page do
			copy[index] = item
		end
		return copy
	end,

	-- Doc oficial: `Pages:AdvanceToNextPageAsync(): null` -- Yields. Ver cabeçalho, "AdvanceToNextPageAsync".
	AdvanceToNextPageAsync = function(self: Runtime.Instance): ()
		AsyncCall.Yield("Pages:AdvanceToNextPageAsync")

		local alreadyFinished = Runtime.Instance.GetPropertyRaw(self, "IsFinished") :: boolean?
		if alreadyFinished == true then
			-- Aproximação de boa-fé, família Roblox (NÃO CONFIRMADA por fonte primária) -- ver
			-- cabeçalho deste arquivo. `self.ClassName` (não um texto genérico "Pages") porque o
			-- Roblox real reportaria a classe CONCRETA (`DataStoreVersionPages`/`DataStoreKeyPages`),
			-- nunca a base abstrata.
			error(`{self.ClassName}:AdvanceToNextPageAsync() cannot be called because this is already the last page`, 2)
		end

		local nextStartIndex = requireState(self, NextStartIndexState, "_LuauBenchPagesNextStartIndex")
		loadPage(self, nextStartIndex)
	end,
}

--[[
	Fábrica (fora do contrato `Types.Behavior`, mesmo padrão de `./DataStoreKeyInfo.luau`, `New`):
	constrói uma instância de `className` (deve ser uma subclasse CONCRETA de `Pages` -- esta
	tarefa só usa `"DataStoreVersionPages"`/`"DataStoreKeyPages"`) já com a 1a página carregada.

	- `items`: buffer COMPLETO, já filtrado/ordenado pelo CHAMADOR -- nunca mutado por este módulo
	  depois de guardado (cada página é uma cópia fatiada, ver `loadPage`).
	- `pageSize`: SEMPRE positivo (engenharia interna -- erra se `<= 0`; resolver `0`/omitido para
	  o default é responsabilidade do CHAMADOR, que conhece o default correto para o SEU método).
	- `hasCursorProperty`: `true` só se o schema REAL de `className` declara `Cursor` -- ver
	  cabeçalho, "ESTADO PRIVADO".
	- `resumeCursor`: `Cursor` de uma página anterior desta MESMA consulta (`ListKeysAsync`) --
	  `nil` para uma consulta NOVA (`ListVersionsAsync`, que nem tem parâmetro de cursor no dump).
]]
local function new(className: string, items: { unknown }, pageSize: number, hasCursorProperty: boolean, resumeCursor: string?): Runtime.Instance
	if pageSize <= 0 then
		error(`engenharia interna: Pages.New('{className}', ...) recebeu pageSize <= 0 ({pageSize}) -- resolver o default ANTES de chamar (ver ./DataStore.luau, DEFAULT_PAGE_SIZE)`, 2)
	end

	local instance = Runtime.ClassRegistry.NewEngineInstance(className)

	ItemsState.Set(instance, items)
	PageSizeState.Set(instance, pageSize)
	HasCursorPropertyState.Set(instance, hasCursorProperty)

	loadPage(instance, decodeStartIndex(resumeCursor))
	return instance
end

-- Módulo devolve `{ Methods, New }` -- MAIS do que `Types.Behavior` declara, mesmo padrão de
-- `./DataStoreKeyInfo.luau`: `behavior/Index.luau` faz `require("./Pages") :: Types.Behavior`
-- (downcast seguro), `./DataStore.luau` faz `require("./Pages")` sem cast para alcançar `.New`.
return {
	Methods = Methods,
	New = new,
}
