--!strict

--[[
	Behavior de `HttpService`. Sub-leva A (task-services-022): JSONEncode/JSONDecode/UrlEncode/
	GenerateGUID + `HttpEnabled` semeado `false`, SEM `@lune/net`. Sub-leva B (task-services-026,
	ESTA tarefa): `GetAsync`/`PostAsync`/`RequestAsync` REAIS sobre `@lune/net`, atrás do portão
	`HttpEnabled` -- que agora pode nascer `true` de verdade, via `BootstrapOptions.AllowHttp`.
	LER .claude/agents-memory/arquiteto-services-2026-09-05.md, seção "L2.2 -- `HttpService`: a
	rede é opt-in de quem roda o LuauBench, exatamente como é opt-in do dono do lugar no Roblox"
	INTEIRA (L2.2.1 a L2.2.5), sobretudo L2.2.2/L2.2.4/L2.2.5, antes de mexer aqui. ÚNICO módulo
	de rede do projeto -- merece cuidado extra, é código de segurança.

	## RACIOCÍNIO DA DECISÃO (por que existe um PORTÃO, e não um BLOQUEIO) -- task-services-026

	A invariante 6 (local-first) tem como SUJEITO o LuauBench -- ela proíbe a FERRAMENTA de
	mandar dado do usuário para fora por conta própria (telemetria, análise remota, "modo
	online" não pedido). `HttpService:PostAsync(url, corpo)` é o SCRIPT DO USUÁRIO fazendo o que
	ELE escreveu para fazer, e a regra 00 é explícita sobre o critério: "a superfície exposta ao
	script é a que o Roblox real exporia". Recusar rede seria DIVERGIR do Roblox (invariante 2) e
	amputar metade da API que existe justamente para falar com serviço externo (webhook, API de
	analytics, backend próprio). O que justifica o PORTÃO (não o bloqueio) é a invariante 7: um
	`.project.json` clonado de um repositório desconhecido não deve ganhar a rede da máquina do
	desenvolvedor só por ser executado uma vez -- e o portão default-off é SIMULTANEAMENTE o
	comportamento mais FIEL, porque no Roblox um lugar novo também tem HTTP desligado (`HttpEnabled`
	já semeada `false`, sub-leva A). O que FERIRIA a invariante 6, e continua proibido, é o
	LuauBench mandar qualquer coisa por conta própria -- nunca a chamada literal que o script
	pediu.

	## `HttpEnabled` -- de onde vem `true` agora (a via NOVA desta sub-leva)

	`HttpEnabled` continua `ReadOnly` no schema (sub-leva A, gerador -- nenhuma mudança aqui: um
	script continua sem conseguir escrevê-la). O que muda é QUEM pode ligá-la e QUANDO: `cli`
	(`RunCommand.luau`, `task-cli-026`, rodando em paralelo com esta tarefa) traduz as flags
	`--allow-http`/`--allow-http-local` em dois campos NOVOS de `Services.BootstrapOptions`
	(`../Types.luau`, adicionados por esta tarefa): `AllowHttp: boolean?` e
	`AllowHttpLocal: boolean?` -- ambos tratados como `false` quando `nil`/omitidos. Este módulo
	NUNCA lê `BootstrapOptions` diretamente (não é dele) -- lê via `Context.IsHttpAllowed()`/
	`Context.IsHttpLocalAllowed()` (`../Context.luau`, também estendido por esta tarefa), o mesmo
	canal que `RunService.luau`/`MessagingService.luau` já usam para alcançar algo do bootstrap de
	dentro de um `Behavior`.

	IMPORTANTE: `Services.Bootstrap` roda ANTES de qualquer Instance de Service nascer (`DataModel`
	é leniente -- `HttpService` só passa a existir no primeiro `game:GetService("HttpService")`),
	então a permissão não pode ser aplicada dentro de `Bootstrap`/`Context.Set` (não há instância
	ainda para chamar `SetPropertyRaw` nela). Por isso este módulo ganha um `Initialize` (ver
	`HttpServiceBehavior` no fim do arquivo): roda DEPOIS que o schema já foi aplicado à instância
	nova (mesma ordem garantida por `Runtime.ClassRegistry.new`/`NewEngineInstance` que
	`RunService.luau` já documenta), lê `Context.IsHttpAllowed()` e, se `true`, chama
	`Runtime.Instance.SetPropertyRaw(instance, "HttpEnabled", true)` -- a MESMA via de engenharia
	que a sub-leva A já usava (na spec) para simular esta flag antes de ela existir de verdade.
	Sem a flag, `HttpEnabled` continua `false` (o `Default` do schema gerado, nunca tocado) --
	MESMO comportamento fiel da sub-leva A: lugar novo, HTTP desligado.

	`AllowHttpLocal = true` SEM `AllowHttp = true` nunca abre rede nenhuma: `HttpEnabled` só nasce
	`true` quando `AllowHttp` é `true` (ver `Initialize`, acima) -- `AllowHttpLocal` só é
	CONSULTADO depois que `assertHttpEnabled` já deixou passar (ver `GetAsync`/`PostAsync`/
	`RequestAsync`, abaixo), então "rede local sem rede geral" nunca é um estado alcançável: com
	`AllowHttp = false`, os três métodos continuam errando "HTTP não habilitado" ANTES de qualquer
	checagem de destino, seja ele público ou privado. Isto resolve, do lado de `services`, o pedido
	do contrato coordenado com `cli` de "nunca abrir rede local sem rede geral" sem precisar de
	nenhuma lógica de OR entre as duas flags -- a ORDEM das checagens já garante isso sozinha.

	## SEM REDE quando `HttpEnabled` é `false` -- continua EXATO, não uma aproximação

	Com a flag desligada (o caso default, e o único alcançável sem `--allow-http`), o
	comportamento é IDÊNTICO ao da sub-leva A: `assertHttpEnabled` erra ANTES de qualquer `require`
	de rede ser exercitado -- `GetAsync`/`PostAsync`/`RequestAsync` nunca chegam perto de
	`net.request` neste ramo. Confirmado nesta tarefa (mesma disciplina da sub-leva A): um lugar
	Roblox recém-criado, não publicado, tem `HttpEnabled == false` por DEFAULT -- o LuauBench sem
	a flag é uma simulação EXATA desse estado, não uma aproximação dele.

	## ENDURECIMENTO deliberado -- MAIS restritivo que o Roblox real (L2.2.4)

	Com `HttpEnabled == true` (via `--allow-http`), destinos loopback/link-local/privados
	(`127.0.0.0/8`, `::1`, `169.254.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) são
	RECUSADOS por padrão -- só passam com uma SEGUNDA permissão explícita, `AllowHttpLocal`. O
	modelo de ameaça é genuinamente diferente do Roblox real: um servidor Roblox roda num
	datacenter e não alcança a rede doméstica de ninguém; o LuauBench roda NA MÁQUINA do
	desenvolvedor, onde `http://127.0.0.1:*`/`http://169.254.169.254/` (metadata de nuvem) são
	alvos reais que não existem no Roblox. Manter fidelidade estrita neste ponto específico seria
	copiar uma permissão cujo contexto de ameaça não se aplica -- por isso esta checagem NÃO tem
	contraparte real (mensagem `[LuauBench]`, ver `assertDestinationAllowed`, abaixo).

	EXTENSÃO desta tarefa em relação à lista literal do desenho (declarada, não escondida): o host
	"localhost" (e variações de capitalização) é tratado como loopback pelo MESMO motivo dos
	CIDRs -- sem isto, o portão de `127.0.0.0/8` seria trivialmente contornável escrevendo
	"localhost" em vez do IP, que é justamente o destino mais comum de um servidor de
	desenvolvimento local (o caso que a MESMA seção do desenho cita como precisando da segunda
	flag). Ranges IPv6 além de `::1` (ex.: `fe80::/10` link-local, `fc00::/7` ULA) NÃO são cobertos
	-- fora da lista literal do desenho, e adicioná-los por analogia seria inventar escopo não
	pedido; registrado aqui como lacuna conhecida, não escondida.

	CORREÇÃO DE SSRF (retomada desta seção -- correção de bug de segurança, revisor-services
	reprovou a versão original): a comparação original só reconhecia IPv4 na grafia canônica
	"#.#.#.#" e IPv6 loopback só nas grafias literais "::1"/"0:0:0:0:0:0:0:1" -- QUALQUER outra
	representação textual válida do MESMO endereço passava direto pelo filtro (`http://2130706433/`
	decimal, `http://017700000001/` octal, `http://0x7f000001/` hex, `http://127.1/` abreviado,
	`http://[::ffff:127.0.0.1]/` IPv4-mapped IPv6 comprimido/expandido -- todos resolvem para
	127.0.0.1, e todos alcançavam rede local mesmo SEM `--allow-http-local`). `isIPv4Private`/
	`isLocalDestination` (ver `tryParseIPv4`/`extractIPv4MappedOctets`, abaixo) agora NORMALIZAM o
	host para os 4 octetos canônicos em QUALQUER dessas notações antes de comparar contra os
	ranges -- essas formas passam a ser RECUSADAS sem `AllowHttpLocal` e ACEITAS com ela, como
	qualquer outro destino privado (testado em `HttpService.spec.luau`). `0.0.0.0` foi decidido
	EXPLICITAMENTE como bloqueado por padrão (comportamento de conectar nele depende do SO -- em
	vários Linux resolve para loopback -- então recusar é o lado seguro). Continuam FORA de escopo,
	pelo MESMO motivo já declarado acima (não inventar cobertura não pedida): ranges IPv6 além de
	`::1`/IPv4-mapped (`fe80::/10`, `fc00::/7`), e qualquer forma de compressão "::" de IPv6 em
	posição diferente do prefixo IPv4-mapped.

	LIMITAÇÃO DECLARADA (nunca escondida): esta checagem olha só o HOST LITERAL da URL (IP escrito
	à mão em qualquer notação reconhecida acima, ou o nome "localhost") -- o LuauBench NÃO resolve
	DNS por conta própria antes de decidir se bloqueia (não há uma função de resolução de DNS
	separada de `net.request`/`net.socket` no Lune 0.10.5 para isso). Um hostname comum que RESOLVE
	para um IP privado (DNS rebinding, ou um domínio interno da rede do desenvolvedor, tipo
	"meu-servidor.local") NÃO é bloqueado por este mecanismo -- `net.request` resolve e conecta como
	uma operação só, do lado do Lune, sem dar ao LuauBench a chance de inspecionar o IP resolvido
	antes de conectar. Esta lacuna foi INVESTIGADA A FUNDO e formalmente ACEITA como risco residual
	pelo usuário (não é mais pendência desta tarefa) -- ver "RISCOS RESIDUAIS ACEITOS", abaixo, logo
	após a 5ª rodada de revisão.

	## 3ª RODADA DE REVISÃO (`revisor-services-http-ssrf-round2-2026-09-06.md`) -- MUDANÇA DE
	## ESTRATÉGIA: de "reconhecer cada notação" para "normalizar como a rede real normaliza"

	As duas primeiras rodadas corrigiram bypass por bypass (uma LISTA de notações de IPv4/IPv6
	reconhecidas). O padrão "o revisor acha mais uma forma nova a cada rodada" é sintoma de que
	`extractHost` fazia um parsing PRÓPRIO, sem garantia nenhuma de bater com o que a stack de rede
	real (WHATWG URL Standard) realmente faz -- cada rodada só fechava a forma ESPECÍFICA reportada,
	nunca a CLASSE do bug. Esta rodada muda a estratégia: em vez de mais uma notação de IP na lista,
	`normalizeUrlForParsing`/`percentDecodeHost` (abaixo) fazem a URL passar pelas MESMAS
	transformações que o parser real faz ANTES de qualquer checagem de host -- depois disso, a lista
	de notações IPv4/IPv6 já existente (herdada das rodadas 1/2) volta a ser suficiente, porque o
	host que ela recebe já É o host real.

	Achados desta rodada (todos reproduzidos com `net.request` puro + canário `net.serve` local
	ANTES do fix, script descartável -- ver relatório da tarefa):
	1. **GRAVE -- "\@" como separador de autoridade.** WHATWG trata "\" como "/" em QUALQUER posição
	   de uma URL de esquema especial -- `"http://127.0.0.1:P\@evil.invalid/"` conecta em
	   `127.0.0.1:P` de verdade, mas o `extractHost` antigo lia "evil.invalid" (e `OnHttpRequest`
	   auditava o host ERRADO). Fix: `normalizeUrlForParsing` troca "\" por "/" na URL inteira,
	   ANTES de qualquer outro parsing -- a mesma URL normalizada flui para `extractHost`,
	   `assertDestinationAllowed`, `auditOutgoingRequest` E `performNetRequest`.
	2. **GRAVE -- IPv4-compatible IPv6 (`::a.b.c.d`, RFC 4291 legado, SEM `ffff:`).** Forma irmã do
	   IPv4-mapped já coberto, só sem o grupo `ffff`. Fix: `ipv4CompatibleFromCompressed`,
	   agregada em `extractEmbeddedIPv4Octets` (renomeada de `extractIPv4MappedOctets`).
	3. **BAIXO -- zone ID IPv6 (`::1%eth0`) não normalizado em `isIPv6Loopback`.** Não explorável
	   hoje (Lune 0.10.5 rejeita a sintaxe antes de conectar), corrigido por barato/estar na área.
	4. **GRAVE, achado NESTA rodada por caça ativa (pedida explicitamente, não esperar o revisor
	   achar de novo) -- classe INTEIRA de host-parsing divergente, não só um caso**:
	   - Percent-encoding do host: `"http://%31%32%37%2e%30%2e%30%2e%31/"` E até só os pontos
	     (`"http://127%2e0%2e0%2e1/"`) conectam de verdade -- o host parser do WHATWG
	     percent-decodifica o host ANTES de checar se "parece um número". Fix: `percentDecodeHost`,
	     aplicada ao token de host DEPOIS de `extractHost` já ter segmentado a URL pelos
	     delimitadores literais (nunca decodifica a URL inteira antes de segmentar -- decodificar
	     cedo demais criaria uma classe DIFERENTE de bug, um "%2f" virando delimitador de path).
	   - Tab/LF/CR (bytes ASCII 0x09/0x0A/0x0D) embutidos em QUALQUER posição da URL: WHATWG remove
	     os 3 como um dos primeiros passos do parsing -- `"http://12\t7.0.0.1/"` conecta em
	     `127.0.0.1` de verdade. Fix: `normalizeUrlForParsing` também remove esses 3 bytes da URL
	     INTEIRA (mesma função que já troca "\" por "/").

	Descartados por não serem exploráveis (`net.request` rejeita ANTES de qualquer tentativa de
	conexão -- confirmado rodando, ver relatório da tarefa): espaço embutido no meio do host
	("bad argument #1: invalid international domain name"), IPv6 sem colchetes ("bad argument #1:
	empty host"), espaço entre host e porta (mesmo erro de IDN inválido), "@" duplo cru sem
	backslash (o ÚLTIMO "@" já era o delimitador correto tanto para este módulo quanto para
	`net.request` -- comportamento IDÊNTICO, não uma divergência).

	## 4ª RODADA DE REVISÃO (task-services-026) -- MUDANÇA DE ESTRATÉGIA: de "mais um delimitador
	## na lista" para "a GRAMÁTICA COMPLETA da RFC 3986, em 3 passos ordenados"

	Achado desta rodada (GRAVE, reportado pelo revisor -- reproduzido e confirmado ANTES do fix,
	script descartável + canário `net.serve` local, ver relatório da tarefa):
	`"http://127.0.0.1:PORT?x@evil-marker.invalid/"` conecta de verdade em `127.0.0.1:PORT` (a
	"query" nunca é host de verdade), mas `extractHost` (versão anterior a esta rodada) lia
	"evil-marker.invalid" como host -- a mesma classe de bug das 3 rodadas anteriores (host
	auditado/checado divergindo do host real usado pela conexão), desta vez porque a extração só
	cortava a região de autoridade pela primeira "/", nunca por "?"/"#" -- um "@" dentro da query
	ainda era achado pelo delimitador de userinfo.

	As 3 rodadas anteriores fecharam bypass por bypass (uma lista de delimitadores/notações
	reconhecidos) -- o padrão "o revisor acha mais um a cada rodada" é sintoma de que a extração
	nunca seguiu uma GRAMÁTICA completa, só delimitadores adicionados incrementalmente. Esta rodada
	reescreve `extractHost` do zero seguindo, EM ORDEM, a gramática RFC 3986 (§3, §3.2) --
	`authority = [ userinfo "@" ] host [ ":" port ]`, com a `authority` delimitada do resto da URL
	pelo PRIMEIRO de "/", "?", "#" (nunca um "@" sozinho) -- em 3 passos, cada um operando só na
	fatia que o passo anterior isolou (nunca um regex solto tentando casar tudo de uma vez contra a
	URL inteira). Detalhe completo do algoritmo e da caça ativa contra a PRÓPRIA gramática nova
	(authority vazia, múltiplos "@", host vazio, porta não numérica -- nenhum revelou bypass novo)
	no comentário de `extractHost`, abaixo.

	## Forma EXATA de `RequestAsync` (doc oficial, confirmada na pesquisa) + divergências

	Entrada: `{ Url, Method, Headers, Body, Compress, Timeout }`. Saída:
	`{ Success, StatusCode, StatusMessage, Headers, Body }`. `RequestAsync` NÃO lança erro para
	status HTTP de falha (só `Success = false`) -- só lança para erro de rede/IO genuíno (doc:
	"Only throws an error if a miscellaneous network or I/O error occurs, never for unsuccessful
	status codes"). `GetAsync`/`PostAsync` são tratados como atalhos que RETORNAM só o corpo em
	sucesso e LANÇAM em qualquer falha (rede OU status HTTP não-2xx) -- comportamento amplamente
	documentado na comunidade Roblox (é por isto que praticamente todo tutorial envolve `pcall` ao
	redor de `GetAsync`/`PostAsync`), mas SEM citação de doc oficial byte-a-byte para a string
	exata da mensagem -- tratado como aproximação de boa-fé (`"{StatusCode}: {StatusMessage}"`,
	formato minimalista plausível), não confirmado ao pé da letra.

	Divergências DECLARADAS (regra 00 -- nunca silenciosas):
	1. **`Timeout` aceito e IGNORADO.** Confirmado RODANDO nesta tarefa (Lune 0.10.5,
	   `~/.lune/.typedefs/0.10.5/net.luau`): `FetchParams` NÃO tem campo `timeout` em lugar
	   nenhum (nem em `options`) -- passar um valor extra não documentado no schema é
	   silenciosamente ignorado pelo `net.request` nativo. Implementar um timeout por cima
	   (rodar a chamada numa task própria + cancelamento) exigiria um mecanismo de cancelamento
	   que não existe hoje no território -- fora do escopo desta sub-leva.
	2. **Host inexistente/falha de conexão NUNCA vaza a mensagem crua do SO/Rust.** Confirmado
	   rodando (Windows, Lune 0.10.5) contra um host inexistente: `net.request` LANÇA
	   `"No such host is known. (os error 11001)"` -- `performNetRequest`, abaixo, CAPTURA
	   qualquer erro de `net.request` (não só DNS -- também conexão recusada, TLS, etc.) e
	   traduz para uma família única, genérica, em inglês, SEM prefixo `[LuauBench]` (tem
	   contraparte real: o Roblox também lança para erro de rede genuíno). A tradução é
	   DELIBERADAMENTE genérica (não tenta distinguir DNS de conexão recusada de TLS) -- fazer
	   essa distinção exigiria parsing frágil de uma string de erro que varia por plataforma
	   (o texto acima é específico do Windows; Linux/macOS têm textos completamente diferentes
	   para a mesma falha), e o formato de saída desta tarefa nem inclui `Enum.HttpError` (que
	   seria o único lugar onde essa distinção importaria).
	3. **Sem bloqueio de `roblox.com` e sem o erro "client-only".** Confirmados só por DevForum
	   (não por doc oficial), e o LuauBench é sempre servidor -- não implementados, registrados.
	4. **Sem limite de 500 req/min.** Mesma conta já aplicada a DataStore/MessagingService
	   (L2.1.4): a fórmula real depende de jogadores conectados, e o LuauBench tem sempre zero --
	   simular o orçamento mínimo quebraria código que roda folgado em produção real.
	5. **`nocache` de `GetAsync` é um no-op.** O LuauBench não tem cache de HTTP nenhum -- toda
	   chamada é sempre uma requisição de rede fresca, o que equivale a `nocache = true` sempre,
	   nunca ao inverso (nunca devolve uma resposta desatualizada por engano).
	6. **`content_type`/`compress` de `PostAsync` e `Compress` de `RequestAsync` são aceitos e
	   IGNORADOS.** `content_type` é `Enum.HttpContentType` no dump -- `Enum`/`EnumItem` já
	   existem em `src/valuetypes/` (leva de Value Types), mas NENHUM `behavior/*.luau` desta
	   leva de `services` os consome ainda, e mapear um `EnumItem` de `HttpContentType` para uma
	   string de MIME type real está fora do escopo desta tarefa (que é sobre PERMISSÃO de rede,
	   não sobre integração de Enum). Um script pode continuar passando `Headers = { ["Content-
	   Type"] = "..." }` manualmente, que flui sem alteração. `compress`/`Compress` (gzip do
	   corpo da requisição) não têm equivalente em `net.request` do Lune 0.10.5 (só existe
	   `options.decompress` para a RESPOSTA, default `true` -- nunca configurado por este módulo,
	   sempre o default do Lune) -- implementar compressão de saída própria via `@lune/serde`
	   (`serde.compress("gzip", ...)`) é POSSÍVEL mas está fora do escopo pedido por esta tarefa
	   (que não lista `compress` entre os itens a implementar) -- registrado como extensão futura,
	   não uma omissão silenciosa.

	## Composição com `Runtime.Scheduler` -- verificado RODANDO nesta tarefa, não assumido

	`net.request` é uma função nativa ASSÍNCRONA do Lune (yielda de verdade a `coroutine` que a
	chama, resumida depois pelo runtime interno do PRÓPRIO Lune -- não por
	`Runtime.Scheduler:resumeThread`). Isto é uma via de retomada TOTALMENTE diferente de
	`Scheduler:Wait`, e o Scheduler deste projeto é um agendador cooperativo PRÓPRIO, sobre
	`coroutine.resume`/`yield` puro (ver `src/runtime/Scheduler.luau`) -- não delega a
	`@lune/task` para nada além do cochilo ocioso do laço principal (`Run`). Verificado
	empiricamente nesta tarefa (script de prova descartável, rodado e removido, não faz parte de
	nenhum território): uma thread criada via `Runtime.Scheduler:Spawn` que chama `net.request`
	dentro de si (a) YIELDA de verdade (`resumeThread` recebe `ok = true`, `status =
	"suspended"`, nunca bloqueia o laço principal), (b) o resto do Scheduler continua funcionando
	NORMALMENTE enquanto a requisição está em voo (`Heartbeat` seguiu pulsando, uma segunda
	thread `Spawn`ada avançou normalmente via `scheduler:Wait(0)` durante a espera), e (c) quando
	o Lune resume a thread sozinho (fora de `resumeThread`), o auto-heal já existente em
	`Scheduler.IsAlive` (`for co in self.liveThreads do if coroutine.status(co) == "dead" then
	...`) poda corretamente `liveThreads`/`ThreadBroker` no tique seguinte -- `Scheduler:Run()`
	termina limpo, sem thread fantasma. Por isso `GetAsync`/`PostAsync`/`RequestAsync`, abaixo,
	chamam `net.request` DIRETO (sem nenhum wrapper de scheduler adicional) depois de
	`AsyncCall.Yield` -- o `AsyncCall.Yield` continua sendo chamado primeiro, não porque
	`net.request` precise dele para yieldar (ele já yielda sozinho, de verdade), mas para manter a
	MESMA restrição uniforme de todo método `Yields` deste território ("só pode ser chamado de
	uma thread gerida pelo Scheduler" -- Script principal ou `task.spawn`/`task.delay`): sem essa
	chamada, uma `coroutine.wrap` crua e não rastreada conseguiria completar uma requisição real
	mesmo sem ser uma thread do Scheduler, uma assimetria em relação a `DataStore`/
	`MessagingService` (que SEMPRE rejeitam essa mesma thread não-rastreada) que este módulo evita
	de propósito.

	## JSONEncode / JSONDecode -- sobre `@lune/serde`, com UMA divergência descoberta e corrigida à
	## MÃO, e UMA divergência descoberta e só DECLARADA (nunca escondida -- regra 00)

	[Sub-leva A, task-services-022 -- inalterado por esta tarefa.] Verificado RODANDO
	`serde.encode`/`serde.decode` de verdade (Lune 0.10.5, mesma versão do `rokit.toml`), além do
	que a pesquisa já tinha (pesquisa-http-messaging-2026-09-05.md, item B.5):

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

	3. **DIVERGÊNCIA DECLARADA (nunca corrigida) -- `inf`/`NaN`.** A doc oficial diz que o Roblox
	   ACEITA `inf`/`NaN` em `JSONEncode` e produz JSON DELIBERADAMENTE INVÁLIDO (o token literal
	   `inf`/`nan`, que nenhum parser JSON padrão aceita) -- é uma escolha de design documentada do
	   motor real, não um bug. `serde.encode` do Lune 0.10.5, confirmado rodando, NÃO recusa/erra
	   nesses casos -- ele SILENCIOSAMENTE substitui `inf`/`-inf`/`NaN` por `null`
	   (`{"x": math.huge}` vira `{"x":null}`). Reimplementar um encoder JSON próprio só para
	   reproduzir bit-a-bit esse detalhe está FORA de escopo (que pede JSON "sobre `@lune/serde`",
	   não um encoder autoral) -- a divergência fica DECLARADA aqui, e no relatório da tarefa,
	   nunca escondida (regra 00).

	4. Chaves de tabela mistas (string + número -- "array tem prioridade, chaves string são
	   ignoradas", doc oficial): comportamento nativo do `serde.encode`, sem código extra
	   necessário aqui. DIVERGÊNCIA DECLARADA ADICIONAL (tabela vazia): a doc oficial afirma que
	   uma tabela Lua vazia `{}` vira array JSON vazio `[]`. Confirmado RODANDO:
	   `serde.encode("json", {})` devolve `"{}"` (objeto JSON vazio), NUNCA `"[]"` -- o Lune não
	   distingue "mapa vazio" de "array vazio". Impacto prático BAIXO, corrigir exigiria um
	   encoder JSON autoral -- fora de escopo. Declarado aqui e no relatório, nunca corrigido
	   silenciosamente.

	## UrlEncode -- percent-encoding CONFIRMADO byte-a-byte contra o exemplo literal da doc oficial

	[Sub-leva A -- inalterado.] Doc oficial (pesquisa, item B.7):
	`"https://www.roblox.com/discover#/"` -> `"https%3A%2F%2Fwww%2Eroblox%2Ecom%2Fdiscover%23%2F"`
	-- note que até `.` vira `%2E` (mais agressivo que `encodeURIComponent` do JS, que preserva
	`.`). A regra `[^%w]` (só letra/dígito ASCII preservado, QUALQUER outro byte vira `%XX`
	maiúsculo) foi verificada à MÃO contra esse exemplo inteiro (todo caractere não-alfanumérico
	do exemplo -- `:`, `/`, `.`, `#` -- aparece percent-encoded, e SÓ eles) -- bate exatamente,
	caractere por caractere. Espaço não tem exemplo oficial testado (vira `%20` por esta regra,
	nunca `+`) -- tratado como extrapolação direta da MESMA regra confirmada.

	## GenerateGUID -- formato confirmado, NÃO é RFC 4122 exato (mesma fidelidade já aceita em
	## `runtime` para `DataModel.JobId`)

	[Sub-leva A -- inalterado.] Exemplos literais da doc oficial (pesquisa, item B.6): com chaves,
	`"{94b717b2-d54f-4340-a504-bd809ef5bf5c}"`; sem chaves,
	`"db454790-7563-44ed-ab4b-397ff5df737b"` -- hexadecimal MINÚSCULO, formato `8-4-4-4-12`,
	chaves OPCIONAIS (`wrapInCurlyBraces`, default `true` no dump). Funciona INDEPENDENTEMENTE de
	`HttpEnabled` (confirmado na doc) -- por isso `Methods.GenerateGUID` NUNCA chama
	`assertHttpEnabled`. Não força os bits de versão/variante de um UUIDv4 RFC 4122 de verdade --
	MESMA decisão, pelo MESMO motivo, já tomada e documentada por `generateProcessGuid`/
	`randomHexDigit` em `src/runtime/DataModel.luau` (`task-runtime-034`, para `game.JobId`).

	## `GetSecret` / `CreateWebStreamClient` -- SEM entrada em `Methods`, de propósito

	[Sub-leva A -- inalterado.] Sobrevivem ao filtro do gerador (`Security None`,
	`Capabilities [Network]`) mas ficam com o stub `[LuauBench] ... not simulated by LuauBench yet`
	que `ClassBuilder.Build` já instala sozinho para todo `MethodNames` sem implementação (regra
	03) -- nenhum dos dois é usado por `ProfileStore`/o caso de uso central do projeto, e
	`GetSecret` depende de Secrets do Open Cloud (fora do escopo local-first desta fase).

	Depende de: `../../runtime` (tipos + `GetPropertyRaw`/`SetPropertyRaw`), `../Types`
	(`Behavior`), `../Context` (`IsHttpAllowed`/`IsHttpLocalAllowed`; `NotifyHttpRequest`, NOVO na
	correção de auditoria coordenada com `task-cli-026`), `../AsyncCall` (ponto único de yield),
	`@lune/serde` (JSON, sub-leva A), `@lune/net` (rede real). Estado: NENHUM próprio deste módulo além da
	propriedade `HttpEnabled` (que já mora na instância, via schema) -- `HttpService` é Service
	singleton sem estado adicional.
]]

local net = require("@lune/net")
local serde = require("@lune/serde")
local Runtime = require("../../runtime")
local Types = require("../Types")
local Context = require("../Context")
local AsyncCall = require("../AsyncCall")

-- Ver cabeçalho, "GetAsync/PostAsync/RequestAsync" -- aproximação de boa-fé, string exata NÃO
-- CONFIRMADA (pesquisa-http-messaging-2026-09-05.md, "Pontos NÃO CONFIRMADOS").
local HTTP_NOT_ENABLED_MESSAGE = "Http requests are not enabled. Enable via game settings"

-- Ver cabeçalho, item 2 ("JSONEncode... referência cíclica"). Aproximação de boa-fé -- a doc
-- oficial confirma QUE erra ("a cyclical reference... will cause an error"), mas não cita a
-- string exata (pesquisa, item B.5: só o comportamento é confirmado, não o texto).
local CYCLIC_REFERENCE_MESSAGE = "Argument 1 to JSONEncode contains a table which references itself (cyclic reference)"

-- Conjunto fechado de métodos HTTP aceitos -- o MESMO conjunto que `net.HttpMethod` (Lune
-- 0.10.5, `~/.lune/.typedefs/0.10.5/net.luau`) e a doc oficial de `RequestAsync` documentam,
-- não uma lista inventada por este módulo.
local VALID_HTTP_METHODS: { [string]: boolean } = {
	GET = true,
	POST = true,
	PUT = true,
	DELETE = true,
	HEAD = true,
	OPTIONS = true,
	PATCH = true,
}

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
-- a codificação de verdade. [Sub-leva A -- inalterado.]
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
-- [Sub-leva A -- inalterado.]
-- ================================================================================================

local function percentEncodeByte(char: string): string
	return string.format("%%%02X", string.byte(char) :: number)
end

-- ================================================================================================
-- GenerateGUID -- ver cabeçalho: formato confirmado, não é RFC 4122 exato de propósito.
-- [Sub-leva A -- inalterado.]
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

-- ================================================================================================
-- Rede real (task-services-026) -- validação de argumento, endurecimento de destino e a chamada
-- de fato a `net.request`. Ver cabeçalho para o raciocínio completo de cada peça.
-- ================================================================================================

--[[
	CORREÇÃO DE SSRF (achado GRAVE #1, 3ª rodada de revisão -- reproduzido e confirmado ANTES
	deste fix, script descartável): a stack de rede real por trás de `net.request` (WHATWG URL
	Standard, que toda lib de URL para esquema "especial" -- http/https/ws/wss/file -- herda) trata
	"\" como equivalente a "/" em QUALQUER posição da URL durante o parsing -- não só na parte de
	path. Uma URL como `"http://127.0.0.1:PORT\@evil-marker.invalid/"` faz o parser real enxergar
	`"http://127.0.0.1:PORT/@evil-marker.invalid/"` (a barra invertida vira barra ANTES do "@" ser
	interpretado como delimitador de userinfo) -- a conexão de fato vai para `127.0.0.1:PORT`, mas
	QUALQUER extração de host que não faça esta MESMA normalização primeiro lê "evil-marker.invalid"
	(host público, não bloqueado) em vez do host real. Confirmado rodando: `net.request` COMPLETOU
	contra um servidor local respondendo em `127.0.0.1:PORT` usando exatamente essa URL, enquanto
	`extractHost` (sem normalizar) extraía "evil-marker.invalid".

	A correção NÃO fica dentro de `extractHost` -- fica em `normalizeUrlForParsing`, chamada UMA
	VEZ dentro de `assertValidUrl` (abaixo), ANTES de qualquer outra checagem. A URL NORMALIZADA (já
	sem nenhum "\") é o valor que flui para TODO o resto do pipeline (`extractHost`,
	`assertDestinationAllowed`, `auditOutgoingRequest`, e o próprio `net.request` via
	`performNetRequest`) -- a invariante que importa é que o host que ESTE módulo valida/audita e o
	host que a rede REAL usa sejam garantidamente o MESMO, nunca "mais um padrão de bypass coberto".

	SEGUNDA NORMALIZAÇÃO (achado do "4º bypass" pedido nesta rodada -- caça ATIVA, não esperar o
	revisor achar de novo): o WHATWG URL Standard também remove TODO byte ASCII tab (0x09) ou
	newline (0x0A LF / 0x0D CR) da URL inteira, em QUALQUER posição, como um dos primeiros passos do
	parsing -- não só nas pontas. Confirmado RODANDO contra `net.request` puro (script descartável,
	canário `net.serve` local): `http://12\t7.0.0.1:PORT/`, `http://12\n7.0.0.1:PORT/` e
	`http://12\r7.0.0.1:PORT/` CONECTAM de verdade no canário em `127.0.0.1:PORT` -- ou seja, a
	stack de rede real faz essa remoção, exatamente como o standard descreve. Sem replicar isto
	aqui, um host escrito como "12\t7.0.0.1" chega ileso em `extractHost`, falha o parse de
	`tryParseIPv4` (o tab quebra o componente numérico), e é tratado como hostname comum -- deixando
	passar um destino privado disfarçado. `string.gsub` removendo os 3 bytes fecha essa classe
	inteira de uma vez (não é "mais um caractere na lista", é a MESMA transformação que a rede real
	aplica).
]]
local function normalizeUrlForParsing(url: string): string
	local withoutBackslashes = (string.gsub(url, "\\", "/"))
	local withoutTabsAndNewlines = (string.gsub(withoutBackslashes, "[\t\n\r]", ""))
	return withoutTabsAndNewlines
end

--[[
	TERCEIRA NORMALIZAÇÃO (mesma caça ao "4º bypass"): o host parser do WHATWG URL Standard faz
	percent-decode do HOST (não da URL inteira -- só do token de host, depois que "@"/":"/"/" já
	separaram autoridade de userinfo/porta/path pelos bytes LITERAIS) ANTES de checar se ele "parece
	um número" (IPv4) ou rodar IDNA. Confirmado RODANDO contra `net.request` puro (mesmo canário):
	`http://%31%32%37%2e%30%2e%30%2e%31:PORT/` (== "127.0.0.1" byte a byte, todo percent-encoded) E
	`http://127%2e0%2e0%2e1:PORT/` (só os pontos) CONECTAM de verdade no canário -- a stack de rede
	real decodifica o host antes de resolver/conectar. `extractHost`, sem isto, devolvia o literal
	"%31%32%37..."/"127%2e0%2e0%2e1" (string com "%"), que `tryParseIPv4` rejeita (não são dígitos
	puros) -- tratado como hostname comum, destino privado disfarçado passa direto.

	Decodificar SÓ o token de host (nunca a URL inteira) é deliberado: os delimitadores estruturais
	("@" separando userinfo de host, ":" separando host de porta, "/" iniciando o path) são bytes
	LITERAIS na URL -- um "%40"/"%3a"/"%2f" dentro de um componente NÃO deveria virar um delimitador
	nesta função (a mesma ordem que o WHATWG usa: primeiro segmenta pelos bytes literais, DEPOIS
	decodifica o host isolado) -- decodificar a URL inteira antes de segmentar inverteria essa ordem
	e criaria uma classe de bug DIFERENTE (um "%2f" em vez de host virando delimitador de path).
]]
local function percentDecodeHost(host: string): string
	local decoded = string.gsub(host, "%%(%x%x)", function(hex: string): string
		return string.char(tonumber(hex, 16) :: number)
	end)
	return decoded
end

--[[
	4ª RODADA DE REVISÃO (task-services-026) -- MUDANÇA ESTRUTURAL: de "mais um delimitador na
	lista" para "a GRAMÁTICA COMPLETA da RFC 3986, em 3 passos, cada um operando só na fatia que o
	passo anterior já isolou". As 3 rodadas anteriores corrigiram bypass por bypass (backslash,
	IPv4-compatible IPv6, percent-encoding, tab/LF/CR) -- cada uma fechando a forma ESPECÍFICA
	reportada, nunca a CLASSE do bug. O padrão só parou quando o revisor achou mais uma variação
	que a versão anterior desta função não cobria: `"http://127.0.0.1:PORT?x@evil-marker.invalid/"`
	-- a extração antiga (`beforeSlash = string.match(afterScheme, "^([^/]*)")`) só cortava pela
	primeira "/", NUNCA por "?"/"#" -- então o "@" dentro da QUERY (que já devia estar fora da
	região de autoridade) ainda era achado pelo `"@([^@]*)$")` e lido como delimitador de host.
	Confirmado rodando ANTES deste fix (script descartável, canário `net.serve` local): a conexão
	REAL vai para "127.0.0.1:PORT" (a query "?x@evil-marker.invalid/" nunca é host de verdade),
	mas a extração antiga devolvia "evil-marker.invalid" -- host ERRADO auditado/checado.

	A correção NÃO é "também corte por ?/#" plantado no meio da lógica antiga -- é reescrever a
	função inteira seguindo, EM ORDEM, a gramática RFC 3986 (§3, §3.2):

		URI       = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
		hier-part = "//" authority path-abempty
		authority = [ userinfo "@" ] host [ ":" port ]

	Passo 1 -- isola `authority`: o PRIMEIRO de "/", "?", "#" (ou fim da string, se nenhum
	aparecer) termina a região de autoridade -- NUNCA um "@" sozinho. Tudo a partir desse ponto é
	path/query/fragment e NUNCA pode voltar a influenciar host, mesmo que contenha um "@" mais à
	frente (é exatamente essa garantia que fecha o bypass desta rodada).

	Passo 2 -- separa userinfo de host DENTRO da `authority` já isolada pelo passo 1 (nunca antes,
	nunca na URL inteira): o ÚLTIMO "@" dentro dela é quem separa `userinfo` de `host[:port]" --
	mesma técnica (`"@([^@]*)$"`) das 3 rodadas anteriores, só que agora aplicada à FATIA CORRETA
	(a `authority`, não a URL inteira até a primeira "/"), o que sozinho já fecha a classe inteira
	de "delimitador de authority (`?`/`#`) sendo ignorado por um `@` mais à frente".

	Passo 3 -- dentro do `host[:port]` resultante, separa porta (IPv6 entre colchetes é um caso
	especial: a porta, se houver, vem depois de "]:"). Idêntico às rodadas anteriores.

	Cada passo consome só a fatia que o passo anterior devolveu -- nunca um regex solto tentando
	casar host/porta/userinfo de uma vez contra a URL inteira (a causa raiz do padrão "mais um
	bypass a cada rodada": um regex solto não tem como saber que já passou de um delimitador de
	nível mais alto).

	CAÇA ATIVA contra a PRÓPRIA gramática nova (pedida explicitamente nesta rodada, ver relatório
	da tarefa para o script descartável usado): authority vazia (`"http:///etc"` -- authority ==
	"" pelo passo 1, `net.request` real REJEITA com "bad argument #1: invalid format" antes de
	qualquer tentativa de conexão, confirmado rodando); múltiplos "@" dentro da authority já
	isolada (`"http://evil-marker.invalid@127.0.0.1:PORT/x"` -- confirmado rodando que TANTO esta
	função quanto a conexão REAL concordam no host "127.0.0.1", o ÚLTIMO "@" venceu dos dois
	lados); host vazio depois do último "@" (`"http://user@/x"` -- devolve `nil` aqui, e
	`net.request` real REJEITA com "bad argument #1: invalid authority" antes de conectar,
	confirmado rodando); porta com caracteres não numéricos (`"http://127.0.0.1:abc/x"` -- esta
	função extrai "127.0.0.1" corretamente de qualquer forma -- porta inválida nunca muda o host
	que ela devolve --, e `net.request` real REJEITA com "invalid port number" antes de conectar,
	confirmado rodando). NENHUM dos 4 casos revelou bypass novo -- todos ou (a) esta função já
	concorda com o host real, ou (b) `net.request` recusa a URL inteira antes de qualquer conexão
	acontecer -- registrado aqui e no relatório da tarefa, não virou fix novo por não haver nada
	para corrigir.

	## 5ª RODADA DE REVISÃO (`revisor-services-http-ssrf-round4-2026-09-06.md`) -- Unicode/IDNA no
	## HOST, e DECISÃO EXPLÍCITA do usuário: esta é a ÚLTIMA rodada de correção ativa de SSRF desta
	## tarefa (task-services-026)

	Achado desta rodada (GRAVE, reportado pelo revisor -- reproduzido e confirmado ANTES do fix,
	três formas independentes, com canário `net.serve` real em loopback): `extractHost`/
	`tryParseIPv4`/`splitByDot` (acima) operam em bytes ASCII crus (`.` literal, `%d` do Lua) -- a
	stack de rede real (WHATWG URL Standard, processamento IDNA/UTS46 "domain to ASCII") normaliza
	separadores de label Unicode equivalentes ao ponto e dígitos "fullwidth" para seus
	equivalentes ASCII ANTES de resolver/conectar. `"http://127．0．0．1/"` (fullwidth full stop
	U+FF0E), `"http://127。0。0。1/"` (ideographic full stop U+3002) e `"http://１２７.0.0.１/"`
	(dígitos fullwidth U+FF10-FF19) conectavam de verdade em `127.0.0.1` mesmo com
	`AllowHttp=true, AllowHttpLocal=false` (a postura default/segura) -- a MESMA classe de bug das
	4 rodadas anteriores (host auditado/checado divergindo do host real usado pela conexão), desta
	vez na camada de NORMALIZAÇÃO DE CARACTERE dentro do label do host, não na de delimitadores
	estruturais.

	Fix: `normalizeUnicodeHostLabels` (comentário completo junto à função, perto de
	`isLocalDestination`, abaixo) mapeia os 4 separadores de ponto (".", "．", "。", "｡") para "."
	ASCII e os 10 dígitos fullwidth ("０"-"９") para "0"-"9", rodando SEMPRE antes de
	`tryParseIPv4`/comparação com "localhost" -- único ponto de chamada, dentro de
	`isLocalDestination`. O host ORIGINAL (com os caracteres Unicode, não normalizado) continua
	fluindo, sem alteração, para a mensagem de erro de `assertDestinationAllowed` e para o canal
	de auditoria (`auditOutgoingRequest`) -- só a DECISÃO de bloqueio usa o host normalizado.

	NÃO é NFKC/IDNA completo -- mapeia especificamente só os 4 caracteres de separador e os 10
	dígitos fullwidth, os ÚNICOS casos CONFIRMADOS explorável contra `net.request`/Lune 0.10.5
	real pelo revisor nesta rodada (ver docblock de `normalizeUnicodeHostLabels` para o porquê de
	não generalizar para NFKC completo).

	DECISÃO EXPLÍCITA DO USUÁRIO (2026-09-06): depois de 4 rodadas REPROVADAS seguidas, esta é a
	ÚLTIMA rodada de correção ativa de SSRF de `task-services-026` -- os riscos abaixo ("RISCOS
	RESIDUAIS ACEITOS") ficam formalmente aceitos para esta fase do projeto, não pendências a
	resolver numa rodada futura de graça -- reabri-los exige decisão nova e explícita do usuário
	(ex.: um pedido de reescrever `HttpService` sobre `net.tcp.connect`), não um achado de revisão
	de rotina.

	## RISCOS RESIDUAIS ACEITOS (decisão explícita do usuário, 2026-09-06 -- NÃO são pendências
	## silenciosas, regra 00: são riscos conhecidos e aceitos DELIBERADAMENTE para esta fase)

	1. **DNS rebinding.** Este módulo valida só o HOST LITERAL da URL (ver "LIMITAÇÃO DECLARADA",
	   acima) -- um hostname comum que RESOLVE para IP privado (servidor DNS malicioso muda a
	   resposta entre a validação textual e a conexão real, ou um domínio interno da rede do
	   desenvolvedor) não é bloqueado por este mecanismo. Pesquisado A FUNDO
	   (`.claude/agents-memory/pesquisa-lune-dns-resolution-2026-09-06.md`, lendo o código-fonte
	   Rust real de `@lune/net` na tag `v0.10.5`): `@lune/net` NÃO expõe nenhuma função de
	   resolução de DNS separada de `net.request` (API completa de `net` confirmada exaustivamente
	   contra `types.d.luau`, sem `resolve`/`lookup`/`getaddrinfo`), e `net.request` SEMPRE
	   sobrescreve o header `Host` com o host da própria URL usada para conectar
	   (`HeaderMap::insert` em `send.rs`, código-fonte lido) -- não dá para "conectar por IP já
	   validado, falando o hostname original" por essa via (quebraria vhost/roteamento por nome no
	   destino, e quebraria SNI/validação de certificado TLS). A ÚNICA API do Lune que combina
	   "resolver e conectar como uma coisa só" com "eu vejo o IP resolvido" é `net.tcp.connect`
	   (primitiva TCP crua) -- mas ela não fala HTTP sozinha: fechar esta classe de bug de verdade
	   exigiria reescrever `HttpService` inteiro sobre `net.tcp.connect` (resolver+conectar+
	   inspecionar `remoteIp` como operação atômica, então falar HTTP/1.1 à mão), perdendo toda a
	   camada que `net.request`/Hyper dá de graça hoje (redirects, decompressão, parsing de
	   resposta) -- escopo de arquitetura considerável (reabriria `arquiteto-services-2026-09-05.
	   md`, seção L2.2), que o usuário decidiu EXPLICITAMENTE não fazer nesta leva. Risco ACEITO:
	   um script rodando com `--allow-http` (sem `--allow-http-local`) pode, em tese, ser vítima de
	   um servidor DNS malicioso que resolve um hostname comum para um IP privado só DEPOIS da
	   validação textual ocorrer -- mitigação completa fica para uma tarefa futura dedicada, se o
	   usuário decidir reabrir o escopo.

	2. **Unicode/IDNA além dos 4 caracteres cobertos.** `normalizeUnicodeHostLabels` (abaixo)
	   mapeia só os 4 separadores de label equivalentes ao ponto e os 10 dígitos fullwidth -- os
	   casos CONFIRMADOS explorável nesta rodada. NÃO cobertos, deliberadamente: bidi override
	   (caracteres de controle de direção Unicode que podem fazer um host parecer outro
	   visualmente), homoglifos (ex.: "а" cirílico visualmente idêntico a "a" latino, ou um
	   "localhost" inteiro escrito com letras Unicode de largura total tipo "ｌｏｃａｌｈｏｓｔ" --
	   levantado pelo revisor como mesma causa raiz, não confirmado empiricamente contra
	   `net.request` real), e qualquer outra tabela de mapeamento IDNA/UTS46 (letras acentuadas,
	   ligaduras, "ß"->"ss", etc.) que uma normalização NFKC completa cobriria. Mitigação DIRIGIDA
	   aos casos confirmados nesta rodada, não uma garantia geral contra toda normalização Unicode
	   possível.

	3. Nenhum outro vetor CONCRETO (confirmado ou levantado com causa raiz identificável) além dos
	   dois acima foi identificado nesta rodada -- não se especula hipotético vago aqui (regra 00:
	   divergência declarada, não invenção de risco).

	Extrai só o HOST (sem userinfo, sem porta, sem colchetes de IPv6, sem path/query/fragment, JÁ
	percent-decodificado -- ver `percentDecodeHost`, acima) de uma URL "http(s)://..." JÁ
	NORMALIZADA (ver `normalizeUrlForParsing`, acima -- todo chamador desta função passa a URL que
	`assertValidUrl` devolveu, nunca a crua do script). Devolve `nil` se a URL não tiver o formato
	mínimo esperado -- não é responsabilidade desta função validar a URL por completo (isso é
	`assertValidUrl`, chamada ANTES desta em todo caminho de código); esta função só alimenta a
	checagem de destino privado/loopback, logo abaixo, e o canal de auditoria. Uma URL cujo host não
	dá para extrair (ex.: `"https://"`, `"http:///etc"`, `"http://user@/x"`) segue sem checagem de
	destino -- `net.request`, mais adiante, é quem vai rejeitar essa URL de verdade (confirmado
	rodando, ver caça acima -- nenhuma delas alcança conexão real sem host).
]]
local function extractHost(url: string): string?
	local afterScheme = string.match(url, "^[Hh][Tt][Tt][Pp][Ss]?://(.+)$")
	if afterScheme == nil then
		return nil
	end

	-- PASSO 1 (RFC 3986, hier-part): a região de `authority` termina no PRIMEIRO de "/", "?", "#"
	-- -- ou vai até o fim da string, se nenhum dos três aparecer. Tudo a partir desse ponto é
	-- path/query/fragment; NADA depois dele participa dos passos 2/3, mesmo que contenha um "@"
	-- mais à frente (é essa garantia, sozinha, que fecha o bypass desta rodada -- ver cabeçalho
	-- desta função). A busca acontece sobre os bytes LITERAIS (nunca decodificados) -- ver
	-- `percentDecodeHost`, abaixo, para o porquê de a decodificação só acontecer depois.
	local delimiterStart = string.find(afterScheme, "[/?#]")
	local authority = if delimiterStart then string.sub(afterScheme, 1, delimiterStart - 1) else afterScheme
	if authority == "" then
		return nil
	end

	-- PASSO 2 (RFC 3986, authority = [ userinfo "@" ] host [ ":" port ]): DENTRO da `authority` JÁ
	-- ISOLADA pelo passo 1 (nunca antes) -- o ÚLTIMO "@" separa `userinfo` de `host[:port]`.
	-- Múltiplos "@" dentro da authority (raro, mas sintaticamente válido) ainda usam o ÚLTIMO como
	-- delimitador real -- mesma regra que a stack de rede real aplica (confirmado na caça acima).
	local hostPort = string.match(authority, "@([^@]*)$") or authority
	if hostPort == "" then
		return nil
	end

	-- PASSO 3: separa porta de host. IPv6 literal entre colchetes ("[::1]:8080") -- o host É o
	-- conteúdo entre colchetes, a porta (se houver) vem depois de "]:".
	local ipv6 = string.match(hostPort, "^%[(.-)%]")
	if ipv6 then
		return percentDecodeHost(ipv6)
	end

	-- Caso geral: corta a porta, se houver ("example.com:8080" -> "example.com"). Uma porta com
	-- caracteres não numéricos não muda o HOST que esta função devolve (a validação de porta é
	-- responsabilidade de `net.request`, que rejeita a URL inteira antes de conectar -- confirmado
	-- na caça acima) -- esta função só precisa concordar com QUAL seria o host, nunca validar a
	-- porta.
	local host = string.match(hostPort, "^([^:]+)")
	if host == nil or host == "" then
		return nil
	end
	return percentDecodeHost(host)
end

-- ================================================================================================
-- CORREÇÃO DE SSRF (revisor-services reprovou a versão anterior desta checagem -- a versão antiga
-- só reconhecia IPv4 na grafia canônica "#.#.#.#" e IPv6 loopback só nas grafias literais
-- "::1"/"0:0:0:0:0:0:0:1" -- QUALQUER outra representação textual válida do MESMO endereço
-- (decimal, octal, hexadecimal, forma abreviada, IPv4-mapped IPv6) passava direto pelo filtro,
-- alcançando `127.0.0.1`/rede local mesmo SEM `--allow-http-local`). As funções abaixo NORMALIZAM
-- o host para os 4 octetos canônicos ANTES de comparar contra os ranges privados -- escolhida em
-- vez da alternativa mais simples (recusar host puramente numérico fora do padrão "#.#.#.#" como
-- formato não suportado) porque o acceptance desta correção exige que essas formas sejam
-- RECUSADAS sem `AllowHttpLocal` e ACEITAS com ela -- tratadas como qualquer outro destino
-- privado, nunca como uma categoria de erro à parte.
-- ================================================================================================

-- Os 4 octetos de um endereço IPv4 já resolvidos para a forma canônica -- resultado comum de
-- QUALQUER notação reconhecida abaixo (decimal, octal, hex, abreviada, ou extraída de dentro de
-- um IPv4-mapped IPv6).
type IPv4Octets = { o1: number, o2: number, o3: number, o4: number }

-- Interpreta UM componente separado por "." (ou o host inteiro, na forma de inteiro único) do
-- mesmo jeito que `inet_aton`/navegadores/curl interpretam: prefixo "0x"/"0X" -> hexadecimal;
-- prefixo "0" seguido de mais dígitos -> octal; caso contrário -> decimal. Devolve `nil` para
-- qualquer coisa que não seja nenhuma dessas três formas (hostname comum, ex.: "example").
local function parseNumericComponent(part: string): number?
	if part == "" then
		return nil
	end
	local hex = string.match(part, "^0[xX](%x+)$")
	if hex ~= nil then
		return tonumber(hex, 16)
	end
	if string.match(part, "^0[0-7]+$") ~= nil then
		return tonumber(part, 8)
	end
	if string.match(part, "^%d+$") ~= nil then
		return tonumber(part, 10)
	end
	return nil
end

-- Separa por "." sem exigir formato -- só isola os componentes candidatos a numéricos; um
-- componente que não for numérico faz `tryParseIPv4` (abaixo) devolver `nil` de qualquer forma
-- (host tratado como hostname comum).
local function splitByDot(host: string): { string }
	local parts: { string } = {}
	for part in string.gmatch(host, "[^.]+") do
		table.insert(parts, part)
	end
	return parts
end

-- Divide um inteiro de 32 bits nos 4 octetos, mais significativo primeiro -- todos os divisores
-- são potências de 2, então a divisão de ponto flutuante é EXATA (sem erro de arredondamento) para
-- qualquer inteiro que caiba em 32 bits.
local function octetsFrom32Bit(value: number): IPv4Octets
	return {
		o1 = math.floor(value / 0x1000000) % 256,
		o2 = math.floor(value / 0x10000) % 256,
		o3 = math.floor(value / 0x100) % 256,
		o4 = value % 256,
	}
end

--[[
	Reconhece um host como IPv4 em QUALQUER notação que `inet_aton` aceita -- não só "#.#.#.#":

	- 4 componentes ("a.b.c.d"): cada um É um octeto (decimal/octal/hex, precisa caber em 0-255).
	- 3 componentes ("a.b.c"): os dois primeiros são octetos, o terceiro cobre os últimos 16 bits.
	- 2 componentes ("a.b"): o primeiro é o octeto mais significativo, o segundo cobre os últimos
	  24 bits (ex.: "127.1" -> 127.0.0.1 -- a forma abreviada do bypass reportado).
	- 1 componente (inteiro único, decimal/octal/hex): cobre o endereço de 32 bits inteiro (ex.:
	  "2130706433"/"017700000001"/"0x7f000001" -> 127.0.0.1 -- as três formas do bypass
	  reportado).

	Devolve `nil` quando o host não é IPv4 em NENHUMA dessas formas (hostname comum, ex.:
	"example.com" -- falha porque "example"/"com" não são numéricos) ou quando tem mais de 4
	componentes (não é uma forma reconhecida por nenhum parser real).
]]
local function tryParseIPv4(host: string): IPv4Octets?
	local parts = splitByDot(host)
	if #parts == 0 or #parts > 4 then
		return nil
	end

	local numbers: { number } = {}
	for _, part in parts do
		local value = parseNumericComponent(part)
		if value == nil then
			return nil
		end
		table.insert(numbers, value)
	end

	if #numbers == 4 then
		for _, octet in numbers do
			if octet < 0 or octet > 255 then
				return nil
			end
		end
		return { o1 = numbers[1], o2 = numbers[2], o3 = numbers[3], o4 = numbers[4] }
	elseif #numbers == 3 then
		if numbers[1] < 0 or numbers[1] > 255 or numbers[2] < 0 or numbers[2] > 255 then
			return nil
		end
		local last = numbers[3]
		if last < 0 or last > 0xFFFF then
			return nil
		end
		return { o1 = numbers[1], o2 = numbers[2], o3 = math.floor(last / 256) % 256, o4 = last % 256 }
	elseif #numbers == 2 then
		if numbers[1] < 0 or numbers[1] > 255 then
			return nil
		end
		local rest = numbers[2]
		if rest < 0 or rest > 0xFFFFFF then
			return nil
		end
		return {
			o1 = numbers[1],
			o2 = math.floor(rest / 0x10000) % 256,
			o3 = math.floor(rest / 0x100) % 256,
			o4 = rest % 256,
		}
	else
		local value = numbers[1]
		if value < 0 or value > 0xFFFFFFFF then
			return nil
		end
		return octetsFrom32Bit(value)
	end
end

-- 127.0.0.0/8, 169.254.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, e "0.0.0.0" -- ver
-- cabeçalho, "ENDURECIMENTO deliberado"/"CORREÇÃO DE SSRF". Núcleo puro sobre os 4 octetos JÁ
-- resolvidos -- reaproveitado tanto por `isIPv4Private` (host textual) quanto pelo IPv4 embutido
-- em IPv6 (octetos já extraídos de dentro de outra notação, ver `extractEmbeddedIPv4Octets`
-- abaixo).
local function isIPv4PrivateOctets(octets: IPv4Octets): boolean
	local o1, o2 = octets.o1, octets.o2
	if o1 == 127 then
		return true -- 127.0.0.0/8 (loopback)
	end
	if o1 == 169 and o2 == 254 then
		return true -- 169.254.0.0/16 (link-local)
	end
	if o1 == 10 then
		return true -- 10.0.0.0/8 (privado)
	end
	if o1 == 172 and o2 >= 16 and o2 <= 31 then
		return true -- 172.16.0.0/12 (privado)
	end
	if o1 == 192 and o2 == 168 then
		return true -- 192.168.0.0/16 (privado)
	end
	if o1 == 0 and o2 == 0 and octets.o3 == 0 and octets.o4 == 0 then
		-- "0.0.0.0" -- DECISÃO EXPLÍCITA (ver cabeçalho, "CORREÇÃO DE SSRF"): conectar em
		-- 0.0.0.0 é comportamento dependente do SO (em vários Linux resolve para loopback) --
		-- recusar por padrão é o lado seguro, mesmo sem confirmar o comportamento em toda
		-- plataforma.
		return true
	end
	return false
end

-- Um host que não bate NENHUMA notação IPv4 reconhecida por `tryParseIPv4` nunca é tratado como
-- IPv4 (segue como hostname comum, sem falso-positivo).
local function isIPv4Private(host: string): boolean
	local octets = tryParseIPv4(host)
	if octets == nil then
		return false
	end
	return isIPv4PrivateOctets(octets)
end

--[[
	"::1" (forma curta) ou "0:0:0:0:0:0:0:1" (forma expandida) -- as duas representações literais
	do loopback IPv6 que um script poderia escrever à mão; NÃO faz normalização geral de IPv6
	(compressão "::" em posições arbitrárias) -- fora do escopo da lista literal do desenho.

	Achado BAIXO (3ª rodada de revisão, mesma leva do achado GRAVE #1/#2): um zone ID IPv6
	("::1%eth0", RFC 4007 -- identifica a interface de rede local para um endereço link-local) NÃO
	era removido antes da comparação, então "::1%eth0" ~= "::1" e passava direto. HOJE isto não é
	explorável (`net.request` do Lune 0.10.5 rejeita a sintaxe "%zona" numa URL antes de tentar
	conectar, confirmado -- ver relatório da tarefa) -- corrigido mesmo assim por estar mexendo
	nesta área e o custo de normalizar ser desprezível. `%` é o delimitador (RFC 4007 usa "%25"
	percent-encoded dentro de uma URI, mas um script também pode escrever o "%" cru) -- corta tudo
	a partir do primeiro "%", se houver.
]]
local function isIPv6Loopback(loweredHost: string): boolean
	local withoutZone = string.match(loweredHost, "^([^%%]*)") or loweredHost
	return withoutZone == "::1" or withoutZone == "0:0:0:0:0:0:0:1"
end

--[[
	IPv4-mapped IPv6 (`::ffff:a.b.c.d`), forma COMPRIMIDA: "::ffff:" seguido do endereço IPv4
	embutido, na notação dotted-quad OU em dois grupos hexadecimais de 16 bits (ex.:
	"::ffff:7f00:1" -- os 32 bits de "127.0.0.1" escritos como dois grupos hex, "7f00" e "1"). O
	`loweredHost` chega aqui já em minúsculas (ver `extractEmbeddedIPv4Octets`, mais abaixo).
]]
local function ipv4MappedFromCompressed(loweredHost: string): IPv4Octets?
	local tail = string.match(loweredHost, "^::ffff:(.+)$")
	if tail == nil then
		return nil
	end
	if string.find(tail, ":", 1, true) == nil then
		-- "::ffff:127.0.0.1" -- sem mais ":", a cauda inteira é o dotted-quad.
		return tryParseIPv4(tail)
	end
	local hiRaw, loRaw = string.match(tail, "^(%x+):(%x+)$")
	if hiRaw == nil or loRaw == nil then
		return nil
	end
	local hi, lo = tonumber(hiRaw, 16), tonumber(loRaw, 16)
	if hi == nil or lo == nil or hi < 0 or hi > 0xFFFF or lo < 0 or lo > 0xFFFF then
		return nil
	end
	return octetsFrom32Bit(hi * 0x10000 + lo)
end

--[[
	IPv4-mapped IPv6, forma EXPANDIDA (sem "::"): "x:x:x:x:x:ffff:d.d.d.d" (RFC 4291 §2.5.5.2,
	notação mista) ou "x:x:x:x:x:ffff:XXXX:YYYY" (mesmos 32 bits em dois grupos hex) -- os 5
	primeiros grupos precisam ser exatamente zero e o 6º precisa ser "ffff" para valer como
	IPv4-mapped; qualquer outra coisa (IPv6 comum, não relacionado a IPv4) devolve `nil` e segue
	sem checagem de destino privado (mesma limitação já declarada no cabeçalho: este módulo não
	cobre `fe80::/10`/`fc00::/7`).
]]
local function ipv4MappedFromExpanded(loweredHost: string): IPv4Octets?
	if string.find(loweredHost, "::", 1, true) ~= nil then
		return nil -- forma comprimida -- tratada por `ipv4MappedFromCompressed`, acima
	end

	local groups: { string } = {}
	for group in string.gmatch(loweredHost, "[^:]+") do
		table.insert(groups, group)
	end
	if #groups ~= 7 and #groups ~= 8 then
		return nil
	end
	for i = 1, 5 do
		if string.match(groups[i], "^0+$") == nil then
			return nil
		end
	end
	if groups[6] ~= "ffff" then
		return nil
	end

	if #groups == 7 then
		if string.find(groups[7], ".", 1, true) == nil then
			return nil -- 7 grupos sem dotted-quad -- não é uma forma IPv4-mapped reconhecida
		end
		return tryParseIPv4(groups[7])
	end

	local hi, lo = tonumber(groups[7], 16), tonumber(groups[8], 16)
	if hi == nil or lo == nil or hi < 0 or hi > 0xFFFF or lo < 0 or lo > 0xFFFF then
		return nil
	end
	return octetsFrom32Bit(hi * 0x10000 + lo)
end

--[[
	CORREÇÃO DE SSRF (achado GRAVE #2, 3ª rodada de revisão -- reproduzido e confirmado ANTES
	deste fix, script descartável): IPv4-COMPATIBLE IPv6 (RFC 4291 §2.5.5.1, sintaxe LEGADA --
	"::a.b.c.d", SEM o grupo "ffff:" que a forma IPv4-MAPPED tem). `extractIPv4MappedOctets`
	(acima, antes desta correção) só reconhecia a forma mapped ("::ffff:a.b.c.d") -- a forma
	compatible ("::127.0.0.1", "::10.0.0.1") passava direto pelo filtro. Confirmado rodando:
	`net.request` tenta abrir socket de verdade para "[::10.0.0.1]" (erro de REDE genuíno -- "os
	error 10051", rede inalcançável -- não um erro de sintaxe/parsing rejeitado antes de qualquer
	tentativa de conexão), e o GATE deste módulo deixava passar (a falha final era de rede, nunca
	"[LuauBench] refusing").

	Distingue de `ipv4MappedFromCompressed` (acima) pela AUSÊNCIA de um segundo ":" logo após "::":
	"::ffff:..." tem um grupo hex ("ffff") seguido de ":" antes do endereço embutido; a forma
	compatible vai direto de "::" para o próprio endereço, sem nenhum grupo intermediário. Só
	reconhece quando a cauda contém "." (dotted-quad) -- deliberadamente NÃO aceita um inteiro
	decimal/octal/hex "nu" depois de "::" (ex.: "::10" sozinho): isso seria confundir um endereço
	IPv6 comum de 16 bits (ex.: "::10" = "0:0:0:0:0:0:0:10", um endereço IPv6 qualquer, SEM relação
	com IPv4) com uma forma IPv4-compatible -- ao contrário da forma mapped/expandida, a sintaxe
	legada de IPv4-compatible SEMPRE usa dotted-quad (ou uma das formas abreviadas de
	`tryParseIPv4` que também usam ".", ex.: "::127.1") -- exigir "." evita esse falso-positivo
	sem abrir mão de nenhuma forma real do bypass reportado.
]]
local function ipv4CompatibleFromCompressed(loweredHost: string): IPv4Octets?
	local tail = string.match(loweredHost, "^::(.+)$")
	if tail == nil then
		return nil
	end
	if string.find(tail, ":", 1, true) ~= nil then
		return nil -- tem mais ":" -- outra forma (ex.: "::ffff:...", tratada acima), não compatible
	end
	if string.find(tail, ".", 1, true) == nil then
		return nil -- sem "." -- endereço IPv6 comum (grupo hex de 16 bits), não IPv4-compatible
	end
	return tryParseIPv4(tail)
end

-- Ponto único: tenta as três formas reconhecidas (mapped comprimida, mapped expandida, compatible
-- legada -- nesta ordem, mais comum na prática primeiro) -- `loweredHost` já normalizado para
-- minúsculas por quem chama (`isLocalDestination`, abaixo).
local function extractEmbeddedIPv4Octets(loweredHost: string): IPv4Octets?
	local fromMappedCompressed = ipv4MappedFromCompressed(loweredHost)
	if fromMappedCompressed ~= nil then
		return fromMappedCompressed
	end
	local fromMappedExpanded = ipv4MappedFromExpanded(loweredHost)
	if fromMappedExpanded ~= nil then
		return fromMappedExpanded
	end
	return ipv4CompatibleFromCompressed(loweredHost)
end

--[[
	MITIGAÇÃO DIRIGIDA DE UNICODE/IDNA (achado GRAVE, `revisor-services-http-ssrf-round4-2026-09-
	06.md` -- 5ª rodada desta MESMA tarefa, task-services-026): a stack de rede real por trás de
	`net.request` (WHATWG URL Standard -- a MESMA referência já citada acima para justificar
	`normalizeUrlForParsing`/`percentDecodeHost`) aplica processamento IDNA/UTS46 ("domain to
	ASCII") ao host de um esquema especial ANTES de resolver/conectar -- isso inclui mapear os
	QUATRO separadores de label equivalentes ao ponto ASCII ("." U+002E) -- "．" (U+FF0E, fullwidth
	full stop), "。" (U+3002, ideographic full stop) e "｡" (U+FF61, halfwidth ideographic full
	stop) -- para "." ASCII, e mapear dígitos "fullwidth" ("０"-"９", U+FF10-FF19) para seus
	equivalentes ASCII "0"-"9".

	Confirmado RODANDO pelo revisor (round4, 3 formas independentes, com canário `net.serve` real
	em loopback): `HttpService:GetAsync("http://127．0．0．1/")` (fullwidth full stop),
	`"http://127。0。0。1/"` (ideographic full stop) e `"http://１２７.0.0.１/"` (dígitos fullwidth)
	CONECTAM de verdade em `127.0.0.1` mesmo com `AllowHttp=true, AllowHttpLocal=false` (a postura
	default/segura) -- `splitByDot`/`tryParseIPv4` (acima) só reconhecem o ponto ASCII e dígitos
	ASCII, então o host "127．0．0．1" não separa em componentes reconhecidos, `tryParseIPv4`
	devolvia `nil`, e `isLocalDestination` (abaixo) devolvia `false` -- a checagem passava direto,
	`net.request` conectava no loopback de verdade.

	IMPORTANTE -- NÃO é NFKC/IDNA completo (decisão explícita do usuário, ver relatório da
	tarefa): esta função mapeia APENAS os 4 separadores de ponto e os 10 dígitos fullwidth acima
	-- os ÚNICOS casos CONFIRMADOS explorável contra `net.request`/Lune 0.10.5 real pelo revisor
	nesta rodada. Bidi override, homoglifos (ex.: caracteres cirílicos/gregos visualmente
	idênticos a letras latinas, incluindo um "localhost" inteiro escrito com letras Unicode de
	largura total), e qualquer outra tabela de normalização IDNA/UTS46 (letras acentuadas,
	ligaduras, "ß"->"ss", etc.) NÃO estão cobertos -- ver cabeçalho do arquivo, "RISCOS RESIDUAIS
	ACEITOS". Implementar NFKC genérico exigiria uma tabela de normalização Unicode completa
	(milhares de entradas, biblioteca própria dedicada) -- fora do escopo desta correção dirigida.

	Aplicada UMA VEZ, sobre o host JÁ extraído/percent-decodificado por `extractHost` (nunca sobre
	a URL inteira -- os separadores estruturais "/", "?", "#", "@", ":" continuam sendo bytes
	ASCII literais, isolados ANTES desta função rodar), e SEMPRE antes de `string.lower`/
	comparação com "localhost"/`tryParseIPv4` (ver `isLocalDestination`, abaixo -- único ponto de
	chamada). O host ORIGINAL (não normalizado por esta função) continua sendo o valor que
	`extractHost` devolve -- usado, sem alteração, pela mensagem de erro de
	`assertDestinationAllowed` e pelo canal de auditoria (`auditOutgoingRequest`) -- só a DECISÃO
	de bloqueio (`isLocalDestination`) usa o normalizado.
]]
local function normalizeUnicodeHostLabels(host: string): string
	local normalized = (string.gsub(host, "\u{FF0E}", ".")) -- "．" fullwidth full stop
	normalized = (string.gsub(normalized, "\u{3002}", ".")) -- "。" ideographic full stop
	normalized = (string.gsub(normalized, "\u{FF61}", ".")) -- "｡" halfwidth ideographic full stop
	for digit = 0, 9 do
		-- "０"-"９" (U+FF10-FF19) -> "0"-"9" ASCII.
		normalized = (string.gsub(normalized, utf8.char(0xFF10 + digit), tostring(digit)))
	end
	return normalized
end

-- Ver cabeçalho, "EXTENSÃO desta tarefa": "localhost" entra no mesmo balde do loopback IPv4/IPv6
-- por ser o alias mais comum para eles -- sem isto, todo o endurecimento de 127.0.0.0/8 seria
-- contornável escrevendo o nome em vez do número. Também reconhece IPv4 embutido em IPv6 --
-- mapped E compatible (ver `extractEmbeddedIPv4Octets`, acima) -- ver cabeçalho, "CORREÇÃO DE
-- SSRF". `normalizeUnicodeHostLabels` (acima) roda PRIMEIRO -- ver cabeçalho, "MITIGAÇÃO
-- DIRIGIDA DE UNICODE/IDNA" -- único ponto de chamada.
local function isLocalDestination(host: string): boolean
	local lowered = string.lower(normalizeUnicodeHostLabels(host))
	if lowered == "localhost" then
		return true
	end
	if isIPv6Loopback(lowered) then
		return true
	end
	local embeddedOctets = extractEmbeddedIPv4Octets(lowered)
	if embeddedOctets ~= nil then
		return isIPv4PrivateOctets(embeddedOctets)
	end
	return isIPv4Private(lowered)
end

--[[
	Nível 2 (mesma convenção de `assertHttpEnabled`, acima): culpa quem chamou esta função
	diretamente (Methods.GetAsync/PostAsync/RequestAsync). Mensagem `[LuauBench]` -- ver
	cabeçalho: esta checagem NÃO tem contraparte no Roblox real, é um endurecimento PRÓPRIO do
	LuauBench (regra de idioma dos erros: sem contraparte real -> prefixo obrigatório, em inglês,
	porque é o script do usuário quem vê este erro).
]]
local function assertDestinationAllowed(url: string): ()
	local host = extractHost(url)
	if host == nil then
		return
	end
	if isLocalDestination(host) and not Context.IsHttpLocalAllowed() then
		error(
			`[LuauBench] refusing to send an HTTP request to "{host}": loopback/link-local/private network destinations are blocked by default -- LuauBench runs on the developer's machine (unlike a real Roblox server, which cannot reach it), so this restriction is deliberately stricter than the real Roblox HttpService (see task-services-026) -- rerun luaubench with --allow-http-local to allow requests to local/private destinations`,
			2
		)
	end
end

--[[
	Canal de AUDITORIA (correção coordenada com `task-cli-026`, ver `Types.BootstrapOptions.
	OnHttpRequest`/`Context.NotifyHttpRequest`): chamado UMA VEZ por requisição de saída, sempre
	DEPOIS que `assertHttpEnabled`/`assertDestinationAllowed` já deixaram passar (uma requisição
	recusada nunca chega aqui -- nada saiu de verdade, nada para auditar) e ANTES de `net.request`
	tocar a rede de verdade. `extractHost` pode devolver `nil` para uma URL cujo host não dá para
	isolar (caso raro, já tolerado por `assertDestinationAllowed` acima) -- audita a URL inteira
	nesse caso, para nunca perder a linha de auditoria por uma URL degenerada.
]]
local function auditOutgoingRequest(method: string, url: string): ()
	Context.NotifyHttpRequest(method, extractHost(url) or url)
end

-- Nível 2 (mesma convenção). `label` descreve de onde o valor ruim veio (ex.: "argument #1 to
-- 'GetAsync'" ou "the 'Url' field of the RequestAsync options table") -- reaproveitado pelos
-- três métodos, cada um com sua própria forma de nomear o argumento (posicional vs. campo de
-- dicionário). Devolve a URL JÁ NORMALIZADA (ver `normalizeUrlForParsing`, achado GRAVE #1) -- é
-- ESSA string, nunca a `url` crua recebida, que flui para `extractHost`/`assertDestinationAllowed`/
-- `auditOutgoingRequest`/`performNetRequest` em todo caminho de código (`GetAsync`/`PostAsync`/
-- `RequestAsync`, abaixo, todos usam o valor de RETORNO desta função, nunca o argumento original).
local function assertValidUrl(url: unknown, label: string): string
	if type(url) ~= "string" then
		error(`invalid {label} (string expected, got {type(url)})`, 2)
	end
	-- Normaliza ANTES do regex de esquema: "\" em posição de "//" logo após "http:"/"https:"
	-- também é reconhecido como separador de autoridade pela stack de rede real (WHATWG URL
	-- Standard trata esquema "especial" + "\" como equivalente a "//" em qualquer posição), então
	-- a normalização precisa acontecer antes de QUALQUER parsing, não só antes da extração de host.
	local normalized = normalizeUrlForParsing(url)
	if string.match(normalized, "^[Hh][Tt][Tt][Pp][Ss]?://") == nil then
		error(`invalid {label}: only http:// and https:// URLs are supported (got "{url}")`, 2)
	end
	return normalized
end

-- Nível 2. `headers` pode ser `nil` (omitido) -- devolve `nil` nesse caso, nunca uma tabela
-- vazia (`net.request` trata os dois de forma equivalente, mas `nil` é mais fiel à intenção do
-- script de "não mandei headers nenhum").
local function assertValidHeaders(headers: unknown, label: string): net.HttpHeaderMap?
	if headers == nil then
		return nil
	end
	if type(headers) ~= "table" then
		error(`invalid {label} (table expected, got {type(headers)})`, 2)
	end

	local validated: net.HttpHeaderMap = {}
	for key, value in headers :: { [unknown]: unknown } do
		if type(key) ~= "string" then
			error(`invalid {label}: header keys must be strings (got {type(key)})`, 2)
		end
		if type(value) ~= "string" then
			error(`invalid {label}: header value for "{key}" must be a string (got {type(value)})`, 2)
		end
		validated[key] = value
	end
	return validated
end

-- Nível 2. Default "GET" quando `Method` é omitido (doc oficial de `RequestAsync`) -- só aceita
-- o conjunto fechado que TANTO a doc oficial quanto `net.HttpMethod` (Lune) reconhecem. Devolve
-- `string` puro (não `net.HttpMethod`) DE PROPÓSITO: o cast para o tipo-união literal de `net`
-- fica isolado dentro de `performNetRequest`, no único ponto que de fato monta o `FetchParams`
-- passado a `net.request` -- threadear o alias por múltiplas funções fez o `luau-lsp` colapsar
-- a união de 7 literais numa união de 7 cópias de `string` (bug de exibição/inferência
-- observado rodando `luau-lsp analyze` nesta tarefa), então o cast fica concentrado num só
-- lugar.
local function assertValidMethod(method: unknown): string
	if method == nil then
		return "GET"
	end
	if type(method) ~= "string" then
		error(`invalid 'Method' field of the RequestAsync options table (string expected, got {type(method)})`, 2)
	end
	local upper = string.upper(method)
	if not VALID_HTTP_METHODS[upper] then
		error(`invalid 'Method' field of the RequestAsync options table: unsupported HTTP method "{method}"`, 2)
	end
	return upper
end

-- Nível 2. Doc oficial (pesquisa, item B.1): `Body` proibido com `GET`/`HEAD`.
local function assertValidBody(body: unknown, method: string): string?
	if body == nil then
		return nil
	end
	if type(body) ~= "string" then
		error(`invalid 'Body' field of the RequestAsync options table (string expected, got {type(body)})`, 2)
	end
	if method == "GET" or method == "HEAD" then
		error(`invalid RequestAsync options table: 'Body' cannot be specified when 'Method' is "{method}"`, 2)
	end
	return body
end

-- Forma que os três `Methods.*` montam para pedir uma requisição -- `method` é `string` puro
-- (ver comentário de `assertValidMethod`, acima); o cast para o tipo-união literal que
-- `net.request` exige acontece só dentro de `performNetRequest`, abaixo.
type OutgoingRequest = {
	url: string,
	method: string,
	headers: net.HttpHeaderMap?,
	body: string?,
}

--[[
	Chama `net.request` de verdade e traduz QUALQUER falha (DNS, conexão recusada, TLS, etc.)
	para uma família única -- ver cabeçalho, divergência 2: NUNCA vaza a mensagem crua do
	SO/Rust. Nível 2 (mesma convenção): chamada sempre direto do corpo de
	Methods.GetAsync/PostAsync/RequestAsync.
]]
local function performNetRequest(request: OutgoingRequest): net.FetchResponse
	local ok, responseOrError = pcall(function()
		return net.request({
			url = request.url,
			method = request.method :: net.HttpMethod,
			headers = request.headers,
			body = request.body,
		})
	end)
	if not ok then
		error(`HttpService request to "{request.url}" failed: the request could not be completed`, 2)
	end
	return responseOrError :: net.FetchResponse
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
		`Capabilities [Network]`. Atalho de `RequestAsync` que devolve só o corpo -- ver
		cabeçalho para a forma exata e as divergências (Timeout ignorado não se aplica aqui,
		`nocache` é no-op: o LuauBench não tem cache de HTTP nenhum, toda chamada é sempre uma
		requisição fresca). LANÇA em qualquer falha (rede OU status HTTP não-2xx) -- ver
		cabeçalho, "Forma EXATA de RequestAsync".
	]]
	GetAsync = function(self: Runtime.Instance, url: unknown, nocache: boolean?, headers: unknown): string
		assertHttpEnabled(self)
		if nocache ~= nil and type(nocache) ~= "boolean" then
			error(`invalid argument #2 to 'GetAsync' (boolean expected, got {type(nocache)})`, 2)
		end
		local validUrl = assertValidUrl(url, "argument #1 to 'GetAsync'")
		local validHeaders = assertValidHeaders(headers, "argument #3 to 'GetAsync'")
		assertDestinationAllowed(validUrl)
		auditOutgoingRequest("GET", validUrl)

		AsyncCall.Yield("HttpService:GetAsync")

		local response = performNetRequest({ url = validUrl, method = "GET", headers = validHeaders })
		if not response.ok then
			error(`{response.statusCode}: {response.statusMessage}`, 2)
		end
		return response.body
	end,

	--[[
		Doc oficial: `PostAsync(url, data, content_type, compress, headers): string` -- mesma
		disciplina de `GetAsync`, acima. `content_type`/`compress` aceitos e IGNORADOS -- ver
		cabeçalho, divergência 6.
	]]
	PostAsync = function(
		self: Runtime.Instance,
		url: unknown,
		data: string,
		_contentType: unknown,
		_compress: boolean?,
		headers: unknown
	): string
		assertHttpEnabled(self)
		if type(data) ~= "string" then
			error(`invalid argument #2 to 'PostAsync' (string expected, got {type(data)})`, 2)
		end
		local validUrl = assertValidUrl(url, "argument #1 to 'PostAsync'")
		local validHeaders = assertValidHeaders(headers, "argument #5 to 'PostAsync'")
		assertDestinationAllowed(validUrl)
		auditOutgoingRequest("POST", validUrl)

		AsyncCall.Yield("HttpService:PostAsync")

		local response = performNetRequest({ url = validUrl, method = "POST", headers = validHeaders, body = data })
		if not response.ok then
			error(`{response.statusCode}: {response.statusMessage}`, 2)
		end
		return response.body
	end,

	--[[
		Doc oficial: `RequestAsync(requestOptions: Dictionary): Dictionary` -- forma EXATA de
		entrada/saída confirmada na pesquisa, ver cabeçalho. NÃO lança para status HTTP de falha
		(só `Success = false`) -- só para erro de rede/IO genuíno, via `performNetRequest`.
	]]
	RequestAsync = function(self: Runtime.Instance, requestOptions: unknown): { [string]: unknown }
		assertHttpEnabled(self)
		if type(requestOptions) ~= "table" then
			error(`invalid argument #1 to 'RequestAsync' (table expected, got {type(requestOptions)})`, 2)
		end
		local options = requestOptions :: { [string]: unknown }

		local validUrl = assertValidUrl(options.Url, "'Url' field of the RequestAsync options table")
		local method = assertValidMethod(options.Method)
		local body = assertValidBody(options.Body, method)
		local validHeaders = assertValidHeaders(options.Headers, "'Headers' field of the RequestAsync options table")
		-- `Compress`/`Timeout`: aceitos e IGNORADOS -- ver cabeçalho, divergências 1 e 6. Nunca
		-- lidos abaixo de propósito (não afetam `fetchParams`).
		assertDestinationAllowed(validUrl)
		auditOutgoingRequest(method, validUrl)

		AsyncCall.Yield("HttpService:RequestAsync")

		local response = performNetRequest({ url = validUrl, method = method, headers = validHeaders, body = body })

		return {
			Success = response.ok,
			StatusCode = response.statusCode,
			StatusMessage = response.statusMessage,
			Headers = response.headers,
			Body = response.body,
		}
	end,
}

local HttpServiceBehavior: Types.Behavior = {
	Methods = Methods,

	--[[
		Ver cabeçalho, "`HttpEnabled` -- de onde vem `true` agora". Roda DEPOIS que o schema já
		foi aplicado (`Runtime.ClassRegistry.new`/`NewEngineInstance` garante essa ordem, mesma
		garantia que `RunService.luau` já documenta) -- só então `SetPropertyRaw` tem uma
		propriedade `HttpEnabled` para sobrescrever. `Context.IsHttpAllowed()` já normaliza
		`nil`/omitido para `false` (ver `Context.luau`) -- sem a flag, este `Initialize` não faz
		nada, e `HttpEnabled` fica com o `Default` `false` do schema gerado.
	]]
	Initialize = function(instance: Runtime.Instance): ()
		if Context.IsHttpAllowed() then
			Runtime.Instance.SetPropertyRaw(instance, "HttpEnabled", true)
		end
	end,
}

return HttpServiceBehavior
