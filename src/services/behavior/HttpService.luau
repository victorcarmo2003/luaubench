--!strict

--[[
	Behavior de `HttpService` -- task-services-022 (sub-leva A). LER
	.claude/agents-memory/arquiteto-services-2026-09-05.md, seção "L2.2 -- `HttpService`: a rede é
	opt-in de quem roda o LuauBench, exatamente como é opt-in do dono do lugar no Roblox" INTEIRA
	(L2.2.1 a L2.2.5) antes de mexer aqui.

	SEM REDE NENHUMA neste módulo -- confirmável estaticamente: `@lune/net` NUNCA é `require`d
	aqui (só `@lune/serde`, para JSON). Isto É a fidelidade desta sub-leva, não uma limitação dela:
	um lugar Roblox recém-criado, não publicado, tem `HttpEnabled == false` por DEFAULT (dump:
	`Default 'false'`) -- o LuauBench, sem a flag `--allow-http` (sub-leva B, task-services-026,
	ainda não construída), é uma simulação EXATA desse estado, não uma aproximação dele.

	## `HttpEnabled` -- NENHUM behavior explícito necessário para a PROPRIEDADE em si

	Confirmado depois de rodar o gerador nesta tarefa: `generated/classes/HttpService.luau` já
	emite `HttpEnabled = { Kind = "Property", Default = false, ReadOnly = true, ... }` sozinho, via
	a regra de emissão A.4 do gerador (passo 5: `Security.Write ("LocalUserSecurity") ~= "None"` ->
	incluído, `ReadOnly = true`) -- exatamente a consequência que L2.2.1 previu a partir do dump
	(`HttpEnabled: Security { Read = None, Write = LocalUserSecurity }`). `ClassRegistry.new`/
	`NewEngineInstance` semeia o valor `false` sozinho a partir desse `Default`, e o modo ESTRITO da
	instância (`Instance.luau`, passo 7 do `__newindex`) já erra "Unable to assign property
	HttpEnabled. Property is read only" para qualquer tentativa de escrita de script -- nenhuma das
	duas coisas precisa de código aqui. Este módulo só LÊ `HttpEnabled` (via
	`Runtime.Instance.GetPropertyRaw`, a via de engenharia que ignora o schema -- mesmo mecanismo
	que `--allow-http`, quando existir, vai usar para LIGAR a flag por fora do schema, via
	`SetPropertyRaw`).

	## JSONEncode / JSONDecode -- sobre `@lune/serde`, com UMA divergência descoberta e corrigida à
	## MÃO, e UMA divergência descoberta e só DECLARADA (nunca escondida -- regra 00)

	Verificado RODANDO `serde.encode`/`serde.decode` de verdade nesta tarefa (Lune 0.10.5, mesma
	versão do `rokit.toml`), além do que a pesquisa já tinha (pesquisa-http-messaging-2026-09-05.md,
	item B.5):

	1. **JSON de entrada inválido ERRA de verdade** (`typeof(err) == "error"`, mesmo formato que
	   `src/cli/JsonValue.luau` já documenta para o mesmo `serde.decode`) -- bate com a doc oficial
	   ("JSON de entrada inválido: lança erro, não retorna nil"). `JSONDecode`, abaixo, RETRADUZ essa
	   mensagem (corta a stack trace multi-linha do parser Rust, reformula em uma frase única) em vez
	   de vazar o formato interno -- mesma disciplina da tabela de fidelidade da leva (L2.2.5:
	   "Mensagem retraduzida").

	2. **DESCOBERTA (diverge da pesquisa) -- referência cíclica NÃO faz `serde.encode` errar.**
	   A doc oficial do Roblox afirma que uma referência cíclica CAUSA ERRO em JSONEncode, e a
	   pesquisa registrou isso como fato esperado -- mas `serde.encode("json", t)` com `t.self = t`
	   devolve `ok = true, "{}"` (a chave cíclica é SILENCIOSAMENTE OMITIDA, sem erro, sem
	   trava/loop infinito) -- confirmado rodando várias formas (auto-referência direta, ciclo
	   mútuo A<->B, tabela com campo cíclico ao lado de campos normais: só o campo cíclico some,
	   o resto do JSON sai correto). Isto SERIA uma divergência silenciosa grave em relação ao
	   Roblox real (que erra) se este módulo só delegasse a `serde.encode` -- por isso `JSONEncode`,
	   abaixo, faz sua PRÓPRIA varredura de ciclo (`hasCyclicReference`, mesma técnica de
	   pilha-de-ancestrais -- `seen[value] = true` antes de recursar, `seen[value] = nil` depois --
	   já usada e testada em `../datastore/Value.luau`, `checkSerializableRec`) ANTES de chamar
	   `serde.encode`, e ERRA com a família Roblox se encontrar um ciclo. Isto é comportamento
	   ESCRITO À MÃO (regra 03: o dump/a doc dão o "o quê" -- "erra com referência cíclica" -- nunca
	   o "como"), não uma reimplementação de JSON inteira -- a codificação de verdade continua 100%
	   delegada a `serde.encode`.

	3. **DIVERGÊNCIA DECLARADA (nunca corrigida nesta sub-leva) -- `inf`/`NaN`.** A doc oficial diz
	   que o Roblox ACEITA `inf`/`NaN` em `JSONEncode` e produz JSON DELIBERADAMENTE INVÁLIDO (o
	   token literal `inf`/`nan`, que nenhum parser JSON padrão aceita) -- é uma escolha de design
	   documentada do motor real, não um bug. `serde.encode` do Lune 0.10.5, confirmado rodando,
	   NÃO recusa/erra nesses casos (o que já seria aceitável dentro da instrução desta tarefa) --
	   ele SILENCIOSAMENTE substitui `inf`/`-inf`/`NaN` por `null` (`{"x": math.huge}` vira
	   `{"x":null}`). Ou seja: nem erro (que já seria uma divergência, mas ALTA e óbvia), nem o
	   comportamento real (token inválido) -- um terceiro resultado, silencioso, que MUDA O VALOR.
	   Reimplementar um encoder JSON próprio só para reproduzir bit-a-bit esse detalhe está FORA do
	   escopo desta sub-leva (que pede JSON "sobre `@lune/serde`", não um encoder autoral) -- a
	   divergência fica DECLARADA aqui, no código, e no relatório da tarefa, nunca escondida (regra
	   00): `HttpService:JSONEncode({x = 1/0})` no LuauBench devolve `{"x":null}`; no Roblox real
	   devolveria `{"x":inf}` (JSON tecnicamente inválido, de propósito).

	4. Chaves de tabela mistas (string + número -- "array tem prioridade, chaves string são
	   ignoradas", doc oficial): comportamento nativo do `serde.encode`, sem código extra necessário
	   aqui.

	   DIVERGÊNCIA DECLARADA ADICIONAL (achado desta tarefa, tabela vazia): a doc oficial afirma que
	   uma tabela Lua vazia `{}` vira array JSON vazio `[]`. Confirmado RODANDO nesta tarefa:
	   `serde.encode("json", {})` devolve `"{}"` (objeto JSON vazio), NUNCA `"[]"` -- o Lune não
	   distingue "mapa vazio" de "array vazio" (a ambiguidade inversa da que `serde.decode` já tem,
	   documentada em `src/cli/JsonValue.luau`: JSON `{}` e `[]` decodificam igual em Lua; aqui é
	   Lua `{}` que só pode ir para UM dos dois lados em JSON, e o `serde` escolhe objeto). Impacto
	   prático BAIXO (a maioria dos consumidores JSON trata `{}`/`[]` vazios de forma equivalente) e
	   corrigir exigiria um encoder JSON autoral só para este caso -- fora do escopo desta sub-leva
	   ("JSON sobre `@lune/serde`", não um encoder próprio). Declarado aqui e no relatório da tarefa,
	   nunca corrigido silenciosamente nem escondido.

	## UrlEncode -- percent-encoding CONFIRMADO byte-a-byte contra o exemplo literal da doc oficial

	Doc oficial (pesquisa, item B.7): `"https://www.roblox.com/discover#/"` ->
	`"https%3A%2F%2Fwww%2Eroblox%2Ecom%2Fdiscover%23%2F"` -- note que até `.` vira `%2E` (mais
	agressivo que `encodeURIComponent` do JS, que preserva `.`). A regra `[^%w]` (só letra/dígito
	ASCII preservado, QUALQUER outro byte vira `%XX` maiúsculo) foi verificada à MÃO contra esse
	exemplo inteiro nesta tarefa (todo caractere não-alfanumérico do exemplo -- `:`, `/`, `.`, `#` --
	aparece percent-encoded, e SÓ eles) -- bate exatamente, caractere por caractere. Espaço não tem
	exemplo oficial testado (vira `%20` por esta regra, nunca `+` -- a doc não descreve
	`application/x-www-form-urlencoded`, é percent-encoding de URL) -- tratado como extrapolação
	direta da MESMA regra confirmada, não uma suposição nova.

	## GenerateGUID -- formato confirmado, NÃO é RFC 4122 exato (mesma fidelidade já aceita em
	## `runtime` para `DataModel.JobId`)

	Exemplos literais da doc oficial (pesquisa, item B.6): com chaves,
	`"{94b717b2-d54f-4340-a504-bd809ef5bf5c}"`; sem chaves, `"db454790-7563-44ed-ab4b-397ff5df737b"`
	-- hexadecimal MINÚSCULO, formato `8-4-4-4-12`, chaves OPCIONAIS (`wrapInCurlyBraces`, default
	`true` no dump: `GenerateGUID(wrapInCurlyBraces: bool = true): string`). Funciona
	INDEPENDENTEMENTE de `HttpEnabled` (confirmado na doc, "Funciona independente de HttpEnabled") --
	por isso `Methods.GenerateGUID`, abaixo, NUNCA chama `assertHttpEnabled`. Não força os bits de
	versão/variante de um UUIDv4 RFC 4122 de verdade -- MESMA decisão, pelo MESMO motivo, já tomada
	e documentada por `generateProcessGuid`/`randomHexDigit` em `src/runtime/DataModel.luau`
	(`task-runtime-034`, para `game.JobId`): "suficiente para ser praticamente único... nunca para
	uma prova criptográfica". Esse gerador de `runtime` é `local function` module-privada (não
	reexportada por `src/runtime/init.luau`) -- `services` não pode alcançá-la (contrato de
	território: só a API pública de `runtime`), então este módulo reimplementa a MESMA técnica
	(dígito hex aleatório por `math.random(0, 15)`, sem `math.randomseed` explícito -- o próprio
	`runtime` já confirmou empiricamente que o Lune 0.10.5 semeia `math.random` de forma distinta
	por processo sozinho) de forma independente, não por desleixo de reaproveitamento.

	## `GetAsync`/`PostAsync`/`RequestAsync` -- erram com a família "HTTP não habilitado"

	`assertHttpEnabled`, abaixo, lê `HttpEnabled` via `Runtime.Instance.GetPropertyRaw` (nunca via
	schema -- é ReadOnly, mas a LEITURA por dentro do próprio `services` não precisa passar pelo
	`__index` da instância) e erra com `HTTP_NOT_ENABLED_MESSAGE` se for `false` -- o ÚNICO estado
	alcançável nesta sub-leva (não existe `--allow-http` ainda; task-services-026 é quem vai
	introduzir o caminho que liga a flag via `SetPropertyRaw`). String da mensagem: APROXIMAÇÃO DE
	BOA-FÉ, família Roblox, SEM prefixo `[LuauBench]` (tem contraparte real) -- pesquisa
	(pesquisa-http-messaging-2026-09-05.md, "Pontos NÃO CONFIRMADOS"): "String de erro exata para
	HttpEnabled = false" está listada como NÃO CONFIRMADA; DevForum cita só o TÍTULO "HTTP requests
	are not enabled" sem reproduzir o texto completo de forma confiável. Mesmo protocolo já em uso
	para `Instance.new` de classe desconhecida (`src/services/init.luau`,
	`Unable to create an Instance of type "..."`): aproximação plausível e curta, nunca apresentada
	como certeza.

	Os três métodos são construídos para ficarem TESTÁVEIS nos dois ramos SEM precisar de
	`cli`/flag nenhuma: o spec força `HttpEnabled = true` via `Runtime.Instance.SetPropertyRaw`
	(mesma via de engenharia) para alcançar o segundo ramo -- que erra `[LuauBench] ... not
	simulated by LuauBench yet` nomeando `task-services-026`, porque a REDE DE VERDADE não é desta
	sub-leva (nenhum destes três métodos chama `net.request`, nem faz qualquer I/O). Isto NÃO é o
	stub genérico do `ClassBuilder` (que dispararia se o método nem estivesse em `behavior.Methods`)
	-- é uma implementação PRÓPRIA, deliberadamente sem rede, que documenta ONDE a rede de verdade
	vai entrar.

	## `GetSecret` / `CreateWebStreamClient` -- SEM entrada em `Methods`, de propósito

	Sobrevivem ao filtro do gerador (`Security None`, `Capabilities [Network]` -- `Network` é
	grantable, não reserved, ver `tools/capabilities.lock.json`) mas ficam com o stub
	`[LuauBench] HttpService:GetSecret()/CreateWebStreamClient() ... not simulated by LuauBench yet`
	que `ClassBuilder.Build` já instala sozinho para todo `MethodNames` sem implementação (regra 03)
	-- nenhum dos dois é usado por `ProfileStore`/o caso de uso central do projeto, e `GetSecret`
	depende de Secrets do Open Cloud (fora do escopo local-first desta fase).

	Depende de: `../../runtime` (tipos + `GetPropertyRaw`), `../Types` (`Behavior`), `@lune/serde`
	(JSON). Estado: NENHUM -- `HttpService` é Service singleton sem estado próprio além da
	propriedade `HttpEnabled` (que já mora na instância, via schema).
]]

