--!strict

--[[
	Validação e cópia profunda de VALORES de DataStore -- dado puro, SEM `Runtime.Instance`, SEM
	I/O (fs/net), SEM `require` nenhum. Cobre os 3 limites de tamanho e as categorias de valor não
	serializável que a doc oficial do Roblox documenta para `GlobalDataStore`/`DataStore`/
	`OrderedDataStore` (fonte: .claude/agents-memory/pesquisa-datastore-2026-09-05.md, seção B.5;
	desenho: .claude/agents-memory/arquiteto-services-2026-09-05.md, "L2.1.3"/"L2.1.6").

	Território desta tarefa (task-services-017): só este módulo e `./Store.luau` (+ specs) --
	nenhum `behavior/*.luau` é criado aqui (fica para tarefa futura, que vai chamar
	`Value.Validate`/`Value.AssertNameLength` a partir de `GlobalDataStore:GetAsync`/`SetAsync`/
	`UpdateAsync`/etc.).

	POR QUE "SEM Instance": este módulo precisa ser chamável e TESTÁVEL sem `Services.Bootstrap`
	nem `Runtime.DataModel` (regra 01: "teste o que for prático sem precisar de `.project.json`
	real") -- ele valida a FORMA de um valor Luau qualquer, nunca inspeciona se esse valor
	"pertence" a alguma árvore de Instance. Consequência direta e DECLARADA (regra 00, divergência
	de precisão, não de comportamento): uma `Runtime.Instance` real, nesta simulação, é um
	`newproxy(true)` puro sem `__type` (ver src/runtime/Instance.luau, `NewBase`) -- do ponto de
	vista de `type()` NATIVO do Luau (o único disponível aqui, sem importar `runtime`), ela é
	ESTRUTURALMENTE IDÊNTICA a qualquer outro userdata (`Vector3`, `CFrame`, `buffer`, etc. --
	também `newproxy(true)`, ver `.claude/rules/06-valuetypes.md`). Por isso a categoria de falha
	`"Userdata"` abaixo cobre `Instance` E qualquer outro userdata igualmente -- isto NÃO introduz
	um falso-negativo em relação ao Roblox real: nenhum DataType (Vector3/CFrame/Color3/...) é um
	`Variant` válido de DataStore também (a doc só lista nil/boolean/number/string/table como
	suportados) -- scripts reais convertem para tabela antes de guardar. Só se perde a
	granularidade de NOMEAR qual userdata era, que o próprio Roblox também não expõe de volta ao
	script no erro real.

	MENSAGENS DE ERRO: aproximação de boa-fé na família Roblox (inglês, sem prefixo `[LuauBench]`
	-- regra de idioma dos erros: erro com contraparte real no Roblox usa a família/formato do
	Roblox). A pesquisa dedicada (pesquisa-datastore-2026-09-05.md, seção "NÃO CONFIRMADO") não
	achou a string EXATA do Roblox para nenhum dos casos daqui (nome/chave/scope grande demais,
	valor grande demais, valor não serializável) -- texto autoral, não copiado de lugar nenhum, na
	FORMA que o Roblox usa (frase curta, em inglês, sem stack trace).

	CORREÇÃO 2026-09-05 (task-services-028, .claude/agents-memory/pesquisa-services-leva2-
	pendencias-2026-09-05.md, item 2): a pesquisa dedicada FECHOU a pendência acima para
	função/`Instance`/thread/chave mista (confirma que continuam recusados, e traz string
	observada por evidência de comunidade -- ex.: `"104: Cannot store Instance in data store.
	Data stores can only accept valid UTF-8 characters"` para `Instance` de topo, `"104: Cannot
	store Array/Dictionary in DataStore"` quando o valor problemático está ANINHADO dentro de uma
	tabela -- o erro real nomeia o CONTÊINER, não o valor culpado). Este módulo NÃO adota essas
	strings ao pé da letra (o Kind reportado aqui é sempre o do valor folha -- ex.: "Function" --
	nunca o do contêiner que o envolve; reproduzir a nuance "nomeia o contêiner, não a folha"
	exigiria redesenhar `SerializabilityFailure`/`Path`, fora do escopo desta correção) -- as
	mensagens abaixo para essas 4 categorias CONTINUAM como aproximação de boa-fé, NÃO CONFIRMADA
	byte-a-byte, exatamente como já estavam. Fica registrado para uma tarefa futura que queira
	subir a fidelidade dessas 4 mensagens especificamente.

	A MESMA pesquisa, porém, CORRIGE uma premissa que este módulo tinha implementado errada:
	**`NaN`/`inf`/`-inf` NÃO são recusados pelo Roblox real.** A doc oficial de Open Cloud
	(`https://create.roblox.com/docs/cloud/guides/data-stores`) confirma que "data store entries
	written through the Engine API can contain non-finite Luau numbers" -- ou seja, `SetAsync`/
	`UpdateAsync` chamados de DENTRO do jogo (o caso do LuauBench, que simula um script Luau
	rodando no servidor, nunca uma chamada Open Cloud externa) aceitam `NaN`/`inf`/`-inf` sem
	erro; só as RESPOSTAS do Open Cloud (API HTTP externa, JSON) precisam de uma representação
	especial (`{"t": "numeric", "v": "nan"}` etc.), porque JSON não tem `NaN`/`Infinity` -- isso
	não se aplica aqui. A tabela original do desenho do arquiteto (L2.1.3: "NaN, inf -> Recusado
	com erro") estava incorreta para esses dois casos especificamente -- era inferência por
	analogia com os outros tipos não serializáveis, nunca confirmada por leitura da doc
	(`error-codes-and-limits.md` não menciona NaN/inf em lugar nenhum, confirmado por grep no
	arquivo bruto pela própria pesquisa). Por isso `Value.CheckSerializable`/`Value.Validate`
	tratam `NaN`/`inf`/`-inf` como `number` válido, igual a qualquer outro -- NÃO existe mais
	`Kind = "NaN"`/`"Infinite"` neste módulo (removidos desta versão; existiram numa versão
	anterior desta mesma tarefa, antes da correção chegar).

	TAMANHO DO VALOR (bytes): o Roblox serializa o valor internamente (formato não documentado
	publicamente) antes de aplicar o limite de 4 194 304 bytes. Este módulo estima esse tamanho com
	um serializador JSON PRÓPRIO, minimalista, escrito só para a ESTIMATIVA -- chaves de tabela
	SEMPRE ordenadas (nunca a ordem de iteração de `pairs`, que não é estável entre execuções), o
	que torna `Value.EstimateByteSize` determinístico e testável. É uma APROXIMAÇÃO DECLARADA
	(regra 00): não afirma bater byte-a-byte com o serializador real do Roblox, mas é conservadora
	o bastante para pegar o caso que importa de verdade (um valor genuinamente grande demais) sem
	inventar uma unidade de medida nova.

	DEEP COPY: OBRIGATÓRIA na leitura E na escrita (L2.1.3) -- no Roblox o valor é serializado ao
	gravar e desserializado ao ler, então a tabela que o script recebe de `GetAsync`/`UpdateAsync`
	NUNCA é a mesma referência que está guardada, e a tabela que o script passa a `SetAsync` também
	não continua "viva" dentro do store depois da chamada. Sem cópia profunda aqui, o LuauBench
	criaria um ALIAS silencioso -- mutar o retorno de `GetAsync` alteraria o valor guardado, e um
	código que depende disso passaria no LuauBench e divergiria (silenciosamente, de outro jeito)
	no Roblox real -- exatamente a classe de bug que a regra 00 pede para nunca esconder. Ver
	`Value.DeepCopy`, usado por `./Store.luau` nos dois lados (escrita em `Set`/`Update`, leitura em
	`Get`/`Update`).

	Depende só de si mesmo -- nenhum `require`. Usado por `./Store.luau` (só `DeepCopy`) e, em
	tarefas futuras, por `../behavior/GlobalDataStore.luau`/`DataStoreService.luau`/etc. (fora do
	território desta tarefa).
]]

local Value = {}

-- Fonte: doc oficial "error-codes-and-limits.md", via pesquisa-datastore-2026-09-05.md, seção B.5.
local MAX_NAME_LENGTH = 50
local MAX_VALUE_BYTES = 4194304

-- ============================================================================================
-- Limite de nome (chave/nome de store/scope) -- os "3 limites de tamanho" do acceptance da task
-- contam: (1) key, (2) nome de store/scope [mesma regra, dois lugares], (3) tamanho do valor.
-- ============================================================================================

export type NameKind = "key" | "name" | "scope"

local function nameKindLabel(kind: NameKind): string
	if kind == "key" then
		return "DataStore key"
	elseif kind == "name" then
		return "DataStore name"
	end
	return "DataStore scope"
end

-- Não-lançante -- usado por quem quer decidir o que fazer sem pagar o custo de um `pcall`.
function Value.CheckNameLength(value: string, kind: NameKind): boolean
	return string.len(value) <= MAX_NAME_LENGTH
end

-- Nível 2: culpa quem chamou `Value.AssertNameLength` diretamente -- mesma convenção que
-- `./Store.luau`/tarefas futuras de `behavior/*.luau` devem seguir ao repassar o erro (ver
-- `AsyncCall.luau`, "POR QUE NÍVEL 3, NÃO 2" para o raciocínio de contagem de frames quando este
-- módulo passar a ser chamado através de uma camada `behavior` -- ajuste de nível fica por conta
-- de quem envolver esta chamada, este módulo não assume esse chamador ainda).
function Value.AssertNameLength(value: string, kind: NameKind): ()
	if not Value.CheckNameLength(value, kind) then
		error(
			`{nameKindLabel(kind)} must be less than or equal to {MAX_NAME_LENGTH} characters (got {string.len(value)})`,
			2
		)
	end
end

-- ============================================================================================
-- Serializabilidade -- as 4 categorias que a pesquisa CONFIRMA como recusadas (chave mista,
-- função, Instance, thread -- ver "CORREÇÃO 2026-09-05" no cabeçalho: NaN/inf/-inf NÃO entram
-- aqui, são `number` válido) + 2 categorias EXTRAS de robustez (chave de tipo exótico, referência
-- cíclica) que a doc não nomeia mas que um checker recursivo precisa tratar para nunca estourar a
-- pilha nem fingir que "não sabe" um caso que apareceu.
-- ============================================================================================

export type SerializabilityFailureKind =
	"MixedKeyTable"
	| "UnsupportedKey"
	| "Function"
	| "Thread"
	| "Userdata"
	| "CyclicReference"
	| "UnsupportedType"

export type SerializabilityFailure = {
	Kind: SerializabilityFailureKind,
	-- Caminho até o valor problemático, em notação Luau-like: "value", "value.Inventory[3]",
	-- "value.Owner.Name". Só para a mensagem de erro -- nunca reprocessado por código.
	Path: string,
	-- Preenchido só para "UnsupportedKey"/"UnsupportedType": o `type()` bruto do valor rejeitado.
	DetailType: string?,
}

local function childPath(path: string, key: unknown): string
	if type(key) == "string" then
		return `{path}.{key :: string}`
	end
	return `{path}[{tostring(key)}]`
end

local function checkSerializableRec(value: unknown, path: string, seen: { [unknown]: boolean }): SerializabilityFailure?
	if value == nil then
		return nil
	end

	local t = type(value)

	-- boolean/string/number são SEMPRE serializáveis -- inclusive `NaN`/`inf`/`-inf` (ver
	-- cabeçalho, "CORREÇÃO 2026-09-05": a Engine API real aceita não-finitos; só o Open Cloud
	-- precisaria de uma representação JSON especial, o que não é o caso do LuauBench).
	if t == "boolean" or t == "string" or t == "number" then
		return nil
	end

	if t == "function" then
		return { Kind = "Function", Path = path, DetailType = nil }
	end

	if t == "thread" then
		return { Kind = "Thread", Path = path, DetailType = nil }
	end

	if t == "userdata" then
		-- Cobre `Instance` e qualquer outro userdata -- ver cabeçalho, "POR QUE 'SEM Instance'".
		return { Kind = "Userdata", Path = path, DetailType = nil }
	end

	if t == "table" then
		if seen[value] then
			return { Kind = "CyclicReference", Path = path, DetailType = nil }
		end
		seen[value] = true

		local generic = value :: { [unknown]: unknown }
		local hasStringKey = false
		local hasNumberKey = false

		for key in generic do
			local keyType = type(key)
			if keyType == "string" then
				hasStringKey = true
			elseif keyType == "number" then
				hasNumberKey = true
			else
				seen[value] = nil
				return { Kind = "UnsupportedKey", Path = path, DetailType = keyType }
			end
		end

		if hasStringKey and hasNumberKey then
			seen[value] = nil
			return { Kind = "MixedKeyTable", Path = path, DetailType = nil }
		end

		for key, child in generic do
			local failure = checkSerializableRec(child, childPath(path, key), seen)
			if failure ~= nil then
				seen[value] = nil
				return failure
			end
		end

		seen[value] = nil
		return nil
	end

	-- CORREÇÃO 2026-09-05 (revisão de task-services-017): `type()` do Luau/Lune NÃO se limita aos 8
	-- nomes clássicos de Lua -- também devolve `"buffer"` e `"vector"` (tipos nativos do Luau,
	-- confirmado empiricamente: `type(buffer.create(4)) == "buffer"`, `type(vector.create(1,2,3))
	-- == "vector"`). Este ramo, portanto, É alcançável na prática -- e o comportamento já era
	-- (e continua sendo) correto: `buffer`/`vector` caem aqui e são recusados como
	-- `"UnsupportedType"` em vez de aceitos silenciosamente (nenhum dos dois é um `Variant` válido
	-- de DataStore -- a doc só lista nil/boolean/number/string/table). O `--!strict` de qualquer
	-- forma exigiria um retorno em todo caminho mesmo que este ramo fosse inalcançável -- devolvido
	-- como categoria genérica em vez de um `error()` de engenharia, para nunca crashar a validação
	-- de um valor de script do usuário por um caso que este módulo ainda não nomeia especificamente.
	return { Kind = "UnsupportedType", Path = path, DetailType = t }
end

local function describeSerializabilityFailure(failure: SerializabilityFailure): string
	local kind = failure.Kind
	if kind == "MixedKeyTable" then
		return `{failure.Path} is a table with both string and numeric keys, which cannot be stored in a DataStore (mixed Array/Dictionary tables are not supported)`
	elseif kind == "UnsupportedKey" then
		return `{failure.Path} has a table key of type '{failure.DetailType or "?"}', which cannot be stored in a DataStore (only string and number keys are supported)`
	elseif kind == "Function" then
		return `{failure.Path} is a function, which cannot be stored in a DataStore`
	elseif kind == "Thread" then
		return `{failure.Path} is a thread, which cannot be stored in a DataStore`
	elseif kind == "Userdata" then
		return `{failure.Path} is a userdata value (e.g. an Instance), which cannot be stored in a DataStore`
	elseif kind == "CyclicReference" then
		return `{failure.Path} contains a cyclic reference, which cannot be stored in a DataStore`
	end
	return `{failure.Path} has an unsupported type ('{failure.DetailType or "?"}'), which cannot be stored in a DataStore`
end

-- Não-lançante -- devolve `nil` se `value` é serializável, ou a falha estruturada (Kind + Path)
-- caso contrário. Ponto único de verdade -- `Value.AssertSerializable`/`Value.Validate` só
-- chamam isto e decidem o que fazer com o resultado.
function Value.CheckSerializable(value: unknown): SerializabilityFailure?
	return checkSerializableRec(value, "value", {})
end

-- Mensagem pronta (família Roblox, ver cabeçalho) para uma falha já detectada -- exposta para que
-- uma tarefa futura de `behavior/*.luau` possa compor a mensagem sem duplicar o texto aqui.
function Value.DescribeSerializabilityFailure(failure: SerializabilityFailure): string
	return describeSerializabilityFailure(failure)
end

-- Nível 2 -- ver comentário de `Value.AssertNameLength` sobre quem ajusta o nível quando isto
-- passar a ser chamado através de `behavior/*.luau`.
function Value.AssertSerializable(value: unknown): ()
	local failure = Value.CheckSerializable(value)
	if failure ~= nil then
		error(describeSerializabilityFailure(failure), 2)
	end
end

-- ============================================================================================
-- Tamanho serializado (estimativa determinística -- ver cabeçalho, "TAMANHO DO VALOR").
-- ============================================================================================

-- Bytes extras que aspas/barra-invertida (+1 cada, viram "\"" /"\\\\") e caracteres de controle
-- (+5 cada, viram "\\uXXXX", 6 bytes no lugar de 1) custariam se `s` fosse codificada como string
-- JSON -- usado só para a ESTIMATIVA de tamanho, nunca para gerar JSON de verdade.
local function estimateStringBytes(s: string): number
	local extra = 0
	for i = 1, string.len(s) do
		local byte = string.byte(s, i) :: number
		if byte == 34 or byte == 92 then -- '"' ou '\'
			extra += 1
		elseif byte < 0x20 then
			extra += 5
		end
	end
	return string.len(s) + extra + 2 -- +2 das aspas delimitadoras
end

local function estimateSizeRec(value: unknown, seen: { [unknown]: boolean }): number
	if value == nil then
		return 4 -- "null"
	end

	local t = type(value)
	if t == "boolean" then
		if value then
			return 4 -- "true"
		end
		return 5 -- "false"
	elseif t == "number" then
		return string.len(tostring(value))
	elseif t == "string" then
		return estimateStringBytes(value :: string)
	elseif t == "table" then
		if seen[value] then
			-- Referência cíclica -- `Value.Validate` já teria rejeitado antes de chegar aqui;
			-- tratado defensivamente para `EstimateByteSize` nunca travar quando chamado sozinho.
			return 4
		end
		seen[value] = true

		local generic = value :: { [unknown]: unknown }
		local stringKeys: { string } = {}
		local numberKeys: { number } = {}
		for key in generic do
			if type(key) == "string" then
				table.insert(stringKeys, key :: string)
			elseif type(key) == "number" then
				table.insert(numberKeys, key :: number)
			end
		end

		local total: number
		if #stringKeys > 0 then
			-- Ordem determinística -- `pairs`/`next` não garantem ordem estável entre execuções.
			table.sort(stringKeys)
			total = 2 -- "{" + "}"
			for i, key in stringKeys do
				if i > 1 then
					total += 1 -- ","
				end
				total += estimateStringBytes(key) + 1 -- ":"
				total += estimateSizeRec(generic[key], seen)
			end
		else
			table.sort(numberKeys)
			total = 2 -- "[" + "]"
			for i, key in numberKeys do
				if i > 1 then
					total += 1 -- ","
				end
				total += estimateSizeRec(generic[key], seen)
			end
		end

		seen[value] = nil
		return total
	end

	-- function/thread/userdata/outro: não deveria acontecer para um valor já validado por
	-- `Value.AssertSerializable` -- tratado como "null" (4 bytes) em vez de erro, porque este
	-- estimador também é útil isoladamente (ex.: diagnóstico) e não deveria panicar sozinho.
	return 4
end

-- Não-lançante. Determinístico: duas chamadas com o mesmo `value` (mesmo com tabelas recriadas de
-- outra referência, desde que estruturalmente iguais) sempre devolvem o mesmo número.
function Value.EstimateByteSize(value: unknown): number
	return estimateSizeRec(value, {})
end

-- Nível 2 -- ver comentário de `Value.AssertNameLength`.
function Value.AssertByteSize(value: unknown): ()
	local size = Value.EstimateByteSize(value)
	if size > MAX_VALUE_BYTES then
		error(
			`DataStore value exceeds the maximum size of {MAX_VALUE_BYTES} bytes (got {size} bytes, serialized)`,
			2
		)
	end
end

-- Combinação que `SetAsync`/`UpdateAsync`/`IncrementAsync` (tarefa futura de `behavior/*.luau`)
-- precisam antes de gravar: serializável E dentro do limite de tamanho, nesta ordem (um valor não
-- serializável não tem "tamanho" que faça sentido reportar antes de dizer POR QUE ele é inválido).
function Value.Validate(value: unknown): ()
	Value.AssertSerializable(value)
	Value.AssertByteSize(value)
end

-- ============================================================================================
-- Deep copy -- OBRIGATÓRIA na leitura E na escrita (ver cabeçalho, "DEEP COPY").
-- ============================================================================================

local function deepCopyRec(value: unknown, seen: { [unknown]: unknown }): unknown
	if type(value) ~= "table" then
		return value
	end

	local existingCopy = seen[value]
	if existingCopy ~= nil then
		return existingCopy
	end

	local copy: { [unknown]: unknown } = {}
	seen[value] = copy
	for key, child in value :: { [unknown]: unknown } do
		copy[deepCopyRec(key, seen)] = deepCopyRec(child, seen)
	end
	return copy
end

-- Genérico (`T` qualquer, não só `SerializabilityFailure`-válido) de propósito: `./Store.luau`
-- chama isto tanto para o valor de DataStore quanto, potencialmente, para `UserIds`/`Metadata` --
-- estruturas simples que também precisam da mesma garantia de não-alias. Referência cíclica é
-- preservada corretamente (a MESMA tabela original vira a MESMA tabela copiada, não uma cópia por
-- ocorrência) via `seen`, embora um valor cíclico nunca devesse chegar aqui vindo de
-- `Value.Validate` -- defesa, não caminho esperado.
function Value.DeepCopy<T>(value: T): T
	return (deepCopyRec(value, {}) :: unknown) :: T
end

return Value
