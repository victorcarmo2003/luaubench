--!strict

--[[
	Behavior de `DataStore` -- task-services-019 (sub-leva B). LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6", ANTES de mexer aqui.
	Constrói EM CIMA de `./GlobalDataStore.luau` (task-018, já aprovado -- `DataStore` HERDA de
	`GlobalDataStore` no dump, `generated/classes/DataStore.luau`, `Superclass = "GlobalDataStore"`)
	e de `./Pages.luau` (mesma tarefa -- fábrica genérica de paginação).

	`GetAsync`/`SetAsync`/`UpdateAsync`/`RemoveAsync`/`IncrementAsync` NÃO são reimplementados
	aqui -- continuam resolvidos pela cadeia de classes de `Runtime.ClassRegistry` a partir do
	`Methods` registrado sob `"GlobalDataStore"` (mesmo achatamento que já beneficia
	`OrderedDataStore`, ver o cabeçalho de `./GlobalDataStore.luau`). Este módulo só cobre os TRÊS
	métodos que `DataStore` acrescenta por cima do que já vem herdado.

	STORE COMPARTILHADO: `./GlobalDataStore.luau` agora exporta `.Store`/`.StoreIdOf`/
	`.KeyInfoOrNil` (além do já existente `.StoreIdState`) exatamente para este módulo -- ver o
	comentário atualizado no final daquele arquivo. NUNCA um segundo `Store.new()` aqui -- seria um
	segundo banco de dados, invisível para `GetAsync`/`SetAsync` (quebraria a premissa central do
	acceptance: "SetAsync/UpdateAsync repetidos geram versões distintas recuperáveis por
	GetVersionAsync").

	`GetVersionAtTimeAsync`/`RemoveVersionAsync` NÃO entram aqui -- fora do território desta tarefa
	(`RemoveVersionAsync` é `Deprecated` no dump, regra 03: "implementado só se algum projeto real
	ainda depender dela" -- nenhum sinal disso). Ficam com o stub `[LuauBench]` do `ClassBuilder`,
	mesmo mecanismo de sempre (`ClassBuilder.Build`, passo (b): método declarado em `MethodNames`
	sem `behavior.Methods[nome]` correspondente vira stub automático que erra claro).

	SORT DIRECTION -- instrução EXPLÍCITA da tarefa despachante, registrada aqui como decisão
	fechada: `Enum` simulado (`src/valuetypes/types/Enum.luau`) EXISTE tecnicamente no processo,
	mas NENHUMA ponte foi construída para resolver/validar um `EnumItem` de `Enum.SortDirection`
	vindo de um script especificamente para ESTE parâmetro -- construir essa ponte agora seria
	decisão de arquitetura cruzando pra `valuetypes` (território de outro agente), fora do escopo
	desta task. Por isso:
	- `sortDirection == nil` (omitido): usa o default do dump (`"Ascending"`) -- como
	  ORDENAÇÃO INTERNA do LuauBench (`ORDER = "Ascending"`, comentado abaixo), nunca um `EnumItem`
	  de verdade. DIVERGÊNCIA DECLARADA (regra 00): um script que lê de volta o `sortDirection`
	  passado (o dump não expõe isso em lugar nenhum, então não há como um script observar essa
	  diferença de qualquer forma).
	- `sortDirection ~= nil` (QUALQUER valor não-nil, MESMO um `Enum.SortDirection.Ascending`
	  genuíno que bateria com o default): ERRA com `[LuauBench]` nomeando a lacuna -- nunca aceito
	  em silêncio fingindo que foi processado (a instrução é explícita: não há como comparar um
	  `EnumItem` de `valuetypes.Enum` sem uma ponte que não existe para este parâmetro, então
	  "aceitar só quando bate com Ascending" exigiria essa mesma ponte para inspecionar o valor).

	RESOLVIDO em task-services-019-fix (achado MÉDIO da revisão de task-services-019, ver
	.claude/agents-memory/revisor-services-task-services-019-2026-09-05.md): itens de
	`ListKeysAsync`/`DataStoreKeyPages` agora são instâncias `DataStoreKey` REAIS (`.KeyName:
	unknown` -- tipo gerado como `unknown`, não `string`, porque o `Default` de `KeyName` no dump é
	o sentinela `"__api_dump_class_not_creatable__"`, não representável -- mesma disciplina que já
	vale para `DataStoreKeyInfo.CreatedTime`/`.Version`), construídas via
	`Runtime.ClassRegistry.NewEngineInstance("DataStoreKey")` + `Runtime.Instance.SetPropertyRaw`
	(ver `buildKeyItems`, abaixo) -- MESMA fábrica que `./DataStoreKeyInfo.luau` já usa para
	`DataStoreObjectVersionInfo`/`DataStoreKeyInfo`, nenhum segundo mecanismo de criar Instance.
	`DataStoreKey` EXISTE no `Full-API-Dump.json` fixado (`Superclass = "Instance"`, tag
	`NotCreatable`, único membro `KeyName` com `Capabilities.Read = ["DataStore"]`) mas nunca era
	emitido em `generated/classes/`, porque o retorno de `Pages:GetCurrentPage()`/
	`DataStore:ListKeysAsync` no dump é `{ Category = "Group", Name = "Array" }` genérico, sem
	parametrização de item -- o fecho transitivo do gerador (Decisão 1 do desenho) nunca o
	descobria como dependência (não é bug do gerador -- é uma limitação estrutural do próprio
	formato do dump, que não parametriza tipo de item de Array). `DataStoreKey` foi acrescentado À
	MÃO a `tools/coverage.luau` (comentário lá explica por que essa entrada é diferente das demais)
	e o gerador foi rodado de novo (`lune run tools/generate-services`) -- ver
	`generated/classes/DataStoreKey.luau`.

	Depende de: `../../runtime`, `../AsyncCall` (L2.0.1), `../datastore/Value` (L2.1.3, limites de
	nome), `../datastore/Store` (só o TIPO `Store.VersionInfo` -- a INSTÂNCIA de verdade vem de
	`./GlobalDataStore.luau`, nunca `Store.new()` aqui), `./GlobalDataStore` (Store/StoreIdOf/
	KeyInfoOrNil), `./Pages` (fábrica de paginação).
]]

local Runtime = require("../../runtime")
local AsyncCall = require("../AsyncCall")
local Value = require("../datastore/Value")
local Store = require("../datastore/Store")
local GlobalDataStoreBehavior = require("./GlobalDataStore")
local PagesBehavior = require("./Pages")

local store = GlobalDataStoreBehavior.Store :: Store.Store
local storeIdOf = GlobalDataStoreBehavior.StoreIdOf :: (Runtime.Instance) -> string
local keyInfoOrNil = GlobalDataStoreBehavior.KeyInfoOrNil :: (Store.VersionInfo?) -> Runtime.Instance?

-- Default de página quando `pageSize` é omitido/`0` -- NÃO CONFIRMADO por fonte primária para
-- `ListVersionsAsync`/`ListKeysAsync` especificamente (pesquisa-datastore-2026-09-05.md só
-- confirma esse número, "50", para `GetSortedAsync`, fora do território desta task). Aproximação
-- de boa-fé, mesma ordem de grandeza documentada para o resto da família -- nunca `0`/`math.huge`
-- (uma página "infinita" não seria paginação de verdade e esconderia bug de script que assume
-- múltiplas páginas).
local DEFAULT_PAGE_SIZE = 50

-- Ver cabeçalho, "SORT DIRECTION" -- única ordenação suportada nesta leva.
local ASCENDING = true

-- `DataStore:ListVersionsAsync` -- devolve TODAS as versões de `key` (via `store:ListVersions`,
-- task-services-019, `datastore/Store.luau`) filtradas por `[minDate, maxDate]` (`<= 0` == sem
-- limite naquele lado -- mesma convenção do dump, cujo default de ambos é `0`) e ordenadas
-- conforme `ascending`. Devolve `DataStoreObjectVersionInfo` (via `NewEngineInstance` --
-- `NotCreatable` no dump) para cada item, NUNCA `Store.VersionInfo` cru (que não é uma Instance).
--
-- `DataStoreObjectVersionInfo.CreatedTime` = quando ESTA VERSÃO foi criada
-- (`Store.VersionInfo.UpdatedTime`) -- NÃO confundir com `Store.VersionInfo.CreatedTime` (quando a
-- CHAVE nasceu, constante entre versões) -- ver `generated/classes/DataStoreObjectVersionInfo.luau`
-- (só `CreatedTime`/`IsDeleted`/`Version`) e o cabeçalho de `datastore/Store.luau`.
local function buildVersionItems(storeId: string, key: string, minDate: number, maxDate: number, ascending: boolean): { unknown }
	local allVersions = store:ListVersions(storeId, key)

	local filtered: { Store.VersionInfo } = {}
	for _, versionInfo in allVersions do
		local afterMin = minDate <= 0 or versionInfo.UpdatedTime >= minDate
		local beforeMax = maxDate <= 0 or versionInfo.UpdatedTime <= maxDate
		if afterMin and beforeMax then
			table.insert(filtered, versionInfo)
		end
	end

	-- `Version` (string de largura fixa, `datastore/Store.luau`, "VERSION (string)") ordena
	-- lexicograficamente igual à ordem de escrita -- por isso comparar por `Version` (não por
	-- `UpdatedTime`) já resolve empate determinístico entre duas versões escritas no MESMO
	-- milissegundo.
	table.sort(filtered, function(a: Store.VersionInfo, b: Store.VersionInfo): boolean
		if ascending then
			return a.Version < b.Version
		end
		return a.Version > b.Version
	end)

	local items: { unknown } = table.create(#filtered)
	for index, versionInfo in filtered do
		local objectVersionInfo = Runtime.ClassRegistry.NewEngineInstance("DataStoreObjectVersionInfo")
		Runtime.Instance.SetPropertyRaw(objectVersionInfo, "CreatedTime", versionInfo.UpdatedTime)
		Runtime.Instance.SetPropertyRaw(objectVersionInfo, "IsDeleted", versionInfo.Tombstone)
		Runtime.Instance.SetPropertyRaw(objectVersionInfo, "Version", versionInfo.Version)
		items[index] = objectVersionInfo
	end
	return items
end

-- `DataStore:ListKeysAsync` -- devolve instâncias `DataStoreKey` (ver cabeçalho, "RESOLVIDO em
-- task-services-019-fix") para os NOMES de chave que casam com `prefix` (prefixo LITERAL via
-- `string.sub` -- nunca padrão Lua; o Roblox real não documenta suporte a wildcard aqui),
-- opcionalmente excluindo chaves cuja versão CORRENTE é um tombstone (`RemoveAsync` --
-- `excludeDeleted == true`). Ordem: a mesma (alfabética) que `store:ListKeys` já devolve
-- (`datastore/Store.luau`).
local function buildKeyItems(storeId: string, prefix: string, excludeDeleted: boolean): { unknown }
	local allKeys = store:ListKeys(storeId)

	local items: { unknown } = {}
	for _, entry in allKeys do
		local matchesPrefix = prefix == "" or string.sub(entry.Key, 1, string.len(prefix)) == prefix
		local excluded = excludeDeleted and entry.Current.Tombstone
		if matchesPrefix and not excluded then
			local dataStoreKey = Runtime.ClassRegistry.NewEngineInstance("DataStoreKey")
			Runtime.Instance.SetPropertyRaw(dataStoreKey, "KeyName", entry.Key)
			table.insert(items, dataStoreKey)
		end
	end
	return items
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `DataStore:GetVersionAsync(key, version): Tuple` -- Yields. `(valorNaquelaVersao,
	-- keyInfo)`, ou `(nil, nil)` se `version` nunca existiu para `key` -- via `Store.GetVersion`
	-- (task-017), que devolve a versão MESMO tombstoned (histórico continua legível depois de
	-- `RemoveAsync` -- L2.1.3, acceptance desta task).
	GetVersionAsync = function(self: Runtime.Instance, key: string, version: string): (unknown, Runtime.Instance?)
		Value.AssertNameLength(key, "key")
		AsyncCall.Yield("DataStore:GetVersionAsync")

		local value, versionInfo = store:GetVersion(storeIdOf(self), key, version)
		return value, keyInfoOrNil(versionInfo)
	end,

	--[[
		Doc oficial: `DataStore:ListVersionsAsync(key, sortDirection?, minDate?, maxDate?, pageSize?):
		DataStoreVersionPages` -- Yields. Cada item da página é um `DataStoreObjectVersionInfo` (ver
		`buildVersionItems`, acima). `DataStoreVersionPages` NÃO declara `Cursor` no schema
		(`generated/classes/DataStoreVersionPages.luau`, `Schema = {}`) -- `hasCursorProperty = false`
		abaixo, e o dump nem declara parâmetro de cursor para este método (diferente de
		`ListKeysAsync`).

		`sortDirection`: ver cabeçalho deste arquivo, "SORT DIRECTION" -- omitido usa Ascending
		(default do dump); presente (qualquer valor) ERRA citando a lacuna de ponte Enum.
	]]
	ListVersionsAsync = function(self: Runtime.Instance, key: string, sortDirection: unknown?, minDate: number?, maxDate: number?, pageSize: number?): Runtime.Instance
		Value.AssertNameLength(key, "key")

		if sortDirection ~= nil then
			error(
				"[LuauBench] DataStore:ListVersionsAsync's 'sortDirection' argument is not simulated by LuauBench yet -- Enum.SortDirection has no bridge into services (Enum is simulated in valuetypes, but no resolver was built to read an EnumItem from this parameter); call ListVersionsAsync without a sortDirection argument to use the default (Ascending)",
				2
			)
		end

		AsyncCall.Yield("DataStore:ListVersionsAsync")

		local resolvedMinDate = if minDate ~= nil then minDate else 0
		local resolvedMaxDate = if maxDate ~= nil then maxDate else 0
		local resolvedPageSize = if pageSize ~= nil and pageSize > 0 then pageSize else DEFAULT_PAGE_SIZE

		local items = buildVersionItems(storeIdOf(self), key, resolvedMinDate, resolvedMaxDate, ASCENDING)
		return PagesBehavior.New("DataStoreVersionPages", items, resolvedPageSize, false, nil)
	end,

	--[[
		Doc oficial: `DataStore:ListKeysAsync(prefix?, pageSize?, cursor?, excludeDeleted?):
		DataStoreKeyPages` -- Yields. Ver `buildKeyItems`, acima -- cada item é uma instância
		`DataStoreKey` real (`.KeyName`). `cursor` (STRING opaca devolvida pela `Cursor` de uma
		página anterior DESTA MESMA classe -- ver `./Pages.luau`, "Cursor") resolve o índice de onde
		retomar; vazio/ausente/inválido começa do zero (`Pages.luau`, `decodeStartIndex`).
	]]
	ListKeysAsync = function(self: Runtime.Instance, prefix: string?, pageSize: number?, cursor: string?, excludeDeleted: boolean?): Runtime.Instance
		AsyncCall.Yield("DataStore:ListKeysAsync")

		local resolvedPrefix = if prefix ~= nil then prefix else ""
		local resolvedExcludeDeleted = if excludeDeleted ~= nil then excludeDeleted else false
		local resolvedPageSize = if pageSize ~= nil and pageSize > 0 then pageSize else DEFAULT_PAGE_SIZE

		local items = buildKeyItems(storeIdOf(self), resolvedPrefix, resolvedExcludeDeleted)
		return PagesBehavior.New("DataStoreKeyPages", items, resolvedPageSize, true, cursor)
	end,
}

local DataStoreBehavior = {
	Methods = Methods,
}

return DataStoreBehavior
