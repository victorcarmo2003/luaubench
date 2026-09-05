# Pesquisa — HttpService e MessagingService (2026-09-05)

API Dump fixado: commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` de MaximumADHD/Roblox-Client-Tracker.
Cache local: `D:\UserData\Documents\GitHub\luaubench\.cache\api-dump\28360dea4b90b35dc3fe9f829baae64fb6c50e75.json` (já existia, não foi necessário baixar).

Fontes primárias usadas:
- `Full-API-Dump.json` (dump acima) — seção A.
- `Roblox/creator-docs` (repo fonte real da doc oficial, não a página renderizada — a página renderizada via WebFetch veio como stub raso): `content/en-us/reference/engine/classes/HttpService.yaml`, `.../MessagingService.yaml`, `content/en-us/cloud-services/http-service.md`, `content/en-us/cloud-services/cross-server-messaging.md` — todos em `main` no momento da consulta (2026-09-05).
- DevForum (comunidade, não Roblox oficial) — só para os pontos que a doc oficial não cobre (eco de servidor, erro exato de client-side, erro exato de roblox.com bloqueado).
- Lune `net` — `crates/lune-std-net/types.d.luau` do repo `lune-org/lune` na tag `v0.10.5` (mesma versão instalada nesta máquina) + execução real via `lune run` nesta máquina (Lune 0.10.5, `D:\UserData\Documents\GitHub\luaubench` como cwd por causa do `rokit.toml`).

---

## A) Superfície no dump

### HttpService
`Superclass: Instance`. `Tags: ["NotCreatable", "Service"]`.

| Member | MemberType | Security | Capabilities | Tags | Passa no filtro do projeto? |
|---|---|---|---|---|---|
| `HttpEnabled` | Property | Read=None, Write=LocalUserSecurity | Read:[Network] | — | Leitura sim, escrita não (Write ~= None) |
| `CreateWebStreamClient` | Function | None | [Network] | — | Sim (Network não está na lista de exclusão) |
| `CreateWebStreamClientInternal` | Function | RobloxScriptSecurity | — | — | Não |
| `GenerateGUID` | Function | None | — | — | Sim |
| `GetHttpEnabled` | Function | RobloxScriptSecurity | — | — | Não |
| `GetSecret` | Function | None | [Network] | — | Sim |
| `GetUserAgent` | Function | RobloxScriptSecurity | — | — | Não |
| `JSONDecode` | Function | None | — | [CustomLuaState] | Sim |
| `JSONEncode` | Function | None | — | [CustomLuaState] | Sim |
| `RequestInternal` | Function | RobloxScriptSecurity | — | — | Não |
| `SetHttpEnabled` | Function | RobloxScriptSecurity | — | — | Não |
| `UrlEncode` | Function | None | [Network] | — | Sim |
| `GetAsync` | Function | None | [Network] | [Yields] | Sim |
| `JSONDecodeAsync` | Function | RobloxScriptSecurity | — | [Yields] | Não |
| `JSONEncodeAsync` | Function | RobloxScriptSecurity | — | [Yields] | Não |
| `PostAsync` | Function | None | [Network] | [Yields] | Sim |
| `RequestAccessTokenScopesAsync` | Function | LocalUserSecurity | — | [Yields] | Não |
| `RequestAsync` | Function | None | [Network] | [Yields] | Sim |

Nenhum membro tem tag `Deprecated`. Não há `Events` nem `Callbacks` nesta classe no dump.

Assinaturas exatas (`Parameters`/`ReturnType` do dump):
- `GenerateGUID(wrapInCurlyBraces: bool = true): string`
- `GetAsync(url: Variant, nocache: bool = false, headers: Variant): string`
- `PostAsync(url: Variant, data: string, content_type: Enum.HttpContentType = ApplicationJson, compress: bool = false, headers: Variant): string`
- `RequestAsync(requestOptions: Dictionary): Dictionary`
- `JSONEncode(input: Variant): string`
- `JSONDecode(input: string): Variant`
- `UrlEncode(input: string): string`

Enums (seção `Enums` do dump):
- `Enum.HttpContentType`: `ApplicationJson=0, ApplicationXml=1, ApplicationUrlEncoded=2, TextPlain=3, TextXml=4`
- `Enum.HttpCompression`: `None=0, Gzip=1`
- `Enum.WebStreamClientType`: `SSE=0, RawStream=1, WebSocket=2`

### MessagingService
`Superclass: Instance`. `Tags: ["NotCreatable", "Service", "NotReplicated"]`. Só **2 membros no dump inteiro**, ambos sobrevivem ao filtro:

| Member | MemberType | Security | Capabilities | Tags |
|---|---|---|---|---|
| `PublishAsync(topic: string, message: Variant): ()` | Function | None | [ServerCommunication] | [Yields] |
| `SubscribeAsync(topic: string, callback: Function): RBXScriptConnection` | Function | None | [ServerCommunication] | [Yields] |

Sem `Properties`, sem `Events`, sem `Callbacks`. Isso confirma que o "recebimento de mensagem" **não é um evento/RBXScriptSignal simulável como `Changed`/`ChildAdded`** — é um callback Luau passado direto para `SubscribeAsync`, que devolve um `RBXScriptConnection` (só para `:Disconnect()`).

---

## B) HttpService — semântica (fonte: `HttpService.yaml` do creator-docs, texto literal)

1. **`RequestAsync` — tabela de entrada** (nomes com capitalização exata, confirmados no YAML fonte):
   `Url` (string, obrigatório, só `http`/`https`), `Method` (string, opcional), `Headers` (Dictionary, opcional), `Body` (string, opcional — proibido com `GET`/`HEAD`), `Compress` (`Enum.HttpCompression`, opcional), `Timeout` (integer, opcional, segundos, "deve ser > 0 e não maior que o timeout padrão da requisição").
   **Tabela de saída:** `Success` (bool, true sse `StatusCode` em 200-299), `StatusCode` (integer), `StatusMessage` (string), `Headers` (Dictionary), `Body` (sem tipo declarado na tabela da doc, mas é string). Confirma exatamente os nomes que você listou, mais `Timeout` que não estava na sua lista.

2. `GetAsync(url: Variant, nocache: boolean = false, headers: Variant): string` — atalho de `RequestAsync`, retorna só o body.
   `PostAsync(url: Variant, data: string, content_type: Enum.HttpContentType = ApplicationJson, compress: boolean = false, headers: Variant): string`.

3. `HttpEnabled`: Security `Read: None` / `Write: LocalUserSecurity` (só Command Bar/plugin, não script de jogo). Precisa estar `true` para experiências não publicadas via Command Bar: `game:GetService("HttpService").HttpEnabled = true`.
   **Mensagem de erro exata quando desabilitado: NÃO CONFIRMADO.** A doc oficial não cita a string literal. Threads de DevForum citam o título "HTTP requests are not enabled" mas nenhuma reproduz o texto exato entre aspas de forma confiável — os resumos de duas fontes divergiram no texto literal. Não tenho confiança para afirmar a string exata; recomendo testar em Studio real antes de hardcodar.

4. Restrições reais (fonte oficial, YAML + guia `http-service.md`):
   - **Rate limit confirmado na doc oficial**: 500 req/min para requisições externas; 2500 req/min separado para Open Cloud. Acima disso as requisições falham (raise error, não retorno silencioso).
   - **`Timeout`**: campo existe em `RequestAsync`, mas o valor do timeout padrão não é numericamente declarado na doc ("não maior que o timeout padrão da requisição" — o número não é dito).
   - **`..` (dois pontos) não é permitido em path de domínios Roblox** — afeta acesso a DataStores via Open Cloud through HttpService.
   - **Domínio `roblox.com` bloqueado**: confirmado por padrão consistente em múltiplas threads DevForum ("HttpService is not allowed to access ROBLOX resources" / variante em minúsculas) ao chamar `GetAsync` contra `inventory.roblox.com` etc. **Não é doc oficial, é comportamento relatado pela comunidade** — mas é consistente e replicado em vários threads independentes, então trato como fato de alta confiança, só não com string de erro 100% fixa.
   - Headers proibidos citados na doc oficial: `Content-Length` (calculado automaticamente), `User-Agent` e `Roblox-Id` (travados pela Roblox); outros como `Accept`/`Cache-Control` têm default mas podem ser sobrescritos.
   - Portas bloqueadas / tamanho máximo de body/resposta: **NÃO CONFIRMADO** — nem a doc oficial nem os guias citam números.

5. `JSONEncode`/`JSONDecode` (texto literal do YAML, seção `description`):
   - Encode: chaves devem ser strings OU números; se a tabela tiver os dois tipos, **array tem prioridade e as chaves string são ignoradas**. Tabela vazia `{}` vira array JSON vazio `[]`. Evitar `nil` em qualquer índice (não documentado o que acontece exatamente, só "avoid"). **Referência cíclica causa erro.** Aceita `inf`/`nan` mesmo não sendo JSON válido — pode gerar JSON inválido para outros parsers. Aceita `buffer` de até 50 MiB, convertido para base64 antes de virar JSON.
   - Decode: chaves viram string OU número; se o JSON object misturar (não deveria, JSON só tem string keys, mas se as strings parecerem números)... a doc diz "se tiver os dois, chaves string são ignoradas" (mesma regra, direção inversa do que eu disse antes verbalmente — texto exato: "Keys of the table are strings or numbers but not both. If a JSON object contains both, string keys are ignored"). JSON de entrada inválido: **lança erro** (não retorna `nil`). JSON object vazio `{}` vira tabela Luau vazia `{}`.

6. `GenerateGUID(wrapInCurlyBraces: boolean = true): string` — UUID v4, variant 1, formato `8-4-4-4-12` (36 chars sem chaves). Exemplos literais da doc: com `true` → `{94b717b2-d54f-4340-a504-bd809ef5bf5c}`; com `false` → `db454790-7563-44ed-ab4b-397ff5df737b`. Funciona independente de `HttpEnabled`.

7. `UrlEncode` — percent-encoding (RFC-style, "%" + 2 hex). Exemplo literal da doc: `https://www.roblox.com/discover#/` → `https%3A%2F%2Fwww%2Eroblox%2Ecom%2Fdiscover%23%2F` — note que até o `.` vira `%2E`, é bem mais agressivo que `encodeURIComponent` do JS. **Espaço não foi testado no exemplo oficial**, mas dado o padrão observado (`.` sendo escapado), é razoável esperar `%20` e não `+` (form-encoding usa `+`, mas essa função não é descrita como form-encoding — é usada para compor a própria URL). Trate como inferência, não confirmado por exemplo direto.

