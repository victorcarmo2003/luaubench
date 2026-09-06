--!strict

--[[
	Behavior de `DataStoreService` -- task-services-018. LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.4"/"L2.1.6"/"L2.1.7",
	ANTES de mexer aqui.

	MEMOIZAÇÃO (L2.1.3): doc oficial, "subsequent calls return the same object" -- duas chamadas
	com o MESMO `(name, scope)` devolvem a MESMA `Instance`. `GetDataStore`/`GetOrderedDataStore`/
	`GetGlobalDataStore` compartilham UM único cache, nomeado por `Kind` ("DataStore"/
	"OrderedDataStore"/"GlobalDataStore") -- não um mapa por método -- exatamente como o texto da
	tarefa pede ("GetOrderedDataStore memoizado no MESMO mapa, não um separado"). `Kind` distingue
	`GetDataStore("X")` de `GetOrderedDataStore("X")`: são DUAS instâncias diferentes mesmo com o
	MESMO `(name, scope)` (uma é `DataStore`, a outra `OrderedDataStore` -- ClassName diferente),
	e cada uma memoiza indepententemente dentro do seu próprio `Kind`. `GetGlobalDataStore()` usa
	seu PRÓPRIO `Kind` ("GlobalDataStore", com `name`/`scope` fixos em `""`) -- DECISÃO (não
	confirmada por pesquisa, ver "AMBIGUIDADE" abaixo): isto garante que `GetGlobalDataStore()`
	NUNCA colide com um eventual `GetDataStore("", nil)` do script, sem precisar adivinhar se o
	Roblox real trata os dois como o MESMO armazenamento subjacente (não há fonte confirmando isso
	nesta leva) -- mais seguro tratá-los como namespaces distintos do que arriscar uma colisão
	silenciosa não pedida por nenhuma fonte.

	AMBIGUIDADE REGISTRADA (L2.1.7, citação literal do desenho do arquiteto): "o dump declara
	`GetGlobalDataStore() -> DataStore` [dump 09-05d], embora o nome sugira `GlobalDataStore`.
	Decisão: seguir o dump -- as duas fábricas devolvem `ClassName == 'DataStore'`." Por isso
	`GetGlobalDataStore` abaixo cria uma Instance de `ClassName = "DataStore"`, idêntico a
	`GetDataStore` -- só o `Kind` do cache e os `name`/`scope` fixos (`""`/`""`) diferem.

	REQUEST BUDGET (L2.1.4): `GetRequestBudgetForRequestType` devolve uma CONSTANTE GRANDE E FIXA
	(NUNCA `math.huge`, NUNCA `0`) -- nada throttla. Três razões, nesta ordem (citação do desenho):
	(1) a fórmula real soma um termo por jogador e o LuauBench tem ZERO jogadores por decisão já
	tomada (`Players.GetPlayers() == {}`) -- simular a fórmula real daria o orçamento MÍNIMO e
	quebraria código que roda folgado em produção (falha por comissão); (2) os números exatos da
	fórmula vieram NÃO CONFIRMADOS da pesquisa; (3) `ProfileStore` (o caso de uso central do
	projeto) NUNCA chama este método. `SetRateLimitForRequestType` é aceito e IGNORADO -- mesma
	razão. `requestType` (um `Enum.DataStoreRequestType` no Roblox real) é `unknown` e nunca
	inspecionado -- `Enum` simulado não existe no território de `services` (leva de Value Types,
	fora daqui) e o valor do orçamento é o MESMO para qualquer tipo de requisição, de propósito.

	NÃO implementado (L2.1.4): `ListDataStoresAsync` -- fica com o stub `[LuauBench]` do
	`ClassBuilder` (nenhum é usado por `ProfileStore`).

	Doc oficial confirma (ver pesquisa-datastore-2026-09-05.md, seção B.5): `GetDataStore`/
	`GetGlobalDataStore`/`GetOrderedDataStore` são SÍNCRONOS (sem tag `Yields` no dump) -- só
	CONSTROEM o objeto memoizado, nunca chamam `AsyncCall.Yield`. Quem yielda é o `*Async` de
	`GlobalDataStore` (`./GlobalDataStore.luau`), na PRIMEIRA chamada de verdade sobre a instância
	devolvida aqui.

	DEFAULT SCOPE: doc oficial de `GetDataStore`/`GetOrderedDataStore` -- quando `scope` é omitido
	(`nil`), o Roblox real usa o scope `"global"` (não uma string vazia) -- decisão adotada aqui
	também, e validada com o MESMO limite de 50 caracteres que um scope explícito receberia (embora
	`"global"` nunca estoure esse limite, a checagem roda incondicionalmente, sem caso especial).
]]

local Runtime = require("../../runtime")
local Value = require("../datastore/Value")
local GlobalDataStoreBehavior = require("./GlobalDataStore")

-- Ver cabeçalho, "REQUEST BUDGET" -- nunca math.huge, nunca 0. 1 bilhão é grande o bastante para
-- que qualquer `while budget < N do task.wait() end` de um script real prossiga de imediato, e
-- pequeno o bastante para não overflow-ar aritmética simples feita em cima do valor.
local REQUEST_BUDGET = 1e9