local serde = require("@lune/serde")
local Runtime = require("../../runtime")
local Types = require("../Types")

-- Ver cabeçalho, "GetAsync/PostAsync/RequestAsync" -- aproximação de boa-fé, string exata NÃO
-- CONFIRMADA (pesquisa-http-messaging-2026-09-05.md, "Pontos NÃO CONFIRMADOS").
local HTTP_NOT_ENABLED_MESSAGE = "Http requests are not enabled. Enable via game settings"

-- Ver cabeçalho, item 2 ("JSONEncode... referência cíclica"). Aproximação de boa-fé -- a doc
-- oficial confirma QUE erra ("a cyclical reference... will cause an error"), mas não cita a
-- string exata (pesquisa, item B.5: só o comportamento é confirmado, não o texto).
local CYCLIC_REFERENCE_MESSAGE = "Argument 1 to JSONEncode contains a table which references itself (cyclic reference)"

-- Nível 2: culpa quem chamou esta função diretamente (Methods.GetAsync/PostAsync/RequestAsync,
-- abaixo) -- mesma convenção já em uso por `assertValidTopic` em `./MessagingService.luau`.
local function assertHttpEnabled(self: Runtime.Instance): ()
	local enabled = Runtime.Instance.GetPropertyRaw(self, "HttpEnabled")
	if enabled ~= true then
		error(HTTP_NOT_ENABLED_MESSAGE, 2)
	end