8. **Cliente/LocalScript**: a doc oficial não declara isso explicitamente na classe, mas múltiplos threads DevForum independentes convergem no erro **"Http requests can only be executed by game server"** ao chamar de LocalScript/client-side. **Fonte é comunidade, não doc oficial** — mas o padrão é consistente (raiz do problema costuma ser script rodando client-side via `require` de um LocalScript). Trate a string como aproximação plausível, não 100% garantida caractere-por-caractere.

---

## C) MessagingService — semântica (fonte: `MessagingService.yaml` + `cross-server-messaging.md` do creator-docs, texto literal)

1. `PublishAsync(topic: string, message: Variant): ()` — "yields until the message is received by the backend" (síncrono do ponto de vista do script: bloqueia a coroutine até o backend confirmar o recebimento, mas não até os assinantes processarem).
   `SubscribeAsync(topic: string, callback: (message: {Data: unknown, Sent: number}) -> ()): RBXScriptConnection` — retorna um objeto com `:Disconnect()`. "It yields until the subscription is properly registered."
   **Formato exato da tabela do callback** (nomes literais do YAML): `Data` (payload do desenvolvedor, mesmo tipo passado em `PublishAsync`) e `Sent` (**Unix time em segundos**, ou seja `number`).

2. **A PERGUNTA DECISIVA — eco local:**
   A doc oficial (YAML da classe + guia `cross-server-messaging.md`) **não menciona o comportamento de eco em nenhum lugar** — nem confirma, nem nega.
   Evidência indireta forte de dois threads DevForum independentes:
   - [Does MessagingService:SubscribeAsync fire in the same server...](https://devforum.roblox.com/t/does-messagingservicesubscribeasync-fire-in-the-same-server-that-messagingservicepublishasync-is-in/1565236) — resposta de usuário regular (não staff): "Runs on both server A and server B", sem citar teste.
   - [How to prevent...firing in the same server](https://devforum.roblox.com/t/how-to-prevent-messagingservicesubscribeasync-firing-in-the-same-server-that-messagingservicepublishasync-is-in/2156982) — relato de sintoma real (VFX/SFX disparando "aleatoriamente" no próprio servidor que publicou) e solução testada empiricamente: incluir `game.JobId` na mensagem e comparar no callback para ignorar mensagens da própria origem. O autor confirma: "I tested it and it works fine" depois de aplicar o filtro por JobId.
   **Conclusão: SIM, o servidor que publica recebe o próprio eco quando está inscrito no mesmo tópico — mas isso é confirmado por evidência empírica de comunidade (dois relatos independentes + padrão de solução consolidado no ecossistema, ex.: bibliotecas de terceiros que já embutem filtro de JobId por padrão), não por documentação oficial da Roblox.** Não achei nenhuma fonte oficial (doc, changelog, post de staff) que declare isso explicitamente. Marcar como **confirmado por evidência forte de comunidade, não por fonte primária Roblox**.

3. Síncrono/assíncrono: `PublishAsync` **yielda** (é uma chamada bloqueante da coroutine que a chama, tag `Yields` no dump e na doc) até o backend confirmar recebimento — não até os assinantes rodarem o callback. Latência entre publish e o callback disparar em outro servidor: doc diz "typically within 1-2 seconds" (texto literal do YAML da classe). Não há garantia de entrega ("Delivery is best effort and not guaranteed").

4. Limites documentados (tabela literal do YAML, "subject to change" segundo a própria doc):
   - Tamanho máximo de mensagem: **1 kB**.
   - Mensagens enviadas por servidor: `600 + 240 * (jogadores no servidor)` por minuto.
   - Mensagens recebidas por tópico: `(40 + 80 * número de servidores)` por minuto.
   - Mensagens recebidas para o jogo inteiro: `(400 + 200 * número de servidores)` por minuto.
   - Assinaturas permitidas por servidor: `20 + 8 * (jogadores no servidor)`.
   - Requisições de subscribe por servidor: **240/min**.
   - Tamanho do nome do tópico: **1–80 caracteres** (texto da doc: "Topics are developer-defined strings (1–80 characters)").

5. Tipos permitidos em `message`: dump declara `Variant`. A doc oficial não lista os tipos exatos aceitos, mas exemplos de código real (creator-docs) mostram só `string`. Busca na comunidade indica que tabelas com tipos básicos (string/number/bool) também são aceitas, desde que serializem para ≤1kB — **não encontrei uma fonte oficial que declare a lista exata de tipos suportados, nem um changelog específico de quando tabela passou a ser aceita.** Marcar como **NÃO CONFIRMADO** com precisão — trate como "provavelmente aceita string e tabelas serializáveis simples", não como certeza.

6. Cliente/LocalScript: a doc oficial cita `NotReplicated` como tag da classe e a capability `ServerCommunication` — nenhum documento afirma explicitamente "só funciona no servidor", mas a arquitetura (capability restrita + tag `NotReplicated`) e o padrão consistente de exemplos exclusivamente server-side (`ServerScriptService`) apontam fortemente para uso exclusivo de servidor. **Erro exato ao chamar do cliente: NÃO CONFIRMADO** — não achei um thread reproduzindo esse caso específico para MessagingService (os que achei sobre "client-side" eram de HttpService).

7. Em Studio sem "Enable Studio Access to API Services": **NÃO CONFIRMADO com string exata.** Um resultado de busca menciona "MessagingService: Service disconnected" como mensagem associada a esse cenário, mas não consegui abrir e confirmar a fonte primária desse texto (não é doc oficial, é um resumo de busca de segunda mão). Para DataStoreService o padrão documentado é `"<Service>: StudioAccessToApisNotAllowed: Studio access to APIs is not allowed. API: <Método>, Data Store: <nome>"` — plausível que MessagingService siga um padrão similar, mas isso é inferência por analogia, não confirmação direta para esta classe.

---

## D) Lune `net` — confirmado rodando de verdade nesta máquina

Versão instalada: **Lune 0.10.5** (`lune --version`). Fonte do tipo: `crates/lune-std-net/types.d.luau` do repo `lune-org/lune`, tag `v0.10.5` (mesma versão, buscado via `gh api`) — bate exatamente com o comportamento observado ao rodar.

- **`net.request(config: string | FetchParams): FetchResponse`**
  `FetchParams`: `url: string` (obrigatório), `method: HttpMethod?` (default `"GET"`), `body: (string | buffer)?`, `query: {[string]: string | {string}}?`, `headers: {[string]: string | {string}}?`, `options: {decompress: boolean?}?` (default `decompress = true`).
  **Não existe campo `timeout`** em `FetchParams` nem em `options` nesta versão — testei passar `options = {timeout = 1}` contra um endpoint com `/delay/2`; o campo foi silenciosamente ignorado pelo Lua (não gerou erro, não truncou a espera) porque não faz parte do schema. **Não há timeout configurável pelo usuário no Lune 0.10.5.**
  `FetchResponse`: `ok: boolean`, `statusCode: number`, `statusMessage: string`, `headers: {...}`, `body: string` — **confirmado rodando** contra `https://httpbin.org/get`: `ok=true, statusCode=200, statusMessage="OK"`, `headers` é `table`, `body` é `string`.

- **Host inexistente**: `net.request` **lança erro** (não retorna `ok=false`). Rodei contra `https://this-host-does-not-exist-abc123xyz.invalid/` e `pcall` capturou:
  ```
  No such host is known. (os error 11001)
  ```
  Isso bate com a doc do tipo: "Only throws an error if a miscellaneous network or I/O error occurs, never for unsuccessful status codes." — ou seja, erro de DNS/rede lança exceção Luau; status 4xx/5xx **não** lança, só reflete em `ok=false`/`statusCode`.

- Nenhum timeout configurável — implicação de design para o LuauBench: se `RequestAsync` simulado quiser respeitar o campo `Timeout` do Roblox real, o LuauBench precisa implementar o timeout ele mesmo por cima do `net.request` cru do Lune (ex.: correndo a chamada numa task e usando `task.delay`/cancelamento), já que o Lune não oferece isso nativamente nesta versão.

---

## Pontos NÃO CONFIRMADOS (resumo)

- String de erro exata para `HttpEnabled = false`.
- String de erro exata para chamar HttpService do client.
- String de erro exata para domínio roblox.com bloqueado (padrão sim, texto exato não).
- Portas bloqueadas e tamanho máximo de body/resposta do HttpService.
- Tipos exatos aceitos em `MessagingService:PublishAsync` além de string (tabela parece funcionar na prática, mas sem fonte oficial que declare a lista).
- Erro exato ao chamar MessagingService do client.
- Erro exato em Studio sem "Enable Studio Access to API Services" para MessagingService.
- Eco de servidor em `MessagingService` — comportamento confirmado por evidência forte de comunidade (dois relatos independentes + padrão de mitigação consolidado via JobId), mas não por fonte oficial Roblox.