-- Ver cabeçalho, "DEFAULT SCOPE".
local DEFAULT_SCOPE = "global"

-- Ver cabeçalho, "MEMOIZAÇÃO" -- um `Kind` por família de fábrica, cada um com seu próprio mapa
-- `name -> scope -> Instance`. `GlobalDataStore` usa `name = ""`/`scope = ""` fixos (constantes,
-- nunca alcançáveis por um script via `GetDataStore`/`GetOrderedDataStore`, que sempre operam nos
-- outros dois `Kind`s).
type CacheKind = "DataStore" | "OrderedDataStore" | "GlobalDataStore"

local cache: { [CacheKind]: { [string]: { [string]: Runtime.Instance } } } = {
	DataStore = {},
	OrderedDataStore = {},
	GlobalDataStore = {},
}

-- Encoding com PREFIXO DE TAMANHO (`"{len}:{texto}"`) -- bijetivo, sem separador nenhum que um
-- `name`/`scope` malicioso pudesse forjar para colidir dois pares `(kind, name, scope)` distintos
-- no mesmo `storeId` (diferente de concatenar com um único caractere separador, que uma chave
-- contendo esse mesmo caractere poderia, em teoria, imitar).
local function encodeComponent(text: string): string
	return `{string.len(text)}:{text}`
end

local function computeStoreId(kind: CacheKind, name: string, scope: string): string
	return `{encodeComponent(kind)}{encodeComponent(name)}{encodeComponent(scope)}`
end

-- Ponto ÚNICO de memoização + criação -- os 3 métodos abaixo só decidem `kind`/`className` e
-- validam nome/scope; toda a disciplina de cache mora aqui.
local function getOrCreate(kind: CacheKind, name: string, scope: string, className: string): Runtime.Instance
	local byName = cache[kind][name]
	if byName == nil then
		byName = {}
		cache[kind][name] = byName
	end

	local existing = byName[scope]
	if existing ~= nil then
		return existing
	end

	local created = Runtime.ClassRegistry.NewEngineInstance(className)
	GlobalDataStoreBehavior.StoreIdState.Set(created, computeStoreId(kind, name, scope))
	byName[scope] = created
	return created
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/`Lighting.luau`.
local Methods: { [string]: unknown } = {
	-- Doc oficial: `DataStoreService:GetDataStore(name, scope?, options?): DataStore` -- síncrono
	-- (sem `Yields`, ver cabeçalho). `options` (`DataStoreOptions`) é aceito e IGNORADO nesta
	-- tarefa -- `AllScopes` só afeta operações de listagem (`ListKeysAsync`), fora do território
	-- desta task (sub-leva B).
	GetDataStore = function(_self: Runtime.Instance, name: string, scope: string?, _options: unknown?): Runtime.Instance
		Value.AssertNameLength(name, "name")
		local resolvedScope = if scope ~= nil then scope else DEFAULT_SCOPE
		Value.AssertNameLength(resolvedScope, "scope")

		return getOrCreate("DataStore", name, resolvedScope, "DataStore")
	end,

	-- Doc oficial: `DataStoreService:GetGlobalDataStore(): DataStore` (ver cabeçalho,
	-- "AMBIGUIDADE REGISTRADA" -- ClassName == "DataStore", seguindo o dump ao pé da letra).
	GetGlobalDataStore = function(_self: Runtime.Instance): Runtime.Instance
		return getOrCreate("GlobalDataStore", "", "", "DataStore")
	end,

	-- Doc oficial: `DataStoreService:GetOrderedDataStore(name, scope?): OrderedDataStore` --
	-- síncrono, mesma disciplina de `GetDataStore` acima (sem `options` -- o dump não declara esse
	-- 3º parâmetro para `GetOrderedDataStore`, ver `generated/classes/DataStoreService.luau`).
	GetOrderedDataStore = function(_self: Runtime.Instance, name: string, scope: string?): Runtime.Instance
		Value.AssertNameLength(name, "name")
		local resolvedScope = if scope ~= nil then scope else DEFAULT_SCOPE
		Value.AssertNameLength(resolvedScope, "scope")

		return getOrCreate("OrderedDataStore", name, resolvedScope, "OrderedDataStore")
	end,

	-- Ver cabeçalho, "REQUEST BUDGET" -- constante fixa, `requestType` nunca inspecionado.
	GetRequestBudgetForRequestType = function(_self: Runtime.Instance, _requestType: unknown): number
		return REQUEST_BUDGET
	end,

	-- Ver cabeçalho, "REQUEST BUDGET" -- aceito e ignorado, nunca lançado.
	SetRateLimitForRequestType = function(_self: Runtime.Instance, _requestType: unknown, _baseLimit: number, _perPlayerLimit: number): ()
		-- no-op deliberado
	end,
}

local DataStoreServiceBehavior = {
	Methods = Methods,
}

return DataStoreServiceBehavior
