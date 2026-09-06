--!strict

--[[
	Behavior de `OrderedDataStore` -- task-services-020. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6", ANTES de mexer aqui.
	Constrói EM CIMA de `./GlobalDataStore.luau` (task-018, já aprovado -- `OrderedDataStore` HERDA
	de `GlobalDataStore` no dump, `generated/classes/OrderedDataStore.luau`, `Superclass =
	"GlobalDataStore"`) e de `./Pages.luau` (task-019, já aprovado -- fábrica genérica de
	paginação, mesma base que `./DataStore.luau` já reusa para `ListVersionsAsync`/`ListKeysAsync`).

	`GetAsync` NÃO é reimplementado aqui -- continua resolvido pela cadeia de classes de
	`Runtime.ClassRegistry` a partir do `Methods` registrado sob `"GlobalDataStore"` (mesmo
	achatamento que já beneficia `DataStore`, ver o cabeçalho de `./GlobalDataStore.luau`). Este
	módulo só cobre `GetSortedAsync` -- o ÚNICO método que `generated/classes/OrderedDataStore.luau`
	declara (`MethodNames = { "GetSortedAsync" }`, confirmado lendo o arquivo gerado: o dump nunca
	redeclara um membro herdado, então `SetAsync`/`UpdateAsync`/`IncrementAsync`/`RemoveAsync` nem
	aparecem no `MethodNames` desta classe).

	DESVIO DE TERRITÓRIO DECLARADO (reportar ao chat principal -- ver o relatório desta tarefa):
	a validação "valor precisa ser INTEIRO" que `SetAsync`/`UpdateAsync`/`IncrementAsync` precisam
	ganhar para `OrderedDataStore` NÃO mora neste arquivo. `ClassBuilder.Build`
	(`src/services/ClassBuilder.luau`, passo (a)) só aceita, no `behavior.Methods` de UMA classe,
	chaves que existem no `MethodNames` DELA MESMA -- registrar um `SetAsync` próprio aqui estouraria
	"método 'SetAsync' não existe em 'OrderedDataStore' segundo o Roblox API Dump" no load, porque
	esse nome só está declarado no `MethodNames` de `GlobalDataStore`, nunca no de
	`OrderedDataStore` (confirmado tentando -- não é suposição). Não há como sobrescrever SÓ para a
	subclasse através do achatamento de `Runtime.ClassRegistry.resolveClassMethods` sem alterar
	`ClassBuilder.luau`/`src/services/init.luau`, ambos fora do território desta tarefa
	(`.claude/tasks.json`, task-services-020) e compartilhados por TODAS as classes de `services`.
	Por isso a validação foi acrescentada em `./GlobalDataStore.luau` (`checkIntegerForOrderedDataStore`/
	`assertIntegerForOrderedDataStore`), gated por `self.ClassName == "OrderedDataStore"` -- reaproveita
	a lógica inteira de leitura/escrita sem duplicar UMA linha dela. Ver o cabeçalho daquele arquivo,
	seção "task-services-020", para o raciocínio completo.

	REMOÇÃO PERMANENTE (L2.1.3, despacho da tarefa: "a remoção em OrderedDataStore é PERMANENTE, SEM
	tombstone -- diferente de GlobalDataStore/DataStore"): `RemoveAsync` (herdado de
	`GlobalDataStore`, também não reimplementado aqui) continua criando um tombstone em
	`datastore/Store.luau` por baixo -- mas isso é OBSERVACIONALMENTE equivalente a uma remoção
	permanente para QUALQUER script que só tenha acesso a um `OrderedDataStore`: esta classe nunca
	ganha `GetVersionAsync`/`ListVersionsAsync` (membros de "DataStore" no dump, fora da cadeia de
	superclasses de `OrderedDataStore` -- ver `./DataStore.luau`, cabeçalho), e `GetSortedAsync`
	(abaixo) só enxerga a versão CORRENTE de cada chave via `store:Get`, que já trata tombstone como
	ausente. Ou seja: depois de um `RemoveAsync`, a chave NUNCA MAIS aparece em `GetAsync`/
	`IncrementAsync`/`GetSortedAsync`, e não existe NENHUM método alcançável nesta classe capaz de
	ler o histórico de volta -- decisão documentada em vez de construir um caminho de "hard delete"
	real dentro de `datastore/Store.luau` (fora do território desta tarefa, módulo compartilhado por
	toda a família DataStore). Ver o comentário de `RemoveAsync` em `./GlobalDataStore.luau` para o
	mesmo raciocínio, no lugar onde o método de fato vive.

	GetSortedAsync(ascending, pagesize, minValue, maxValue): DataStorePages -- Yields (doc oficial).
	Cada item da página é uma TABELA PLANA `{ key: string, value: number }` -- NUNCA uma Instance,
	diferente de `DataStoreObjectVersionInfo`/chave-string usados por `./DataStore.luau`. Isso não é
	uma aproximação: é assim que o Roblox real devolve os itens de `GetSortedAsync` (confirmado pela
	pesquisa desta leva, pesquisa-datastore-2026-09-05.md, linha 132: "cada item da página é
	{key=..., value=...}").

	PAGESIZE: default `50` -- mais confirmado que o de `./DataStore.luau` (aquele era NÃO CONFIRMADO
	para ListVersionsAsync/ListKeysAsync especificamente; este número aparece citado direto para
	GetSortedAsync na mesma pesquisa). O "máximo de 100" citado por fonte SECUNDÁRIA (resumo de
	WebFetch, não visto na fonte primária/YAML) NÃO é imposto aqui -- instrução explícita do despacho
	da tarefa: "aceite sem impor teto, comentando isso no código". `pagesize` omitido/`<= 0` cai no
	default; qualquer valor positivo, por maior que seja, é aceito como está.

	MINVALUE/MAXVALUE: `nil` de qualquer lado == sem limite naquele lado (mesma convenção de
	`./DataStore.luau` para `minDate`/`maxDate`, adaptada aqui para `nil` em vez de `<= 0` porque um
	`value` de OrderedDataStore pode legitimamente ser negativo ou zero -- ver "POSITIVIDADE NÃO
	EXIGIDA" em `./GlobalDataStore.luau`). Filtro é `minValue <= value <= maxValue`, inclusive nas
	duas pontas -- doc oficial não é explícita sobre inclusividade das pontas para este método
	específico; a convenção usual do Roblox para range é inclusiva, e não há fonte contradizendo
	isso (aproximação de boa-fé).

	DESEMPATE DE ORDENAÇÃO: quando dois itens têm o MESMO `value`, o desempate é por `key` alfabética
	crescente (SEMPRE, independente de `ascending`) -- o Roblox real não documenta desempate;
	determinístico e testável é preferível a depender de uma ordem de iteração instável (mesma
	disciplina de `./DataStore.luau`, `ListKeysAsync`, ordem alfabética via `store:ListKeys`).

	Depende de: `../../runtime`, `../AsyncCall` (L2.0.1), `./GlobalDataStore` (Store/StoreIdOf --
	MESMO store singleton, nunca um segundo `Store.new()`, ver `./GlobalDataStore.luau`, "STORE
	ÚNICO, MÓDULO-LOCAL"), `./Pages` (fábrica de paginação, `New("DataStorePages", ...)`).
]]

local Runtime = require("../../runtime")
local AsyncCall = require("../AsyncCall")
local Store = require("../datastore/Store")
local GlobalDataStoreBehavior = require("./GlobalDataStore")
local PagesBehavior = require("./Pages")

local store = GlobalDataStoreBehavior.Store :: Store.Store
local storeIdOf = GlobalDataStoreBehavior.StoreIdOf :: (Runtime.Instance) -> string

-- Ver cabeçalho, "PAGESIZE".
local DEFAULT_PAGE_SIZE = 50

type SortedEntry = { key: string, value: number }

--[[
	Constrói o pool de itens de `GetSortedAsync`: um `{ key, value }` por chave VIVA (nunca
	tombstoned -- ver cabeçalho, "REMOÇÃO PERMANENTE") cujo valor numérico esteja dentro de
	`[minValue, maxValue]`, ordenado por `value` (crescente/decrescente conforme `ascending`) com
	`key` alfabética como desempate.

	`store:ListKeys` (task-017/019, `datastore/Store.luau`) devolve TODAS as chaves conhecidas,
	tombstoned ou não, mas SEM o valor em si (`VersionInfo` não carrega `Value` -- só metadata de
	versão). Por isso o valor de cada chave é lido de novo via `store:Get` -- que JÁ trata uma versão
	corrente tombstoned como ausente (`Store.luau`, `self.Get`), exatamente a regra que faz uma
	chave removida nunca aparecer aqui, sem precisar checar `Tombstone` manualmente.
]]
local function buildSortedItems(storeId: string, ascending: boolean, minValue: number?, maxValue: number?): { unknown }
	local allKeys = store:ListKeys(storeId)

	local matched: { SortedEntry } = {}
	for _, entry in allKeys do
		local value = store:Get(storeId, entry.Key)
		if value == nil then
			-- Tombstoned (removida) OU (defensivamente) já não existe mais -- nunca aparece na
			-- ordenação. Ver cabeçalho, "REMOÇÃO PERMANENTE".
			continue
		end

		if type(value) ~= "number" then
			-- Defesa: só alcançável se um valor não-numérico entrou no store por um caminho que não
			-- seja SetAsync/UpdateAsync/IncrementAsync (blindados em ./GlobalDataStore.luau contra
			-- valor não-inteiro para OrderedDataStore). NÃO CONFIRMADO por fonte primária o que o
			-- Roblox real faria aqui -- pular a chave problemática (falha por omissão) é o lado
			-- seguro em vez de derrubar a consulta inteira (falha por comissão, Decisão 3 do
			-- desenho do arquiteto).
			continue
		end

		local numberValue = value :: number
		if minValue ~= nil and numberValue < minValue then
			continue
		end
		if maxValue ~= nil and numberValue > maxValue then
			continue
		end

		table.insert(matched, { key = entry.Key, value = numberValue })
	end

	table.sort(matched, function(a: SortedEntry, b: SortedEntry): boolean
		if a.value ~= b.value then
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end
		-- Desempate DETERMINÍSTICO -- ver cabeçalho, "DESEMPATE DE ORDENAÇÃO".
		return a.key < b.key
	end)

	local items: { unknown } = table.create(#matched)
	for index, entry in matched do
		-- Tabela PLANA, NUNCA uma Instance -- ver cabeçalho, "GetSortedAsync". Cópia fresca (não a
		-- entrada de `matched`) para que nenhum script alcance/mute o array interno.
		items[index] = { key = entry.key, value = entry.value }
	end
	return items
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `./DataStore.luau`/`./Pages.luau`.
local Methods: { [string]: unknown } = {
	--[[
		Doc oficial: `OrderedDataStore:GetSortedAsync(ascending, pagesize, minValue, maxValue):
		DataStorePages` -- Yields. Validação de argumento ANTES do Yield -- mesma disciplina
		síncrona de `./DataStore.luau`/`./GlobalDataStore.luau` (erro de argumento não deveria
		depender de round-trip). `pagesize`/`minValue`/`maxValue` aceitam `nil` (omitidos) mesmo o
		dump não os marcando opcionais -- um script comum (`.server.lua`) não é `--!strict`, então
		nada impede uma chamada como `store:GetSortedAsync(true, nil, nil, nil)` na prática.
	]]
	GetSortedAsync = function(self: Runtime.Instance, ascending: unknown, pagesize: unknown, minValue: unknown, maxValue: unknown): Runtime.Instance
		if type(ascending) ~= "boolean" then
			error(`invalid argument #1 to 'GetSortedAsync' (boolean expected, got {type(ascending)})`, 2)
		end
		if pagesize ~= nil and type(pagesize) ~= "number" then
			error(`invalid argument #2 to 'GetSortedAsync' (number expected, got {type(pagesize)})`, 2)
		end
		if minValue ~= nil and type(minValue) ~= "number" then
			error(`invalid argument #3 to 'GetSortedAsync' (number expected, got {type(minValue)})`, 2)
		end
		if maxValue ~= nil and type(maxValue) ~= "number" then
			error(`invalid argument #4 to 'GetSortedAsync' (number expected, got {type(maxValue)})`, 2)
		end

		AsyncCall.Yield("OrderedDataStore:GetSortedAsync")

		local resolvedAscending = ascending :: boolean
		local resolvedPageSize = if type(pagesize) == "number" and (pagesize :: number) > 0
			then pagesize :: number
			else DEFAULT_PAGE_SIZE

		local items = buildSortedItems(storeIdOf(self), resolvedAscending, minValue :: number?, maxValue :: number?)
		-- "DataStorePages" -- Schema vazio, SEM Cursor (`generated/classes/DataStorePages.luau`,
		-- confirmado lendo o arquivo gerado) -- mesmo `hasCursorProperty = false` que
		-- `./DataStore.luau` usa para "DataStoreVersionPages" (a outra subclasse de `Pages` sem
		-- Cursor).
		return PagesBehavior.New("DataStorePages", items, resolvedPageSize, false, nil)
	end,
}

local OrderedDataStoreBehavior = {
	Methods = Methods,
}

return OrderedDataStoreBehavior
