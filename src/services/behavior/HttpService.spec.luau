--!strict

--[[
	Teste dedicado de `./HttpService.luau` (regra 01: teste na mesma tarefa da lógica que cobre).

	Sub-leva A (task-services-022, MANTIDO): `game:GetService('HttpService')` devolve instância;
	`JSONEncode`/`JSONDecode`/`UrlEncode`/`GenerateGUID` funcionam e erram como o Roblox nos casos
	inválidos; `HttpEnabled` lê `false` por default e escrever erra.

	Sub-leva B (task-services-026, NOVO nesta tarefa): `AllowHttp`/`AllowHttpLocal` via
	`Services.BootstrapOptions` fazem `HttpEnabled` nascer `true` de verdade (mecanismo de
	produção -- `Initialize`, não mais só `SetPropertyRaw` manual de teste); destino loopback/
	link-local/privado é recusado sem `AllowHttpLocal` e aceito com ela, SEM depender de rede
	real (a checagem acontece antes de qualquer `net.request`); `GetAsync`/`PostAsync`/
	`RequestAsync` fazem requisição REAL contra um servidor HTTP LOCAL (`@lune/net`'s `net.serve`,
	nunca um serviço externo -- ver "SERVIDOR DE TESTE LOCAL", abaixo) quando a permissão está
	ligada; host inexistente erra com mensagem traduzida, NUNCA a crua do SO; `Timeout` é aceito e
	ignorado.

	REMOVIDOS desta tarefa (obsoletos, contradiziam o novo comportamento por desenho):
	- "SEM REDE: o texto-fonte de ./HttpService.luau nunca chama require(\"@lune/net\")" -- esta
	  sub-leva ADICIONA `@lune/net` de propósito (é o ponto inteiro da tarefa).
	- "com HttpEnabled forçado para true... os 3 métodos de rede passam a errar [LuauBench]
	  nomeando task-services-026" -- essa mensagem de stub documentava EXATAMENTE a lacuna que
	  esta tarefa fecha; substituída pelos testes de sucesso/recusa abaixo.

	SERVIDOR DE TESTE LOCAL: os testes de SUCESSO (requisição completando de verdade) sobem um
	servidor HTTP próprio via `net.serve` (Lune, mesmo módulo usado pela implementação) em
	"127.0.0.1", NUNCA dependendo de nenhum serviço externo -- consistente com "specs cobrindo
	cada item sem depender de rede externa" (acceptance desta tarefa). Como "127.0.0.1" É um
	destino que o ENDURECIMENTO desta própria tarefa bloquearia por padrão, esses testes passam
	`AllowHttpLocal = true` de propósito -- isso também exercita, de quebra, o caminho "aceito com
	a segunda permissão" do acceptance. O único teste que precisa de alcance de rede de verdade
	(fora de "127.0.0.1") é o de HOST INEXISTENTE, abaixo -- documentado no próprio teste.

	CORREÇÃO DE SSRF (retomada -- revisor-services reprovou a comparação original de destino
	privado, ver cabeçalho de ./HttpService.luau, "CORREÇÃO DE SSRF"): `BLOCKED_DESTINATIONS`
	ganhou as 6 formas de bypass reportadas (decimal/octal/hex/abreviada de 127.0.0.1,
	IPv4-mapped IPv6 comprimido em duas grafias e expandido) + "0.0.0.0" -- todas RECUSADAS sem
	`AllowHttpLocal` pelo mesmo loop já existente. A ACEITAÇÃO com `AllowHttpLocal` é testada em
	dois grupos, por causa de uma LIMITAÇÃO DE PLATAFORMA confirmada empiricamente (Windows, Lune
	0.10.5): decimal/octal/hex/abreviada fazem round-trip REAL contra o servidor local (o SO
	conecta normalmente); IPv4-mapped IPv6 e "0.0.0.0" só confirmam que o GATE não recusa (a
	conexão real falha no Windows com "os error 10049", "the requested address is not valid in
	its context" -- falha de SOCKET do SO, reproduzível chamando `net.request` puro sem nenhuma
	checagem do LuauBench no meio, nada a ver com este módulo).

	Achado do orquestrador (par de task-cli-026): `OnHttpRequest` (canal de auditoria de saída,
	`Services.BootstrapOptions`/`Context.NotifyHttpRequest`) -- testado chamado com `(method, host)`
	corretos numa requisição real (`GetAsync` e `RequestAsync` com `Method` não-GET, para confirmar
	que não é hardcoded), e NÃO chamado quando a requisição é recusada antes de tocar a rede
	(`HttpEnabled=false` e destino privado sem `AllowHttpLocal`).

	Roda com `lune run src/services/behavior/HttpService.spec.luau`.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
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

type MakeOptions = {
	AllowHttp: boolean?,
	AllowHttpLocal: boolean?,
	-- Correção coordenada com task-cli-026 (ver ../Types.luau/../Context.luau): canal de
	-- auditoria, `nil` == sem auditoria (comportamento de hoje). Testado abaixo, seção "canal de
	-- auditoria OnHttpRequest".
	OnHttpRequest: ((method: string, host: string) -> ())?,
}

-- Devolve `(httpService, scheduler)` -- a maioria dos testes só usa o primeiro valor (Lua ignora
-- o resto quando atribuído a uma única `local`), mas os testes de rede REAL (que precisam driblar
-- o scheduler para deixar `AsyncCall.Yield`/`net.request` completarem) usam os dois.
local function makeHttpService(options: MakeOptions?): (Dynamic, Runtime.Scheduler)
	local resolved: MakeOptions = options or {}
	local scheduler = Runtime.Scheduler.new()
	local game = Runtime.DataModel.new()
	Services.Bootstrap({
		scheduler = scheduler,
		dataModel = game,
		AllowHttp = resolved.AllowHttp,
		AllowHttpLocal = resolved.AllowHttpLocal,
		OnHttpRequest = resolved.OnHttpRequest,
	})
	local httpService = (game:GetService("HttpService") :: unknown) :: Dynamic
	return httpService, scheduler
end

--[[
	`GetAsync`/`PostAsync`/`RequestAsync` reais passam por `AsyncCall.Yield`, que só aceita ser
	chamado de uma thread GERIDA pelo Scheduler (ver ../AsyncCall.luau) -- a thread principal
	deste próprio arquivo de spec (criada por `lune run`) NÃO é uma dessas threads. Por isso todo
	teste que alcança rede de verdade roda `fn` dentro de `scheduler:Spawn`, e dirige
	`scheduler:Run` até a thread terminar -- mesmo padrão verificado empiricamente nesta tarefa
	(script de prova descartável, não versionado) para confirmar que `net.request` compõe com o
	Scheduler sem travar. Watchdog de 10s de parede para a suíte nunca travar para sempre caso
	algo pare de resumir.
]]
local function runOnScheduler(scheduler: Runtime.Scheduler, fn: () -> ()): (boolean, unknown)
	local finished = false
	local ok = true
	local errResult: unknown = nil

	scheduler:Spawn(function()
		-- `pcall(fn)` com `fn: () -> ()` tipa o resultado como só `(boolean)` -- sem uma segunda
		-- posição de retorno para o erro, porque `fn` não declara nenhum retorno de sucesso
		-- (Luau não modela "o segundo valor só existe no ramo de erro"). Envolver `fn` numa
		-- closure que declara retornar `boolean` (sempre `true` no sucesso) dá a `pcall` uma
		-- aridade de 2 -- o valor real devolvido no ramo de erro (a mensagem) ainda chega aqui
		-- corretamente em runtime, só a ANOTAÇÃO estática do segundo valor fica `boolean` (nunca
		-- lida como tal -- é atribuída direto a `errResult: unknown`, que aceita qualquer coisa).
		local threadOk, threadErr = pcall(function(): boolean
			fn()
			return true
		end)
		ok = threadOk
		errResult = threadErr
		finished = true
	end)

	local startClock = os.clock()
	scheduler:Run(function()
		return (not finished) and (os.clock() - startClock) < 10
	end)

	assert(finished, "runOnScheduler: a thread não terminou dentro do watchdog de 10s (rede travada?)")
	return ok, errResult
end

test("game:GetService('HttpService') devolve uma instância -- singleton do processo (Service, NotCreatable)", function()
	local httpService = makeHttpService()
	assert(httpService ~= nil, "HttpService deveria existir depois de Bootstrap")
	local instance = (httpService :: unknown) :: Runtime.Instance
	assert(instance.ClassName == "HttpService", "ClassName deveria ser HttpService")
end)

test("HttpEnabled lê false (default do dump) quando Bootstrap não recebe AllowHttp -- semeado pelo schema gerado", function()
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

test("JSONEncode de uma tabela com REFERÊNCIA CÍCLICA ERRA -- serde.encode do Lune NÃO erra sozinho (omite o campo em silêncio), então este módulo detecta o ciclo à mão", function()
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

test("GetAsync ERRA com a família 'HTTP não habilitado' quando HttpEnabled é false (sem AllowHttp)", function()
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

-- ================================================================================================
-- task-services-026 -- rede real, atrás do portão HttpEnabled
-- ================================================================================================

test("com AllowHttp=true em Services.Bootstrap, HttpEnabled nasce true (mecanismo de PRODUÇÃO -- Initialize lendo Context.IsHttpAllowed, não mais SetPropertyRaw manual de teste)", function()
	local httpService = makeHttpService({ AllowHttp = true })
	assert(httpService.HttpEnabled == true, `HttpEnabled deveria ser true com AllowHttp=true, recebeu {tostring(httpService.HttpEnabled)}`)
end)

test("AllowHttpLocal=true SEM AllowHttp continua ERRANDO 'not enabled' -- nunca abre a rede local sem a rede geral primeiro", function()
	local httpService = makeHttpService({ AllowHttpLocal = true })
	assert(httpService.HttpEnabled == false, "HttpEnabled deveria continuar false -- só AllowHttp controla isso, nunca AllowHttpLocal sozinho")

	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string
	local ok, err = pcall(function()
		getAsync(httpService, "http://127.0.0.1/", nil, nil)
	end)
	assert(not ok, "deveria continuar errando mesmo pedindo um destino loopback")
	assert(
		string.find(tostring(err), "not enabled", 1, true) ~= nil,
		`deveria ser o erro de HTTP não habilitado (nunca chega a checar o destino), recebeu: {tostring(err)}`
	)
end)

-- Tabela de destinos que o endurecimento (L2.2.4) deveria recusar por padrão -- cobre os 5
-- ranges do desenho mais o alias "localhost" (extensão desta tarefa, ver cabeçalho de
-- ./HttpService.luau). Todos SEM depender de rede real: a recusa acontece ANTES de
-- `AsyncCall.Yield`/`net.request` (chamada direta, fora de `runOnScheduler`, de propósito -- se
-- este teste algum dia yieldar de verdade, `AsyncCall.Yield` erraria por thread não-gerida,
-- expondo a regressão).
local BLOCKED_DESTINATIONS = {
	{ label = "127.0.0.1 (loopback IPv4)", url = "http://127.0.0.1/" },
	{ label = "127.5.5.5 (loopback IPv4, qualquer host no /8)", url = "http://127.5.5.5/" },
	{ label = "localhost (alias -- extensão desta tarefa)", url = "http://localhost/" },
	{ label = "LOCALHOST (case-insensitive)", url = "http://LOCALHOST:8080/" },
	{ label = "[::1] (loopback IPv6, forma com colchetes)", url = "http://[::1]:8080/" },
	{ label = "169.254.1.1 (link-local)", url = "http://169.254.1.1/" },
	{ label = "10.0.0.5 (privado, 10/8)", url = "http://10.0.0.5/" },
	{ label = "172.16.0.1 (privado, 172.16/12, limite inferior)", url = "http://172.16.0.1/" },
	{ label = "172.31.255.255 (privado, 172.16/12, limite superior)", url = "http://172.31.255.255/" },
	{ label = "192.168.1.1 (privado, 192.168/16)", url = "http://192.168.1.1/" },

	-- CORREÇÃO DE SSRF (revisor-services reprovou a versão anterior -- ver cabeçalho de
	-- ./HttpService.luau, "CORREÇÃO DE SSRF"): as 6 formas de bypass reportadas, todas
	-- representações alternativas de 127.0.0.1/0.0.0.0 que a versão antiga deixava passar.
	{ label = "2130706433 (DECIMAL de 127.0.0.1 -- bypass corrigido)", url = "http://2130706433/" },
	{ label = "017700000001 (OCTAL de 127.0.0.1 -- bypass corrigido)", url = "http://017700000001/" },
	{ label = "0x7f000001 (HEXADECIMAL de 127.0.0.1 -- bypass corrigido)", url = "http://0x7f000001/" },
	{ label = "127.1 (forma ABREVIADA de 127.0.0.1 -- bypass corrigido)", url = "http://127.1/" },
	{ label = "[::ffff:127.0.0.1] (IPv4-mapped IPv6, dotted-quad comprimido -- bypass corrigido)", url = "http://[::ffff:127.0.0.1]/" },
	{ label = "[::ffff:7f00:1] (IPv4-mapped IPv6, grupos hex comprimidos -- bypass corrigido)", url = "http://[::ffff:7f00:1]/" },
	{
		label = "[0000:...:ffff:7f00:0001] (IPv4-mapped IPv6, forma EXPANDIDA -- bypass corrigido)",
		url = "http://[0000:0000:0000:0000:0000:ffff:7f00:0001]/",
	},
	{ label = "0.0.0.0 (DECISÃO EXPLÍCITA: recusado por padrão -- comportamento depende do SO)", url = "http://0.0.0.0/" },

	-- 3ª RODADA DE REVISÃO (task-services-026, revisor-services-http-ssrf-round2): dois achados
	-- GRAVES novos, reproduzidos e confirmados ANTES do fix (script descartável, ver relatório da
	-- tarefa) -- ambos com a MESMA assinatura dos bypasses anteriores: o host que `extractHost`
	-- calculava divergia do host que `net.request` de fato usa.
	{
		label = "backslash como separador de autoridade (achado GRAVE #1 -- \\@ confunde host com userinfo)",
		url = "http://127.0.0.1:1\\@evil-marker.invalid/",
	},
	{ label = "::127.0.0.1 (IPv4-compatible IPv6 comprimido, achado GRAVE #2, SEM o grupo ffff:)", url = "http://[::127.0.0.1]/" },
	{ label = "::10.0.0.1 (IPv4-compatible IPv6 comprimido, achado GRAVE #2, privado 10/8)", url = "http://[::10.0.0.1]/" },
	{ label = "[::1%eth0] (loopback IPv6 com zone ID RFC 4007 -- achado BAIXO, normalização barata)", url = "http://[::1%eth0]:8080/" },

	-- CAÇA AO "4º BYPASS" (pedida explicitamente nesta rodada, ANTES de reportar pronto -- ver
	-- relatório da tarefa): mesma classe de bug do achado GRAVE #1 (extractHost divergindo do
	-- parsing real), duas formas NOVAS confirmadas rodando contra `net.request` puro com um
	-- canário `net.serve` local: (a) percent-encoding do host -- o WHATWG URL Standard
	-- percent-decodifica o host ANTES de checar se é um IPv4; (b) tab/CR/LF embutidos em QUALQUER
	-- posição da URL -- o WHATWG remove esses 3 bytes da URL inteira como um dos primeiros passos
	-- do parsing. As duas SÃO corrigidas nesta rodada (percentDecodeHost/normalizeUrlForParsing),
	-- não só reportadas.
	{ label = "%31%32%37%2e%30%2e%30%2e%31 (127.0.0.1 TODO percent-encoded -- 4º bypass, corrigido)", url = "http://%31%32%37%2e%30%2e%30%2e%31/" },
	{ label = "127%2e0%2e0%2e1 (só os PONTOS percent-encoded -- 4º bypass, corrigido)", url = "http://127%2e0%2e0%2e1/" },
	{ label = "12<TAB>7.0.0.1 (tab ASCII embutido no meio do host -- 4º bypass, corrigido)", url = "http://12\t7.0.0.1/" },
	{ label = "12<LF>7.0.0.1 (newline ASCII embutido no meio do host -- 4º bypass, corrigido)", url = "http://12\n7.0.0.1/" },
	{ label = "12<CR>7.0.0.1 (carriage return ASCII embutido no meio do host -- 4º bypass, corrigido)", url = "http://12\r7.0.0.1/" },

	-- 4ª RODADA DE REVISÃO (task-services-026) -- achado GRAVE do revisor: "?"/"#" (início de
	-- query/fragment) terminam a região de `authority` da RFC 3986 ANTES de qualquer "@" que
	-- apareça depois -- a extração anterior só cortava pela primeira "/", nunca por "?"/"#",
	-- então um "@" dentro da query/fragment ainda era lido como delimitador de userinfo/host.
	-- Todas as 8 combinações pedidas (?x@ / ?@ / #x@ / #@, com e sem porta explícita) mais o caso
	-- SEM "@" nenhum que o revisor também citou -- ver `HttpService.luau`, "4ª RODADA".
	{
		label = "?x@ SEM porta -- query com texto antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1?x@evil-marker.invalid/",
	},
	{
		label = "?x@ COM porta -- query com texto antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1:1?x@evil-marker.invalid/",
	},
	{
		label = "?@ SEM porta -- query vazia antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1?@evil-marker.invalid/",
	},
	{
		label = "?@ COM porta -- query vazia antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1:1?@evil-marker.invalid/",
	},
	{
		label = "#x@ SEM porta -- fragment com texto antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1#x@evil-marker.invalid/",
	},
	{
		label = "#x@ COM porta -- fragment com texto antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1:1#x@evil-marker.invalid/",
	},
	{
		label = "#@ SEM porta -- fragment vazio antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1#@evil-marker.invalid/",
	},
	{
		label = "#@ COM porta -- fragment vazio antes do @ (achado da 4ª rodada)",
		url = "http://127.0.0.1:1#@evil-marker.invalid/",
	},
	{
		label = "SEM @ nenhum -- só query depois do host (http://127.0.0.1?x/, citado pelo revisor)",
		url = "http://127.0.0.1?x/",
	},

	-- 5ª RODADA DE REVISÃO (task-services-026, revisor-services-http-ssrf-round4) -- achado GRAVE:
	-- IDNA/UTS46 normaliza separadores de label Unicode equivalentes ao ponto e dígitos
	-- "fullwidth" para seus equivalentes ASCII ANTES de resolver/conectar -- `extractHost`/
	-- `tryParseIPv4` (bytes ASCII crus) não reproduziam essa normalização. Corrigido por
	-- `normalizeUnicodeHostLabels` (ver HttpService.luau, perto de `isLocalDestination`). As 3
	-- primeiras formas foram CONFIRMADAS conectando de verdade em 127.0.0.1 pelo revisor (ver
	-- ALTERNATE_LOOPBACK_NOTATIONS, abaixo, para o round-trip real); a 4ª (halfwidth ideographic
	-- full stop) é o 4º separador coberto pelo fix mas não foi testada como bypass real na
	-- revisão -- coberta aqui mesmo assim, por consistência com o que o código agora normaliza.
	{
		label = "127．0．0．1 (fullwidth full stop U+FF0E no lugar do ponto -- achado da 5ª rodada)",
		url = "http://127\u{FF0E}0\u{FF0E}0\u{FF0E}1/",
	},
	{
		label = "127。0。0。1 (ideographic full stop U+3002 no lugar do ponto -- achado da 5ª rodada)",
		url = "http://127\u{3002}0\u{3002}0\u{3002}1/",
	},
	{
		label = "１２７.0.0.１ (dígitos fullwidth U+FF11/U+FF17 no lugar de 1/2/7 -- achado da 5ª rodada)",
		url = "http://\u{FF11}\u{FF12}\u{FF17}.0.0.\u{FF11}/",
	},
	{
		label = "127｡0｡0｡1 (halfwidth ideographic full stop U+FF61 -- 4º separador coberto pelo fix)",
		url = "http://127\u{FF61}0\u{FF61}0\u{FF61}1/",
	},
}

for _, destination in BLOCKED_DESTINATIONS do
	test(`GetAsync RECUSA destino privado/loopback sem AllowHttpLocal: {destination.label}`, function()
		local httpService = makeHttpService({ AllowHttp = true })
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string
		local ok, err = pcall(function()
			getAsync(httpService, destination.url, nil, nil)
		end)
		assert(not ok, `deveria recusar {destination.url} sem AllowHttpLocal`)
		local message = tostring(err)
		assert(string.find(message, "[LuauBench]", 1, true) ~= nil, `mensagem deveria ter prefixo [LuauBench] (endurecimento sem contraparte real), recebeu: {message}`)
		assert(string.find(message, "allow-http-local", 1, true) ~= nil, `mensagem deveria citar --allow-http-local, recebeu: {message}`)
	end)
end

--[[
	NÃO testado com uma tentativa de rede real (decisão deliberada, não uma lacuna esquecida):
	confirmar que "172.15.255.255"/"172.32.0.0" (fora de 172.16.0.0/12 por 1 endereço) NÃO são
	bloqueados exigiria uma conexão de verdade contra um IP público arbitrário -- que pode
	demorar dezenas de segundos para falhar (sem ICMP unreachable, o SO só desiste depois do
	timeout de conexão do próprio SO, que o Lune 0.10.5 não deixa configurar, ver divergência
	"Timeout" no cabeçalho de ./HttpService.luau) ou até "funcionar" se algum host real responder
	naquele endereço -- risco de instabilidade real na suíte, não escolhido. A cobertura da
	INCLUSÃO do range já é forte sem isso: os dois testes acima ("172.16.0.1"/"172.31.255.255",
	as DUAS bordas do range) confirmam que 172.16.0.0/12 bloqueia exatamente do primeiro ao
	último endereço -- um erro "off-by-one" que ENCOLHESSE o range teria feito um dos dois falhar
	já. Só o erro complementar (um range que VAZASSE um endereço a mais para fora) fica sem teste
	de rede dedicado; aceito como risco residual em vez de introduzir uma dependência de rede
	instável.
]]

test("RequestAsync ERRA para Method não suportado -- validado ANTES de qualquer yield/rede", function()
	local httpService = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = pcall(function()
		requestAsync(httpService, { Url = "https://example.com/", Method = "TRACE" })
	end)
	assert(not ok, "Method 'TRACE' não é suportado -- deveria erro")
	assert(string.find(tostring(err), "unsupported HTTP method", 1, true) ~= nil, `mensagem deveria citar o método não suportado, recebeu: {err}`)
end)

test("RequestAsync ERRA quando Body é especificado junto de Method GET (doc oficial: proibido com GET/HEAD)", function()
	local httpService = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = pcall(function()
		requestAsync(httpService, { Url = "https://example.com/", Method = "GET", Body = "x" })
	end)
	assert(not ok, "Body com Method GET deveria erro")
	assert(string.find(tostring(err), "Body", 1, true) ~= nil, `mensagem deveria citar 'Body', recebeu: {err}`)
end)

test("RequestAsync ERRA quando Url está ausente da tabela de opções", function()
	local httpService = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = pcall(function()
		requestAsync(httpService, { Method = "GET" })
	end)
	assert(not ok, "Url ausente deveria erro")
	assert(string.find(tostring(err), "Url", 1, true) ~= nil, `mensagem deveria citar 'Url', recebeu: {err}`)
end)

test("RequestAsync ERRA quando Url usa um esquema diferente de http/https", function()
	local httpService = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = pcall(function()
		requestAsync(httpService, { Url = "ftp://example.com/file" })
	end)
	assert(not ok, "esquema ftp:// deveria erro -- só http/https são suportados")
	assert(string.find(tostring(err), "http", 1, true) ~= nil, `mensagem deveria citar http/https, recebeu: {err}`)
end)

test("RequestAsync ERRA quando um header não é string", function()
	local httpService = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = pcall(function()
		requestAsync(httpService, { Url = "https://example.com/", Headers = { ["X-Test"] = 5 } })
	end)
	assert(not ok, "header com valor não-string deveria erro")
	assert(string.find(tostring(err), "Headers", 1, true) ~= nil, `mensagem deveria citar 'Headers', recebeu: {err}`)
end)

--[[
	Único teste desta suíte que depende de alcance de rede de VERDADE (fora de "127.0.0.1") --
	precisa que a tentativa de conexão FALHE (DNS/conexão) para exercitar a tradução de erro.
	Não depende de nenhum serviço específico responder -- só de a tentativa falhar, o que um
	domínio ".invalid" (reservado pela IANA para nunca resolver, RFC 2606) garante em qualquer
	ambiente com pilha de rede presente. Roda dentro de `runOnScheduler` -- alcança
	`AsyncCall.Yield`/`net.request` de verdade.
]]
test("RequestAsync contra host inexistente ERRA com mensagem TRADUZIDA -- NUNCA vaza a mensagem crua do SO (ex.: 'os error 11001')", function()
	local httpService, scheduler = makeHttpService({ AllowHttp = true })
	local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

	local ok, err = runOnScheduler(scheduler, function()
		requestAsync(httpService, { Url = "https://this-host-does-not-exist-abc123xyz.invalid/" })
	end)
	assert(not ok, "RequestAsync deveria erro para um host que não existe")
	local message = tostring(err)
	assert(string.find(message, "os error", 1, true) == nil, `mensagem NUNCA deveria vazar "os error" cru do SO, recebeu: {message}`)
	assert(string.find(message, "11001", 1, true) == nil, `mensagem NUNCA deveria vazar o código de erro cru do SO, recebeu: {message}`)
	assert(string.find(message, "could not be completed", 1, true) ~= nil, `mensagem deveria citar a tradução genérica de falha, recebeu: {message}`)
	-- Confirma, de quebra, que um hostname público NÃO é recusado pela checagem de destino
	-- privado (o erro que chegou é o de CONEXÃO, não o de "[LuauBench] refusing").
	assert(string.find(message, "refusing", 1, true) == nil, `um host público não deveria disparar a recusa de destino privado, recebeu: {message}`)
end)

-- ================================================================================================
-- Servidor de teste LOCAL (net.serve) -- testes de SUCESSO/status de falha, sem nenhuma
-- dependência de rede externa. Ver cabeçalho do arquivo, "SERVIDOR DE TESTE LOCAL".
-- ================================================================================================

do
	local TEST_PORT = 47182
	local serveHandle = net.serve(TEST_PORT, function(request)
		if request.path == "/not-found" then
			return { status = 404, body = "not found" }
		end
		-- `\{`/`\}` -- chaves LITERAIS do JSON de eco, escapadas (senão o parser de string
		-- interpolada do Luau as lê como início de uma expressão de interpolação nova).
		-- `request.method` é `net.HttpMethod` (união de literais) -- convertido para `string`
		-- puro ANTES de entrar na tabela de headers, senão o literal da tabela infere um
		-- registro "selado" (uma chave com tipo `HttpMethod`, outra com `string`) incompatível
		-- com `ServeResponse.headers: {[string]: string}?`.
		local method = request.method :: string
		return {
			status = 200,
			headers = { ["Content-Type"] = "application/json", ["X-Echo-Method"] = method },
			body = `\{"method":"{method}","body":"{request.body}"\}`,
		}
	end)

	local baseUrl = `http://127.0.0.1:{TEST_PORT}`

	test("com AllowHttp e AllowHttpLocal, RequestAsync faz uma requisição REAL contra um servidor local e devolve a forma EXATA {Success, StatusCode, StatusMessage, Headers, Body}", function()
		local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
		local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

		local result: Dynamic? = nil
		local ok, err = runOnScheduler(scheduler, function()
			result = requestAsync(httpService, {
				Url = `{baseUrl}/echo`,
				Method = "POST",
				Body = "hello-world",
				Headers = { ["X-Test"] = "1" },
				-- Timeout aceito e IGNORADO (ver acceptance/divergência 1) -- não deveria mudar
				-- nada no resultado nem fazer a chamada errar.
				Timeout = 5,
			})
		end)

		assert(ok, `RequestAsync não deveria erro contra o servidor local, recebeu: {tostring(err)}`)
		assert(result ~= nil, "RequestAsync deveria ter devolvido um resultado")
		local resultTable = result :: Dynamic
		assert(resultTable.Success == true, `Success deveria ser true, recebeu {tostring(resultTable.Success)}`)
		assert(resultTable.StatusCode == 200, `StatusCode deveria ser 200, recebeu {tostring(resultTable.StatusCode)}`)
		assert(type(resultTable.StatusMessage) == "string", "StatusMessage deveria ser string")
		assert(type(resultTable.Headers) == "table", "Headers deveria ser tabela")
		assert(
			type(resultTable.Body) == "string" and string.find(resultTable.Body :: string, "hello%-world", 1, false) ~= nil,
			`Body deveria ecoar o corpo enviado, recebeu: {tostring(resultTable.Body)}`
		)
	end)

	test("GetAsync contra servidor local devolve o corpo (sucesso) -- nocache é no-op, aceito sem erro", function()
		local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

		local body: string? = nil
		local ok, err = runOnScheduler(scheduler, function()
			body = getAsync(httpService, `{baseUrl}/echo`, true, nil)
		end)
		assert(ok, `GetAsync não deveria erro, recebeu: {tostring(err)}`)
		assert(type(body) == "string" and string.find(body :: string, "GET", 1, true) ~= nil, `body deveria ecoar o método GET, recebeu: {tostring(body)}`)
	end)

	test("PostAsync contra servidor local devolve o corpo (sucesso) -- content_type/compress aceitos e ignorados", function()
		local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
		local postAsync = httpService.PostAsync :: (self: Dynamic, url: unknown, data: string, contentType: unknown, compress: boolean?, headers: unknown) -> string

		local body: string? = nil
		local ok, err = runOnScheduler(scheduler, function()
			body = postAsync(httpService, `{baseUrl}/echo`, "{}", nil, true, nil)
		end)
		assert(ok, `PostAsync não deveria erro, recebeu: {tostring(err)}`)
		assert(type(body) == "string" and string.find(body :: string, "POST", 1, true) ~= nil, `body deveria ecoar o método POST, recebeu: {tostring(body)}`)
	end)

	test("GetAsync ERRA quando o servidor responde status não-2xx -- diferente de RequestAsync, que só reporta Success=false", function()
		local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

		local ok, err = runOnScheduler(scheduler, function()
			getAsync(httpService, `{baseUrl}/not-found`, nil, nil)
		end)
		assert(not ok, "GetAsync deveria erro para status 404")
		assert(string.find(tostring(err), "404", 1, true) ~= nil, `mensagem deveria citar 404, recebeu: {tostring(err)}`)
	end)

	test("RequestAsync NÃO erra para status não-2xx -- só reporta Success=false com o StatusCode real (doc oficial)", function()
		local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
		local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

		local result: Dynamic? = nil
		local ok, err = runOnScheduler(scheduler, function()
			result = requestAsync(httpService, { Url = `{baseUrl}/not-found` })
		end)
		assert(ok, `RequestAsync não deveria erro para status HTTP de falha, recebeu: {tostring(err)}`)
		local resultTable = result :: Dynamic
		assert(resultTable.Success == false, "Success deveria ser false para 404")
		assert(resultTable.StatusCode == 404, `StatusCode deveria ser 404, recebeu {tostring(resultTable.StatusCode)}`)
	end)

	--[[
		CORREÇÃO DE SSRF -- ACEITAÇÃO com AllowHttpLocal, round-trip REAL contra o servidor local
		(ver cabeçalho de ./HttpService.luau, "CORREÇÃO DE SSRF"). Confirmado EMPIRICAMENTE nesta
		tarefa (script de prova descartável, não versionado, rodado contra `net.serve` local no
		Windows): `net.request` de fato CONECTA usando decimal/octal/hexadecimal/forma abreviada
		como host (o próprio motivo do bypass ser real) -- por isso estes 4 casos fazem um
		round-trip de VERDADE contra `{baseUrl}`, reescrito com cada notação alternativa, em vez de
		só checar que o gate não recusa.
	]]
	local ALTERNATE_LOOPBACK_NOTATIONS = {
		{ label = "DECIMAL (2130706433)", host = "2130706433" },
		{ label = "OCTAL (017700000001)", host = "017700000001" },
		{ label = "HEXADECIMAL (0x7f000001)", host = "0x7f000001" },
		{ label = "ABREVIADA (127.1)", host = "127.1" },

		-- CAÇA AO "4º BYPASS" (3ª rodada) -- confirmadas com round-trip REAL contra `net.request`
		-- puro nesta máquina (Windows), diferente das formas IPv4-mapped/0.0.0.0 abaixo
		-- (`PLATFORM_LIMITED_NOTATIONS`) que falham por limitação de socket do SO.
		{ label = "PERCENT-ENCODED total (%31%32%37%2e%30%2e%30%2e%31)", host = "%31%32%37%2e%30%2e%30%2e%31" },
		{ label = "PERCENT-ENCODED só os pontos (127%2e0%2e0%2e1)", host = "127%2e0%2e0%2e1" },
		{ label = "TAB ASCII embutido (12<TAB>7.0.0.1)", host = "12\t7.0.0.1" },
		{ label = "LF ASCII embutido (12<LF>7.0.0.1)", host = "12\n7.0.0.1" },
		{ label = "CR ASCII embutido (12<CR>7.0.0.1)", host = "12\r7.0.0.1" },

		-- 5ª RODADA (achado Unicode/IDNA, revisor-services-http-ssrf-round4) -- as 3 formas que o
		-- revisor CONFIRMOU conectando de verdade em 127.0.0.1 (script descartável + canário
		-- `net.serve`, ver relatório da tarefa) -- round-trip real aqui também, mesma disciplina
		-- das notações decimal/octal/hex/abreviada acima. A 4ª forma coberta pelo fix (halfwidth
		-- ideographic full stop, U+FF61) NÃO foi confirmada como bypass real na revisão -- fica em
		-- `PLATFORM_LIMITED_NOTATIONS`, abaixo, que só exige "o GATE não recusou", nunca um
		-- round-trip completo (evita um teste condicionado a um detalhe de `net.request` real que
		-- ninguém confirmou empiricamente ainda).
		{ label = "fullwidth full stop (127．0．0．1, U+FF0E)", host = "127\u{FF0E}0\u{FF0E}0\u{FF0E}1" },
		{ label = "ideographic full stop (127。0。0。1, U+3002)", host = "127\u{3002}0\u{3002}0\u{3002}1" },
		{ label = "dígitos fullwidth (１２７.0.0.１, U+FF11/U+FF17)", host = "\u{FF11}\u{FF12}\u{FF17}.0.0.\u{FF11}" },
	}
	for _, notation in ALTERNATE_LOOPBACK_NOTATIONS do
		test(`GetAsync ACEITA (com AllowHttpLocal) e COMPLETA round-trip real contra o servidor local usando notação {notation.label} de 127.0.0.1`, function()
			local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
			local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

			local body: string? = nil
			local ok, err = runOnScheduler(scheduler, function()
				body = getAsync(httpService, `http://{notation.host}:{TEST_PORT}/echo`, nil, nil)
			end)
			assert(ok, `deveria aceitar e completar a requisição com AllowHttpLocal, recebeu: {tostring(err)}`)
			assert(type(body) == "string" and string.find(body :: string, "GET", 1, true) ~= nil, `body deveria ecoar GET, recebeu: {tostring(body)}`)
		end)
	end

	--[[
		CORREÇÃO DE SSRF -- ACEITAÇÃO com AllowHttpLocal para IPv4-mapped IPv6 e "0.0.0.0":
		LIMITAÇÃO DE PLATAFORMA confirmada EMPIRICAMENTE nesta tarefa (mesmo script de prova) --
		diferente das 4 notações acima, conectar de verdade em `[::ffff:127.0.0.1]`/
		`[::ffff:7f00:1]`/`0.0.0.0` FALHA no Windows com "os error 10049" ("the requested address
		is not valid in its context") -- uma limitação do socket do SO, nada a ver com o GATE deste
		módulo (a mesma falha acontece mesmo chamando `net.request` diretamente, fora de qualquer
		checagem do LuauBench). Por isso estes 3 casos confirmam só que o GATE deixou passar (o
		erro final NUNCA é "[LuauBench] refusing") -- nunca um round-trip completo, que este
		ambiente não consegue fazer independente do nosso código.
	]]
	local PLATFORM_LIMITED_NOTATIONS = {
		{ label = "IPv4-mapped IPv6 comprimido dotted-quad ([::ffff:127.0.0.1])", host = "[::ffff:127.0.0.1]" },
		{ label = "IPv4-mapped IPv6 comprimido em grupos hex ([::ffff:7f00:1])", host = "[::ffff:7f00:1]" },
		{ label = "0.0.0.0 (decisão explícita)", host = "0.0.0.0" },

		-- Achado GRAVE #2 (3ª rodada) -- IPv4-compatible IPv6 (RFC 4291, sintaxe legada, SEM
		-- "ffff:"). MESMA limitação de plataforma que os IPv4-mapped acima: `net.request` PURO
		-- contra `[::127.0.0.1]` falha neste Windows com "os error 10051" (rede inalcançável --
		-- falha de ROTEAMENTO do SO, não de sintaxe) -- confirmado no script de prova desta tarefa.
		-- O que importa aqui é só que o GATE deste módulo aceite (nunca "[LuauBench] refusing")
		-- quando `AllowHttpLocal=true` -- a mesma checagem já feita para `BLOCKED_DESTINATIONS`
		-- confirma a RECUSA sem a flag; este teste confirma a ACEITAÇÃO com ela.
		{ label = "IPv4-compatible IPv6 comprimido ([::127.0.0.1], achado GRAVE #2)", host = "[::127.0.0.1]" },
		{ label = "IPv4-compatible IPv6 comprimido, privado 10/8 ([::10.0.0.1], achado GRAVE #2)", host = "[::10.0.0.1]" },

		-- 5ª RODADA -- 4º separador coberto por `normalizeUnicodeHostLabels` (halfwidth
		-- ideographic full stop, U+FF61), mas NÃO confirmado como bypass real contra `net.request`
		-- nesta revisão (diferente dos outros 3 -- ver ALTERNATE_LOOPBACK_NOTATIONS, acima). Este
		-- grupo só exige que o GATE não recuse (nunca "[LuauBench] refusing"); se `net.request`
		-- real também normalizar este caractere, a conexão completa; se não normalizar, falha por
		-- DNS -- qualquer um dos dois é aceitável aqui.
		{ label = "halfwidth ideographic full stop (127｡0｡0｡1, U+FF61 -- não confirmado como bypass real)", host = "127\u{FF61}0\u{FF61}0\u{FF61}1" },
	}
	for _, notation in PLATFORM_LIMITED_NOTATIONS do
		test(`GetAsync com AllowHttpLocal NÃO recusa {notation.label} -- gate aceita, falha (se houver) é de rede/SO, nunca "[LuauBench] refusing"`, function()
			local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
			local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

			local ok, err = runOnScheduler(scheduler, function()
				getAsync(httpService, `http://{notation.host}:{TEST_PORT}/echo`, nil, nil)
			end)
			if not ok then
				local message = tostring(err)
				assert(
					string.find(message, "refusing", 1, true) == nil,
					`o gate NÃO deveria recusar com AllowHttpLocal=true -- se falhou, deveria ser um erro de rede/SO, recebeu: {message}`
				)
			end
			-- `ok == true` (round-trip completou) também é um resultado válido -- este teste só
			-- garante que o GATE de destino não é o que barrou, nunca exige uma falha específica.
		end)
	end

	--[[
		Achado do orquestrador (par de task-cli-026): `OnHttpRequest` -- canal de auditoria de
		requisição de SAÍDA (ver ../Types.luau/../Context.luau) -- chamado UMA VEZ por requisição
		real, ANTES de `net.request` tocar a rede de verdade. `RunCommand.luau` (`cli`) já monta o
		closure de produção; faltava `services` chamá-lo de volta -- testado aqui contra o
		servidor local (sem depender de rede externa, mesmo servidor de `baseUrl` acima).
	]]
	test("OnHttpRequest é chamado com (method, host) corretos numa requisição REAL (GetAsync), ANTES de tocar a rede", function()
		local capturedCalls: { { method: string, host: string } } = {}
		local httpService, scheduler = makeHttpService({
			AllowHttp = true,
			AllowHttpLocal = true,
			OnHttpRequest = function(method: string, host: string)
				table.insert(capturedCalls, { method = method, host = host })
			end,
		})
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

		local ok, err = runOnScheduler(scheduler, function()
			getAsync(httpService, `{baseUrl}/echo`, nil, nil)
		end)
		assert(ok, `GetAsync não deveria erro, recebeu: {tostring(err)}`)
		assert(#capturedCalls == 1, `OnHttpRequest deveria ter sido chamado exatamente 1 vez, foi chamado {#capturedCalls} vez(es)`)
		assert(capturedCalls[1].method == "GET", `method deveria ser "GET", recebeu {capturedCalls[1].method}`)
		assert(capturedCalls[1].host == "127.0.0.1", `host deveria ser "127.0.0.1", recebeu {capturedCalls[1].host}`)
	end)

	test("OnHttpRequest recebe o Method correto (PUT) para RequestAsync -- não é hardcoded em GET", function()
		local capturedCalls: { { method: string, host: string } } = {}
		local httpService, scheduler = makeHttpService({
			AllowHttp = true,
			AllowHttpLocal = true,
			OnHttpRequest = function(method: string, host: string)
				table.insert(capturedCalls, { method = method, host = host })
			end,
		})
		local requestAsync = httpService.RequestAsync :: (self: Dynamic, requestOptions: unknown) -> Dynamic

		local ok, err = runOnScheduler(scheduler, function()
			requestAsync(httpService, { Url = `{baseUrl}/echo`, Method = "PUT", Body = "x" })
		end)
		assert(ok, `RequestAsync não deveria erro, recebeu: {tostring(err)}`)
		assert(#capturedCalls == 1, `OnHttpRequest deveria ter sido chamado exatamente 1 vez, foi chamado {#capturedCalls} vez(es)`)
		assert(capturedCalls[1].method == "PUT", `method deveria ser "PUT", recebeu {capturedCalls[1].method}`)
		assert(capturedCalls[1].host == "127.0.0.1", `host deveria ser "127.0.0.1", recebeu {capturedCalls[1].host}`)
	end)

	--[[
		Achado GRAVE #1 (3ª rodada de revisão) -- ver cabeçalho de ./HttpService.luau,
		"normalizeUrlForParsing". A URL usa "\@" para tentar confundir o host REAL (127.0.0.1, o
		que vem ANTES do "\") com um host disfarçado (o que vem DEPOIS do "@", "evil-marker.invalid")
		-- round-trip REAL contra o servidor local confirma que a requisição de fato vai para
		127.0.0.1 (o `body` ecoado só existe nesse servidor), e `OnHttpRequest` precisa auditar o
		HOST REAL -- nunca "evil-marker.invalid", que mascararia o alvo verdadeiro mesmo com
		`--verbose` ligado no `cli`.
	]]
	test("GetAsync ACEITA (com AllowHttpLocal) o truque '\\@' de separador de autoridade -- round-trip REAL vai para 127.0.0.1, e OnHttpRequest audita o HOST REAL (achado GRAVE #1)", function()
		local capturedCalls: { { method: string, host: string } } = {}
		local httpService, scheduler = makeHttpService({
			AllowHttp = true,
			AllowHttpLocal = true,
			OnHttpRequest = function(method: string, host: string)
				table.insert(capturedCalls, { method = method, host = host })
			end,
		})
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

		local body: string? = nil
		local ok, err = runOnScheduler(scheduler, function()
			body = getAsync(httpService, `http://127.0.0.1:{TEST_PORT}\\@evil-marker.invalid/echo`, nil, nil)
		end)
		assert(ok, `deveria completar contra o servidor local, recebeu: {tostring(err)}`)
		assert(type(body) == "string" and string.find(body :: string, "GET", 1, true) ~= nil, `body deveria ecoar GET do servidor local REAL, recebeu: {tostring(body)}`)
		assert(#capturedCalls == 1, `OnHttpRequest deveria ter sido chamado exatamente 1 vez, foi chamado {#capturedCalls} vez(es)`)
		assert(
			capturedCalls[1].host == "127.0.0.1",
			`OnHttpRequest deveria auditar o HOST REAL "127.0.0.1", nunca o host disfarçado "evil-marker.invalid" (mascararia o alvo verdadeiro), recebeu: {capturedCalls[1].host}`
		)
	end)

	--[[
		SEM `AllowHttpLocal`: confirma que o truque '\@' é RECUSADO citando o host REAL
		(127.0.0.1) na mensagem -- não seria suficiente recusar "alguma coisa" se a mensagem
		mostrada ao usuário citasse o host ERRADO (isso reproduziria, na própria mensagem de erro,
		o mesmo mascaramento que o achado GRAVE #1 causava na auditoria).
	]]
	test("GetAsync RECUSA (sem AllowHttpLocal) o truque '\\@' citando o HOST REAL (127.0.0.1) na mensagem, nunca o disfarçado", function()
		local httpService = makeHttpService({ AllowHttp = true })
		local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

		local ok, err = pcall(function()
			getAsync(httpService, `http://127.0.0.1:{TEST_PORT}\\@evil-marker.invalid/`, nil, nil)
		end)
		assert(not ok, "deveria recusar o truque de backslash sem AllowHttpLocal")
		local message = tostring(err)
		assert(string.find(message, "127.0.0.1", 1, true) ~= nil, `mensagem deveria citar o HOST REAL "127.0.0.1", recebeu: {message}`)
		assert(string.find(message, "evil%-marker", 1, false) == nil, `mensagem NUNCA deveria citar o host disfarçado, recebeu: {message}`)
	end)

	--[[
		4ª RODADA DE REVISÃO (task-services-026) -- achado GRAVE do revisor:
		`"http://127.0.0.1:PORT?x@evil-marker.invalid/"` faz o parser real ler "127.0.0.1:PORT"
		como authority (o "?" já termina a região de autoridade, RFC 3986) mas a extração ANTERIOR
		lia "evil-marker.invalid" (achava o "@" sem saber que já tinha passado do delimitador de
		query). MESMA disciplina do achado GRAVE #1 (truque '\@', acima): round-trip REAL contra o
		servidor local confirma que a conexão de fato vai para 127.0.0.1, e `OnHttpRequest` precisa
		auditar o HOST REAL -- nunca o disfarçado que aparece depois do "@" na query/fragment.
		Cobre as 4 variantes COM porta explícita (?x@ / ?@ / #x@ / #@) -- as 4 variantes SEM porta
		(mesmos 4 delimitadores, sem ":{TEST_PORT}" antes do "?"/"#") NÃO ganham round-trip real
		aqui de propósito: sem porta explícita a authority vira só "127.0.0.1" (RFC 3986 -- a porta
		default de http é 80), e um round-trip de verdade contra a porta 80 exigiria um serviço
		fixo rodando nela (fora do controle desta suíte, instável entre máquinas/CI) -- a
		propriedade de RECUSA sem `AllowHttpLocal` para as 4 variantes SEM porta já está coberta,
		sem depender de rede nenhuma, em `BLOCKED_DESTINATIONS` (acima, mesmo arquivo) -- essa é a
		propriedade de segurança que importa (o destino é corretamente identificado como loopback e
		bloqueado por padrão); o round-trip aqui só confirma, a MAIS, que a aceitação com
		`AllowHttpLocal` também concorda com o host real, o que só é observável com uma porta que
		esta suíte de fato controla.
	]]
	local AUTHORITY_TERMINATOR_BYPASS_URLS = {
		{ label = "?x@ COM porta", url = `http://127.0.0.1:{TEST_PORT}?x@evil-marker.invalid/echo` },
		{ label = "?@ COM porta", url = `http://127.0.0.1:{TEST_PORT}?@evil-marker.invalid/echo` },
		{ label = "#x@ COM porta", url = `http://127.0.0.1:{TEST_PORT}#x@evil-marker.invalid/echo` },
		{ label = "#@ COM porta", url = `http://127.0.0.1:{TEST_PORT}#@evil-marker.invalid/echo` },
	}
	for _, bypass in AUTHORITY_TERMINATOR_BYPASS_URLS do
		test(`GetAsync ACEITA (com AllowHttpLocal) o truque de terminador de authority '{bypass.label}' -- round-trip REAL vai para 127.0.0.1, e OnHttpRequest audita o HOST REAL (achado da 4ª rodada)`, function()
			local capturedCalls: { { method: string, host: string } } = {}
			local httpService, scheduler = makeHttpService({
				AllowHttp = true,
				AllowHttpLocal = true,
				OnHttpRequest = function(method: string, host: string)
					table.insert(capturedCalls, { method = method, host = host })
				end,
			})
			local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

			local body: string? = nil
			local ok, err = runOnScheduler(scheduler, function()
				body = getAsync(httpService, bypass.url, nil, nil)
			end)
			assert(ok, `deveria completar contra o servidor local, recebeu: {tostring(err)}`)
			assert(type(body) == "string", `body deveria ser string, recebeu: {tostring(body)}`)
			assert(#capturedCalls == 1, `OnHttpRequest deveria ter sido chamado exatamente 1 vez, foi chamado {#capturedCalls} vez(es)`)
			assert(
				capturedCalls[1].host == "127.0.0.1",
				`OnHttpRequest deveria auditar o HOST REAL "127.0.0.1", nunca o host disfarçado "evil-marker.invalid", recebeu: {capturedCalls[1].host}`
			)
		end)
	end

	serveHandle.stop()
end

-- ================================================================================================
-- OnHttpRequest -- NUNCA chamado quando a requisição é recusada ANTES de tocar a rede (nada saiu
-- de verdade, nada para auditar). Nenhum dos dois casos abaixo precisa de scheduler/servidor: os
-- dois erram ANTES de `AsyncCall.Yield`/`net.request`.
-- ================================================================================================

test("OnHttpRequest NÃO é chamado quando a requisição é recusada por HttpEnabled=false", function()
	local calls = 0
	local httpService = makeHttpService({
		OnHttpRequest = function(_method: string, _host: string)
			calls += 1
		end,
	})
	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

	local ok = pcall(function()
		getAsync(httpService, "https://example.com", nil, nil)
	end)
	assert(not ok, "deveria continuar errando -- HttpEnabled é false")
	assert(calls == 0, `OnHttpRequest NÃO deveria ter sido chamado, foi chamado {calls} vez(es)`)
end)

test("OnHttpRequest NÃO é chamado quando a requisição é recusada por destino privado sem AllowHttpLocal", function()
	local calls = 0
	local httpService = makeHttpService({
		AllowHttp = true,
		OnHttpRequest = function(_method: string, _host: string)
			calls += 1
		end,
	})
	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

	local ok = pcall(function()
		getAsync(httpService, "http://127.0.0.1/", nil, nil)
	end)
	assert(not ok, "deveria continuar errando -- destino privado sem AllowHttpLocal")
	assert(calls == 0, `OnHttpRequest NÃO deveria ter sido chamado, foi chamado {calls} vez(es)`)
end)

-- ================================================================================================
-- REGRESSÃO task-services-034: uma falha de REDE genuína (não "HTTP não habilitado", não destino
-- recusado -- um erro de verdade vindo de `net.request`, o caminho onde o bug morava) sai por
-- `Scheduler.ThreadError`, NUNCA como dump cru de pilha do Lune. Ver `performNetRequest`
-- (./HttpService.luau) para a causa raiz completa e a correção (`task.spawn` + poll).
--
-- ACHADO CENTRAL desta tarefa que explica por que NENHUM teste pré-existente deste arquivo pegava
-- o bug: todo teste de rede acima usa `runOnScheduler`, que envolve a chamada num `pcall` PRÓPRIO
-- (linha ~127) -- e um `pcall` comum já protege corretamente através de qualquer yield/resume,
-- não importa QUEM fez o resume por baixo. O bug só se manifesta quando NÃO HÁ NENHUM pcall entre
-- a chamada e o topo da thread gerida -- exatamente a forma de um script real
-- (`local body = HttpService:GetAsync(...)`, sem pcall nenhum) -- por isso este teste NUNCA
-- envolve a chamada num pcall, e dirige o Scheduler manualmente (não usa `runOnScheduler`).
-- ================================================================================================

-- Sobe um servidor local numa porta aleatória e o para IMEDIATAMENTE -- garante "conexão
-- recusada" real, rápida e determinística (sem depender de DNS/rede externa, diferente do teste
-- de "host inexistente" acima, que factualmente pode levar vários segundos). Mesma técnica de
-- porta dinâmica com retry usada por `RunCommand.spec.luau` (`startLocalHttpServer`) -- nunca uma
-- porta fixa, que colidiria entre execuções concorrentes.
local function pickPortWithNothingListening(): number
	local MAX_ATTEMPTS = 25
	for _ = 1, MAX_ATTEMPTS do
		local candidatePort = math.random(40000, 59999)
		local ok, handleOrError = pcall(function()
			return net.serve(candidatePort, function(_request: net.ServeRequest): net.ServeResponse
				return { status = 200, body = "unused -- parado antes de qualquer requisição" }
			end)
		end)
		if ok then
			(handleOrError :: net.ServeHandle).stop()
			return candidatePort
		end
	end
	error(`HttpService.spec: não conseguiu achar uma porta livre em {MAX_ATTEMPTS} tentativas`)
end

test("task-services-034: GetAsync chamado SEM pcall (como um script real faria) -- falha de rede genuína sai por Scheduler.ThreadError, NUNCA como dump cru do Lune", function()
	local port = pickPortWithNothingListening()

	local httpService, scheduler = makeHttpService({ AllowHttp = true, AllowHttpLocal = true })
	local getAsync = httpService.GetAsync :: (self: Dynamic, url: unknown, nocache: boolean?, headers: unknown) -> string

	local threadErrorCount = 0
	local threadErrorMessage: string? = nil
	local errorConnection = scheduler.ThreadError:Connect(function(_thread: thread, message: string)
		threadErrorCount += 1
		threadErrorMessage = message
	end)

	local finished = false
	scheduler:Spawn(function()
		-- SEM pcall aqui de propósito -- ver comentário do cabeçalho desta seção: é exatamente a
		-- ausência de qualquer pcall que reproduzia o bug original (o erro, antes da correção,
		-- escapava como dump cru em vez de virar ThreadError).
		getAsync(httpService, `http://127.0.0.1:{port}/`, nil, nil)
		finished = true
	end)

	local startClock = os.clock()
	scheduler:Run(function()
		return threadErrorCount == 0 and (os.clock() - startClock) < 10
	end)

	assert(not finished, "a thread NUNCA deveria terminar normalmente -- GetAsync deveria ter errado (nada escuta na porta)")
	assert(
		threadErrorCount == 1,
		`esperava exatamente 1 ThreadError (a falha de rede saindo pelo caminho normal), recebeu {threadErrorCount} -- se 0, o bug de task-services-034 voltou (erro escapando cru)`
	)
	assert(
		string.find(threadErrorMessage or "", "the request could not be completed", 1, true) ~= nil,
		`ThreadError deveria carregar a mensagem traduzida de falha de rede, recebeu: {tostring(threadErrorMessage)}`
	)

	errorConnection:Disconnect()
end)

test("SEM ANY: o texto-fonte de ./HttpService.luau nunca usa o tipo `any` (regra 01 -- checagem mecânica, complementar ao `luau-lsp analyze`)", function()
	local source = fs.readFile("src/services/behavior/HttpService.luau")
	assert(string.find(source, "%f[%w]any%f[%W]") == nil, "./HttpService.luau NÃO deveria conter o tipo `any` em lugar nenhum (regra 01)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
