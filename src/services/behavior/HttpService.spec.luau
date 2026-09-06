--!strict

--[[
	Teste dedicado de `./HttpService.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o acceptance de task-services-022 (sub-leva A): `game:GetService('HttpService')` devolve
	instância; `JSONEncode`/`JSONDecode`/`UrlEncode`/`GenerateGUID` funcionam e erram como o Roblox
	nos casos inválidos (incluindo a divergência do `serde.encode` sobre referência cíclica,
	corrigida à mão -- ver cabeçalho de `./HttpService.luau`, item 2); `HttpEnabled` lê `false` e
	escrever erra; `GetAsync`/`PostAsync`/`RequestAsync` erram com a família "HTTP não habilitado";
	NENHUMA chamada de rede acontece (verificado tanto por leitura de código quanto por uma
	checagem automática do texto-fonte, abaixo, de que `@lune/net` nunca é `require`d).

	Roda com `lune run src/services/behavior/HttpService.spec.luau`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

Services.Register()

local function makeHttpService(): Dynamic
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({ scheduler = scheduler, dataModel = game })
	return (game:GetService("HttpService") :: unknown) :: Dynamic
end

test("SEM REDE: o texto-fonte de ./HttpService.luau nunca CHAMA require(\"@lune/net\") (verificação mecânica do acceptance -- busca só a chamada de require, não a menção em comentário)", function()
	local source = fs.readFile("src/services/behavior/HttpService.luau")
	assert(
		string.find(source, 'require("@lune/net")', 1, true) == nil,
		'./HttpService.luau NUNCA deveria conter require("@lune/net") -- SEM REDE NENHUMA nesta sub-leva (task-services-022)'
	)
end)

test("game:GetService('HttpService') devolve uma instância -- singleton do processo (Service, NotCreatable)", function()
	local httpService = makeHttpService()
	assert(httpService ~= nil, "HttpService deveria existir depois de Bootstrap")
	local instance = (httpService :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "HttpService", "ClassName deveria ser HttpService")
end)

test("HttpEnabled lê false (default do dump) -- semeado pelo schema gerado, sem behavior explícito", function()
	local httpService = makeHttpService()
	assert(httpService.HttpEnabled == false, `HttpEnabled deveria ser false por default, recebeu {tostring(httpService.HttpEnabled)}`)
end)

test("escrever HttpEnabled ERRA -- ReadOnly (dump: Security Write=LocalUserSecurity, a rede é opt-in de quem roda o LuauBench, nunca do script)", function()
	local httpService = makeHttpService()
	local ok, err = pcall(function()
		httpService.HttpEnabled = true
	end)
	assert(not ok, "escrever HttpService.HttpEnabled deveria erro -- é ReadOnly")
	assert(
		string.find(tostring(err), "read only", 1, true) ~= nil,
		`mensagem deveria citar "read only" (família Roblox de propriedade ReadOnly), recebeu: {err}`
	)
end)

test("JSONEncode/JSONDecode fazem um round-trip fiel para tabela simples", function()
	local httpService = makeHttpService()
	local jsonEncode = httpService.JSONEncode :: (self: Dynamic, input: unknown) -> string
	local jsonDecode = httpService.JSONDecode :: (self: Dynamic, input: string) -> unknown

	local encoded = jsonEncode(httpService, { name = "Alice", level = 5 })
	assert(type(encoded) == "string", "JSONEncode deveria devolver string")
	assert(string.find(encoded, '"name":"Alice"', 1, true) ~= nil, `encoded deveria conter name:Alice, recebeu: {encoded}`)

	local decoded = jsonDecode(httpService, encoded) :: { [string]: unknown }
	assert(decoded.name == "Alice", `decoded.name deveria ser "Alice", recebeu {tostring(decoded.name)}`)
	assert(decoded.level == 5, `decoded.level deveria ser 5, recebeu {tostring(decoded.level)}`)
end)

test("JSONEncode de array Lua produz um array JSON, e o round-trip preserva a ordem", function()
	local httpService = makeHttpService()
	local jsonEncode = httpService.JSONEncode :: (self: Dynamic, input: unknown) -> string
	local jsonDecode = httpService.JSONDecode :: (self: Dynamic, input: string) -> unknown

	local encoded = jsonEncode(httpService, { 10, 20, 30 })
	assert(encoded == "[10,20,30]", `esperava "[10,20,30]", recebeu {encoded}`)

	local decoded = jsonDecode(httpService, encoded) :: { number }
	assert(#decoded == 3 and decoded[1] == 10 and decoded[2] == 20 and decoded[3] == 30, "round-trip do array deveria preservar ordem e valores")
end)

test("JSONDecode de JSON INVÁLIDO ERRA -- nunca devolve nil, como o Roblox real", function()
	local httpService = makeHttpService()
	local jsonDecode = httpService.JSONDecode :: (self: Dynamic, input: string) -> unknown

	local ok, err = pcall(function()
		jsonDecode(httpService, "{not valid json")
	end)
	assert(not ok, "JSONDecode de JSON inválido deveria erro")
	assert(
		string.find(tostring(err), "Unable to parse JSON", 1, true) ~= nil,
		`mensagem deveria citar "Unable to parse JSON" (retraduzida, nunca a crua do parser), recebeu: {err}`
	)
end)

test("JSONEncode de uma tabela com REFERÊNCIA CÍCLICA ERRA -- descoberta desta tarefa: serde.encode do Lune NÃO erra sozinho (omite o campo em silêncio), então este módulo detecta o ciclo à mão", function()
	local httpService = makeHttpService()
	local jsonEncode = httpService.JSONEncode :: (self: Dynamic, input: unknown) -> string

	local cyclic: { [string]: unknown } = {}
	cyclic.self = cyclic

	local ok, err = pcall(function()
		jsonEncode(httpService, cyclic)
	end)
	assert(not ok, "JSONEncode de tabela com referência cíclica deveria erro (família Roblox, doc oficial confirma que causa erro)")
	assert(
		string.find(tostring(err), "cyclic reference", 1, true) ~= nil,
		`mensagem deveria citar "cyclic reference", recebeu: {err}`
	)
end)

test("JSONEncode de um CICLO MÚTUO (A<->B, dois níveis) TAMBÉM erra", function()
	local httpService = makeHttpService()
	local jsonEncode = httpService.JSONEncode :: (self: Dynamic, input: unknown) -> string

	local a: { [string]: unknown } = {}
	local b: { [string]: unknown } = {}
	a.b = b
	b.a = a

	local ok = pcall(function()
		jsonEncode(httpService, a)
	end)
	assert(not ok, "ciclo mútuo de dois níveis (A.b = B, B.a = A) também deveria erro")
end)

test("JSONEncode de DUAS referências NÃO-cíclicas à MESMA sub-tabela (irmãos compartilhando referência) NÃO erra -- não é um ciclo de verdade", function()
	local httpService = makeHttpService()
	local jsonEncode = httpService.JSONEncode :: (self: Dynamic, input: unknown) -> string

	local shared = { x = 1 }
	local ok, result = pcall(function()
		return jsonEncode(httpService, { first = shared, second = shared })
	end)
	assert(ok, `duas referências irmãs à mesma sub-tabela NÃO deveriam ser tratadas como ciclo, erro: {tostring(result)}`)
end)

test("UrlEncode bate EXATAMENTE o exemplo literal da doc oficial (percent-encoding agressivo -- até '.' vira %2E)", function()
	local httpService = makeHttpService()
	local urlEncode = httpService.UrlEncode :: (self: Dynamic, input: string) -> string

	local encoded = urlEncode(httpService, "https://www.roblox.com/discover#/")
	assert(
		encoded == "https%3A%2F%2Fwww%2Eroblox%2Ecom%2Fdiscover%23%2F",
		`deveria bater o exemplo literal da doc oficial, recebeu: {encoded}`
	)
end)

test("UrlEncode preserva alfanuméricos sem tocar (nenhum %XX neles)", function()
	local httpService = makeHttpService()
	local urlEncode = httpService.UrlEncode :: (self: Dynamic, input: string) -> string

	local encoded = urlEncode(httpService, "abcXYZ789")
	assert(encoded == "abcXYZ789", `alfanumérico não deveria ser alterado, recebeu: {encoded}`)
end)

test("GenerateGUID() (default true) devolve string ENVOLTA em chaves, formato 8-4-4-4-12 hex minúsculo", function()
	local httpService = makeHttpService()
	local generateGuid = httpService.GenerateGUID :: (self: Dynamic, wrapInCurlyBraces: boolean?) -> string

	local guid = generateGuid(httpService, nil)
	assert(
		string.match(guid, "^{%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x}$") ~= nil,
		`GenerateGUID() deveria bater o formato {"{"}8-4-4-4-12{"}"} hex minúsculo com chaves, recebeu: {guid}`
	)
end)

test("GenerateGUID(false) devolve string SEM chaves, mesmo formato 8-4-4-4-12", function()
	local httpService = makeHttpService()
	local generateGuid = httpService.GenerateGUID :: (self: Dynamic, wrapInCurlyBraces: boolean?) -> string

	local guid = generateGuid(httpService, false)
	assert(
		string.match(guid, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil,
		`GenerateGUID(false) deveria bater o formato 8-4-4-4-12 hex minúsculo SEM chaves, recebeu: {guid}`
	)
end)

test("GenerateGUID funciona INDEPENDENTE de HttpEnabled (dump: 'Funciona independente de HttpEnabled') -- HttpEnabled continua false aqui", function()
	local httpService = makeHttpService()
	assert(httpService.HttpEnabled == false, "pré-condição: HttpEnabled deveria continuar false neste teste")

	local generateGuid = httpService.GenerateGUID :: (self: Dynamic, wrapInCurlyBraces: boolean?) -> string
	local ok = pcall(function()
		return generateGuid(httpService, true)
	end)
	assert(ok, "GenerateGUID NÃO deveria depender de HttpEnabled -- deveria funcionar mesmo com HTTP desabilitado")
end)

test("duas chamadas de GenerateGUID devolvem valores DIFERENTES (aleatório, não uma constante)", function()
	local httpService = makeHttpService()
	local generateGuid = httpService.GenerateGUID :: (self: Dynamic, wrapInCurlyBraces: boolean?) -> string

	local first = generateGuid(httpService, false)
	local second = generateGuid(httpService, false)
	assert(first ~= second, "duas chamadas consecutivas de GenerateGUID deveriam devolver GUIDs diferentes")
end)

test("GetAsync ERRA com a família 'HTTP não habilitado' quando HttpEnabled é false (único estado alcançável nesta sub-leva)", function()
	local httpService = makeHttpService()
	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

	local ok, err = pcall(function()
		getAsync(httpService, "https://example.com", nil, nil)
	end)
	assert(not ok, "GetAsync deveria erro quando HttpEnabled é false")
	assert(
		string.find(tostring(err), "not enabled", 1, true) ~= nil,
		`mensagem deveria citar "not enabled" (família Roblox), recebeu: {err}`
	)
end)

test("PostAsync ERRA com a família 'HTTP não habilitado' quando HttpEnabled é false", function()
	local httpService = makeHttpService()
	local postAsync = httpService.PostAsync :: (self: Dynamic, url: unknown, data: string, contentType: unknown, compress: boolean?, headers: unknown) -> string

	local ok, err = pcall(function()
		postAsync(httpService, "https://example.com", "{}", nil, nil, nil)
	end)
	assert(not ok, "PostAsync deveria erro quando HttpEnabled é false")
	assert(
		string.find(tostring(err), "not enabled", 1, true) ~= nil,
		`mensagem deveria citar "not enabled" (família Roblox), recebeu: {err}`
	)
end)

test("RequestAsync ERRA com a família 'HTTP não habilitado' quando HttpEnabled é false", function()
	local httpService = makeHttpService()
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> unknown

	local ok, err = pcall(function()
		requestAsync(httpService, { Url = "https://example.com", Method = "GET" })
	end)
	assert(not ok, "RequestAsync deveria erro quando HttpEnabled é false")
	assert(
		string.find(tostring(err), "not enabled", 1, true) ~= nil,
		`mensagem deveria citar "not enabled" (família Roblox), recebeu: {err}`
	)
end)

test("com HttpEnabled forçado para true (via SetPropertyRaw, via de engenharia -- simula a futura --allow-http), os 3 métodos de rede passam a errar [LuauBench] nomeando task-services-026, NUNCA fazem I/O de verdade", function()
	local httpService = makeHttpService()
	local instance = (httpService :: unknown) :: Runtime.Instance
	Runtime.Instance.SetPropertyRaw(instance, "HttpEnabled", true)

	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string
	local okGet, errGet = pcall(function()
		getAsync(httpService, "https://example.com", nil, nil)
	end)
	assert(not okGet, "GetAsync deveria continuar errando mesmo com HttpEnabled == true (rede de verdade não é desta sub-leva)")
	assert(
		string.find(tostring(errGet), "[LuauBench]", 1, true) ~= nil and string.find(tostring(errGet), "task-services-026", 1, true) ~= nil,
		`mensagem deveria ser [LuauBench] nomeando task-services-026 (rede real ainda não simulada), recebeu: {errGet}`
	)

	local postAsync = httpService.PostAsync :: (self: Dynamic, url: unknown, data: string, contentType: unknown, compress: boolean?, headers: unknown) -> string
	local okPost, errPost = pcall(function()
		postAsync(httpService, "https://example.com", "{}", nil, nil, nil)
	end)
	assert(not okPost, "PostAsync deveria continuar errando mesmo com HttpEnabled == true")
	assert(string.find(tostring(errPost), "[LuauBench]", 1, true) ~= nil, `mensagem deveria ser [LuauBench], recebeu: {errPost}`)

	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> unknown
	local okRequest, errRequest = pcall(function()
		requestAsync(httpService, { Url = "https://example.com" })
	end)
	assert(not okRequest, "RequestAsync deveria continuar errando mesmo com HttpEnabled == true")
	assert(string.find(tostring(errRequest), "[LuauBench]", 1, true) ~= nil, `mensagem deveria ser [LuauBench], recebeu: {errRequest}`)
end)

test("GetSecret e CreateWebStreamClient ficam com o stub [LuauBench] do ClassBuilder -- não implementados de propósito", function()
	local httpService = makeHttpService()

	local getSecret = httpService.GetSecret :: (self: Dynamic, key: string) -> unknown
	local okSecret, errSecret = pcall(function()
		getSecret(httpService, "some-key")
	end)
	assert(not okSecret, "GetSecret deveria erro -- não implementado nesta sub-leva")
	assert(
		string.find(tostring(errSecret), "not simulated by LuauBench yet", 1, true) ~= nil,
		`mensagem deveria ser o stub padrão do ClassBuilder, recebeu: {errSecret}`
	)

	local createWebStreamClient = httpService.CreateWebStreamClient :: (self: Dynamic, streamClientType: unknown, requestOptions: unknown) -> unknown
	local okStream, errStream = pcall(function()
		createWebStreamClient(httpService, nil, nil)
	end)
	assert(not okStream, "CreateWebStreamClient deveria erro -- não implementado nesta sub-leva")
	assert(
		string.find(tostring(errStream), "not simulated by LuauBench yet", 1, true) ~= nil,
		`mensagem deveria ser o stub padrão do ClassBuilder, recebeu: {errStream}`
	)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