end

-- ================================================================================================
-- JSONEncode -- detecção de ciclo ESCRITA À MÃO (ver cabeçalho, item 2) + delegação a `serde` para
-- a codificação de verdade.
-- ================================================================================================

-- Mesma técnica de `checkSerializableRec` em `../datastore/Value.luau`: `seen[value] = true` antes
-- de recursar para dentro de um valor-tabela, `seen[value] = nil` depois -- detecta só CICLOS DE
-- ANCESTRALIDADE (a mesma tabela reaparecendo no PRÓPRIO caminho de recursão), nunca uma referência
-- compartilhada não-cíclica entre dois ramos irmãos (que o Roblox real também NÃO rejeita -- só
-- ciclo verdadeiro causa erro).
local function hasCyclicReference(value: unknown, seen: { [unknown]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end

	if seen[value] then
		return true
	end
	seen[value] = true

	local generic = value :: { [unknown]: unknown }
	local found = false
	for key, child in generic do
		if hasCyclicReference(key, seen) or hasCyclicReference(child, seen) then
			found = true
			break
		end
	end

	seen[value] = nil
	return found
end

-- Corta a stack trace multi-linha que `tostring` de um erro nativo do Lune/Rust produz (mesmo
-- tratamento que `src/cli/JsonValue.luau` já documenta para o mesmo tipo de erro de `serde`) --
-- nunca vaza o formato interno do parser para o script do usuário.
local function firstLineOf(err: unknown): string
	local text = tostring(err)
	return string.match(text, "^[^\n]*") or text
end

-- ================================================================================================
-- UrlEncode -- ver cabeçalho: `[^%w]` confirmado byte-a-byte contra o exemplo literal da doc.
-- ================================================================================================

local function percentEncodeByte(char: string): string
	return string.format("%%%02X", string.byte(char) :: number)
end

-- ================================================================================================
-- GenerateGUID -- ver cabeçalho: formato confirmado, não é RFC 4122 exato de propósito.
-- ================================================================================================

local function randomHexDigit(): string
	return string.format("%x", math.random(0, 15))
end

local function generateGuidDigits(): string
	local segmentLengths = { 8, 4, 4, 4, 12 }
	local segments: { string } = {}
	for _, length in segmentLengths do
		local chars = table.create(length)
		for i = 1, length do
			chars[i] = randomHexDigit()
		end
		table.insert(segments, table.concat(chars))
	end
	return table.concat(segments, "-")
end

-- Anotação explícita de `{ [string]: unknown }` -- mesmo padrão de `RunService.luau`/
-- `DataStoreService.luau`/`MessagingService.luau`.
local Methods: { [string]: unknown } = {
	--[[
		Doc oficial: `JSONEncode(input: Variant): string`. Ver cabeçalho, itens 2/3/4 para as
		divergências encontradas e como cada uma foi tratada (ciclo: escrito à mão; inf/NaN:
		declarado; chaves mistas/tabela vazia: nativo do serde, já correto).
	]]
	JSONEncode = function(_self: Runtime.Instance, input: unknown): string
		if hasCyclicReference(input, {}) then
			error(CYCLIC_REFERENCE_MESSAGE, 2)
		end

		local ok, encodedOrError = pcall(function(): string
			return serde.encode("json", input)
		end)
		if not ok then
			-- Alcançável para tipo não serializável (função/thread/userdata/buffer -- confirmado
			-- rodando: `serde.encode` erra nativamente para esses casos, ver cabeçalho). Mensagem
			-- RETRADUZIDA, nunca a crua do Rust.
			error(`Unable to encode value to JSON: {firstLineOf(encodedOrError)}`, 2)
		end
		return encodedOrError
	end,

	--[[
		Doc oficial: `JSONDecode(input: string): Variant`. JSON inválido ERRA (confirmado rodando
		e na doc oficial) -- nunca devolve `nil`. Mensagem RETRADUZIDA (ver cabeçalho, item 1).
	]]
	JSONDecode = function(_self: Runtime.Instance, input: string): unknown
		if type(input) ~= "string" then
			error(`invalid argument #1 to 'JSONDecode' (string expected, got {type(input)})`, 2)
		end

		local ok, decodedOrError = pcall(function(): unknown
			return serde.decode("json", input)
		end)
		if not ok then
			error(`Unable to parse JSON: {firstLineOf(decodedOrError)}`, 2)
		end
		return decodedOrError
	end,

	--[[
		Doc oficial: `UrlEncode(input: string): string`. Ver cabeçalho -- percent-encoding
		confirmado byte-a-byte contra o exemplo literal da doc oficial.
	]]
	UrlEncode = function(_self: Runtime.Instance, input: string): string
		if type(input) ~= "string" then
			error(`invalid argument #1 to 'UrlEncode' (string expected, got {type(input)})`, 2)
		end

		local encoded = string.gsub(input, "[^%w]", percentEncodeByte)
		return encoded
	end,

	--[[
		Doc oficial: `GenerateGUID(wrapInCurlyBraces: bool = true): string`. Funciona
		INDEPENDENTE de `HttpEnabled` (ver cabeçalho) -- SEM `assertHttpEnabled` de propósito.
	]]
	GenerateGUID = function(_self: Runtime.Instance, wrapInCurlyBraces: boolean?): string
		if wrapInCurlyBraces ~= nil and type(wrapInCurlyBraces) ~= "boolean" then
			error(`invalid argument #1 to 'GenerateGUID' (boolean expected, got {type(wrapInCurlyBraces)})`, 2)
		end

		local guid = generateGuidDigits()
		local shouldWrap = if wrapInCurlyBraces == nil then true else wrapInCurlyBraces
		if shouldWrap then
			return "{" .. guid .. "}"
		end
		return guid
	end,

	--[[
		Doc oficial: `GetAsync(url, nocache, headers): string` -- Yields, `Security None`,
		`Capabilities [Network]`. Ver cabeçalho, "GetAsync/PostAsync/RequestAsync": SEM REDE nesta
		sub-leva -- `assertHttpEnabled` erra sempre (único estado alcançável); o `error` seguinte
		documenta onde a rede real entra (task-services-026) para o caso, hoje inalcançável por
		qualquer `cli`, de `HttpEnabled` estar `true`.
	]]
	GetAsync = function(self: Runtime.Instance, _url: unknown, _nocache: boolean?, _headers: unknown): string
		assertHttpEnabled(self)
		error("[LuauBench] HttpService:GetAsync() real network requests are not simulated by LuauBench yet (see task-services-026)", 2)
	end,

	-- Doc oficial: `PostAsync(url, data, content_type, compress, headers): string` -- mesma
	-- disciplina de `GetAsync`, acima.
	PostAsync = function(
		self: Runtime.Instance,
		_url: unknown,
		_data: string,
		_contentType: unknown,
		_compress: boolean?,
		_headers: unknown
	): string
		assertHttpEnabled(self)
		error("[LuauBench] HttpService:PostAsync() real network requests are not simulated by LuauBench yet (see task-services-026)", 2)
	end,

	-- Doc oficial: `RequestAsync(requestOptions: Dictionary): Dictionary` -- mesma disciplina de
	-- `GetAsync`, acima.
	RequestAsync = function(self: Runtime.Instance, _requestOptions: unknown): unknown
		assertHttpEnabled(self)
		error("[LuauBench] HttpService:RequestAsync() real network requests are not simulated by LuauBench yet (see task-services-026)", 2)
	end,
}

local HttpServiceBehavior: Types.Behavior = {
	Methods = Methods,
}

return HttpServiceBehavior
