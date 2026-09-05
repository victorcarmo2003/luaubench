--!strict

--[[
	`Enum`/`Enums`/`EnumItem` (task-valuetypes-003). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.2 ("SÃO TRÊS TIPOS, não um").
	Assinaturas confirmadas por pesquisa em
	.claude/agents-memory/pesquisa-datatypes-color-udim-enum-2026-09-05.md, seção D ("Enum --
	estrutura e semântica").

	## Três datatypes distintos, confirmados pela pesquisa (seção D.2, tabela de membros)

	| Valor Luau           | `typeof()` | Superfície confirmada                                     |
	|-----------------------|------------|------------------------------------------------------------|
	| a global `Enum`       | `"Enums"`  | `:GetEnums(): {Enum}`                                       |
	| `Enum.KeyCode`         | `"Enum"`   | `:GetEnumItems(): {EnumItem}`, `:FromName(name): EnumItem?`, `:FromValue(value): EnumItem?` |
	| `Enum.KeyCode.Space`   | `"EnumItem"` | `.Name: string`, `.Value: number`, `.EnumType: Enum`; `tostring` = `"Enum.<Enum>.<Item>"` |

	Confirmado que o datatype `Enum` (o objeto de UM enum, ex. `Enum.KeyCode`) NÃO tem propriedades
	`.Name`/`.Value` documentadas -- só `EnumItem` tem. Isso importa de verdade: o dump real tem
	itens de enum cujo `Name` é literalmente `"Name"` ou `"Value"`
	(`Enum.SortOrder.Name`/`Enum.LexemeType.Name`/`Enum.CompletionItemKind.Value`, confirmado por
	inspeção direta em `tools/generate-enums.luau`) -- por isso o objeto "Enum" abaixo NÃO reserva
	essas chaves como propriedade especial, só faz lookup de item por nome. `Enum.SortOrder.Name`
	resolve pro EnumItem "Name" de SortOrder, exatamente como o Roblox real resolveria (ausência de
	`.Name` no datatype "Enum" não é omissão desta implementação -- é o que a pesquisa confirma).

	## Construção PREGUIÇOSA e memoizada POR ENUM (não por item)

	Tocar `Enum.KeyCode` materializa TODOS os itens de KeyCode (e só de KeyCode) na primeira vez --
	nunca os outros 628 enums. A unidade de laziness é o ENUM inteiro, não o item individual: assim
	que `Enum.KeyCode` é acessado pela primeira vez, o objeto "Enum" resultante já vem com todos os
	seus `EnumItem` construídos e cacheados (`enumObjectCache`, abaixo) -- acessos seguintes a
	`Enum.KeyCode` (e a qualquer `Enum.KeyCode.<Item>`) reusam os MESMOS userdata, sem reconstrução.
	Custo total (todos os 629 enums, 3611 itens) medido em `Enum.spec.luau` -- só é pago de verdade
	se um script tocar todo enum que existe (ex.: `Enum:GetEnums()`).

	## Itens INTERNADOS (identidade preservada)

	P7 (seção 9 do desenho) não confirmou se o Roblox real garante `rawequal` entre dois acessos ao
	mesmo `EnumItem`, só que datatypes de valor clássicos comparam por VALOR. Internar (mesma
	referência sempre, via `enumObjectCache`/o campo `ItemsByName` construído uma única vez por
	enum) satisfaz as duas hipóteses ao mesmo tempo: identidade E valor batem, sempre. É também o
	que permite usar `EnumItem` como chave de tabela de forma consistente entre dois `require`s
	diferentes deste módulo (o padrão mais comum do ecossistema Roblox real, citado na pesquisa).

	## DIVERGÊNCIA DECLARADA -- mensagens de erro de membro inválido (P10, não confirmado 100%)

	A pesquisa (seção D.2, "Erro ao acessar enum/item inexistente") reconstruiu, a partir de
	relatos de devforum (não doc oficial -- confiança média-alta, não prova formal), dois formatos
	DIFERENTES do formato genérico `"{key} is not a valid member of {TypeName}"` que
	`Userdata.luau:sharedIndex` produziria sozinho:
	  - Enum inexistente no global: `"RigType is not a valid member of Enum"` -- note que é
	    `"Enum"` (o nome da variável global), NÃO `"Enums"` (o `TypeName`/`typeof()` real, que tem
	    que continuar sendo `"Enums"` para o `typeof(Enum) == "Enums"` confirmado bater).
	  - Item inexistente dentro de um enum válido: `"MouseButton2 is not a valid member of
	    "Enum.KeyCode""` -- com ASPAS ao redor de `Enum.KeyCode` e o NOME DO ENUM embutido, que o
	    formato genérico não tem como produzir (ele só conhece o `TypeName` fixo "Enum", não o nome
	    dinâmico do enum específico).
	Por isso `GetProperty` de "Enums" e de "Enum" (abaixo) ERRAM DIRETAMENTE com a mensagem
	reconstruída em vez de devolver `found = false` e deixar `Userdata.luau` formatar a mensagem
	genérica -- divergência deliberada do contrato padrão do `Descriptor`
	("é a FÁBRICA, não o tipo individual, que formata o erro", seção 3.1 do desenho), justificada
	aqui porque o formato genérico produziria texto CONFIRMADAMENTE diferente do Roblox real nestes
	dois casos específicos. Nível de erro `3` (não o `2` que `Userdata.luau` usa nos seus próprios
	erros) porque aqui o `error()` roda DENTRO de `GetProperty`, que é chamado por `sharedIndex`, que
	é chamado pelo despacho do metamétodo `__index` da VM -- um nível mais fundo. Verificado
	empiricamente nesta tarefa com um script descartável de scratchpad reproduzindo a mesma cadeia
	de chamadas (proxy real via `newproxy(true)`, `__index` real, `error(msg, 3)` apontando
	corretamente pra linha do script de teste, não pra linha interna).

	Depende de: `../Userdata.luau`, `../generated/EnumData.luau`. Usado por: `init.luau` (task
	futura, task-valuetypes-007) e por qualquer tipo da leva 2 que precise de um `EnumItem` como
	campo (`TweenInfo.EasingStyle`, `Font.Weight`, etc.).
]]

local Userdata = require("../Userdata")
local EnumData = require("../generated/EnumData")

-- ================================================================================================
-- Tipos NOMINAIS OPACOS exportados -- mesma técnica prescrita pela seção 3.1 do desenho ("Nota de
-- tipagem") e já usada em `Userdata.spec.luau` (`SpecPoint`/`SpecColor`): o valor em runtime é
-- userdata (o Luau não deixa declarar campo em userdata de verdade), então estes tipos são só a
-- "vitrine" estática usada em ASSINATURA entre módulos -- quem checa de verdade é `__index` em
-- runtime (divergência D4 do desenho: sem checagem em tempo de análise, só em runtime).
--
-- `EnumItem` e `Enum` são mutuamente recursivos (`EnumItem.EnumType: Enum`, `Enum.GetEnumItems():
-- {EnumItem}`) -- Luau resolve isso normalmente entre `type`/`export type` do mesmo arquivo
-- (confirmado por `luau-lsp analyze` nesta tarefa), sem exigir nenhum truque de ordem.
-- ================================================================================================

export type EnumItem = typeof(setmetatable(
	{} :: {
		Name: string,
		Value: number,
		EnumType: Enum,
	},
	{} :: { __tostring: (EnumItem) -> string }
))

export type Enum = typeof(setmetatable(
	{} :: {
		GetEnumItems: (self: Enum) -> { EnumItem },
		FromName: (self: Enum, name: string) -> EnumItem?,
		FromValue: (self: Enum, value: number) -> EnumItem?,
	},
	{} :: { __tostring: (Enum) -> string }
))

export type Enums = typeof(setmetatable(
	{} :: {
		GetEnums: (self: Enums) -> { Enum },
	},
	{} :: {}
))

-- ================================================================================================
-- Índice por nome de enum, construído UMA vez no load a partir de `EnumData` (dados puros
-- gerados) -- O(629), desprezível (não é a materialização preguiçosa dos ITENS, só o índice pra
-- saber se um nome de enum EXISTE e onde estão os dados brutos dele).
-- ================================================================================================

local enumDefinitionByName: { [string]: EnumData.EnumDefinition } = {}
for _, definition in EnumData do
	enumDefinitionByName[definition.Name] = definition
end

-- Enum "Enum" (por-enum, ex. KeyCode) já materializado, indexado por nome -- a memoização que
-- garante (a) laziness por enum e (b) identidade (`rawequal`) entre dois acessos ao mesmo
-- `Enum.<Nome>`. `__mode` NÃO é usado aqui (ao contrário da side-table de `Userdata.luau`): ao
-- contrário de um value type comum, o conjunto de enums existentes é fixo e pequeno (629) e
-- semanticamente GLOBAL/eterno -- o mesmo padrão de `registeredTypeNames` em `Userdata.luau`
-- (conjunto fixo por processo, sem motivo pra coletar).
local enumObjectCache: { [string]: unknown } = {}

-- Forward declarations -- mesmo padrão de `Userdata.spec.luau` (`SpecPointFactory: Userdata.
-- Factory` declarado antes de `Userdata.Define` rodar): `getOrBuildEnum`/`buildEnumItems` abaixo
-- fecham sobre estas variáveis como upvalue, mas só são CHAMADAS depois que o módulo inteiro já
-- carregou (nenhum enum é tocado durante o load -- ver cabeçalho, "Construção preguiçosa"), então
-- as atribuições reais (mais abaixo) já aconteceram antes de qualquer chamada de verdade.
local defineEnum: Userdata.Factory
local defineEnumItem: Userdata.Factory

-- Constrói TODOS os `EnumItem` de um enum (zipando `ItemNames[i]`/`ItemValues[i]` -- ver
-- `tools/generate-enums.luau` pro motivo das listas paralelas) e devolve as três estruturas de
-- lookup que o objeto "Enum" guarda em `Fields` (posições 2/3/4, ver `getOrBuildEnum`).
local function buildEnumItems(
	enumProxy: unknown,
	definition: EnumData.EnumDefinition
): ({ [string]: unknown }, { unknown }, { [number]: unknown })
	local itemsByName: { [string]: unknown } = {}
	local itemsList: { unknown } = table.create(#definition.ItemNames)
	local itemsByValue: { [number]: unknown } = {}

	for index, itemName in definition.ItemNames do
		local itemValue = definition.ItemValues[index]
		-- Fields de EnumItem: posição 1 = Name, 2 = Value, 3 = EnumType (o proxy "Enum" pai --
		-- já existe neste ponto, ver `getOrBuildEnum`: constrói o proxy "Enum" ANTES de construir
		-- os itens, exatamente pra poder passar essa referência aqui).
		local itemProxy = defineEnumItem({ itemName, itemValue, enumProxy })
		itemsByName[itemName] = itemProxy
		itemsList[index] = itemProxy
		itemsByValue[itemValue] = itemProxy
	end

	return itemsByName, itemsList, itemsByValue
end

-- Materializa (ou devolve do cache) o objeto "Enum" de `name`. Único ponto do módulo que constrói
-- um enum -- chamado por `Enums.GetProperty` (`Enum.KeyCode`) e por `Enums:GetEnums()` (força
-- todos os 629).
local function getOrBuildEnum(name: string): unknown
	local cached = enumObjectCache[name]
	if cached ~= nil then
		return cached
	end

	local definition = enumDefinitionByName[name]
	if definition == nil then
		-- Defesa interna -- todo CHAMADOR desta função já validou que `name` existe em
		-- `enumDefinitionByName` antes de chamar (ver `Enums.GetProperty`/`GetEnums`, abaixo).
		-- Nunca deveria disparar; se disparar é bug de programação neste módulo, não erro de
		-- script de usuário.
		error(`getOrBuildEnum: enum '{name}' não existe em EnumData (bug interno de valuetypes)`, 2)
	end

	-- Construção em DUAS fases -- necessária porque cada `EnumItem` guarda uma referência ao
	-- proxy "Enum" PAI (`.EnumType`), que só existe DEPOIS de `defineEnum` já ter sido chamado.
	-- Fase 1: cria o proxy "Enum" com Fields ainda incompletos (só o Name, posição 1). Fase 2:
	-- MUTA a MESMA tabela `enumFields` (a mesma referência que `Userdata.luau` já guardou
	-- internamente como `entry.Fields` para este proxy) para preencher os itens de verdade.
	-- Técnica de construção interna, NUNCA visível de fora deste módulo: o proxy só é devolvido
	-- ao chamador na fase 3, já totalmente populado, e `__newindex` continua bloqueando qualquer
	-- tentativa de mutação vinda de um script (a mutação aqui é feita por ESTE módulo sobre sua
	-- própria tabela Lua interna, nunca através do proxy/`__newindex`).
	local enumFields: Userdata.Fields = { name }
	local enumProxy = defineEnum(enumFields)

	local itemsByName, itemsList, itemsByValue = buildEnumItems(enumProxy, definition)
	enumFields[2] = itemsByName
	enumFields[3] = itemsList
	enumFields[4] = itemsByValue

	enumObjectCache[name] = enumProxy
	return enumProxy
end

-- ================================================================================================
-- "Enums" -- o objeto raiz, exposto como a global Luau `Enum` (confusão de nomenclatura do
-- próprio Roblox: a global se chama `Enum`, o DATATYPE dela se chama `Enums`, plural --
-- `typeof(Enum) == "Enums"`, confirmado na pesquisa).
-- ================================================================================================

local EnumsMethods: { [string]: unknown } = {
	GetEnums = function(self: unknown): { unknown }
		Userdata.Unwrap(self, "Enums")
		-- Força materializar TODOS os 629 enums (e os 3611 itens) -- custo esperado de uma
		-- chamada explícita e rara, não um custo ambiente pago por scripts que só tocam alguns
		-- enums (ver cabeçalho, "Construção preguiçosa").
		local result: { unknown } = table.create(#EnumData)
		for index, definition in EnumData do
			result[index] = getOrBuildEnum(definition.Name)
		end
		return result
	end,
}
-- `table.freeze({...})` diretamente no inicializador confunde o inferenciador de tipo do
-- luau-lsp 1.69.0 (achado desta tarefa: produz um tipo exato com campos de FUNÇÃO concretos,
-- incompatível na comparação com a anotação `{ [string]: unknown }` -- mesmo com todo campo de
-- função sendo um `unknown` válido). Mesmo padrão já usado em `Userdata.spec.luau`
-- (`specPointMethods`): declarar com a anotação larga primeiro, congelar como statement
-- SEPARADO logo em seguida.
table.freeze(EnumsMethods)

local defineEnums = Userdata.Define({
	TypeName = "Enums",
	Methods = EnumsMethods,
	GetProperty = function(_fields: Userdata.Fields, key: string): (unknown, boolean)
		local definition = enumDefinitionByName[key]
		if definition == nil then
			-- Ver cabeçalho, "Divergência declarada -- mensagens de erro": formato reconstruído
			-- da pesquisa (P10, não confirmado 100%), citando o NOME que faltou. Level 3: ver
			-- cabeçalho.
			error(`{key} is not a valid member of Enum`, 3)
		end
		return getOrBuildEnum(key), true
	end,
	-- `tostring(Enum)` (o global sozinho, sem indexar nenhum enum) -- NÃO confirmado por nenhuma
	-- fonte da pesquisa (não é P2/P3/P10, é um caso novo que a pesquisa nem cobriu). Aproximação
	-- de boa-fé de baixíssimo risco: script real praticamente nunca faz `tostring(Enum)` sozinho
	-- (sempre indexa um enum específico primeiro) -- mas documentado aqui como não confirmado,
	-- nunca silencioso (regra 00).
	Format = function(_fields: Userdata.Fields): string
		return "Enum"
	end,
	-- Singleton verdadeiro -- só existe UM proxy "Enums" no processo inteiro (`EnumsRoot`,
	-- abaixo), construído uma única vez neste módulo. Não há como dois proxies "Enums"
	-- DIFERENTES existirem pra comparar, então `Equals` sempre `true` é correto por construção,
	-- não uma aproximação.
	Equals = function(_a: Userdata.Fields, _b: Userdata.Fields): boolean
		return true
	end,
})

local EnumsRoot = defineEnums({})

-- ================================================================================================
-- "Enum" -- um enum individual, ex. `Enum.KeyCode`. Fields: 1 = Name (string), 2 = ItemsByName
-- ({[string]: EnumItem}), 3 = ItemsList (ordenada, {EnumItem}), 4 = ItemsByValue ({[number]:
-- EnumItem}) -- as três estruturas de lookup são preenchidas em `getOrBuildEnum`, acima, antes de
-- o proxy ser devolvido a qualquer chamador (nunca observável parcialmente construído).
--
-- NÃO reserva `.Name`/`.Value` como propriedade -- ver cabeçalho ("Três datatypes distintos") pro
-- porquê (só `EnumItem` tem essas propriedades no Roblox real, e existem itens de enum
-- literalmente chamados "Name"/"Value" no dump).
-- ================================================================================================

local EnumMethods: { [string]: unknown } = {
	GetEnumItems = function(self: unknown): { unknown }
		local fields = Userdata.Unwrap(self, "Enum")
		local itemsList = fields[3] :: { unknown }
		-- Cópia NOVA a cada chamada -- mesma disciplina de `Catalog.All()`: nunca expor a
		-- referência interna (um script poderia `table.insert`/`table.remove` nela e corromper o
		-- cache de todo mundo que chamar `GetEnumItems` depois).
		local copy: { unknown } = table.create(#itemsList)
		for index, item in itemsList do
			copy[index] = item
		end
		return copy
	end,
	FromName = function(self: unknown, name: string): unknown
		local fields = Userdata.Unwrap(self, "Enum")
		local itemsByName = fields[2] :: { [string]: unknown }
		-- `?` no retorno confirmado pela pesquisa (`FromName(name: string): EnumItem?`) -- ao
		-- contrário de indexar `Enum.KeyCode.<Nome>` diretamente (que ERRA se `<Nome>` não
		-- existir, ver `GetProperty` abaixo), `FromName`/`FromValue` são LOOKUPS explícitos que
		-- devolvem `nil` sem erro quando não encontram -- mesma convenção do resto da API Roblox
		-- pra métodos "From.../Find...".
		return itemsByName[name]
	end,
	FromValue = function(self: unknown, value: number): unknown
		local fields = Userdata.Unwrap(self, "Enum")
		local itemsByValue = fields[4] :: { [number]: unknown }
		return itemsByValue[value]
	end,
}
table.freeze(EnumMethods)

defineEnum = Userdata.Define({
	TypeName = "Enum",
	Methods = EnumMethods,
	GetProperty = function(fields: Userdata.Fields, key: string): (unknown, boolean)
		local itemsByName = fields[2] :: { [string]: unknown }
		local item = itemsByName[key]
		if item ~= nil then
			return item, true
		end
		-- Ver cabeçalho, "Divergência declarada": formato reconstruído da pesquisa (P10), com
		-- aspas ao redor de "Enum.<NomeDoEnum>" e o nome do enum embutido -- o genérico de
		-- `Userdata.luau` não teria como produzir isso (só conhece o TypeName fixo "Enum", não o
		-- nome dinâmico do enum). Level 3: ver cabeçalho.
		error(`{key} is not a valid member of "Enum.{fields[1] :: string}"`, 3)
	end,
	-- `tostring(Enum.KeyCode)` -- CONFIRMADO pela pesquisa: `print(Enum.PartType.Cylinder.
	-- EnumType) --> PartType`, ou seja, o objeto "Enum" sozinho imprime só o próprio nome, sem
	-- prefixo "Enum.".
	Format = function(fields: Userdata.Fields): string
		return fields[1] :: string
	end,
	-- Dado o cache por nome (`enumObjectCache`), dois proxies "Enum" só existem se forem enums
	-- DIFERENTES -- comparar pelo Name é value-equality correta (e nunca dispara de verdade pro
	-- MESMO enum, que é sempre o mesmo proxy).
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1]
	end,
})

-- ================================================================================================
-- "EnumItem" -- ex. `Enum.KeyCode.Space`. Fields: 1 = Name (string), 2 = Value (number), 3 =
-- EnumType (o proxy "Enum" pai).
-- ================================================================================================

local EnumItemMethods: { [string]: unknown } = {}
table.freeze(EnumItemMethods)

defineEnumItem = Userdata.Define({
	TypeName = "EnumItem",
	Methods = EnumItemMethods,
	GetProperty = function(fields: Userdata.Fields, key: string): (unknown, boolean)
		if key == "Name" then
			return fields[1], true
		elseif key == "Value" then
			return fields[2], true
		elseif key == "EnumType" then
			return fields[3], true
		end
		-- Propriedade inválida de um EnumItem -- não há pesquisa específica pra este caso (P10 só
		-- cobriu enum/item inexistente, não "propriedade inválida de um item que EXISTE"). Deixa o
		-- genérico de `Userdata.luau` formatar (`"{key} is not a valid member of EnumItem"`) --
		-- não há achado que contradiga esse formato aqui.
		return nil, false
	end,
	-- CONFIRMADO pela pesquisa (`content/en-us/luau/enums.md`, exemplo literal de `print`):
	-- formato exato `"Enum.<NomeDoEnum>.<NomeDoItem>"`.
	Format = function(fields: Userdata.Fields): string
		local enumFields = Userdata.Unwrap(fields[3], "Enum")
		return `Enum.{enumFields[1] :: string}.{fields[1] :: string}`
	end,
	-- Comparação por valor: mesmo Name, mesmo Value, mesmo EnumType (o `==` em `a[3] == b[3]`
	-- dispara nosso próprio `__eq` de "Enum" se forem proxies DIFERENTES, ou curto-circuita `true`
	-- sem metamétodo nenhum se forem o MESMO proxy -- semântica nativa do Luau pra `==` entre duas
	-- referências idênticas). Praticamente nunca é exercitado de verdade dado o internamento (ver
	-- cabeçalho): dois `EnumItem` "iguais" são sempre o MESMO proxy, e `Userdata.luau:sharedEq`
	-- nem chega a chamar `Equals` nesse caso (curto-circuita antes, na comparação nativa do
	-- Luau) -- mas `Equals` continua tendo que ser uma comparação de valor genuína, não só
	-- `return true`, pro caso hipotético de dois `EnumItem` distintos (bug de internamento)
	-- precisarem ser comparados de verdade.
	Equals = function(a: Userdata.Fields, b: Userdata.Fields): boolean
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end,
})

-- Superfície pública do módulo: o PRÓPRIO valor `Enum` global (ver arquiteto-valuetypes-2026-09-05
-- .md, seção 3.1 "init.luau": `Enum = EnumRoot` -- este `require` é o `EnumRoot` que uma task
-- futura, task-valuetypes-007, vai atribuir direto em `ValueTypes.Enum`). Os tipos exportados
-- acima (`Enums`/`Enum`/`EnumItem`) continuam acessíveis via `require(...).TipoExportado` em
-- QUALQUER módulo que fizer `require` deste arquivo, independente do valor de RUNTIME devolvido
-- (mesmo padrão já usado no território `services`, ex. `Runtime.Instance` como tipo com `Runtime`
-- ligado a um `require` cujo valor de runtime não é literalmente esse tipo).
return EnumsRoot
