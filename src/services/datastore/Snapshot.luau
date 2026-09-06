--!strict

--[[
	Envelope de valor + documento de topo do estado "cloud" simulado (persistência local de
	`DataStoreService` entre execuções sucessivas de `luaubench run`). Território desta tarefa
	(task-services-029): SÓ este módulo + spec. Desenho completo:
	`.claude/agents-memory/arquiteto-persistencia-cloud-2026-09-06.md`, seções 3 e 4 -- este
	módulo IMPLEMENTA exatamente a tabela de 8 linhas da seção 4 e o formato de documento da
	seção 3, sem inventar forma diferente.

	POR QUE ESTE MÓDULO EXISTE (medido empiricamente pelo arquiteto, `@lune/serde` 0.10.5,
	reproduzido nesta tarefa antes de escrever este arquivo, via script descartável): JSON cru
	(via `serde.encode("json", ...)` direto, sem envelope) NÃO é um contêiner sem perda para o
	domínio de valor que `./Value.luau` (`Value.CheckSerializable`) já aceita hoje --

		* `NaN`/`math.huge`/`-math.huge` viram `null` SEM ERRO -- corrupção silenciosa (o valor
		  volta `nil` na próxima execução, nunca `NaN`/`inf`). Confirmado: `serde.encode("json",
		  0/0) == "null"`.
		* Tabela numérica ESPARSA (ex.: `{[1]=1, [3]=3}`) vira `[1]` SEM ERRO -- corrupção
		  silenciosa (o elemento `[3]` some).
		* Tabela com chave numérica que não começa em 1, é negativa ou fracionária (ex.:
		  `{[2]="a"}`, `{[-1]="a"}`, `{[1.5]="a"}`) e string com byte inválido em UTF-8 (ex.:
		  `string.char(0xFF)`) ERRAM no `serde.encode` nativo (confirmado: mensagem
		  `"deserialize error: invalid type: byte array, expected any valid JSON value"` para o
		  caso da string) -- não corrompem, mas também não deveriam quebrar aqui, já que
		  `Value.CheckSerializable` os ACEITA (não são um dos 4 tipos recusados: função/thread/
		  userdata/chave mista/tipo exótico).

	Os dois primeiros violam a invariante 2 do projeto (fidelidade -- divergência do LuauBench EM
	RELAÇÃO A ELE MESMO entre duas execuções, pior que divergência em relação ao Roblox) se
	deixados sem tratamento. É exatamente o que este módulo evita.

	## O envelope: "plain quando dá, tagueado quando precisa" (seção 4 do desenho)

	Regra de ENCODE de um valor `v` (ver `encodeValue`/`encodeTable` abaixo):

		boolean                                          -> JSON boolean, cru
		number finito                                    -> JSON number, cru
		number não-finito (NaN/inf/-inf)                 -> {"$":"n","v":"nan"|"inf"|"-inf"}
		string UTF-8 válida (utf8.len(s) ~= nil)          -> JSON string, crua
		string com byte inválido                          -> {"$":"s","hex":"ff00..."}
		table densa 1..n sem buracos (n == contagem       -> JSON array (elementos recursivos)
		  de chaves, chaves só-number)
		table só com chaves string, NENHUMA delas "$"      -> JSON object (valores recursivos)
		qualquer OUTRA table (numérica esparsa/negativa/   -> {"$":"m","e":[[k,v],[k,v],...]}
		  fracionária/não iniciando em 1, OU dicionário       (k e v ambos recursivos)
		  contendo a chave "$", OU -- defensivo -- chave
		  mista string+number)

	Regra de DECODE (ver `decodeValue`/`decodeTable`/`decodeTag`), SIMÉTRICA e SEM AMBIGUIDADE: um
	objeto JSON COM a chave "$" é SEMPRE um envelope tagueado; SEM ela é SEMPRE um dicionário de
	chaves string. É por isso que a linha do dicionário, no ENCODE, exige "nenhuma chave igual a
	'$'" -- um dicionário do usuário que contenha "$" cai no formato "m" no encode, então o decode
	NUNCA precisa adivinhar (nenhum dicionário legítimo chega ao decode como objeto plano com
	chave "$" -- só os 3 tags "n"/"s"/"m" fazem isso).

	Tabela VAZIA (`{}`): Lua não distingue array vazio de dicionário vazio (`next({}) == nil` para
	os dois) -- convenção deste módulo (decisão registrada, não confirmada por fonte externa
	porque não há o que confirmar: é uma limitação estrutural do Lua, não uma escolha de
	fidelidade): `encodeTable` trata tabela vazia como array vazio (`[]`); o decode de `[]` OU de
	`{}` produzem igualmente `{}`. O round-trip nunca observa essa escolha (`DeepEqual` não
	diferencia array vazio de dicionário vazio -- não existe tal distinção em Lua).

	`hex` em vez de base64 (ver seção 4 do desenho): `@lune/serde` 0.10.5 não expõe base64
	(confirmado por pesquisa anterior, citada no desenho) -- hex são ~10 linhas de Luau. Caso
	raríssimo (string de DataStore com byte inválido em UTF-8); legibilidade > densidade.

	`nil` no valor de TOPO: `Value.CheckSerializable(nil) == nil` (nil É serializável -- é a
	AUSÊNCIA de uma chave, nunca um valor guardado DENTRO de uma tabela, já que uma tabela Lua não
	consegue guardar `nil` como valor). Confirmado empiricamente: `serde.encode("json", nil)`
	produz `"null"` sem erro, e `serde.decode("json", "null")` devolve `nil` -- então
	`Encode(nil)`/`Decode(nil)` são identidade (`nil -> nil`), sem necessidade de tag.

	## O documento de topo (seção 3 do desenho)

	`Snapshot.EncodeDocument`/`Snapshot.DecodeDocument` implementam o envelope de DOCUMENTO
	completo -- `{SchemaVersion, Kind, SavedAt, Stores}` -- exatamente como a seção 3 especifica.
	`Stores` é OPACO para este módulo (tipado `{[string]: unknown}` na entrada e saída): o formato
	interno por-store (`Stores[storeId] = {Name, Scope, Keys}`, onde `Keys` vem de
	`Store.Export`) é responsabilidade de `./Store.luau`/`../behavior/GlobalDataStore.luau`
	(tarefas irmãs desta leva, `task-services-030`/`031`, FORA do território desta tarefa) -- este
	módulo só GARANTE que qualquer estrutura de dado dentro do domínio de
	`Value.CheckSerializable` (que é exatamente o que `KeyRecord`/`VersionRecord` produzem:
	tabelas com chave string, arrays densos, valores primitivos, e o `Value` arbitrário de cada
	versão) sobrevive ao round-trip via o MESMO envelope de valor acima, aplicado recursivamente à
	estrutura inteira -- não existe um segundo formato de codificação para o "documento" versus
	"um valor solto"; é o mesmo `Encode`/`Decode`, só que a raiz é sempre a tabela `Stores`.

	`SchemaVersion` DESCONHECIDO (maior que `Snapshot.CurrentSchemaVersion`) é RECUSADO com erro
	nomeando a versão encontrada e a suportada -- NUNCA ignorado nem sobrescrito (destruiria
	estado real do usuário em silêncio se um documento de uma versão futura do formato fosse lido
	por engano por uma versão mais antiga do LuauBench). `SchemaVersion` menor ou igual ao
	suportado é aceito sem migração (hoje só existe a versão 1 -- lógica de migração entre versões
	é tarefa futura, que só faz sentido quando existir uma 2ª versão de verdade).

	## Fronteira de responsabilidade (regra 02/03: `services` nunca faz I/O)

	ZERO `require("@lune/fs")` neste módulo -- e ZERO qualquer outra forma de I/O. Este módulo só
	TRADUZ dado (Luau <-> JSON), nunca decide onde os bytes moram -- isso é
	`src/cli/CloudStore.luau` (tarefa irmã de outro território, `task-cli-029`). Depende só de
	`@lune/serde` (JÁ usado por `../behavior/HttpService.luau:335`, `JSONEncode`/`JSONDecode` --
	não é dependência nova) e de `utf8`/`string`/`table` nativos do Luau.

	MENSAGENS DE ERRO: este módulo não tem contraparte real no Roblox (é um formato PRÓPRIO do
	LuauBench, fora do namespace de qualquer classe simulada -- regra 00 permite extensão
	deliberada fora do namespace de Instance) -- então usam inglês técnico simples, sempre
	nomeando o campo/valor problemático (regra 01: "mensagem de erro inclui contexto suficiente
	para debugar").

	Recursão: `encodeTable`/`encodeAsMap` e `decodeTag`/`decodeTable` recebem a função de
	recursão (`encodeValue`/`decodeValue`) como PARÂMETRO em vez de mutuamente se referenciarem
	por nome de upvalue -- evita declaração antecipada (`local x: T` sem inicializador, que este
	módulo do zero preferiu não introduzir como um padrão novo no território) e deixa o fluxo de
	chamada explícito na assinatura de cada função auxiliar.
]]

local serde = require("@lune/serde")

local Snapshot = {}

-- ================================================================================================
-- Tipo do valor JÁ ENVELOPADO -- estruturalmente seguro para `serde.encode("json", ...)` sem
-- nenhuma das 3 falhas medidas no cabeçalho (nunca contém NaN/inf cru, nunca contém tabela
-- esparsa/chave inválida sem passar pelo tag "m", nunca contém string com byte inválido crua).
-- Mesmo padrão de `src/cli/JsonValue.luau` (`JsonValue`) -- união recursiva incluindo `nil` (para
-- o caso do valor de TOPO ser `nil`, ver cabeçalho).
-- ================================================================================================

export type EncodedValue = nil | boolean | number | string | { EncodedValue } | { [string]: EncodedValue }

-- Assinatura da função de recursão, passada como parâmetro para as auxiliares de tabela (ver
-- cabeçalho, "Recursão").
type Encoder = (value: unknown) -> EncodedValue
type Decoder = (value: unknown) -> unknown

-- ================================================================================================
-- Hex (só para strings com byte inválido em UTF-8 -- caso raro, ver cabeçalho "hex em vez de
-- base64").
-- ================================================================================================

local function bytesToHex(s: string): string
	local parts: { string } = table.create(string.len(s))
	for i = 1, string.len(s) do
		parts[i] = string.format("%02x", string.byte(s, i) :: number)
	end
	return table.concat(parts)
end

local function hexToBytes(hex: string): string
	if string.len(hex) % 2 ~= 0 then
		error(`Snapshot.Decode: invalid hex string (odd length): "{hex}"`, 3)
	end
	local parts: { string } = table.create(string.len(hex) // 2)
	local index = 0
	for i = 1, string.len(hex), 2 do
		local byteText = string.sub(hex, i, i + 1)
		local byte = tonumber(byteText, 16)
		if byte == nil then
			error(`Snapshot.Decode: invalid hex string (non-hex digits): "{byteText}"`, 3)
		end
		index += 1
		parts[index] = string.char(byte)
	end
	return table.concat(parts)
end

-- ================================================================================================
-- ENCODE -- domínio de `Value.CheckSerializable` -> `EncodedValue` (seção 4, tabela de 8 linhas).
-- ================================================================================================

local function isFiniteNumber(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge -- `n == n` exclui NaN (NaN nunca é igual a si mesmo)
end

local function encodeNonFiniteNumber(n: number): { [string]: EncodedValue }
	local tag: string
	if n ~= n then
		tag = "nan"
	elseif n == math.huge then
		tag = "inf"
	else
		tag = "-inf"
	end
	return { ["$"] = "n", v = tag }
end

local function isValidUtf8(s: string): boolean
	return utf8.len(s) ~= nil
end

-- Fallback UNIVERSAL: representa QUALQUER par chave/valor (inclusive chave mista, numérica
-- esparsa/negativa/fracionária, ou dicionário contendo "$") como uma lista de pares recursivos --
-- ver cabeçalho, tabela do envelope, última linha.
local function encodeAsMap(value: { [unknown]: unknown }, encode: Encoder): { [string]: EncodedValue }
	local entries: { EncodedValue } = {}
	for key, child in value do
		table.insert(entries, { encode(key), encode(child) })
	end
	return { ["$"] = "m", e = entries }
end

local function encodeTable(value: { [unknown]: unknown }, encode: Encoder): EncodedValue
	local stringKeys: { string } = {}
	local numberKeys: { number } = {}
	local keyCount = 0
	local hasOtherKey = false

	for key in value do
		keyCount += 1
		local keyType = type(key)
		if keyType == "string" then
			table.insert(stringKeys, key :: string)
		elseif keyType == "number" then
			table.insert(numberKeys, key :: number)
		else
			-- `Value.CheckSerializable` já teria rejeitado uma chave que não é string/number --
			-- defensivo (nunca deveria ser alcançado por um valor pré-validado), tratado como
			-- fallback "m" em vez de erro: "m" representa QUALQUER chave recursivamente, então
			-- nem essa categoria hipotética perde informação.
			hasOtherKey = true
		end
	end

	if hasOtherKey then
		return encodeAsMap(value, encode)
	end

	if keyCount == 0 then
		-- Tabela vazia: convenção do módulo, ver cabeçalho ("Tabela VAZIA") -- array vazio.
		return {}
	end

	if #stringKeys == keyCount then
		-- Só chaves string. Dicionário -- A MENOS que contenha "$" (reservado para tag).
		for _, key in stringKeys do
			if key == "$" then
				return encodeAsMap(value, encode)
			end
		end
		local result: { [string]: EncodedValue } = {}
		for _, key in stringKeys do
			result[key] = encode(value[key])
		end
		return result
	end

	-- `#stringKeys == 0` e `#numberKeys == keyCount` neste ponto (o único outro caso possível, já
	-- que `Value.CheckSerializable` recusa chave mista string+number -- e mesmo que não
	-- recusasse, essa mistura cairia aqui e seria tratada corretamente pelo teste de densidade
	-- abaixo, que falha e cai no fallback "m").
	local isDenseArray = true
	for _, key in numberKeys do
		if key ~= math.floor(key) or key < 1 or key > keyCount then
			isDenseArray = false
			break
		end
	end

	if isDenseArray then
		-- `numberKeys` cobre exatamente `1..keyCount` sem repetição (chaves de tabela são
		-- únicas, e o teste acima garante que cada uma está no intervalo [1, keyCount] --
		-- `keyCount` chaves distintas nesse intervalo de tamanho `keyCount` é necessariamente
		-- uma bijeção com `1..keyCount`).
		local result: { EncodedValue } = table.create(keyCount)
		for _, key in numberKeys do
			result[key] = encode(value[key])
		end
		return result
	end

	-- Numérica esparsa/negativa/fracionária/não iniciando em 1 -- ver cabeçalho, tabela.
	return encodeAsMap(value, encode)
end

local function encodeValue(value: unknown): EncodedValue
	if value == nil then
		return nil
	end

	local t = type(value)

	if t == "boolean" then
		return value :: boolean
	end

	if t == "number" then
		local n = value :: number
		if isFiniteNumber(n) then
			return n
		end
		return encodeNonFiniteNumber(n)
	end

	if t == "string" then
		local s = value :: string
		if isValidUtf8(s) then
			return s
		end
		return { ["$"] = "s", hex = bytesToHex(s) }
	end

	if t == "table" then
		return encodeTable(value :: { [unknown]: unknown }, encodeValue)
	end

	-- Fora do domínio de `Value.CheckSerializable` (function/thread/userdata/buffer/vector) --
	-- `Snapshot.Encode` assume um valor JÁ validado (contrato documentado em `Snapshot.Encode`);
	-- alcançar isto é bug de quem chamou sem validar antes, então erra com clareza em vez de
	-- produzir um envelope corrompido silenciosamente (regra 01).
	error(`Snapshot.Encode: unsupported Luau type '{t}' -- only the domain accepted by Value.CheckSerializable can be encoded`)
end

-- ================================================================================================
-- DECODE -- `EncodedValue` -> domínio de `Value.CheckSerializable` (inverso exato de ENCODE).
-- ================================================================================================

local function decodeTag(value: { [string]: unknown }, tagValue: string, decode: Decoder): unknown
	if tagValue == "n" then
		local v = value.v
		if v == "nan" then
			return 0 / 0
		elseif v == "inf" then
			return math.huge
		elseif v == "-inf" then
			return -math.huge
		end
		error(`Snapshot.Decode: tag "n" has unknown "v" field: {tostring(v)}`, 3)
	elseif tagValue == "s" then
		local hex = value.hex
		if type(hex) ~= "string" then
			error(`Snapshot.Decode: tag "s" is missing a string "hex" field`, 3)
		end
		return hexToBytes(hex :: string)
	elseif tagValue == "m" then
		local entries = value.e
		if type(entries) ~= "table" then
			error(`Snapshot.Decode: tag "m" is missing a table "e" field`, 3)
		end
		local result: { [unknown]: unknown } = {}
		for _, pair in entries :: { unknown } do
			if type(pair) ~= "table" then
				error(`Snapshot.Decode: tag "m" has a malformed entry (expected a [key, value] pair)`, 3)
			end
			local pairTable = pair :: { unknown }
			local key = decode(pairTable[1])
			local decodedValue = decode(pairTable[2])
			if key == nil then
				error(`Snapshot.Decode: tag "m" has a nil key, which is not a valid Luau table key`, 3)
			end
			result[key] = decodedValue
		end
		return result
	end

	error(`Snapshot.Decode: unknown "$" tag: "{tagValue}"`, 3)
end

-- Tabela decodificada pelo `serde.decode` já chegou como array (chaves number, 1..n -- garantia
-- do próprio serde/JSON: um array JSON decodifica com chaves number, um objeto com chaves string,
-- nunca misturado -- mesma premissa que `src/cli/JsonValue.luau`, `isArrayShaped`, já documenta e
-- usa) ou como objeto (chaves string). Distingue pela primeira chave via `next`, igual
-- `JsonValue.luau`.
local function decodeTable(value: { [unknown]: unknown }, decode: Decoder): unknown
	local tagValue = (value :: { [string]: unknown })["$"]
	if tagValue ~= nil then
		if type(tagValue) ~= "string" then
			error(`Snapshot.Decode: "$" tag field must be a string, got '{type(tagValue)}'`, 3)
		end
		return decodeTag(value :: { [string]: unknown }, tagValue :: string, decode)
	end

	local firstKey = next(value)
	if firstKey == nil then
		-- Tabela vazia -- `{}`/`[]` decodificados pelo serde são indistinguíveis (ver cabeçalho).
		return {}
	end

	if type(firstKey) == "number" then
		-- Array -- decodifica cada elemento recursivamente, preserva o índice.
		local result: { [unknown]: unknown } = {}
		for key, child in value do
			result[key] = decode(child)
		end
		return result
	end

	-- Objeto SEM "$" -- SEMPRE dicionário (ver cabeçalho: decisão sem ambiguidade).
	local result: { [string]: unknown } = {}
	for key, child in value do
		result[key :: string] = decode(child)
	end
	return result
end

local function decodeValue(value: unknown): unknown
	if value == nil then
		return nil
	end

	local t = type(value)

	if t == "boolean" or t == "number" or t == "string" then
		return value
	end

	if t == "table" then
		return decodeTable(value :: { [unknown]: unknown }, decodeValue)
	end

	-- `serde.decode("json", ...)` nunca produz `function`/`thread`/`userdata` -- inalcançável na
	-- prática, mas `--!strict` exige um retorno em todo caminho; erra em vez de devolver algo
	-- inventado (regra 01).
	error(`Snapshot.Decode: unexpected decoded type '{t}'`)
end

-- ================================================================================================
-- API pública -- valor solto
-- ================================================================================================

-- Traduz um valor Luau do domínio aceito por `Value.CheckSerializable` (chamador garante isso
-- ANTES de chamar -- este módulo não revalida, é tradução pura) para uma `EncodedValue` segura
-- para `serde.encode("json", ...)` sem nenhuma das 3 falhas medidas no cabeçalho.
function Snapshot.Encode(value: unknown): EncodedValue
	return encodeValue(value)
end

-- Inverso exato de `Snapshot.Encode` -- `Snapshot.Decode(Snapshot.Encode(v))` é `DeepEqual` a `v`
-- para todo `v` no domínio (é o acceptance/invariante central desta tarefa, ver spec).
function Snapshot.Decode(encoded: EncodedValue): unknown
	return decodeValue(encoded)
end

-- Corta a stack trace multi-linha que um erro nativo do Lune/Rust produz (mesmo tratamento que
-- `../behavior/HttpService.luau`, `firstLineOf`, e `src/cli/JsonValue.luau` já documentam para o
-- mesmo tipo de erro de `serde`) -- nunca vaza o formato interno do parser.
local function firstLineOf(err: unknown): string
	local text = tostring(err)
	return string.match(text, "^[^\n]*") or text
end

-- Combinação `Encode` + `serde.encode("json", ...)` -- conveniência para quem só precisa de uma
-- string JSON pronta a partir de um valor solto (não um documento inteiro). Por construção, o
-- resultado de `Snapshot.Encode` nunca deveria falhar ao ser serializado por `serde.encode`
-- (nenhuma das 3 causas medidas sobrevive ao envelope) -- o `pcall` aqui é defesa, não caminho
-- esperado (regra 01: nunca esconder um erro inesperado atrás de um valor inventado).
function Snapshot.EncodeToJson(value: unknown): string
	local encoded = Snapshot.Encode(value)
	local ok, jsonOrError = pcall(function(): string
		return serde.encode("json", encoded)
	end)
	if not ok then
		error(`Snapshot.EncodeToJson: unexpected failure serializing to JSON: {firstLineOf(jsonOrError)}`, 2)
	end
	return jsonOrError
end

-- Combinação `serde.decode("json", ...)` + `Decode` -- inverso de `Snapshot.EncodeToJson`. JSON
-- malformado erra com mensagem clara (nunca devolve `nil`/tabela vazia fingindo sucesso).
function Snapshot.DecodeFromJson(text: string): unknown
	local ok, decodedOrError = pcall(function(): unknown
		return serde.decode("json", text)
	end)
	if not ok then
		error(`Snapshot.DecodeFromJson: invalid JSON: {firstLineOf(decodedOrError)}`, 2)
	end
	-- CAST DE FRONTEIRA: `serde.decode` devolve `unknown` (fronteira externa) -- daqui em diante
	-- é tratado como `EncodedValue` (mesma disciplina de `src/cli/JsonValue.luau`, "CAST DE
	-- FRONTEIRA ÚNICO"). `Snapshot.Decode` valida a FORMA internamente (erra em vez de aceitar
	-- silenciosamente algo fora do domínio esperado).
	return Snapshot.Decode(decodedOrError :: EncodedValue)
end

-- ================================================================================================
-- API pública -- documento de topo (seção 3 do desenho)
-- ================================================================================================

-- Versão ATUAL do formato de documento -- ver cabeçalho, "SchemaVersion". Único número que este
-- módulo conhece; migração entre versões (quando existir uma 2ª) é tarefa futura.
Snapshot.CurrentSchemaVersion = 1 :: number

-- `Kind` fixo para o documento de `DataStoreService` -- outro nome lógico (ex.: "memorystore",
-- seção 8 do desenho) usaria seu PRÓPRIO `Kind`, quando essa leva futura existir; não inventado
-- aqui, só declarado para o único `Kind` que este módulo emite hoje.
Snapshot.DocumentKind = "luaubench-datastore" :: string

export type Document = {
	SchemaVersion: number,
	Kind: string,
	SavedAt: number, -- ms desde epoch -- só informativo (ver desenho, seção 3)
	-- Conteúdo OPACO para este módulo -- formato interno (`Stores[storeId] = {Name, Scope,
	-- Keys}`) é responsabilidade de `./Store.luau`/`../behavior/GlobalDataStore.luau` (fora do
	-- território desta tarefa, ver cabeçalho). Já DECODIFICADO (passou por `Snapshot.Decode`).
	Stores: { [string]: unknown },
}

-- Constrói o documento completo (`SchemaVersion` = `Snapshot.CurrentSchemaVersion`, `Kind` =
-- `Snapshot.DocumentKind`, `SavedAt` = `savedAtMillis`) e serializa para uma string JSON
-- (pretty-printed -- seção 3 do desenho: "para o arquivo ser legível e diffável"). `stores` passa
-- pelo MESMO `Snapshot.Encode` que um valor solto -- não existe um segundo formato de codificação
-- para o documento (ver cabeçalho).
function Snapshot.EncodeDocument(stores: { [string]: unknown }, savedAtMillis: number): string
	local document = {
		SchemaVersion = Snapshot.CurrentSchemaVersion,
		Kind = Snapshot.DocumentKind,
		SavedAt = savedAtMillis,
		Stores = Snapshot.Encode(stores),
	}

	local ok, jsonOrError = pcall(function(): string
		return serde.encode("json", document, true) -- `true` = pretty, ver seção 3 do desenho
	end)
	if not ok then
		error(`Snapshot.EncodeDocument: unexpected failure serializing document: {firstLineOf(jsonOrError)}`, 2)
	end
	return jsonOrError
end

-- Inverso de `Snapshot.EncodeDocument`. Recusa com erro claro:
--   * JSON malformado (nunca devolve documento vazio fingindo sucesso);
--   * documento sem a forma esperada no topo (campo ausente/tipo errado);
--   * `SchemaVersion` MAIOR que `Snapshot.CurrentSchemaVersion` -- nomeia a versão ENCONTRADA e a
--     SUPORTADA (ver cabeçalho: nunca ignora nem sobrescreve estado do usuário em silêncio).
-- `SchemaVersion` menor ou igual ao suportado é aceito sem migração (só existe a versão 1 hoje).
function Snapshot.DecodeDocument(text: string): Document
	local ok, decodedOrError = pcall(function(): unknown
		return serde.decode("json", text)
	end)
	if not ok then
		error(`Snapshot.DecodeDocument: invalid JSON: {firstLineOf(decodedOrError)}`, 2)
	end

	if type(decodedOrError) ~= "table" then
		error(`Snapshot.DecodeDocument: malformed document (expected a JSON object at the top level, got '{type(decodedOrError)}')`, 2)
	end
	local raw = decodedOrError :: { [string]: unknown }

	local schemaVersion = raw.SchemaVersion
	if type(schemaVersion) ~= "number" then
		error(`Snapshot.DecodeDocument: malformed document (missing or non-number "SchemaVersion" field)`, 2)
	end
	local schemaVersionNumber = schemaVersion :: number
	if schemaVersionNumber > Snapshot.CurrentSchemaVersion then
		error(
			`Snapshot.DecodeDocument: unsupported SchemaVersion {schemaVersionNumber} (this LuauBench supports up to {Snapshot.CurrentSchemaVersion}) -- update LuauBench to open this project`,
			2
		)
	end

	local kind = raw.Kind
	if type(kind) ~= "string" then
		error(`Snapshot.DecodeDocument: malformed document (missing or non-string "Kind" field)`, 2)
	end

	local savedAt = raw.SavedAt
	if type(savedAt) ~= "number" then
		error(`Snapshot.DecodeDocument: malformed document (missing or non-number "SavedAt" field)`, 2)
	end

	local storesRaw = raw.Stores
	if storesRaw == nil then
		error(`Snapshot.DecodeDocument: malformed document (missing "Stores" field)`, 2)
	end

	-- CAST DE FRONTEIRA -- ver `Snapshot.DecodeFromJson` acima, mesmo raciocínio.
	local decodedStores = Snapshot.Decode(storesRaw :: EncodedValue)
	if type(decodedStores) ~= "table" then
		error(`Snapshot.DecodeDocument: malformed document ("Stores" field does not decode to a table)`, 2)
	end

	return {
		SchemaVersion = schemaVersionNumber,
		Kind = kind :: string,
		SavedAt = savedAt :: number,
		Stores = decodedStores :: { [string]: unknown },
	}
end

return Snapshot
